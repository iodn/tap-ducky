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
    return PayloadDraft.fromResponse(response ?? '');
  }
}

class PayloadDraft {
  const PayloadDraft._(this.title, this.description, this.tags, this.script);

  final String title;
  final String description;
  final List<String> tags;
  final String script;

  factory PayloadDraft.fromResponse(String response) {
    var json = response.trim();
    final fence = RegExp(
      r'^```(?:json)?\s*([\s\S]*?)\s*```$',
      caseSensitive: false,
    );
    json = fence.firstMatch(json)?.group(1) ?? json;
    if (json.length > 4096) throw const FormatException('Draft is too long.');
    final data = jsonDecode(json);
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Expected a draft object.');
    }

    String field(String key, int limit) {
      final value = data[key];
      if (value is! String ||
          value.trim().isEmpty ||
          value.length > limit ||
          !RegExp(r'^[ -~]+$').hasMatch(value)) {
        throw FormatException('Invalid draft field: $key.');
      }
      return value.trim();
    }

    final text = field('text', 160);
    final repeat = data['repeat'];
    final tags = data['tags'];
    if (!RegExp(r"^[A-Za-z0-9 .,!?'-]+$").hasMatch(text) ||
        repeat is! int ||
        repeat < 1 ||
        repeat > 100 ||
        tags is! List ||
        tags.length > 5 ||
        tags.any(
          (tag) =>
              tag is! String || !RegExp(r'^[a-zA-Z0-9_-]{1,24}$').hasMatch(tag),
        )) {
      throw const FormatException(
        'Draft is outside the supported typing format.',
      );
    }

    final script = [
      'STRINGLN $text',
      if (repeat > 1) 'REPEAT ${repeat - 1}',
    ].join('\n');
    if (DuckyScriptValidator().validate(script).hasErrors) {
      throw const FormatException('The generated typing script was invalid.');
    }
    return PayloadDraft._(
      field('title', 60),
      field('description', 240),
      List.unmodifiable(tags.cast<String>()),
      script,
    );
  }
}
