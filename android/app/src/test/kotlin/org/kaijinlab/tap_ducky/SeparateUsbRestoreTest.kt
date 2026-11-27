package org.kaijinlab.tap_ducky

import java.io.File
import java.nio.file.Files
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class SeparateUsbRestoreTest {
  @get:Rule val directory = TemporaryFolder()

  @Test fun selectsOnlyTheVerifiedController() {
    assertTrue(Configfs.useSeparateGadget("msm_hsusb"))
    for (name in listOf("16751000.usb0", "11110000.dwc3", "", "dummy_udc.0")) {
      assertFalse(Configfs.useSeparateGadget(name))
    }
  }

  @Test fun detectsExynosCapabilitiesWithoutSelectingOtherDwc3OrMediatekControllers() {
    val base = directory.newFolder()
    val parent = File(base, "platform/usb").apply { mkdirs() }
    val core = File(parent, "core").apply { mkdir() }
    val udc = File(base, "udc/fixture.dwc3").apply { mkdirs() }
    Files.createSymbolicLink(File(udc, "device").toPath(), core.toPath())
    val driver = File(core, "driver")
    Files.createSymbolicLink(driver.toPath(), File(base, "dwc3").toPath())
    val probe = Configfs.buildSeparateControllerProbe("fixture.dwc3")
      .replace("/sys/class/udc", File(base, "udc").path)
    fun checkProbe(): Int {
      val process = ProcessBuilder("/bin/sh", "-c", probe).start()
      try {
        assertTrue(process.waitFor(5, TimeUnit.SECONDS))
        return process.exitValue()
      } finally { process.destroyForcibly() }
    }
    assertNotEquals(0, checkProbe())
    for (name in listOf("usb_data_enabled", "new_data_role", "dwc3_exynos_gadget_state")) {
      File(parent, name).writeText("original\n")
    }
    assertEquals(0, checkProbe())
    assertEquals("original\n", File(parent, "usb_data_enabled").readText())
    Files.delete(driver.toPath())
    Files.createSymbolicLink(driver.toPath(), File(base, "mtu3").toPath())
    assertNotEquals(0, checkProbe())
  }

  @Test(expected = IllegalArgumentException::class)
  fun refusesControllerPathsInTheCapabilityProbe() {
    Configfs.buildSeparateControllerProbe("../other")
  }

  @Test fun refusesSeparateRestorationOnAnUnverifiedDwc3WithoutChangingBindings() {
    val base = directory.newFolder()
    val stock = File(base, "g1").apply { mkdir() }
    File(stock, "UDC").writeText("")
    val own = File(base, "gadgetfs_test").apply { mkdir() }
    File(own, "UDC").writeText("fixture.dwc3\n")
    val script = Configfs.buildSeparateRestoreScript("gadgetfs_test", "g1", "fixture.dwc3")
      .replace("/config/usb_gadget", base.path)
      .replace("/sys/class/udc", File(base, "missing-udc").path)
    val process = ProcessBuilder("/bin/sh", "-c", script).redirectErrorStream(true).start()
    try {
      assertTrue(process.waitFor(5, TimeUnit.SECONDS))
      assertEquals(Configfs.STOCK_BINDING_CHANGED, process.exitValue())
    } finally { process.destroyForcibly() }
    assertEquals("", File(stock, "UDC").readText())
    assertEquals("fixture.dwc3\n", File(own, "UDC").readText())
  }

  @Test fun restoresOnlyItsOwnGadgetAndIsIdempotent() {
    val base = directory.newFolder()
    val stock = File(base, "g1").apply { mkdir() }
    File(stock, "UDC").writeText("")
    val own = File(base, "gadgetfs_test").apply { mkdir() }
    File(own, "UDC").writeText("msm_hsusb\n")
    val config = File(own, "configs/c.1").apply { mkdirs() }
    val function = File(own, "functions/hid.usb0").apply { mkdirs() }
    Files.createSymbolicLink(File(config, "hid.usb0").toPath(), function.toPath())
    val other = File(base, "unrelated").apply { mkdir() }
    File(other, "UDC").writeText("another_controller\n")
    val script = Configfs.buildSeparateRestoreScript("gadgetfs_test", "g1", "msm_hsusb")
      .replace("/config/usb_gadget", base.path)
    // ConfigFS attributes disappear with their owning directory.
    val fixture = """
      rmdir() {
        case "${'$'}1" in '${own.path}') rm -f "${'$'}1/UDC"; command rmdir "${'$'}1/functions" "${'$'}1/configs" ;; esac
        command rmdir "${'$'}@"
      }
    """.trimIndent()
    repeat(2) {
      val process = ProcessBuilder("/bin/sh", "-c", "$fixture\n$script").redirectErrorStream(true).start()
      try {
        assertTrue(process.waitFor(5, TimeUnit.SECONDS))
        assertEquals(process.inputStream.bufferedReader().readText(), 0, process.exitValue())
      } finally { process.destroyForcibly() }
    }
    assertEquals("msm_hsusb", File(stock, "UDC").readText().trim())
    assertFalse(own.exists())
    assertEquals("another_controller\n", File(other, "UDC").readText())
  }

  @Test fun refusesAnotherControllersOwnerWithoutWriting() {
    val base = directory.newFolder()
    val stock = File(base, "g1").apply { mkdir() }
    File(stock, "UDC").writeText("")
    val other = File(base, "other").apply { mkdir() }
    File(other, "UDC").writeText("msm_hsusb\n")
    val script = Configfs.buildSeparateRestoreScript("gadgetfs_test", "g1", "msm_hsusb")
      .replace("/config/usb_gadget", base.path)
    val process = ProcessBuilder("/bin/sh", "-c", script).start()
    try {
      assertTrue(process.waitFor(5, TimeUnit.SECONDS))
      assertEquals(Configfs.STOCK_BINDING_CHANGED, process.exitValue())
    } finally { process.destroyForcibly() }
    assertEquals("", File(stock, "UDC").readText())
    assertEquals("msm_hsusb\n", File(other, "UDC").readText())
  }

  @Test fun recoversAnAlreadyUnboundGadgetBeforeReapplyingAndroidMode() {
    val base = directory.newFolder()
    val stock = File(base, "g1").apply { mkdir() }
    File(stock, "UDC").writeText("msm_hsusb\n")
    val own = File(base, "gadgetfs_test").apply { mkdir() }
    File(own, "UDC").writeText("")
    val calls = File(base, "mode-calls")
    val script = Configfs.buildSeparateRestoreScript("gadgetfs_test", "g1", "msm_hsusb", "adb")
      .replace("/config/usb_gadget", base.path)
    val fixture = """
      rmdir() {
        rm -f "${'$'}1/UDC"
        command rmdir "${'$'}@"
      }
      setprop() {
        [ ! -d '${own.path}' ] || exit 99
        printf '%s=%s\n' "${'$'}1" "${'$'}2" >> '${calls.path}'
      }
      getprop() { printf 'adb\n'; }
    """.trimIndent()
    val process = ProcessBuilder("/bin/sh", "-c", "$fixture\n$script").redirectErrorStream(true).start()
    try {
      assertTrue(process.waitFor(5, TimeUnit.SECONDS))
      assertEquals(process.inputStream.bufferedReader().readText(), 0, process.exitValue())
    } finally { process.destroyForcibly() }
    assertFalse(own.exists())
    assertEquals("msm_hsusb\n", File(stock, "UDC").readText())
    assertEquals(listOf("sys.usb.config=none", "sys.usb.config=adb"), calls.readLines())
  }
}
