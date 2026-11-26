package org.kaijinlab.tap_ducky

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class UsbHostOsObserverTest {
  private val prefix = "irq-14 [001] .... 3.000000: "
  private val mtuAddress = "${prefix}mtu3_handle_setup: setup - 00 05 0002 0000 0000"
  private val mtuWindows = "${prefix}mtu3_handle_setup: setup - 80 06 03ee 0000 0012"
  private val detach = "${prefix}usb_gadget_set_state: speed 0/5 state 0 0mA [connected] --> 0"
  private val newAddress = "${prefix}usb_gadget_set_state: speed 3/5 state 6 0mA [connected] --> 0"

  @Test
  fun recognizesTheMicrosoftRequestOnEitherSupportedController() {
    assertEquals("windows", classifyUsbHostTrace("$mtuAddress\n$newAddress\n$mtuWindows", 3000).os)
    val dwcAddress = "${prefix}dwc3_ctrl_req: Set Address(Addr = 09)"
    val dwcWindows = "${prefix}dwc3_ctrl_req: 0a600000: Get String Descriptor(Index = 238, Length = 18)"
    assertEquals("windows", classifyUsbHostTrace("$dwcAddress\n$dwcWindows", 3000).os)
  }

  @Test
  fun ignoresIncompleteAndAmbiguousCaptures() {
    assertNull(classifyUsbHostTrace(mtuWindows, 6000).os)
    assertNull(classifyUsbHostTrace("$mtuAddress\n${prefix}mtu3_handle_setup: setup - 80 06 0301 0409 00ff", 6000).os)
    assertNull(classifyUsbHostTrace("$mtuAddress\n${prefix}mtu3_handle_setup: setup - 80 06 03ee 0409 0012", 6000).os)
  }

  @Test
  fun dropsThePreviousHostEvenIfPollingMissesUnplug() {
    val previous = "$mtuAddress\n$mtuWindows"
    assertNull(classifyUsbHostTrace("$previous\n$detach", 6000).os)
    assertNull(classifyUsbHostTrace("$previous\n$newAddress", 6000).os)
    assertNull(classifyUsbHostTrace("$previous\n$mtuAddress", 6000).os)
    assertEquals("windows", classifyUsbHostTrace("$previous\n$detach\n$mtuAddress\n$mtuWindows", 6000).os)
  }

  @Test
  fun replaysBothHardwareCapturesForEachHost() {
    val captures = mapOf(
      "linux" to listOf("linux-01", "linux-02"),
      "android" to listOf("android-01", "android-02"),
      "windows" to listOf("windows-usb-a", "windows-usb-c"),
      "macos" to listOf("macos-01", "macos-02"),
      "ios" to listOf("ios-01", "ios-02"),
    )
    for ((host, trials) in captures) {
      for (trial in trials) {
        assertEquals(trial, host, classifyUsbHostTrace(capture(trial), 15000).os)
      }
    }
  }

  @Test
  fun waitsForLateAndroidRequestsAndIgnoresTrafficAfterEnumeration() {
    val capture = capture("android-01")
    val early = capture.substringBefore(
      capture.lineSequence().first { it.endsWith("80 06 0300 0000 00fe") }
    )
    assertEquals(UsbHostFingerprint(detecting = true), classifyUsbHostTrace(early, 10500))
    assertEquals(UsbHostFingerprint("android"), classifyUsbHostTrace(capture, 11000))

    val late = "capture [000] .... 99.000000: mtu3_handle_setup: setup - 80 06 0300 0000 00fe"
    assertEquals("linux", classifyUsbHostTrace(capture("linux-01") + late, 100000).os)
  }

  @Test
  fun reportsOnlyAnUnresolvedWindowAsDetecting() {
    assertEquals(
      UsbHostFingerprint(detecting = true),
      classifyUsbHostTrace(capture("linux-01"), 11000),
    )
    assertEquals(UsbHostFingerprint("linux"), classifyUsbHostTrace(capture("linux-01"), 15000))

    val configured = "${prefix}usb_gadget_set_state: speed 3/5 state 7 0mA [connected] --> 0"
    val unfamiliar = "$mtuAddress\n$configured"
    assertEquals(UsbHostFingerprint(detecting = true), classifyUsbHostTrace(unfamiliar, 4000))
    assertEquals(UsbHostFingerprint(), classifyUsbHostTrace(unfamiliar, 6000))
    assertEquals(UsbHostFingerprint(), classifyUsbHostTrace("$unfamiliar\n$detach", 4000))
  }

  @Test
  fun reportsPositiveWindowsAndMacSignaturesBeforeTheWindowEnds() {
    assertEquals(UsbHostFingerprint("windows"), classifyUsbHostTrace(capture("windows-usb-c"), 11500))
    assertEquals(UsbHostFingerprint("macos"), classifyUsbHostTrace(capture("macos-01"), 11500))
  }

  @Test
  fun recognizesTheWindowsReconnectInDecodedDwc3Output() {
    val requests = listOf(
      "Set Address(Addr = 04)",
      "Get Configuration Descriptor(Index = 0, Length = 255)",
      "Type=Vendor Recipient=Device Dir=IN bRequest=1 wValue=0 wIndex=4 wLength=16",
      "Type=Vendor Recipient=Device Dir=IN bRequest=1 wValue=0 wIndex=4 wLength=40",
      "Get String Descriptor(Index = 5, Length = 4)",
      "Get String Descriptor(Index = 5, Length = 28)",
      "Get String Descriptor(Index = 6, Length = 4)",
      "Get String Descriptor(Index = 6, Length = 28)",
    )
    val configured = "${prefix}usb_gadget_set_state: speed 3/5 state 7 0mA [connected] --> 0"
    val trace = requests.joinToString("\n", postfix = "\n$configured") {
      "${prefix}dwc3_ctrl_req: a600000: $it"
    }
    assertEquals("windows", classifyUsbHostTrace(trace, 6000).os)
    assertNull(classifyUsbHostTrace(trace.replace("bRequest=1 wValue=0 wIndex=4 wLength=40",
      "bRequest=2 wValue=0 wIndex=4 wLength=40"), 6000).os)
  }

  @Test
  fun distinguishesIosFromMacosByTheAppleLedReport() {
    assertEquals("macos", classifyUsbHostTrace(capture("macos-01"), 11500).os)
    assertEquals("ios", classifyUsbHostTrace(capture("ios-01"), 11500).os)
    assertEquals("ios", classifyUsbHostTrace(capture("ios-02"), 11500).os)
  }

  @Test
  fun doesNotUseAnUnrelatedHidSetReportAsIos() {
    val unrelated = "capture [000] .... 10.210000: mtu3_handle_setup: setup - 21 09 0100 0001 0001"
    assertEquals("macos", classifyUsbHostTrace("${capture("macos-01")}\n$unrelated", 11500).os)
  }

  @Test
  fun capturesTheHidSetReportNeededForIos() {
    val script = UsbHostOsObserver.buildStartScript("16751000.usb0")
    assertTrue(script.contains("bRequest == 9"))
  }

  @Test
  fun doesNotLatchIosAsMacosBeforeTheLedReport() {
    val beforeLed = capture("ios-01").lineSequence()
      .takeWhile { !it.endsWith("setup - 21 09 0200 0001 0001") }
      .joinToString("\n")
    assertEquals(UsbHostFingerprint(detecting = true), classifyUsbHostTrace(beforeLed, 10110))
    assertEquals("ios", classifyUsbHostTrace(capture("ios-01"), 10200).os)
  }

  @Test
  fun doesNotLatchIosAsMacosWhenTheAppleGateArrivesLate() {
    val trace = listOf(
      traceLine("10.000000", "usb_gadget_set_state: speed 3/3 state 0 0mA [bus-powered:activated:connected] --> 0"),
      traceLine("10.001000", "mtu3_handle_setup: setup - 00 05 0001 0000 0000"),
      traceLine("10.002000", "usb_gadget_set_state: speed 3/3 state 6 0mA [bus-powered:activated:connected] --> 0"),
      traceLine("10.003000", "mtu3_handle_setup: setup - 80 06 0302 0409 0002"),
      traceLine("10.004000", "mtu3_handle_setup: setup - 80 06 0302 0409 0012"),
      traceLine("10.005000", "mtu3_handle_setup: setup - 80 06 0301 0409 0002"),
      traceLine("10.006000", "mtu3_handle_setup: setup - 80 06 0301 0409 000c"),
      traceLine("10.007000", "mtu3_handle_setup: setup - 80 06 0303 0409 0002"),
      traceLine("10.008000", "mtu3_handle_setup: setup - 80 06 0303 0409 0022"),
      traceLine("10.009000", "mtu3_handle_setup: setup - 00 09 0001 0000 0000"),
      traceLine("10.010000", "usb_gadget_set_state: speed 3/3 state 7 0mA [bus-powered:activated:connected] --> 0"),
      traceLine("10.400000", "mtu3_handle_setup: setup - 21 0a 0600 0001 0000"),
      traceLine("10.401000", "mtu3_handle_setup: setup - 21 0b 0001 0001 0000"),
    ).joinToString("\n")
    assertEquals(UsbHostFingerprint(detecting = true), classifyUsbHostTrace(trace, 10420))
  }

  @Test
  fun ignoresAnAppleLedReportLongAfterTheHidGate() {
    val late = "capture [000] .... 11.000000: mtu3_handle_setup: setup - 21 09 0200 0001 0001"
    assertEquals("macos", classifyUsbHostTrace("${capture("macos-01")}\n$late", 11500).os)
  }

  @Test
  fun recognizesIosInDecodedDwc3Output() {
    val configured = "${prefix}usb_gadget_set_state: speed 3/5 state 7 0mA [connected] --> 0"
    val requests = listOf(
      "Set Address(Addr = 01)",
      "Get String Descriptor(Index = 2, Length = 2)",
      "Get String Descriptor(Index = 2, Length = 18)",
      "Get String Descriptor(Index = 1, Length = 2)",
      "Get String Descriptor(Index = 1, Length = 12)",
      "Get String Descriptor(Index = 3, Length = 2)",
      "Get String Descriptor(Index = 3, Length = 34)",
      "Type=Class Recipient=Interface Dir=OUT bRequest=10 wValue=1536 wIndex=1 wLength=0",
      "Type=Class Recipient=Interface Dir=OUT bRequest=11 wValue=1 wIndex=1 wLength=0",
      "Type=Class Recipient=Interface Dir=OUT bRequest=9 wValue=512 wIndex=1 wLength=1",
    )
    val trace = requests.joinToString("\n", postfix = "\n$configured") {
      "${prefix}dwc3_ctrl_req: a600000: $it"
    }
    assertEquals("ios", classifyUsbHostTrace(trace, 6000).os)
  }

  private fun traceLine(time: String, details: String): String =
    "capture [000] .... $time: $details"

  private fun capture(name: String): String =
    checkNotNull(javaClass.getResource("/usb-host/$name.trace")).readText()
}
