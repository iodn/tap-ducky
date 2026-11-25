package org.kaijinlab.tap_ducky

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class DuckyScriptHostOsTest {
  @Test
  fun comparesTheCurrentFingerprintWithHak5Names() {
    var host: String? = null
    val evaluator = ExpressionEvaluator { DuckyScriptHostOs.encode(host) }
    val os = DuckyScriptHostOs.variable
    assertEquals(1, evaluator.evaluate("$os == UNKNOWN", emptyMap()))

    for (name in listOf("windows", "macos", "linux", "chromeos", "android", "ios")) {
      host = name
      assertEquals(1, evaluator.evaluate("$os == ${name.uppercase()}", emptyMap()))
      assertEquals(0, evaluator.evaluate("$os == UNKNOWN", emptyMap()))
    }
    host = null
    assertEquals(0, evaluator.evaluate("$os == IOS", emptyMap()))
  }

  @Test
  fun adaptsImportedOsExtensionAndPreservesDelayExpressions() {
    val parser = DuckyScriptParser()
    val script = """
      EXTENSION OS_DETECTION
      FUNCTION DETECT_OS()
        ${DuckyScriptHostOs.variable} = WINDOWS
      END_FUNCTION
      END_EXTENSION
      DETECT_OS()
      IF (${DuckyScriptHostOs.variable} == MACOS) THEN
        DELAY ${'$'}pause + 30
      END_IF
    """.trimIndent()
    val commands = parser.parse(script)
    assertEquals(
      listOf(CommandType.DETECT_OS, CommandType.IF, CommandType.DELAY, CommandType.END_IF),
      commands.map { it.type },
    )
    assertEquals(6, commands.first().lineNumber)
    val delay = commands[2].args.single()
    assertEquals(50, ExpressionEvaluator().evaluate(delay, mapOf("\$pause" to 20)))
  }

  @Test
  fun reportsInvalidCallsAndWritesBeforeExecution() {
    val parser = DuckyScriptParser()
    for (script in listOf(
      "DETECT_OS(1)",
      "${DuckyScriptHostOs.variable} = WINDOWS",
      "VAR ${DuckyScriptHostOs.variable} = 0",
      "FUNCTION sample(${DuckyScriptHostOs.variable})\nEND_FUNCTION",
      "EXTENSION OS_DETECTION\nREM Missing terminator",
      "EXTENSION OTHER\nEND_EXTENSION",
    )) {
      assertThrows(script, IllegalArgumentException::class.java) { parser.parse(script) }
    }
  }
}
