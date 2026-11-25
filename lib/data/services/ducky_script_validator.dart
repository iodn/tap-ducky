import 'dart:math';

class ValidationIssue {
  const ValidationIssue({
    required this.line,
    required this.severity,
    required this.message,
    this.suggestion,
  });

  final int line;
  final IssueSeverity severity;
  final String message;
  final String? suggestion;

  @override
  String toString() => 'Line $line: $message${suggestion != null ? " → $suggestion" : ""}';
}

enum IssueSeverity {
  error,
  warning,
  info;

  String get label {
    switch (this) {
      case IssueSeverity.error:
        return 'ERROR';
      case IssueSeverity.warning:
        return 'WARNING';
      case IssueSeverity.info:
        return 'INFO';
    }
  }
}

class ValidationResult {
  const ValidationResult({
    required this.issues,
    required this.commandCount,
    required this.estimatedDurationMs,
    required this.totalDelayMs,
    required this.hasErrors,
    required this.hasWarnings,
  });

  final List<ValidationIssue> issues;
  final int commandCount;

  final int estimatedDurationMs;
  final int totalDelayMs;

  final bool hasErrors;
  final bool hasWarnings;

  int get errorCount => issues.where((i) => i.severity == IssueSeverity.error).length;
  int get warningCount => issues.where((i) => i.severity == IssueSeverity.warning).length;
  int get infoCount => issues.where((i) => i.severity == IssueSeverity.info).length;

  String get estimatedDurationFormatted {
    final seconds = estimatedDurationMs / 1000;
    if (seconds < 1) return '${estimatedDurationMs}ms';
    if (seconds < 60) return '${seconds.toStringAsFixed(1)}s';
    final minutes = seconds ~/ 60;
    final remainingSeconds = (seconds % 60).round();
    return '${minutes}m ${remainingSeconds}s';
  }

  factory ValidationResult.empty() => const ValidationResult(
        issues: [],
        commandCount: 0,
        estimatedDurationMs: 0,
        totalDelayMs: 0,
        hasErrors: false,
        hasWarnings: false,
      );
}

class DuckyScriptValidator {
  static bool isSupportedCommand(String word) =>
      _supportedCommands.contains(word.toUpperCase());

  static const _supportedCommands = {
    'REM',
    'REM_BLOCK',
    'END_REM',
    'STRING',
    'STRINGLN',
    'STRING_DELAY',
    'STRINGDELAY',
    'END_STRING',
    'END_STRINGLN',
    'UP',
    'DOWN',
    'LEFT',
    'RIGHT',
    'UPARROW',
    'DOWNARROW',
    'LEFTARROW',
    'RIGHTARROW',
    'PAGEUP',
    'PAGEDOWN',
    'HOME',
    'END',
    'INSERT',
    'DELETE',
    'DEL',
    'BACKSPACE',
    'BKSP',
    'TAB',
    'SPACE',
    'ENTER',
    'ESCAPE',
    'ESC',
    'PAUSE',
    'BREAK',
    'PRINTSCREEN',
    'PRINTSCRN',
    'PRTSCN',
    'MENU',
    'APP',
    'F1',
    'F2',
    'F3',
    'F4',
    'F5',
    'F6',
    'F7',
    'F8',
    'F9',
    'F10',
    'F11',
    'F12',
    'F13',
    'F14',
    'F15',
    'F16',
    'F17',
    'F18',
    'F19',
    'F20',
    'F21',
    'F22',
    'F23',
    'F24',
    'SHIFT',
    'ALT',
    'CONTROL',
    'CTRL',
    'COMMAND',
    'WINDOWS',
    'GUI',
    'OPTION',
    'INJECT_MOD',
    'INJECT_VAR',
    'CAPSLOCK',
    'NUMLOCK',
    'SCROLLLOCK',
    'DELAY',
    'DEFAULTDELAY',
    'DEFAULT_DELAY',
    'DEFINE',
    'VAR',
    'IF',
    'THEN',
    'ELSE',
    'ELSE_IF',
    'END_IF',
    'ENDIF',
    'WHILE',
    'END_WHILE',
    'ENDWHILE',
    'FUNCTION',
    'DETECT_OS()',
    'EXTENSION',
    'END_EXTENSION',
    'END_FUNCTION',
    'ENDFUNCTION',
    'RETURN',
    'REPEAT',
    'HOLD',
    'RELEASE',
    'KEYDOWN',
    'KEYUP',
    'ATTACKMODE',
    'TRY',
    'CATCH',
    'END_TRY',
    'ENDTRY',
    'WAIT_FOR',
    'WAITFOR',
    'WAIT_FOR_BUTTON_PRESS',
    'ENABLE_BUTTON',
    'DISABLE_BUTTON',
    'BUTTON_DEF',
    'END_BUTTON',
    'STOP_PAYLOAD',
    'SLEEP_UNTIL',
    'SLEEPUNTIL',
    'RANDOM_LOWERCASE_LETTER',
    'RANDOMLOWERCASELETTER',
    'RANDOM_UPPERCASE_LETTER',
    'RANDOMUPPERCASELETTER',
    'RANDOM_LETTER',
    'RANDOMLETTER',
    'RANDOM_NUMBER',
    'RANDOMNUMBER',
    'RANDOM_SPECIAL',
    'RANDOMSPECIAL',
    'RANDOM_CHAR',
    'RANDOMCHAR',
    'NUMPAD_0',
    'NUMPAD_1',
    'NUMPAD_2',
    'NUMPAD_3',
    'NUMPAD_4',
    'NUMPAD_5',
    'NUMPAD_6',
    'NUMPAD_7',
    'NUMPAD_8',
    'NUMPAD_9',
    'NUMPAD_PLUS',
    'NUMPAD_MINUS',
    'NUMPAD_MULTIPLY',
    'NUMPAD_DIVIDE',
    'NUMPAD_ENTER',
    'NUMPAD_PERIOD',
    'KP0',
    'KP1',
    'KP2',
    'KP3',
    'KP4',
    'KP5',
    'KP6',
    'KP7',
    'KP8',
    'KP9',
    'KPPLUS',
    'KPMINUS',
    'KPASTERISK',
    'KPSLASH',
    'KPENTER',
    'KPDOT',
    'MEDIA_PLAYPAUSE',
    'PLAYPAUSE',
    'MEDIA_STOP',
    'STOPCD',
    'MEDIA_PREV',
    'PREVIOUSSONG',
    'MEDIA_NEXT',
    'NEXTSONG',
    'MEDIA_VOLUMEUP',
    'VOLUMEUP',
    'MEDIA_VOLUMEDOWN',
    'VOLUMEDOWN',
    'MEDIA_MUTE',
    'MUTE',
    'MOUSE',
    'POINTER',
  };

