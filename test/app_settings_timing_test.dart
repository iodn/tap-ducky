import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tap_ducky/data/services/platform_gadget_service.dart';
import 'package:tap_ducky/state/controllers/app_settings_controller.dart';
import 'package:tap_ducky/state/providers.dart';

class _TimingBackend extends PlatformGadgetService {
  final factors = <double>[];
  Completer<void>? pending;

  @override
  Future<void> setTypingSpeedFactor(double factor) async {
    factors.add(factor);
    await pending?.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'keyboard timing updates Android without overwriting a concurrent script pause change',
    () async {
      SharedPreferences.setMockInitialValues({});
      final backend = _TimingBackend();
      final container = ProviderContainer.test(
        overrides: [platformGadgetServiceProvider.overrideWithValue(backend)],
      );
      await container.read(appSettingsControllerProvider.future);
      final controller = container.read(appSettingsControllerProvider.notifier);
      final repository = await container.read(
        settingsRepositoryProvider.future,
      );

      backend.pending = Completer<void>();
      final keyboardChange = controller.setTypingSpeedFactor(2);
      await controller.setDelayMultiplier(1.5);
      expect(backend.factors, [1, 2]);
      backend.pending!.complete();
      await keyboardChange;
      expect(repository.load().delayMultiplier, 1.5);
      expect(repository.load().typingSpeedFactor, 2);

      await controller.setHiddenExecution(false);
      await controller.resetExecutionDefaults();
      final reset = repository.load();
      expect(reset.delayMultiplier, 1);
      expect(reset.typingSpeedFactor, 1);
      expect(reset.hiddenExecution, isFalse);
      expect(backend.factors.last, 1);
    },
  );
}
