package org.kaijinlab.tap_ducky

import java.util.Locale
import java.util.Calendar
import java.util.regex.Pattern
import kotlin.random.Random

internal const val MAX_SCRIPT_REPEATS = 20_000

data class DuckyCommand(
  val type: CommandType,
  val args: List<String> = emptyList(),
  val lineNumber: Int = 0
)

enum class CommandType {
  REM,
  REM_BLOCK_START,
  REM_BLOCK_END,
  STRING,
  STRINGLN,
  STRING_DELAY,
  STRING_BLOCK_START,
  STRING_BLOCK_END,
  STRINGLN_BLOCK_START,
  STRINGLN_BLOCK_END,
  DELAY,
  DEFAULTDELAY,
  DEFAULT_DELAY,
  KEY,
  KEYDOWN,
  KEYUP,
  HOLD,
  RELEASE,
  INJECT_MOD,
  INJECT_VAR,
  REPEAT,
  MODIFIER_COMBO,
  MOUSE_CLICK,
  MOUSE_HOLD,
  MOUSE_DRAG,
  MOUSE_MOVE,
  MOUSE_SCROLL,
  IF,
  ELSE_IF,
  ELSE,
  END_IF,
  WHILE,
  END_WHILE,
  TRY,
  CATCH,
  END_TRY,
  SLEEP_UNTIL,
  WAIT_FOR,
  WAIT_FOR_BUTTON_PRESS,
  ENABLE_BUTTON,
  DISABLE_BUTTON,
  BUTTON_DEF,
  END_BUTTON,
  FUNCTION,
  END_FUNCTION,
  RETURN,
  CALL_FUNCTION,
  DETECT_OS,
  MENU,
  APP,
  ENTER,
  ESCAPE,
  ESC,
  BACKSPACE,
  TAB,
  SPACE,
  CAPSLOCK,
  NUMLOCK,
  SCROLLLOCK,
  PRINTSCREEN,
  PAUSE,
  BREAK,
  INSERT,
  HOME,
  PAGEUP,
  PAGEDOWN,
  DELETE,
  END,
  UP,
  DOWN,
  LEFT,
  RIGHT,
  F1,
  F2,
  F3,
  F4,
  F5,
  F6,
  F7,
  F8,
  F9,
  F10,
  F11,
  F12,
  F13,
  F14,
  F15,
  F16,
  F17,
  F18,
  F19,
  F20,
  F21,
  F22,
  F23,
  F24,
  DEFINE,
  VAR,
  ATTACKMODE,
  RANDOM_LOWERCASE_LETTER,
  RANDOM_UPPERCASE_LETTER,
  RANDOM_LETTER,
  RANDOM_NUMBER,
  RANDOM_SPECIAL,
  RANDOM_CHAR,
  MEDIA_PLAYPAUSE,
  MEDIA_STOP,
  MEDIA_PREV,
  MEDIA_NEXT,
  MEDIA_VOLUMEUP,
  MEDIA_VOLUMEDOWN,
  MEDIA_MUTE,
  NUMPAD_0,
  NUMPAD_1,
  NUMPAD_2,
  NUMPAD_3,
  NUMPAD_4,
  NUMPAD_5,
  NUMPAD_6,
  NUMPAD_7,
  NUMPAD_8,
  NUMPAD_9,
  NUMPAD_PLUS,
  NUMPAD_MINUS,
  NUMPAD_MULTIPLY,
  NUMPAD_DIVIDE,
  NUMPAD_ENTER,
  NUMPAD_PERIOD,
  UNKNOWN
}

class DuckyScriptParser {
  private val defines = mutableMapOf<String, String>()
  private var definePattern: Regex? = null
  private val defineDeclaration = Regex("^DEFINE\\s+(\\S+)\\s(.*)$", RegexOption.IGNORE_CASE)
  private val modifierCommands = setOf(
    "GUI",
    "WINDOWS",
    "COMMAND",
    "SHIFT",
    "ALT",
    "CONTROL",
    "CTRL",
    "OPTION"
  )

  private val functionCallRegex = Regex("^([A-Za-z_][A-Za-z0-9_]*)\\s*\\((.*)\\)\\s*$")
  private val variableName = "\\$(?:[A-Za-z0-9_]+|\\?)"
  private val assignRegex = Regex("^($variableName)\\s*=\\s*(.*)$")
  private val varDeclRegex = Regex("^VAR\\s+($variableName)(?:\\s*=\\s*(.*)|\\s+(.+))?$", RegexOption.IGNORE_CASE)