  static const _commonTypos = {
    'STRNIG': 'STRING',
    'STIRNG': 'STRING',
    'STRIGN': 'STRING',
    'SRING': 'STRING',
    'STRNG': 'STRING',
    'STRIG': 'STRING',
    'STTRING': 'STRING',
    'STIRNIG': 'STRING',
    'STING': 'STRING',
    'STRIN': 'STRING',
    'STRINGG': 'STRING',
    'DLEAY': 'DELAY',
    'DEALY': 'DELAY',
    'DELYA': 'DELAY',
    'DALAY': 'DELAY',
    'DLAEY': 'DELAY',
    'DELAYY': 'DELAY',
    'DELAT': 'DELAY',
    'DELAYA': 'DELAY',
    'ENER': 'ENTER',
    'ENTEER': 'ENTER',
    'ENTR': 'ENTER',
    'ENETR': 'ENTER',
    'ETNER': 'ENTER',
    'ENRTE': 'ENTER',
    'ENTRE': 'ENTER',
    'ENTTER': 'ENTER',
    'ENTERD': 'ENTER',
    'CRTL': 'CTRL',
    'CONTRL': 'CTRL',
    'CTLR': 'CTRL',
    'CRL': 'CTRL',
    'CNTRL': 'CTRL',
    'COTRL': 'CTRL',
    'ATL': 'ALT',
    'ALTT': 'ALT',
    'SHFIT': 'SHIFT',
    'SHTIF': 'SHIFT',
    'SHFT': 'SHIFT',
    'SHIF': 'SHIFT',
    'WIDNOWS': 'WINDOWS',
    'WINODWS': 'WINDOWS',
    'WINDWOS': 'WINDOWS',
    'WINDOS': 'WINDOWS',
    'WNDOWS': 'WINDOWS',
    'WINOWS': 'WINDOWS',
    'SUPER': 'GUI',
    'META': 'GUI',
    'WIN': 'WINDOWS',
    'ESACPE': 'ESCAPE',
    'ESCPE': 'ESCAPE',
    'ESCAP': 'ESCAPE',
    'ECSAPE': 'ESCAPE',
    'BACKPSACE': 'BACKSPACE',
    'BAKCSPACE': 'BACKSPACE',
    'BACKSAPCE': 'BACKSPACE',
    'BACKSPCAE': 'BACKSPACE',
    'BACKSPAC': 'BACKSPACE',
    'BAKCSAPCE': 'BACKSPACE',
    'BCKSPACE': 'BACKSPACE',
    'RME': 'REM',
    'DELTE': 'DELETE',
    'DLEETE': 'DELETE',
    'DELET': 'DELETE',
    'DEETE': 'DELETE',
    'DEELTE': 'DELETE',
    'DELETTE': 'DELETE',
  };

  static const _modifierTokens = {
    'GUI',
    'WINDOWS',
    'WIN',
    'COMMAND',
    'CONTROL',
    'CTRL',
    'ALT',
    'OPTION',
    'SHIFT',
    'RCTRL',
    'RCONTROL',
    'RSHIFT',
    'RALT',
    'RGUI',
    'RWINDOWS',
    'RCOMMAND',
  };

  static final Set<String> _comboKeys = {
    'ENTER',
    'ESC',
    'ESCAPE',
    'BACKSPACE',
    'BKSP',
    'TAB',
    'SPACE',
    'DELETE',
    'DEL',
    'UP',
    'UPARROW',
    'DOWN',
    'DOWNARROW',
    'LEFT',
    'LEFTARROW',
    'RIGHT',
    'RIGHTARROW',
    'HOME',
    'END',
    'PAGEUP',
    'PAGEDOWN',
    'INSERT',
    'INS',
    'PRINTSCREEN',
    'PRTSCN',
    'SCROLLLOCK',
    'PAUSE',
    'BREAK',
    'CAPSLOCK',
    'NUMLOCK',
    'MENU',
    'APP',
    for (var i = 1; i <= 24; i++) 'F$i',
    for (var i = 0; i <= 9; i++) 'NUMPAD_$i',
    for (var i = 0; i <= 9; i++) 'KP$i',
    'NUMPAD_PLUS',
    'KPPLUS',
    'NUMPAD_MINUS',
    'KPMINUS',
    'NUMPAD_MULTIPLY',
    'KPASTERISK',
    'NUMPAD_DIVIDE',
    'KPSLASH',
    'NUMPAD_ENTER',
    'KPENTER',
    'NUMPAD_PERIOD',
    'KPDOT',
  };

  static const int _minDelayMs = 20;

