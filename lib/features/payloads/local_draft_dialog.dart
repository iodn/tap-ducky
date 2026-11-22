import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/services/local_drafts_service.dart';

class LocalDraftDialog extends StatefulWidget {
  const LocalDraftDialog({
    super.key,
    required this.service,
    required this.replacing,
  });

  final LocalDraftsService service;
  final bool replacing;

  @override
  State<LocalDraftDialog> createState() => _LocalDraftDialogState();
}

class _LocalDraftDialogState extends State<LocalDraftDialog> {
  final _prompt = TextEditingController();
  PayloadDraft? _draft;
  String? _error;
  bool _generating = false;

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final prompt = _prompt.text.trim();
    if (prompt.isEmpty) {
      setState(() => _error = 'Describe what you want the script to type.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final draft = await widget.service.generate(prompt);
      if (mounted) setState(() => _draft = draft);
    } on FormatException {
      if (mounted) {
        setState(
          () => _error =
              'Try a simple typing request, such as “Type hello world 20 times.”',
        );
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.message ?? 'The model could not generate a draft.',
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    return AlertDialog(
      scrollable: true,
      title: Text(draft == null ? 'Draft with AI' : 'Review draft'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (draft == null) ...[
            const Text(
              'Describe a plain-text typing script. Generation runs on this phone.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _prompt,
              enabled: !_generating,
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Request',
                hintText: 'Type hello world 20 times',
                errorText: _error,
                errorMaxLines: 4,
              ),
            ),
            if (_generating) ...[
              const LinearProgressIndicator(semanticsLabel: 'Generating draft'),
              const SizedBox(height: 8),
              const Text('Generating on this phone…'),
            ],
          ] else ...[
            Text(draft.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(draft.description),
            if (draft.tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Tags: ${draft.tags.join(', ')}'),
            ],
            const SizedBox(height: 12),
            SelectableText(
              draft.script,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            if (widget.replacing) ...[
              const SizedBox(height: 12),
              const Text(
                'Applying this draft replaces the title, description, tags, and script.',
              ),
            ],
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (draft == null)
          FilledButton(
            onPressed: _generating ? null : _generate,
            child: const Text('Generate'),
          )
        else ...[
          TextButton(
            onPressed: () => setState(() => _draft = null),
            child: const Text('Edit request'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, draft),
            child: const Text('Use draft'),
          ),
        ],
      ],
    );
  }
}
