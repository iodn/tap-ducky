package org.kaijinlab.tap_ducky

import java.util.Locale

internal object DuckyScriptHostOs {
  const val variable = "\$_OS"
  const val detectFunction = "DETECT_OS"
  val extensionNames = setOf("OS_DETECTION", "OS_DETECT")

  // Hak5 publishes the symbolic names. The integers are TapDucky's internal representation.
  private val codes = listOf("UNKNOWN", "WINDOWS", "MACOS", "LINUX", "CHROMEOS", "ANDROID", "IOS")

  fun constant(name: String): Int? = codes.indexOf(name).takeIf { it >= 0 }

  fun encode(fingerprint: String?): Int = constant(fingerprint?.uppercase(Locale.US).orEmpty()) ?: 0
}
