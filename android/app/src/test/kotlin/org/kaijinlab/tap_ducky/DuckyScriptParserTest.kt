package org.kaijinlab.tap_ducky

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class DuckyScriptParserTest {
  @Test
  fun commentBlocksDoNotEmitCommands() {
    val commands = DuckyScriptParser().parse(
      "DEFINE REM_BLOCK ENTER\nREM_BLOCK\nSTRING ignored\nENTER\n  end_rem\nSTRING kept"
    )
    assertEquals(listOf(DuckyCommand(CommandType.STRING, listOf("kept"), 6)), commands)
  }

  @Test
  fun textOperandsRetainLiteralWhitespace() {
    val commands = DuckyScriptParser().parse(
      "  STRING  a  b \nSTRINGLN c\td  \nSTRING_DELAY  20  e\t f "
    )
    assertEquals(listOf(" a  b "), commands[0].args)
    assertEquals(listOf("c\td  "), commands[1].args)
    assertEquals(listOf("20", " e\t f "), commands[2].args)
  }

  @Test
  fun stringBlocksUseTrimmedDelimitersAndKeepLiteralContent() {
    val commands = DuckyScriptParser().parse(
      "STRINGLN\nfirst\n\n  \\END_STRINGLN \n  end_stringln\n" +
        "STRING\nsecond\n third \n end_string"
    )
    assertEquals(
      listOf(
        DuckyCommand(CommandType.STRINGLN, listOf("first\n\n  END_STRINGLN "), 1),
        DuckyCommand(CommandType.STRING, listOf("second third "), 6),
      ),
      commands,
    )
  }

  @Test
  fun emptyStringLnBlockDoesNotAppendAnEnter() {
    assertEquals(emptyList<DuckyCommand>(), DuckyScriptParser().parse("STRINGLN\nEND_STRINGLN"))
  }

  @Test
  fun unterminatedBlockRejectsTheWholeScript() {
    for ((start, end) in listOf("REM_BLOCK" to "END_REM", "STRING" to "END_STRING", "STRINGLN" to "END_STRINGLN")) {
      val error = assertThrows(IllegalArgumentException::class.java) {
        DuckyScriptParser().parse("STRING first\n$start\nSTRING next")
      }
      assertEquals("Line 2: missing $end", error.message)
    }
  }

  @Test
  fun commandNormalizationMatchesUnderscoredNames() {
    val commands = DuckyScriptParser().parse("INJECT_MOD SHIFT\nMEDIA_MUTE\nNUMPAD_1\nreturn 42")
    assertEquals(
      listOf(CommandType.INJECT_MOD, CommandType.MEDIA_MUTE, CommandType.NUMPAD_1, CommandType.RETURN),
      commands.map { it.type },
    )
    assertEquals(listOf("42"), commands.last().args)
  }

  @Test
  fun repeatBudgetAppliesAcrossTheScriptBeforePreprocessing() {
    val parser = DuckyScriptParser()
    val exact = parser.parse("STRING sample\nREPEAT 12000\nREPEAT 8000")
    assertEquals(listOf("8000"), exact.last().args)
    val cumulative = assertThrows(IllegalArgumentException::class.java) {
      parser.parse("STRING sample\nREPEAT 12000\nREPEAT 8001")
    }
    assertEquals("Line 3: REPEAT exceeds the script limit of 20000 repetitions", cumulative.message)
    for (count in listOf("0", "2147483647", "2147483648")) {
      assertThrows(IllegalArgumentException::class.java) {
        parser.parse("STRING sample\nREPEAT $count")
      }
    }
  }
}
