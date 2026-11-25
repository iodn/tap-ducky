package org.kaijinlab.tap_ducky

import java.util.Locale

internal object DuckyScriptHostOs {
  const val variable = "\$_OS"
  const val detectFunction = "DETECT_OS"
  val extensionNames = setOf("OS_DETECTION", "OS_DETECT")

  // These are TapDucky's script-visible values. Hak5 publishes the symbolic names.
  private const val unknown = 0
  private val codes = mapOf(
    "UNKNOWN" to unknown,
    "WINDOWS" to 1,
    "MACOS" to 2,
    "LINUX" to 3,
    "CHROMEOS" to 4,
    "ANDROID" to 5,
    "IOS" to 6,
  )

  fun constant(name: String): Int? = codes[name]

  fun encode(fingerprint: String?): Int = constant(fingerprint?.uppercase(Locale.US).orEmpty()) ?: unknown
}
