import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tap_ducky/data/models/scheduled_task.dart';
import 'package:tap_ducky/data/services/hardware_keys_service.dart';
import 'package:tap_ducky/state/providers.dart';
import 'package:tap_ducky/state/controllers/scheduler_controller.dart';
import 'package:tap_ducky/state/controllers/execution_controller.dart';
import 'package:tap_ducky/state/controllers/hid_status_controller.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tap_ducky/widgets/app_shell.dart';

class _Keys extends HardwareKeysService {
  @override
  Stream<HardwareKeyEvent> get events => const Stream.empty();
}

class _Scheduler extends SchedulerController {
  @override
  Future<List<ScheduledTask>> build() async => [];
}

class _Execution extends ExecutionController {
  @override
  ExecutionState build() => ExecutionState.idle();
}

class _Hid extends HidStatusController {
  @override
  HidStatus build() => const HidStatus(
    rootAvailable: true,
    hidSupported: true,
    deviceConnected: false,
    sessionArmed: false,
  );
}

void main() {
  for (final initialLocation in ['/settings', '/settings/detail']) {
    for (final destination in [
      'Dashboard',
      'Payloads',
      'Execute',
      'Schedule',
      'Settings',
    ]) {
      testWidgets(
        'bottom $destination leaves stacked subsections from $initialLocation',
        (tester) async {
          final navigatorKey = GlobalKey<NavigatorState>();
          final router = GoRouter(
            initialLocation: initialLocation,
            routes: [
              ShellRoute(
                navigatorKey: navigatorKey,
                builder: (context, state, child) =>
                    AppShell(navigatorKey: navigatorKey, child: child),
                routes: [
                  for (final path in [
                    'dashboard',
                    'payloads',
                    'execute',
                    'schedule',
                    'settings',
                  ])
                    GoRoute(
                      path: '/$path',
                      pageBuilder: (context, state) => NoTransitionPage(
                        key: state.pageKey,
                        child: Scaffold(body: Text('$path root')),
                      ),
                      routes: [
                        if (path == 'settings')
                          GoRoute(
                            path: 'detail',
                            builder: (_, _) =>
                                const Scaffold(body: Text('Routed detail')),
                          ),
                      ],
                    ),
                ],
              ),
            ],
          );
          addTearDown(router.dispose);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                hardwareKeysServiceProvider.overrideWithValue(_Keys()),
                schedulerControllerProvider.overrideWith(_Scheduler.new),
                executionControllerProvider.overrideWith(_Execution.new),
                hidStatusControllerProvider.overrideWith(_Hid.new),
              ],
              child: MaterialApp.router(routerConfig: router),
            ),
          );
          await tester.pumpAndSettle();
          for (final name in ['Settings subsection', 'Nested details']) {
            navigatorKey.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(body: Text(name)),
              ),
            );
            await tester.pumpAndSettle();
          }
          expect(find.text('Nested details'), findsOneWidget);
          await tester.tap(find.text(destination));
          await tester.pumpAndSettle();
          expect(
            find.text('${destination.toLowerCase()} root'),
            findsOneWidget,
          );
          expect(find.text('Nested details'), findsNothing);
          router.go('/settings');
          await tester.pumpAndSettle();
          expect(find.text('settings root'), findsOneWidget);
          expect(find.text('Settings subsection'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
