package org.kaijinlab.tap_ducky

import java.util.Locale

/** Control-endpoint metadata only; never enables logging of keyboard reports. */
internal class QualcommUsbHostTrace(private var lastTimestampUs: Long) {
  private val trace = ArrayDeque<String>()
  private var clockOffsetMs: Long? = null

  fun readProbe(events: String, nowMs: Long): UsbHostFingerprint = readRecords(
    events.lineSequence().mapNotNull { line ->
      coreState.matchEntire(line)?.let { match ->
        val (time, state) = match.destructured
        return@mapNotNull (time to "usb_gadget_set_state: speed 0/0 state $state core")
          .takeIf { state in listOf("0", "6", "7") }
      }
      coreSetup.matchEntire(line)?.let { match ->
        val values = match.groupValues.drop(2).map { it.toIntOrNull() ?: return@mapNotNull null }
        if (values.take(2).any { it !in 0..255 } || values.drop(2).any { it !in 0..65535 }) return@mapNotNull null
        return@mapNotNull match.groupValues[1] to String.format(
          Locale.US, "usb_core_setup: setup - %02x %02x %04x %04x %04x", *values.toTypedArray(),
        )
      }
      val match = probe.matchEntire(line) ?: return@mapNotNull null
      val (time, address, kind, payload) = match.destructured
      decodeRecord(time, address.toIntOrNull(), kind, payload)
    }.toList(), nowMs,
  )

  fun read(events: String, nowMs: Long): UsbHostFingerprint = readRecords(
    events.lineSequence().mapNotNull { line ->
      val match = event.matchEntire(line.trim()) ?: return@mapNotNull null
      val (time, endpoint, kind, payload) = match.destructured
      decodeRecord(time, endpoint.toIntOrNull(16), kind, payload)
    }.toList(), nowMs,
  )

  private fun decodeRecord(time: String, endpoint: Int?, kind: String, payload: String): Pair<String, String>? {
    val decoded = when {
      kind == "BUS RST" && endpoint == 255 -> "usb_gadget_set_state: speed 0/0 state 0 reset"
      kind == "SETUP" && endpoint == 0 -> {
        val request = setup.matchEntire(payload) ?: return null
        val (type, code, value, index, length) = request.destructured
        val size = length.toIntOrNull()?.takeIf { it in 0..65535 } ?: return null
        "qualcomm_setup: setup - $type $code $value $index ${String.format(Locale.US, "%04x", size)}"
      }
      else -> return null
    }
    return time to decoded
  }

  private fun readRecords(records: List<Pair<String, String>>, nowMs: Long): UsbHostFingerprint {
    val newest = records.maxOfOrNull { (seconds, _) -> (seconds.toDouble() * 1_000_000).toLong() } ?: 0L
    if (clockOffsetMs == null && newest > lastTimestampUs) {
      // Driver logs use cpu_clock(), not necessarily Android's uptime clock.
      clockOffsetMs = nowMs - newest / 1000
    }
    for ((seconds, decoded) in records) {
      val time = (seconds.toDouble() * 1_000_000).toLong()
      if (time <= lastTimestampUs) continue
      lastTimestampUs = time
      trace.addLast("capture [000] .... $seconds: $decoded")
      while (trace.size > 256) trace.removeFirst()
    }
    return classifyUsbHostTrace(trace.joinToString("\n"), nowMs - (clockOffsetMs ?: 0))
  }

