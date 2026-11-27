package org.kaijinlab.tap_ducky

import java.io.File
import java.nio.file.Files
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class StockUsbVerificationTest {
  @get:Rule val directory = TemporaryFolder()

  @Test
  fun reportsUsbModeOnlyWhenEveryConfigurationAgrees() {
    val base = directory.newFolder()
    val gadget = File(base, "stock").apply { mkdir() }
    val udc = File(gadget, "UDC").apply { writeText("fixture_udc\n") }
    File(gadget, "idVendor").writeText("0x1234\n")
    File(gadget, "idProduct").writeText("0x5678\n")
    val keyboard = File(gadget, "functions/hid.tapducky0").apply { mkdirs() }
    File(keyboard, "protocol").writeText("1\n")
    val storage = File(gadget, "functions/mass_storage.0").apply { mkdirs() }
    val first = File(gadget, "configs/b.1").apply { mkdirs() }
    val second = File(gadget, "configs/b.2").apply { mkdirs() }
    Files.createSymbolicLink(File(first, keyboard.name).toPath(), keyboard.toPath())
    Files.createSymbolicLink(File(second, keyboard.name).toPath(), keyboard.toPath())
    val script = Configfs.buildProbeSessionScript("stock", shared = true)
      .replace("/config/usb_gadget /sys/kernel/config/usb_gadget", "'${base.path}'")

    fun readProbe(): List<String> {
      val shell = ProcessBuilder("/bin/sh", "-c", script).start()
      try {
        assertTrue(shell.waitFor(10, TimeUnit.SECONDS))
        assertEquals(0, shell.exitValue())
        return shell.inputStream.bufferedReader().use { it.readLines() }
      } finally {
        shell.destroyForcibly()
      }
    }
    fun readMode(): String = readProbe().single { it.startsWith("attack_mode=") }

    assertEquals("attack_mode=1", readMode())
    Files.createSymbolicLink(File(second, storage.name).toPath(), storage.toPath())
    assertEquals("attack_mode=unknown", readMode())
    Files.createSymbolicLink(File(first, storage.name).toPath(), storage.toPath())
    assertEquals("attack_mode=3", readMode())
    Files.delete(File(second, keyboard.name).toPath())
    assertEquals("attack_mode=unknown", readMode())
    Files.delete(File(first, keyboard.name).toPath())
    assertEquals("attack_mode=2", readMode())

    val adb = File(gadget, "functions/ffs.adb").apply { mkdirs() }
    Files.createSymbolicLink(File(first, adb.name).toPath(), adb.toPath())
    assertEquals("attack_mode=unknown", readMode())
    Files.delete(File(first, adb.name).toPath())
    Files.delete(storage.toPath())
    assertEquals("attack_mode=unknown", readMode())
    udc.writeText("\n")
    assertEquals(listOf("unbound"), readProbe())
  }

  @Test
  fun discardsTheProbeWhenTheGadgetBindingChangesWhileReadingDescriptors() {
    val base = directory.newFolder()
    val gadget = File(base, "stock").apply { mkdir() }
    File(gadget, "UDC").writeText("original_udc\n")
    File(gadget, "idVendor").writeText("0x1234\n")
    File(gadget, "idProduct").writeText("0x5678\n")
    val probe = Configfs.buildProbeSessionScript("stock", shared = true)
      .replace("/config/usb_gadget /sys/kernel/config/usb_gadget", "'${base.path}'")
    val disconnectDuringRead = """
      cat() {
        case "${'$'}1" in
          */idVendor) printf '\n' > "${'$'}{1%/*}/UDC" ;;
        esac
        command cat "${'$'}@"
      }
    """.trimIndent()

    val shell = ProcessBuilder("/bin/sh", "-c", "$disconnectDuringRead\n$probe").start()
    try {
      assertTrue(shell.waitFor(10, TimeUnit.SECONDS))
      assertEquals(2, shell.exitValue())
      val output = shell.inputStream.bufferedReader().readText()
      assertTrue(output.contains("vid=0x1234"))
      assertFalse(output.contains("devices_ready="))
    } finally {
      shell.destroyForcibly()
    }
  }

  @Test
  fun restoresOnlyChangedPowerDescriptorsOnAnUnpluggedPhone() {
    val fixture = Fixture(directory.newFolder())
    assertEquals(0, fixture.verify().first)
    fixture.assertRestored()
    assertEquals(emptyList<String>(), fixture.calls())
  }

  @Test
  fun pausesAndResumesDataBeforeRestoringAnAttachedPhone() {
    val fixture = Fixture(directory.newFolder(), attached = true)
    assertEquals(0, fixture.verify().first)
    fixture.assertRestored()
    assertEquals(listOf("usb enableUsbDataSignal false", "usb enableUsbDataSignal true"), fixture.calls())
    assertEquals("enabled", fixture.status.readText().trim())
    assertFalse(fixture.marker.exists())
  }

  @Test
  fun defersWhenItCannotPauseAConnectedPort() {
    val fixture = Fixture(directory.newFolder(), attached = true, canPause = false)
    assertEquals(Configfs.HOST_ATTACHED_REFUSED, fixture.verify().first)
    assertEquals("0", fixture.maxPower.readText().trim())
    assertEquals("0xc0", fixture.attributes.readText().trim())
    assertFalse(fixture.marker.exists())
  }

  @Test
  fun keepsExactVerificationAndReportsOtherMismatches() {
    val fixture = Fixture(directory.newFolder())
    File(fixture.gadget, "idProduct").writeText("0x0002\n")
    val (exit, output) = fixture.verify()
    assertEquals(25, exit)
    assertTrue(output.contains("Changed: idProduct"))
    assertEquals("0", fixture.maxPower.readText().trim())
  }

  @Test
  fun disarmPreservesAdbAndMtpLinksWithOrWithoutCable() {
    for (attached in listOf(false, true)) {
      val fixture = Fixture(directory.newFolder(), attached = attached, stockMode = "mtp,adb")
      val adb = fixture.addFunction("f1", "ffs.adb")
      val mtp = fixture.addFunction("f2", "mtp.gs0")
      fixture.maxPower.writeText("500\n")
      fixture.attributes.writeText("0x80\n")
      val (snapshotExit, layout) = fixture.snapshot()
      assertEquals(0, snapshotExit)
      assertTrue(layout.contains("configs/b.1/f1="))
      assertTrue(layout.contains("configs/b.1/f2="))

      val hid = fixture.addFunction("hid.tapducky0", "hid.tapducky0")
      File(hid, "no_out_endpoint").writeText("1\n")
      val (restoreExit, restoreOutput) = fixture.restore()
      assertEquals(restoreOutput, 0, restoreExit)
      assertFalse(Files.isSymbolicLink(hid.toPath()))
      assertFalse(File(fixture.gadget, "functions/hid.tapducky0").exists())
      assertEquals(adb.toPath().toRealPath(), File(fixture.gadget, "functions/ffs.adb").toPath())
      assertEquals(mtp.toPath().toRealPath(), File(fixture.gadget, "functions/mtp.gs0").toPath())
      val (verifyExit, verifyOutput) = fixture.verify(layout)
      assertEquals(verifyOutput, 0, verifyExit)
      fixture.assertRestored()
      val calls = if (attached) listOf("usb enableUsbDataSignal false", "usb enableUsbDataSignal true") else emptyList()
      assertEquals(calls, fixture.calls())
      assertEquals("enabled", fixture.status.readText().trim())
      assertFalse(fixture.marker.exists())
    }
  }

  @Test
  fun verificationRejectsMissingAdbOrMtpLinksEvenWhenUsbModeMatches() {
    val fixture = Fixture(directory.newFolder(), stockMode = "mtp,adb")
    val adb = fixture.addFunction("f1", "ffs.adb")
    val mtp = fixture.addFunction("f2", "mtp.gs0")
    val (snapshotExit, layout) = fixture.snapshot()
    assertEquals(0, snapshotExit)

    for (link in listOf(adb, mtp)) {
      val target = Files.readSymbolicLink(link.toPath())
      Files.delete(link.toPath())
      val (exit, output) = fixture.verify(layout)
      assertEquals(output, 25, exit)
      assertTrue(output.contains("Missing: configs/b.1/${link.name}"))
      Files.createSymbolicLink(link.toPath(), target)
    }
    assertEquals(0, fixture.verify(layout).first)
  }

  private class Fixture(
    private val root: File,
    private val attached: Boolean = false,
    canPause: Boolean = true,
    private val stockMode: String = "adb",
  ) {
    val gadget = File(root, "stock")
    val status = File(root, "status").apply { writeText(if (canPause) "enabled" else "disabled-dock") }
    val marker = File(root, "restore-data")
    private val commands = File(root, "commands").apply { writeText("") }
    private val config = File(gadget, "configs/b.1").apply { mkdirs() }
    val maxPower = File(config, "MaxPower").apply { writeText("0\n") }
    val attributes = File(config, "bmAttributes").apply { writeText("0xc0\n") }

    init {
      File(gadget, "UDC").writeText("fixture_udc\n")
      File(gadget, "idProduct").writeText("0x0001\n")
    }

    fun calls(): List<String> = commands.readLines()

    fun assertRestored() {
      assertEquals("500", maxPower.readText().trim())
      assertEquals("0x80", attributes.readText().trim())
      assertEquals("fixture_udc", File(gadget, "UDC").readText().trim())
    }

    fun addFunction(link: String, name: String): File {
      val function = File(gadget, "functions/$name").apply { mkdirs() }
      return File(config, link).also {
        Files.createSymbolicLink(it.toPath(), function.toPath())
      }
    }

    fun snapshot(): Pair<Int, String> {
      val (exit, layout) = run(Configfs.buildReadStockLayoutScript("stock"))
      return exit to layout.trimEnd('\n')
    }

    fun restore(): Pair<Int, String> = run(Configfs.buildRestoreStockScript("stock", "fixture_udc", marker.path))

    fun verify(layout: String = """
        mode=
        sys.usb.config=adb
        sys.usb.state=adb
        persist.sys.usb.config=adb
        UDC=fixture_udc
        idProduct=0x0001
        configs/b.1/bmAttributes=0x80
        configs/b.1/MaxPower=500
      """.trimIndent()): Pair<Int, String> = run(Configfs.buildVerifyStockLayoutScript("stock", layout, marker.path))

    private fun run(operation: String): Pair<Int, String> {
      assumeTrue(File("/bin/sh").canExecute())
      val script = operation
        .replace("G=\"/config/usb_gadget/", "G=\"${root.path}/")
      val fixture = """
        UDC_NAME=fixture_udc
        usb_quiet() { [ "${if (attached) "yes" else "no"}" = no ]; }
        usb_controller_detached() { usb_quiet || [ "${'$'}(cat '${status.path}')" = disabled-force ]; }
        getprop() { echo '$stockMode'; }
        dumpsys() { printf 'usb_data_status=%s\n' "${'$'}(cat '${status.path}')"; }
        sleep() { :; }
        rmdir() {
          # ConfigFS attributes are virtual and do not prevent removal of a function.
          if [ "${'$'}1" = functions/hid.tapducky0 ]; then rm -f "${'$'}1/no_out_endpoint"; fi
          command rmdir "${'$'}@"
        }
        svc() {
          if [ "${'$'}*" = 'usb getFunctions' ]; then echo '${stockMode.substringBefore(",adb").takeUnless { it == "adb" }.orEmpty()}'; return; fi
          echo "${'$'}*" >> '${commands.path}'
          case "${'$'}*" in
            'usb enableUsbDataSignal false') echo disabled-force > '${status.path}' ;;
            'usb enableUsbDataSignal true') echo enabled > '${status.path}' ;;
          esac
        }
      """.trimIndent()
      val shell = ProcessBuilder("/bin/sh", "-c", "$fixture\n$script").redirectErrorStream(true).start()
      try {
        assertTrue(shell.waitFor(5, TimeUnit.SECONDS))
        return shell.exitValue() to shell.inputStream.bufferedReader().readText()
      } finally {
        shell.destroyForcibly()
      }
    }
  }
}