  fun parse(script: String): List<DuckyCommand> {
    defines.clear()
    definePattern = null
    val commands = mutableListOf<DuckyCommand>()
    val lines = script.lines()
    var inRemBlock = false
    var inOsExtension = false
    var stringBlockType: CommandType? = null
    val stringBlockLines = mutableListOf<String>()
    var blockStart = 0
    var remainingRepeats = MAX_SCRIPT_REPEATS
    var lineNumber = 0

    for (raw in lines) {
      lineNumber++
      val trimmed = raw.trim()

      if (inOsExtension) {
        if (trimmed.equals("END_EXTENSION", ignoreCase = true)) inOsExtension = false
        continue
      }

      if (inRemBlock) {
        if (trimmed.equals("END_REM", ignoreCase = true)) {
          inRemBlock = false
        }
        continue
      }

      val blockType = stringBlockType
      if (blockType != null) {
        val end = "END_${blockType.name}"
        if (trimmed.equals(end, ignoreCase = true)) {
          if (stringBlockLines.isNotEmpty()) {
            val separator = if (blockType == CommandType.STRINGLN) "\n" else ""
            commands.add(DuckyCommand(blockType, listOf(stringBlockLines.joinToString(separator)), blockStart))
          }
          stringBlockType = null
          stringBlockLines.clear()
        } else {
          val text = if (trimmed.equals("\\$end", ignoreCase = true)) raw.replaceFirst("\\", "") else raw
          stringBlockLines.add(expandDefines(text))
        }
        continue
      }

      if (trimmed.isEmpty()) continue
      val sourceKeyword = trimmed.takeWhile { !it.isWhitespace() }
      when (sourceKeyword.uppercase(Locale.US)) {
        "REM" -> continue
        "DEFINE" -> {
          defineDeclaration.matchEntire(raw.trimStart())?.let { declaration ->
            defines[declaration.groupValues[1]] = declaration.groupValues[2]
            definePattern = null
          }
          continue
        }
        "REM_BLOCK" -> {
          inRemBlock = true
          blockStart = lineNumber
          continue
        }
        "EXTENSION" -> {
          val name = trimmed.drop(sourceKeyword.length).trim().uppercase(Locale.US)
          require(name in DuckyScriptHostOs.extensionNames) {
            "Line $lineNumber: unsupported extension $name"
          }
          inOsExtension = true
          blockStart = lineNumber
          continue
        }
        "END_EXTENSION" -> throw IllegalArgumentException("Line $lineNumber: END_EXTENSION without EXTENSION")
      }

      val expanded = expandDefines(raw.trimStart())
      val line = expanded.trimEnd()

      val assignMatch = assignRegex.matchEntire(line)
      if (assignMatch != null) {
        val varName = assignMatch.groupValues[1].trim()
        val expr = assignMatch.groupValues[2].trim()
        if (expr.isEmpty()) variableSyntaxError(lineNumber, "Expected a value after '='")
        requireWritableVariable(varName, lineNumber)
        commands.add(DuckyCommand(CommandType.VAR, listOf(varName, expr), lineNumber))
        continue
      }

      val parts = line.split(Pattern.compile("\\s+"))
      if (parts.isEmpty()) continue
      val cmdRaw = parts[0].uppercase(Locale.US)
      val cmd = cmdRaw.replace("_", "")

      when (cmd) {
        "REM" -> continue
        "REMBLOCK" -> {
          inRemBlock = true
          blockStart = lineNumber
        }
        "TRY" -> {
          commands.add(DuckyCommand(CommandType.TRY, emptyList(), lineNumber))
        }
        "CATCH" -> {
          commands.add(DuckyCommand(CommandType.CATCH, emptyList(), lineNumber))
        }
        "ENDTRY" -> {
          commands.add(DuckyCommand(CommandType.END_TRY, emptyList(), lineNumber))
        }
        "SLEEPUNTIL" -> {
          val arg = parts.drop(1).joinToString(" ").trim()
          commands.add(DuckyCommand(CommandType.SLEEP_UNTIL, listOf(arg), lineNumber))
        }
        "WAITFOR" -> {
          val args = parts.drop(1)
          commands.add(DuckyCommand(CommandType.WAIT_FOR, args, lineNumber))
        }
        "WAITFORBUTTONPRESS" -> {
          require(parts.size == 1) { "Line $lineNumber: WAIT_FOR_BUTTON_PRESS takes no arguments" }
          commands.add(DuckyCommand(CommandType.WAIT_FOR_BUTTON_PRESS, emptyList(), lineNumber))
        }
        "ENABLEBUTTON", "DISABLEBUTTON" -> {
          val type = if (cmd == "ENABLEBUTTON") CommandType.ENABLE_BUTTON else CommandType.DISABLE_BUTTON
          require(parts.size == 1) { "Line $lineNumber: ${type.name} takes no arguments" }
          commands.add(DuckyCommand(type, emptyList(), lineNumber))
        }
        "BUTTONDEF", "ENDBUTTON" -> {
          val type = if (cmd == "BUTTONDEF") CommandType.BUTTON_DEF else CommandType.END_BUTTON
          require(parts.size == 1) { "Line $lineNumber: ${type.name} takes no arguments" }
          commands.add(DuckyCommand(type, emptyList(), lineNumber))
        }

        "STRING", "STRINGLN" -> {
          val type = if (cmd == "STRING") CommandType.STRING else CommandType.STRINGLN
          val text = expanded.drop(parts[0].length + 1)
          if (text.isBlank()) {
            stringBlockType = type
            blockStart = lineNumber
          } else {
            commands.add(DuckyCommand(type, listOf(text), lineNumber))
          }
        }

        "STRINGDELAY" -> {
          val delayMs = parts.getOrNull(1)?.toIntOrNull() ?: 0
          val text = expanded.drop(parts[0].length).trimStart()
            .drop(parts.getOrNull(1).orEmpty().length + 1)
          commands.add(DuckyCommand(CommandType.STRING_DELAY, listOf(delayMs.toString(), text), lineNumber))
        }

        "DELAY" -> {
          val expression = line.drop(parts[0].length).trim().ifEmpty { "0" }
          commands.add(DuckyCommand(CommandType.DELAY, listOf(expression), lineNumber))
        }

        "DEFAULTDELAY" -> {
          val expression = line.drop(parts[0].length).trim()
          if (expression.isEmpty()) variableSyntaxError(lineNumber, "DEFAULT_DELAY requires a time expression")
          commands.add(DuckyCommand(CommandType.DEFAULTDELAY, listOf(expression), lineNumber))
        }

        "HOLD" -> {
          val key = parts.drop(1).joinToString(" ")
          commands.add(DuckyCommand(CommandType.HOLD, listOf(key), lineNumber))
        }

        "RELEASE" -> {
          val key = parts.drop(1).joinToString(" ")
          commands.add(DuckyCommand(CommandType.RELEASE, listOf(key), lineNumber))
        }

        "KEYDOWN" -> {
          val key = parts.drop(1).joinToString(" ")
          commands.add(DuckyCommand(CommandType.KEYDOWN, listOf(key), lineNumber))
        }

        "KEYUP" -> {
          val key = parts.drop(1).joinToString(" ")
          commands.add(DuckyCommand(CommandType.KEYUP, listOf(key), lineNumber))
        }

        "INJECTMOD" -> {
          val args = parts.drop(1)
          commands.add(DuckyCommand(CommandType.INJECT_MOD, args, lineNumber))
        }

        "INJECTVAR" -> {
          val expression = line.drop(parts[0].length).trim()
          require(expression.isNotEmpty()) { "Line $lineNumber: INJECT_VAR requires a scancode variable" }
          commands.add(DuckyCommand(CommandType.INJECT_VAR, listOf(expression), lineNumber))
        }

        "MOUSE", "POINTER" -> {
          val action = parts.getOrNull(1)?.uppercase(Locale.US) ?: ""
          when (action) {
            "CLICK" -> {
              val button = parts.getOrNull(2)?.uppercase(Locale.US) ?: ""
              val count = parts.getOrNull(3)?.toIntOrNull() ?: 1
              if (button.isNotEmpty()) {
                commands.add(DuckyCommand(CommandType.MOUSE_CLICK, listOf(button, count.toString()), lineNumber))
              } else {
                commands.add(DuckyCommand(CommandType.UNKNOWN, listOf(line), lineNumber))
              }
            }

            "HOLD" -> {
              val button = parts.getOrNull(2)?.uppercase(Locale.US) ?: ""
              val dx = parts.getOrNull(3)?.toIntOrNull() ?: 0
              val dy = parts.getOrNull(4)?.toIntOrNull() ?: 0
              val count = parts.getOrNull(5)?.toIntOrNull() ?: 1
              if (button.isNotEmpty()) {
                commands.add(DuckyCommand(CommandType.MOUSE_HOLD, listOf(button, dx.toString(), dy.toString(), count.toString()), lineNumber))
              } else {
                commands.add(DuckyCommand(CommandType.UNKNOWN, listOf(line), lineNumber))
              }
            }

            "DRAG" -> {
              val button = parts.getOrNull(2)?.uppercase(Locale.US) ?: ""
              val dx = parts.getOrNull(3)?.toIntOrNull() ?: 0
              val dy = parts.getOrNull(4)?.toIntOrNull() ?: 0
              val count = parts.getOrNull(5)?.toIntOrNull() ?: 1
              if (button.isNotEmpty()) {
                commands.add(DuckyCommand(CommandType.MOUSE_DRAG, listOf(button, dx.toString(), dy.toString(), count.toString()), lineNumber))
              } else {
                commands.add(DuckyCommand(CommandType.UNKNOWN, listOf(line), lineNumber))
              }
            }

            "MOVE" -> {
              val dx = parts.getOrNull(2)?.toIntOrNull()
              val dy = parts.getOrNull(3)?.toIntOrNull()
              val count = parts.getOrNull(4)?.toIntOrNull() ?: 1
              if (dx != null && dy != null) {
                commands.add(DuckyCommand(CommandType.MOUSE_MOVE, listOf(dx.toString(), dy.toString(), count.toString()), lineNumber))
              } else {
                commands.add(DuckyCommand(CommandType.UNKNOWN, listOf(line), lineNumber))
              }
            }

            "SCROLL" -> {
              val dir = parts.getOrNull(2)?.uppercase(Locale.US) ?: ""
              val count = parts.getOrNull(3)?.toIntOrNull() ?: 1
              if (dir == "UP" || dir == "DOWN") {
                commands.add(DuckyCommand(CommandType.MOUSE_SCROLL, listOf(dir, count.toString()), lineNumber))
              } else {
                commands.add(DuckyCommand(CommandType.UNKNOWN, listOf(line), lineNumber))
              }
            }

            else -> commands.add(DuckyCommand(CommandType.UNKNOWN, listOf(line), lineNumber))
          }
        }

        "WHILE" -> {
          val condition = extractConditionAfterKeyword(line, "WHILE", dropThen = false, dropDo = true)
          commands.add(DuckyCommand(CommandType.WHILE, listOf(condition), lineNumber))
        }

        "ENDWHILE" -> commands.add(DuckyCommand(CommandType.END_WHILE, emptyList(), lineNumber))

        "IF" -> {
          val condition = extractConditionAfterKeyword(line, "IF", dropThen = true, dropDo = false)
          commands.add(DuckyCommand(CommandType.IF, listOf(condition), lineNumber))
        }

        "ELSE" -> {
          if (parts.size > 1 && parts[1].equals("IF", ignoreCase = true)) {
            val condition = extractConditionAfterKeyword(line, "ELSE IF", dropThen = true, dropDo = false)
            commands.add(DuckyCommand(CommandType.ELSE_IF, listOf(condition), lineNumber))
          } else {
            commands.add(DuckyCommand(CommandType.ELSE, emptyList(), lineNumber))
          }
        }

        "ENDIF" -> commands.add(DuckyCommand(CommandType.END_IF, emptyList(), lineNumber))

        "FUNCTION" -> {
          val (funcName, funcArgs) = extractFunctionSignature(line)
          funcArgs.forEach {
            require(normalizeVariableName(it) !in DuckyScriptVariables.reserved) {
              "Line $lineNumber: reserved variable $it cannot be a function parameter"
            }
          }
          commands.add(DuckyCommand(CommandType.FUNCTION, listOf(funcName, *funcArgs.toTypedArray()), lineNumber))
        }

        "ENDFUNCTION" -> commands.add(DuckyCommand(CommandType.END_FUNCTION, emptyList(), lineNumber))

        "RETURN" -> {
          val value = line.drop(parts[0].length).trim()
          commands.add(DuckyCommand(CommandType.RETURN, if (value.isEmpty()) emptyList() else listOf(value), lineNumber))
        }

        "VAR" -> {
          val declaration = varDeclRegex.matchEntire(line)
            ?: variableSyntaxError(lineNumber, "VAR requires a valid variable name")
          val varName = declaration.groupValues[1]
          val expr = (declaration.groups[2]?.value ?: declaration.groups[3]?.value)?.trim()
          if (expr != null && expr.isEmpty()) variableSyntaxError(lineNumber, "Expected a value after '='")
          requireWritableVariable(varName, lineNumber)
          commands.add(DuckyCommand(CommandType.VAR, listOf(varName, expr ?: "0"), lineNumber))
        }

        "ATTACKMODE" -> commands.add(DuckyCommand(CommandType.ATTACKMODE, parts.drop(1), lineNumber))

        "REPEAT" -> {
          val count = parts.getOrNull(1)?.toIntOrNull()
          require(count != null && count in 1..MAX_SCRIPT_REPEATS) {
            "Line $lineNumber: REPEAT requires a count from 1 to $MAX_SCRIPT_REPEATS"
          }
          require(count <= remainingRepeats) {
            "Line $lineNumber: REPEAT exceeds the script limit of $MAX_SCRIPT_REPEATS repetitions"
          }
          remainingRepeats -= count
          commands.add(DuckyCommand(CommandType.REPEAT, listOf(count.toString()), lineNumber))
        }

        "RANDOMLOWERCASELETTER" -> {
          val count = parts.getOrNull(1)?.toIntOrNull() ?: 1
          commands.add(DuckyCommand(CommandType.RANDOM_LOWERCASE_LETTER, listOf(count.toString()), lineNumber))
        }

        "RANDOMUPPERCASELETTER" -> {
          val count = parts.getOrNull(1)?.toIntOrNull() ?: 1
          commands.add(DuckyCommand(CommandType.RANDOM_UPPERCASE_LETTER, listOf(count.toString()), lineNumber))
        }

        "RANDOMLETTER" -> {
          val count = parts.getOrNull(1)?.toIntOrNull() ?: 1
          commands.add(DuckyCommand(CommandType.RANDOM_LETTER, listOf(count.toString()), lineNumber))
        }

        "RANDOMNUMBER" -> {
          val count = parts.getOrNull(1)?.toIntOrNull() ?: 1
          commands.add(DuckyCommand(CommandType.RANDOM_NUMBER, listOf(count.toString()), lineNumber))
        }

        "RANDOMSPECIAL" -> {
          val count = parts.getOrNull(1)?.toIntOrNull() ?: 1
          commands.add(DuckyCommand(CommandType.RANDOM_SPECIAL, listOf(count.toString()), lineNumber))
        }

        "RANDOMCHAR" -> {
          val count = parts.getOrNull(1)?.toIntOrNull() ?: 1
          commands.add(DuckyCommand(CommandType.RANDOM_CHAR, listOf(count.toString()), lineNumber))
        }

        in modifierCommands -> {
          val upperLine = line.uppercase(Locale.US)
          commands.add(DuckyCommand(CommandType.MODIFIER_COMBO, listOf(upperLine), lineNumber))
        }

        "MENU", "APP" -> commands.add(DuckyCommand(CommandType.MENU, emptyList(), lineNumber))
        "ENTER" -> commands.add(DuckyCommand(CommandType.ENTER, emptyList(), lineNumber))
        "ESCAPE", "ESC" -> commands.add(DuckyCommand(CommandType.ESCAPE, emptyList(), lineNumber))
        "BACKSPACE", "BKSP" -> commands.add(DuckyCommand(CommandType.BACKSPACE, emptyList(), lineNumber))
        "TAB" -> commands.add(DuckyCommand(CommandType.TAB, emptyList(), lineNumber))
        "SPACE" -> commands.add(DuckyCommand(CommandType.SPACE, emptyList(), lineNumber))
        "CAPSLOCK" -> commands.add(DuckyCommand(CommandType.CAPSLOCK, emptyList(), lineNumber))
        "NUMLOCK" -> commands.add(DuckyCommand(CommandType.NUMLOCK, emptyList(), lineNumber))
        "SCROLLLOCK" -> commands.add(DuckyCommand(CommandType.SCROLLLOCK, emptyList(), lineNumber))
        "PRINTSCREEN", "PRINTSCRN", "PRTSCN" -> commands.add(DuckyCommand(CommandType.PRINTSCREEN, emptyList(), lineNumber))
        "PAUSE", "BREAK" -> commands.add(DuckyCommand(CommandType.PAUSE, emptyList(), lineNumber))
        "INSERT", "INS" -> commands.add(DuckyCommand(CommandType.INSERT, emptyList(), lineNumber))
        "HOME" -> commands.add(DuckyCommand(CommandType.HOME, emptyList(), lineNumber))
        "PAGEUP" -> commands.add(DuckyCommand(CommandType.PAGEUP, emptyList(), lineNumber))
        "PAGEDOWN" -> commands.add(DuckyCommand(CommandType.PAGEDOWN, emptyList(), lineNumber))
        "DELETE", "DEL" -> commands.add(DuckyCommand(CommandType.DELETE, emptyList(), lineNumber))
        "END" -> commands.add(DuckyCommand(CommandType.END, emptyList(), lineNumber))
        "UP", "UPARROW" -> commands.add(DuckyCommand(CommandType.UP, emptyList(), lineNumber))
        "DOWN", "DOWNARROW" -> commands.add(DuckyCommand(CommandType.DOWN, emptyList(), lineNumber))
        "LEFT", "LEFTARROW" -> commands.add(DuckyCommand(CommandType.LEFT, emptyList(), lineNumber))
        "RIGHT", "RIGHTARROW" -> commands.add(DuckyCommand(CommandType.RIGHT, emptyList(), lineNumber))
        "F1" -> commands.add(DuckyCommand(CommandType.F1, emptyList(), lineNumber))
        "F2" -> commands.add(DuckyCommand(CommandType.F2, emptyList(), lineNumber))
        "F3" -> commands.add(DuckyCommand(CommandType.F3, emptyList(), lineNumber))
        "F4" -> commands.add(DuckyCommand(CommandType.F4, emptyList(), lineNumber))
        "F5" -> commands.add(DuckyCommand(CommandType.F5, emptyList(), lineNumber))
        "F6" -> commands.add(DuckyCommand(CommandType.F6, emptyList(), lineNumber))
        "F7" -> commands.add(DuckyCommand(CommandType.F7, emptyList(), lineNumber))
        "F8" -> commands.add(DuckyCommand(CommandType.F8, emptyList(), lineNumber))
        "F9" -> commands.add(DuckyCommand(CommandType.F9, emptyList(), lineNumber))
        "F10" -> commands.add(DuckyCommand(CommandType.F10, emptyList(), lineNumber))
        "F11" -> commands.add(DuckyCommand(CommandType.F11, emptyList(), lineNumber))
        "F12" -> commands.add(DuckyCommand(CommandType.F12, emptyList(), lineNumber))
        "F13" -> commands.add(DuckyCommand(CommandType.F13, emptyList(), lineNumber))
        "F14" -> commands.add(DuckyCommand(CommandType.F14, emptyList(), lineNumber))
        "F15" -> commands.add(DuckyCommand(CommandType.F15, emptyList(), lineNumber))
        "F16" -> commands.add(DuckyCommand(CommandType.F16, emptyList(), lineNumber))
        "F17" -> commands.add(DuckyCommand(CommandType.F17, emptyList(), lineNumber))
        "F18" -> commands.add(DuckyCommand(CommandType.F18, emptyList(), lineNumber))
        "F19" -> commands.add(DuckyCommand(CommandType.F19, emptyList(), lineNumber))
        "F20" -> commands.add(DuckyCommand(CommandType.F20, emptyList(), lineNumber))
        "F21" -> commands.add(DuckyCommand(CommandType.F21, emptyList(), lineNumber))
        "F22" -> commands.add(DuckyCommand(CommandType.F22, emptyList(), lineNumber))
        "F23" -> commands.add(DuckyCommand(CommandType.F23, emptyList(), lineNumber))
        "F24" -> commands.add(DuckyCommand(CommandType.F24, emptyList(), lineNumber))

        "MEDIAPLAYPAUSE", "PLAYPAUSE" -> commands.add(DuckyCommand(CommandType.MEDIA_PLAYPAUSE, emptyList(), lineNumber))
        "MEDIASTOP", "STOPCD" -> commands.add(DuckyCommand(CommandType.MEDIA_STOP, emptyList(), lineNumber))
        "MEDIAPREV", "PREVIOUSSONG" -> commands.add(DuckyCommand(CommandType.MEDIA_PREV, emptyList(), lineNumber))
        "MEDIANEXT", "NEXTSONG" -> commands.add(DuckyCommand(CommandType.MEDIA_NEXT, emptyList(), lineNumber))
        "MEDIAVOLUMEUP", "VOLUMEUP" -> commands.add(DuckyCommand(CommandType.MEDIA_VOLUMEUP, emptyList(), lineNumber))
        "MEDIAVOLUMEDOWN", "VOLUMEDOWN" -> commands.add(DuckyCommand(CommandType.MEDIA_VOLUMEDOWN, emptyList(), lineNumber))
        "MEDIAMUTE", "MUTE" -> commands.add(DuckyCommand(CommandType.MEDIA_MUTE, emptyList(), lineNumber))

        "NUMPAD0", "KP0" -> commands.add(DuckyCommand(CommandType.NUMPAD_0, emptyList(), lineNumber))
        "NUMPAD1", "KP1" -> commands.add(DuckyCommand(CommandType.NUMPAD_1, emptyList(), lineNumber))
        "NUMPAD2", "KP2" -> commands.add(DuckyCommand(CommandType.NUMPAD_2, emptyList(), lineNumber))
        "NUMPAD3", "KP3" -> commands.add(DuckyCommand(CommandType.NUMPAD_3, emptyList(), lineNumber))
        "NUMPAD4", "KP4" -> commands.add(DuckyCommand(CommandType.NUMPAD_4, emptyList(), lineNumber))
        "NUMPAD5", "KP5" -> commands.add(DuckyCommand(CommandType.NUMPAD_5, emptyList(), lineNumber))
        "NUMPAD6", "KP6" -> commands.add(DuckyCommand(CommandType.NUMPAD_6, emptyList(), lineNumber))
        "NUMPAD7", "KP7" -> commands.add(DuckyCommand(CommandType.NUMPAD_7, emptyList(), lineNumber))
        "NUMPAD8", "KP8" -> commands.add(DuckyCommand(CommandType.NUMPAD_8, emptyList(), lineNumber))
        "NUMPAD9", "KP9" -> commands.add(DuckyCommand(CommandType.NUMPAD_9, emptyList(), lineNumber))
        "NUMPADPLUS", "KPPLUS" -> commands.add(DuckyCommand(CommandType.NUMPAD_PLUS, emptyList(), lineNumber))
        "NUMPADMINUS", "KPMINUS" -> commands.add(DuckyCommand(CommandType.NUMPAD_MINUS, emptyList(), lineNumber))
        "NUMPADMULTIPLY", "KPASTERISK" -> commands.add(DuckyCommand(CommandType.NUMPAD_MULTIPLY, emptyList(), lineNumber))
        "NUMPADDIVIDE", "KPSLASH" -> commands.add(DuckyCommand(CommandType.NUMPAD_DIVIDE, emptyList(), lineNumber))
        "NUMPADENTER", "KPENTER" -> commands.add(DuckyCommand(CommandType.NUMPAD_ENTER, emptyList(), lineNumber))
        "NUMPADPERIOD", "KPDOT" -> commands.add(DuckyCommand(CommandType.NUMPAD_PERIOD, emptyList(), lineNumber))

        else -> {
          val m = functionCallRegex.matchEntire(line)
          if (m != null) {
            val name = m.groupValues[1]
            val rawArgs = m.groupValues.getOrNull(2).orEmpty()
            if (name.equals(DuckyScriptHostOs.detectFunction, ignoreCase = true)) {
              require(rawArgs.isBlank()) { "Line $lineNumber: DETECT_OS() takes no arguments" }
              commands.add(DuckyCommand(CommandType.DETECT_OS, emptyList(), lineNumber))
            } else {
              val args = rawArgs.split(",").map { it.trim() }.filter { it.isNotEmpty() }
              commands.add(DuckyCommand(CommandType.CALL_FUNCTION, listOf(name, *args.toTypedArray()), lineNumber))
            }
          } else {
            commands.add(DuckyCommand(CommandType.UNKNOWN, listOf(line), lineNumber))
          }
        }
      }
    }

    val missingEnd = when {
      inOsExtension -> "END_EXTENSION"
      inRemBlock -> "END_REM"
      else -> stringBlockType?.let { "END_${it.name}" }
    }
    require(missingEnd == null) { "Line $blockStart: missing $missingEnd" }
    var buttonStart: Int? = null
    for (command in commands) {
      when (command.type) {
        CommandType.BUTTON_DEF -> {
          require(buttonStart == null) { "Line ${command.lineNumber}: nested BUTTON_DEF" }
          buttonStart = command.lineNumber
        }
        CommandType.END_BUTTON -> {
          require(buttonStart != null) { "Line ${command.lineNumber}: END_BUTTON without BUTTON_DEF" }
          buttonStart = null
        }
        else -> Unit
      }
    }
    require(buttonStart == null) { "Line $buttonStart: missing END_BUTTON" }
    validateExpressions(commands)
    return commands
  }

