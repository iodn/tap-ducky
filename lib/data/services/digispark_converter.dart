class DigiConvertResult {
  final String text;
  final bool usedMouseApis;
  DigiConvertResult(this.text, this.usedMouseApis);
}

class DigiSparkConverter {
  static const _modMap = {
    'MOD_GUI_LEFT': 'GUI',
    'MOD_GUI_RIGHT': 'GUI',
    'MOD_ALT_LEFT': 'ALT',
    'MOD_ALT_RIGHT': 'ALT',
    'MOD_CONTROL_LEFT': 'CTRL',
    'MOD_CONTROL_RIGHT': 'CTRL',
    'MOD_SHIFT_LEFT': 'SHIFT',
    'MOD_SHIFT_RIGHT': 'SHIFT',
  };

  static const _keyMap = {
    // common aliases
    'KEY_RETURN': 'ENTER',
    'KEY_CAPSLOCK': 'CAPSLOCK',
    'KEY_CAPS_LOCK': 'CAPSLOCK',
    'KEY_PRINTSCREEN': 'PRINTSCREEN',
    'KEY_PRTSC': 'PRINTSCREEN',
    'KEY_MENU': 'MENU',
    'KEY_APP': 'APP',
    // arrow aliases seen in sketches
    'KEY_ARROW_LEFT': 'LEFT',
    'KEY_ARROW_RIGHT': 'RIGHT',
    'KEY_ARROW_UP': 'UP',
    'KEY_ARROW_DOWN': 'DOWN',
    'KEY_LEFT_ARROW': 'LEFT',
    'KEY_RIGHT_ARROW': 'RIGHT',
    'KEY_UP_ARROW': 'UP',
    'KEY_DOWN_ARROW': 'DOWN',
    // standard keys
    'KEY_ENTER': 'ENTER',
    'KEY_TAB': 'TAB',
    'KEY_ESC': 'ESC',
    'KEY_ESCAPE': 'ESC',
    'KEY_BACKSPACE': 'BACKSPACE',
    'KEY_SPACE': 'SPACE',
    'KEY_UP': 'UP',
    'KEY_DOWN': 'DOWN',
    'KEY_LEFT': 'LEFT',
    'KEY_RIGHT': 'RIGHT',
    'KEY_DELETE': 'DELETE',
    'KEY_HOME': 'HOME',
    'KEY_END': 'END',
    'KEY_PAGE_UP': 'PAGEUP',
    'KEY_PAGE_DOWN': 'PAGEDOWN',
    'KEY_F1': 'F1',
    'KEY_F2': 'F2',
    'KEY_F3': 'F3',
    'KEY_F4': 'F4',
    'KEY_F5': 'F5',
    'KEY_F6': 'F6',
    'KEY_F7': 'F7',
    'KEY_F8': 'F8',
    'KEY_F9': 'F9',
    'KEY_F10': 'F10',
    'KEY_F11': 'F11',
    'KEY_F12': 'F12',
  };