  static const int _baseKeyMs = 25;
  static const int _baseMouseMs = 20;
  static const int _commandOverheadMs = 3;
  static const int _maxScriptRepeats = 20000;
  static const _hostOsVariable = r'$_OS';
  static const _readOnlyHak5Variables = {
    _hostOsVariable, r'$_CURRENT_VID', r'$_CURRENT_PID', r'$_CURRENT_ATTACKMODE',
    r'$_RANDOM_INT', r'$_RANDOM_SEED', r'$_RANDOM_LOWER_LETTER_KEYCODE',
    r'$_RANDOM_UPPER_LETTER_KEYCODE', r'$_RANDOM_LETTER_KEYCODE',
    r'$_RANDOM_NUMBER_KEYCODE', r'$_RANDOM_SPECIAL_KEYCODE', r'$_RANDOM_CHAR_KEYCODE',
  };
  static const _hostOsExtensions = {'OS_DETECTION', 'OS_DETECT'};
  static const _unsignedHak5Variables = {
    r'$_RANDOM_MIN', r'$_RANDOM_MAX', r'$_BUTTON_TIMEOUT',
  };
  static const _writableHak5Variables = {
    ..._unsignedHak5Variables,
    r'$_BUTTON_ENABLED',
    r'$_BUTTON_USER_DEFINED',
    r'$_INJECTING_LEDS_ENABLED',
    r'$_BUTTON_PUSH_RECEIVED',
  };
  static const _variableName = r'\$(?:[A-Za-z0-9_]+|\?)';
  static final _variablePattern = RegExp(_variableName);
  static final _assignmentPattern = RegExp('^($_variableName)\\s*=\\s*(.*)\$');
  static final _varDeclarationPattern = RegExp(
    '^VAR\\s+($_variableName)(?:\\s*=\\s*(.*)|\\s+(.+))?\$',
    caseSensitive: false,
  );
  static final _functionCallPattern = RegExp(r'^([A-Za-z_]\w*)\s*\((.*)\)\s*$');
  static final _delayValueToken = RegExp(
    '$_variableName|'
    r'0x[0-9a-f]+|\d+|'
    r'\b(?:TRUE|FALSE|UNKNOWN|WINDOWS|MACOS|LINUX|CHROMEOS|ANDROID|IOS)\b',
    caseSensitive: false,
  );
  static final _delayExpressionOperators = RegExp(r'^[\s()+*/%^<>=!&|\-]*$');
  static bool _looksLikeDelayExpression(String expression) {
    final operators = expression.replaceAll(_delayValueToken, '');
    return operators != expression && _delayExpressionOperators.hasMatch(operators);
  }
  static final _integerLiteral = RegExp(r'^[+-]?(?:0x[0-9a-f]+|\d+)$', caseSensitive: false);
  static final _defineDeclaration = RegExp(r'^DEFINE\s+(\S+)\s(.*)$', caseSensitive: false);
  static const _unsupportedHak5Variables = {
    r'$_SYSTEM_LEDS_ENABLED', r'$_STORAGE_LEDS_ENABLED',
    r'$_LED_CONTINUOUS_SHOW_STORAGE_ACTIVITY',
    r'$_EXFIL_LEDS_ENABLED', r'$_LED_SHOW_CAPS', r'$_LED_SHOW_NUM',
    r'$_LED_SHOW_SCROLL', r'$_JITTER_ENABLED', r'$_JITTER_MAX',
    r'$_CAPSLOCK_ON', r'$_NUMLOCK_ON', r'$_SCROLLLOCK_ON',
    r'$_SAVED_CAPSLOCK_ON', r'$_SAVED_NUMLOCK_ON', r'$_SAVED_SCROLLLOCK_ON',
    r'$_RECEIVED_HOST_LOCK_LED_REPLY', r'$_STORAGE_ACTIVITY_TIMEOUT',
    r'$_EXFIL_MODE_ENABLED', r'$_HOST_CONFIGURATION_REQUEST_COUNT',
  };