  private fun validateExpressions(commands: List<DuckyCommand>) {
    val evaluator = ExpressionEvaluator()
    for (command in commands) {
      val expressions = when (command.type) {
        CommandType.VAR, CommandType.CALL_FUNCTION -> command.args.drop(1)
        CommandType.DELAY, CommandType.DEFAULTDELAY, CommandType.DEFAULT_DELAY,
        CommandType.INJECT_VAR, CommandType.RETURN,
        CommandType.IF, CommandType.ELSE_IF, CommandType.WHILE -> command.args
        else -> continue
      }
      for (expression in expressions) {
        if (expression.isBlank()) continue
        try {
          evaluator.validateSyntax(expression)
        } catch (e: DuckyExpressionSyntaxException) {
          e.lineNumber = command.lineNumber
          throw e
        }
      }
    }
  }

  private fun normalizeVariableName(name: String): String = "\$${name.trim().removePrefix("$")}"

  private fun variableSyntaxError(line: Int, message: String): Nothing {
    throw DuckyExpressionSyntaxException(message).also { it.lineNumber = line }
  }

  private fun requireWritableVariable(name: String, lineNumber: Int) {
    val key = normalizeVariableName(name)
    if (key in DuckyScriptVariables.readOnly) {
      variableSyntaxError(lineNumber, "$name is read-only")
    }
    if (key in DuckyScriptVariables.unavailable) {
      variableSyntaxError(lineNumber, "$name is a Hak5 variable unavailable in TapDucky")
    }
  }

  private fun extractFunctionSignature(line: String): Pair<String, List<String>> {
    val trimmed = line.trim()
    val regex = Regex("^FUNCTION\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*(\\((.*)\\))?\\s*$", RegexOption.IGNORE_CASE)
    val m = regex.find(trimmed)
    if (m != null) {
      val name = m.groupValues[1]
      val rawArgs = m.groupValues.getOrNull(3).orEmpty()
      val args = rawArgs.split(",").map { it.trim() }.filter { it.isNotEmpty() }
      return name to args
    }
    val parts = trimmed.split(Pattern.compile("\\s+"))
    val raw = parts.getOrNull(1) ?: ""
    return raw.removeSuffix("()") to emptyList()
  }

  private fun extractConditionAfterKeyword(line: String, keyword: String, dropThen: Boolean, dropDo: Boolean): String {
    var rest = line.trim()
    val upper = rest.uppercase(Locale.US)
    val kwUpper = keyword.uppercase(Locale.US)
    if (upper.startsWith(kwUpper)) {
      rest = rest.substring(keyword.length).trim()
    }
    if (dropThen) rest = dropTrailingToken(rest, "THEN")
    if (dropDo) rest = dropTrailingToken(rest, "DO")
    rest = stripOuterParensIfWhole(rest.trim())
    return rest.trim()
  }

  private fun dropTrailingToken(s: String, token: String): String {
    val parts = s.trim().split(Regex("\\s+"))
    if (parts.isEmpty()) return s.trim()
    if (parts.last().equals(token, ignoreCase = true)) {
      return parts.dropLast(1).joinToString(" ").trim()
    }
    return s.trim()
  }

  private fun stripOuterParensIfWhole(s: String): String {
    val t = s.trim()
    if (t.length < 2) return t
    if (t.first() != '(' || t.last() != ')') return t
    var depth = 0
    for (i in t.indices) {
      when (t[i]) {
        '(' -> depth++
        ')' -> depth--
      }
      if (depth == 0 && i != t.lastIndex) return t
      if (depth < 0) return t
    }
    if (depth != 0) return t
    return t.substring(1, t.lastIndex).trim()
  }

  private fun expandDefines(line: String): String {
    if (defines.isEmpty()) return line
    val pattern = definePattern ?: defines.keys.sortedByDescending { it.length }
      .joinToString("|") { label ->
        val literal = Regex.escape(label)
        if (label.startsWith('#')) literal else "(?<!\\S)$literal(?!\\S)"
      }.toRegex().also { definePattern = it }
    return pattern.replace(line) { match ->
      defines.getValue(match.value)
    }
  }

  fun getDefaultDelay(): Int = 0
}

private fun endButtonIndex(commands: List<DuckyCommand>, start: Int, endExclusive: Int): Int =
  (start + 1 until endExclusive).firstOrNull { commands[it].type == CommandType.END_BUTTON }
    ?: throw IllegalArgumentException("Line ${commands[start].lineNumber}: missing END_BUTTON in this block")

private class TimingController(
  private val delayMultiplier: Double,
  private val onClamp: (String) -> Unit,
) {
  private val maxMs = 5 * 60 * 1000

  fun scaleMs(rawMs: Int, reportClamp: Boolean = true): Int {
    val scaled = (rawMs * delayMultiplier).toLong()
    val clamped = scaled.coerceIn(0, maxMs.toLong()).toInt()
    if (reportClamp && scaled != clamped.toLong()) {
      onClamp("Delay clamped from ${scaled}ms to ${clamped}ms")
    }
    return clamped
  }

  fun sleepMs(rawMs: Int) {
    val ms = scaleMs(rawMs).toLong()
    if (ms <= 0) return
    Thread.sleep(ms)
  }
}

