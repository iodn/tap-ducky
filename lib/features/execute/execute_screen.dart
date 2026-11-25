import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/router.dart';
import '../../data/models/execution_group.dart';
import '../../data/models/payload.dart';
import '../../data/services/ducky_script.dart';
import '../../data/services/ducky_script_validator.dart';
import '../../state/controllers/advanced_settings_controller.dart';
import '../../state/controllers/app_settings_controller.dart';
import '../../state/controllers/execution_controller.dart';
import '../../state/controllers/hid_status_controller.dart';
import '../../state/controllers/logs_controller.dart';
import '../../state/controllers/payloads_controller.dart';
import '../../state/controllers/selection_controller.dart';
import '../../state/providers.dart';
import '../../widgets/empty_state.dart';

class ExecuteScreen extends ConsumerStatefulWidget {
  const ExecuteScreen({super.key});

  @override
  ConsumerState<ExecuteScreen> createState() => _ExecuteScreenState();
}

class _ExecuteScreenState extends ConsumerState<ExecuteScreen> with SingleTickerProviderStateMixin {
  final _rawCtrl = TextEditingController();
  final Map<String, TextEditingController> _paramCtrls = {};
  late TabController _tabController;
  final _validator = DuckyScriptValidator();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _rawCtrl.dispose();
    _tabController.dispose();
    for (final c in _paramCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final payloadsAsync = ref.watch(payloadsControllerProvider);
    final selectedId = ref.watch(selectedPayloadIdProvider);
    final hid = ref.watch(hidStatusControllerProvider);
    final exec = ref.watch(executionControllerProvider);
    final logsAsync = ref.watch(logsControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Execute'),
        actions: [
          if (exec.isRunning)
            IconButton(
              tooltip: 'Panic Stop',
              onPressed: () => ref.read(executionControllerProvider.notifier).panicStop(),
              icon: const Icon(Icons.warning_amber_rounded),
              color: Theme.of(context).colorScheme.error,
            ),
          logsAsync.when(
            data: (logs) {
              final groups = ExecutionGroup.fromLogs(logs);
              final recent24h = ExecutionGroup.countRecent(groups, const Duration(hours: 24));
              return Badge(
                label: Text('$recent24h'),
                isLabelVisible: recent24h > 0,
                child: IconButton(
                  tooltip: 'Execution history',
                  onPressed: () => context.push(const ExecutionHistoryRoute().location),
                  icon: const Icon(Icons.history),
                ),
              );
            },
            loading: () => IconButton(
              tooltip: 'Execution history',
              onPressed: () => context.push(const ExecutionHistoryRoute().location),
              icon: const Icon(Icons.history),
            ),
            error: (_, __) => IconButton(
              tooltip: 'Execution history',
              onPressed: () => context.push(const ExecutionHistoryRoute().location),
              icon: const Icon(Icons.history),
            ),
          ),
          IconButton(
            tooltip: 'Logs',
            onPressed: () => context.push(const LogsRoute().location),
            icon: const Icon(Icons.list_alt),
          ),
          IconButton(
            tooltip: 'Device',
            onPressed: () => context.push(const DeviceRoute().location),
            icon: const Icon(Icons.phone_android),
          ),
        ],
      ),
      body: payloadsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 64, color: Theme.of(context).colorScheme.error),
                const SizedBox(height: 16),
                Text('Failed to load payloads', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('$e', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
        data: (payloads) {
          if (payloads.isEmpty) {
            return EmptyState(
              title: 'No payloads available',
              subtitle: 'Create or import a payload first.',
              icon: Icons.inventory_2_outlined,
              action: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => context.go('${const PayloadsRoute().location}/new'),
                      icon: const Icon(Icons.add),
                      label: const Text('Create payload'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => context.go(const PayloadsStoreRoute().location),
                      icon: const Icon(Icons.cloud_download),
                      label: const Text('Import from GitHub Store'),
                    ),
                  ),
                ],
              ),
            );
          }

          final selected = _resolveSelected(payloads, selectedId);
          if (selected == null) {
            ref.read(selectedPayloadIdProvider.notifier).state = payloads.first.id;
          } else {
            _syncParamControllers(selected);
          }