  ValidationResult validate(
    String script, {
    double delayMultiplier = 1.0,
  }) {
    final issues = <ValidationIssue>[];

    final normalizedScript = script.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final rawLines = normalizedScript.split('\n');

    int commandCount = 0;

    int totalDelayMs = 0;
    int keyTimeMs = 0;
    int overheadMs = 0;

    int defaultDelayMs = 0;
    int remainingRepeats = _maxScriptRepeats;

    bool inRemBlock = false;
    bool inStringBlock = false;
    bool inStringLnBlock = false;
    int? extensionStart;
    int? buttonStart;
    final warnedVariables = <String>{};
    final defines = <String, String>{};
    RegExp? definePattern;
    final scriptVariables = <String>{r'$?', ..._readOnlyHak5Variables, ..._writableHak5Variables};
    final referencedVariables = <String, int>{};
    final functionParameters = <Set<String>>[];

    final Set<String> declaredFunctions = {};
    int ifDepth = 0;
    int whileDepth = 0;
    final tryHasCatch = <bool>[];

    int lastCommandTotalMs = 0;

    int scaledMs(int ms) {
      if (ms <= 0) return 0;
      final v = (ms * (delayMultiplier <= 0 ? 1.0 : delayMultiplier)).truncate();
      return v.clamp(0, 300000);
    }

    int approxTextLen(String text) {
      if (text.isEmpty) return 0;
      final replaced = text.replaceAll(RegExp(r'\{\{[^}]+\}\}'), 'XXXXXXXX');
      return replaced.length;
    }

    void addDefaultDelayIfAny() {
      if (defaultDelayMs <= 0) return;
      final d = scaledMs(defaultDelayMs);
      totalDelayMs += d;
      lastCommandTotalMs += d;
    }

    void commitCommand({
      required int keyCount,
      required int perCharDelayMs,
      required int charCount,
      bool addEnter = false,
      bool applyDefaultDelay = true,
      int extraDelayMs = 0,
      int extraKeyCount = 0,
      int extraOverheadMs = 0,
    }) {
      final keys = keyCount + (addEnter ? 1 : 0) + extraKeyCount;
      final kMs = keys * _baseKeyMs;
      keyTimeMs += kMs;

      final perCharDelayScaled = scaledMs(perCharDelayMs);
      final dMs = (charCount > 0) ? (perCharDelayScaled * charCount) : 0;
      totalDelayMs += dMs;

      final extraDelayScaled = scaledMs(extraDelayMs);
      totalDelayMs += extraDelayScaled;

      final oMs = _commandOverheadMs + extraOverheadMs;
      overheadMs += oMs;

      lastCommandTotalMs = kMs + dMs + extraDelayScaled + oMs;

      if (applyDefaultDelay) {
        addDefaultDelayIfAny();
      }
    }

    void typeText(String text, {required int perCharDelay, bool addEnter = false}) {
      final len = approxTextLen(text);
      commitCommand(
        keyCount: len,
        perCharDelayMs: perCharDelay,
        charCount: len,
        addEnter: addEnter,
      );
    }

    final stringBlockLines = <String>[];
    String expandDefines(String expression) {
      if (defines.isEmpty) return expression;
      final pattern = definePattern ??= RegExp(
        (defines.keys.toList()..sort((a, b) => b.length.compareTo(a.length)))
            .map((label) {
              final literal = RegExp.escape(label);
              return label.startsWith('#') ? literal : '(?<!\\S)$literal(?!\\S)';
            })
            .join('|'),
      );
      return expression.replaceAllMapped(pattern, (match) => defines[match[0]]!);
    }

    void checkVariableWrite(String name, int line, String? expression) {
      if (expression?.trim().isEmpty == true) {
        issues.add(ValidationIssue(
          line: line,
          severity: IssueSeverity.error,
          message: "Expected a value after '='",
        ));
        return;
      }
      if (_readOnlyHak5Variables.contains(name)) {
        issues.add(ValidationIssue(
          line: line,
          severity: IssueSeverity.error,
          message: '$name is read-only',
        ));
      } else if (_unsupportedHak5Variables.contains(name)) {
        issues.add(ValidationIssue(
          line: line,
          severity: IssueSeverity.error,
          message: '$name is a Hak5 variable unavailable in TapDucky',
        ));
      } else if (_unsignedHak5Variables.contains(name) && expression != null) {
        final literal = expression.trim();
        if (!_integerLiteral.hasMatch(literal)) return;
        final value = int.tryParse(literal);
        if (value == null || value < 0 || value > 65535) {
          issues.add(ValidationIssue(
            line: line,
            severity: IssueSeverity.error,
            message: '$name requires a value from 0 to 65535, got ${value ?? literal}',
          ));
        }
      }
    }

    bool isFunctionParameter(String name) =>
        functionParameters.any((parameters) => parameters.contains(name));

    for (int i = 0; i < rawLines.length; i++) {
      final lineNum = i + 1;

      final rawLine = rawLines[i];
      final trimmed = rawLine.trim();

      if (extensionStart != null) {
        if (trimmed.toUpperCase() == 'END_EXTENSION') extensionStart = null;
        continue;
      }

      if (inRemBlock) {
        if (trimmed.toUpperCase() == 'END_REM') {
          inRemBlock = false;
        }
        continue;
      }

      if (inStringBlock || inStringLnBlock) {
        final end = inStringLnBlock ? 'END_STRINGLN' : 'END_STRING';
        final upper = trimmed.toUpperCase();
        if (upper == end) {
          if (stringBlockLines.isNotEmpty) {
            typeText(
              stringBlockLines.join(inStringLnBlock ? '\n' : ''),
              perCharDelay: 0,
              addEnter: inStringLnBlock,
            );
          }
          stringBlockLines.clear();
          inStringBlock = false;
          inStringLnBlock = false;
        } else {
          final text = upper == '\\$end' ? rawLine.replaceFirst('\\', '') : rawLine;
          stringBlockLines.add(expandDefines(text));
        }
        continue;
      }

      if (trimmed.isEmpty) continue;

      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.isEmpty) continue;

      final command = parts[0].toUpperCase();
      final expanded = expandDefines(trimmed).trimRight();
      final assignMatch = _assignmentPattern.firstMatch(expanded);
      final declaration = command == 'VAR' ? _varDeclarationPattern.firstMatch(expanded) : null;
      final functionCall = _supportedCommands.contains(command)
          ? null
          : _functionCallPattern.firstMatch(trimmed);

      if (const {'IF', 'ELSE', 'ELSE_IF', 'WHILE', 'RETURN', 'DELAY', 'DEFAULTDELAY', 'DEFAULT_DELAY', 'INJECT_VAR'}
              .contains(command) ||
          declaration != null || assignMatch != null || functionCall != null) {
        final references = declaration != null
            ? declaration[2] ?? declaration[3] ?? ''
            : assignMatch != null ? assignMatch[2]! : expanded;
        for (final match in _variablePattern.allMatches(references)) {
          final variable = match.group(0)!;
          if (_unsupportedHak5Variables.contains(variable)) {
            if (warnedVariables.add(variable)) {
              issues.add(ValidationIssue(
                line: lineNum,
                severity: IssueSeverity.warning,
                message: '$variable is a Hak5 variable unavailable in TapDucky',
              ));
            }
          } else if (!isFunctionParameter(variable)) {
            referencedVariables.putIfAbsent(variable, () => lineNum);
          }
        }
      }

      if (_commonTypos.containsKey(command)) {
        issues.add(ValidationIssue(
          line: lineNum,
          severity: IssueSeverity.error,
          message: 'Unknown command: $command',
          suggestion: 'Did you mean ${_commonTypos[command]}?',
        ));
        continue;
      }

      switch (command) {
        case 'INJECT_VAR':
          commandCount++;
          if (parts.length == 1) {
            issues.add(ValidationIssue(
              line: lineNum,
              severity: IssueSeverity.error,
              message: 'INJECT_VAR requires a scancode variable',
            ));
          } else {
            commitCommand(keyCount: 1, perCharDelayMs: 0, charCount: 0);
          }
          break;

        case 'EXTENSION':
          final name = parts.skip(1).join(' ').toUpperCase();
          if (!_hostOsExtensions.contains(name)) {
            issues.add(ValidationIssue(
              line: lineNum,
              severity: IssueSeverity.error,
              message: 'Unsupported extension: $name',
            ));
          }
          extensionStart = lineNum;
          break;

        case 'END_EXTENSION':
          issues.add(ValidationIssue(
            line: lineNum,
            severity: IssueSeverity.error,
            message: 'END_EXTENSION without EXTENSION',
          ));
          break;

        case 'REM':
          break;

        case 'REM_BLOCK':
          inRemBlock = true;
          break;

        case 'STRING':
        case 'STRINGLN':
          commandCount++;
          if (trimmed.length == command.length) {
            inStringBlock = command == 'STRING';
            inStringLnBlock = command == 'STRINGLN';
          } else {
            final text = expandDefines(rawLine.trimLeft().substring(command.length + 1));
            typeText(text, perCharDelay: 0, addEnter: command == 'STRINGLN');
          }
          break;

        case 'STRING_DELAY':
        case 'STRINGDELAY':
          commandCount++;
          final operand = expandDefines(rawLine.trimLeft().substring(command.length)).trimLeft();
          final delayToken = operand.split(RegExp(r'\s+')).first;
          if (delayToken.isEmpty) {
            issues.add(ValidationIssue(
              line: lineNum,
              severity: IssueSeverity.error,
              message: 'STRING_DELAY requires a numeric delay value',
              suggestion: 'Example: STRING_DELAY 100 Hello',
            ));
            break;
          }
          final delayArg = int.tryParse(delayToken);
          if (delayArg == null) {
            issues.add(ValidationIssue(
              line: lineNum,
              severity: IssueSeverity.error,
              message: 'STRING_DELAY requires a numeric delay value',
              suggestion: 'Example: STRING_DELAY 50',
            ));
            break;
          }
          final text = operand.length > delayToken.length
              ? operand.substring(delayToken.length + 1)
              : '';
          typeText(text, perCharDelay: max(0, delayArg), addEnter: false);
          break;

        case 'DEFAULTDELAY':
        case 'DEFAULT_DELAY':
          final expression = expandDefines(trimmed.substring(command.length)).trim();
          final ms = int.tryParse(expression);
          if (ms == null && !_looksLikeDelayExpression(expression)) {
            issues.add(ValidationIssue(
              line: lineNum,
              severity: IssueSeverity.error,
              message: 'DEFAULT_DELAY requires a time expression',
            ));
          } else {
            defaultDelayMs = max(0, ms ?? 0);
          }
          break;

        case 'DELAY':
          commandCount++;
          if (parts.length < 2) {
            issues.add(ValidationIssue(
              line: lineNum,
              severity: IssueSeverity.error,
              message: 'DELAY requires a time value in milliseconds',
              suggestion: 'Example: DELAY 500',
            ));
            break;
          }
          final expression = expandDefines(trimmed.substring(command.length).trim());
          final delayValue = int.tryParse(expression);
          if (delayValue == null) {
            if (!_looksLikeDelayExpression(expression)) {
              issues.add(ValidationIssue(
                line: lineNum,
                severity: IssueSeverity.error,
                message: 'DELAY requires a time expression',
                suggestion: 'Example: DELAY 500 or DELAY \$MY_DELAY',
              ));
            }
            commitCommand(
              keyCount: 0,
              perCharDelayMs: 0,
              charCount: 0,
              extraDelayMs: _minDelayMs,
            );
          } else {
            if (delayValue < _minDelayMs) {
              issues.add(ValidationIssue(
                line: lineNum,
                severity: IssueSeverity.warning,
                message: 'DELAY minimum value is ${_minDelayMs}ms',
                suggestion: 'Use DELAY $_minDelayMs or higher',
              ));
            }
            commitCommand(
              keyCount: 0,
              perCharDelayMs: 0,
              charCount: 0,
              extraDelayMs: max(_minDelayMs, delayValue),
            );
          }
          break;

        case 'SLEEP_UNTIL':
        case 'SLEEPUNTIL':
          commandCount++;
          commitCommand(keyCount: 0, perCharDelayMs: 0, charCount: 0);
          break;

        case 'WAIT_FOR':
        case 'WAITFOR':
          commandCount++;
          if (parts.length >= 2) {
            final target = parts[1].toUpperCase();
            const allowed = {
              'HOST_CONNECTED',
              'HOST',
              'UDC_CONFIGURED',
              'UDC',
              'KEYBOARD_READY',
              'KBD_READY',
              'MOUSE_READY',
              'SESSION_ARMED',
              'ACTIVE',
            };
            if (!allowed.contains(target)) {
              issues.add(ValidationIssue(
                line: lineNum,
                severity: IssueSeverity.warning,
                message: 'WAIT_FOR target not recognized: $target',
                suggestion: 'Use HOST_CONNECTED, UDC_CONFIGURED, KEYBOARD_READY, MOUSE_READY, or SESSION_ARMED',
              ));
            }
          }
          commitCommand(keyCount: 0, perCharDelayMs: 0, charCount: 0);
          break;

        case 'WAIT_FOR_BUTTON_PRESS':
        case 'ENABLE_BUTTON':
        case 'DISABLE_BUTTON':
        case 'STOP_PAYLOAD':
          commandCount++;
          if (parts.length != 1) {
            issues.add(ValidationIssue(
              line: lineNum,
              severity: IssueSeverity.error,
              message: '$command takes no arguments',
            ));
          }
          commitCommand(keyCount: 0, perCharDelayMs: 0, charCount: 0);
          break;

        case 'BUTTON_DEF':
        case 'END_BUTTON':
          if (parts.length != 1) {
            issues.add(ValidationIssue(
              line: lineNum,
              severity: IssueSeverity.error,
              message: '$command takes no arguments',
            ));
          } else if (command == 'BUTTON_DEF' && buttonStart != null ||
              command == 'END_BUTTON' && buttonStart == null) {
            issues.add(ValidationIssue(
              line: lineNum,
              severity: IssueSeverity.error,
              message: command == 'BUTTON_DEF' ? 'Nested BUTTON_DEF' : 'END_BUTTON without BUTTON_DEF',
            ));
          } else {
            buttonStart = command == 'BUTTON_DEF' ? lineNum : null;
          }
          break;

        case 'DEFINE':
          final declaration = _defineDeclaration.firstMatch(rawLine.trimLeft());
          if (declaration == null || declaration[2]!.trim().isEmpty) {
            issues.add(ValidationIssue(
              line: lineNum,
              severity: IssueSeverity.error,
              message: 'DEFINE requires a name and value',
              suggestion: 'Example: DEFINE APP notepad',
            ));
          } else {
            defines[declaration[1]!] = declaration[2]!;
            definePattern = null;
          }
          break;

        case 'VAR':
          commandCount++;
          if (declaration == null) {
            issues.add(ValidationIssue(
              line: lineNum,
              severity: IssueSeverity.error,
              message: 'VAR requires a valid variable name',
              suggestion: 'Example: VAR \$counter = 0',
            ));
          } else {
            final varName = declaration[1]!;
            checkVariableWrite(varName, lineNum, declaration[2] ?? declaration[3]);
            if (!isFunctionParameter(varName)) scriptVariables.add(varName);
          }
          commitCommand(keyCount: 0, perCharDelayMs: 0, charCount: 0);
          break;

        case 'FUNCTION':
          if (parts.length < 2) {
            issues.add(ValidationIssue(
              line: lineNum,
              severity: IssueSeverity.error,
              message: 'FUNCTION requires a name',
              suggestion: 'Example: FUNCTION my_function',
            ));
          } else {
            final m = RegExp(r'^FUNCTION\s+([A-Za-z_][A-Za-z0-9_]*)', caseSensitive: false)
                .firstMatch(trimmed);
            final funcName = m?.group(1) ?? parts[1].replaceAll(RegExp(r'[()]'), '');
            final args = RegExp(r'\(([^()]*)\)\s*$').firstMatch(trimmed)?.group(1);
            final parameters = <String>{};
            for (final param in args?.split(',') ?? const <String>[]) {
              final name = param.trim();
              if (name.isEmpty) continue;
              final variable = name.startsWith(r'$') ? name : '\$$name';
              parameters.add(variable);
              if (_readOnlyHak5Variables.contains(variable) ||
                  _unsupportedHak5Variables.contains(variable) ||
                  _writableHak5Variables.contains(variable)) {
                issues.add(ValidationIssue(
                  line: lineNum,
                  severity: IssueSeverity.error,
                  message: 'Reserved variable $variable cannot be a function parameter',
                ));
              }
            }
            functionParameters.add(parameters);
            declaredFunctions.add(funcName.toLowerCase());
          }
          break;

        case 'END_FUNCTION':
        case 'ENDFUNCTION':
          if (functionParameters.isEmpty) {
            issues.add(ValidationIssue(
              line: lineNum,
              severity: IssueSeverity.error,
              message: 'END_FUNCTION without matching FUNCTION',
            ));
          } else {
            functionParameters.removeLast();
          }
          break;

        case 'RETURN':
          commandCount++;
          if (functionParameters.isEmpty) {
            issues.add(ValidationIssue(
              line: lineNum,
              severity: IssueSeverity.warning,
              message: 'RETURN outside of FUNCTION',
            ));
          }
          commitCommand(keyCount: 0, perCharDelayMs: 0, charCount: 0);
          break;

        case 'IF':
          ifDepth++;
          commandCount++;
          commitCommand(keyCount: 0, perCharDelayMs: 0, charCount: 0);
          break;

        case 'ELSE':
          if (ifDepth <= 0) {
            issues.add(ValidationIssue(
              line: lineNum,
              severity: IssueSeverity.error,
              message: 'ELSE without matching IF',
            ));
          }
          break;

        case 'END_IF':
        case 'ENDIF':
          if (ifDepth <= 0) {
            issues.add(ValidationIssue(
              line: lineNum,
              severity: IssueSeverity.error,
              message: 'END_IF without matching IF',
            ));
          } else {
            ifDepth--;
          }
          break;

        case 'WHILE':
          whileDepth++;
          commandCount++;
          commitCommand(keyCount: 0, perCharDelayMs: 0, charCount: 0);
          break;

        case 'END_WHILE':
        case 'ENDWHILE':
          if (whileDepth <= 0) {
            issues.add(ValidationIssue(
              line: lineNum,
              severity: IssueSeverity.error,
              message: 'END_WHILE without matching WHILE',
            ));
          } else {
            whileDepth--;
          }
          break;

        case 'TRY':
          tryHasCatch.add(false);
          break;

        case 'CATCH':
          if (tryHasCatch.isEmpty) {
            issues.add(ValidationIssue(
              line: lineNum,
              severity: IssueSeverity.error,
              message: 'CATCH without matching TRY',
            ));
          } else if (tryHasCatch.last) {
            issues.add(ValidationIssue(
              line: lineNum,
              severity: IssueSeverity.error,
              message: 'Duplicate CATCH for the same TRY',
            ));
          } else {
            tryHasCatch[tryHasCatch.length - 1] = true;
          }
          break;

        case 'END_TRY':
        case 'ENDTRY':
          if (tryHasCatch.isEmpty) {
            issues.add(ValidationIssue(
              line: lineNum,
              severity: IssueSeverity.error,
              message: 'END_TRY without matching TRY',
            ));
          } else {
            tryHasCatch.removeLast();
          }
          break;

        case 'REPEAT':
          commandCount++;
          final count = parts.length > 1 ? int.tryParse(parts[1]) : null;
          if (count == null || count <= 0) {
            issues.add(ValidationIssue(
              line: lineNum,
              severity: IssueSeverity.error,
              message: 'REPEAT requires a numeric count',
              suggestion: 'Example: REPEAT 5',
            ));
          } else if (count > remainingRepeats) {
            issues.add(ValidationIssue(
              line: lineNum,
              severity: IssueSeverity.error,
              message: 'REPEAT exceeds the script limit of $_maxScriptRepeats repetitions',
            ));
          } else {
            remainingRepeats -= count;
            overheadMs += lastCommandTotalMs * count;
          }
          break;

        case 'MOUSE':
        case 'POINTER':
          commandCount++;
          if (parts.length < 2) {
            issues.add(ValidationIssue(
              line: lineNum,
              severity: IssueSeverity.error,
              message: 'MOUSE requires an action (CLICK, MOVE, SCROLL, etc.)',
            ));
          }
          final kMs = _baseMouseMs;
          keyTimeMs += kMs;
          final oMs = _commandOverheadMs;
          overheadMs += oMs;
          lastCommandTotalMs = kMs + oMs;
          addDefaultDelayIfAny();
          break;

        default:
          final funcCallMatch = functionCall ?? _functionCallPattern.firstMatch(trimmed);
          if (funcCallMatch != null) {
            commandCount++;
            final funcName = funcCallMatch.group(1)!.toLowerCase();
            if (funcName == 'detect_os') {
              if (funcCallMatch.group(2)!.trim().isNotEmpty) {
                issues.add(ValidationIssue(
                  line: lineNum,
                  severity: IssueSeverity.error,
                  message: 'DETECT_OS() takes no arguments',
                ));
              }
            } else if (!declaredFunctions.contains(funcName)) {
              issues.add(ValidationIssue(
                line: lineNum,
                severity: IssueSeverity.warning,
                message: 'Function "$funcName" not declared in this script',
                suggestion: 'Declare it with: FUNCTION $funcName',
              ));
            }
            commitCommand(keyCount: 0, perCharDelayMs: 0, charCount: 0);
            break;
          }

          if (assignMatch != null) {
            commandCount++;
            final varName = assignMatch.group(1)!;
            checkVariableWrite(varName, lineNum, assignMatch.group(2));
            if (!isFunctionParameter(varName)) scriptVariables.add(varName);
            commitCommand(keyCount: 0, perCharDelayMs: 0, charCount: 0);
            break;
          }

          if (_supportedCommands.contains(command)) {
            commandCount++;
            if (_modifierTokens.contains(command)) {
              _validateModifierCombo(parts.skip(1), lineNum, command, issues);
            }
            if (_isSingleKeyCommand(command)) {
              commitCommand(keyCount: 1, perCharDelayMs: 0, charCount: 0);
            } else if (_isRandomCharCommand(command)) {
              commitCommand(keyCount: 1, perCharDelayMs: 0, charCount: 0);
            } else if (command == 'HOLD' || command == 'RELEASE') {
              commitCommand(keyCount: 1, perCharDelayMs: 0, charCount: 0);
            } else {
              commitCommand(keyCount: 0, perCharDelayMs: 0, charCount: 0);
            }
          } else {
            // Accept hyphen-separated combos, e.g., CTRL-ALT-T or CTRL-ALT t
            final normalized = trimmed.replaceAll('-', ' ');
            final comboParts = normalized.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
            final isModifierCombo = comboParts.any(
                  (p) => !_modifierTokens.contains(p.toUpperCase()),
                ) &&
                comboParts.every((p) {
                  final upper = p.toUpperCase();
                  return _modifierTokens.contains(upper) || _isComboKey(upper);
                });

            if (isModifierCombo) {
              commandCount++;
              final keyCount = max(1, parts.length);
              commitCommand(keyCount: keyCount, perCharDelayMs: 0, charCount: 0);
            } else {
              issues.add(ValidationIssue(
                line: lineNum,
                severity: IssueSeverity.warning,
                message: 'Unknown command: $command',
                suggestion: _findClosestCommand(command),
              ));
            }
          }
          break;
      }
    }