class DuckyScriptExecutor(
  private val manager: GadgetManager,
  private val log: LogBus,
  private val delayMultiplier: Double = 1.0,
  private val executionId: String,
  private val canShowButtonPrompt: Boolean,
  private val emitExec: (Map<String, Any?>) -> Unit,
  private val shouldCancel: () -> Boolean,
) {
  private val cancelPollMs = 100L
  private var defaultDelay = 0
  private val globalVariables = mutableMapOf<String, Int>()
  private val localScopes = ArrayDeque<MutableMap<String, Int>>()
  private val functions = mutableMapOf<String, FunctionDef>()
  private val heldKeyCodes = linkedSetOf<Int>()
  private var injectedModifierMask = 0
  private var heldModifierMask = 0

  private fun activeModifierMask(): Int = injectedModifierMask or heldModifierMask
  private var heldMouseButtonsMask = 0
  private var callDepth = 0
  private val internalVariables = DuckyScriptVariables(manager::readScriptUsbVariable, manager::scriptKeyStroke)
  private var scriptButtonRegistered = false
  private var buttonBody: List<DuckyCommand>? = null
  private val evaluator = ExpressionEvaluator { name ->
    if (name == "\$_BUTTON_PUSH_RECEIVED") registerScriptButton()
    internalVariables.read(name)
  }

  private fun registerScriptButton() {
    if (canShowButtonPrompt && !scriptButtonRegistered &&
      manager.enableScriptButton(executionId, internalVariables)
    ) {
      scriptButtonRegistered = true
      updateScriptButton()
    }
  }

  private fun updateScriptButton(suspended: Boolean = false) {
    if (!scriptButtonRegistered) return
    emitExec(mapOf(
      "type" to "button_available",
      "executionId" to executionId,
      "available" to (!suspended && internalVariables.canPressScriptButton()),
    ))
  }
  private val rng = Random.Default

  private class ReturnSignal(val value: Int) : RuntimeException()
  private class CancelSignal : RuntimeException()
  private class ButtonPromptFailure(message: String) : RuntimeException(message)

  private var totalSteps = 0
  private var completedSteps = 0
  private var currentLine: Int? = null
  private val timing = TimingController(delayMultiplier) { log.log("ducky", it) }

  fun execute(script: String) {
    if (!globalVariables.containsKey("$?")) globalVariables["$?"] = 0
    val parser = DuckyScriptParser()
    val commands = parser.parse(script)
    defaultDelay = 0

    val processed = preprocessCommands(commands)
    totalSteps = processed.count { isExecutable(it.type) }.coerceAtLeast(1)
    completedSteps = 0

    emitExec(
      mapOf(
        "type" to "start",
        "executionId" to executionId,
        "total" to totalSteps,
        "completed" to completedSteps,
        "progress" to 0.0,
        "message" to "Starting",
        "timestampMs" to System.currentTimeMillis(),
      )
    )

    log.log("ducky", "=== Starting execution of ${commands.size} commands ===")

    try {
      executeRange(processed, 0, processed.size)
      internalVariables.closeScriptButtonInput()
      updateScriptButton()
      throwIfCancelled()
      runPendingButtonCallback()
      throwIfCancelled()
    } catch (e: CancelSignal) {
      manager.releaseHeldInputBestEffort()
      emitExec(
        mapOf(
          "type" to "done",
          "executionId" to executionId,
          "success" to false,
          "cancelled" to true,
          "total" to totalSteps,
          "completed" to completedSteps,
          "progress" to currentProgress(),
          "message" to "Cancelled",
          "timestampMs" to System.currentTimeMillis(),
        )
      )
      throw IllegalStateException("Execution cancelled")
    } catch (e: ReturnSignal) {
      setVar("$?", e.value)
    } catch (e: Exception) {
      log.logError("ducky", "Execution failed: ${e.message}")
      manager.releaseHeldInputBestEffort()
      emitExec(
        mapOf(
          "type" to "error",
          "executionId" to executionId,
          "message" to (e.message ?: "Execution failed"),
          "error_code" to ((e as? GadgetManager.HidWriteException)?.errorCode),
          "lineNumber" to currentLine,
          "total" to totalSteps,
          "completed" to completedSteps,
          "progress" to currentProgress(),
          "timestampMs" to System.currentTimeMillis(),
        )
      )
      throw e
    } finally {
      internalVariables.closeScriptButtonInput()
    }

    manager.releaseHeldInputBestEffort()
    log.log("ducky", "=== Execution complete ===")

    emitExec(
      mapOf(
        "type" to "done",
        "executionId" to executionId,
        "success" to true,
        "cancelled" to false,
        "total" to totalSteps,
        "completed" to completedSteps,
        "progress" to 1.0,
        "message" to "Completed",
        "timestampMs" to System.currentTimeMillis(),
      )
    )
  }

  private fun preprocessCommands(commands: List<DuckyCommand>): List<DuckyCommand> {
    val result = mutableListOf<DuckyCommand>()
    var lastAdded: DuckyCommand? = null
    var i = 0
    while (i < commands.size) {
      val cmd = commands[i]
      when (cmd.type) {
        CommandType.FUNCTION -> {
          val funcName = cmd.args.firstOrNull() ?: ""
          val funcArgs = if (cmd.args.size > 1) cmd.args.drop(1) else emptyList()
          val funcBody = mutableListOf<DuckyCommand>()
          i++
          while (i < commands.size && commands[i].type != CommandType.END_FUNCTION) {
            funcBody.add(commands[i])
            i++
          }
          functions[funcName] = FunctionDef(funcArgs, funcBody)
        }

        CommandType.BUTTON_DEF, CommandType.END_BUTTON -> {
          result.add(cmd)
          lastAdded = null
        }

        CommandType.REPEAT -> {
          val last = lastAdded
          if (last != null) {
            repeat(cmd.args.single().toInt()) {
              result.add(last)
            }
          }
        }

        else -> {
          result.add(cmd)
          lastAdded = cmd
        }
      }
      i++
    }
    return result
  }

  private fun executeRange(commands: List<DuckyCommand>, start: Int, endExclusive: Int) {
    var i = start
    while (i < endExclusive) {
      throwIfCancelled()
      runPendingButtonCallback()

      val cmd = commands[i]
      when (cmd.type) {
        CommandType.BUTTON_DEF -> {
          val end = endButtonIndex(commands, i, endExclusive)
          buttonBody = commands.subList(i + 1, end)
          internalVariables.defineButtonCallback()
          registerScriptButton()
          i = end + 1
          continue
        }
        CommandType.IF -> {
          val endIf = findMatchingEndIf(commands, i, endExclusive)
          executeIfChain(commands, i, endIf)
          i = endIf + 1
          continue
        }

        CommandType.WHILE -> {
          val endWhile = findMatchingEndWhile(commands, i, endExclusive)
          val condition = normalizeCondition(cmd.args.firstOrNull() ?: "")
          while (true) {
            throwIfCancelled()
            runPendingButtonCallback()
            if (!evaluateCondition(condition, cmd.lineNumber)) break
            executeRange(commands, i + 1, endWhile)
          }
          i = endWhile + 1
          continue
        }

        CommandType.TRY -> {
          val (catchIndex, endTry) = findMatchingEndTry(commands, i, endExclusive)
          try {
            val tryEnd = catchIndex ?: endTry
            executeRange(commands, i + 1, tryEnd)
          } catch (e: CancelSignal) {
            throw e
          } catch (e: ButtonPromptFailure) {
            throw e
          } catch (e: ReturnSignal) {
            throw e
          } catch (e: Exception) {
            if (catchIndex != null) {
              executeRange(commands, catchIndex + 1, endTry)
            } else {
              throw e
            }
          }
          i = endTry + 1
          continue
        }

        CommandType.ELSE_IF,
        CommandType.ELSE,
        CommandType.END_IF,
        CommandType.END_WHILE,
        CommandType.END_FUNCTION,
        CommandType.CATCH,
        CommandType.END_TRY -> {
          i++
          continue
        }

        else -> {
          currentLine = cmd.lineNumber
          if (requiresHost(cmd.type)) {
            if (!manager.isHostConnected()) {
              val ok = waitForPredicateCancellable(10_000L, "Waiting for USB host") { manager.isHostConnected() }
              if (!ok) {
                throw GadgetManager.HidWriteException("HOST_DISCONNECTED", "Host not connected")
              }
            }
          }
          throwIfCancelled()
          val stepMessage = executeCommand(cmd)
          throwIfCancelled()
          markStep(cmd, stepMessage)
          if (defaultDelay > 0) {
            sleepMsCancellable(timing.scaleMs(defaultDelay).toLong(), "Default script pause")
          }
        }
      }
      i++
    }
  }

  private fun throwIfCancelled() {
    if (shouldCancel()) throw CancelSignal()
  }

  private fun runPendingButtonCallback() {
    val body = buttonBody ?: return
    if (!internalVariables.beginPendingButtonCallback()) return
    val interruptedLine = currentLine
    updateScriptButton()
    try {
      executeRange(body, 0, body.size)
    } catch (r: ReturnSignal) {
      setExitCode(r.value)
    } finally {
      internalVariables.finishButtonCallback()
    }
    currentLine = interruptedLine
    updateScriptButton()
  }

  private fun reportWait(message: String, waitMs: Long, promptId: String? = null) {
    emitExec(mapOf(
      "type" to "wait",
      "executionId" to executionId,
      "lineNumber" to currentLine,
      "message" to message,
      "waitMs" to waitMs,
      "promptId" to promptId,
    ))
  }

  private fun sleepMsCancellable(totalMs: Long, label: String, dispatchButton: Boolean = true) {
    if (totalMs <= 0L) return
    if (totalMs >= 1000L) reportWait(label, totalMs)
    val deadline = android.os.SystemClock.elapsedRealtime() + totalMs
    while (true) {
      throwIfCancelled()
      if (dispatchButton) runPendingButtonCallback()
      val remaining = deadline - android.os.SystemClock.elapsedRealtime()
      if (remaining <= 0L) break
      Thread.sleep(minOf(cancelPollMs, remaining))
    }
    throwIfCancelled()
  }

  private fun waitForPredicateCancellable(
    timeoutMs: Long,
    label: String,
    pollMs: Long = 200L,
    predicate: () -> Boolean,
  ): Boolean {
    if (predicate()) return true
    val timeout = timeoutMs.coerceAtLeast(0L)
    if (timeout == 0L) return predicate()

    reportWait(label, timeout)
    val deadline = android.os.SystemClock.elapsedRealtime() + timeout
    while (true) {
      throwIfCancelled()
      runPendingButtonCallback()
      val remaining = deadline - android.os.SystemClock.elapsedRealtime()
      if (remaining <= 0L) break
      Thread.sleep(minOf(pollMs.coerceAtLeast(50L), remaining))
      if (predicate()) return true
    }
    throwIfCancelled()
    return predicate()
  }

  private fun markStep(cmd: DuckyCommand, stepMessage: String?) {
    if (!isExecutable(cmd.type)) return
    completedSteps++
    emitExec(
      mapOf(
        "type" to "step",
        "executionId" to executionId,
        "total" to totalSteps,
        "completed" to completedSteps,
        "progress" to currentProgress(),
        "lineNumber" to cmd.lineNumber,
        "command" to cmd.type.name,
        "message" to (stepMessage ?: describeCommand(cmd)),
        "timestampMs" to System.currentTimeMillis(),
      )
    )
  }

  private fun currentProgress(): Double {
    if (completedSteps >= totalSteps) return 0.99
    val ratio = completedSteps.toDouble() / totalSteps.toDouble()
    return (ratio * 0.99).coerceIn(0.0, 0.99)
  }

  private fun describeCommand(cmd: DuckyCommand): String {
    return when (cmd.type) {
      CommandType.STRING -> {
        val t = cmd.args.getOrNull(0) ?: ""
        "STRING (${t.length} chars)"
      }
      CommandType.STRINGLN -> {
        val t = cmd.args.getOrNull(0) ?: ""
        "STRINGLN (${t.length} chars)"
      }
      CommandType.STRING_DELAY -> {
        val d = timing.scaleMs(cmd.args.getOrNull(0)?.toIntOrNull() ?: 0, reportClamp = false)
        val t = cmd.args.getOrNull(1) ?: ""
        "STRING_DELAY ${d}ms per char (${t.length} chars)"
      }
      CommandType.DEFAULTDELAY,
      CommandType.DEFAULT_DELAY -> "DEFAULT_DELAY ${timing.scaleMs(defaultDelay, reportClamp = false)}ms"
      CommandType.MODIFIER_COMBO -> "COMBO ${cmd.args.getOrNull(0) ?: ""}".trim()
      CommandType.MOUSE_CLICK -> "MOUSE CLICK ${cmd.args.joinToString(" ")}".trim()
      CommandType.MOUSE_HOLD -> "MOUSE HOLD ${cmd.args.joinToString(" ")}".trim()
      CommandType.MOUSE_DRAG -> "MOUSE DRAG ${cmd.args.joinToString(" ")}".trim()
      CommandType.MOUSE_MOVE -> "MOUSE MOVE ${cmd.args.joinToString(" ")}".trim()
      CommandType.MOUSE_SCROLL -> "MOUSE SCROLL ${cmd.args.joinToString(" ")}".trim()
      CommandType.SLEEP_UNTIL -> "SLEEP_UNTIL ${cmd.args.joinToString(" ")}".trim()
      CommandType.WAIT_FOR -> "WAIT_FOR ${cmd.args.joinToString(" ")}".trim()
      else -> cmd.type.name
    }
  }

  private fun isExecutable(t: CommandType): Boolean {
    return when (t) {
      CommandType.IF,
      CommandType.WHILE,
      CommandType.ELSE_IF,
      CommandType.ELSE,
      CommandType.END_IF,
      CommandType.END_WHILE,
      CommandType.FUNCTION,
      CommandType.END_FUNCTION,
      CommandType.REM,
      CommandType.REM_BLOCK_START,
      CommandType.REM_BLOCK_END,
      CommandType.DEFINE,
      CommandType.TRY,
      CommandType.CATCH,
      CommandType.END_TRY,
      CommandType.DEFAULTDELAY,
      CommandType.DEFAULT_DELAY -> false
      else -> true
    }
  }

  private fun executeIfChain(commands: List<DuckyCommand>, ifIndex: Int, endIfIndex: Int) {
    data class Branch(val condition: String?, val start: Int, val end: Int)
    val branches = mutableListOf<Branch>()
    var currentCond: String? = normalizeCondition(commands[ifIndex].args.firstOrNull() ?: "")
    var currentStart = ifIndex + 1
    var depth = 0
    var scan = ifIndex + 1
    while (scan < endIfIndex) {
      val t = commands[scan].type
      when (t) {
        CommandType.IF -> depth++
        CommandType.END_IF -> if (depth > 0) depth--
        else -> {}
      }
      if (depth == 0 && (t == CommandType.ELSE_IF || t == CommandType.ELSE)) {
        branches.add(Branch(currentCond, currentStart, scan))
        currentCond = if (t == CommandType.ELSE_IF) normalizeCondition(commands[scan].args.firstOrNull() ?: "") else null
        currentStart = scan + 1
      }
      scan++
    }
    branches.add(Branch(currentCond, currentStart, endIfIndex))
    for (b in branches) {
      if (b.condition == null || evaluateCondition(b.condition, commands[b.start - 1].lineNumber)) {
        executeRange(commands, b.start, b.end)
        break
      }
    }
  }

  private fun findMatchingEndIf(commands: List<DuckyCommand>, start: Int, endExclusive: Int): Int {
    var depth = 1
    var i = start + 1
    while (i < endExclusive) {
      when (commands[i].type) {
        CommandType.IF -> depth++
        CommandType.END_IF -> {
          depth--
          if (depth == 0) return i
        }
        else -> {}
      }
      i++
    }
    return endExclusive - 1
  }

  private fun findMatchingEndWhile(commands: List<DuckyCommand>, start: Int, endExclusive: Int): Int {
    var depth = 1
    var i = start + 1
    while (i < endExclusive) {
      when (commands[i].type) {
        CommandType.WHILE -> depth++
        CommandType.END_WHILE -> {
          depth--
          if (depth == 0) return i
        }
        else -> {}
      }
      i++
    }
    return endExclusive - 1
  }

  private fun findMatchingEndTry(commands: List<DuckyCommand>, start: Int, endExclusive: Int): Pair<Int?, Int> {
    var depth = 1
    var i = start + 1
    var catchIndex: Int? = null
    while (i < endExclusive) {
      when (commands[i].type) {
        CommandType.TRY -> depth++
        CommandType.END_TRY -> {
          depth--
          if (depth == 0) return catchIndex to i
        }
        CommandType.CATCH -> if (depth == 1 && catchIndex == null) catchIndex = i
        else -> {}
      }
      i++
    }
    return catchIndex to (endExclusive - 1)
  }

  private fun requiresHost(t: CommandType): Boolean {
    return when (t) {
      CommandType.STRING,
      CommandType.STRINGLN,
      CommandType.STRING_DELAY,
      CommandType.MODIFIER_COMBO,
      CommandType.KEY,
      CommandType.KEYDOWN,
      CommandType.KEYUP,
      CommandType.HOLD,
      CommandType.RELEASE,
      CommandType.INJECT_MOD,
      CommandType.INJECT_VAR,
      CommandType.MOUSE_CLICK,
      CommandType.MOUSE_HOLD,
      CommandType.MOUSE_DRAG,
      CommandType.MOUSE_MOVE,
      CommandType.MOUSE_SCROLL,
      CommandType.MENU,
      CommandType.ENTER,
      CommandType.ESCAPE,
      CommandType.BACKSPACE,
      CommandType.TAB,
      CommandType.SPACE,
      CommandType.CAPSLOCK,
      CommandType.NUMLOCK,
      CommandType.SCROLLLOCK,
      CommandType.PRINTSCREEN,
      CommandType.PAUSE,
      CommandType.INSERT,
      CommandType.HOME,
      CommandType.PAGEUP,
      CommandType.PAGEDOWN,
      CommandType.DELETE,
      CommandType.END,
      CommandType.UP,
      CommandType.DOWN,
      CommandType.LEFT,
      CommandType.RIGHT,
      CommandType.F1,
      CommandType.F2,
      CommandType.F3,
      CommandType.F4,
      CommandType.F5,
      CommandType.F6,
      CommandType.F7,
      CommandType.F8,
      CommandType.F9,
      CommandType.F10,
      CommandType.F11,
      CommandType.F12,
      CommandType.F13,
      CommandType.F14,
      CommandType.F15,
      CommandType.F16,
      CommandType.F17,
      CommandType.F18,
      CommandType.F19,
      CommandType.F20,
      CommandType.F21,
      CommandType.F22,
      CommandType.F23,
      CommandType.F24,
      CommandType.MEDIA_PLAYPAUSE,
      CommandType.MEDIA_STOP,
      CommandType.MEDIA_PREV,
      CommandType.MEDIA_NEXT,
      CommandType.MEDIA_VOLUMEUP,
      CommandType.MEDIA_VOLUMEDOWN,
      CommandType.MEDIA_MUTE,
      CommandType.NUMPAD_0,
      CommandType.NUMPAD_1,
      CommandType.NUMPAD_2,
      CommandType.NUMPAD_3,
      CommandType.NUMPAD_4,
      CommandType.NUMPAD_5,
      CommandType.NUMPAD_6,
      CommandType.NUMPAD_7,
      CommandType.NUMPAD_8,
      CommandType.NUMPAD_9,
      CommandType.NUMPAD_PLUS,
      CommandType.NUMPAD_MINUS,
      CommandType.NUMPAD_MULTIPLY,
      CommandType.NUMPAD_DIVIDE,
      CommandType.NUMPAD_ENTER,
      CommandType.NUMPAD_PERIOD -> true
      else -> false
    }
  }

  private fun normalizeCondition(raw: String): String {
    var s = raw.trim()
    if (s.isEmpty()) return "FALSE"
    s = stripOuterParensIfWhole(s)
    return s
  }

  private fun computeSleepUntilMs(arg: String): Int {
    val trimmed = arg.trim()
    if (trimmed.isEmpty()) return 0
    if (trimmed.all { it.isDigit() }) {
      val v = trimmed.toLongOrNull() ?: return 0
      val ms = if (trimmed.length >= 10) {
        v - System.currentTimeMillis()
      } else {
        v
      }
      return ms.coerceAtLeast(0L).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
    }
    val now = Calendar.getInstance()
    val parts = trimmed.split(":")
    val h = parts.getOrNull(0)?.toIntOrNull()
    val m = parts.getOrNull(1)?.toIntOrNull()
    val s = parts.getOrNull(2)?.toIntOrNull() ?: 0
    if (h == null || m == null) return 0

    val target = Calendar.getInstance().apply {
      timeInMillis = now.timeInMillis
      set(Calendar.HOUR_OF_DAY, h)
      set(Calendar.MINUTE, m)
      set(Calendar.SECOND, s)
      set(Calendar.MILLISECOND, 0)
    }

    if (target.before(now) || target == now) {
      target.add(Calendar.DAY_OF_MONTH, 1)
    }
    val duration = target.timeInMillis - now.timeInMillis
    return duration.coerceAtLeast(0L).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
  }

  private fun stripOuterParensIfWhole(s: String): String {
    val t = s.trim()
    if (t.length < 2) return t
    if (t.first() != '(' || t.last() != ')') return t
    var depth = 0
    for (i in t.indices) {
      when (t[i]) {
        '(' -> depth++
        ')' -> depth--
      }
      if (depth == 0 && i != t.lastIndex) return t
      if (depth < 0) return t
    }
    if (depth != 0) return t
    return t.substring(1, t.lastIndex).trim()
  }

  private fun evaluateCondition(condition: String, lineNumber: Int): Boolean {
    currentLine = lineNumber
    return evaluator.evaluateCondition(condition, currentVarsView()) {
      log.logError("ducky", "Failed to evaluate condition: $condition")
    }
  }

  private fun clampU16(v: Int): Int = v.coerceIn(0, 65535)

  private fun setExitCode(v: Int) {
    setVar("$?", v)
  }

  private fun randomFrom(chars: String, count: Int): String {
    val n = count.coerceAtLeast(1)
    val sb = StringBuilder(n)
    repeat(n) {
      val idx = rng.nextInt(chars.length)
      sb.append(chars[idx])
    }
    return sb.toString()
  }

  private fun managerUpdateAttackMode(args: List<String>): Boolean {
    val candidates = listOf("updateAttackMode", "setAttackMode", "attackMode", "setMode")
    if (tryInvokeAny(candidates, listOf(args))) return true
    if (tryInvokeAny(candidates, listOf(args.toTypedArray()))) return true
    if (tryInvokeAny(candidates, listOf(args.joinToString(" ")))) return true
    return false
  }

  private fun managerSendMediaKey(code: String): Boolean {
    val c = code.uppercase(Locale.US)
    val sent = manager.sendMediaKey(c)
    if (!sent) log.log("media", "Media key unavailable: $c")
    return sent
  }

  private fun executeCommand(cmd: DuckyCommand): String? {
    when (cmd.type) {
      CommandType.STRING -> {
        val text = cmd.args.getOrNull(0) ?: ""
        if (text.isNotEmpty()) manager.typeString(text, 0, activeModifierMask(), extraKeys = heldKeyCodes.toList(), shouldCancel = shouldCancel)
        setExitCode(0)
      }

      CommandType.STRINGLN -> {
        val text = cmd.args.getOrNull(0) ?: ""
        manager.typeString(text, 0, activeModifierMask(), extraKeys = heldKeyCodes.toList(), shouldCancel = shouldCancel)
        throwIfCancelled()
        sendKeyWithInjectedMods("ENTER")
        setExitCode(0)
      }

      CommandType.STRING_DELAY -> {
        val delayMs = cmd.args.getOrNull(0)?.toIntOrNull() ?: 0
        val adjustedDelayMs = timing.scaleMs(delayMs)
        val text = cmd.args.getOrNull(1) ?: ""
        manager.typeString(text, adjustedDelayMs, activeModifierMask(), extraKeys = heldKeyCodes.toList(), shouldCancel = shouldCancel)
        setExitCode(0)
      }

      CommandType.DELAY -> {
        val delayMs = timing.scaleMs(evaluator.evaluate(cmd.args.first(), currentVarsView()))
        sleepMsCancellable(delayMs.toLong(), "Script pause")
        setExitCode(0)
        return "DELAY ${delayMs}ms"
      }

      CommandType.DETECT_OS -> {
        waitForPredicateCancellable(10_000L, "Detecting host OS") { !manager.isScriptHostOsPending() }
        setExitCode(0)
      }

      CommandType.WAIT_FOR_BUTTON_PRESS -> {
        if (!canShowButtonPrompt) {
          throw ButtonPromptFailure("WAIT_FOR_BUTTON_PRESS requires a run started in the TapDucky app")
        }
        val waitMs = 60_000L
        val prompt = manager.beginButtonPrompt(executionId, waitMs, internalVariables)
        updateScriptButton(suspended = true)
        try {
          sleepMsCancellable(prompt.cooldownMs, "Button cooldown", dispatchButton = false)
          throwIfCancelled()
          reportWait("Waiting for you to press Continue", waitMs, prompt.id)
          val confirmedAtMs: Long
          while (true) {
            throwIfCancelled()
            val remaining = prompt.deadlineMs - android.os.SystemClock.elapsedRealtime()
            val acceptedAtMs = manager.buttonPromptConfirmedAt(prompt.id)
            if (acceptedAtMs != null) {
              confirmedAtMs = acceptedAtMs
              break
            }
            if (remaining <= 0) throw ButtonPromptFailure("Continue was not pressed on the phone")
            Thread.sleep(minOf(cancelPollMs, remaining))
          }
          throwIfCancelled()
          internalVariables.recordButtonPress(confirmedAtMs)
          setExitCode(0)
        } finally {
          manager.endButtonPrompt(prompt.id)
        }
        updateScriptButton()
      }

      CommandType.ENABLE_BUTTON, CommandType.DISABLE_BUTTON -> {
        setVar(DuckyScriptVariables.BUTTON_ENABLED, if (cmd.type == CommandType.ENABLE_BUTTON) 1 else 0)
        setExitCode(0)
      }

      CommandType.SLEEP_UNTIL -> {
        val arg = cmd.args.firstOrNull().orEmpty()
        val ms = computeSleepUntilMs(arg)
        val relative = arg.trim().let { it.length < 10 && it.all(Char::isDigit) }
        val durationMs = if (relative) timing.scaleMs(ms) else ms
        sleepMsCancellable(durationMs.toLong(), "Scheduled wait")
        setExitCode(0)
      }

      CommandType.WAIT_FOR -> {
        val target = cmd.args.firstOrNull()?.uppercase(Locale.US) ?: ""
        val timeoutMs = cmd.args.getOrNull(1)?.toIntOrNull() ?: 15000
        val label = "Waiting for $target"
        val ok = when (target) {
          "HOST_CONNECTED", "HOST" -> waitForPredicateCancellable(timeoutMs.toLong(), label) { manager.isHostConnected() }
          "UDC_CONFIGURED", "UDC" -> waitForPredicateCancellable(timeoutMs.toLong(), label) { manager.isUdcConfigured() }
          "KEYBOARD_READY", "KBD_READY" -> waitForPredicateCancellable(timeoutMs.toLong(), label) { manager.isKeyboardWriterReady() }
          "MOUSE_READY" -> waitForPredicateCancellable(timeoutMs.toLong(), label) { manager.isMouseWriterReady() }
          "SESSION_ARMED", "ACTIVE" -> waitForPredicateCancellable(timeoutMs.toLong(), label) { manager.isActive() }
          "" -> true
          else -> throw IllegalArgumentException("WAIT_FOR unsupported target: $target")
        }
        if (!ok) {
          throw GadgetManager.HidWriteException("WAIT_FOR_TIMEOUT", "WAIT_FOR $target timed out")
        }
        setExitCode(0)
      }

      CommandType.DEFAULTDELAY,
      CommandType.DEFAULT_DELAY -> {
        defaultDelay = evaluator.evaluate(cmd.args.first(), currentVarsView())
        setExitCode(0)
      }

      CommandType.HOLD -> {
        val key = cmd.args.firstOrNull() ?: ""
        applyHoldRelease(key, isHold = true)
        setExitCode(0)
      }

      CommandType.RELEASE -> {
        val key = cmd.args.firstOrNull() ?: ""
        applyHoldRelease(key, isHold = false)
        setExitCode(0)
      }

      CommandType.KEYDOWN -> {
        val key = cmd.args.firstOrNull() ?: ""
        applyHoldRelease(key, isHold = true)
        setExitCode(0)
      }

      CommandType.KEYUP -> {
        val key = cmd.args.firstOrNull() ?: ""
        applyHoldRelease(key, isHold = false)
        setExitCode(0)
      }

      CommandType.INJECT_MOD -> {
        val tokens = cmd.args
        val joined = tokens.joinToString(" ").trim()
        val previousMask = activeModifierMask()
        injectedModifierMask = when (joined.uppercase(Locale.US)) {
          "", "CLEAR", "NONE", "OFF", "0" -> 0
          else -> parseModifierMask(tokens)
        }
        if (activeModifierMask() != previousMask) {
          manager.writeKeyboardReport(activeModifierMask(), heldKeyCodes.toList())
        }
        setExitCode(0)
      }

      CommandType.INJECT_VAR -> {
        val stroke = decodeDuckyKeyStroke(evaluator.evaluate(cmd.args.first(), currentVarsView()))
        sendKeyWithInjectedMods(stroke.keyCode, stroke.modifiers)
        setExitCode(0)
      }

      CommandType.MODIFIER_COMBO -> {
        val line = cmd.args.firstOrNull() ?: ""
        executeModifierCombo(line)
        setExitCode(0)
      }

      CommandType.CALL_FUNCTION -> {
        val name = cmd.args.firstOrNull() ?: ""
        val args = if (cmd.args.size > 1) cmd.args.drop(1) else emptyList()
        callFunction(name, args)
      }

      CommandType.RETURN -> {
        val expr = cmd.args.firstOrNull() ?: "0"
        val value = if (expr.isBlank()) 0 else evaluator.evaluate(expr, currentVarsView())
        throw ReturnSignal(clampU16(value))
      }

      CommandType.VAR -> {
        val varName = cmd.args.getOrNull(0) ?: ""
        val expr = cmd.args.getOrNull(1) ?: "0"
        val value = if (expr.isBlank()) 0 else evaluator.evaluate(expr, currentVarsView())
        setVar(varName, value)
        setExitCode(0)
      }

      CommandType.RANDOM_LOWERCASE_LETTER -> {
        val count = cmd.args.firstOrNull()?.toIntOrNull() ?: 1
        manager.typeString(randomFrom("abcdefghijklmnopqrstuvwxyz", count), 0, activeModifierMask(), extraKeys = heldKeyCodes.toList(), shouldCancel = shouldCancel)
        setExitCode(0)
      }

      CommandType.RANDOM_UPPERCASE_LETTER -> {
        val count = cmd.args.firstOrNull()?.toIntOrNull() ?: 1
        manager.typeString(randomFrom("ABCDEFGHIJKLMNOPQRSTUVWXYZ", count), 0, activeModifierMask(), extraKeys = heldKeyCodes.toList(), shouldCancel = shouldCancel)
        setExitCode(0)
      }

      CommandType.RANDOM_LETTER -> {
        val count = cmd.args.firstOrNull()?.toIntOrNull() ?: 1
        manager.typeString(randomFrom("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ", count), 0, activeModifierMask(), extraKeys = heldKeyCodes.toList(), shouldCancel = shouldCancel)
        setExitCode(0)
      }

      CommandType.RANDOM_NUMBER -> {
        val count = cmd.args.firstOrNull()?.toIntOrNull() ?: 1
        manager.typeString(randomFrom("0123456789", count), 0, activeModifierMask(), extraKeys = heldKeyCodes.toList(), shouldCancel = shouldCancel)
        setExitCode(0)
      }

      CommandType.RANDOM_SPECIAL -> {
        val count = cmd.args.firstOrNull()?.toIntOrNull() ?: 1
        manager.typeString(randomFrom("!@#$%^&*()-_=+[]{};:'\",.<>/?\\|`~", count), 0, activeModifierMask(), extraKeys = heldKeyCodes.toList(), shouldCancel = shouldCancel)
        setExitCode(0)
      }

      CommandType.RANDOM_CHAR -> {
        val count = cmd.args.firstOrNull()?.toIntOrNull() ?: 1
        manager.typeString(randomFrom("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()-_=+[]{};:'\",.<>/?\\|`~", count), 0, activeModifierMask(), extraKeys = heldKeyCodes.toList(), shouldCancel = shouldCancel)
        setExitCode(0)
      }

      CommandType.ATTACKMODE -> {
        managerUpdateAttackMode(cmd.args)
        setExitCode(0)
      }

      CommandType.MOUSE_CLICK -> {
        val button = cmd.args.getOrNull(0) ?: ""
        val count = cmd.args.getOrNull(1)?.toIntOrNull() ?: 1
        mouseClick(button, count)
        setExitCode(0)
      }

      CommandType.MOUSE_HOLD -> {
        val button = cmd.args.getOrNull(0) ?: ""
        val dx = cmd.args.getOrNull(1)?.toIntOrNull() ?: 0
        val dy = cmd.args.getOrNull(2)?.toIntOrNull() ?: 0
        val count = cmd.args.getOrNull(3)?.toIntOrNull() ?: 1
        mouseHold(button, dx, dy, count)
        setExitCode(0)
      }

      CommandType.MOUSE_DRAG -> {
        val button = cmd.args.getOrNull(0) ?: ""
        val dx = cmd.args.getOrNull(1)?.toIntOrNull() ?: 0
        val dy = cmd.args.getOrNull(2)?.toIntOrNull() ?: 0
        val count = cmd.args.getOrNull(3)?.toIntOrNull() ?: 1
        mouseDrag(button, dx, dy, count)
        setExitCode(0)
      }

      CommandType.MOUSE_MOVE -> {
        val dx = cmd.args.getOrNull(0)?.toIntOrNull() ?: 0
        val dy = cmd.args.getOrNull(1)?.toIntOrNull() ?: 0
        val count = cmd.args.getOrNull(2)?.toIntOrNull() ?: 1
        mouseMove(dx, dy, count)
        setExitCode(0)
      }

      CommandType.MOUSE_SCROLL -> {
        val dir = cmd.args.getOrNull(0) ?: "UP"
        val count = cmd.args.getOrNull(1)?.toIntOrNull() ?: 1
        mouseScroll(dir, count)
        setExitCode(0)
      }

      CommandType.MENU -> { sendKeyWithInjectedMods("MENU"); setExitCode(0) }
      CommandType.ENTER -> { sendKeyWithInjectedMods("ENTER"); setExitCode(0) }
      CommandType.ESCAPE -> { sendKeyWithInjectedMods("ESCAPE"); setExitCode(0) }
      CommandType.BACKSPACE -> { sendKeyWithInjectedMods("BACKSPACE"); setExitCode(0) }
      CommandType.TAB -> { sendKeyWithInjectedMods("TAB"); setExitCode(0) }
      CommandType.SPACE -> { sendKeyWithInjectedMods("SPACE"); setExitCode(0) }
      CommandType.CAPSLOCK -> { sendKeyWithInjectedMods("CAPSLOCK"); setExitCode(0) }
      CommandType.NUMLOCK -> { sendKeyWithInjectedMods("NUMLOCK"); setExitCode(0) }
      CommandType.SCROLLLOCK -> { sendKeyWithInjectedMods("SCROLLLOCK"); setExitCode(0) }
      CommandType.PRINTSCREEN -> { sendKeyWithInjectedMods("PRINTSCREEN"); setExitCode(0) }
      CommandType.PAUSE -> { sendKeyWithInjectedMods("PAUSE"); setExitCode(0) }
      CommandType.INSERT -> { sendKeyWithInjectedMods("INSERT"); setExitCode(0) }
      CommandType.HOME -> { sendKeyWithInjectedMods("HOME"); setExitCode(0) }
      CommandType.PAGEUP -> { sendKeyWithInjectedMods("PAGEUP"); setExitCode(0) }
      CommandType.PAGEDOWN -> { sendKeyWithInjectedMods("PAGEDOWN"); setExitCode(0) }
      CommandType.DELETE -> { sendKeyWithInjectedMods("DELETE"); setExitCode(0) }
      CommandType.END -> { sendKeyWithInjectedMods("END"); setExitCode(0) }
      CommandType.UP -> { sendKeyWithInjectedMods("UP"); setExitCode(0) }
      CommandType.DOWN -> { sendKeyWithInjectedMods("DOWN"); setExitCode(0) }
      CommandType.LEFT -> { sendKeyWithInjectedMods("LEFT"); setExitCode(0) }
      CommandType.RIGHT -> { sendKeyWithInjectedMods("RIGHT"); setExitCode(0) }

      CommandType.F1 -> { sendKeyWithInjectedMods("F1"); setExitCode(0) }
      CommandType.F2 -> { sendKeyWithInjectedMods("F2"); setExitCode(0) }
      CommandType.F3 -> { sendKeyWithInjectedMods("F3"); setExitCode(0) }
      CommandType.F4 -> { sendKeyWithInjectedMods("F4"); setExitCode(0) }
      CommandType.F5 -> { sendKeyWithInjectedMods("F5"); setExitCode(0) }
      CommandType.F6 -> { sendKeyWithInjectedMods("F6"); setExitCode(0) }
      CommandType.F7 -> { sendKeyWithInjectedMods("F7"); setExitCode(0) }
      CommandType.F8 -> { sendKeyWithInjectedMods("F8"); setExitCode(0) }
      CommandType.F9 -> { sendKeyWithInjectedMods("F9"); setExitCode(0) }
      CommandType.F10 -> { sendKeyWithInjectedMods("F10"); setExitCode(0) }
      CommandType.F11 -> { sendKeyWithInjectedMods("F11"); setExitCode(0) }
      CommandType.F12 -> { sendKeyWithInjectedMods("F12"); setExitCode(0) }
      CommandType.F13 -> { sendKeyWithInjectedMods("F13"); setExitCode(0) }
      CommandType.F14 -> { sendKeyWithInjectedMods("F14"); setExitCode(0) }
      CommandType.F15 -> { sendKeyWithInjectedMods("F15"); setExitCode(0) }
      CommandType.F16 -> { sendKeyWithInjectedMods("F16"); setExitCode(0) }
      CommandType.F17 -> { sendKeyWithInjectedMods("F17"); setExitCode(0) }
      CommandType.F18 -> { sendKeyWithInjectedMods("F18"); setExitCode(0) }
      CommandType.F19 -> { sendKeyWithInjectedMods("F19"); setExitCode(0) }
      CommandType.F20 -> { sendKeyWithInjectedMods("F20"); setExitCode(0) }
      CommandType.F21 -> { sendKeyWithInjectedMods("F21"); setExitCode(0) }
      CommandType.F22 -> { sendKeyWithInjectedMods("F22"); setExitCode(0) }
      CommandType.F23 -> { sendKeyWithInjectedMods("F23"); setExitCode(0) }
      CommandType.F24 -> { sendKeyWithInjectedMods("F24"); setExitCode(0) }

      CommandType.MEDIA_PLAYPAUSE -> { managerSendMediaKey("PLAYPAUSE"); setExitCode(0) }
      CommandType.MEDIA_STOP -> { managerSendMediaKey("STOP"); setExitCode(0) }
      CommandType.MEDIA_PREV -> { managerSendMediaKey("PREVIOUSSONG"); setExitCode(0) }
      CommandType.MEDIA_NEXT -> { managerSendMediaKey("NEXTSONG"); setExitCode(0) }
      CommandType.MEDIA_VOLUMEUP -> { managerSendMediaKey("VOLUMEUP"); setExitCode(0) }
      CommandType.MEDIA_VOLUMEDOWN -> { managerSendMediaKey("VOLUMEDOWN"); setExitCode(0) }
      CommandType.MEDIA_MUTE -> { managerSendMediaKey("MUTE"); setExitCode(0) }

      CommandType.NUMPAD_0 -> { sendKeyWithInjectedMods("KP0"); setExitCode(0) }
      CommandType.NUMPAD_1 -> { sendKeyWithInjectedMods("KP1"); setExitCode(0) }
      CommandType.NUMPAD_2 -> { sendKeyWithInjectedMods("KP2"); setExitCode(0) }
      CommandType.NUMPAD_3 -> { sendKeyWithInjectedMods("KP3"); setExitCode(0) }
      CommandType.NUMPAD_4 -> { sendKeyWithInjectedMods("KP4"); setExitCode(0) }
      CommandType.NUMPAD_5 -> { sendKeyWithInjectedMods("KP5"); setExitCode(0) }
      CommandType.NUMPAD_6 -> { sendKeyWithInjectedMods("KP6"); setExitCode(0) }
      CommandType.NUMPAD_7 -> { sendKeyWithInjectedMods("KP7"); setExitCode(0) }
      CommandType.NUMPAD_8 -> { sendKeyWithInjectedMods("KP8"); setExitCode(0) }
      CommandType.NUMPAD_9 -> { sendKeyWithInjectedMods("KP9"); setExitCode(0) }
      CommandType.NUMPAD_PLUS -> { sendKeyWithInjectedMods("KPPLUS"); setExitCode(0) }
      CommandType.NUMPAD_MINUS -> { sendKeyWithInjectedMods("KPMINUS"); setExitCode(0) }
      CommandType.NUMPAD_MULTIPLY -> { sendKeyWithInjectedMods("KPASTERISK"); setExitCode(0) }
      CommandType.NUMPAD_DIVIDE -> { sendKeyWithInjectedMods("KPSLASH"); setExitCode(0) }
      CommandType.NUMPAD_ENTER -> { sendKeyWithInjectedMods("KPENTER"); setExitCode(0) }
      CommandType.NUMPAD_PERIOD -> { sendKeyWithInjectedMods("KPDOT"); setExitCode(0) }

      CommandType.UNKNOWN -> {
        val line = cmd.args.firstOrNull() ?: ""
        executeModifierCombo(line)
        setExitCode(0)
      }

      else -> setExitCode(0)
    }
    return null
  }

  private fun callFunction(name: String, argsPassed: List<String>) {
    val def = functions[name]
    val body = def?.body
    if (body == null) {
      setExitCode(0)
      return
    }
    callDepth++
    if (callDepth > 64) {
      callDepth--
      throw IllegalStateException("Max function call depth exceeded")
    }
    try {
      val callerVariables = currentVarsView()
      val scope = mutableMapOf<String, Int>()
      localScopes.addLast(scope)
      if (def != null) {
        val params = def.params
        for (i in params.indices) {
          val param = params[i]
          if (param.isBlank()) continue
          val expr = argsPassed.getOrNull(i) ?: "0"
          val value = if (expr.isBlank()) 0 else evaluator.evaluate(expr, callerVariables)
          scope[normalizeVarName(param)] = clampU16(value)
        }
      }
      try {
        executeRange(body, 0, body.size)
        setExitCode(0)
      } catch (r: ReturnSignal) {
        setExitCode(r.value)
      }
    } finally {
      if (localScopes.isNotEmpty()) localScopes.removeLast()
      callDepth--
    }
  }

  private data class FunctionDef(val params: List<String>, val body: List<DuckyCommand>)

  private fun normalizeVarName(name: String): String {
    val trimmed = name.trim()
    return if (trimmed.startsWith("$")) trimmed else "\$$trimmed"
  }

  private fun setVar(name: String, value: Int) {
    val key = normalizeVarName(name)
    if (internalVariables.write(key, value)) {
      if (key == DuckyScriptVariables.BUTTON_ENABLED) updateScriptButton()
      return
    }
    val stored = clampU16(value)
    if (localScopes.isNotEmpty()) {
      for (i in localScopes.size - 1 downTo 0) {
        val scope = localScopes.elementAt(i)
        if (scope.containsKey(key)) {
          scope[key] = stored
          return
        }
      }
    }
    globalVariables[key] = stored
  }

  private fun currentVarsView(): Map<String, Int> {
    if (localScopes.isEmpty()) return globalVariables
    val out = LinkedHashMap<String, Int>(globalVariables)
    for (scope in localScopes) {
      for ((k, v) in scope) out[k] = v
    }
    return out
  }

  private fun parseModifierMask(tokens: List<String>): Int {
    var mask = 0
    for (raw in tokens) {
      val split = raw.split("+")
      for (t in split) {
        val upper = t.trim().uppercase(Locale.US)
        if (upper.isEmpty()) continue
        val mod = HidSpec.modifierFor(upper)
        if (mod != null) mask = mask or mod
      }
    }
    return mask
  }

  private fun sendKeyWithInjectedMods(keyName: String) {
    val key = keyName.uppercase(Locale.US)
    val keyCode = HidSpec.keyCodeFor(key) ?: return
    sendKeyWithInjectedMods(keyCode)
  }

  private fun sendKeyWithInjectedMods(keyCode: Int, modifiers: Int = 0) {
    val mask = injectedModifierMask or heldModifierMask
    manager.writeKeyboardTapWithMods(
      mask or modifiers,
      keyCode,
      heldModifiers = mask,
      extraKeys = heldKeyCodes.toList(),
    )
  }

  private fun executeModifierCombo(line: String) {
    // Normalize hyphen-separated combos like "CTRL-ALT-T" to space-separated tokens
    val normalized = line.replace('-', ' ')
    if (line.isBlank()) return
    val parts = normalized.trim().split(Regex("\\s+")).filter { it.isNotBlank() }
    if (parts.isEmpty()) return

    var modifierMask = 0
    var targetKey: String? = null

    for (part in parts) {
      val upper = part.uppercase(Locale.US)
      val mod = HidSpec.modifierFor(upper)
      if (mod != null) modifierMask = modifierMask or mod else targetKey = upper
    }

    if (targetKey == null) return
    val keyCode = HidSpec.keyCodeFor(targetKey) ?: return
    val finalMask = modifierMask or injectedModifierMask or heldModifierMask
    manager.writeKeyboardTapWithMods(
      finalMask,
      keyCode,
      heldModifiers = injectedModifierMask or heldModifierMask,
      extraKeys = heldKeyCodes.toList(),
    )
  }

  private fun applyHoldRelease(keySpec: String, isHold: Boolean) {
    val tokens = keySpec.split(Regex("[\\s+]+")).filter { it.isNotBlank() }
    if (tokens.isEmpty()) return
    for (token in tokens) {
      val upper = token.uppercase(Locale.US)
      val mod = HidSpec.modifierFor(upper)
      if (mod != null) {
        heldModifierMask = if (isHold) heldModifierMask or mod else heldModifierMask and mod.inv()
        continue
      }
      val code = HidSpec.keyCodeFor(upper) ?: continue
      if (isHold) {
        if (heldKeyCodes.contains(code)) continue
        if (heldKeyCodes.size < KEYBOARD_KEY_SLOTS) {
          heldKeyCodes.add(code)
        } else {
          log.log("kbd", "HOLD ignored ($KEYBOARD_KEY_SLOTS-key rollover): $upper")
        }
      } else {
        heldKeyCodes.remove(code)
      }
    }
    val mask = injectedModifierMask or heldModifierMask
    manager.writeKeyboardReport(mask, heldKeyCodes.toList())
  }

  private fun mouseButtonMask(button: String): Int {
    return when (button.uppercase(Locale.US)) {
      "LEFT" -> 0x01
      "RIGHT" -> 0x02
      "MIDDLE" -> 0x04
      else -> 0
    }
  }

  private fun mouseClick(button: String, count: Int) {
    val b = mouseButtonMask(button)
    if (b == 0) return
    val times = count.coerceAtLeast(1)
    repeat(times) {
      sendMouseReport(heldMouseButtonsMask or b, 0, 0, 0)
      sendMouseReport(heldMouseButtonsMask, 0, 0, 0)
    }
  }

  private fun mouseHold(button: String, dx: Int, dy: Int, count: Int) {
    val b = mouseButtonMask(button)
    if (b == 0) return
    heldMouseButtonsMask = heldMouseButtonsMask or b
    sendMouseReport(heldMouseButtonsMask, 0, 0, 0)
    val times = count.coerceAtLeast(1)
    if (dx != 0 || dy != 0) repeat(times) { sendMouseReport(heldMouseButtonsMask, dx, dy, 0) }
  }

  private fun mouseDrag(button: String, dx: Int, dy: Int, count: Int) {
    val b = mouseButtonMask(button)
    if (b == 0) return
    val prior = heldMouseButtonsMask
    heldMouseButtonsMask = heldMouseButtonsMask or b
    sendMouseReport(heldMouseButtonsMask, 0, 0, 0)
    val times = count.coerceAtLeast(1)
    repeat(times) { sendMouseReport(heldMouseButtonsMask, dx, dy, 0) }
    heldMouseButtonsMask = prior
    sendMouseReport(heldMouseButtonsMask, 0, 0, 0)
  }

  private fun mouseMove(dx: Int, dy: Int, count: Int) {
    val times = count.coerceAtLeast(1)
    repeat(times) { sendMouseReport(heldMouseButtonsMask, dx, dy, 0) }
  }

  private fun mouseScroll(direction: String, count: Int) {
    val times = count.coerceAtLeast(1)
    val wheel = if (direction.equals("DOWN", ignoreCase = true)) -1 else 1
    repeat(times) { sendMouseReport(heldMouseButtonsMask, 0, 0, wheel) }
  }

  private fun sendMouseReport(buttons: Int, dx: Int, dy: Int, wheel: Int) {
    throwIfCancelled()
    manager.sendMouseReport(buttons, dx, dy, wheel)
  }

  private fun tryInvokeAny(names: List<String>, args: List<Any>): Boolean {
    for (n in names) if (tryInvokeByName(n, args)) return true
    return false
  }

  private fun tryInvokeByName(methodName: String, args: List<Any>): Boolean {
    val methods = manager.javaClass.methods.filter { it.name == methodName && it.parameterTypes.size == args.size }
    for (m in methods) {
      val converted = convertArgs(m.parameterTypes, args) ?: continue
      return try { m.isAccessible = true; m.invoke(manager, *converted.toTypedArray()); true } catch (_: Throwable) { false }
    }
    val methodsCi = manager.javaClass.methods.filter { it.name.equals(methodName, ignoreCase = true) && it.parameterTypes.size == args.size }
    for (m in methodsCi) {
      val converted = convertArgs(m.parameterTypes, args) ?: continue
      return try { m.isAccessible = true; m.invoke(manager, *converted.toTypedArray()); true } catch (_: Throwable) { false }
    }
    return false
  }

  private fun convertArgs(paramTypes: Array<Class<*>>, args: List<Any>): List<Any?>? {
    val out = ArrayList<Any?>(args.size)
    for (i in args.indices) {
      val p = paramTypes[i]
      val a = args[i]
      val v = when {
        p == Int::class.javaPrimitiveType || p == Int::class.java -> (a as? Int) ?: (a.toString().toIntOrNull() ?: return null)
        p == Long::class.javaPrimitiveType || p == Long::class.java -> ((a as? Int)?.toLong()) ?: (a.toString().toLongOrNull() ?: return null)
        p == Short::class.javaPrimitiveType || p == Short::class.java -> ((a as? Int)?.toShort()) ?: (a.toString().toShortOrNull() ?: return null)
        p == Byte::class.javaPrimitiveType || p == Byte::class.java -> ((a as? Int)?.toByte()) ?: (a.toString().toByteOrNull() ?: return null)
        p == Boolean::class.javaPrimitiveType || p == Boolean::class.java -> (a as? Boolean) ?: a.toString().equals("true", ignoreCase = true)
        p == String::class.java -> a.toString()
        else -> if (p.isInstance(a)) a else return null
      }
      out.add(v)
    }
    return out
  }
}

