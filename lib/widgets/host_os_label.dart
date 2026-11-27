import 'package:material_ui/material_ui.dart';

import '../data/models/host_os.dart';

class HostOsLabel extends StatelessWidget {
  const HostOsLabel({
    super.key,
    required this.diagnostic,
    this.showTitle = false,
    this.detecting = false,
    this.detectionAvailable = true,
    this.style,
  });

  final HostOsDiagnostic diagnostic;
  final bool showTitle;
  final bool detecting;
  final bool detectionAvailable;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    if (detecting) {
      return Semantics(
        liveRegion: true,
        child: Text('Detecting host OS…', style: style),
      );
    }

    final label = !detectionAvailable && !diagnostic.isKnown
        ? 'Detection unavailable'
        : diagnostic.label;
    final text = Text(
      showTitle ? 'Host OS · $label' : label,
      style: style,
    );
    if (diagnostic.source != HostOsSource.inferred) return text;

    final logo = switch (diagnostic.os) {
      HostOs.android => 'android',
      HostOs.linux => 'linux',
      HostOs.macos || HostOs.ios => 'apple',
      HostOs.windows => 'windows',
      _ => null,
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'Automatically inferred from USB',
          child: logo == null
              ? const Icon(Icons.auto_awesome, size: 18)
              : Image.asset(
                  'assets/images/host_os/$logo.png',
                  width: 18,
                  height: 18,
                  color: Theme.of(context).colorScheme.primary,
                  excludeFromSemantics: true,
                ),
        ),
        const SizedBox(width: 6),
        Flexible(child: text),
      ],
    );
  }
}
