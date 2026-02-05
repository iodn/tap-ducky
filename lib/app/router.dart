import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/device/device_screen.dart';
import '../features/execute/execute_screen.dart';
import '../features/execute/execution_history_screen.dart';  // Add this
import '../features/logs/log_detail_screen.dart';
import '../features/logs/logs_screen.dart';
import '../features/payloads/payload_editor_screen.dart';
import '../features/payloads/payloads_screen.dart';
import '../features/payloads/store/payloads_store_screen.dart';
import '../features/payloads/store/manage_sources_screen.dart';
import '../features/schedule/schedule_editor_screen.dart';
import '../features/schedule/schedule_screen.dart';
import '../features/settings/advanced_settings_screen.dart';
import '../features/settings/settings_screen.dart';
import '../widgets/app_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: const DashboardRoute().location,
    routes: [
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: const DashboardRoute().location,
            name: DashboardRoute.name,
            pageBuilder: (context, state) => const NoTransitionPage(child: DashboardScreen()),
          ),
          GoRoute(
            path: const PayloadsRoute().location,
            name: PayloadsRoute.name,
            pageBuilder: (context, state) => const NoTransitionPage(child: PayloadsScreen()),
            routes: [
             GoRoute(
               path: 'store',
               name: PayloadsStoreRoute.name,
               pageBuilder: (context, state) => const MaterialPage(child: PayloadsStoreScreen()),
               routes: [
                 GoRoute(
                   path: 'manage',
                   name: PayloadsManageSourcesRoute.name,
                   pageBuilder: (context, state) => const MaterialPage(child: ManageSourcesScreen()),
                 ),
               ],
             ),
              GoRoute(
                path: 'new',
                name: PayloadEditorRoute.newName,
                pageBuilder: (context, state) => const MaterialPage(
                  fullscreenDialog: true,
                  child: PayloadEditorScreen(),
                ),
              ),
              GoRoute(
                path: ':id/edit',
                name: PayloadEditorRoute.editName,
                pageBuilder: (context, state) {
                  final id = state.pathParameters['id']!;
                  return MaterialPage(
                    fullscreenDialog: true,
                    child: PayloadEditorScreen(payloadId: id),
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: const ExecuteRoute().location,
            name: ExecuteRoute.name,
            pageBuilder: (context, state) => const NoTransitionPage(child: ExecuteScreen()),
            routes: [
              GoRoute(
                path: 'history',
                name: ExecutionHistoryRoute.name,
                pageBuilder: (context, state) => const MaterialPage(child: ExecutionHistoryScreen()),
              ),
            ],
          ),
          GoRoute(
            path: const ScheduleRoute().location,
            name: ScheduleRoute.name,
            pageBuilder: (context, state) => const NoTransitionPage(child: ScheduleScreen()),
            routes: [
              GoRoute(
                path: 'new',
                name: ScheduleEditorRoute.newName,
                pageBuilder: (context, state) => const MaterialPage(
                  fullscreenDialog: true,
                  child: ScheduleEditorScreen.newTask(),
                ),
              ),
              GoRoute(
                path: ':id/edit',
                name: ScheduleEditorRoute.editName,
                pageBuilder: (context, state) {
                  final id = state.pathParameters['id']!;
                  return MaterialPage(
                    fullscreenDialog: true,
                    child: ScheduleEditorScreen.edit(taskId: id),
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: const SettingsRoute().location,
            name: SettingsRoute.name,
            pageBuilder: (context, state) => const NoTransitionPage(child: SettingsScreen()),
            routes: [
              GoRoute(
                path: 'advanced',
                name: AdvancedSettingsRoute.name,
                pageBuilder: (context, state) => const MaterialPage(child: AdvancedSettingsScreen()),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: const LogsRoute().location,
        name: LogsRoute.name,
        pageBuilder: (context, state) => const MaterialPage(child: LogsScreen()),
        routes: [
          GoRoute(
            path: ':id',
            name: LogDetailRoute.name,
            pageBuilder: (context, state) {
              final id = state.pathParameters['id']!;
              return MaterialPage(child: LogDetailScreen(logId: id));
            },
          ),
        ],
      ),
      GoRoute(
        path: const DeviceRoute().location,
        name: DeviceRoute.name,
        pageBuilder: (context, state) => const MaterialPage(child: DeviceScreen()),
      ),
    ],
  );
});

sealed class AppRoute {
  const AppRoute(this.location);
  final String location;
}

class DashboardRoute extends AppRoute {
  const DashboardRoute() : super('/dashboard');
  static const name = 'dashboard';
}

class PayloadsRoute extends AppRoute {
  const PayloadsRoute() : super('/payloads');
  static const name = 'payloads';
}

class PayloadsStoreRoute extends AppRoute {
  const PayloadsStoreRoute() : super('/payloads/store');
  static const name = 'payloads_store';
}

class PayloadsManageSourcesRoute extends AppRoute {
  const PayloadsManageSourcesRoute() : super('/payloads/store/manage');
  static const name = 'payloads_manage_sources';
}

class PayloadEditorRoute {
  static const newName = 'payload_new';
  static const editName = 'payload_edit';
}

class ExecuteRoute extends AppRoute {
  const ExecuteRoute() : super('/execute');
  static const name = 'execute';
}

class ExecutionHistoryRoute extends AppRoute {
  const ExecutionHistoryRoute() : super('/execute/history');
  static const name = 'execution_history';
}

class ScheduleRoute extends AppRoute {
  const ScheduleRoute() : super('/schedule');
  static const name = 'schedule';
}

class ScheduleEditorRoute {
  static const newName = 'schedule_new';
  static const editName = 'schedule_edit';
}

class SettingsRoute extends AppRoute {
  const SettingsRoute() : super('/settings');
  static const name = 'settings';
}

class AdvancedSettingsRoute extends AppRoute {
  const AdvancedSettingsRoute() : super('/settings/advanced');
  static const name = 'settings_advanced';
}

class LogsRoute extends AppRoute {
  const LogsRoute() : super('/logs');
  static const name = 'logs';
}

class LogDetailRoute extends AppRoute {
  const LogDetailRoute() : super('/logs/:id');
  static const name = 'log_detail';
}

class DeviceRoute extends AppRoute {
  const DeviceRoute() : super('/device');
  static const name = 'device';
}
