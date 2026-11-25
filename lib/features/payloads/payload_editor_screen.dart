import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../app/router.dart';
import '../../data/models/payload.dart';
import '../../data/services/ducky_script.dart';
import '../../data/services/ducky_script_validator.dart';
import '../../data/services/local_drafts_service.dart';
import '../../state/controllers/app_settings_controller.dart';
import '../../state/controllers/payloads_controller.dart';
import '../../state/providers.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/configuration_page.dart';
import '../../widgets/ducky_script_text.dart';
import '../settings/widgets/local_draft_settings.dart';
import 'local_draft_dialog.dart';

const _uuid = Uuid();

class PayloadEditorScreen extends ConsumerStatefulWidget {
  const PayloadEditorScreen({super.key, this.payloadId});

  final String? payloadId;

  @override
  ConsumerState<PayloadEditorScreen> createState() =>
      _PayloadEditorScreenState();
}

class _PayloadEditorScreenState extends ConsumerState<PayloadEditorScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _scriptFocus = FocusNode();
  final _scriptScroll = ScrollController();
  final _nameFocus = FocusNode();
  int _section = 0;
  String? _nameError;
  String? _scriptError;
  bool _saving = false;
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _scriptCtrl = DuckyScriptEditingController();
  final _tagsCtrl = TextEditingController();

  final List<PayloadParameter> _params = [];
  bool _isBuiltin = false;
  bool _editReady = false;
  bool _hasChanges = false;

  final _validator = DuckyScriptValidator();
  ValidationResult _validationResult = ValidationResult.empty();
  Timer? _validationDebounce;
  Timer? _estimateDebounce;
  bool _showValidation = false;
  int? _engineEstimateMs;
  ValidationIssue? _engineIssue;
  int _estimateRevision = 0;
  String _observedScript = '';

  double _currentDelayMultiplier() {
    final settings = ref.read(appSettingsControllerProvider).value;
    final m = settings?.delayMultiplier;
    if (m == null || m <= 0) return 1.0;
    return m;
  }

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this)..addListener(_changeSection);
    _scriptCtrl.addListener(_onScriptChanged);
    if (widget.payloadId != null) {
      ref.listenManual(
        payloadsControllerProvider,
        (_, next) => _loadPayload(next.value),
        fireImmediately: true,
      );
    }
  }

  @override
  void dispose() {
    _validationDebounce?.cancel();
    _estimateDebounce?.cancel();
    _scriptCtrl.removeListener(_onScriptChanged);
    _tabs.dispose();
    _scriptFocus.dispose();
    _scriptScroll.dispose();
    _nameFocus.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _scriptCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  void _onScriptChanged() {
    if (_scriptCtrl.text == _observedScript) return;
    _observedScript = _scriptCtrl.text;
    _estimateRevision++;
    _estimateDebounce?.cancel();
    setState(() {
      _hasChanges = true;
      _scriptError = null;
      _engineEstimateMs = null;
      _engineIssue = null;
    });
    _validationDebounce?.cancel();
    _validationDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final mul = _currentDelayMultiplier();
      setState(() {
        _validationResult = _validator.validate(
          _scriptCtrl.text,
          delayMultiplier: mul,
        );
        _showValidation = _scriptCtrl.text.trim().isNotEmpty;
      });
      _requestEngineEstimate(_scriptCtrl.text);
    });
  }

  Future<void> _showLocalDraft() async {
    final draft = await showConfigurationPage<PayloadDraft>(
      context,
      (_) => LocalDraftDialog(
        service: ref.read(localDraftsServiceProvider),
        replacing: [
          _nameCtrl,
          _descCtrl,
          _tagsCtrl,
          _scriptCtrl,
        ].any((controller) => controller.text.isNotEmpty),
      ),
    );
    if (!mounted || draft == null) return;
    setState(() {
      _nameCtrl.text = draft.title;
      _descCtrl.text = draft.description;
      _tagsCtrl.text = draft.tags.join(', ');
      _scriptCtrl.text = draft.script;
      _nameError = null;
      _scriptError = null;
      _hasChanges = true;
    });
  }

  void _loadPayload(List<Payload>? items) {
    if (_editReady || items == null) return;
    final found = items
        .where((payload) => payload.id == widget.payloadId)
        .firstOrNull;
    if (found == null) return;

    setState(() {
      _observedScript = found.script;
      _nameCtrl.text = found.name;
      _descCtrl.text = found.description;
      _scriptCtrl.text = found.script;
      _tagsCtrl.text = found.tags.join(', ');
      _params.addAll(found.parameters);
      _isBuiltin = found.isBuiltin;
      _validationResult = _validator.validate(
        found.script,
        delayMultiplier: _currentDelayMultiplier(),
      );
      _showValidation = found.script.trim().isNotEmpty;
      _editReady = true;
    });
    _requestEngineEstimate(found.script);
  }

  void _requestEngineEstimate(String script) {
    final revision = ++_estimateRevision;
    _estimateDebounce?.cancel();
    if (script.trim().isEmpty ||
        _validationResult.hasErrors ||
        DuckyScript.hasPlaceholders(script))
      return;
    final mul = _currentDelayMultiplier();
    _estimateDebounce = Timer(const Duration(milliseconds: 600), () async {
      final service = ref.read(platformGadgetServiceProvider);
      try {
        final ms = await service.estimateDuckyScriptDurationMs(
          script: script,
          delayMultiplier: mul,
        );
        if (!mounted || revision != _estimateRevision) return;
        setState(() => _engineEstimateMs = ms);
      } on PlatformException catch (error) {
        if (!mounted || revision != _estimateRevision) return;
        final line = error.details;
        if (error.code == 'DUCKY_EXPRESSION_SYNTAX' && line is int) {
          setState(() {
            _engineEstimateMs = null;
            _engineIssue = ValidationIssue(
              line: line,
              severity: IssueSeverity.warning,
              message: error.message ?? 'Invalid expression',
            );
          });
        }
      } catch (_) {
        if (!mounted || revision != _estimateRevision) return;
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
    if (!isNew && !_editReady) {
      final payloads = ref.watch(payloadsControllerProvider);
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Payload')),
        body: Center(
          child: payloads.isLoading
              ? const CircularProgressIndicator()
              : Text(
                  payloads.hasError
                      ? 'Could not load payload'
                      : 'Payload unavailable',
                ),
        ),
      );
    }

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
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(isNew ? 'New Payload' : 'Edit Payload'),
          leading: CloseButton(
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          actions: [
            if (!isNew)
              PopupMenuButton<String>(
                tooltip: 'Payload actions',
                onSelected: (action) async {
                  switch (action) {
                    case 'duplicate':
                      await _duplicate(context);
                    case 'export':
                      await _export();
                    case 'delete':
                      await _delete(context);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'duplicate',
                    child: Text('Duplicate'),
                  ),
                  const PopupMenuItem(value: 'export', child: Text('Export')),
                  if (!_isBuiltin)
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            if (!_isBuiltin)
              TextButton(
                onPressed: _saving ? null : _save,
                child: const Text('Save'),
              ),
          ],
          bottom: TabBar(
            controller: _tabs,
            labelPadding: const EdgeInsets.symmetric(horizontal: 6),
            tabs: [
              for (final label in const ['Script', 'Details', 'Parameters'])
                Tab(
                  child: FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
                ),
            ],
          ),
        ),
        body: SafeArea(
          top: false,
          child: switch (_section) {
            0 => _scriptSection(context),
            1 => _detailsSection(),
            _ => _parametersSection(),
          },
        ),
      ),
    );
  }

  void _changeSection() {
    if (_section == _tabs.index) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _section = _tabs.index);
  }

  void _focusSection(int index, FocusNode focus) {
    _tabs.animateTo(index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _section == index) focus.requestFocus();
    });
  }

  Widget _scriptSection(BuildContext context) {
    final model = ref.watch(localModelStatusProvider).value;
    final theme = Theme.of(context);
    final issueCount = _validationResult.issues.length + (_engineIssue == null ? 0 : 1);
    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: EdgeInsets.fromLTRB(
          12,
          4,
          12,
          constraints.maxHeight < 100 ? 4 : 12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (constraints.maxHeight >= 100)
              Row(
                children: [
                  Expanded(
                    child: _isBuiltin
                        ? const Text('Built-in script · Read only')
                        : model == null || model.state == 'unsupported'
                        ? const SizedBox.shrink()
                        : Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TextButton.icon(
                              icon: const Icon(Icons.auto_awesome_outlined),
                              label: Text(
                                model.state == 'ready'
                                    ? 'Draft with AI'
                                    : 'Set up AI',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onPressed: model.state == 'ready'
                                  ? _showLocalDraft
                                  : _showModelSetup,
                            ),
                          ),
                  ),
                  IconButton(
                    tooltip: 'Syntax',
                    onPressed: () => _showSyntaxHelp(context),
                    icon: const Icon(Icons.help_outline),
                  ),
                  if (_showValidation)
                    IconButton(
                      tooltip: issueCount == 0
                          ? 'Script validation and estimate'
                          : 'Show validation issues',
                      onPressed: () => _showValidationDialog(context),
                      icon: Badge(
                        isLabelVisible: issueCount > 0,
                        label: Text('$issueCount'),
                        child: Icon(
                          issueCount == 0
                              ? Icons.fact_check_outlined
                              : Icons.report_problem_outlined,
                          color: _validationResult.hasErrors
                              ? theme.colorScheme.error
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 4),
            Expanded(
              child: TextFormField(
                key: const ValueKey('payload-script-editor'),
                controller: _scriptCtrl,
                focusNode: _scriptFocus,
                scrollController: _scriptScroll,
                expands: true,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                autocorrect: false,
                enableSuggestions: false,
                smartDashesType: SmartDashesType.disabled,
                smartQuotesType: SmartQuotesType.disabled,
                readOnly: _isBuiltin,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  height: 1.45,
                ),
                decoration: InputDecoration(
                  labelText: 'DuckyScript',
                  alignLabelWithHint: true,
                  hintText:
                      'REM Write your script here\nSTRING Hello world\nENTER',
                  errorText: _scriptError,
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerLow,
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showModelSetup() => showConfigurationPage<void>(
    context,
    (_) => Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: const Text('Set up AI drafting'),
      ),
      body: const SafeArea(
        top: false,
        child: SingleChildScrollView(child: LocalDraftSettings()),
      ),
    ),
  );

  Widget _detailsSection() {
    return ListView(
      key: const PageStorageKey('payload-details'),
      padding: const EdgeInsets.all(16),
      children: [
        TextFormField(
          controller: _nameCtrl,
          focusNode: _nameFocus,
          readOnly: _isBuiltin,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {
            _nameError = null;
            _hasChanges = true;
          }),
          decoration: InputDecoration(
            labelText: 'Name',
            errorText: _nameError,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _descCtrl,
          readOnly: _isBuiltin,
          onChanged: (_) => _hasChanges = true,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Description',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _tagsCtrl,
          readOnly: _isBuiltin,
          onChanged: (_) => _hasChanges = true,
          decoration: const InputDecoration(
            labelText: 'Tags',
            hintText: 'Separate tags with commas',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _parametersSection() {
    return ListView(
      key: const PageStorageKey('payload-parameters'),
      padding: const EdgeInsets.all(16),
      children: [
        if (!_isBuiltin)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.tonalIcon(
              onPressed: _changeParameter,
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('Use {{KEY}} in the script to insert a parameter.'),
        ),
        if (_params.isEmpty) const Text('No parameters'),
        for (var i = 0; i < _params.length; i++) ...[
          _ParameterTile(
            param: _params[i],
            onEdit: _isBuiltin ? null : () => _changeParameter(i),
            onDelete: _isBuiltin ? null : () => _deleteParameter(i),
          ),
          if (i != _params.length - 1) const Divider(height: 1),
        ],
      ],
    );
  }

  void _showValidationDialog(BuildContext context) {
    if (_validationDebounce?.isActive == true) return;
    final issue = _engineIssue;
    final result = issue == null
        ? _validationResult
        : ValidationResult(
            issues: [..._validationResult.issues, issue],
            commandCount: _validationResult.commandCount,
            estimatedDurationMs: _validationResult.estimatedDurationMs,
            totalDelayMs: _validationResult.totalDelayMs,
            hasErrors: _validationResult.hasErrors,
            hasWarnings: true,
          );
    showConfigurationPage<void>(
      context,
      (_) => _ValidationDialog(
        result: result,
        engineEstimateMs: _engineEstimateMs,
        formatDuration: _formatDuration,
      ),
    );
  }

  Future<void> _changeParameter([int? index]) async {
    final initial = index == null ? null : _params[index];
    final reservedKeys = {
      for (var i = 0; i < _params.length; i++)
        if (i != index) _params[i].key,
    };
    final parameter = await showConfigurationPage<PayloadParameter>(
      context,
      (_) => _ParameterEditor(initial: initial, reservedKeys: reservedKeys),
    );
    if (!mounted || parameter == null) return;
    setState(() {
      if (index == null) {
        _params.add(parameter);
      } else {
        _params[index] = parameter;
      }
      _hasChanges = true;
    });
  }

  void _deleteParameter(int index) {
    setState(() {
      _params.removeAt(index);
      _hasChanges = true;
    });
  }

  Future<void> _save() async {
    if (_saving || _isBuiltin) return;
    final script = _scriptCtrl.text;
    final name = _nameCtrl.text.trim();
    _validationDebounce?.cancel();
    final result = _validator.validate(
      script,
      delayMultiplier: _currentDelayMultiplier(),
    );
    setState(() {
      _validationResult = result;
      _showValidation = script.trim().isNotEmpty;
      _scriptError = !_showValidation ? 'Enter a script' : null;
      _nameError = name.isEmpty ? 'Enter a name' : null;
    });
    if (_scriptError != null) {
      _focusSection(0, _scriptFocus);
      return;
    }
    if (result.hasErrors) {
      _tabs.animateTo(0);
      _showValidationDialog(context);
      return;
    }
    if (_nameError != null) {
      _focusSection(1, _nameFocus);
      return;
    }

    final tags = _tagsCtrl.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final payload = Payload(
      id: widget.payloadId ?? _uuid.v4(),
      name: name,
      description: _descCtrl.text.trim(),
      script: script,
      tags: tags,
      parameters: List.of(_params),
      isBuiltin: _isBuiltin,
    );

    setState(() => _saving = true);
    try {
      if (widget.payloadId == null) {
        await ref.read(payloadsControllerProvider.notifier).create(payload);
      } else {
        await ref
            .read(payloadsControllerProvider.notifier)
            .updatePayload(payload);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.payloadId == null ? 'Payload created' : 'Payload updated',
          ),
        ),
      );
      context.go(const PayloadsRoute().location);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save the payload')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
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

    await ref
        .read(payloadsControllerProvider.notifier)
        .delete(widget.payloadId!);

    if (mounted) {
      context.go(const PayloadsRoute().location);
    }
  }

  Future<void> _duplicate(BuildContext context) async {
    final id = widget.payloadId;
    if (id == null) return;

    await ref.read(payloadsControllerProvider.notifier).duplicate(id);

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Payload duplicated')));
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
          TextButton(
            onPressed: () => showConfigurationPage<void>(context, (_) => const _Hak5VariablesPage()),
            child: const Text('Internal variables'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _Hak5VariablesPage extends StatelessWidget {
  const _Hak5VariablesPage();

  static const _compatibilityNotes = {
    r'$_OS': 'Auto-detects Windows, macOS, Linux, and Android. Compare with symbolic OS names.',
    r'$_CURRENT_ATTACKMODE': 'Reports OFF, HID, storage, or HID plus storage when the USB configuration can be verified.',
    r'$_RANDOM_SEED': 'TapDucky generates a fresh seed for each run.',
    r'$_RANDOM_CHAR_KEYCODE': 'Uses the selected layout and TapDucky’s scancode format.',
    r'$_BUTTON_ENABLED': 'Controls the optional Press button action in the task bar.',
    r'$_BUTTON_USER_DEFINED': 'Controls the callback registered by BUTTON_DEF for on-phone taps.',
    r'$_BUTTON_PUSH_RECEIVED': 'Set by Press button or Continue in the task bar.',
    r'$_BUTTON_TIMEOUT': 'Minimum interval between accepted taps, in milliseconds.',
    r'$_SYSTEM_LEDS_ENABLED': 'Controls the on-screen pulse at run start and completion.',
    r'$_INJECTING_LEDS_ENABLED': 'Controls the on-screen pulse during script steps.',
  };

  @override
  Widget build(BuildContext context) {
    const groups = [
      ('Read-only', DuckyScriptValidator.readOnlyHak5Variables),
      ('Writable', DuckyScriptValidator.writableHak5Variables),
      ('Unavailable', DuckyScriptValidator.unsupportedHak5Variables),
    ];
    return Scaffold(
      appBar: AppBar(leading: const CloseButton(), title: const Text('Hak5 variables')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            for (final (title, names) in groups)
              ExpansionTile(
                title: Text('$title (${names.length})'),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final name in names.toList()..sort())
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(name, style: const TextStyle(fontFamily: 'monospace')),
                          if (_compatibilityNotes[name] case final String note) Text(note),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

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

    final estimate = engineEstimateMs == null
        ? 'Rough estimate: ${result.estimatedDurationFormatted}'
        : 'Estimated script time: ~${formatDuration(engineEstimateMs!)}';
    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: const Text('Validation results'),
      ),
      body: SafeArea(
        top: false,
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: result.issues.length + 1,
          itemBuilder: (context, index) {
            if (index > 0)
              return _IssueListTile(issue: result.issues[index - 1]);
            return Card(
              color: cs.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${result.commandCount} commands'),
                    if (!result.hasErrors) ...[
                      Text(estimate),
                      const Text('Excludes host and scheduled waits.'),
                    ],
                    Text(
                      'Total delays: ${(result.totalDelayMs / 1000).toStringAsFixed(1)}s',
                    ),
                    Text(
                      result.issues.isEmpty
                          ? 'No issues found'
                          : 'Issues (${result.issues.length})',
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [DuckyScriptText(cmd), Text(desc)],
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
      subtitle: Text(
        '{{${param.key}}} • ${param.type}${param.required ? " • required" : ""}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onEdit != null)
            IconButton(
              icon: const Icon(Icons.edit, size: 20),
              tooltip: 'Edit parameter',
              onPressed: onEdit,
            ),
          if (onDelete != null)
            IconButton(
              icon: const Icon(Icons.delete, size: 20),
              tooltip: 'Delete parameter',
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}

class _ParameterEditor extends StatefulWidget {
  const _ParameterEditor({this.initial, required this.reservedKeys});

  final PayloadParameter? initial;
  final Set<String> reservedKeys;

  @override
  State<_ParameterEditor> createState() => _ParameterEditorState();
}

class _ParameterEditorState extends State<_ParameterEditor> {
  final _formKey = GlobalKey<FormState>();

  late final _keyCtrl = TextEditingController(text: widget.initial?.key);
  late final _labelCtrl = TextEditingController(text: widget.initial?.label);
  late final _defaultCtrl = TextEditingController(
    text: widget.initial?.defaultValue,
  );
  late final _descCtrl = TextEditingController(
    text: widget.initial?.description,
  );
  late String _type = widget.initial?.type ?? 'text';
  late bool _required = widget.initial?.required ?? false;

  @override
  void dispose() {
    _keyCtrl.dispose();
    _labelCtrl.dispose();
    _defaultCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      PayloadParameter(
        key: _keyCtrl.text.trim(),
        label: _labelCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        type: _type,
        defaultValue: _defaultCtrl.text.trim(),
        required: _required,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final types = <String, String>{
      'text': 'Text',
      'number': 'Number',
      'url': 'URL',
    };
    final initialType = widget.initial?.type;
    if (initialType != null) {
      types.putIfAbsent(
        initialType,
        () => initialType.isEmpty ? 'Unspecified' : initialType,
      );
    }

    return ConfigurationPage(
      title: widget.initial == null ? 'Add parameter' : 'Edit parameter',
      actionLabel: 'Save',
      onAction: _save,
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _keyCtrl,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Key',
                helperText: 'Use in the script as {{KEY}}.',
                helperMaxLines: 2,
                errorMaxLines: 3,
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                final key = value?.trim() ?? '';
                if (key.isEmpty) return 'Enter a key';
                if (widget.reservedKeys.contains(key) &&
                    key != widget.initial?.key) {
                  return 'This key is already in use';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _labelCtrl,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Label',
                helperText: 'Shown when configuring this payload.',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  (value?.trim().isEmpty ?? true) ? 'Enter a label' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _type,
              isExpanded: true,
              items: [
                for (final entry in types.entries)
                  DropdownMenuItem(
                    value: entry.key,
                    child: Text(
                      entry.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _type = value);
              },
              decoration: const InputDecoration(
                labelText: 'Type',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _required,
              title: const Text('Required'),
              onChanged: (value) => setState(() => _required = value),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _defaultCtrl,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Default value',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descCtrl,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Description',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
