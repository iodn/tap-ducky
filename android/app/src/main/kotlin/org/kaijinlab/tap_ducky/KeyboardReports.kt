package org.kaijinlab.tap_ducky

import java.io.File
import java.util.Locale
import kotlin.math.roundToInt

internal const val KEYBOARD_KEY_SLOTS = 6
internal const val KEYBOARD_BATCH_CANCELLED = 76
internal const val KEYBOARD_BATCH_KILLED = 137
internal const val DEFAULT_KEY_HOLD_US = 4000

internal class KeyboardReportTiming(factor: Double, val allowShorterTimings: Boolean) {
  val factor = (if (factor.isFinite()) factor else 1.0).coerceIn(0.1, 10.0)
  val interKeyUs = (600 * this.factor).roundToInt().coerceIn(if (allowShorterTimings) 40 else 180, 50_000)
  val estimatedReportOverheadUs = if (allowShorterTimings) 800 else 1500

  fun holdUs(requestedUs: Int = DEFAULT_KEY_HOLD_US): Int =
    (requestedUs * factor).roundToInt().coerceIn(if (allowShorterTimings) 300 else 1500, 150_000)

  fun delaysFor(reportCount: Int, requestedHoldUs: Int = DEFAULT_KEY_HOLD_US): List<Int> {
    val holdUs = holdUs(requestedHoldUs)
    return List((reportCount - 1).coerceAtLeast(0)) { index ->
      if (index % 2 == 0) interKeyUs else holdUs
    }
  }
}

internal fun keyboardReport(modifiers: Int, keys: List<Int>): ByteArray {
  require(keys.size <= KEYBOARD_KEY_SLOTS) { "A USB keyboard report holds at most $KEYBOARD_KEY_SLOTS keys" }
  return ByteArray(2 + KEYBOARD_KEY_SLOTS).apply {
    this[0] = modifiers.toByte()
    keys.forEachIndexed { index, key -> this[index + 2] = key.toByte() }
  }
}

internal fun keyboardPressReport(modifiers: Int, key: Int, heldKeys: List<Int>): ByteArray {
  if (key in heldKeys) {
    throw GadgetManager.HidWriteException(
      "HID_KEY_ALREADY_HELD",
      "Release the held key before tapping or typing it again.",
    )
  }
  if (heldKeys.size >= KEYBOARD_KEY_SLOTS) {
    throw GadgetManager.HidWriteException(
      "HID_KEY_ROLLOVER",
      "All $KEYBOARD_KEY_SLOTS keyboard slots are in use. Release a key before tapping or typing another.",
    )
  }
  return keyboardReport(modifiers, listOf(key) + heldKeys)
}

internal fun toPrintfEsc(bytes: ByteArray): String =
  bytes.joinToString(separator = "") { String.format(Locale.US, "\\%03o", it.toInt() and 0xFF) }

internal fun shQuote(value: String): String = "'" + value.replace("'", "'\\''") + "'"

internal fun keyboardBatchWatchdog(continueMarker: File): String {
  val marker = shQuote(continueMarker.path)
  // Normally the writer exits at the next guard. An interruptible HID write
  // stalled in the kernel needs a signal from outside the writer shell.
  return """
    (
      while [ -f $marker ]; do sleep 0.02; done
      sleep 0.05
      kill -KILL "${'$'}$"
    ) 3>&- >/dev/null 2>&1 &
    watchdogPid=${'$'}!
    trap 'kill "${'$'}watchdogPid" 2>/dev/null || :' EXIT
  """.trimIndent()
}

// The worker owns fd 3. The app can remove its own marker without waiting on the root shell.
internal fun buildKeyboardBatchWrites(
  reports: List<ByteArray>,
  delaysUs: List<Int>,
  continueMarker: File?,
): String = buildString {
  val guard = continueMarker?.let {
    "[ -f ${shQuote(it.path)} ] || exit $KEYBOARD_BATCH_CANCELLED\n"
  }
  for ((index, report) in reports.withIndex()) {
    if (guard != null) append(guard)
    append("printf '${toPrintfEsc(report)}' >&3\n")
    val delayUs = delaysUs.getOrNull(index) ?: 0
    if (index != reports.lastIndex && delayUs > 0) {
      val fallbackUs = maxOf(delayUs, 10_000)
      val fallbackSeconds = String.format(Locale.US, "%d.%06d", fallbackUs / 1_000_000, fallbackUs % 1_000_000)
      appendLine("if [ -n \"\$USLP\" ]; then \$USLP $delayUs; else sleep $fallbackSeconds; fi")
    }
  }
}
