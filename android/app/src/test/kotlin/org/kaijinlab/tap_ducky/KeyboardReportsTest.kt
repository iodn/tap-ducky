package org.kaijinlab.tap_ducky

import java.io.File
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class KeyboardReportsTest {
  @get:Rule val directory = TemporaryFolder()

  @Test
  fun configuredTimingScalesBothTheReportGapAndTheKeyHold() {
    val normal = KeyboardReportTiming(1.0, allowShorterTimings = false)
    val slower = KeyboardReportTiming(2.0, allowShorterTimings = false)
    assertEquals(listOf(600, 4000), normal.delaysFor(3))
    assertEquals(listOf(1200, 8000, 1200, 8000), slower.delaysFor(5))
    assertEquals(listOf(180, 1500), KeyboardReportTiming(0.1, false).delaysFor(3))
    assertEquals(normal.delaysFor(3), KeyboardReportTiming(Double.NaN, false).delaysFor(3))
  }

  @Test
  fun reportWriterKeepsLongerDelaysWhenMicrosecondSleepIsUnavailable() {
    val reports = listOf(keyboardReport(0, emptyList()), keyboardReport(0, listOf(4)), keyboardReport(0, emptyList()))
    val timing = KeyboardReportTiming(10.0, allowShorterTimings = false)
    val writes = buildKeyboardBatchWrites(reports, timing.delaysFor(reports.size), null)

    val pauses = writes.lineSequence().filter { "else sleep" in it }.toList()
    assertEquals(2, pauses.size)
    assertTrue(pauses[0].contains("then \$USLP 6000; else sleep 0.010000"))
    assertTrue(pauses[1].contains("then \$USLP 40000; else sleep 0.040000"))
  }

  @Test
  fun tapPreservesFiveHeldKeysAndModifiers() {
    val held = listOf(4, 5, 6, 7, 8)
    assertArrayEquals(byteArrayOf(2, 0, 9, 4, 5, 6, 7, 8), keyboardPressReport(2, 9, held))
    assertArrayEquals(byteArrayOf(2, 0, 4, 5, 6, 7, 8, 0), keyboardReport(2, held))
  }

  @Test
  fun aTapCannotEvictOrRetriggerAHeldKey() {
    val held = listOf(4, 5, 6, 7, 8, 9)
    val overflow = assertThrows(GadgetManager.HidWriteException::class.java) {
      keyboardPressReport(0, 10, held)
    }
    assertEquals("HID_KEY_ROLLOVER", overflow.errorCode)
    val collision = assertThrows(GadgetManager.HidWriteException::class.java) {
      keyboardPressReport(0, 9, held)
    }
    assertEquals("HID_KEY_ALREADY_HELD", collision.errorCode)
    assertArrayEquals(byteArrayOf(0, 0, 4, 5, 6, 7, 8, 9), keyboardReport(0, held))
  }

  @Test(timeout = 5000)
  fun cancelledBatchStopsBeforeItsNextReport() {
    assumeTrue(File("/bin/sh").canExecute())
    val marker = directory.newFile("run's marker")
    val first = keyboardReport(0, listOf(4))
    val second = keyboardReport(0, listOf(5))
    val writes = buildKeyboardBatchWrites(listOf(first, second), listOf(1), marker)
    val shell = ProcessBuilder("/bin/sh", "-c", """
      set -e
      exec 3>&1
      pause() { while [ -f ${shQuote(marker.path)} ]; do sleep 0.01; done; }
      USLP=pause
      $writes
    """.trimIndent()).start()

    try {
      assertArrayEquals(first, shell.inputStream.readNBytes(first.size))
      assertTrue(marker.delete())
      assertTrue(shell.waitFor(2, TimeUnit.SECONDS))
      assertEquals(KEYBOARD_BATCH_CANCELLED, shell.exitValue())
      assertEquals(-1, shell.inputStream.read())
    } finally {
      shell.destroyForcibly()
    }
  }

  @Test(timeout = 5000)
  fun watchdogStopsAWriterBlockedInsideAReport() {
    assumeTrue(File("/bin/sh").canExecute())
    val marker = directory.newFile("blocked")
    val shell = ProcessBuilder("/bin/sh", "-c", """
      set -e
      exec 3>&1
      ${keyboardBatchWatchdog(marker)}
      printf 'ready\n'
      read -r data
      printf 'unexpected\n'
    """.trimIndent()).start()

    try {
      val output = shell.inputStream.bufferedReader()
      assertEquals("ready", output.readLine())
      assertTrue(marker.delete())
      assertTrue(shell.waitFor(2, TimeUnit.SECONDS))
      assertEquals(KEYBOARD_BATCH_KILLED, shell.exitValue())
      assertEquals(null, output.readLine())
    } finally {
      shell.destroyForcibly()
    }
  }
}
