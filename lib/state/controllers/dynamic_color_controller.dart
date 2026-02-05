import 'dart:io' show Platform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kDynamicColorsKey = 'use_dynamic_colors_v1';

final dynamicColorsControllerProvider =
    NotifierProvider<DynamicColorsController, bool>(DynamicColorsController.new);

class DynamicColorsController extends Notifier<bool> {
  @override
  bool build() {
    _load();
    return Platform.isAndroid; // default enable on Android
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getBool(_kDynamicColorsKey);
    if (v != null) state = v;
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDynamicColorsKey, enabled);
  }
}
