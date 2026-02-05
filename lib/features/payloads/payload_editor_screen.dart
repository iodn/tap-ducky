import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../app/router.dart';
import '../../data/models/payload.dart';
import '../../data/services/ducky_script_validator.dart';
import '../../data/services/platform_gadget_service.dart';
import '../../state/controllers/app_settings_controller.dart';
import '../../state/controllers/payloads_controller.dart';
import '../../state/providers.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/section_header.dart';

const _uuid = Uuid();

class PayloadEditorScreen extends ConsumerStatefulWidget {
  const PayloadEditorScreen({super.key, this.payloadId});

  final String? payloadId;

  @override
  ConsumerState<PayloadEditorScreen> createState() => _PayloadEditorScreenState();
}

class _PayloadEditorScreenState extends ConsumerState<PayloadEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _scriptCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();

  final List<PayloadParameter> _params = [];
  bool _isBuiltin = false;
  bool _hasChanges = false;

  final _validator = DuckyScriptValidator();
  ValidationResult _validationResult = ValidationResult.empty();
  Timer? _validationDebounce;
  Timer? _estimateDebounce;
  bool _showValidation = false;
  int? _engineEstimateMs;
  String _lastEstimateKey = '';

  double _currentDelayMultiplier() {
    final settings = ref.read(appSettingsControllerProvider).value;
    final m = settings?.delayMultiplier;
    if (m == null || m <= 0) return 1.0;
    return m;
  }

  @override
  void initState() {
    super.initState();
    _loadPayload();
    _scriptCtrl.addListener(_onScriptChanged);
  }

  @override
  void dispose() {
    _validationDebounce?.cancel();
    _estimateDebounce?.cancel();
    _scriptCtrl.removeListener(_onScriptChanged);
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _scriptCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  void _onScriptChanged() {
    _validationDebounce?.cancel();
    _validationDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final mul = _currentDelayMultiplier();
      setState(() {
        _validationResult = _validator.validate(_scriptCtrl.text, delayMultiplier: mul);
        _showValidation = _scriptCtrl.text.trim().isNotEmpty;
      });
      _requestEngineEstimate(_scriptCtrl.text);
    });
  }

  void _loadPayload() {
    final id = widget.payloadId;
    if (id == null) return;

    final async = ref.read(payloadsControllerProvider);
    final items = async.value ?? [];
    final found = items.where((e) => e.id == id).firstOrNull;

    if (found != null) {
      _nameCtrl.text = found.name;
      _descCtrl.text = found.description;
      _scriptCtrl.text = found.script;
      _tagsCtrl.text = found.tags.join(', ');
      _params.addAll(found.parameters);
      _isBuiltin = found.isBuiltin;

      final mul = _currentDelayMultiplier();
      _validationResult = _validator.validate(found.script, delayMultiplier: mul);
      _showValidation = found.script.trim().isNotEmpty;
      _requestEngineEstimate(found.script);
    }
  }

  void _requestEngineEstimate(String script) {
    final trimmed = script.trim();
    if (trimmed.isEmpty) {
      setState(() => _engineEstimateMs = null);
      return;
    }
    final mul = _currentDelayMultiplier();
    final key = '${trimmed.hashCode}::$mul';
    if (key == _lastEstimateKey) return;
    _lastEstimateKey = key;

    _estimateDebounce?.cancel();
    _estimateDebounce = Timer(const Duration(milliseconds: 600), () async {
      final service = ref.read(platformGadgetServiceProvider);
      try {
        final ms = await service.estimateDuckyScriptDurationMs(
          script: script,
          delayMultiplier: mul,
        );
        if (!mounted) return;
        setState(() => _engineEstimateMs = ms);
      } catch (_) {
        if (!mounted) return;
        setState(() => _engineEstimateMs = null);
      }
    });
  }

  String _formatDuration(int ms) {
    final seconds = ms / 1000;
    if (seconds < 1) return '${ms}ms';
    if (seconds < 60) return '${seconds.toStringAsFixed(1)}s';
    final minutes = seconds ~/ 60;
    final remainingSeconds = (seconds % 60).round();
    return '${minutes}m ${remainingSeconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.payloadId == null;
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !_hasChanges,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final ok = await showConfirmDialog(
          context,
          title: 'Discard changes?',
          message: 'You have unsaved changes. Discard them?',
          confirmLabel: 'Discard',
          dangerous: true,
        );
        if (ok && context.mounted) {
          context.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(isNew ? 'New Payload' : 'Edit Payload'),
          actions: [
            if (_showValidation && (_validationResult.hasErrors || _validationResult.hasWarnings))
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: IconButton(
                  icon: Badge(
                    label: Text('${_validationResult.errorCount + _validationResult.warningCount}'),
                    backgroundColor: _validationResult.hasErrors ? cs.error : cs.tertiary,
                    child: Icon(
                      _validationResult.hasErrors ? Icons.error : Icons.warning,
                      color: _validationResult.hasErrors ? cs.error : cs.tertiary,
                    ),
                  ),
                  onPressed: () => _showValidationDialog(context),
                  tooltip: 'Show validation issues',
                ),
              ),
            if (!isNew && !_isBuiltin)
              IconButton(
                icon: const Icon(Icons.delete),
                tooltip: 'Delete',
                onPressed: () => _delete(context),
              ),
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: 'Save',
              onPressed: _validationResult.hasErrors ? null : _save,
            ),
          ],
        ),
        body: Form(
          key: _formKey,
          onChanged: () => setState(() => _hasChanges = true),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              if (_isBuiltin)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.tertiaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lock, color: cs.onTertiaryContainer),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'This is a built-in payload. You can duplicate it to create a custom version.',
                            style: TextStyle(color: cs.onTertiaryContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SectionHeader(title: 'Basic Info'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Name',
                            hintText: 'e.g., Windows Run Dialog',
                            prefixIcon: Icon(Icons.title),
                          ),
                          validator: (v) => (v?.trim().isEmpty ?? true) ? 'Name is required' : null,
                          enabled: !_isBuiltin,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _descCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Description',
                            hintText: 'What does this payload do?',
                            prefixIcon: Icon(Icons.description),
                          ),
                          maxLines: 2,
                          enabled: !_isBuiltin,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _tagsCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Tags',
                            hintText: 'windows, recon, exfil (comma-separated)',
                            prefixIcon: Icon(Icons.label),
                          ),
                          enabled: !_isBuiltin,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const SectionHeader(title: 'Script'),
              if (_showValidation)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _ValidationSummaryCard(
                    result: _validationResult,
                    engineEstimateMs: _engineEstimateMs,
                    formatDuration: _formatDuration,
                    onTap: () => _showValidationDialog(context),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.code, size: 20, color: cs.primary),
                            const SizedBox(width: 8),
                            const Text(
                              'DuckyScript',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: () => _showSyntaxHelp(context),
                              icon: const Icon(Icons.help_outline, size: 18),
                              label: const Text('Syntax'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _scriptCtrl,
                          decoration: InputDecoration(
                            hintText: 'DELAY 500\nSTRING Hello World\nENTER',
                            border: const OutlineInputBorder(),
                            filled: true,
                            fillColor: cs.surfaceContainerHighest,
                          ),
                          maxLines: 15,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                          validator: (v) => (v?.trim().isEmpty ?? true) ? 'Script is required' : null,
                          enabled: !_isBuiltin,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Use {{PARAM_NAME}} for dynamic values',
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SectionHeader(
                title: 'Parameters (${_params.length})',
                trailing: _isBuiltin
                    ? null
                    : TextButton.icon(
                        onPressed: _addParameter,
                        icon: const Icon(Icons.add),
                        label: const Text('Add'),
                      ),
              ),
              if (_params.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Card(
                    child: ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('No parameters'),
                      subtitle: const Text(
                        'Add parameters to make this payload reusable with different values.',
                      ),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Card(
                    child: Column(
                      children: [
                        for (int i = 0; i < _params.length; i++) ...[
                          _ParameterTile(
                            param: _params[i],
                            onEdit: _isBuiltin ? null : () => _editParameter(i),
                            onDelete: _isBuiltin ? null : () => _deleteParameter(i),
                          ),
                          if (i != _params.length - 1) const Divider(height: 1),
                        ],
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              const SectionHeader(title: 'Quick Actions'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.content_copy),
                        title: const Text('Duplicate'),
                        subtitle: const Text('Create a copy of this payload'),
                        onTap: () => _duplicate(context),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.ios_share),
                        title: const Text('Export'),
                        subtitle: const Text('Share as JSON'),
                        onTap: _export,
                      ),
                      if (!isNew && !_isBuiltin) ...[
                        const Divider(height: 1),
                        ListTile(
                          leading: Icon(Icons.delete, color: cs.error),
                          title: Text('Delete', style: TextStyle(color: cs.error)),
                          subtitle: const Text('Remove this payload permanently'),
                          onTap: () => _delete(context),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 80),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _validationResult.hasErrors ? null : _save,
          icon: const Icon(Icons.check),
          label: const Text('Save'),
          backgroundColor: _validationResult.hasErrors ? cs.surfaceContainerHighest : null,
          foregroundColor: _validationResult.hasErrors ? cs.onSurfaceVariant : null,
        ),
      ),
    );
  }

  void _showValidationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _ValidationDialog(
        result: _validationResult,
        engineEstimateMs: _engineEstimateMs,
        formatDuration: _formatDuration,
      ),
    );
  }

  void _addParameter() {
    showDialog(
      context: context,
      builder: (context) => _ParameterDialog(
        onSave: (param) {
          setState(() {
            _params.add(param);
            _hasChanges = true;
          });
        },
      ),
    );
  }

  void _editParameter(int index) {
    showDialog(
      context: context,
      builder: (context) => _ParameterDialog(
        initial: _params[index],
        onSave: (param) {
          setState(() {
            _params[index] = param;
            _hasChanges = true;
          });
        },
      ),
    );
  }

  void _deleteParameter(int index) {
    setState(() {
      _params.removeAt(index);
      _hasChanges = true;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_validationResult.hasErrors) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot save: script has validation errors'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final tags = _tagsCtrl.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final payload = Payload(
      id: widget.payloadId ?? _uuid.v4(),
      name: _nameCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      script: _scriptCtrl.text,
      tags: tags,
      parameters: _params,
      isBuiltin: _isBuiltin,
    );

    if (widget.payloadId == null) {
      await ref.read(payloadsControllerProvider.notifier).create(payload);
    } else {
      await ref.read(payloadsControllerProvider.notifier).updatePayload(payload);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.payloadId == null ? 'Payload created' : 'Payload updated')),
      );
      context.go(const PayloadsRoute().location);
    }
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete payload',
      message: 'Delete "${_nameCtrl.text}"? This cannot be undone.',
      confirmLabel: 'Delete',
      dangerous: true,
    );
    if (!ok) return;

    await ref.read(payloadsControllerProvider.notifier).delete(widget.payloadId!);

    if (mounted) {
      context.go(const PayloadsRoute().location);
    }
  }

  Future<void> _duplicate(BuildContext context) async {
    final id = widget.payloadId;
    if (id == null) return;

    await ref.read(payloadsControllerProvider.notifier).duplicate(id);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payload duplicated')),
      );
      context.go(const PayloadsRoute().location);
    }
  }

  Future<void> _export() async {
    final tags = _tagsCtrl.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final payload = Payload(
      id: widget.payloadId ?? _uuid.v4(),
      name: _nameCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      script: _scriptCtrl.text,
      tags: tags,
      parameters: _params,
      isBuiltin: _isBuiltin,
    );

    final json = payload.exportJson();
    await Share.share(json, subject: 'TapDucky payload: ${payload.name}');
  }

  void _showSyntaxHelp(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('DuckyScript Syntax'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text(
                'Keystroke Injection',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              SizedBox(height: 8),
              _SyntaxItem(cmd: 'STRING text', desc: 'Type text'),
              _SyntaxItem(cmd: 'STRINGLN text', desc: 'Type text + Enter'),
              _SyntaxItem(cmd: 'DELAY ms', desc: 'Wait milliseconds'),
              SizedBox(height: 12),
              Text(
                'System Keys',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              SizedBox(height: 8),
              _SyntaxItem(cmd: 'ENTER', desc: 'Press Enter'),
              _SyntaxItem(cmd: 'TAB', desc: 'Press Tab'),
              _SyntaxItem(cmd: 'ESC', desc: 'Press Escape'),
              _SyntaxItem(cmd: 'BACKSPACE', desc: 'Press Backspace'),
              _SyntaxItem(cmd: 'DELETE', desc: 'Press Delete'),
              SizedBox(height: 12),
              Text(
                'Modifiers',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              SizedBox(height: 8),
              _SyntaxItem(cmd: 'GUI r', desc: 'Windows+R'),
              _SyntaxItem(cmd: 'CTRL ALT DEL', desc: 'Ctrl+Alt+Del'),
              _SyntaxItem(cmd: 'ALT F4', desc: 'Alt+F4'),
              _SyntaxItem(cmd: 'CTRL c', desc: 'Ctrl+C'),
              SizedBox(height: 12),
              Text(
                'Variables',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              SizedBox(height: 8),
              _SyntaxItem(cmd: '{{PARAM}}', desc: 'Parameter placeholder'),
              _SyntaxItem(cmd: 'VAR \$FOO = 42', desc: 'Define variable'),
              _SyntaxItem(cmd: 'DEFINE #CONST 100', desc: 'Define constant'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }
}

/* Validation Summary Card Widget */
class _ValidationSummaryCard extends StatelessWidget {
  const _ValidationSummaryCard({
    required this.result,
    required this.engineEstimateMs,
    required this.formatDuration,
    required this.onTap,
  });

  final ValidationResult result;
  final int? engineEstimateMs;
  final String Function(int) formatDuration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Color bgColor;
    Color fgColor;
    IconData icon;
    String title;

    if (result.hasErrors) {
      bgColor = cs.errorContainer;
      fgColor = cs.onErrorContainer;
      icon = Icons.error;
      title = 'Script has errors';
    } else if (result.hasWarnings) {
      bgColor = cs.tertiaryContainer;
      fgColor = cs.onTertiaryContainer;
      icon = Icons.warning;
      title = 'Script has warnings';
    } else {
      bgColor = cs.primaryContainer;
      fgColor = cs.onPrimaryContainer;
      icon = Icons.check_circle;
      title = 'Script is valid';
    }

    return Card(
      color: bgColor,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: fgColor, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: fgColor,
                      ),
                    ),
                  ),
                  if (result.hasErrors || result.hasWarnings)
                    Icon(Icons.chevron_right, color: fgColor, size: 20),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _StatChip(
                    icon: Icons.code,
                    label: '${result.commandCount} commands',
                    color: fgColor,
                  ),
                  const SizedBox(width: 8),
                  _StatChip(
                    icon: Icons.timer,
                    label: engineEstimateMs != null
                        ? '~${formatDuration(engineEstimateMs!)}'
                        : '~${result.estimatedDurationFormatted}',
                    color: fgColor,
                  ),
                ],
              ),
              if (result.hasErrors || result.hasWarnings) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (result.errorCount > 0) ...[
                      Icon(Icons.error, size: 16, color: cs.error),
                      const SizedBox(width: 4),
                      Text(
                        '${result.errorCount} error${result.errorCount != 1 ? 's' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.error,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    if (result.warningCount > 0) ...[
                      Icon(Icons.warning, size: 16, color: cs.tertiary),
                      const SizedBox(width: 4),
                      Text(
                        '${result.warningCount} warning${result.warningCount != 1 ? 's' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.tertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/* Validation Dialog Widget */
class _ValidationDialog extends StatelessWidget {
  const _ValidationDialog({
    required this.result,
    required this.engineEstimateMs,
    required this.formatDuration,
  });

  final ValidationResult result;
  final int? engineEstimateMs;
  final String Function(int) formatDuration;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Validation Results'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.code, size: 16, color: cs.primary),
                      const SizedBox(width: 8),
                      Text(
                        '${result.commandCount} commands',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.timer, size: 16, color: cs.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Estimated duration: ~${engineEstimateMs != null ? formatDuration(engineEstimateMs!) : result.estimatedDurationFormatted}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Total delays: ${(result.totalDelayMs / 1000).toStringAsFixed(1)}s',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (result.issues.isEmpty) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.check_circle, color: cs.primary),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'No issues found. Script is valid!',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 16),
              Text(
                'Issues (${result.issues.length})',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: result.issues.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final issue = result.issues[i];
                    return _IssueListTile(issue: issue);
                  },
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}

class _IssueListTile extends StatelessWidget {
  const _IssueListTile({required this.issue});

  final ValidationIssue issue;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    IconData icon;
    Color color;

    switch (issue.severity) {
      case IssueSeverity.error:
        icon = Icons.error;
        color = cs.error;
        break;
      case IssueSeverity.warning:
        icon = Icons.warning;
        color = cs.tertiary;
        break;
      case IssueSeverity.info:
        icon = Icons.info;
        color = cs.primary;
        break;
    }

    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20, color: color),
      title: Text(
        issue.line > 0 ? 'Line ${issue.line}' : 'Script',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(issue.message, style: const TextStyle(fontSize: 13)),
          if (issue.suggestion != null) ...[
            const SizedBox(height: 4),
            Text(
              issue.suggestion!,
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: cs.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SyntaxItem extends StatelessWidget {
  const _SyntaxItem({required this.cmd, required this.desc});

  final String cmd;
  final String desc;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              cmd,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(child: Text(desc, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}

class _ParameterTile extends StatelessWidget {
  const _ParameterTile({
    required this.param,
    required this.onEdit,
    required this.onDelete,
  });

  final PayloadParameter param;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.settings_input_component),
      title: Text(param.label),
      subtitle: Text('{{${param.key}}} • ${param.type}${param.required ? " • required" : ""}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onEdit != null)
            IconButton(
              icon: const Icon(Icons.edit, size: 20),
              onPressed: onEdit,
            ),
          if (onDelete != null)
            IconButton(
              icon: const Icon(Icons.delete, size: 20),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}

class _ParameterDialog extends StatefulWidget {
  const _ParameterDialog({this.initial, required this.onSave});

  final PayloadParameter? initial;
  final ValueChanged<PayloadParameter> onSave;

  @override
  State<_ParameterDialog> createState() => _ParameterDialogState();
}

class _ParameterDialogState extends State<_ParameterDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _keyCtrl;
  late final TextEditingController _labelCtrl;
  late final TextEditingController _defaultCtrl;
  late final TextEditingController _descCtrl;

  late String _type;
  late bool _required;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    _keyCtrl = TextEditingController(text: p?.key ?? '');
    _labelCtrl = TextEditingController(text: p?.label ?? '');
    _defaultCtrl = TextEditingController(text: p?.defaultValue ?? '');
    _descCtrl = TextEditingController(text: p?.description ?? '');
    _type = p?.type ?? 'text';
    _required = p?.required ?? false;
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _labelCtrl.dispose();
    _defaultCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Add Parameter' : 'Edit Parameter'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _keyCtrl,
                decoration: const InputDecoration(
                  labelText: 'Key',
                  hintText: 'TARGET_IP',
                ),
                validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _labelCtrl,
                decoration: const InputDecoration(
                  labelText: 'Label',
                  hintText: 'Target IP Address',
                ),
                validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Optional description',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _type,
                items: const [
                  DropdownMenuItem(value: 'text', child: Text('Text')),
                  DropdownMenuItem(value: 'number', child: Text('Number')),
                  DropdownMenuItem(value: 'url', child: Text('URL')),
                ],
                onChanged: (v) => setState(() => _type = v!),
                decoration: const InputDecoration(labelText: 'Type'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _defaultCtrl,
                decoration: const InputDecoration(
                  labelText: 'Default Value',
                  hintText: '192.168.1.1',
                ),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: _required,
                onChanged: (v) => setState(() => _required = v!),
                title: const Text('Required'),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            final param = PayloadParameter(
              key: _keyCtrl.text.trim(),
              label: _labelCtrl.text.trim(),
              description: _descCtrl.text.trim(),
              type: _type,
              defaultValue: _defaultCtrl.text.trim(),
              required: _required,
            );
            widget.onSave(param);
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
