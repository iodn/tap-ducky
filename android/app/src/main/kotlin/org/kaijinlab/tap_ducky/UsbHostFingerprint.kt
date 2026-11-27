package org.kaijinlab.tap_ducky

private const val ENUMERATION_WINDOW_MS = 2500L
private const val APPLE_LED_GRACE_MS = 250L

internal data class UsbHostFingerprint(val os: String? = null, val detecting: Boolean = false)

private val traceEvent = Regex("""\s(\d+\.\d+): (usb_gadget_set_state|mtu3_handle_setup|dwc3_ctrl_req|qualcomm_setup|usb_core_setup): (.*)$""")
private val gadgetState = Regex("""^speed \S+ state ([067]) """)
private val mtu3Setup = Regex("""^setup - (\p{XDigit}{2}) (\p{XDigit}{2}) (\p{XDigit}{4}) (\p{XDigit}{4}) (\p{XDigit}{4})$""")
private val dwc3Address = Regex("""^Set Address\(Addr = (\p{XDigit}{2})\)$""")
private val dwc3Descriptor = Regex("""^Get (String|Configuration) Descriptor\(Index = (\d+), Length = (\d+)\)$""")
private val dwc3Request = Regex("""^Type=(Class|Vendor) Recipient=(Device|Interface) Dir=(IN|OUT) bRequest=(\d+) wValue=(\d+) wIndex=(\d+) wLength=(\d+)$""")

private data class SetupRequest(
  val type: Int,
  val request: Int,
  val value: Int,
  val index: Int?,
  val length: Int,
  val timeMs: Long,
) {
  val isAddress: Boolean get() = type == 0 && request == 5
  val isDescriptorRead: Boolean get() = type == 0x80 && request == 6
  val descriptorType: Int get() = value shr 8
  val descriptorIndex: Int get() = value and 0xff
  val isMicrosoftString: Boolean get() =
    isDescriptorRead && value == 0x03ee && (index == 0 || index == null) && length == 18
}

private fun parseSetup(event: String, details: String, timeMs: Long): SetupRequest? {
  if (event == "mtu3_handle_setup" || event == "qualcomm_setup" || event == "usb_core_setup") {
    val values = mtu3Setup.matchEntire(details)?.groupValues?.drop(1)?.map { it.toInt(16) } ?: return null
    val (type, request, value, index, length) = values
    return SetupRequest(type, request, value, index, length, timeMs)
  }

  // Upstream DWC3 may prefix the decoded request with a controller address.
  val decoded = details.substringAfter(": ")
  dwc3Address.matchEntire(decoded)?.let { match ->
    return SetupRequest(0, 5, match.groupValues[1].toInt(16), 0, 0, timeMs)
  }
  dwc3Descriptor.matchEntire(decoded)?.let { match ->
    val (label, index, length) = match.destructured
    val type = if (label == "String") 3 else 2
    val id = index.toIntOrNull()?.takeIf { it in 0..255 } ?: return null
    return SetupRequest(0x80, 6, (type shl 8) or id, null, length.toIntOrNull() ?: return null, timeMs)
  }
  val match = dwc3Request.matchEntire(decoded) ?: return null
  val (kind, recipient, direction, request, value, index, length) = match.destructured
  val type = (if (kind == "Vendor") 0x40 else 0x20) or
    (if (recipient == "Interface") 1 else 0) or (if (direction == "IN") 0x80 else 0)
  return SetupRequest(
    type,
    request.toIntOrNull() ?: return null,
    value.toIntOrNull() ?: return null,
    index.toIntOrNull() ?: return null,
    length.toIntOrNull() ?: return null,
    timeMs,
  )
}

/** The clock is CLOCK_MONOTONIC, matching the instance's trace clock. */
internal fun classifyUsbHostTrace(trace: String, nowMs: Long): UsbHostFingerprint {
  var addressed = false
  var configuredAt: Long? = null
  val requests = mutableListOf<SetupRequest>()
  val pendingCoreRequests = mutableListOf<SetupRequest>()
  var coreConfigurationRequested = false
  for (line in trace.lineSequence()) {
    val match = traceEvent.find(line) ?: continue
    val (seconds, event, details) = match.destructured
    val time = (seconds.toDouble() * 1000).toLong()
    if (event == "usb_gadget_set_state") {
      when (val state = gadgetState.find(details)?.groupValues?.get(1)) {
        "0", "6" -> {
          addressed = state == "6"
          configuredAt = null
          requests.clear()
          pendingCoreRequests.clear()
          coreConfigurationRequested = false
        }
        "7" -> if (configuredAt == null && (addressed || coreConfigurationRequested)) {
          // Legacy UDCs handle SET_ADDRESS internally without reporting state 6.
          // Accept the buffered core requests only after configuration succeeds.
          if (!addressed) {
            addressed = true
            requests.addAll(pendingCoreRequests)
            pendingCoreRequests.clear()
          }
          configuredAt = time
        }
      }
      continue
    }

    val request = parseSetup(event, details, time) ?: continue
    if (request.isAddress) {
      addressed = request.value in 1..127
      configuredAt = null
      requests.clear()
      pendingCoreRequests.clear()
      coreConfigurationRequested = false
    } else if (event == "usb_core_setup" && request.type == 0 && request.request == 9 &&
      request.value == 0 && request.index == 0 && request.length == 0
    ) {
      addressed = false
      configuredAt = null
      requests.clear()
      pendingCoreRequests.clear()
      coreConfigurationRequested = false
    } else if (!addressed && event == "usb_core_setup") {
      pendingCoreRequests.add(request)
      if (request.type == 0 && request.request == 9) {
        coreConfigurationRequested = request.value in 1..255 && request.index == 0 && request.length == 0
        if (!coreConfigurationRequested) pendingCoreRequests.clear()
      }
    } else if (addressed && (configuredAt == null || time <= configuredAt + ENUMERATION_WINDOW_MS)) {
      requests.add(request)
      // CI13xxx logs SET_CONFIGURATION rather than a gadget state tracepoint.
      if (event == "qualcomm_setup" && request.type == 0 && request.request == 9 &&
        request.index == 0 && request.length == 0
      ) {
        configuredAt = time.takeIf { request.value in 1..255 }
        if (request.value == 0) { addressed = false; requests.clear() }
      }
    }
  }

  if (requests.any { it.isMicrosoftString }) return UsbHostFingerprint("windows")
  val configured = configuredAt ?: return UsbHostFingerprint()
  val elapsed = nowMs - configured
  val windowComplete = elapsed >= ENUMERATION_WINDOW_MS
  val protocolAt = requests.filter {
    it.type == 0x21 && it.request == 11 && it.value == 1
  }.maxOfOrNull { it.timeMs }
  val gateElapsed = protocolAt?.let { nowMs - it } ?: elapsed
  val os = inferFromEnumeration(requests, windowComplete, gateElapsed, protocolAt)
  return UsbHostFingerprint(os, detecting = os == null && !windowComplete)
}

