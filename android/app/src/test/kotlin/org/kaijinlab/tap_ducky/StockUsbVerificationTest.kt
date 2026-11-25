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
  fun reportsStorageOnlyWhenEveryUsbConfigurationAgrees() {
    val base = directory.newFolder()
    val gadget = File(base, "stock").apply { mkdir() }
    File(gadget, "UDC").writeText("fixture_udc\n")
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

    fun readStorage(): String {
      val shell = ProcessBuilder("/bin/sh", "-c", script).start()
      try {
        assertTrue(shell.waitFor(10, TimeUnit.SECONDS))
        assertEquals(0, shell.exitValue())
        return shell.inputStream.bufferedReader().use { it.lines().filter { line -> line.startsWith("storage=") }.findFirst().get() }
      } finally {
        shell.destroyForcibly()
      }
    }

    assertEquals("storage=0", readStorage())
    Files.createSymbolicLink(File(second, storage.name).toPath(), storage.toPath())
    assertEquals("storage=unknown", readStorage())
    Files.createSymbolicLink(File(first, storage.name).toPath(), storage.toPath())
    assertEquals("storage=1", readStorage())
    Files.delete(File(second, keyboard.name).toPath())
    assertEquals("storage=unknown", readStorage())
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

  private class Fixture(
    private val root: File,
    private val attached: Boolean = false,
    canPause: Boolean = true,
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

    fun verify(): Pair<Int, String> {
      assumeTrue(File("/bin/sh").canExecute())
      val layout = """
        mode=
        sys.usb.config=adb
        sys.usb.state=adb
        persist.sys.usb.config=adb
        UDC=fixture_udc
        idProduct=0x0001
        configs/b.1/bmAttributes=0x80
        configs/b.1/MaxPower=500
      """.trimIndent()
      val verify = Configfs.buildVerifyStockLayoutScript("stock", layout, marker.path)
        .replace("G=\"/config/usb_gadget/", "G=\"${root.path}/")
      val fixture = """
        usb_quiet() { [ "${if (attached) "yes" else "no"}" = no ]; }
        usb_controller_detached() { usb_quiet || [ "${'$'}(cat '${status.path}')" = disabled-force ]; }
        getprop() { echo adb; }
        dumpsys() { printf 'usb_data_status=%s\n' "${'$'}(cat '${status.path}')"; }
        sleep() { :; }
        svc() {
          echo "${'$'}*" >> '${commands.path}'
          case "${'$'}*" in
            'usb enableUsbDataSignal false') echo disabled-force > '${status.path}' ;;
            'usb enableUsbDataSignal true') echo enabled > '${status.path}' ;;
          esac
        }
      """.trimIndent()
      val shell = ProcessBuilder("/bin/sh", "-c", "$fixture\n$verify").redirectErrorStream(true).start()
      try {
        assertTrue(shell.waitFor(5, TimeUnit.SECONDS))
        return shell.exitValue() to shell.inputStream.bufferedReader().readText()
      } finally {
        shell.destroyForcibly()
      }
    }
  }
}
