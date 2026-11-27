import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tap_ducky/features/settings/app_updates_screen.dart';
import 'package:tap_ducky/state/controllers/hid_status_controller.dart';

class _Hid extends HidStatusController {
  @override
  HidStatus build() => const HidStatus(
    rootAvailable: true,
    hidSupported: true,
    deviceConnected: false,
    sessionArmed: false,
  );
}

Future<void> _open(WidgetTester tester) => tester.pumpWidget(
  ProviderScope(
    overrides: [hidStatusControllerProvider.overrideWith(_Hid.new)],
    child: const MaterialApp(home: AppUpdatesScreen()),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(appUpdatesChannel, null));

  testWidgets('installs the offered version and explains Android permission', (
    tester,
  ) async {
    final installs = <Object?>[];
    var allowInstall = false;
    messenger.setMockMethodCallHandler(appUpdatesChannel, (call) async {
      switch (call.method) {
        case 'settings':
          return {
            'installed': '1.0.8+8',
            'enabled': true,
            'notificationsAllowed': false,
          };
        case 'check':
          return {'version': '1.0.9+9', 'installable': true};
        case 'install':
          installs.add(call.arguments);
          return allowInstall;
        case 'setEnabled':
          return {
            'installed': '1.0.8+8',
            'enabled': call.arguments,
            'notificationsAllowed': false,
          };
      }
      return null;
    });
    await _open(tester);
    await tester.pumpAndSettle();
    expect(find.text('Version 1.0.9+9 available'), findsOneWidget);
    expect(find.text('Android notifications are off'), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text('Android notifications are off'), findsNothing);

    final install = find.text('Download and install');
    await tester.tap(install);
    await tester.pumpAndSettle();
    expect(installs, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(installs, isEmpty);
    await tester.tap(install);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download APK'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Allow installs from TapDucky'), findsOneWidget);
    allowInstall = true;
    await tester.tap(install);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download APK'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Confirm the update'), findsOneWidget);
    expect(installs, ['1.0.9+9', '1.0.9+9']);
  });

  testWidgets(
    'network failure is retryable and incompatible APKs cannot install',
    (tester) async {
      var error = true;
      messenger.setMockMethodCallHandler(appUpdatesChannel, (call) async {
        if (call.method == 'settings') return {'installed': '1.0.8+8'};
        if (error) {
          throw PlatformException(
            code: 'network',
            message: 'GitHub is unreachable.',
          );
        }
        return {'version': '1.0.9', 'installable': false};
      });
      await _open(tester);
      await tester.pumpAndSettle();
      expect(find.text('GitHub is unreachable.'), findsOneWidget);
      error = false;
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(find.text('No verified APK for this device.'), findsOneWidget);
      expect(find.text('Download and install'), findsNothing);
    },
  );
}
