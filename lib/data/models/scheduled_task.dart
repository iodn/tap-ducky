class ScheduledTask {
  const ScheduledTask({
    required this.id,
    required this.payloadId,
    required this.name,
    required this.enabled,
    required this.trigger,
    required this.params,
    required this.createdAt,
    this.runAt,
    this.windowStart,
    this.windowEnd,
    this.lastRunAt,
  });

  final String id;
  final String payloadId;
  final String name;
  final bool enabled;
  final String trigger;
  final DateTime? runAt;
  final String? windowStart;
  final String? windowEnd;
  final Map<String, String> params;
  final DateTime createdAt;
  final DateTime? lastRunAt;

  static const Object _unset = Object();

  ScheduledTask copyWith({
    String? id,
    String? payloadId,
    String? name,
    bool? enabled,
    String? trigger,
    Object? runAt = _unset,
    Object? windowStart = _unset,
    Object? windowEnd = _unset,
    Map<String, String>? params,
    DateTime? createdAt,
    Object? lastRunAt = _unset,
  }) {
    return ScheduledTask(
      id: id ?? this.id,
      payloadId: payloadId ?? this.payloadId,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      trigger: trigger ?? this.trigger,
      runAt: identical(runAt, _unset) ? this.runAt : runAt as DateTime?,
      windowStart: identical(windowStart, _unset) ? this.windowStart : windowStart as String?,
      windowEnd: identical(windowEnd, _unset) ? this.windowEnd : windowEnd as String?,
      params: params ?? this.params,
      createdAt: createdAt ?? this.createdAt,
      lastRunAt: identical(lastRunAt, _unset) ? this.lastRunAt : lastRunAt as DateTime?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'payloadId': payloadId,
        'name': name,
        'enabled': enabled,
        'trigger': trigger,
        'runAt': runAt?.toIso8601String(),
        'windowStart': windowStart,
        'windowEnd': windowEnd,
        'params': params,
        'createdAt': createdAt.toIso8601String(),
        'lastRunAt': lastRunAt?.toIso8601String(),
      };

  static ScheduledTask fromJson(Map<String, dynamic> json) {
    final paramsRaw = json['params'];
    return ScheduledTask(
      id: (json['id'] ?? '').toString(),
      payloadId: (json['payloadId'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      enabled: (json['enabled'] ?? true) == true,
      trigger: (json['trigger'] ?? 'one_time').toString(),
      runAt: json['runAt'] == null ? null : DateTime.tryParse(json['runAt'].toString()),
      windowStart: json['windowStart']?.toString(),
      windowEnd: json['windowEnd']?.toString(),
      params: paramsRaw is Map
          ? paramsRaw.map((k, v) => MapEntry(k.toString(), v.toString()))
          : const <String, String>{},
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()) ?? DateTime.now(),
      lastRunAt: json['lastRunAt'] == null ? null : DateTime.tryParse(json['lastRunAt'].toString()),
    );
  }
}