private fun inferFromEnumeration(
  requests: List<SetupRequest>,
  windowComplete: Boolean,
  gateElapsedMs: Long,
  protocolAt: Long?,
): String? {
  val strings = requests.filter { it.isDescriptorRead && it.descriptorType == 3 }
  val configurations = requests.filter { it.isDescriptorRead && it.descriptorType == 2 }
  val compatibilityReads = requests.filter { it.type == 0xc0 && it.value == 0 && it.index == 4 }
    .groupBy { it.request }

  // A Microsoft Extended Compat ID header is 16 bytes, followed by 24 bytes per function.
  val microsoftCompatibility = compatibilityReads.values.any { reads ->
    val header = reads.indexOfFirst { it.length == 16 }
    header >= 0 && reads.drop(header + 1).any { it.length >= 40 && (it.length - 16) % 24 == 0 }
  }
  if (microsoftCompatibility && configurations.any { it.length == 255 } && pairedStrings(strings, 4) >= 2) {
    return "windows"
  }

  // Standalone Windows HID captures can omit cached Microsoft OS requests.
  // Require the observed combination, not a single generic descriptor read.
  val windowsHidStrings = strings.filter {
    it.length == 1026 && it.index == 0x0409 && it.descriptorIndex in 1..237
  }.map { it.descriptorIndex }.distinct().size >= 2
  val zeroHidIdle = requests.any {
    it.type == 0x21 && it.request == 10 && it.value == 0 && it.length == 0
  }
  if (windowComplete && windowsHidStrings && zeroHidIdle &&
    configurations.any { it.length == 255 } &&
    strings.any { it.descriptorIndex == 0 && it.length == 255 }
  ) return "windows"

  val appleHid = requests.any { it.type == 0x21 && it.request == 10 && (it.value shr 8) > 0 } &&
    requests.any { it.type == 0x21 && it.request == 11 && it.value == 1 }
  if (appleHid && pairedStrings(strings, 2) >= 3 && strings.none { it.length >= 254 }) {
    // iOS initializes the keyboard LED report during enumeration; the macOS
    // captures do not. Keep the exact report shape so unrelated HID output
    // reports do not turn a Mac into iOS.
    val gate = protocolAt ?: return null
    val appleLedReport = requests.any {
      it.type == 0x21 && it.request == 9 &&
        it.value == 0x0200 && it.index == 1 && it.length == 1 &&
        it.timeMs >= gate && it.timeMs - gate <= APPLE_LED_GRACE_MS
    }
    return when {
      appleLedReport -> "ios"
      // iOS sends the LED report shortly after SET_PROTOCOL. Wait a short grace
      // from that request so an early poll cannot latch iOS as macOS.
      gateElapsedMs < APPLE_LED_GRACE_MS -> null
      else -> "macos"
    }
  }

  val longStrings = strings.filter { it.length == 255 }
  val hasLinuxBase = longStrings.any { it.descriptorIndex == 0 } &&
    longStrings.map { it.descriptorIndex }.filter { it != 0 && it != 0xee }.distinct().size >= 5 &&
    configurations.any { it.length == 9 } && configurations.none { it.length == 255 }
  if (!hasLinuxBase) return null
  // Android can begin with the same reads and request its language table later.
  if (strings.all { it.length == 255 }) return "linux".takeIf { windowComplete }

  val androidLanguageReads = strings.count {
    it.descriptorIndex == 0 && (it.index == 0 || it.index == null) && it.length == 254
  }
  if (androidLanguageReads >= 2 && strings.all { it.length == 255 || (it.descriptorIndex == 0 && it.length == 254) }) {
    return "android"
  }
  return null
}

private fun pairedStrings(requests: List<SetupRequest>, headerLength: Int): Int =
  requests.filter { it.descriptorIndex != 0 && it.descriptorIndex != 0xee }
    .groupBy { it.descriptorIndex to it.index }
    .count { (_, reads) ->
      val header = reads.indexOfFirst { it.length == headerLength }
      header >= 0 && reads.drop(header + 1).any { it.length > headerLength && it.length < 254 && it.length % 2 == 0 }
    }
