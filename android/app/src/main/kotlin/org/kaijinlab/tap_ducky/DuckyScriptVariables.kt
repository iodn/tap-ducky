package org.kaijinlab.tap_ducky

import kotlin.random.Random

internal open class DuckyScriptValueException(message: String) : IllegalArgumentException(message)
internal class DuckyVariableException(message: String) : DuckyScriptValueException(message)

internal class DuckyButtonPrompt(
  private val executionId: String,
  val id: String,
  val deadlineMs: Long,
) {
  var confirmedAtMs: Long? = null
    private set

  fun confirm(executionId: String, promptId: String, nowMs: Long): Boolean {
    if (this.executionId != executionId || id != promptId ||
      confirmedAtMs != null || nowMs >= deadlineMs
    ) return false
    confirmedAtMs = nowMs
    return true
  }
}

internal class DuckyScriptVariables(
  private val readUsb: (String) -> Int?,
  private val strokeFor: (Char) -> KeyStroke?,
  private val seed: Int = Random.Default.nextInt(65536),
) {
  private val random = Random(seed)
  private var randomMin = 0
  private var randomMax = 9
  private var buttonPressed = false
  private var buttonTimeoutMs = 1000
  private var lastButtonPressMs: Long? = null

  fun recordButtonPress(elapsedMs: Long) {
    lastButtonPressMs = elapsedMs
    buttonPressed = true
  }

  fun buttonCooldownRemainingMs(nowMs: Long): Long = lastButtonPressMs?.let { pressedAt ->
    (pressedAt + buttonTimeoutMs - nowMs).coerceAtLeast(0L)
  } ?: 0L

  fun read(name: String): Int? = when (name) {
    "\$_BUTTON_PUSH_RECEIVED" -> if (buttonPressed) 1 else 0
    "\$_BUTTON_TIMEOUT" -> buttonTimeoutMs
    "\$_RANDOM_MIN" -> randomMin
    "\$_RANDOM_MAX" -> randomMax
    "\$_RANDOM_SEED" -> seed
    "\$_RANDOM_INT" -> {
      if (randomMin > randomMax) throw DuckyVariableException("\$_RANDOM_MIN exceeds \$_RANDOM_MAX")
      random.nextInt(randomMin, randomMax + 1)
    }
    in randomKeySets -> {
      val keys = randomKeySets.getValue(name).mapNotNull(strokeFor)
        .filter { it.terminatorKeyCode == null }
      if (keys.isEmpty()) throw DuckyVariableException("No single-stroke characters for $name in the selected layout")
      val stroke = keys.random(random)
      (stroke.modifiers shl 8) or stroke.keyCode
    }
    in usbVariables -> readUsb(name)
      ?: throw DuckyVariableException("$name is unavailable for the current USB gadget")
    in unavailable -> throw DuckyVariableException("$name is a Hak5 variable unavailable in TapDucky")
    else -> null
  }

  fun write(name: String, value: Int): Boolean {
    when (name) {
      "\$_BUTTON_PUSH_RECEIVED" -> buttonPressed = value != 0
      "\$_BUTTON_TIMEOUT", "\$_RANDOM_MIN", "\$_RANDOM_MAX" -> {
        if (value !in 0..65535) {
          throw DuckyVariableException("$name requires a value from 0 to 65535, got $value")
        }
        when (name) {
          "\$_BUTTON_TIMEOUT" -> buttonTimeoutMs = value
          "\$_RANDOM_MIN" -> randomMin = value
          else -> randomMax = value
        }
      }
      in readOnly -> throw DuckyVariableException("$name is read-only")
      in unavailable -> throw DuckyVariableException("$name is a Hak5 variable unavailable in TapDucky")
      else -> return false
    }
    return true
  }

  companion object {
    private const val lower = "abcdefghijklmnopqrstuvwxyz"
    private const val upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    private const val digits = "0123456789"
    private const val special = "!@#\$%^&*()"
    private val randomKeySets = mapOf(
      "\$_RANDOM_LOWER_LETTER_KEYCODE" to lower,
      "\$_RANDOM_UPPER_LETTER_KEYCODE" to upper,
      "\$_RANDOM_LETTER_KEYCODE" to lower + upper,
      "\$_RANDOM_NUMBER_KEYCODE" to digits,
      "\$_RANDOM_SPECIAL_KEYCODE" to special,
      "\$_RANDOM_CHAR_KEYCODE" to lower + upper + digits + special,
    )
    private val usbVariables = setOf(
      DuckyScriptHostOs.variable, "\$_CURRENT_VID", "\$_CURRENT_PID", "\$_CURRENT_ATTACKMODE",
    )
    val readOnly = usbVariables + randomKeySets.keys + setOf("\$_RANDOM_INT", "\$_RANDOM_SEED")
    val unavailable = setOf(
      "\$_BUTTON_ENABLED",
      "\$_BUTTON_USER_DEFINED", "\$_SYSTEM_LEDS_ENABLED", "\$_STORAGE_LEDS_ENABLED",
      "\$_LED_CONTINUOUS_SHOW_STORAGE_ACTIVITY", "\$_INJECTING_LEDS_ENABLED",
      "\$_EXFIL_LEDS_ENABLED", "\$_LED_SHOW_CAPS", "\$_LED_SHOW_NUM", "\$_LED_SHOW_SCROLL",
      "\$_JITTER_ENABLED", "\$_JITTER_MAX", "\$_CAPSLOCK_ON", "\$_NUMLOCK_ON", "\$_SCROLLLOCK_ON",
      "\$_SAVED_CAPSLOCK_ON", "\$_SAVED_NUMLOCK_ON", "\$_SAVED_SCROLLLOCK_ON",
      "\$_RECEIVED_HOST_LOCK_LED_REPLY", "\$_STORAGE_ACTIVITY_TIMEOUT",
      "\$_EXFIL_MODE_ENABLED", "\$_HOST_CONFIGURATION_REQUEST_COUNT",
    )
    val reserved = readOnly + unavailable + setOf(
      "\$_BUTTON_PUSH_RECEIVED", "\$_BUTTON_TIMEOUT", "\$_RANDOM_MIN", "\$_RANDOM_MAX",
    )
  }
}

internal fun hak5UsbId(descriptor: String?): Int? {
  val hex = descriptor?.trim() ?: return null
  val digits = if (hex.startsWith("0x", ignoreCase = true)) hex.drop(2) else hex
  val id = digits.toIntOrNull(16)?.takeIf { it in 0..65535 } ?: return null
  return ((id and 0xff) shl 8) or (id shr 8)
}
