package org.kaijinlab.tap_ducky

import java.io.File
import java.nio.file.Files
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class QualcommUsbHostTraceTest {
  @get:Rule val directory = TemporaryFolder()

  private fun line(time: String, request: String) = "[ $time] \t? 00 SETUP      0 ?\t$request"

  @Test fun parsesDecimalLengthsAndRejectsStaleSessions() {
    val capture = line("3.001000", "00 05 003E 0000 0") + "\n" +
      line("3.002000", "80 06 03EE 0000 18")
    val trace = QualcommUsbHostTrace(3_000_000)
    assertEquals("windows", trace.read(capture, 4000).os)
    assertEquals("windows", trace.read(capture, 5000).os)
    assertNull(QualcommUsbHostTrace(4_000_000).read(capture, 5000).os)
    assertNull(trace.read("[ 6.000000] \t? FF BUS RST    0 ?\t", 6000).os)
    assertNull(trace.read(capture, 7000).os)
  }

  @Test fun recognizesEachExistingHostSignatureInQualcommFormat() {
    for (os in listOf("windows", "linux", "android", "macos", "ios")) {
      val name = if (os == "windows") "windows-usb-c" else "$os-01"
      val original = checkNotNull(javaClass.getResource("/usb-host/$name.trace")).readText()
      val native = original.lineSequence().mapNotNull { row ->
        val time = Regex("""(\d+\.\d+): """).find(row)?.groupValues?.get(1) ?: return@mapNotNull null
        when {
          "mtu3_handle_setup: setup - " in row -> {
            val fields = row.substringAfter("setup - ").split(' ')
            line(time, fields.take(4).joinToString(" ") + " " + fields[4].toInt(16))
          }
          "state 0 " in row -> "[ $time] \t? FF BUS RST    0 ?\t"
          "state 7 " in row -> line(time, "00 09 0001 0000 0")
          else -> null
        }
      }.joinToString("\n")
      val trace = QualcommUsbHostTrace(0)
      trace.read(native, 15000)
      assertEquals(os, os, trace.read(native, 18000).os)
    }
  }

  @Test fun recognizesRealStandaloneWindowsCapturesButNotIncompleteTraffic() {
    for (name in listOf("qualcomm-windows-composite", "qualcomm-windows-keyboard", "qualcomm-windows-direct")) {
      val capture = checkNotNull(javaClass.getResource("/usb-host/$name.trace")).readText()
      val trace = QualcommUsbHostTrace(0)
      trace.read(capture, 10000)
      assertEquals(name, "windows", trace.read(capture, 13000).os)
      val withoutIdle = capture.lineSequence().filterNot { "21 0A 0000" in it }.joinToString("\n")
      val incomplete = QualcommUsbHostTrace(0)
      incomplete.read(withoutIdle, 10000)
      assertNull(incomplete.read(withoutIdle, 13000).os)
    }
    assertNull(QualcommUsbHostTrace(0).read(line("3.000000", "80 06 03EE 0000 18"), 4000).os)
  }

  @Test fun ignoresLateOrInsufficientWindowsHidStringReads() {
    val base = listOf(
      line("3.000000", "00 05 003E 0000 0"),
      line("3.001000", "80 06 0200 0000 255"),
      line("3.002000", "80 06 0300 0000 255"),
      line("3.003000", "00 09 0001 0000 0"),
      line("3.004000", "21 0A 0000 0000 0"),
      line("3.005000", "80 06 0301 0409 1026"),
    ).joinToString("\n")
    for (extra in listOf(
      line("3.006000", "80 06 0301 0409 1026"),
      line("3.006000", "80 06 0302 0410 1026"),
      line("9.006000", "80 06 0302 0409 1026"),
    )) {
      val trace = QualcommUsbHostTrace(0)
      trace.read("$base\n$extra", 10000)
      assertNull(trace.read("$base\n$extra", 13000).os)
    }
  }

  @Test fun handlesIndependentDriverClocksAndAnExistingRing() {
    val old = line("9000.000000", "00 05 003E 0000 0") + "\n" +
      line("9000.001000", "80 06 03EE 0000 18")
    val trace = QualcommUsbHostTrace(QualcommUsbHostTrace.latestTimestampUs(old))
    assertNull(trace.read(old, 1000).os)
    val fresh = line("9001.000000", "00 05 003E 0000 0") + "\n" +
      line("9001.001000", "00 09 0001 0000 0")
    assertTrue(trace.read(fresh, 1000).detecting)
    assertFalse(trace.read(fresh, 4000).detecting)
  }

  @Test fun switchesFromRealWindowsToDebianWithoutRetainingThePreviousHost() {
    val windows = checkNotNull(javaClass.getResource("/usb-host/qualcomm-windows-direct.trace")).readText()
    val debian = checkNotNull(javaClass.getResource("/usb-host/qualcomm-linux-debian.trace")).readText()
    val trace = QualcommUsbHostTrace(0)
    trace.read(windows, 10000)
    assertEquals("windows", trace.read(windows, 13000).os)
    val connected = 10000 + (QualcommUsbHostTrace.latestTimestampUs(debian) -
      QualcommUsbHostTrace.latestTimestampUs(windows)) / 1000
    trace.read(debian, connected)
    assertEquals("linux", trace.read(debian, connected + 3000).os)
    assertNull(trace.read("[ 5000.000000] ? FF BUS RST 0 ?", connected + 500000).os)
  }

  @Test fun filteredProbeReplaysTheSameExistingSignaturesWithoutQueueNoise() {
    for (os in listOf("windows", "linux", "android", "macos", "ios")) {
      val name = if (os == "windows") "windows-usb-c" else "$os-01"
      val capture = checkNotNull(javaClass.getResource("/usb-host/$name.trace")).readText()
      val filtered = capture.lineSequence().mapNotNull { row ->
        val time = Regex("""(\d+\.\d+): """).find(row)?.groupValues?.get(1) ?: return@mapNotNull null
        when {
          "mtu3_handle_setup: setup - " in row -> {
            val fields = row.substringAfter("setup - ").split(' ')
            val payload = fields.take(4).joinToString(" ") + " " + fields[4].toInt(16)
            "irq [001] .... $time: qualcomm_setup: (dbg_print+0x0/0x100) addr=0 kind=\"SETUP\" payload=\"$payload\""
          }
          "state 0 " in row ->
            "irq [001] .... $time: qualcomm_setup: (dbg_print+0x0/0x100) addr=255 kind=\"BUS RST\" payload=\"\""
          else -> null
        }
      }.joinToString("\n")
      val trace = QualcommUsbHostTrace(0)
      trace.readProbe(filtered, 15000)
      assertEquals(os, os, trace.readProbe(filtered, 18000).os)
    }
    val truncated = checkNotNull(javaClass.getResource("/usb-host/qualcomm-android-truncated.trace")).readText()
    val trace = QualcommUsbHostTrace(0)
    trace.read(truncated, 15000)
    assertNull(trace.read(truncated, 18000).os)
  }

  @Test fun filteredCaptureOwnsOnlyItsNamedProbeAndInstance() {
    val start = QualcommUsbHostTrace.buildProbeStartScript("msm_hsusb", "/private/recovery")
    val stop = QualcommUsbHostTrace.buildProbeStopScript("/private/recovery")
    assertTrue(start.contains("kind=+0(%x1):string payload=+0(%x3):string"))
    assertTrue(start.contains("kind == \"SETUP\""))
    assertTrue(start.contains("/instances/tapducky_qualcomm_host"))
    assertFalse(start.contains("ep_addr_rxdbg_mask_enable"))
    assertTrue(start.contains("composite_setup type=+0(%x1):u8"))
    assertTrue(start.contains("usb_gadget_set_state state=%x1:u32"))
    assertTrue(stop.contains("for event in qualcomm_setup qualcomm_ctrl qualcomm_state"))
    assertTrue(stop.contains("\"-:tapducky_usb/${'$'}event\""))
    assertFalse(stop.contains("rm -r"))
    for (script in listOf(start, stop)) {
      val process = ProcessBuilder("/bin/sh", "-n", "-c", script).redirectErrorStream(true).start()
      try {
        assertTrue(process.waitFor(5, TimeUnit.SECONDS))
        assertEquals(process.inputStream.bufferedReader().readText(), 0, process.exitValue())
      } finally { process.destroyForcibly() }
    }
  }

  @Test fun replaysTheCompleteFilteredAndroidHardwareCapture() {
    val capture = checkNotNull(javaClass.getResource("/usb-host/qualcomm-android-filtered.trace")).readText()
    val trace = QualcommUsbHostTrace(0)
    assertEquals("android", trace.readProbe(capture, 10000).os)
    assertEquals("android", trace.readProbe(capture, 13000).os)
  }

  @Test fun numericCoreProbesRecognizeEachHostWithoutAnyKernelStringFetches() {
    for (os in listOf("windows", "linux", "android", "macos", "ios")) {
      val name = if (os == "windows") "windows-usb-c" else "$os-01"
      val capture = checkNotNull(javaClass.getResource("/usb-host/$name.trace")).readText()
      val core = capture.lineSequence().mapNotNull { row ->
        val time = Regex("""(\d+\.\d+): """).find(row)?.groupValues?.get(1) ?: return@mapNotNull null
        if ("usb_gadget_set_state:" in row) {
          val state = Regex("""state ([067]) """).find(row)?.groupValues?.get(1) ?: return@mapNotNull null
          return@mapNotNull "irq [000] .... $time: qualcomm_state: (usb_gadget_set_state+0x0/0x100) state=$state"
        }
        if ("mtu3_handle_setup: setup - " !in row) return@mapNotNull null
        val values = row.substringAfter("setup - ").split(' ').map { it.toInt(16) }
        // SET_ADDRESS is handled by the UDC, not the composite setup callback.
        if (values[0] == 0 && values[1] == 5) return@mapNotNull null
        "irq [000] .... $time: qualcomm_ctrl: (composite_setup+0x0/0x100) " +
          listOf("type", "request", "value", "index", "length").zip(values)
            .joinToString(" ") { (key, value) -> "$key=$value" }
      }.joinToString("\n")
      val trace = QualcommUsbHostTrace(0)
      trace.readProbe(core, 15000)
      assertEquals(os, os, trace.readProbe(core, 18000).os)
      val withoutAddressState = core.lineSequence().filterNot { it.endsWith("state=6") }.joinToString("\n")
      val legacyUdc = QualcommUsbHostTrace(0)
      legacyUdc.readProbe(withoutAddressState, 15000)
      assertEquals("$os without state 6", os, legacyUdc.readProbe(withoutAddressState, 18000).os)
    }
  }

  @Test fun faultedStringFieldsAndInvalidNumericFieldsDoNotIdentifyAHost() {
    val address = "irq [000] .... 3.000000: qualcomm_state: (usb_gadget_set_state+0x0/0x100) state=6"
    val request = "irq [000] .... 3.001000: qualcomm_ctrl: (composite_setup+0x0/0x100) type=128 request=6 value=1006 index=0 length=18"
    assertEquals("windows", QualcommUsbHostTrace(0).readProbe("$address\n$request", 4000).os)
    for (invalid in listOf(
      request.replace("type=128", "type=256"),
      request.replace("request=6", "request=256"),
      request.replace("value=1006", "value=65536"),
      request.replace("index=0", "index=65536"),
      request.replace("length=18", "length=65536"),
      request.replace("length=18", "length=9999999999999999999"),
      "irq [000] .... 3.001000: qualcomm_setup: (dbg_print+0x0/0x1d8) addr=0 kind=(fault) payload=(fault)",
    )) assertNull(QualcommUsbHostTrace(0).readProbe("$address\n$invalid", 4000).os)
  }

  @Test fun coreCaptureWithoutAddressRequiresSuccessfulConfigurationInTheSameEpoch() {
    val request = "irq [000] .... 3.000000: qualcomm_ctrl: (composite_setup+0x0/0x100) type=128 request=6 value=1006 index=0 length=18"
    val configure = "irq [000] .... 3.001000: qualcomm_ctrl: (composite_setup+0x0/0x100) type=0 request=9 value=1 index=0 length=0"
    val configured = "irq [000] .... 3.002000: qualcomm_state: (usb_gadget_set_state+0x0/0x100) state=7"
    val reset = "irq [000] .... 3.001500: qualcomm_state: (usb_gadget_set_state+0x0/0x100) state=0"
    assertEquals("windows", QualcommUsbHostTrace(0).readProbe("$request\n$configure\n$configured", 4000).os)
    for (incomplete in listOf(
      "$request\n$configure", "$request\n$configured", "$request\n$configure\n$reset\n$configured",
      "$request\n${configure.replace("length=0", "length=1")}\n$configured",
      "$request\n${configure.replace("index=0", "index=1")}\n$configured",
      "$request\n${configure.replace("value=1", "value=0")}\n$configured",
    )) assertNull(QualcommUsbHostTrace(0).readProbe(incomplete, 4000).os)
    val trace = QualcommUsbHostTrace(0)
    assertEquals("windows", trace.readProbe("$request\n$configure\n$configured", 4000).os)
    val unconfigure = "irq [000] .... 9.000000: qualcomm_ctrl: (composite_setup+0x0/0x100) type=0 request=9 value=0 index=0 length=0"
    assertNull(trace.readProbe(unconfigure, 10000).os)
  }

  @Test fun restoresOnlyTheControlEndpointBitAfterRestart() {
    val fixture = Fixture()
    fixture.mask.writeText("4\n")
    assertEquals(0, fixture.run(QualcommUsbHostTrace.buildStartScript("fixture", fixture.recovery.path)))
    assertEquals("5", fixture.mask.readText().trim())
    assertTrue(fixture.recovery.exists())
    // Another diagnostic enables a different endpoint before the app restarts.
    fixture.mask.writeText("13\n")
    assertEquals(0, fixture.run(QualcommUsbHostTrace.buildStopScript(fixture.recovery.path)))
    assertEquals("12", fixture.mask.readText().trim())
    assertFalse(fixture.recovery.exists())
    assertEquals(0, fixture.run(QualcommUsbHostTrace.buildStopScript(fixture.recovery.path)))
  }

  @Test fun leavesPreexistingControlLoggingEnabledAndDoesNotRestoreAcrossReboot() {
    val fixture = Fixture()
    fixture.mask.writeText("1\n")
    assertEquals(0, fixture.run(QualcommUsbHostTrace.buildStartScript("fixture", fixture.recovery.path)))
    assertEquals(0, fixture.run(QualcommUsbHostTrace.buildStopScript(fixture.recovery.path)))
    assertEquals("1", fixture.mask.readText().trim())
    assertEquals(0, fixture.run(QualcommUsbHostTrace.buildStartScript("fixture", fixture.recovery.path)))
    fixture.boot.writeText("next-boot\n")
    fixture.mask.writeText("8\n")
    assertEquals(0, fixture.run(QualcommUsbHostTrace.buildStopScript(fixture.recovery.path)))
    assertEquals("8", fixture.mask.readText().trim())
    assertFalse(fixture.recovery.exists())
  }

  @Test fun refusesAnUnsupportedDriverWithoutChangingLogging() {
    val fixture = Fixture("mtu3")
    assertNotEquals(0, fixture.run(QualcommUsbHostTrace.buildStartScript("fixture", fixture.recovery.path)))
    assertEquals("0\n", fixture.mask.readText())
    assertFalse(fixture.recovery.exists())
  }

  private inner class Fixture(driver: String = "msm_hsusb") {
    val base = directory.newFolder()
    val device = File(base, "udc/fixture/device").apply { mkdirs() }
    val gadget = File(device, "gadget").apply { mkdir() }
    val mask = File(gadget, "ep_addr_rxdbg_mask_enable").apply { writeText("0\n") }
    val recovery = File(base, "recovery")
    val boot = File(base, "boot").apply { writeText("initial-boot\n") }
    val uptime = File(base, "uptime").apply { writeText("1.00 3.00\n") }
    init {
      Files.createSymbolicLink(File(device, "driver").toPath(), File(base, driver).toPath())
      File(gadget, "events").writeText("")
    }
    fun run(script: String): Int {
      val adapted = script.replace("/sys/class/udc", File(base, "udc").path)
        .replace("/proc/sys/kernel/random/boot_id", boot.path)
        .replace("/proc/uptime", uptime.path)
      val process = ProcessBuilder("/bin/sh", "-c", adapted).redirectErrorStream(true).start()
      try {
        assertTrue(process.waitFor(5, TimeUnit.SECONDS))
        return process.exitValue()
      } finally { process.destroyForcibly() }
    }
  }
}
