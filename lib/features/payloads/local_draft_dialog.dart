import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../data/services/local_drafts_service.dart';
import '../../widgets/ducky_script_text.dart';
import '../../widgets/configuration_page.dart';

typedef DraftApplication = ({PayloadDraft draft, bool scriptOnly});

class LocalDraftDialog extends StatefulWidget {
  const LocalDraftDialog({
    super.key,
    required this.service,
    required this.replacing,
    required this.editingExisting,
  });

  final LocalDraftsService service;
  final bool replacing;
  final bool editingExisting;

  @override
  State<LocalDraftDialog> createState() => _LocalDraftDialogState();
}

class _LocalDraftDialogState extends State<LocalDraftDialog> {
  final _prompt = TextEditingController();
  PayloadDraft? _draft;
  String? _error;
  bool _generating = false;
  late bool _scriptOnly = widget.editingExisting || widget.replacing;

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final prompt = _prompt.text.trim();
    if (prompt.isEmpty) {
      setState(() => _error = 'Describe what the script should do.');
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
    } on FormatException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.message.isEmpty
              ? 'The model returned an unusable draft. Try rephrasing the request.'
              : e.message,
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
    return ConfigurationPage(
      title: draft == null ? 'Draft with AI' : 'Review draft',
      actionLabel: draft == null ? 'Generate' : 'Use draft',
      onAction: draft == null
          ? (_generating ? null : _generate)
          : () => Navigator.pop<DraftApplication>(context, (
              draft: draft,
              scriptOnly: _scriptOnly,
            )),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (draft == null) ...[
            TextField(
              controller: _prompt,
              enabled: !_generating,
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Request',
                hintText: 'Describe what the script should do',
                errorText: _error,
                errorMaxLines: 4,
              ),
            ),
            if (_generating) ...[
              const LinearProgressIndicator(semanticsLabel: 'Generating draft'),
              const SizedBox(height: 8),
              const Text('Drafting on this device…'),
            ],
          ] else ...[
            TextButton.icon(
              onPressed: () => setState(() => _draft = null),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit request'),
            ),
            if (widget.editingExisting || widget.replacing)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Replace script only'),
                subtitle: Text(
                  _scriptOnly
                      ? 'Keep the current name, description, and tags.'
                      : 'Use the draft’s name, description, and tags too.',
                ),
                value: _scriptOnly,
                onChanged: (value) => setState(() => _scriptOnly = value),
              ),
            Text(draft.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(draft.description),
            if (draft.tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Tags: ${draft.tags.join(', ')}'),
            ],
            const SizedBox(height: 12),
            DuckyScriptText(draft.script, selectable: true),
          ],
        ],
      ),
    );
  }
}
