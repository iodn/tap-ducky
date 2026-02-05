import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/repositories/log_repository.dart';
import '../data/repositories/advanced_settings_repository.dart';
import '../data/repositories/payload_repository.dart';
import '../data/repositories/scheduler_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/services/device_info_service.dart';
import '../data/services/execution_service.dart';
import '../data/services/hardware_keys_service.dart';
import '../data/services/platform_gadget_service.dart';
import '../data/storage/prefs_storage.dart';
import '../data/services/github_store/github_store_service.dart';

final sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) async {
  return SharedPreferences.getInstance();
});

final prefsStorageProvider = FutureProvider<PrefsStorage>((ref) async {
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  return PrefsStorage(prefs);
});

final settingsRepositoryProvider = FutureProvider<SettingsRepository>((ref) async {
  return SettingsRepository(await ref.watch(prefsStorageProvider.future));
});

final advancedSettingsRepositoryProvider = FutureProvider<AdvancedSettingsRepository>((ref) async {
  return AdvancedSettingsRepository(await ref.watch(prefsStorageProvider.future));
});

final payloadRepositoryProvider = FutureProvider<PayloadRepository>((ref) async {
  return PayloadRepository(await ref.watch(prefsStorageProvider.future));
});

final logRepositoryProvider = FutureProvider<LogRepository>((ref) async {
  return LogRepository(await ref.watch(prefsStorageProvider.future));
});

final schedulerRepositoryProvider = FutureProvider<SchedulerRepository>((ref) async {
  return SchedulerRepository(await ref.watch(prefsStorageProvider.future));
});

final deviceInfoServiceProvider = Provider<DeviceInfoService>((ref) {
  return DeviceInfoService();
});

final executionServiceProvider = Provider<ExecutionService>((ref) {
  return ExecutionService();
});

final platformGadgetServiceProvider = Provider<PlatformGadgetService>((ref) {
  return PlatformGadgetService();
});

// GitHub Store service
final githubStoreServiceProvider = Provider<GitHubStoreService>((ref) {
  return GitHubStoreService();
});

final hardwareKeysServiceProvider = Provider<HardwareKeysService>((ref) {
  return HardwareKeysService();
});
