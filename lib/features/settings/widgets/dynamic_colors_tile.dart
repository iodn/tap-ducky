import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../state/controllers/dynamic_color_controller.dart';

class DynamicColorsTile extends ConsumerWidget {
  const DynamicColorsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(dynamicColorsControllerProvider);
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(Icons.wallpaper_rounded, color: cs.primary),
      title: const Text('Use dynamic colors'),
      subtitle: Text(
        Platform.isAndroid
            ? 'Match your system Material You palette on supported devices.'
            : 'Dynamic colors are only available on Android 12+.',
      ),
      trailing: Switch.adaptive(
        value: enabled,
        onChanged: (v) async {
          await ref.read(dynamicColorsControllerProvider.notifier).setEnabled(v);
          HapticFeedback.selectionClick();
        },
      ),
    );
  }
}
