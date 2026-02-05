import 'package:flutter/material.dart';

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool dangerous = false,
}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(cancelLabel)),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: dangerous ? FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error) : null,
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return res ?? false;
}
