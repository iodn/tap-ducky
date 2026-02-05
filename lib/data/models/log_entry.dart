class LogEntry {
  const LogEntry({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.message,
    required this.success,
    this.payloadId,
    this.payloadName,
    this.meta,
  });

  final String id;
  final DateTime timestamp;
  final String level; // info|warn|error|debug
  final String message;
  final bool success;
  final String? payloadId;
  final String? payloadName;
  final Map<String, String>? meta;

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'level': level,
        'message': message,
        'success': success,
        'payloadId': payloadId,
        'payloadName': payloadName,
        'meta': meta,
      };

  static LogEntry fromJson(Map<String, dynamic> json) {
    final metaRaw = json['meta'];
    return LogEntry(
      id: (json['id'] ?? '').toString(),
      timestamp: DateTime.tryParse((json['timestamp'] ?? '').toString()) ?? DateTime.now(),
      level: (json['level'] ?? 'info').toString(),
      message: (json['message'] ?? '').toString(),
      success: (json['success'] ?? false) == true,
      payloadId: json['payloadId']?.toString(),
      payloadName: json['payloadName']?.toString(),
      meta: metaRaw is Map ? metaRaw.map((k, v) => MapEntry(k.toString(), v.toString())) : null,
    );
  }
}
