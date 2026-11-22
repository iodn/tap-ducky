import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/services/local_drafts_service.dart';
import 'section_card.dart';

class LocalDraftSettings extends ConsumerStatefulWidget {
  const LocalDraftSettings({super.key});

  @override
  ConsumerState<LocalDraftSettings> createState() => _LocalDraftSettingsState();
}

class _LocalDraftSettingsState extends ConsumerState<LocalDraftSettings> {
  bool _busy = false;
  String? _error;

  Future<void> _changeModel(bool remove) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final service = ref.read(localDraftsServiceProvider);
    try {
      if (remove) {
        await service.removeModel();
      } else {
        await service.pickModel();
      }
      if (mounted) ref.invalidate(localModelStatusProvider);
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() => _error = e.message ?? 'Could not change the model.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(localModelStatusProvider).value;
    if (status == null || status == 'unsupported') {
      return const SizedBox.shrink();
    }
    final ready = status == 'ready';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SectionCard(
        title: 'Offline drafting',
        subtitle: ready ? 'Local model selected' : 'Optional model setup',
        leading: const Icon(Icons.auto_awesome_outlined),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Choose a .litertlm model for offline drafting. GGUF files are not supported by LiteRT-LM. TapDucky keeps a local copy on this device.',
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _busy ? null : () => _changeModel(false),
                    child: Text(ready ? 'Replace model' : 'Choose model'),
                  ),
                  if (ready)
                    TextButton(
                      onPressed: _busy ? null : () => _changeModel(true),
                      child: const Text('Remove local copy'),
                    ),
                ],
              ),
              if (_busy)
                const LinearProgressIndicator(semanticsLabel: 'Updating model'),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
