import 'package:material_ui/material_ui.dart';

import '../data/services/ducky_script_validator.dart';

enum _Kind { command, comment, literal, number, variable }

typedef _Token = (String, _Kind?);

final _commandPattern = RegExp(r'^\s*(\S+)');
final _variablePattern = RegExp(
  r'\{\{[^{}\n]+\}\}|\$\{[^{}\n]+\}|\$[\w-]+|#[\w-]+',
);
final _operandPattern = RegExp(
  r'''\{\{[^{}\n]+\}\}|\$\{[^{}\n]+\}|\$[\w-]+|#[\w-]+|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|(?<![\w.])-?\d+(?:\.\d+)?(?![\w.])|\b[A-Za-z][A-Za-z0-9_]*\b''',
);
final _delayPrefix = RegExp(r'^\s+[-+]?\d+(?=\s|$)');

Iterable<_Token> _segments(
  String text,
  RegExp pattern,
  _Kind? Function(String) classify, {
  _Kind? base,
}) sync* {
  var offset = 0;
  for (final match in pattern.allMatches(text)) {
    if (offset < match.start) yield (text.substring(offset, match.start), base);
    final part = match.group(0)!;
    yield (part, classify(part));
    offset = match.end;
  }
  if (offset < text.length) yield (text.substring(offset), base);
}

_Kind? _operandKind(String word) {
  if (word.startsWith(r'$') || word.startsWith('#') || word.startsWith('{{')) {
    return _Kind.variable;
  }
  if (word.startsWith('"') || word.startsWith("'")) return _Kind.literal;
  if (double.tryParse(word) != null) return _Kind.number;
  return DuckyScriptValidator.isSupportedCommand(word) ? _Kind.command : null;
}

List<_Token> _tokenize(String source) {
  final lines = source.split('\n');
  final tokens = <_Token>[];
  String? end;
  for (var i = 0; i < lines.length; i++) {
    if (i > 0) tokens.add(('\n', null));
    final line = lines[i];
    final trimmed = line.trim();
    if (end != null && trimmed.toUpperCase() != end) {
      if (end == 'END_REM') {
        tokens.add((line, _Kind.comment));
      } else {
        tokens.addAll(
          _segments(
            line,
            _variablePattern,
            (_) => _Kind.variable,
            base: _Kind.literal,
          ),
        );
      }
      continue;
    }
    end = null;

    final match = _commandPattern.firstMatch(line);
    if (match == null) {
      tokens.add((line, null));
      continue;
    }
    final word = match.group(1)!;
    final command = word.toUpperCase();
    final rest = line.substring(match.end);
    final kind = DuckyScriptValidator.isSupportedCommand(word)
        ? _Kind.command
        : null;
    if (command == 'REM' ||
        command.startsWith('//') ||
        (command.startsWith('#') && !command.startsWith('#{'))) {
      tokens.add((line, _Kind.comment));
      continue;
    }

    tokens.add((line.substring(0, match.end - word.length), null));
    tokens.add((word, kind));
    if (command == 'REM_BLOCK') {
      end = 'END_REM';
      tokens.add((rest, _Kind.comment));
    } else if (command == 'STRING' || command == 'STRINGLN') {
      if (rest.trim().isEmpty) end = 'END_$command';
      tokens.addAll(
        _segments(
          rest,
          _variablePattern,
          (_) => _Kind.variable,
          base: _Kind.literal,
        ),
      );
    } else if (command == 'STRING_DELAY' || command == 'STRINGDELAY') {
      final delay = _delayPrefix.firstMatch(rest);
      final offset = delay?.end ?? 0;
      if (offset > 0) tokens.add((rest.substring(0, offset), _Kind.number));
      tokens.addAll(
        _segments(
          rest.substring(offset),
          _variablePattern,
          (_) => _Kind.variable,
          base: _Kind.literal,
        ),
      );
    } else {
      tokens.addAll(_segments(rest, _operandPattern, _operandKind));
    }
  }
  return tokens;
}

TextStyle? _tokenStyle(Brightness brightness, _Kind? kind) {
  if (kind == null) return null;
  final dark = brightness == Brightness.dark;
  final color = switch (kind) {
    _Kind.command => dark ? const Color(0xffbdcaff) : const Color(0xff343686),
    _Kind.comment => dark ? const Color(0xffb0bdb4) : const Color(0xff505d55),
    _Kind.literal => dark ? const Color(0xffa5dfba) : const Color(0xff245637),
    _Kind.number => dark ? const Color(0xffffca96) : const Color(0xff783e14),
    _Kind.variable => dark ? const Color(0xfff5b9db) : const Color(0xff8b2659),
  };
  return TextStyle(
    color: color,
    fontWeight: kind == _Kind.command ? FontWeight.w600 : null,
    fontStyle: kind == _Kind.comment ? FontStyle.italic : null,
  );
}

TextSpan _highlight(
  BuildContext context,
  List<_Token> tokens, {
  TextStyle? style,
  TextRange? composing,
}) {
  final brightness = Theme.of(context).brightness;
  final children = <TextSpan>[];
  var offset = 0;
  for (final (text, kind) in tokens) {
    if (text.isEmpty) continue;
    final next = offset + text.length;
    final tokenStyle = _tokenStyle(brightness, kind);
    if (composing != null && composing.start < next && composing.end > offset) {
      final start = (composing.start - offset).clamp(0, text.length);
      final end = (composing.end - offset).clamp(0, text.length);
      if (start > 0)
        children.add(
          TextSpan(text: text.substring(0, start), style: tokenStyle),
        );
      children.add(
        TextSpan(
          text: text.substring(start, end),
          style: (tokenStyle ?? const TextStyle()).copyWith(
            decoration: TextDecoration.underline,
          ),
        ),
      );
      if (end < text.length)
        children.add(TextSpan(text: text.substring(end), style: tokenStyle));
    } else {
      children.add(TextSpan(text: text, style: tokenStyle));
    }
    offset = next;
  }
  return TextSpan(style: style, children: children);
}

/// Adds layout-only highlighting while leaving the editable text value intact.
class DuckyScriptEditingController extends TextEditingController {
  DuckyScriptEditingController({super.text});

  String? _cachedText;
  List<_Token> _tokens = const [];

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (_cachedText != text) {
      _cachedText = text;
      _tokens = _tokenize(text);
    }
    return _highlight(
      context,
      _tokens,
      style: style,
      composing:
          withComposing &&
              value.isComposingRangeValid &&
              !value.composing.isCollapsed
          ? value.composing
          : null,
    );
  }
}

class DuckyScriptText extends StatelessWidget {
  const DuckyScriptText(
    this.script, {
    super.key,
    this.selectable = false,
    this.maxLines,
    this.fontSize,
  });

  final String script;
  final bool selectable;
  final int? maxLines;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontFamily: 'monospace', fontSize: fontSize);
    final span = _highlight(context, _tokenize(script));
    if (selectable)
      return SelectableText.rich(span, style: style, maxLines: maxLines);
    return Text.rich(
      span,
      style: style,
      maxLines: maxLines,
      overflow: maxLines == null ? TextOverflow.visible : TextOverflow.ellipsis,
    );
  }
}
