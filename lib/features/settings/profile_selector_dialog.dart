import 'package:flutter/material.dart';

enum GadgetProfileType {
  keyboard,
  mouse,
  composite;

  String get displayName {
    switch (this) {
      case GadgetProfileType.keyboard:
        return 'Keyboard Only';
      case GadgetProfileType.mouse:
        return 'Mouse Only';
      case GadgetProfileType.composite:
        return 'Composite (Keyboard + Mouse)';
    }
  }

  String get description {
    switch (this) {
      case GadgetProfileType.keyboard:
        return 'Single HID keyboard device. Use for typing and key combinations.';
      case GadgetProfileType.mouse:
        return 'Single HID mouse device. Use for cursor movement and clicks.';
      case GadgetProfileType.composite:
        return 'Combined keyboard and mouse. Recommended for most payloads.';
    }
  }

  IconData get icon {
    switch (this) {
      case GadgetProfileType.keyboard:
        return Icons.keyboard;
      case GadgetProfileType.mouse:
        return Icons.mouse;
      case GadgetProfileType.composite:
        return Icons.devices;
    }
  }
}

Future<GadgetProfileType?> showProfileSelectorDialog(
  BuildContext context, {
  GadgetProfileType? initialSelection,
}) async {
  return showDialog<GadgetProfileType>(
    context: context,
    builder: (context) => _ProfileSelectorDialog(initialSelection: initialSelection),
  );
}

class _ProfileSelectorDialog extends StatefulWidget {
  const _ProfileSelectorDialog({this.initialSelection});

  final GadgetProfileType? initialSelection;

  @override
  State<_ProfileSelectorDialog> createState() => _ProfileSelectorDialogState();
}

class _ProfileSelectorDialogState extends State<_ProfileSelectorDialog> {
  late GadgetProfileType _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSelection ?? GadgetProfileType.composite;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Select USB Gadget Profile'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose the HID device type to activate:',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            for (final type in GadgetProfileType.values) ...[
              _ProfileOption(
                type: type,
                selected: _selected == type,
                onTap: () => setState(() => _selected = type),
              ),
              if (type != GadgetProfileType.values.last) const SizedBox(height: 12),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          child: const Text('Activate'),
        ),
      ],
    );
  }
}

class _ProfileOption extends StatelessWidget {
  const _ProfileOption({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final GadgetProfileType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              type.icon,
              color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          type.displayName,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: selected ? cs.onPrimaryContainer : null,
                          ),
                        ),
                      ),
                      if (type == GadgetProfileType.composite)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: cs.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'RECOMMENDED',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: cs.onPrimary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    type.description,
                    style: TextStyle(
                      fontSize: 12,
                      color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Radio<GadgetProfileType>(
              value: type,
              groupValue: selected ? type : null,
              onChanged: (_) => onTap(),
            ),
          ],
        ),
      ),
    );
  }
}