  static DigiConvertResult? convert(String input) {
    // Quick heuristic: require DigiKeyboard include or calls
    if (!input.contains('DigiKeyboard')) return null;
    final lines = input.replaceAll('\r', '').split('\n');
    final out = <String>[];
    bool usedMouseApis = false;

    for (var raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('//')) continue;
      if (line.startsWith('/*')) continue; // naive skip of block comments start
      if (line.startsWith('#')) continue; // preprocessor lines

      // delay
      final delayMatch = RegExp(r'DigiKeyboard\.delay\((\d+)\)\s*;').firstMatch(line);
      if (delayMatch != null) {
        final ms = int.tryParse(delayMatch.group(1)!);
        if (ms != null) out.add('DELAY $ms');
        continue;
      }

      // print / println (supports F("...") and splits on \n)
      final printMatch = RegExp(r'DigiKeyboard\.(print|println)\((.+)\)\s*;').firstMatch(line);
      if (printMatch != null) {
        final method = printMatch.group(1)!; // print or println
        final arg = printMatch.group(2)!;
        final text = _extractStringLiteralSmart(arg);
        if (text != null) {
          final parts = text.split('\\n'); // split on escaped newlines
          if (method == 'println') {
            if (parts.isEmpty) {
              out.add('ENTER');
            } else {
              for (final seg in parts) {
                if (seg.isEmpty) {
                  out.add('ENTER');
                } else {
                  out.add('STRINGLN $seg');
                }
              }
            }
          } else {
            // print: no trailing newline; just type segments
            for (final seg in parts) {
              if (seg.isEmpty) continue;
              out.add('STRING $seg');
            }
          }
        }
        continue;
      }

      // sendKeyStroke(KEY, MOD[, MOD...]) or sendKeyPress
      final strokeMatch = RegExp(r'DigiKeyboard\.(sendKeyStroke|sendKeyPress|pressKey|releaseKey)\(([^)]*)\)\s*;').firstMatch(line);
      if (strokeMatch != null) {
        final args = strokeMatch.group(2)!.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        if (args.isEmpty) continue;
        final keyToken = args.first;
        final mods = args.skip(1).toList();
        final combo = <String>[];
        final method = strokeMatch.group(1)!;

        // map modifiers
        for (final m in mods) {
          final mm = _modMap[m] ?? _modMap[m.replaceAll('(', '').replaceAll(')', '')];
          if (mm != null) combo.add(mm);
        }

        String? keyStr;
        if (_keyMap.containsKey(keyToken)) {
          keyStr = _keyMap[keyToken];
        } else if (RegExp(r'^KEY_[A-Z0-9]$').hasMatch(keyToken)) {
          // KEY_R -> R
          final ch = keyToken.substring(4);
          if (ch.length == 1) {
            keyStr = ch.toUpperCase();
          }
        } else if (RegExp(r'^\d+$').hasMatch(keyToken)) {
          // numeric key code e.g., 70 => 'F', 81 => 'Q'
          final code = int.tryParse(keyToken);
          if (code != null && code >= 32 && code <= 126) {
            keyStr = String.fromCharCode(code).toUpperCase();
          }
        } else if (keyToken == '0') {
          // no-op
          keyStr = null;
        }

        if (keyStr != null) {
          final parts = [...combo, keyStr];
          if (method == 'pressKey') {
            out.add('HOLD ${parts.join(' ')}');
          } else if (method == 'releaseKey') {
            out.add('RELEASE ${parts.join(' ')}');
          } else if (combo.isEmpty) {
            // single key
            if (keyStr.length == 1 && RegExp(r'^[A-Z]$').hasMatch(keyStr)) {
              // Letters are not recognized as standalone key commands by our validator; use STRING
              out.add('STRING $keyStr');
            } else {
              out.add(keyStr);
            }
          } else {
            out.add(parts.join(' '));
          }
        }
        continue;
      }

      // DigiMouse / Mouse API support
      // move(x,y[,wheel])
      final mouseMove = RegExp(r'(DigiMouse|Mouse)\.move\(\s*(-?\d+)\s*,\s*(-?\d+)(?:\s*,\s*(-?\d+)\s*)?\)\s*;').firstMatch(line);
      if (mouseMove != null) {
        usedMouseApis = true;
        final dx = int.tryParse(mouseMove.group(2)! ) ?? 0;
        final dy = int.tryParse(mouseMove.group(3)! ) ?? 0;
        final wheel = mouseMove.group(4) != null ? int.tryParse(mouseMove.group(4)!) ?? 0 : 0;
        if (dx != 0 || dy != 0) out.add('MOUSE MOVE $dx $dy');
        if (wheel != 0) {
          final direction = wheel > 0 ? 'UP' : 'DOWN';
          out.add('MOUSE SCROLL $direction ${wheel.abs()}');
        }
        continue;
      }
      // scroll dedicated forms
      final wheelScroll = RegExp(r'(DigiMouse|Mouse)\.scroll\(\s*(-?\d+)\s*\)\s*;').firstMatch(line);
      if (wheelScroll != null) {
        usedMouseApis = true;
        final amt = int.tryParse(wheelScroll.group(2)! ) ?? 0;
        if (amt != 0) {
          final direction = amt > 0 ? 'UP' : 'DOWN';
          out.add('MOUSE SCROLL $direction ${amt.abs()}');
        }
        continue;
      }
      // DigiMouse click helpers: leftClick(), rightClick(), middleClick()
      final digiClick = RegExp(r'DigiMouse\.(leftClick|rightClick|middleClick)\(\s*\)\s*;').firstMatch(line);
      if (digiClick != null) {
        usedMouseApis = true;
        final button = digiClick.group(1)!.replaceAll('Click', '').toUpperCase();
        out.add('MOUSE CLICK $button');
        continue;
      }
      // click/press/release
      final mouseClick = RegExp(r'(DigiMouse|Mouse)\.click\(\s*([A-Z_]+)?\s*\)\s*;').firstMatch(line);
      if (mouseClick != null) {
        usedMouseApis = true;
        final btn = _mapMouseButton(mouseClick.group(2));
        out.add('MOUSE CLICK $btn');
        continue;
      }
      final mousePress = RegExp(r'(DigiMouse|Mouse)\.press\(\s*([A-Z_]+)\s*\)\s*;').firstMatch(line);
      if (mousePress != null) {
        usedMouseApis = true;
        final btn = _mapMouseButton(mousePress.group(2));
        out.add('MOUSE DOWN $btn');
        continue;
      }
      final mouseRelease = RegExp(r'(DigiMouse|Mouse)\.release\(\s*([A-Z_]+)\s*\)\s*;').firstMatch(line);
      if (mouseRelease != null) {
        usedMouseApis = true;
        final btn = _mapMouseButton(mouseRelease.group(2));
        out.add('MOUSE UP $btn');
        continue;
      }

      // for(;;) infinite loop -> stop processing further
      if (line.startsWith('for') && line.contains(';;')) {
        break;
      }

      // ignore others (setup, loop braces, etc.)
    }

