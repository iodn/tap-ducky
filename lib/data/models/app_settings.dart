import 'package:flutter/material.dart';

class AppSettings {
  const AppSettings({
    required this.themeMode,
    required this.enableLogging,
    required this.simulateRootAvailable,
    required this.simulateHidSupported,
    required this.delayMultiplier,
    required this.randomizeTiming,
    required this.keepScreenOn,
    required this.showPowerUserHints,
    required this.lastProfileType,
    required this.hidGraceWindowMs,
    required this.unicodeFallbackMode,
    required this.riskyFastMode,
    required this.typingSpeedFactor,
    required this.typingSpeedSemanticsVersion,
    required this.dialShortcuts,
  });

  final ThemeMode themeMode;
  final bool enableLogging;
  final bool simulateRootAvailable;
  final bool simulateHidSupported;
  final double delayMultiplier;
  final bool randomizeTiming;
  final bool keepScreenOn;
  final bool showPowerUserHints;
  final String lastProfileType;
  final int hidGraceWindowMs;
  final String unicodeFallbackMode;
  final bool riskyFastMode;
  final double typingSpeedFactor;
  final int typingSpeedSemanticsVersion;
  final List<DialShortcutBinding> dialShortcuts;

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? enableLogging,
    bool? simulateRootAvailable,
    bool? simulateHidSupported,
    double? delayMultiplier,
    bool? randomizeTiming,
    bool? keepScreenOn,
    bool? showPowerUserHints,
    String? lastProfileType,
    int? hidGraceWindowMs,
    String? unicodeFallbackMode,
    bool? riskyFastMode,
    double? typingSpeedFactor,
    int? typingSpeedSemanticsVersion,
    List<DialShortcutBinding>? dialShortcuts,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      enableLogging: enableLogging ?? this.enableLogging,
      simulateRootAvailable: simulateRootAvailable ?? this.simulateRootAvailable,
      simulateHidSupported: simulateHidSupported ?? this.simulateHidSupported,
      delayMultiplier: delayMultiplier ?? this.delayMultiplier,
      randomizeTiming: randomizeTiming ?? this.randomizeTiming,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      showPowerUserHints: showPowerUserHints ?? this.showPowerUserHints,
      lastProfileType: lastProfileType ?? this.lastProfileType,
      hidGraceWindowMs: hidGraceWindowMs ?? this.hidGraceWindowMs,
      unicodeFallbackMode: unicodeFallbackMode ?? this.unicodeFallbackMode,
      riskyFastMode: riskyFastMode ?? this.riskyFastMode,
      typingSpeedFactor: typingSpeedFactor ?? this.typingSpeedFactor,
      typingSpeedSemanticsVersion: typingSpeedSemanticsVersion ?? this.typingSpeedSemanticsVersion,
      dialShortcuts: dialShortcuts ?? this.dialShortcuts,
    );
  }

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.name,
        'enableLogging': enableLogging,
        'simulateRootAvailable': simulateRootAvailable,
        'simulateHidSupported': simulateHidSupported,
        'delayMultiplier': delayMultiplier,
        'randomizeTiming': randomizeTiming,
        'keepScreenOn': keepScreenOn,
        'showPowerUserHints': showPowerUserHints,
        'lastProfileType': lastProfileType,
        'hidGraceWindowMs': hidGraceWindowMs,
        'unicodeFallbackMode': unicodeFallbackMode,
        'riskyFastMode': riskyFastMode,
        'typingSpeedFactor': typingSpeedFactor,
        'typingSpeedSemanticsVersion': typingSpeedSemanticsVersion,
        'dialShortcuts': dialShortcuts.map((e) => e.toJson()).toList(),
      };

  static AppSettings defaults() => const AppSettings(
        themeMode: ThemeMode.system,
        enableLogging: true,
        simulateRootAvailable: true,
        simulateHidSupported: true,
        delayMultiplier: 1.0,
        randomizeTiming: true,
        keepScreenOn: false,
        showPowerUserHints: true,
        lastProfileType: 'composite',
        hidGraceWindowMs: 1500,
        unicodeFallbackMode: 'warn',
        riskyFastMode: false,
        typingSpeedFactor: 1.0,
        typingSpeedSemanticsVersion: 2,
        dialShortcuts: const <DialShortcutBinding>[
          DialShortcutBinding(
            code: '38250',
            enabled: false,
            mode: 'last',
            payloadId: null,
            script: null,
            name: null,
          ),
          DialShortcutBinding(
            code: '38251',
            enabled: false,
            mode: 'last',
            payloadId: null,
            script: null,
            name: null,
          ),
          DialShortcutBinding(
            code: '38252',
            enabled: false,
            mode: 'last',
            payloadId: null,
            script: null,
            name: null,
          ),
          DialShortcutBinding(
            code: '38253',
            enabled: false,
            mode: 'last',
            payloadId: null,
            script: null,
            name: null,
          ),
        ],
      );

  static AppSettings fromJson(Map<String, dynamic> json) {
    final theme = (json['themeMode'] ?? 'system').toString();
    var typingFactor = (json['typingSpeedFactor'] is num)
        ? (json['typingSpeedFactor'] as num).toDouble()
        : 1.0;
    var typingSemantics = (json['typingSpeedSemanticsVersion'] is num)
        ? (json['typingSpeedSemanticsVersion'] as num).toInt()
        : 0;
    if (typingSemantics < 2) {
      if (!typingFactor.isFinite || typingFactor <= 0) {
        typingFactor = 1.0;
      } else {
        typingFactor = 1.0 / typingFactor;
      }
      typingSemantics = 2;
    }
    final shortcutsRaw = json['dialShortcuts'];
    final parsedShortcuts = shortcutsRaw is List
        ? shortcutsRaw.whereType<Map>().map((e) => DialShortcutBinding.fromJson(e.cast<String, dynamic>())).toList()
        : <DialShortcutBinding>[];

    final legacyEnabled = (json['dialShortcutEnabled'] ?? false) == true;
    final legacyMode = (json['dialShortcutMode'] ?? 'last').toString();
    final legacyPayloadIdRaw = (json['dialShortcutPayloadId'] ?? '').toString();
    final legacyPayloadId = legacyPayloadIdRaw.isEmpty ? null : legacyPayloadIdRaw;

    final normalized = parsedShortcuts.map((b) {
      if (b.code == '78259') return b.copyWith(code: '38250');
      if (b.code == '78260') return b.copyWith(code: '38251');
      if (b.code == '78261') return b.copyWith(code: '38252');
      if (b.code == '78262') return b.copyWith(code: '38253');
      return b;
    }).toList();

    final mergedShortcuts = normalized.isNotEmpty
        ? normalized
        : <DialShortcutBinding>[
            DialShortcutBinding(
              code: '38250',
              enabled: legacyEnabled,
              mode: legacyMode,
              payloadId: legacyPayloadId,
              script: null,
              name: null,
            ),
          ];

    return AppSettings(
      themeMode: ThemeMode.values.firstWhere((e) => e.name == theme, orElse: () => ThemeMode.system),
      enableLogging: (json['enableLogging'] ?? true) == true,
      simulateRootAvailable: (json['simulateRootAvailable'] ?? true) == true,
      simulateHidSupported: (json['simulateHidSupported'] ?? true) == true,
      delayMultiplier: (json['delayMultiplier'] is num) ? (json['delayMultiplier'] as num).toDouble() : 1.0,
      randomizeTiming: (json['randomizeTiming'] ?? true) == true,
      keepScreenOn: (json['keepScreenOn'] ?? false) == true,
      showPowerUserHints: (json['showPowerUserHints'] ?? true) == true,
      lastProfileType: (json['lastProfileType'] ?? 'composite').toString(),
      hidGraceWindowMs: (json['hidGraceWindowMs'] is num) ? (json['hidGraceWindowMs'] as num).toInt() : 1500,
      unicodeFallbackMode: (json['unicodeFallbackMode'] ?? 'warn').toString(),
      riskyFastMode: (json['riskyFastMode'] ?? false) == true,
      typingSpeedFactor: typingFactor,
      typingSpeedSemanticsVersion: typingSemantics,
      dialShortcuts: mergedShortcuts,
    );
  }
}

