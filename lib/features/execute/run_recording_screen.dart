import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../state/controllers/run_observation_controller.dart';

class RunRecordingScreen extends ConsumerWidget {
  const RunRecordingScreen({super.key, required this.executionId});

  final String executionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recording = ref.watch(runRecordingProvider(executionId));
    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: const Text('Run details'),
        actions: [
          if (recording.value case final data?)
            IconButton(
              tooltip: 'Share this run',
              icon: const Icon(Icons.ios_share),
              onPressed: () => Share.share(
                const JsonEncoder.withIndent('  ').convert(data.toShareJson()),
                subject: 'TapDucky run recording',
              ),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: recording.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) =>
              const Center(child: Text('Could not load this recording')),
          data: (data) => data == null
              ? const Center(child: Text('No recording for this run'))
              : ListView(
                  children: [
                    for (final event in data.events)
                      ListTile(
                        title: Text(event.kind.label),
                        subtitle: Text(
                          [
                            '+${(event.elapsedMs / 1000).toStringAsFixed(2)} s',
                            if (event.line case final line?) 'Line $line',
                            if (event.waitMs case final ms?)
                              '${(ms / 1000).toStringAsFixed(1)} s wait',
                          ].join(' · '),
                        ),
                      ),
                    if (data.omittedEvents > 0)
                      ListTile(
                        title: Text(
                          '${data.omittedEvents} additional events omitted',
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