internal class DuckyScriptEstimator(
  private val internalVariables: DuckyScriptVariables,
  private val estimateTextDuration: (String, Int) -> Long,
  private val estimateKeyTapDuration: () -> Long,
  delayMultiplier: Double = 1.0,
  onDelayClamp: (String) -> Unit = {},
) {
  private var defaultDelay = 0
  private val globalVariables = mutableMapOf<String, Int>()
  private val localScopes = ArrayDeque<MutableMap<String, Int>>()
  private val functions = mutableMapOf<String, FunctionDef>()
  private var callDepth = 0
  private val evaluator = ExpressionEvaluator(internalVariables::read)
  private val timing = TimingController(delayMultiplier, onDelayClamp)
  private var elapsedMs: Long = 0
  private var remainingWork = 20_000
  private var currentLine: Int? = null

  private class ReturnSignal(val value: Int) : RuntimeException()
  private class EstimateLimit : RuntimeException("Script estimate exceeded its work limit")
  private data class FunctionDef(val params: List<String>, val body: List<DuckyCommand>)

  private fun chargeWork(count: Int = 1) {
    if (count > remainingWork) throw EstimateLimit()
    remainingWork -= count
  }

  fun estimate(script: String): Long {
    if (!globalVariables.containsKey("$?")) globalVariables["$?"] = 0
    val parser = DuckyScriptParser()
    val commands = parser.parse(script)
    defaultDelay = 0
    elapsedMs = 0
    remainingWork = 20_000

    val processed = preprocessCommands(commands)
    try {
      executeRange(processed, 0, processed.size)
    } catch (e: ReturnSignal) {
      setVar("$?", e.value)
    } catch (e: DuckyExpressionSyntaxException) {
      e.lineNumber = currentLine
      throw e
    }

    return elapsedMs
  }

  private fun preprocessCommands(commands: List<DuckyCommand>): List<DuckyCommand> {
    val result = mutableListOf<DuckyCommand>()
    var lastAdded: DuckyCommand? = null
    var i = 0
    while (i < commands.size) {
      chargeWork()
      val cmd = commands[i]
      when (cmd.type) {
        CommandType.FUNCTION -> {
          val funcName = cmd.args.firstOrNull() ?: ""
          val funcArgs = if (cmd.args.size > 1) cmd.args.drop(1) else emptyList()
          val funcBody = mutableListOf<DuckyCommand>()
          i++
          while (i < commands.size && commands[i].type != CommandType.END_FUNCTION) {
            funcBody.add(commands[i])
            i++
          }
          functions[funcName] = FunctionDef(funcArgs, funcBody)
        }

        CommandType.BUTTON_DEF, CommandType.END_BUTTON -> {
          result.add(cmd)
          lastAdded = null
        }

        CommandType.REPEAT -> {
          val last = lastAdded
          if (last != null) {
            val count = cmd.args.single().toInt()
            chargeWork(count)
            repeat(count) {
              result.add(last)
            }
          }
        }

        else -> {
          result.add(cmd)
          lastAdded = cmd
        }
      }
      i++
    }
    return result
  }

  private fun executeRange(commands: List<DuckyCommand>, start: Int, endExclusive: Int) {
    var i = start
    while (i < endExclusive) {
      chargeWork()
      val cmd = commands[i]
      currentLine = cmd.lineNumber
      when (cmd.type) {
        CommandType.BUTTON_DEF -> {
          internalVariables.defineButtonCallback()
          i = endButtonIndex(commands, i, endExclusive) + 1
          continue
        }
        CommandType.IF -> {
          val endIf = findMatchingEndIf(commands, i, endExclusive)
          executeIfChain(commands, i, endIf)
          i = endIf + 1
          continue
        }

        CommandType.WHILE -> {
          val endWhile = findMatchingEndWhile(commands, i, endExclusive)
          val condition = normalizeCondition(cmd.args.firstOrNull() ?: "")
          while (evaluateCondition(condition, cmd.lineNumber)) {
            chargeWork()
            executeRange(commands, i + 1, endWhile)
          }
          i = endWhile + 1
          continue
        }

        CommandType.TRY -> {
          val (catchIndex, endTry) = findMatchingEndTry(commands, i, endExclusive)
          try {
            val tryEnd = catchIndex ?: endTry
            executeRange(commands, i + 1, tryEnd)
          } catch (e: ReturnSignal) {
            throw e
          } catch (e: EstimateLimit) {
            throw e
          } catch (e: Exception) {
            if (catchIndex == null) throw e
            executeRange(commands, catchIndex + 1, endTry)
          }
          i = endTry + 1
          continue
        }

        CommandType.ELSE_IF,
        CommandType.ELSE,
        CommandType.END_IF,
        CommandType.END_WHILE,
        CommandType.END_FUNCTION,
        CommandType.CATCH,
        CommandType.END_TRY -> {
          i++
          continue
        }

        else -> {
          executeCommand(cmd)
          if (defaultDelay > 0) {
            elapsedMs += timing.scaleMs(defaultDelay).toLong()
          }
        }
      }
      i++
    }
  }

  private fun executeIfChain(commands: List<DuckyCommand>, ifIndex: Int, endIfIndex: Int) {
    data class Branch(val condition: String?, val start: Int, val end: Int)
    val branches = mutableListOf<Branch>()
    var currentCond: String? = normalizeCondition(commands[ifIndex].args.firstOrNull() ?: "")
    var currentStart = ifIndex + 1
    var depth = 0
    var scan = ifIndex + 1
    while (scan < endIfIndex) {
      val t = commands[scan].type
      when (t) {
        CommandType.IF -> depth++
        CommandType.END_IF -> if (depth > 0) depth--
        else -> {}
      }
      if (depth == 0 && (t == CommandType.ELSE_IF || t == CommandType.ELSE)) {
        branches.add(Branch(currentCond, currentStart, scan))
        currentCond = if (t == CommandType.ELSE_IF) normalizeCondition(commands[scan].args.firstOrNull() ?: "") else null
        currentStart = scan + 1
      }
      scan++
    }
    branches.add(Branch(currentCond, currentStart, endIfIndex))
    for (b in branches) {
      if (b.condition == null || evaluateCondition(b.condition, commands[b.start - 1].lineNumber)) {
        executeRange(commands, b.start, b.end)
        break
      }
    }
  }

  private fun findMatchingEndIf(commands: List<DuckyCommand>, start: Int, endExclusive: Int): Int {
    var depth = 1
    var i = start + 1
    while (i < endExclusive) {
      when (commands[i].type) {
        CommandType.IF -> depth++
        CommandType.END_IF -> {
          depth--
          if (depth == 0) return i
        }
        else -> {}
      }
      i++
    }
    return endExclusive - 1
  }

  private fun findMatchingEndWhile(commands: List<DuckyCommand>, start: Int, endExclusive: Int): Int {
    var depth = 1
    var i = start + 1
    while (i < endExclusive) {
      when (commands[i].type) {
        CommandType.WHILE -> depth++
        CommandType.END_WHILE -> {
          depth--
          if (depth == 0) return i
        }
        else -> {}
      }
      i++
    }
    return endExclusive - 1
  }

  private fun findMatchingEndTry(commands: List<DuckyCommand>, start: Int, endExclusive: Int): Pair<Int?, Int> {
    var depth = 1
    var i = start + 1
    var catchIndex: Int? = null
    while (i < endExclusive) {
      when (commands[i].type) {
        CommandType.TRY -> depth++
        CommandType.END_TRY -> {
          depth--
          if (depth == 0) return catchIndex to i
        }
        CommandType.CATCH -> if (depth == 1 && catchIndex == null) catchIndex = i
        else -> {}
      }
      i++
    }
    return catchIndex to (endExclusive - 1)
  }

  private fun normalizeCondition(raw: String): String {
    var s = raw.trim()
    if (s.isEmpty()) return "FALSE"
    s = stripOuterParensIfWhole(s)
    return s
  }

  private fun stripOuterParensIfWhole(s: String): String {
    val t = s.trim()
    if (t.length < 2) return t
    if (t.first() != '(' || t.last() != ')') return t
    var depth = 0
    for (i in t.indices) {
      when (t[i]) {
        '(' -> depth++
        ')' -> depth--
      }
      if (depth == 0 && i != t.lastIndex) return t
      if (depth < 0) return t
    }
    if (depth != 0) return t
    return t.substring(1, t.lastIndex).trim()
  }

  private fun evaluateCondition(condition: String, lineNumber: Int): Boolean {
    currentLine = lineNumber
    return evaluator.evaluateCondition(condition, currentVarsView())
  }

  private fun executeCommand(cmd: DuckyCommand) {
    when (cmd.type) {
      CommandType.STRING -> {
        val text = cmd.args.getOrNull(0) ?: ""
        elapsedMs += estimateTextDuration(text, 0)
        setExitCode(0)
      }

      CommandType.STRINGLN -> {
        val text = cmd.args.getOrNull(0) ?: ""
        elapsedMs += estimateTextDuration(text, 0)
        elapsedMs += estimateKeyTapDuration()
        setExitCode(0)
      }

      CommandType.STRING_DELAY -> {
        val delayMs = cmd.args.getOrNull(0)?.toIntOrNull() ?: 0
        val adjustedDelayMs = timing.scaleMs(delayMs)
        val text = cmd.args.getOrNull(1) ?: ""
        elapsedMs += estimateTextDuration(text, adjustedDelayMs)
        setExitCode(0)
      }

      CommandType.DELAY -> {
        val ms = evaluator.evaluate(cmd.args.first(), currentVarsView())
        elapsedMs += timing.scaleMs(ms).toLong()
        setExitCode(0)
      }

      CommandType.DETECT_OS,
      CommandType.SLEEP_UNTIL,
      CommandType.WAIT_FOR -> setExitCode(0)

      CommandType.WAIT_FOR_BUTTON_PRESS -> {
        internalVariables.write("\$_BUTTON_PUSH_RECEIVED", 1)
        setExitCode(0)
      }

      CommandType.ENABLE_BUTTON, CommandType.DISABLE_BUTTON -> {
        setVar(DuckyScriptVariables.BUTTON_ENABLED, if (cmd.type == CommandType.ENABLE_BUTTON) 1 else 0)
        setExitCode(0)
      }

      CommandType.DEFAULTDELAY,
      CommandType.DEFAULT_DELAY -> {
        defaultDelay = evaluator.evaluate(cmd.args.first(), currentVarsView())
        setExitCode(0)
      }

      CommandType.MODIFIER_COMBO -> {
        val line = cmd.args.firstOrNull() ?: ""
        if (hasKeyInCombo(line)) elapsedMs += estimateKeyTapDuration()
        setExitCode(0)
      }

      CommandType.INJECT_VAR -> {
        decodeDuckyKeyStroke(evaluator.evaluate(cmd.args.first(), currentVarsView()))
        elapsedMs += estimateKeyTapDuration()
        setExitCode(0)
      }

      CommandType.CALL_FUNCTION -> {
        val name = cmd.args.firstOrNull() ?: ""
        val args = if (cmd.args.size > 1) cmd.args.drop(1) else emptyList()
        callFunction(name, args)
      }

      CommandType.RETURN -> {
        val expr = cmd.args.firstOrNull() ?: "0"
        val value = if (expr.isBlank()) 0 else evaluator.evaluate(expr, currentVarsView())
        throw ReturnSignal(clampU16(value))
      }

      CommandType.VAR -> {
        val varName = cmd.args.getOrNull(0) ?: ""
        val expr = cmd.args.getOrNull(1) ?: "0"
        val value = if (expr.isBlank()) 0 else evaluator.evaluate(expr, currentVarsView())
        setVar(varName, value)
        setExitCode(0)
      }

      CommandType.RANDOM_LOWERCASE_LETTER -> {
        val count = cmd.args.firstOrNull()?.toIntOrNull() ?: 1
        elapsedMs += estimateTextDuration("a".repeat(count), 0)
        setExitCode(0)
      }

      CommandType.RANDOM_UPPERCASE_LETTER -> {
        val count = cmd.args.firstOrNull()?.toIntOrNull() ?: 1
        elapsedMs += estimateTextDuration("A".repeat(count), 0)
        setExitCode(0)
      }

      CommandType.RANDOM_LETTER -> {
        val count = cmd.args.firstOrNull()?.toIntOrNull() ?: 1
        elapsedMs += estimateTextDuration("a".repeat(count), 0)
        setExitCode(0)
      }

      CommandType.RANDOM_NUMBER -> {
        val count = cmd.args.firstOrNull()?.toIntOrNull() ?: 1
        elapsedMs += estimateTextDuration("0".repeat(count), 0)
        setExitCode(0)
      }

      CommandType.RANDOM_SPECIAL -> {
        val count = cmd.args.firstOrNull()?.toIntOrNull() ?: 1
        elapsedMs += estimateTextDuration("!".repeat(count), 0)
        setExitCode(0)
      }

      CommandType.RANDOM_CHAR -> {
        val count = cmd.args.firstOrNull()?.toIntOrNull() ?: 1
        elapsedMs += estimateTextDuration("a".repeat(count), 0)
        setExitCode(0)
      }

      CommandType.MOUSE_CLICK,
      CommandType.MOUSE_HOLD,
      CommandType.MOUSE_DRAG,
      CommandType.MOUSE_MOVE,
      CommandType.MOUSE_SCROLL,
      CommandType.HOLD,
      CommandType.RELEASE,
      CommandType.KEYDOWN,
      CommandType.KEYUP,
      CommandType.INJECT_MOD,
      CommandType.ATTACKMODE -> {
        setExitCode(0)
      }

      CommandType.MENU,
      CommandType.ENTER,
      CommandType.ESCAPE,
      CommandType.BACKSPACE,
      CommandType.TAB,
      CommandType.SPACE,
      CommandType.CAPSLOCK,
      CommandType.NUMLOCK,
      CommandType.SCROLLLOCK,
      CommandType.PRINTSCREEN,
      CommandType.PAUSE,
      CommandType.INSERT,
      CommandType.HOME,
      CommandType.PAGEUP,
      CommandType.PAGEDOWN,
      CommandType.DELETE,
      CommandType.END,
      CommandType.UP,
      CommandType.DOWN,
      CommandType.LEFT,
      CommandType.RIGHT,
      CommandType.F1,
      CommandType.F2,
      CommandType.F3,
      CommandType.F4,
      CommandType.F5,
      CommandType.F6,
      CommandType.F7,
      CommandType.F8,
      CommandType.F9,
      CommandType.F10,
      CommandType.F11,
      CommandType.F12,
      CommandType.F13,
      CommandType.F14,
      CommandType.F15,
      CommandType.F16,
      CommandType.F17,
      CommandType.F18,
      CommandType.F19,
      CommandType.F20,
      CommandType.F21,
      CommandType.F22,
      CommandType.F23,
      CommandType.F24,
      CommandType.MEDIA_PLAYPAUSE,
      CommandType.MEDIA_STOP,
      CommandType.MEDIA_PREV,
      CommandType.MEDIA_NEXT,
      CommandType.MEDIA_VOLUMEUP,
      CommandType.MEDIA_VOLUMEDOWN,
      CommandType.MEDIA_MUTE,
      CommandType.NUMPAD_0,
      CommandType.NUMPAD_1,
      CommandType.NUMPAD_2,
      CommandType.NUMPAD_3,
      CommandType.NUMPAD_4,
      CommandType.NUMPAD_5,
      CommandType.NUMPAD_6,
      CommandType.NUMPAD_7,
      CommandType.NUMPAD_8,
      CommandType.NUMPAD_9,
      CommandType.NUMPAD_PLUS,
      CommandType.NUMPAD_MINUS,
      CommandType.NUMPAD_MULTIPLY,
      CommandType.NUMPAD_DIVIDE,
      CommandType.NUMPAD_ENTER,
      CommandType.NUMPAD_PERIOD,
      CommandType.UNKNOWN -> {
        elapsedMs += estimateKeyTapDuration()
        setExitCode(0)
      }

      else -> setExitCode(0)
    }
  }

  private fun callFunction(name: String, argsPassed: List<String>) {
    val def = functions[name]
    val body = def?.body
    if (body == null) {
      setExitCode(0)
      return
    }
    callDepth++
    if (callDepth > 64) {
      callDepth--
      return
    }
    try {
      val callerVariables = currentVarsView()
      val scope = mutableMapOf<String, Int>()
      localScopes.addLast(scope)
      if (def != null) {
        val params = def.params
        for (i in params.indices) {
          val param = params[i]
          if (param.isBlank()) continue
          val expr = argsPassed.getOrNull(i) ?: "0"
          val value = if (expr.isBlank()) 0 else evaluator.evaluate(expr, callerVariables)
          scope[normalizeVarName(param)] = clampU16(value)
        }
      }
      try {
        executeRange(body, 0, body.size)
        setExitCode(0)
      } catch (r: ReturnSignal) {
        setExitCode(r.value)
      }
    } finally {
      if (localScopes.isNotEmpty()) localScopes.removeLast()
      callDepth--
    }
  }

  private fun hasKeyInCombo(line: String): Boolean {
    val normalized = line.replace('-', ' ')
    val parts = normalized.trim().split(Regex("\\s+")).filter { it.isNotBlank() }
    if (parts.isEmpty()) return false
    var targetKey: String? = null
    for (part in parts) {
      val upper = part.uppercase(Locale.US)
      val mod = HidSpec.modifierFor(upper)
      if (mod == null) targetKey = upper
    }
    if (targetKey == null) return false
    return HidSpec.keyCodeFor(targetKey) != null
  }

  private fun normalizeVarName(name: String): String {
    val trimmed = name.trim()
    return if (trimmed.startsWith("$")) trimmed else "\$$trimmed"
  }

  private fun setVar(name: String, value: Int) {
    val key = normalizeVarName(name)
    if (internalVariables.write(key, value)) return
    val stored = clampU16(value)
    if (localScopes.isNotEmpty()) {
      for (i in localScopes.size - 1 downTo 0) {
        val scope = localScopes.elementAt(i)
        if (scope.containsKey(key)) {
          scope[key] = stored
          return
        }
      }
    }
    globalVariables[key] = stored
  }

  private fun currentVarsView(): Map<String, Int> {
    if (localScopes.isEmpty()) return globalVariables
    val out = LinkedHashMap<String, Int>(globalVariables)
    for (scope in localScopes) {
      for ((k, v) in scope) out[k] = v
    }
    return out
  }

  private fun clampU16(v: Int): Int = v.coerceIn(0, 65535)

  private fun setExitCode(v: Int) {
    setVar("$?", v)
  }
}
