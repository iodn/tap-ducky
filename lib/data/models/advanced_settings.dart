class KeyboardLayoutOption {
  final String id;
  final String label;
  final int backendId;

  const KeyboardLayoutOption({
    required this.id,
    required this.label,
    required this.backendId,
  });
}

class AdvancedSettings {
  const AdvancedSettings({
    required this.keyboardLayout,
    required this.defaultVid,
    required this.defaultPid,
    required this.commandPresets,
    required this.hotkeys,
  });

  final String keyboardLayout;
  final String defaultVid;
  final String defaultPid;
  final List<String> commandPresets;
  final Map<String, String> hotkeys;

  AdvancedSettings copyWith({
    String? keyboardLayout,
    String? defaultVid,
    String? defaultPid,
    List<String>? commandPresets,
    Map<String, String>? hotkeys,
  }) {
    return AdvancedSettings(
      keyboardLayout: keyboardLayout ?? this.keyboardLayout,
      defaultVid: defaultVid ?? this.defaultVid,
      defaultPid: defaultPid ?? this.defaultPid,
      commandPresets: commandPresets ?? this.commandPresets,
      hotkeys: hotkeys ?? this.hotkeys,
    );
  }

  Map<String, dynamic> toJson() => {
        'keyboardLayout': normalizeKeyboardLayoutId(keyboardLayout),
        'defaultVid': defaultVid,
        'defaultPid': defaultPid,
        'commandPresets': commandPresets,
        'hotkeys': hotkeys,
      };

  static const List<KeyboardLayoutOption> supportedKeyboardLayouts = <KeyboardLayoutOption>[
    KeyboardLayoutOption(id: 'us', label: 'US (QWERTY)', backendId: 0),
    KeyboardLayoutOption(id: 'tr', label: 'Turkish', backendId: 1),
    KeyboardLayoutOption(id: 'sv', label: 'Swedish', backendId: 2),
    KeyboardLayoutOption(id: 'si', label: 'Slovenian', backendId: 3),
    KeyboardLayoutOption(id: 'ru', label: 'Russian (Cyrillic)', backendId: 4),
    KeyboardLayoutOption(id: 'pt', label: 'Portuguese', backendId: 5),
    KeyboardLayoutOption(id: 'no', label: 'Norwegian', backendId: 6),
    KeyboardLayoutOption(id: 'it', label: 'Italian', backendId: 7),
    KeyboardLayoutOption(id: 'hr', label: 'Croatian', backendId: 8),
    KeyboardLayoutOption(id: 'fr', label: 'French (AZERTY)', backendId: 9),
    KeyboardLayoutOption(id: 'fi', label: 'Finnish', backendId: 10),
    KeyboardLayoutOption(id: 'es', label: 'Spanish', backendId: 11),
    KeyboardLayoutOption(id: 'dk', label: 'Danish', backendId: 12),
    KeyboardLayoutOption(id: 'de', label: 'German (QWERTZ)', backendId: 13),
    KeyboardLayoutOption(id: 'ca', label: 'Canadian', backendId: 14),
    KeyboardLayoutOption(id: 'br', label: 'Brazilian', backendId: 15),
    KeyboardLayoutOption(id: 'be', label: 'Belgian', backendId: 16),
    KeyboardLayoutOption(id: 'hu', label: 'Hungarian', backendId: 17),
    KeyboardLayoutOption(id: 'jp', label: 'Japanese', backendId: 18),
  ];

  static const Map<String, String> keyboardLayoutLabels = <String, String>{
    'us': 'US (QWERTY)',
    'tr': 'Turkish',
    'sv': 'Swedish',
    'si': 'Slovenian',
    'ru': 'Russian (Cyrillic)',
    'pt': 'Portuguese',
    'no': 'Norwegian',
    'it': 'Italian',
    'hr': 'Croatian',
    'fr': 'French (AZERTY)',
    'fi': 'Finnish',
    'es': 'Spanish',
    'dk': 'Danish',
    'de': 'German (QWERTZ)',
    'ca': 'Canadian',
    'br': 'Brazilian',
    'be': 'Belgian',
    'hu': 'Hungarian',
    'jp': 'Japanese',
  };

  static AdvancedSettings defaults() => const AdvancedSettings(
        keyboardLayout: 'us',
        defaultVid: '0x1D6B',
        defaultPid: '0x0104',
        commandPresets: <String>[
          'DELAY 500\nSTRING TapDucky ready\nENTER',
          'DELAY 250\nGUI r\nDELAY 200\nSTRING notepad\nENTER',
        ],
        hotkeys: <String, String>{
          'arm_toggle': '—',
          'stop_execution': '—',
          'execute_recent': '—',
          'execute_selected': '—',
        },
      );