          final payload = selected ?? payloads.first;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _PayloadSelectionCard(
                payloads: payloads,
                selectedPayload: payload,
                onChanged: (id) => ref.read(selectedPayloadIdProvider.notifier).state = id,
                onEdit: () => context.go('${const PayloadsRoute().location}/${payload.id}/edit'),
              ),
              const SizedBox(height: 16),
              if (payload.parameters.isNotEmpty) ...[
                _ParametersCard(payload: payload, controllers: _paramCtrls),
                const SizedBox(height: 16),
              ],
              ListenableBuilder(
                listenable: Listenable.merge(_paramCtrls.values),
                builder: (context, _) {
                  final params = _collectParams(payload);
                  final missing = payload.parameters.any(
                    (p) => p.required && (params[p.key]?.trim().isEmpty ?? true),
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ExecutionControlCard(
                        exec: exec,
                        hid: hid,
                        missingParameters: missing,
                        onRun: () => ref.read(executionControllerProvider.notifier).runPayload(payload, params),
                        onStop: () => ref.read(executionControllerProvider.notifier).stop(),
                      ),
                      const SizedBox(height: 16),
                      _ExecutionSpeedCard(
                        script: missing ? null : DuckyScript.resolvePlaceholders(payload.script, params),
                        validator: _validator,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              _ConsoleTabs(
                tabController: _tabController,
                rawController: _rawCtrl,
                exec: exec,
                onSendCommand: (cmd) async {
                  await ref.read(executionControllerProvider.notifier).sendRawCommand(cmd);
                  _rawCtrl.clear();
                  setState(() {});
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Payload? _resolveSelected(List<Payload> payloads, String? selectedId) {
    final id = selectedId ?? payloads.first.id;
    for (final p in payloads) {
      if (p.id == id) return p;
    }
    return null;
  }

  void _syncParamControllers(Payload payload) {
    final keys = payload.parameters.map((e) => e.key).toSet();
    final toRemove = _paramCtrls.keys.where((k) => !keys.contains(k)).toList();
    for (final k in toRemove) {
      _paramCtrls.remove(k)?.dispose();
    }
    for (final p in payload.parameters) {
      _paramCtrls.putIfAbsent(p.key, () => TextEditingController(text: p.defaultValue));
    }
  }

  Map<String, String> _collectParams(Payload payload) {
    final out = <String, String>{};
    for (final p in payload.parameters) {
      final v = _paramCtrls[p.key]?.text ?? p.defaultValue;
      out[p.key] = v;
    }
    return out;
  }
}

class _ExecutionSpeedCard extends ConsumerStatefulWidget {
  const _ExecutionSpeedCard({
    required this.script,
    required this.validator,
  });

  final String? script;
  final DuckyScriptValidator validator;

  @override
  ConsumerState<_ExecutionSpeedCard> createState() => _ExecutionSpeedCardState();
}

class _ExecutionSpeedCardState extends ConsumerState<_ExecutionSpeedCard> {
  Timer? _estimateDebounce;
  int? _engineEstimateMs;
  Object? _estimateKey;
  int _estimateToken = 0;

  @override
  void dispose() {
    _estimateDebounce?.cancel();
    super.dispose();
  }

  void _refreshEngineEstimate(String? script, double multiplier, Object key) {
    if (key == _estimateKey) return;
    _estimateKey = key;
    _engineEstimateMs = null;
    _estimateDebounce?.cancel();
    final token = ++_estimateToken;
    if (script == null) return;
    _estimateDebounce = Timer(const Duration(milliseconds: 400), () async {
      final service = ref.read(platformGadgetServiceProvider);
      try {
        final ms = await service.estimateDuckyScriptDurationMs(
          script: script,
          delayMultiplier: multiplier,
        );
        if (!mounted || token != _estimateToken) return;
        setState(() => _engineEstimateMs = ms);
      } catch (_) {} // The validator provides a rough estimate if Android cannot.
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final settingsAsync = ref.watch(appSettingsControllerProvider);
    final layout = ref.watch(advancedSettingsControllerProvider).value?.keyboardLayoutBackendId;

    return settingsAsync.when(
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (settings) {
        final currentMultiplier = settings.delayMultiplier;
        final script = widget.script;
        final candidate = script == null || RegExp(r'\$\{[\w-]+\}').hasMatch(script)
            ? null
            : script;
        final validation = candidate == null ? null : widget.validator.validate(candidate, delayMultiplier: currentMultiplier);
        final estimateScript = validation?.hasErrors == false ? candidate : null;
        _refreshEngineEstimate(estimateScript, currentMultiplier, (
          estimateScript, currentMultiplier, settings.typingSpeedFactor,
          settings.unicodeFallbackMode, settings.riskyFastMode, layout,
        ));
        final estimateMs = _engineEstimateMs ?? (estimateScript == null ? null : validation?.estimatedDurationMs);

        final speed = '${currentMultiplier.toStringAsFixed(2)}×';
        final estimate = estimateMs == null
            ? ''
            : ' · ~${_formatDuration(estimateMs)}';

        return Card(
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            leading: Icon(Icons.speed, color: cs.primary),
            title: const Text('Script speed'),
            subtitle: Text('$speed$estimate'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _SpeedPresetChip(
                    label: 'Ultra',
                    multiplier: 0.1,
                    icon: Icons.bolt,
                    currentMultiplier: currentMultiplier,
                    onTap: () => ref.read(appSettingsControllerProvider.notifier).setDelayMultiplier(0.1),
                    tooltip: 'Short pauses may not give the host app enough time to respond.',
                  ),
                  _SpeedPresetChip(
                    label: 'Fast',
                    multiplier: 0.5,
                    icon: Icons.fast_forward,
                    currentMultiplier: currentMultiplier,
                    onTap: () => ref.read(appSettingsControllerProvider.notifier).setDelayMultiplier(0.5),
                  ),
                  _SpeedPresetChip(
                    label: 'Normal',
                    multiplier: 1.0,
                    icon: Icons.play_arrow,
                    currentMultiplier: currentMultiplier,
                    onTap: () => ref.read(appSettingsControllerProvider.notifier).setDelayMultiplier(1.0),
                  ),
                  _SpeedPresetChip(
                    label: 'Slow',
                    multiplier: 2.0,
                    icon: Icons.speed,
                    currentMultiplier: currentMultiplier,
                    onTap: () => ref.read(appSettingsControllerProvider.notifier).setDelayMultiplier(2.0),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Slider(
                value: currentMultiplier.clamp(0.1, 4.0),
                min: 0.1,
                max: 4.0,
                divisions: 39,
                label: speed,
                semanticFormatterCallback: (value) => '${value.toStringAsFixed(2)}× script delay',
                onChanged: (value) =>
                    ref.read(appSettingsControllerProvider.notifier).setDelayMultiplier(value),
              ),
              Text(
                estimateMs == null
                    ? '0.5× halves script pauses. Key timing is in Settings.'
                    : 'Estimate excludes host and scheduled waits. Key timing is in Settings.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDuration(int ms) {
    final seconds = ms / 1000;
    if (seconds < 1) return '${ms}ms';
    if (seconds < 60) return '${seconds.toStringAsFixed(1)}s';
    final minutes = seconds ~/ 60;
    final remainingSeconds = (seconds % 60).round();
    return '${minutes}m ${remainingSeconds}s';
  }
}

class _SpeedPresetChip extends StatelessWidget {
  const _SpeedPresetChip({
    required this.label,
    required this.multiplier,
    required this.icon,
    required this.currentMultiplier,
    required this.onTap,
    this.tooltip,
  });

  final String label;
  final double multiplier;
  final IconData icon;
  final double currentMultiplier;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = (currentMultiplier - multiplier).abs() < 0.01;

    final chip = ChoiceChip(
      selected: isSelected,
      onSelected: (_) => onTap(),
      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: isSelected ? cs.onPrimaryContainer : cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '$label ${multiplier.toStringAsFixed(1)}×',
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
      selectedColor: cs.primaryContainer,
      backgroundColor: cs.surfaceContainerHighest,
      side: BorderSide(color: isSelected ? cs.primary : cs.outlineVariant),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
    return tooltip == null ? chip : Tooltip(message: tooltip!, child: chip);
  }
}

class _PayloadSelectionCard extends StatelessWidget {
  const _PayloadSelectionCard({
    required this.payloads,
    required this.selectedPayload,
    required this.onChanged,
    required this.onEdit,
  });

  final List<Payload> payloads;
  final Payload selectedPayload;
  final ValueChanged<String> onChanged;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey(selectedPayload.id),
                initialValue: selectedPayload.id,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Payload',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                items: payloads
                    .map((payload) => DropdownMenuItem<String>(
                          value: payload.id,
                          child: Text(payload.name, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (id) {
                  if (id != null) onChanged(id);
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Edit payload',
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEdit,
            ),
          ],
        ),
      ),
    );
  }
}

class _ParametersCard extends StatelessWidget {
  const _ParametersCard({
    required this.payload,
    required this.controllers,
  });

  final Payload payload;
  final Map<String, TextEditingController> controllers;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Parameters',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (int i = 0; i < payload.parameters.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _ParameterField(
                parameter: payload.parameters[i],
                controller: controllers[payload.parameters[i].key]!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ParameterField extends StatelessWidget {
  const _ParameterField({
    required this.parameter,
    required this.controller,
  });

  final parameter;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: parameter.label,
        hintText: parameter.defaultValue,
        helperText: parameter.description.isNotEmpty ? parameter.description : null,
        border: const OutlineInputBorder(),
        suffixIcon: parameter.required ? const Icon(Icons.star, size: 16, color: Colors.red) : null,
      ),
    );
  }
}

class _ExecutionControlCard extends StatelessWidget {
  const _ExecutionControlCard({
    required this.exec,
    required this.hid,
    required this.onRun,
    required this.onStop,
    required this.missingParameters,
  });

  final ExecutionState exec;
  final HidStatus hid;
  final VoidCallback onRun;
  final VoidCallback onStop;
  final bool missingParameters;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final blockReason = _blockReason();
    final status = exec.isRunning
        ? exec.status
        : blockReason ??
            (missingParameters
                ? 'Fill in required parameters'
                : hid.deviceConnected
                    ? null
                    : 'Waiting for USB host');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (exec.isRunning) ...[
              LinearProgressIndicator(
                value: exec.progress,
                semanticsLabel: 'Approximate command progress',
              ),
              const SizedBox(height: 12),
            ],
            if (status != null) ...[
              Text(status, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 12),
            ],
            if (exec.isRunning)
              FilledButton.icon(
                onPressed: onStop,
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
                style: FilledButton.styleFrom(
                  backgroundColor: cs.error,
                  foregroundColor: cs.onError,
                ),
              )
            else
              FilledButton.icon(
                onPressed: blockReason == null ? onRun : null,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Run Payload'),
              ),
          ],
        ),
      ),
    );
  }

  String? _blockReason() {
    if (!hid.rootAvailable) return 'Root access required';
    if (!hid.hidSupported) return 'USB gadget support required';
    if (hid.usbRestoring) return hid.message ?? 'Restoring USB…';
    if (!hid.sessionArmed) return 'Arm a session from Dashboard';
    if (!hid.gadgetBound) return hid.message ?? 'Preparing USB HID…';
    return null;
  }
}

class _ConsoleTabs extends StatelessWidget {
  const _ConsoleTabs({
    required this.tabController,
    required this.rawController,
    required this.exec,
    required this.onSendCommand,
  });

  final TabController tabController;
  final TextEditingController rawController;
  final ExecutionState exec;
  final ValueChanged<String> onSendCommand;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          TabBar(
            controller: tabController,
            tabs: const [
              Tab(text: 'Console', icon: Icon(Icons.terminal, size: 18)),
              Tab(text: 'Events', icon: Icon(Icons.list, size: 18)),
            ],
          ),
          SizedBox(
            height: 350,
            child: TabBarView(
              controller: tabController,
              children: [
                _ConsoleTab(
                  controller: rawController,
                  onSend: onSendCommand,
                ),
                _EventsTab(exec: exec),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsoleTab extends ConsumerStatefulWidget {
  const _ConsoleTab({
    required this.controller,
    required this.onSend,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSend;

  @override
  ConsumerState<_ConsoleTab> createState() => _ConsoleTabState();
}

class _ConsoleTabState extends ConsumerState<_ConsoleTab> {
  String? _selectedPreset;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final advSettingsAsync = ref.watch(advancedSettingsControllerProvider);

    return SingleChildScrollView(
      primary: false,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Send raw HID commands',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              TextButton.icon(
                onPressed: () => _showSavePresetDialog(context),
                icon: const Icon(Icons.bookmark_add, size: 16),
                label: const Text('Save as Preset'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          advSettingsAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (settings) {
              if (settings.commandPresets.isEmpty) {
                return const SizedBox.shrink();
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quick Commands',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: cs.outlineVariant),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedPreset,
                        isExpanded: true,
                        hint: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              Icon(Icons.code, size: 16, color: cs.onSurfaceVariant),
                              const SizedBox(width: 8),
                              Text(
                                'Select a preset...',
                                style: TextStyle(color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        items: [
                          for (int i = 0; i < settings.commandPresets.length; i++)
                            DropdownMenuItem<String>(
                              value: i.toString(),
                              child: Tooltip(
                                message: settings.commandPresets[i],
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Row(
                                    children: [
                                      Icon(Icons.code, size: 16, color: cs.primary),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _truncatePreset(settings.commandPresets[i], 40),
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            final index = int.parse(value);
                            widget.controller.text = settings.commandPresets[index];
                            setState(() => _selectedPreset = null);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              );
            },
          ),
          TextField(
            controller: widget.controller,
            decoration: InputDecoration(
              labelText: 'Command',
              hintText: 'STRING hello | ENTER | DELAY 200',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                onPressed: () {
                  final cmd = widget.controller.text.trim();
                  if (cmd.isNotEmpty) {
                    widget.onSend(cmd);
                  }
                },
                icon: const Icon(Icons.send),
                tooltip: 'Send command',
              ),
            ),
            maxLines: 3,
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) {
                widget.onSend(v.trim());
              }
            },
          ),
          const SizedBox(height: 12),
          Text(
            'Examples: STRING text, ENTER, DELAY 500, GUI r',
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  String _truncatePreset(String preset, int maxLength) {
    final singleLine = preset.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (singleLine.length <= maxLength) return singleLine;
    return '${singleLine.substring(0, maxLength - 1)}…';
  }

  Future<void> _showSavePresetDialog(BuildContext context) async {
    final currentText = widget.controller.text.trim();
    if (currentText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a command first before saving as preset'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final nameCtrl = TextEditingController();
    final presetCtrl = TextEditingController(text: currentText);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save as Preset'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Preset Name (optional)',
                  hintText: 'e.g., Open Notepad',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Command:',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: presetCtrl,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  filled: true,
                ),
                maxLines: 6,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == true && context.mounted) {
      final presetText = presetCtrl.text.trim();
      if (presetText.isNotEmpty) {
        await ref.read(advancedSettingsControllerProvider.notifier).addCommandPreset(presetText);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Preset saved successfully'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }
}

class _EventsTab extends StatelessWidget {
  const _EventsTab({required this.exec});

  final ExecutionState exec;

  @override
  Widget build(BuildContext context) {
    if (exec.tail.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.article_outlined, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            const Text('No events yet'),
            const SizedBox(height: 4),
            Text(
              'Run a payload to see execution events',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: exec.tail.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final e = exec.tail[i];
        return ListTile(
          dense: true,
          leading: Icon(_iconFor(e.level, e.success), size: 20),
          title: Text(e.message, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            _formatTime(e.timestamp),
            style: const TextStyle(fontSize: 11),
          ),
        );
      },
    );
  }

  IconData _iconFor(String level, bool success) {
    if (!success) return Icons.error_outline;
    switch (level) {
      case 'debug':
        return Icons.bug_report_outlined;
      case 'warn':
        return Icons.warning_amber_outlined;
      case 'error':
        return Icons.error_outline;
      default:
        return Icons.info_outline;
    }
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