    for (final reference in referencedVariables.entries) {
      if (scriptVariables.contains(reference.key)) continue;
      issues.add(ValidationIssue(
        line: reference.value,
        severity: IssueSeverity.warning,
        message: '${reference.key} has no assignment in this script',
        suggestion: 'Check the spelling or initialize it with VAR',
      ));
    }

    if (ifDepth > 0) {
      issues.add(ValidationIssue(
        line: 0,
        severity: IssueSeverity.error,
        message: '$ifDepth unclosed IF statement(s)',
        suggestion: 'Add END_IF for each IF',
      ));
    }
    if (whileDepth > 0) {
      issues.add(ValidationIssue(
        line: 0,
        severity: IssueSeverity.error,
        message: '$whileDepth unclosed WHILE loop(s)',
        suggestion: 'Add END_WHILE for each WHILE',
      ));
    }
    if (functionParameters.isNotEmpty) {
      issues.add(ValidationIssue(
        line: 0,
        severity: IssueSeverity.error,
        message: '${functionParameters.length} unclosed FUNCTION(s)',
        suggestion: 'Add END_FUNCTION for each FUNCTION',
      ));
    }
    if (tryHasCatch.isNotEmpty) {
      issues.add(ValidationIssue(
        line: 0,
        severity: IssueSeverity.error,
        message: '${tryHasCatch.length} unclosed TRY block(s)',
        suggestion: 'Add END_TRY for each TRY',
      ));
    }
    if (inRemBlock) {
      issues.add(const ValidationIssue(
        line: 0,
        severity: IssueSeverity.error,
        message: 'Unclosed REM_BLOCK (missing END_REM)',
      ));
    }
    if (inStringBlock) {
      issues.add(const ValidationIssue(
        line: 0,
        severity: IssueSeverity.error,
        message: 'Unclosed STRING block (missing END_STRING)',
      ));
    }
    if (inStringLnBlock) {
      issues.add(const ValidationIssue(
        line: 0,
        severity: IssueSeverity.error,
        message: 'Unclosed STRINGLN block (missing END_STRINGLN)',
      ));
    }
    if (extensionStart != null) {
      issues.add(ValidationIssue(
        line: extensionStart,
        severity: IssueSeverity.error,
        message: 'EXTENSION is missing END_EXTENSION',
      ));
    }
    if (buttonStart != null) {
      issues.add(ValidationIssue(
        line: buttonStart,
        severity: IssueSeverity.error,
        message: 'BUTTON_DEF is missing END_BUTTON',
      ));
    }