  static AdvancedSettings fromJson(Map<String, dynamic> json) {
    final presetsRaw = json['commandPresets'];
    final hotkeysRaw = json['hotkeys'];

    final parsedHotkeys = hotkeysRaw is Map
        ? hotkeysRaw.map((k, v) => MapEntry(k.toString(), v.toString()))
        : <String, String>{};

    if (parsedHotkeys.containsKey('open_execute') && !parsedHotkeys.containsKey('execute_recent')) {
      parsedHotkeys['execute_recent'] = parsedHotkeys['open_execute']!.toString();
    }
    parsedHotkeys.remove('open_execute');

    final mergedHotkeys = <String, String>{
      ...AdvancedSettings.defaults().hotkeys,
      ...parsedHotkeys,
    };

    return AdvancedSettings(
      keyboardLayout: normalizeKeyboardLayoutId((json['keyboardLayout'] ?? 'us').toString()),
      defaultVid: (json['defaultVid'] ?? '0x1D6B').toString(),
      defaultPid: (json['defaultPid'] ?? '0x0104').toString(),
      commandPresets: presetsRaw is List
          ? presetsRaw.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList()
          : AdvancedSettings.defaults().commandPresets,
      hotkeys: mergedHotkeys,
    );
  }

  String get keyboardLayoutId => normalizeKeyboardLayoutId(keyboardLayout);
  int get keyboardLayoutBackendId => keyboardLayoutOption?.backendId ?? 0;
  String get keyboardLayoutDisplayName => keyboardLayoutLabels[keyboardLayoutId] ?? keyboardLayoutId.toUpperCase();

  KeyboardLayoutOption? get keyboardLayoutOption {
    final id = keyboardLayoutId;
    for (final opt in supportedKeyboardLayouts) {
      if (opt.id == id) return opt;
    }
    return null;
  }

  static bool isSupportedKeyboardLayoutId(String id) {
    final normalized = normalizeKeyboardLayoutId(id);
    for (final opt in supportedKeyboardLayouts) {
      if (opt.id == normalized) return true;
    }
    return false;
  }

  static String normalizeKeyboardLayoutId(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return 'us';
    const synonyms = <String, String>{
      'en': 'us',
      'en-us': 'us',
      'en_us': 'us',
      'qwerty': 'us',
      'us': 'us',
      'fr-fr': 'fr',
      'fr_fr': 'fr',
      'azerty': 'fr',
      'fr': 'fr',
      'jp-jp': 'jp',
      'jp_jp': 'jp',
      'ja': 'jp',
      'ja-jp': 'jp',
      'ja_jp': 'jp',
      'jpn': 'jp',
      'jp': 'jp',
      'no-no': 'no',
      'no_no': 'no',
      'nb': 'no',
      'nb-no': 'no',
      'nb_no': 'no',
      'nn': 'no',
      'nn-no': 'no',
      'nn_no': 'no',
      'dk-dk': 'dk',
      'dk_dk': 'dk',
      'da': 'dk',
      'da-dk': 'dk',
      'da_dk': 'dk',
      'sv-se': 'sv',
      'sv_se': 'sv',
      'se': 'sv',
      'de-de': 'de',
      'de_de': 'de',
      'qwertz': 'de',
      'es-es': 'es',
      'es_es': 'es',
      'pt-pt': 'pt',
      'pt_pt': 'pt',
      'pt-br': 'br',
      'pt_br': 'br',
      'br': 'br',
      'be-be': 'be',
      'be_be': 'be',
      'hu-hu': 'hu',
      'hu_hu': 'hu',
      'hr-hr': 'hr',
      'hr_hr': 'hr',
      'ru-ru': 'ru',
      'ru_ru': 'ru',
      'ca-ca': 'ca',
      'ca_ca': 'ca',
      'si-si': 'si',
      'si_si': 'si',
      'sl': 'si',
      'sl-si': 'si',
      'sl_si': 'si',
      'tr-tr': 'tr',
      'tr_tr': 'tr',
      'fi-fi': 'fi',
      'fi_fi': 'fi',
    };
    final mapped = synonyms[s] ?? s;
    for (final opt in supportedKeyboardLayouts) {
      if (opt.id == mapped) return mapped;
    }
    return 'us';
  }
}
