package org.kaijinlab.tap_ducky

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
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

  private fun capture(name: String): String =
    checkNotNull(javaClass.getResource("/usb-host/$name.trace")).readText()
}
