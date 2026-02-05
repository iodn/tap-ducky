import 'dart:math';

class DuckyStep {
  const DuckyStep({
    required this.raw,
    required this.kind,
    required this.display,
    required this.delayMs,
    required this.isDelayOnly,
  });

  final String raw;
  final String kind;
  final String display;
  final int delayMs;
  final bool isDelayOnly;
}

class DuckyScript {
  static String resolvePlaceholders(String input, Map<String, String> values) {
    return input.replaceAllMapped(RegExp(r'\$\{([a-zA-Z0-9_\-]+)\}'), (m) {
      final k = m.group(1)!;
      return values[k] ?? m.group(0)!;
    });
  }

  static List<DuckyStep> parse(String script, {required double delayMultiplier, required bool randomizeTiming, int baseKeyDelayMs = 35}) {
    final rng = Random();
    final lines = script.replaceAll('\r', '').split('\n');
    final steps = <DuckyStep>[];

    int jitter(int ms) {
      if (!randomizeTiming) return ms;
      final factor = 0.85 + (rng.nextDouble() * 0.3);
      return max(0, (ms * factor).round());
    }

    int scale(int ms) => max(0, (ms * delayMultiplier).round());

    for (final original in lines) {
      final line = original.trimRight();
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final upper = trimmed.toUpperCase();

      if (upper.startsWith('#') || upper.startsWith('REM ')) {
        continue;
      }

      if (upper.startsWith('DELAY ')) {
        final rest = trimmed.substring(6).trim();
        final ms = int.tryParse(rest) ?? 0;
        final effective = jitter(scale(ms));
        steps.add(DuckyStep(raw: trimmed, kind: 'delay', display: 'Delay ${effective}ms', delayMs: effective, isDelayOnly: true));
        continue;
      }

      if (upper.startsWith('STRING ')) {
        final text = trimmed.substring(7);
        steps.add(DuckyStep(
          raw: trimmed,
          kind: 'string',
          display: 'Type: ${_ellipsis(text)}',
          delayMs: jitter(scale(baseKeyDelayMs + min(400, text.length * 10))),
          isDelayOnly: false,
        ));
        continue;
      }

      // One-word keys
      const keys = {'ENTER', 'TAB', 'ESC', 'SPACE', 'UP', 'DOWN', 'LEFT', 'RIGHT', 'BACKSPACE'};
      if (keys.contains(upper)) {
        steps.add(DuckyStep(raw: trimmed, kind: 'key', display: 'Key: $upper', delayMs: jitter(scale(baseKeyDelayMs)), isDelayOnly: false));
        continue;
      }

      // Modifier style commands: GUI r, CTRL ALT DEL, etc.
      final parts = trimmed.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
      if (parts.isNotEmpty) {
        final cmd = parts.first.toUpperCase();
        const mods = {'GUI', 'WINDOWS', 'WIN', 'ALT', 'CTRL', 'CONTROL', 'SHIFT'};
        if (mods.contains(cmd)) {
          steps.add(DuckyStep(
            raw: trimmed,
            kind: 'combo',
            display: 'Combo: ${parts.map((e) => e.toUpperCase()).join(' + ')}',
            delayMs: jitter(scale(baseKeyDelayMs + 30)),
            isDelayOnly: false,
          ));
          continue;
        }
      }

      // Fallback: treat as raw command.
      steps.add(DuckyStep(raw: trimmed, kind: 'raw', display: 'Command: ${_ellipsis(trimmed)}', delayMs: jitter(scale(baseKeyDelayMs + 40)), isDelayOnly: false));
    }

    return steps;
  }

  static String _ellipsis(String s, {int max = 34}) {
    final t = s.trim();
    if (t.length <= max) return t;
    return '${t.substring(0, max - 1)}…';
  }
}