    if (out.isEmpty) return null;

    // Post-process: introduce DEFAULTDELAY to minimize repetitive small delays
    final delayCounts = <int, int>{};
    final delayRe = RegExp(r'^DELAY\s+(\d+)$');
    for (final cmd in out) {
      final m = delayRe.firstMatch(cmd);
      if (m != null) {
        final v = int.tryParse(m.group(1)!);
        if (v != null) delayCounts[v] = (delayCounts[v] ?? 0) + 1;
      }
    }

    if (delayCounts.isNotEmpty) {
      // Choose the most frequent small-ish delay (e.g., <= 1000ms)
      int? bestDelay;
      int bestCount = 0;
      delayCounts.forEach((k, v) {
        if (k <= 1000 && v > bestCount) {
          bestDelay = k;
          bestCount = v;
        }
      });
      if (bestDelay != null && bestCount >= 4) {
        // Remove all DELAY bestDelay and add DEFAULTDELAY at the top
        final filtered = <String>[];
        for (final cmd in out) {
          final m = delayRe.firstMatch(cmd);
          if (m != null && int.tryParse(m.group(1)!) == bestDelay) {
            continue; // skip redundant delay
          }
          filtered.add(cmd);
        }
        out
          ..clear()
          ..add('DEFAULTDELAY $bestDelay')
          ..addAll(filtered);
      }
    }

    return DigiConvertResult(out.join('\n'), usedMouseApis);
  }

  static String? _extractStringLiteralSmart(String arg) {
    // Prefer F("...") macro first
    final f = RegExp(r'F\(\s*"((?:\\.|[^"\\])*)"\s*\)').firstMatch(arg);
    String? captured;
    if (f != null) {
      captured = f.group(1);
    } else {
      final m = RegExp(r'"((?:\\.|[^"\\])*)"').firstMatch(arg);
      if (m == null) return null;
      captured = m.group(1);
    }
    var s = captured ?? '';
    // unescape minimal sequences
    s = s.replaceAll('\\"', '"');
    // keep \\n as literal to split by caller
    return s;
  }

  static String _mapMouseButton(String? token) {
    if (token == null || token.isEmpty) return 'left';
    final t = token.toUpperCase();
    if (t.contains('LEFT') || t.contains('BUTTON1')) return 'left';
    if (t.contains('RIGHT') || t.contains('BUTTON2')) return 'right';
    if (t.contains('MIDDLE') || t.contains('BUTTON3')) return 'middle';
    return 'left';
  }
}
