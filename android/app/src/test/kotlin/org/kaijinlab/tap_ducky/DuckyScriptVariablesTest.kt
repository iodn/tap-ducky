package org.kaijinlab.tap_ducky

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class DuckyScriptVariablesTest {
  @Test
  fun rejectsUnsupportedWritesBeforeRunningAnyCommands() {
    for (assignment in listOf("\$_JITTER_MAX = 20", "VAR \$_BUTTON_ENABLED = TRUE")) {
      val error = assertThrows(DuckyExpressionSyntaxException::class.java) {
        DuckyScriptParser().parse("STRING sample\n$assignment")
      }
      assertEquals(2, error.lineNumber)
      assertTrue(error.message!!.contains("unavailable in TapDucky"))
    }
  }

  @Test
  fun reportsMisspelledInternalVariablesWhilePreservingAssignedNames() {
    val variables = DuckyScriptVariables({ null }, { null })
    val estimator = DuckyScriptEstimator(variables, { _, _ -> 0 }, { 0 })
    val error = assertThrows(DuckyVariableException::class.java) {
      estimator.estimate("IF (\$_BUTTON_TIMEOT == 0) THEN\nDELAY 100\nEND_IF")
    }
    assertEquals("Unknown internal variable '\$_BUTTON_TIMEOT'", error.message)
    assertEquals(25L, estimator.estimate("VAR \$_LOCAL = 25\nDELAY \$_LOCAL + \$unset"))
  }

  @Test
  fun respectsInclusiveRangesAndKeepsRandomStatePerRun() {
    val variables = DuckyScriptVariables({ null }, { null }, seed = 42)
    repeat(20) { assertTrue(variables.read("\$_RANDOM_INT")!! in 0..9) }
    variables.write("\$_RANDOM_MAX", 65535)
    variables.write("\$_RANDOM_MIN", 65535)
    assertEquals(65535, variables.read("\$_RANDOM_INT"))
    assertEquals(42, variables.read("\$_RANDOM_SEED"))
    assertEquals(0, DuckyScriptVariables({ null }, { null }).read("\$_RANDOM_MIN"))
  }

  @Test
  fun exposesLayoutModifiersWithStoredKeycodes() {
    val variables = DuckyScriptVariables({ null }, { c ->
      if (c == 'A') KeyStroke(2, 4) else null
    })
    val evaluator = ExpressionEvaluator(variables::read)
    val code = evaluator.evaluate("\$_RANDOM_UPPER_LETTER_KEYCODE", emptyMap())
    val command = DuckyScriptParser().parse("INJECT_VAR \$saved").single()
    assertEquals(CommandType.INJECT_VAR, command.type)
    assertEquals(0x0204, evaluator.evaluate(command.args.single(), mapOf("\$saved" to code)))
  }

  @Test
  fun exposesSwappedUsbIdentityAndRejectsUnsupportedReads() {
    val variables = DuckyScriptVariables(
      { name -> hak5UsbId("0x1234").takeIf { name == "\$_CURRENT_VID" } },
      { null },
    )
    val evaluator = ExpressionEvaluator(variables::read)
    assertEquals(1, evaluator.evaluate("\$_CURRENT_VID == 0x3412", emptyMap()))
    assertEquals(0x3412, hak5UsbId(" 0X1234 "))
    assertNull(hak5UsbId("0x10000"))
    assertThrows(DuckyVariableException::class.java) {
      evaluator.evaluate("\$_NUMLOCK_ON", emptyMap())
    }
    assertThrows(IllegalArgumentException::class.java) {
      DuckyScriptParser().parse("\$_CURRENT_PID = 0")
    }
  }

  @Test
  fun distinguishesConfirmedOffModeFromAProbeFailure() {
    val keyboard = GadgetManager.SessionProbe.Bound(
      "keyboard", "/dev/hidg0", null, null, "not attached", false,
    )
    assertNull(keyboard.scriptAttackMode)
    assertEquals(1, keyboard.copy(storage = false).scriptAttackMode)
    assertEquals(3, keyboard.copy(storage = true).scriptAttackMode)
    assertEquals(0, GadgetManager.SessionProbe.Unbound.scriptAttackMode)
    assertNull(GadgetManager.SessionProbe.Unknown.scriptAttackMode)
  }

  @Test
  fun surfacesUnreadableInternalVariablesInConditions() {
    val variables = DuckyScriptVariables({ null }, { null })
    val evaluator = ExpressionEvaluator(variables::read)
    variables.write("\$_RANDOM_MIN", 10)

    val invalidReads = mapOf(
      "\$_RANDOM_INT" to "\$_RANDOM_MIN exceeds \$_RANDOM_MAX",
      "\$_RANDOM_UPPER_LETTER_KEYCODE" to
        "No single-stroke characters for \$_RANDOM_UPPER_LETTER_KEYCODE in the selected layout",
      "\$_CURRENT_VID" to "\$_CURRENT_VID is unavailable for the current USB gadget",
      "\$_NUMLOCK_ON" to "\$_NUMLOCK_ON is a Hak5 variable unavailable in TapDucky",
    )
    for ((variable, expectedMessage) in invalidReads) {
      val error = assertThrows(DuckyVariableException::class.java) {
        evaluator.evaluateCondition("$variable == 0", emptyMap())
      }
      assertEquals(expectedMessage, error.message)
    }
    assertTrue(evaluator.evaluateCondition("\$_RANDOM_MIN == 10", emptyMap()))
  }

  @Test
  fun evaluatesHak5UnsignedBitwiseExpressions() {
    val evaluator = ExpressionEvaluator()
    val assignment = DuckyScriptParser().parse(
      "\$VID = (((\$VID >> 8) & 0x00FF) | ((\$VID << 8) & 0xFF00))",
    ).single()
    assertEquals(0x05ac, evaluator.evaluate(assignment.args[1], mapOf("\$VID" to 0xac05)))
    assertEquals(0x7fff, evaluator.evaluate("0xffff >> 1", emptyMap()))
    assertEquals(0, evaluator.evaluate("0x8000 << 1", emptyMap()))
    assertEquals(0, evaluator.evaluate("0xffff >> 32", emptyMap()))
    assertEquals(1, evaluator.evaluate("(1 | 2 & 6) == 3 && 1 << 2 + 1 == 8", emptyMap()))
  }

  @Test
  fun estimatesDelayFromInternalVariablesAcrossAConditionalLoop() {
    val estimator = DuckyScriptEstimator(
      DuckyScriptVariables(
        { if (it == "\$_CURRENT_VID") hak5UsbId("0x05ac") else null },
        { null },
        seed = 42,
      ),
      { _, _ -> error("This script contains no text commands") },
      { error("This script contains no key commands") },
    )
    val script = """
      ${'$'}_RANDOM_MIN = 2
      ${'$'}_RANDOM_MAX = 2
      VAR ${'$'}count = ${'$'}_RANDOM_INT
      IF (${'$'}_CURRENT_VID == 0xac05) THEN
        WHILE (${'$'}count > 0)
          DELAY ((${'$'}count << 4) + 20)
          ${'$'}count = ${'$'}count - 1
        END_WHILE
      ELSE
        DELAY 1000
      END_IF
    """.trimIndent()
    assertEquals(88L, estimator.estimate(script))
  }

  @Test
  fun evaluatesAllFunctionArgumentsInTheCallerScope() {
    val estimator = DuckyScriptEstimator(DuckyScriptVariables({ null }, { null }), { _, _ -> 0 }, { 0 })
    val script = """
      FUNCTION applyDelay(${'$'}duration, ${'$'}pause)
        DELAY ${'$'}pause
      END_FUNCTION
      FUNCTION nested(${'$'}duration)
        applyDelay(120, ${'$'}duration)
      END_FUNCTION
      VAR ${'$'}duration = 33
      nested(45)
      applyDelay(120, ${'$'}duration)
    """.trimIndent()
    assertEquals(78L, estimator.estimate(script))
  }

  @Test
  fun usesTheSameVariableNamesForDeclarationsAssignmentsAndReads() {
    val estimator = DuckyScriptEstimator(DuckyScriptVariables({ null }, { null }), { _, _ -> 0 }, { 0 })
    val script = """
      VAR ${'$'}2seconds
      ${'$'}2seconds = 2000
      VAR ${'$'}pause ${'$'}2seconds + 30
      DELAY ${'$'}pause
    """.trimIndent()
    assertEquals(2030L, estimator.estimate(script))

    for (line in listOf("VAR \$bad-name = 20", "VAR \$pause =", "\$pause =")) {
      val error = assertThrows(DuckyExpressionSyntaxException::class.java) {
        estimator.estimate("REM sample\n$line")
      }
      assertEquals(2, error.lineNumber)
    }
  }

  @Test
  fun reportsUnavailableVariableFromAnElseIfDuringEstimation() {
    val estimator = DuckyScriptEstimator(DuckyScriptVariables({ null }, { null }), { _, _ -> 0 }, { 0 })
    val script = """
      IF FALSE THEN
        DELAY 1000
      ELSE IF (${'$'}_CURRENT_PID == 0) THEN
        DELAY 20
      ELSE
        DELAY 2000
      END_IF
    """.trimIndent()
    val error = assertThrows(DuckyVariableException::class.java) { estimator.estimate(script) }
    assertEquals("\$_CURRENT_PID is unavailable for the current USB gadget", error.message)
  }

  @Test
  fun rejectsOutOfRangeRandomBoundsBeforeClampingUserVariables() {
    val variables = DuckyScriptVariables({ null }, { null })
    val estimator = DuckyScriptEstimator(variables, { _, _ -> 0 }, { 0 })
    for ((name, value) in listOf("\$_RANDOM_MIN" to -1, "\$_RANDOM_MAX" to 65536)) {
      val error = assertThrows(DuckyVariableException::class.java) {
        estimator.estimate("$name = $value")
      }
      assertEquals("$name requires a value from 0 to 65535, got $value", error.message)
    }
    assertEquals(0, variables.read("\$_RANDOM_MIN"))
    assertEquals(9, variables.read("\$_RANDOM_MAX"))
    assertEquals(65535L, estimator.estimate("VAR \$pause = 65536\nDELAY \$pause"))
  }

  @Test
  fun rejectsOversizedIntegersInAssignmentsAndConditions() {
    val estimator = DuckyScriptEstimator(DuckyScriptVariables({ null }, { null }), { _, _ -> 0 }, { 0 })
    for (literal in listOf("2147483648", "0x100000000", "0x")) {
      val error = assertThrows(DuckyScriptValueException::class.java) {
        estimator.estimate("\$_RANDOM_MIN = $literal")
      }
      assertEquals("Invalid or out-of-range integer literal: $literal", error.message)
    }
    assertThrows(DuckyScriptValueException::class.java) {
      estimator.estimate("IF (0x100000000 == 0) THEN\nDELAY 20\nEND_IF")
    }
    assertEquals(65535, ExpressionEvaluator().evaluate("0xff00 | 255", emptyMap()))
  }

  @Test
  fun rejectsIncompleteExpressionsInsteadOfUsingTheirPrefix() {
    val variables = DuckyScriptVariables({ null }, { null })
    val estimator = DuckyScriptEstimator(variables, { _, _ -> 0 }, { 0 })
    for (expression in listOf("5 6", "(5 + 6", "5 +", "5 @ 6")) {
      assertThrows(DuckyScriptValueException::class.java) {
        estimator.estimate("\$_RANDOM_MAX = $expression")
      }
      assertEquals(9, variables.read("\$_RANDOM_MAX"))
    }
    val error = assertThrows(DuckyExpressionSyntaxException::class.java) {
      estimator.estimate("IF FALSE THEN\nDELAY 30\nELSE IF (1 == 1) 0 THEN\nDELAY 20\nEND_IF")
    }
    assertEquals(3, error.lineNumber)
    assertEquals(11, ExpressionEvaluator().evaluate("(5 + 6)", emptyMap()))
  }

  @Test
  fun checksSyntaxInUnreachableBranchesBeforeReadingUsbVariables() {
    val variables = DuckyScriptVariables({ error("USB cannot be read during syntax checks") }, { null })
    val estimator = DuckyScriptEstimator(variables, { _, _ -> 0 }, { 0 })
    val script = """
      VAR ${'$'}vendor = ${'$'}_CURRENT_VID
      IF FALSE THEN
        DELAY (100 + 20
      END_IF
    """.trimIndent()
    val error = assertThrows(DuckyExpressionSyntaxException::class.java) { estimator.estimate(script) }
    assertEquals(3, error.lineNumber)
    assertEquals("Missing closing parenthesis in expression", error.message)
    assertEquals(CommandType.STRING, DuckyScriptParser().parse("STRING (literal text").single().type)
  }

  @Test
  fun reportsZeroDivisorsOnlyWhenExpressionsAreEvaluated() {
    val estimator = DuckyScriptEstimator(DuckyScriptVariables({ null }, { null }), { _, _ -> 0 }, { 0 })
    assertEquals(30L, estimator.estimate("VAR \$rate = 2\nDELAY 60 / \$rate"))
    assertEquals(20L, estimator.estimate("IF FALSE THEN\nDELAY 1 / 0\nEND_IF\nDELAY 20"))
    for ((operator, message) in listOf("/" to "Division", "%" to "Remainder")) {
      val error = assertThrows(DuckyScriptValueException::class.java) {
        estimator.estimate("VAR \$rate = 0\nIF (60 $operator \$rate == 0) THEN\nDELAY 20\nEND_IF")
      }
      assertEquals("$message by zero in expression", error.message)
    }
  }

  @Test
  fun estimatesTheConfirmedButtonPathAndAllowsClearingTheFlag() {
    val variables = DuckyScriptVariables({ null }, { null })
    val estimator = DuckyScriptEstimator(variables, { _, _ -> 0 }, { 0 })
    val script = """
      IF ${'$'}_BUTTON_PUSH_RECEIVED THEN
        DELAY 1000
      END_IF
      WAIT_FOR_BUTTON_PRESS
      IF ${'$'}_BUTTON_PUSH_RECEIVED THEN
        DELAY 20
      END_IF
      ${'$'}_BUTTON_PUSH_RECEIVED = FALSE
    """.trimIndent()
    assertEquals(20L, estimator.estimate(script))
    assertEquals(0, variables.read("\$_BUTTON_PUSH_RECEIVED"))
    assertThrows(IllegalArgumentException::class.java) {
      DuckyScriptParser().parse("WAIT_FOR_BUTTON_PRESS 1")
    }
  }

  @Test
  fun appliesTheCurrentButtonTimeoutOnlyAfterAConfirmedPress() {
    val variables = DuckyScriptVariables({ null }, { null })
    assertEquals(1000, variables.read("\$_BUTTON_TIMEOUT"))
    variables.write("\$_BUTTON_PUSH_RECEIVED", 1)
    assertEquals(0L, variables.buttonCooldownRemainingMs(100))

    variables.recordButtonPress(500)
    variables.write("\$_BUTTON_PUSH_RECEIVED", 0)
    assertEquals(750L, variables.buttonCooldownRemainingMs(750))
    assertEquals(0L, variables.buttonCooldownRemainingMs(1500))

    variables.write("\$_BUTTON_TIMEOUT", 400)
    assertEquals(150L, variables.buttonCooldownRemainingMs(750))
    variables.write("\$_BUTTON_TIMEOUT", 0)
    assertEquals(0L, variables.buttonCooldownRemainingMs(750))
    assertThrows(DuckyVariableException::class.java) { variables.write("\$_BUTTON_TIMEOUT", -1) }
  }

  @Test
  fun acceptsOneConfirmationFromTheOwningRunBeforeItsDeadline() {
    val prompt = DuckyButtonPrompt("active-run", "current-prompt", deadlineMs = 1000)
    assertFalse(prompt.confirm("other-run", "current-prompt", nowMs = 900))
    assertFalse(prompt.confirm("active-run", "older-prompt", nowMs = 900))
    assertNull(prompt.confirmedAtMs)
    assertTrue(prompt.confirm("active-run", "current-prompt", nowMs = 999))
    assertFalse(prompt.confirm("active-run", "current-prompt", nowMs = 999))
    assertEquals(999L, prompt.confirmedAtMs)

    val expired = DuckyButtonPrompt("active-run", "next-prompt", deadlineMs = 2000)
    assertFalse(expired.confirm("active-run", "next-prompt", nowMs = 2000))
    assertNull(expired.confirmedAtMs)
  }
}
