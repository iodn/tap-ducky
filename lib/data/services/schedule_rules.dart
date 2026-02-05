bool isWithinWindow(DateTime now, String? start, String? end) {
  if (start == null || end == null) return true;
  final s = _parseHHmm(start);
  final e = _parseHHmm(end);
  if (s == null || e == null) return true;

  final minutes = now.hour * 60 + now.minute;
  final startMin = s.$1 * 60 + s.$2;
  final endMin = e.$1 * 60 + e.$2;

  if (startMin == endMin) return true;
  if (startMin < endMin) {
    return minutes >= startMin && minutes <= endMin;
  }
  // wraps midnight
  return minutes >= startMin || minutes <= endMin;
}

(int, int)? _parseHHmm(String s) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s.trim());
  if (m == null) return null;
  final hh = int.tryParse(m.group(1)!) ?? -1;
  final mm = int.tryParse(m.group(2)!) ?? -1;
  if (hh < 0 || hh > 23 || mm < 0 || mm > 59) return null;
  return (hh, mm);
}
