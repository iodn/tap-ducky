import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ducky_script_validator.dart';

final localDraftsServiceProvider = Provider((ref) => LocalDraftsService());
final localModelStatusProvider = FutureProvider((ref) {
  return ref.watch(localDraftsServiceProvider).status();
});

typedef LocalModelStatus = ({String state, String? name, int? sizeBytes});

class LocalDraftsService {
  static const _channel = MethodChannel('org.kaijinlab.tap_ducky/local_drafts');

  Future<LocalModelStatus> status() async {
    const LocalModelStatus unsupported = (
      state: 'unsupported',
      name: null,
      sizeBytes: null,
    );
    try {
      final data = await _channel.invokeMapMethod<String, dynamic>('status');
      if (data == null) return unsupported;
      return (
        state: data['state'] as String? ?? 'unsupported',
        name: data['name'] as String?,
        sizeBytes: data['sizeBytes'] as int?,
      );
    } on MissingPluginException {
      return unsupported;
    }
  }

  Future<void> pickModel() => _channel.invokeMethod<bool>('pickModel');
  Future<void> removeModel() => _channel.invokeMethod<void>('removeModel');

  Future<PayloadDraft> generate(String prompt) async {
    final response = await _channel.invokeMethod<String>('generate', {
      'prompt': prompt,
    });
    return PayloadDraft.fromResponse(response ?? '', prompt: prompt);
  }
}

class PayloadDraft {
  const PayloadDraft._(this.title, this.description, this.tags, this.script);

  final String title;
  final String description;
  final List<String> tags;
  final String script;