class DialShortcutBinding {
  const DialShortcutBinding({
    required this.code,
    required this.enabled,
    required this.mode,
    required this.payloadId,
    required this.script,
    required this.name,
  });

  final String code;
  final bool enabled;
  final String mode;
  final String? payloadId;
  final String? script;
  final String? name;

  DialShortcutBinding copyWith({
    String? code,
    bool? enabled,
    String? mode,
    String? payloadId,
    String? script,
    String? name,
  }) {
    return DialShortcutBinding(
      code: code ?? this.code,
      enabled: enabled ?? this.enabled,
      mode: mode ?? this.mode,
      payloadId: payloadId ?? this.payloadId,
      script: script ?? this.script,
      name: name ?? this.name,
    );
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'enabled': enabled,
        'mode': mode,
        'payloadId': payloadId,
        'script': script,
        'name': name,
      };

  static DialShortcutBinding fromJson(Map<String, dynamic> json) {
    final code = (json['code'] ?? '').toString();
    final payloadIdRaw = (json['payloadId'] ?? '').toString();
    final payloadId = payloadIdRaw.isEmpty ? null : payloadIdRaw;
    final scriptRaw = (json['script'] ?? '').toString();
    final script = scriptRaw.isEmpty ? null : scriptRaw;
    final nameRaw = (json['name'] ?? '').toString();
    final name = nameRaw.isEmpty ? null : nameRaw;
    return DialShortcutBinding(
      code: code,
      enabled: (json['enabled'] ?? false) == true,
      mode: (json['mode'] ?? 'last').toString(),
      payloadId: payloadId,
      script: script,
      name: name,
    );
  }
}
