import 'dart:convert';

class PayloadParameter {
  const PayloadParameter({
    required this.key,
    required this.label,
    required this.type,
    required this.defaultValue,
    required this.description,
    required this.required,
  });

  final String key;
  final String label;
  final String type;
  final String defaultValue;
  final String description;
  final bool required;

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'type': type,
        'defaultValue': defaultValue,
        'description': description,
        'required': required,
      };

  static PayloadParameter fromJson(Map<String, dynamic> json) {
    return PayloadParameter(
      key: (json['key'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      type: (json['type'] ?? 'string').toString(),
      defaultValue: (json['defaultValue'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      required: (json['required'] ?? false) == true,
    );
  }
}

class Payload {
  const Payload({
    required this.id,
    required this.name,
    required this.description,
    required this.script,
    required this.tags,
    required this.parameters,
    required this.isBuiltin,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? const _DefaultDateTime();

  final String id;
  final String name;
  final String description;
  final String script;
  final List<String> tags;
  final List<PayloadParameter> parameters;
  final DateTime updatedAt;
  final bool isBuiltin;

  Payload copyWith({
    String? id,
    String? name,
    String? description,
    String? script,
    List<String>? tags,
    List<PayloadParameter>? parameters,
    DateTime? updatedAt,
    bool? isBuiltin,
  }) {
    return Payload(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      script: script ?? this.script,
      tags: tags ?? this.tags,
      parameters: parameters ?? this.parameters,
      updatedAt: updatedAt ?? this.updatedAt,
      isBuiltin: isBuiltin ?? this.isBuiltin,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'script': script,
        'tags': tags,
        'parameters': parameters.map((e) => e.toJson()).toList(),
        'updatedAt': updatedAt.toIso8601String(),
        'isBuiltin': isBuiltin,
      };

  static Payload fromJson(Map<String, dynamic> json) {
    final tagsRaw = json['tags'];
    final paramsRaw = json['parameters'];

    return Payload(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      script: (json['script'] ?? '').toString(),
      tags: tagsRaw is List ? tagsRaw.map((e) => e.toString()).toList() : const <String>[],
      parameters: paramsRaw is List
          ? paramsRaw.whereType<Map>().map((e) => PayloadParameter.fromJson(e.cast<String, dynamic>())).toList()
          : const <PayloadParameter>[],
      updatedAt: DateTime.tryParse((json['updatedAt'] ?? '').toString()) ?? DateTime.now(),
      isBuiltin: (json['isBuiltin'] ?? false) == true,
    );
  }

  String exportJson() => const JsonEncoder.withIndent('  ').convert(toJson());
}

class _DefaultDateTime implements DateTime {
  const _DefaultDateTime();

  @override
  DateTime add(Duration duration) => DateTime.now().add(duration);

  @override
  int compareTo(DateTime other) => DateTime.now().compareTo(other);

  @override
  int get day => DateTime.now().day;

  @override
  Duration difference(DateTime other) => DateTime.now().difference(other);

  @override
  int get hour => DateTime.now().hour;

  @override
  bool isAfter(DateTime other) => DateTime.now().isAfter(other);

  @override
  bool isAtSameMomentAs(DateTime other) => DateTime.now().isAtSameMomentAs(other);

  @override
  bool isBefore(DateTime other) => DateTime.now().isBefore(other);

  @override
  bool get isUtc => DateTime.now().isUtc;

  @override
  int get microsecond => DateTime.now().microsecond;

  @override
  int get microsecondsSinceEpoch => DateTime.now().microsecondsSinceEpoch;

  @override
  int get millisecond => DateTime.now().millisecond;

  @override
  int get millisecondsSinceEpoch => DateTime.now().millisecondsSinceEpoch;

  @override
  int get minute => DateTime.now().minute;

  @override
  int get month => DateTime.now().month;

  @override
  int get second => DateTime.now().second;

  @override
  DateTime subtract(Duration duration) => DateTime.now().subtract(duration);

  @override
  String get timeZoneName => DateTime.now().timeZoneName;

  @override
  Duration get timeZoneOffset => DateTime.now().timeZoneOffset;

  @override
  String toIso8601String() => DateTime.now().toIso8601String();

  @override
  DateTime toLocal() => DateTime.now().toLocal();

  @override
  DateTime toUtc() => DateTime.now().toUtc();

  @override
  int get weekday => DateTime.now().weekday;

  @override
  int get year => DateTime.now().year;

  @override
  String toString() => DateTime.now().toString();
}