  factory PayloadDraft.fromResponse(String response, {String prompt = ''}) {
    var json = response.trim();
    final fence = RegExp(
      r'^```(?:json)?\s*([\s\S]*?)\s*```$',
      caseSensitive: false,
    );
    json = fence.firstMatch(json)?.group(1) ?? json;

    try {
      if (json.length > 8192) {
        throw const FormatException('Draft is too long.');
      }
      final data = jsonDecode(json);
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Expected a draft object.');
      }
      final script =
          _compileSteps(data['steps']) ?? _compileRawScript(data['script']);
      if (script == null) {
        throw const FormatException('Unsupported draft.');
      }
      return PayloadDraft._(
        _cleanField(data['title'], 60) ?? _titleFromPrompt(prompt),
        _cleanField(data['description'], 240) ?? 'Generated from the request.',
        List.unmodifiable(_cleanTags(data['tags']) ?? const ['ai']),
        script,
      );
    } on FormatException {
      if (prompt.trim().isEmpty) rethrow;
      return _fallback(prompt);
    } on TypeError {
      if (prompt.trim().isEmpty) rethrow;
      return _fallback(prompt);
    }
  }

  static String? _compileSteps(Object? value) {
    if (value is String) {
      final raw = _sanitizeRaw(value);
      if (raw.isEmpty) return null;
      return _validated(['DELAY 1000', ...raw]);
    }
    if (value is! List || value.isEmpty || value.length > 40) return null;

    final lines = <String>['DELAY 1000'];
    final rawBlocks = <List<String>>[];

    for (final item in value) {
      if (item is String) {
        final block = _sanitizeRaw(item);
        if (block.isNotEmpty) rawBlocks.add(block);
        continue;
      }
      if (item is! Map) continue;
      final actionValue = item['action'];
      final action = actionValue is String
          ? actionValue.trim().toLowerCase()
          : null;
      if (action == null || action.isEmpty) continue;
      final rawValue = item['value'];
      final valueText = rawValue is String ? rawValue.trim() : null;

      switch (action) {
        case 'open_url':
          final url = _extractUrl(valueText);
          if (url == null) break;
          lines.addAll([
            'GUI r',
            'DELAY 800',
            'STRING $url',
            'ENTER',
            'DELAY 3000',
          ]);
          break;

        case 'open_app':
          final app = _cleanText(valueText, 120);
          if (app == null) break;
          lines.addAll([
            'GUI r',
            'DELAY 800',
            'STRING $app',
            'ENTER',
            'DELAY 3000',
          ]);
          break;

        case 'type':
          final text = _cleanText(valueText, 400);
          if (text == null) break;
          lines.add('STRING $text');
          break;

        case 'type_line':
          final text = _cleanText(valueText, 400);
          if (text == null) break;
          lines.add('STRINGLN $text');
          break;

        case 'key':
          final key = _normalizeKey(valueText);
          if (key == null) break;
          lines.add(key);
          break;

        case 'shortcut':
          final combo = _normalizeShortcut(valueText);
          if (combo == null) break;
          lines.add(combo);
          break;

        case 'delay':
          final delay = _intValue(item['ms']) ?? _intValue(valueText);
          if (delay == null) break;
          lines.add('DELAY ${delay.clamp(20, 60000).toInt()}');
          break;

        case 'mouse_click':
          final button = _mouseButton(valueText);
          if (button == null) break;
          lines.add('MOUSE CLICK $button');
          break;

        case 'mouse_move':
          final pair = _parsePair(valueText);
          if (pair == null) break;
          lines.add('MOUSE MOVE ${pair.$1} ${pair.$2}');
          break;

        case 'mouse_scroll':
          final direction = valueText?.toUpperCase();
          if (direction != 'UP' && direction != 'DOWN') break;
          lines.add('MOUSE SCROLL $direction');
          break;

        case 'repeat':
          final count = _intValue(item['ms']) ?? _intValue(valueText);
          if (count == null) break;
          lines.add('REPEAT ${count.clamp(1, 1000).toInt()}');
          break;

        case 'comment':
          final comment = _cleanText(valueText, 200);
          if (comment == null) break;
          lines.add('REM $comment');
          break;

        case 'raw':
          final block = _sanitizeRaw(valueText);
          if (block.isNotEmpty) rawBlocks.add(block);
          break;

        default:
          final text = valueText == null || valueText.isEmpty
              ? action
              : '$action $valueText';
          final line = _normalizeLine(text);
          if (line != null) rawBlocks.add([line]);
          break;
      }
    }

    final base = List<String>.from(lines);
    final withRaw = [...base, for (final block in rawBlocks) ...block];
    return _validated(withRaw) ?? _validated(base);
  }

  static String? _compileRawScript(Object? value) {
    if (value is! String) return null;
    final raw = _sanitizeRaw(value);
    if (raw.isEmpty) return null;
    return _validated(['DELAY 1000', ...raw]);
  }

  static String? _validated(List<String> lines) {
    final script = lines.join('\n').trim();
    if (script.isEmpty || script.length > 6000 || lines.length > 200) {
      return null;
    }
    if (!RegExp(r'^[ -~\n]+$').hasMatch(script)) return null;

    final actionable = lines.any((line) {
      final command = line.trim().split(RegExp(r'\s+')).first.toUpperCase();
      return command.isNotEmpty && command != 'DELAY' && command != 'REM';
    });
    if (!actionable) return null;

    final repeats = RegExp(
      r'^\s*REPEAT\s+([0-9]+)\s*$',
      caseSensitive: false,
      multiLine: true,
    );
    for (final match in repeats.allMatches(script)) {
      if (int.parse(match.group(1)!) > 1000) return null;
    }

    final result = DuckyScriptValidator().validate(script);
    if (result.commandCount == 0 || result.hasErrors || result.hasWarnings) {
      return null;
    }
    return script;
  }

  static List<String> _sanitizeRaw(String? value) {
    if (value == null) return const [];
    final lines = <String>[];
    for (final rawLine
        in value.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n')) {
      final line = _normalizeLine(rawLine);
      if (line == null || line.length > 400) continue;
      lines.add(line);
      if (lines.length >= 100) break;
    }
    return lines;
  }

  static String? _normalizeLine(String raw) {
    var line = raw.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
    if (line.isEmpty) return null;
    line = line
        .replaceAll(RegExp(r'^`+'), '')
        .replaceAll(RegExp(r'`+$'), '')
        .replaceAll(RegExp(r'^[-*]\s+'), '')
        .trim();
    if (line.isEmpty) return null;
    if (line.toUpperCase().startsWith('ATTACKMODE')) return null;

    if (RegExp(r'^[A-Za-z0-9]+(?:\s*[+\-]\s*[A-Za-z0-9]+)+$').hasMatch(line)) {
      final combo = _normalizeShortcut(line);
      if (combo != null) return combo;
    }
    return line;
  }

  static PayloadDraft _fallback(String prompt) {
    final text = _ascii(prompt);
    final url = _extractUrl(text);
    if (url != null) {
      final host = Uri.tryParse(url)?.host ?? url;
      return PayloadDraft._(
        _clip('Open $host', 60),
        _clip('Opens $url in the default browser.', 240),
        const ['browser'],
        'DELAY 1000\nGUI r\nDELAY 800\nSTRING $url\nENTER\nDELAY 3000',
      );
    }

    final open = RegExp(
      r'^\s*(?:please\s+)?(?:open|launch|start)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (open != null) {
      final target = _clip(_ascii(open.group(1)!), 120);
      if (target.isNotEmpty) {
        return PayloadDraft._(
          _clip('Open $target', 60),
          _clip('Opens $target from the Run dialog.', 240),
          const ['windows'],
          'DELAY 1000\nGUI r\nDELAY 800\nSTRING $target\nENTER\nDELAY 3000',
        );
      }
    }

    final press = RegExp(
      r'^\s*(?:please\s+)?(?:press|hit)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (press != null) {
      final combo = _normalizeShortcut(press.group(1));
      if (combo != null) {
        return PayloadDraft._(
          _clip('Press $combo', 60),
          'Presses the requested key.',
          const ['keyboard'],
          'DELAY 1000\n$combo',
        );
      }
    }

    final type = RegExp(
      r'^\s*(?:please\s+)?(?:type|write|enter)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(text);
    final typed = _clip(_ascii(type?.group(1) ?? text), 400);
    final safe = typed.isEmpty ? 'hello' : typed;
    return PayloadDraft._(
      _clip('Type $safe', 60),
      'Types the requested text.',
      const ['text'],
      'DELAY 1000\nSTRING $safe\nENTER',
    );
  }

  static String? _extractUrl(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;

    final withScheme = RegExp(
      r'''https?://[^\s<>"']+''',
      caseSensitive: false,
    ).firstMatch(text)?.group(0);
    final withoutScheme = RegExp(
      r'''(?:www\.)?[a-zA-Z0-9][a-zA-Z0-9-]*(?:\.[a-zA-Z0-9-]+)*\.(?:com|org|net|io|dev|app|ai|co|me|info|biz|edu|gov|uk|de|fr|jp|au|ca|ch|se|no|es|it|nl|ru|cn|in|br|us|xyz|tech|store|online|site)\b(?:/[^\s<>"']*)?''',
      caseSensitive: false,
    ).firstMatch(text)?.group(0);
    final candidate = withScheme ?? withoutScheme;
    if (candidate == null) return null;

    var url = _trimUrl(candidate);
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(url)) {
      url = 'https://$url';
    }
    url = _ascii(url);
    final parsed = Uri.tryParse(url);
    if (parsed == null || parsed.host.isEmpty || !parsed.host.contains('.')) {
      return null;
    }
    return url;
  }

  static String _trimUrl(String url) {
    var value = url.trim();
    while (value.isNotEmpty &&
        '.,;:!?)]}\'"'.contains(value[value.length - 1])) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  static String? _normalizeKey(String? value) {
    if (value == null) return null;
    final key = value.trim().toUpperCase();
    if (key.isEmpty) return null;
    if (RegExp(r'^[A-Z0-9]$').hasMatch(key)) return key;
    return _keys.contains(key) ? key : null;
  }

  static String? _normalizeShortcut(String? value) {
    if (value == null) return null;
    final tokens = value
        .toUpperCase()
        .split(RegExp(r'[+\-,\s]+'))
        .where((token) => token.isNotEmpty);
    final modifiers = <String>[];
    String? key;
    for (final token in tokens) {
      final modifier = _canonicalModifier(token);
      if (modifier != null) {
        if (!modifiers.contains(modifier)) modifiers.add(modifier);
        continue;
      }
      final candidate = _normalizeKey(token);
      if (candidate == null) return null;
      key = candidate;
    }
    if (key == null) return null;
    return [...modifiers, key].join(' ');
  }

  static String? _canonicalModifier(String token) {
    switch (token) {
      case 'CTRL':
      case 'CONTROL':
        return 'CTRL';
      case 'RCTRL':
      case 'RCONTROL':
        return 'RCTRL';
      case 'SHIFT':
        return 'SHIFT';
      case 'RSHIFT':
        return 'RSHIFT';
      case 'ALT':
      case 'OPTION':
        return 'ALT';
      case 'RALT':
        return 'RALT';
      case 'GUI':
      case 'WIN':
      case 'WINDOWS':
      case 'COMMAND':
      case 'SUPER':
      case 'META':
        return 'GUI';
      case 'RGUI':
      case 'RWINDOWS':
      case 'RCOMMAND':
        return 'RGUI';
    }
    return null;
  }

  static String? _mouseButton(String? value) {
    switch (value?.trim().toUpperCase()) {
      case 'LEFT':
      case 'L':
        return 'LEFT';
      case 'RIGHT':
      case 'R':
        return 'RIGHT';
      case 'MIDDLE':
      case 'M':
        return 'MIDDLE';
    }
    return null;
  }

  static (int, int)? _parsePair(String? value) {
    if (value == null) return null;
    final match = RegExp(r'(-?\d+)\s*[,\s]\s*(-?\d+)').firstMatch(value);
    if (match == null) return null;
    final x = int.tryParse(match.group(1)!);
    final y = int.tryParse(match.group(2)!);
    if (x == null || y == null) return null;
    return (_clampMouse(x), _clampMouse(y));
  }

  static int _clampMouse(int value) =>
      value < -127 ? -127 : (value > 127 ? 127 : value);

  static int? _intValue(Object? value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static String? _cleanField(Object? value, int limit) {
    if (value is! String) return null;
    return _cleanText(value, limit);
  }

  static String? _cleanText(String? value, int limit) {
    if (value == null) return null;
    final text = _ascii(value);
    if (text.isEmpty) return null;
    return _clip(text, limit);
  }

  static List<String>? _cleanTags(Object? value) {
    if (value is! List) return null;
    final tags = <String>[];
    for (final tag in value) {
      if (tag is! String) continue;
      final cleaned = tag.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
      if (cleaned.isEmpty || cleaned.length > 24) continue;
      tags.add(cleaned);
      if (tags.length == 5) break;
    }
    return tags.isEmpty ? null : tags;
  }

  static String _titleFromPrompt(String prompt) {
    return _cleanText(prompt, 60) ?? 'AI draft';
  }

  static String _ascii(String input) {
    return input
        .replaceAll(RegExp(r'[^\x20-\x7E]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _clip(String value, int limit) {
    final text = value.trim();
    return text.length <= limit ? text : text.substring(0, limit).trimRight();
  }

  static const Set<String> _mediaKeys = {
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
  };

  static final Set<String> _keys = {
    'ENTER',
    'TAB',
    'ESC',
    'ESCAPE',
    'SPACE',
    'BACKSPACE',
    'BKSP',
    'DELETE',
    'DEL',
    'INSERT',
    'INS',
    'HOME',
    'END',
    'PAGEUP',
    'PAGEDOWN',
    'UP',
    'DOWN',
    'LEFT',
    'RIGHT',
    'UPARROW',
    'DOWNARROW',
    'LEFTARROW',
    'RIGHTARROW',
    'CAPSLOCK',
    'NUMLOCK',
    'SCROLLLOCK',
    'PRINTSCREEN',
    'PRINTSCRN',
    'PRTSCN',
    'PAUSE',
    'BREAK',
    'MENU',
    'APP',
    for (var i = 1; i <= 24; i++) 'F$i',
    ..._mediaKeys,
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
}
