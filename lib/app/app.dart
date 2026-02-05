import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dynamic_color/dynamic_color.dart';

import '../state/controllers/app_settings_controller.dart';
import '../state/controllers/dynamic_color_controller.dart';
import 'router.dart';
import 'theme.dart';

class TapDuckyApp extends ConsumerWidget {
  const TapDuckyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(appSettingsControllerProvider);
    final router = ref.watch(appRouterProvider);

    return settingsAsync.when(
      loading: () => DynamicColorBuilder(
        builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
          final enabled = ref.watch(dynamicColorsControllerProvider);
          return MaterialApp(
            debugShowCheckedModeBanner: kDebugMode,
            title: 'TapDucky',
            theme: AppTheme.light(dynamicScheme: enabled ? lightDynamic : null),
            darkTheme: AppTheme.dark(dynamicScheme: enabled ? darkDynamic : null),
            home: const _BootScreen(),
          );
        },
      ),
      error: (e, st) => DynamicColorBuilder(
        builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
          final enabled = ref.watch(dynamicColorsControllerProvider);
          return MaterialApp(
            debugShowCheckedModeBanner: kDebugMode,
            title: 'TapDucky',
            theme: AppTheme.light(dynamicScheme: enabled ? lightDynamic : null),
            darkTheme: AppTheme.dark(dynamicScheme: enabled ? darkDynamic : null),
            home: _ErrorScreen(error: e),
          );
        },
      ),
      data: (settings) {
        return DynamicColorBuilder(
          builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
            final enabled = ref.watch(dynamicColorsControllerProvider);
            return MaterialApp.router(
              debugShowCheckedModeBanner: kDebugMode,
              title: 'TapDucky',
              theme: AppTheme.light(dynamicScheme: enabled ? lightDynamic : null),
              darkTheme: AppTheme.dark(dynamicScheme: enabled ? darkDynamic : null),
              themeMode: settings.themeMode,
              routerConfig: router,
            );
          },
        );
      },
    );
  }
}

class _BootScreen extends StatelessWidget {
  const _BootScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SizedBox(
          width: 44,
          height: 44,
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 44),
                const SizedBox(height: 12),
                const Text('TapDucky failed to start', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text('$error', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