  companion object {
    private val event = Regex("""^\[\s*(\d+\.\d+)]\s+\S+\s+([\p{XDigit}]{2})\s+(BUS RST|SETUP)\s+-?\d+\s+\S+\s*(.*)$""")
    private val setup = Regex("""^([\p{XDigit}]{2}) ([\p{XDigit}]{2}) ([\p{XDigit}]{4}) ([\p{XDigit}]{4}) (\d+)$""")
    private val timestamp = Regex("""^\[\s*(\d+\.\d+)]""")
    private val probe = Regex("""^.*\s(\d+\.\d+): qualcomm_setup: .* addr=(\d+) kind="(SETUP|BUS RST)" payload="([^"]*)"$""")
    private val coreSetup = Regex("""^.*\s(\d+\.\d+): qualcomm_ctrl: .* type=(\d+) request=(\d+) value=(\d+) index=(\d+) length=(\d+)$""")
    private val coreState = Regex("""^.*\s(\d+\.\d+): qualcomm_state: .* state=(\d+)$""")

    internal fun buildProbeStartScript(controller: String, recovery: String): String {
      require(controller.matches(Regex("[A-Za-z0-9._-]+")))
      return """
        set -e
        driver=${'$'}(readlink /sys/class/udc/$controller/device/driver)
        [ "${'$'}{driver##*/}" = msm_hsusb ] && [ "${'$'}(uname -m)" = aarch64 ] || exit 1
        base=""
        for candidate in /sys/kernel/tracing /sys/kernel/debug/tracing; do
          if [ -d "${'$'}candidate/instances" ] && [ -w "${'$'}candidate/kprobe_events" ]; then
            base="${'$'}candidate"; break
          fi
        done
        [ -n "${'$'}base" ] || exit 1
        state=${shQuote(recovery)}
        dir="${'$'}base/instances/tapducky_qualcomm_host"
        [ ! -e "${'$'}state" ] && [ ! -d "${'$'}dir" ] || exit 1
        for event in qualcomm_setup qualcomm_ctrl qualcomm_state; do
          [ ! -d "${'$'}base/events/tapducky_usb/${'$'}event" ] || exit 1
        done
        umask 077
        printf '%s\n' "${'$'}base" > "${'$'}state.tmp"
        mv "${'$'}state.tmp" "${'$'}state"
        cleanup() { sh -c ${shQuote(buildProbeStopScript(recovery))}; }
        trap cleanup EXIT
        mkdir "${'$'}dir"
        echo 0 > "${'$'}dir/tracing_on"
        echo 64 > "${'$'}dir/buffer_size_kb"
        echo mono > "${'$'}dir/trace_clock"
        # Read exactly the eight USB setup bytes; some kernels cannot fetch strings.
        if printf '%s\n' 'p:tapducky_usb/qualcomm_ctrl composite_setup type=+0(%x1):u8 request=+1(%x1):u8 value=+2(%x1):u16 index=+4(%x1):u16 length=+6(%x1):u16' >> "${'$'}base/kprobe_events" &&
          printf '%s\n' 'p:tapducky_usb/qualcomm_state usb_gadget_set_state state=%x1:u32' >> "${'$'}base/kprobe_events"; then
          echo 'state == 0 || state == 6 || state == 7' > "${'$'}dir/events/tapducky_usb/qualcomm_state/filter"
          echo 1 > "${'$'}dir/events/tapducky_usb/qualcomm_state/enable"
          echo 1 > "${'$'}dir/events/tapducky_usb/qualcomm_ctrl/enable"
        else
          for event in qualcomm_ctrl qualcomm_state; do
            if [ -d "${'$'}base/events/tapducky_usb/${'$'}event" ]; then
              printf '%s\n' "-:tapducky_usb/${'$'}event" >> "${'$'}base/kprobe_events"
            fi
          done
          printf '%s\n' 'p:tapducky_usb/qualcomm_setup dbg_print addr=%x0:u8 kind=+0(%x1):string payload=+0(%x3):string' >> "${'$'}base/kprobe_events"
          echo '(addr == 0 && kind == "SETUP") || (addr == 255 && kind == "BUS RST")' > "${'$'}dir/events/tapducky_usb/qualcomm_setup/filter"
          echo 1 > "${'$'}dir/events/tapducky_usb/qualcomm_setup/enable"
        fi
        echo 1 > "${'$'}dir/tracing_on"
        printf '%s\n' "${'$'}dir"
        trap - EXIT
      """.trimIndent()
    }

    internal fun buildProbeStopScript(recovery: String): String = """
      set -e
      state=${shQuote(recovery)}
      [ -f "${'$'}state" ] || exit 0
      base=${'$'}(cat "${'$'}state")
      case "${'$'}base" in /sys/kernel/tracing|/sys/kernel/debug/tracing) ;; *) exit 1 ;; esac
      dir="${'$'}base/instances/tapducky_qualcomm_host"
      if [ -d "${'$'}dir" ]; then
        echo 0 > "${'$'}dir/tracing_on"
        rmdir "${'$'}dir"
      fi
      for event in qualcomm_setup qualcomm_ctrl qualcomm_state; do
        if [ -d "${'$'}base/events/tapducky_usb/${'$'}event" ]; then
          printf '%s\n' "-:tapducky_usb/${'$'}event" >> "${'$'}base/kprobe_events"
        fi
      done
      rm "${'$'}state"
    """.trimIndent()

    internal fun latestTimestampUs(events: String): Long = events.lineSequence().mapNotNull {
      timestamp.find(it.trim())?.groupValues?.get(1)?.toDoubleOrNull()?.let { seconds ->
        (seconds * 1_000_000).toLong()
      }
    }.maxOrNull() ?: 0L

    internal fun buildStartScript(controller: String, recovery: String): String {
      require(controller.matches(Regex("[A-Za-z0-9._-]+")))
      return """
        set -e
        device=/sys/class/udc/$controller/device
        driver=${'$'}(readlink "${'$'}device/driver")
        [ "${'$'}{driver##*/}" = msm_hsusb ] || exit 1
        # The masks and event format belong to the Qualcomm CI13xxx driver.
        path="${'$'}device/gadget"
        mask="${'$'}path/ep_addr_rxdbg_mask_enable"
        [ -r "${'$'}path/events" ] && [ -w "${'$'}mask" ] || exit 1
        state=${shQuote(recovery)}
        [ ! -e "${'$'}state" ] || exit 1
        original=${'$'}(cat "${'$'}mask")
        case "${'$'}original" in ''|*[!0-9]*) exit 1 ;; esac
        boot=${'$'}(cat /proc/sys/kernel/random/boot_id)
        umask 077
        printf '%s\n%s\n%s\n' '$controller' "${'$'}original" "${'$'}boot" > "${'$'}state.tmp"
        mv "${'$'}state.tmp" "${'$'}state"
        printf '%s\n' "${'$'}path"
        # Snapshot the ring before enabling new records, excluding stale hosts.
        cat "${'$'}path/events"
        # Only EP0 OUT is needed: SETUP packets are recorded on this endpoint.
        echo ${'$'}((original | 1)) > "${'$'}mask"
      """.trimIndent()
    }

    internal fun buildStopScript(recovery: String): String = """
      set -e
      state=${shQuote(recovery)}
      [ -f "${'$'}state" ] || exit 0
      controller=${'$'}(sed -n '1p' "${'$'}state")
      original=${'$'}(sed -n '2p' "${'$'}state")
      boot=${'$'}(sed -n '3p' "${'$'}state")
      case "${'$'}controller" in ''|*[!A-Za-z0-9._-]*) exit 1 ;; esac
      case "${'$'}original" in ''|*[!0-9]*) exit 1 ;; esac
      if [ "${'$'}boot" = "${'$'}(cat /proc/sys/kernel/random/boot_id)" ]; then
        mask="/sys/class/udc/${'$'}controller/device/gadget/ep_addr_rxdbg_mask_enable"
        current=${'$'}(cat "${'$'}mask")
        case "${'$'}current" in ''|*[!0-9]*) exit 1 ;; esac
        # Preserve any unrelated endpoint logging enabled by another tool.
        restored=${'$'}(( (current & ~1) | (original & 1) ))
        echo "${'$'}restored" > "${'$'}mask"
        [ "${'$'}(cat "${'$'}mask")" = "${'$'}restored" ] || exit 1
      fi
      rm "${'$'}state"
    """.trimIndent()
  }
}