    final estimatedDurationMs = max(0, totalDelayMs + keyTimeMs + overheadMs);
    final hasErrors = issues.any((i) => i.severity == IssueSeverity.error);
    final hasWarnings = issues.any((i) => i.severity == IssueSeverity.warning);

    return ValidationResult(
      issues: issues,
      commandCount: commandCount,
      estimatedDurationMs: estimatedDurationMs,
      totalDelayMs: totalDelayMs,
      hasErrors: hasErrors,
      hasWarnings: hasWarnings,
    );
  }

  void _validateModifierCombo(
    Iterable<String> rest,
    int line,
    String command,
    List<ValidationIssue> issues,
  ) {
    final keys = rest
        .expand((part) => part.toUpperCase().split('-'))
        .where((part) => part.isNotEmpty && !_modifierTokens.contains(part))
        .toList();
    if (keys.isEmpty) {
      issues.add(
        ValidationIssue(
          line: line,
          severity: IssueSeverity.warning,
          message: 'Modifier command requires a key',
          suggestion: 'Example: $command r',
        ),
      );
      return;
    }
    if (keys.length > 1) {
      issues.add(
        ValidationIssue(
          line: line,
          severity: IssueSeverity.warning,
          message: 'Modifier combo supports one key',
          suggestion: 'Use one key after the modifiers',
        ),
      );
    }
    for (final key in keys) {
      if (!_isComboKey(key)) {
        issues.add(
          ValidationIssue(
            line: line,
            severity: IssueSeverity.warning,
            message: 'Unknown key: $key',
            suggestion: 'Use a key such as r, ENTER, TAB, F4, or UP',
          ),
        );
      }
    }
  }

  bool _isComboKey(String key) {
    if (RegExp(r'^[A-Z0-9]$').hasMatch(key)) return true;
    return _comboKeys.contains(key);
  }

  bool _isSingleKeyCommand(String cmd) {
    switch (cmd) {
      case 'ENTER':
      case 'TAB':
      case 'ESC':
      case 'ESCAPE':
      case 'BACKSPACE':
      case 'BKSP':
      case 'DELETE':
      case 'DEL':
      case 'SPACE':
      case 'UP':
      case 'DOWN':
      case 'LEFT':
      case 'RIGHT':
      case 'UPARROW':
      case 'DOWNARROW':
      case 'LEFTARROW':
      case 'RIGHTARROW':
      case 'PAGEUP':
      case 'PAGEDOWN':
      case 'HOME':
      case 'END':
      case 'INSERT':
      case 'CAPSLOCK':
      case 'NUMLOCK':
      case 'SCROLLLOCK':
      case 'PRINTSCREEN':
      case 'PRINTSCRN':
      case 'PRTSCN':
      case 'MENU':
      case 'APP':
      case 'PAUSE':
      case 'BREAK':
      case 'F1':
      case 'F2':
      case 'F3':
      case 'F4':
      case 'F5':
      case 'F6':
      case 'F7':
      case 'F8':
      case 'F9':
      case 'F10':
      case 'F11':
      case 'F12':
      case 'F13':
      case 'F14':
      case 'F15':
      case 'F16':
      case 'F17':
      case 'F18':
      case 'F19':
      case 'F20':
      case 'F21':
      case 'F22':
      case 'F23':
      case 'F24':
      case 'MEDIA_PLAYPAUSE':
      case 'PLAYPAUSE':
      case 'MEDIA_STOP':
      case 'STOPCD':
      case 'MEDIA_PREV':
      case 'PREVIOUSSONG':
      case 'MEDIA_NEXT':
      case 'NEXTSONG':
      case 'MEDIA_VOLUMEUP':
      case 'VOLUMEUP':
      case 'MEDIA_VOLUMEDOWN':
      case 'VOLUMEDOWN':
      case 'MEDIA_MUTE':
      case 'MUTE':
        return true;
      default:
        return false;
    }
  }

  bool _isRandomCharCommand(String cmd) {
    switch (cmd) {
      case 'RANDOM_LOWERCASE_LETTER':
      case 'RANDOMLOWERCASELETTER':
      case 'RANDOM_UPPERCASE_LETTER':
      case 'RANDOMUPPERCASELETTER':
      case 'RANDOM_LETTER':
      case 'RANDOMLETTER':
      case 'RANDOM_NUMBER':
      case 'RANDOMNUMBER':
      case 'RANDOM_SPECIAL':
      case 'RANDOMSPECIAL':
      case 'RANDOM_CHAR':
      case 'RANDOMCHAR':
        return true;
      default:
        return false;
    }
  }

  String? _findClosestCommand(String input) {
    final upper = input.toUpperCase();
    if (_commonTypos.containsKey(upper)) {
      return 'Did you mean ${_commonTypos[upper]}?';
    }
    String? closest;
    int minDistance = 999;
    for (final cmd in _supportedCommands) {
      final distance = _levenshteinDistance(upper, cmd);
      if (distance < minDistance && distance <= 3) {
        minDistance = distance;
        closest = cmd;
      }
    }
    return closest != null ? 'Did you mean $closest?' : null;
  }

  int _levenshteinDistance(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    final len1 = s1.length;
    final len2 = s2.length;
    final matrix = List.generate(len1 + 1, (_) => List.filled(len2 + 1, 0));

    for (int i = 0; i <= len1; i++) {
      matrix[i][0] = i;
    }
    for (int j = 0; j <= len2; j++) {
      matrix[0][j] = j;
    }

    for (int i = 1; i <= len1; i++) {
      for (int j = 1; j <= len2; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        matrix[i][j] = min(
          min(matrix[i - 1][j] + 1, matrix[i][j - 1] + 1),
          matrix[i - 1][j - 1] + cost,
        );
      }
    }
    return matrix[len1][len2];
  }
}
