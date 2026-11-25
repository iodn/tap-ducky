import 'dart:async';

import 'package:flutter/services.dart' show MissingPluginException;
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
import '../../data/storage/prefs_storage.dart';
import '../../state/controllers/advanced_settings_controller.dart';
import '../../state/controllers/app_settings_controller.dart';
import '../../state/controllers/payloads_controller.dart';
import '../../state/providers.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/configuration_page.dart';
import '../../widgets/ducky_script_text.dart';
import '../settings/widgets/local_draft_settings.dart';
import 'local_draft_dialog.dart';
import 'script_line_gutter.dart';

const _uuid = Uuid();

class PayloadEditorScreen extends ConsumerStatefulWidget {
  const PayloadEditorScreen({super.key, this.payloadId});

  final String? payloadId;

  @override
  ConsumerState<PayloadEditorScreen> createState() =>
      _PayloadEditorScreenState();
}

class _PayloadEditorScreenState extends ConsumerState<PayloadEditorScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabs;
  final _scriptField = GlobalKey();
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
  PrefsStorage? _draftStorage;
  Future<void> _draftWrites = Future.value();
  Timer? _draftDebounce;
  Object? _pendingDraftUndo;

  final _validator = DuckyScriptValidator();
  ValidationResult _validationResult = ValidationResult.empty();
  Timer? _validationDebounce;
  Timer? _estimateDebounce;
  bool _showValidation = false;
  int? _engineEstimateMs;
  ValidationIssue? _engineIssue;
  String? _nativeValidationScript;
  Future<ValidationIssue?>? _nativeValidation;
  int _estimateRevision = 0;
  String _observedScript = '';
  List<int> _scriptLines = const [0];

  String get _draftKey =>
      'tapducky.editor.draft.${widget.payloadId ?? 'new'}.v1';

  double _currentDelayMultiplier() {
    final settings = ref.read(appSettingsControllerProvider).value;
    final m = settings?.delayMultiplier;
    if (m == null || m <= 0) return 1.0;
    return m;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabs = TabController(length: 3, vsync: this)..addListener(_changeSection);
    _scriptCtrl.addListener(_onScriptChanged);
    ref.listenManual(
      appSettingsControllerProvider.select((state) {
        final settings = state.value;
        return (
          settings?.delayMultiplier,
          settings?.typingSpeedFactor,
          settings?.unicodeFallbackMode,
          settings?.riskyFastMode,
        );
      }),
      (_, _) => _refreshEstimateForSettings(),
    );
    ref.listenManual(
      advancedSettingsControllerProvider.select(
        (state) => state.value?.keyboardLayoutBackendId,
      ),
      (_, _) => _refreshEstimateForSettings(),
    );
    if (widget.payloadId != null) {
      ref.listenManual(
        payloadsControllerProvider,
        (_, next) => _loadPayload(next.value),
        fireImmediately: true,
      );
    } else {
      unawaited(_restoreDraft());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flushDraft();
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _flushDraft();
  }

  Map<String, dynamic> _snapshotEditor() => {
    'name': _nameCtrl.text,
    'description': _descCtrl.text,
    'tags': _tagsCtrl.text,
    'script': _scriptCtrl.text,
    'parameters': _params.map((parameter) => parameter.toJson()).toList(),
  };

  void _applySnapshot(Map<String, dynamic> draft) {
    _nameCtrl.text = draft['name']?.toString() ?? '';
    _descCtrl.text = draft['description']?.toString() ?? '';
    _tagsCtrl.text = draft['tags']?.toString() ?? '';
    final script = draft['script']?.toString() ?? '';
    _observedScript = script;
    _scriptLines = scriptLineOffsets(script);
    _scriptCtrl.text = script;
    final parameters = draft['parameters'];
    _params
      ..clear()
      ..addAll(
        parameters is List
            ? parameters.whereType<Map>().map(
                (json) =>
                    PayloadParameter.fromJson(json.cast<String, dynamic>()),
              )
            : const [],
      );
    _nameError = null;
    _scriptError = null;
  }

  Future<void> _restoreDraft() async {
    Map<String, dynamic>? draft;
    try {
      final storage = await ref.read(prefsStorageProvider.future);
      if (!mounted) return;
      _draftStorage = storage;
      if (!_isBuiltin) draft = storage.getJsonMap(_draftKey);
    } catch (_) {
      // The editor can still be used when local storage is unavailable.
    }
    if (!mounted) return;
    if (_hasChanges) {
      _flushDraft();
      return;
    }
    final snapshot = draft;
    if (snapshot == null) return;
    setState(() {
      _applySnapshot(snapshot);
      _hasChanges = true;
    });
    _validateAndRequestEstimate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unsaved draft restored')));
    });
  }

  void _recordDraftChange() {
    _pendingDraftUndo = null;
    if (!_hasChanges) setState(() => _hasChanges = true);
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(milliseconds: 300), _flushDraft);
  }

  void _flushDraft() {
    _draftDebounce?.cancel();
    if (!_hasChanges) return;
    unawaited(_writeDraft(_snapshotEditor()));
  }

  Future<void> _writeDraft(Map<String, dynamic>? draft) {
    final storage = _draftStorage;
    if (storage == null) return Future.value();
    final key = _draftKey;
    return _draftWrites = _draftWrites.then((_) async {
      try {
        if (draft == null) {
          await storage.remove(key);
        } else {
          await storage.setJsonMap(key, draft);
        }
      } catch (_) {
        // Keep saved payloads independent of draft storage.
      }
    });
  }

  Future<void> _clearDraft() {
    _draftDebounce?.cancel();
    _hasChanges = false;
    return _writeDraft(null);
  }

  void _onScriptChanged() {
    if (_scriptCtrl.text == _observedScript) return;
    _observedScript = _scriptCtrl.text;
    _scriptLines = scriptLineOffsets(_observedScript);
    _estimateRevision++;
    _estimateDebounce?.cancel();
    setState(() {
      _scriptError = null;
      _engineEstimateMs = null;
      _engineIssue = null;
    });
    _recordDraftChange();
    _validationDebounce?.cancel();
    _validationDebounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _validateAndRequestEstimate();
    });
  }

  void _refreshEstimateForSettings() {
    if (_scriptCtrl.text.trim().isEmpty) return;
    _validationDebounce?.cancel();
    _validateAndRequestEstimate();
  }

  void _validateAndRequestEstimate() {
    final script = _scriptCtrl.text;
    setState(() {
      _engineEstimateMs = null;
      _engineIssue = null;
      _validationResult = _validator.validate(
        script,
        delayMultiplier: _currentDelayMultiplier(),
      );
      _showValidation = script.trim().isNotEmpty;
    });
    _requestEngineEstimate(script);
    unawaited(_updateNativeValidation(script));
  }

  Future<ValidationIssue?> _getNativeValidation(String script) {
    if (DuckyScript.hasPlaceholders(script)) return Future.value();
    if (_nativeValidationScript == script && _nativeValidation != null) {
      return _nativeValidation!;
    }
    _nativeValidationScript = script;
    return _nativeValidation = _parseWithAndroid(script);
  }

  Future<ValidationIssue?> _parseWithAndroid(String script) async {
    try {
      return await ref
          .read(platformGadgetServiceProvider)
          .validateDuckyScript(script);
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> _updateNativeValidation(String script) async {
    if (script.trim().isEmpty || _validationResult.hasErrors) return;
    final revision = _estimateRevision;
    try {
      final issue = await _getNativeValidation(script);
      if (mounted &&
          revision == _estimateRevision &&
          _scriptCtrl.text == script) {
        setState(() => _engineIssue = issue);
      }
    } catch (_) {
      if (mounted && _nativeValidationScript == script)
        _nativeValidation = null;
    }
  }

  Future<void> _showLocalDraft() async {
    final application = await showConfigurationPage<DraftApplication>(
      context,
      (_) => LocalDraftDialog(
        service: ref.read(localDraftsServiceProvider),
        editingExisting: widget.payloadId != null,
        replacing: [
          _nameCtrl,
          _descCtrl,
          _tagsCtrl,
          _scriptCtrl,
        ].any((controller) => controller.text.isNotEmpty),
      ),
    );
    if (!mounted || application == null) return;
    final previous = _snapshotEditor();
    final hadChanges = _hasChanges;
    final draft = application.draft;
    setState(() {
      _applySnapshot({
        ...previous,
        if (!application.scriptOnly) ...{
          'name': draft.title,
          'description': draft.description,
          'tags': draft.tags.join(', '),
        },
        'script': draft.script,
      });
    });
    _recordDraftChange();
    _validateAndRequestEstimate();
    final undo = _pendingDraftUndo = Object();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Draft applied'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              if (!mounted || _pendingDraftUndo != undo || _saving) return;
              setState(() {
                _applySnapshot(previous);
                _hasChanges = hadChanges;
              });
              _recordDraftChange();
              if (!hadChanges) unawaited(_clearDraft());
              _validateAndRequestEstimate();
            },
          ),
        ),
      );
  }

  void _loadPayload(List<Payload>? items) {
    if (_editReady || items == null) return;
    final found = items
        .where((payload) => payload.id == widget.payloadId)
        .firstOrNull;
    if (found == null) return;

    setState(() {
      _observedScript = found.script;
      _scriptLines = scriptLineOffsets(found.script);
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
    unawaited(_updateNativeValidation(found.script));
    unawaited(_restoreDraft());
  }

  void _requestEngineEstimate(String script) {
    final revision = ++_estimateRevision;
    _estimateDebounce?.cancel();
    if (script.trim().isEmpty ||
        _validationResult.hasErrors ||
        DuckyScript.hasPlaceholders(script))
      return;
    final mul = _currentDelayMultiplier();
    final layout = ref
        .read(advancedSettingsControllerProvider)
        .value
        ?.keyboardLayoutBackendId;
    _estimateDebounce = Timer(const Duration(milliseconds: 600), () async {
      if (!mounted || revision != _estimateRevision || _engineIssue != null) {
        return;
      }
      final service = ref.read(platformGadgetServiceProvider);
      try {
        final ms = await service.estimateDuckyScriptDurationMs(
          script: script,
          delayMultiplier: mul,
          keyboardLayoutId: layout,
        );
        if (!mounted || revision != _estimateRevision) return;
        setState(() => _engineEstimateMs = ms);
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
      canPop: !_hasChanges && !_saving,
      onPopInvoked: (didPop) async {
        if (didPop || _saving) return;
        final ok = await showConfirmDialog(
          context,
          title: 'Discard changes?',
          message: 'You have unsaved changes. Discard them?',
          confirmLabel: 'Discard',
          dangerous: true,
        );
        if (ok && context.mounted) {
          await _clearDraft();
          if (context.mounted) Navigator.of(context).pop();
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
                enabled: !_saving,
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
          child: AbsorbPointer(
            absorbing: _saving,
            child: switch (_section) {
              0 => _scriptSection(context),
              1 => _detailsSection(),
              _ => _parametersSection(),
            },
          ),
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
    final issueCount =
        _validationResult.issues.length + (_engineIssue == null ? 0 : 1);
    final textScaler = MediaQuery.textScalerOf(context);
    final gutterWidth =
        14 + textScaler.scale(12) * _scriptLines.length.toString().length;
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
                          color:
                              _validationResult.hasErrors ||
                                  _engineIssue != null
                              ? theme.colorScheme.error
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 4),
            Expanded(
              child: CustomPaint(
                key: _scriptField,
                foregroundPainter: ScriptLineGutter(
                  editor: _scriptField,
                  offsets: _scriptLines,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textScaler: textScaler,
                  scrollController: _scriptScroll,
                ),
                child: TextFormField(
                  key: const ValueKey('payload-script-editor'),
                  controller: _scriptCtrl,
                  focusNode: _scriptFocus,
                  scrollController: _scriptScroll,
                  expands: true,
                  maxLines: null,
                  textDirection: TextDirection.ltr,
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
                    contentPadding: EdgeInsets.fromLTRB(
                      gutterWidth,
                      12,
                      12,
                      12,
                    ),
                  ),
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
          onChanged: (_) {
            if (_nameError != null) setState(() => _nameError = null);
            _recordDraftChange();
          },
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
          onChanged: (_) => _recordDraftChange(),
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
          onChanged: (_) => _recordDraftChange(),
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

  Future<void> _showValidationDialog(BuildContext context) async {
    if (_validationDebounce?.isActive == true) {
      _validationDebounce?.cancel();
      _validateAndRequestEstimate();
    }
    final issue = _engineIssue;
    final result = issue == null
        ? _validationResult
        : ValidationResult(
            issues: [..._validationResult.issues, issue],
            commandCount: _validationResult.commandCount,
            estimatedDurationMs: _validationResult.estimatedDurationMs,
            totalDelayMs: _validationResult.totalDelayMs,
            hasErrors: true,
            hasWarnings: _validationResult.hasWarnings,
          );
    final line = await showConfigurationPage<int>(
      context,
      (_) => _ValidationDialog(
        result: result,
        engineEstimateMs: _engineEstimateMs,
        formatDuration: _formatDuration,
        hasParameters: DuckyScript.hasPlaceholders(_scriptCtrl.text),
      ),
    );
    if (mounted && line != null) _jumpToLine(line);
  }

  void _jumpToLine(int line) {
    if (line < 1 || line > _scriptLines.length) return;
    final script = _scriptCtrl.text;
    final start = _scriptLines[line - 1];
    var end = line < _scriptLines.length ? _scriptLines[line] : script.length;
    while (end > start && [0x0A, 0x0D].contains(script.codeUnitAt(end - 1))) {
      end--;
    }
    _tabs.animateTo(0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _scriptCtrl.text != script) return;
      _scriptFocus.requestFocus();
      _scriptCtrl.selection = TextSelection(
        baseOffset: start,
        extentOffset: end,
      );
      findScriptEditable(
        _scriptField.currentContext,
      )?.bringIntoView(TextPosition(offset: start));
    });
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
    });
    _recordDraftChange();
  }

  void _deleteParameter(int index) {
    setState(() {
      _params.removeAt(index);
    });
    _recordDraftChange();
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
      unawaited(_showValidationDialog(context));
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

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _saving = true);
    var syntaxChecked = false;
    try {
      final issue = await _getNativeValidation(script);
      syntaxChecked = true;
      if (!mounted) return;
      if (issue != null) {
        setState(() => _engineIssue = issue);
        _tabs.animateTo(0);
        unawaited(_showValidationDialog(context));
        return;
      }
      if (widget.payloadId == null) {
        await ref.read(payloadsControllerProvider.notifier).create(payload);
      } else {
        await ref
            .read(payloadsControllerProvider.notifier)
            .updatePayload(payload);
      }
      await _clearDraft();
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
      if (!syntaxChecked) _nativeValidation = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              syntaxChecked
                  ? 'Could not save the payload'
                  : 'Could not check script syntax. Try again.',
            ),
          ),
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
    await _clearDraft();

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
    r'$_RANDOM_UINT16': 'Returns a random integer from 0 to 65,535, independent of the configured range.',
    r'$_RANDOM_ASCII_LETTER': 'Returns the ASCII number for a random letter A–Z or a–z.',
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
    required this.hasParameters,
  });

  final ValidationResult result;
  final int? engineEstimateMs;
  final String Function(int) formatDuration;
  final bool hasParameters;

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
                    if (hasParameters)
                      const Text(
                        'Android checks syntax when parameter values are supplied.',
                      ),
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
      onTap: issue.line > 0 ? () => Navigator.pop(context, issue.line) : null,
      trailing: issue.line > 0 ? const Icon(Icons.chevron_right) : null,
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
