import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../state/controllers/run_observation_controller.dart';

class RunStatusText extends StatefulWidget {
  const RunStatusText({
    super.key,
    required this.status,
    this.observation,
    this.style,
    this.maxLines,
  });

  final String status;
  final RunObservation? observation;
  final TextStyle? style;
  final int? maxLines;

  @override
  State<RunStatusText> createState() => _RunStatusTextState();
}

class _RunStatusTextState extends State<RunStatusText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _updateTimer();
  }

  @override
  void didUpdateWidget(RunStatusText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.observation?.waitUntil != widget.observation?.waitUntil)
      _updateTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _updateTimer() {
    _timer?.cancel();
    final deadline = widget.observation?.waitUntil;
    if (deadline == null || !deadline.isAfter(DateTime.now())) return;
    _timer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      if (!deadline.isAfter(DateTime.now())) timer.cancel();
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final observation = widget.observation;
    final line = observation?.line;
    final deadline = observation?.waitUntil;
    final remaining = deadline?.difference(DateTime.now()).inMilliseconds ?? 0;
    final seconds = (remaining / 1000).ceil();
    return Text(
      [
        if (line != null) 'Line $line',
        widget.status,
        if (seconds > 0)
          '${observation!.conditionTimeout ? 'up to ' : ''}${seconds}s',
      ].join(' · '),
      style: widget.style,
      maxLines: widget.maxLines,
      overflow: widget.maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
}
