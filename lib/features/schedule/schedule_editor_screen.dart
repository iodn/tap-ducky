import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/payload.dart';
import '../../data/models/scheduled_task.dart';
import '../../state/controllers/payloads_controller.dart';
import '../../state/controllers/scheduler_controller.dart';
import '../../widgets/empty_state.dart';

class ScheduleEditorScreen extends ConsumerStatefulWidget {
  const ScheduleEditorScreen._({super.key, required this.isNew, this.taskId});

  const ScheduleEditorScreen.newTask({Key? key}) : this._(key: key, isNew: true);

  const ScheduleEditorScreen.edit({Key? key, required String taskId})
      : this._(key: key, isNew: false, taskId: taskId);

  final bool isNew;
  final String? taskId;

  @override
  ConsumerState<ScheduleEditorScreen> createState() => _ScheduleEditorScreenState();
}

class _ScheduleEditorScreenState extends ConsumerState<ScheduleEditorScreen> {
  final _name = TextEditingController();
  final _windowStart = TextEditingController();
  final _windowEnd = TextEditingController();

  String _trigger = 'one_time';
  String? _payloadId;
  DateTime? _runAt;
  final Map<String, TextEditingController> _paramCtrls = {};
  bool _loaded = false;

  @override
  void dispose() {
    _name.dispose();
    _windowStart.dispose();
    _windowEnd.dispose();
    for (final c in _paramCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _loadIfNeeded(List<Payload> payloads, SchedulerController ctrl) {
    if (_loaded) return;

    if (!widget.isNew) {
      final t = ctrl.byId(widget.taskId!);
      if (t != null) {
        _name.text = t.name;
        _windowStart.text = t.windowStart ?? '';
        _windowEnd.text = t.windowEnd ?? '';
        _trigger = _normalizeTriggerForEditor(t.trigger);
        _payloadId = t.payloadId;
        _runAt = t.runAt;
        for (final e in t.params.entries) {
          _paramCtrls[e.key] = TextEditingController(text: e.value);
        }
      }
    } else {
      _name.text = 'New schedule';
      _windowStart.text = '';
      _windowEnd.text = '';
      _trigger = 'one_time';
      _payloadId = payloads.isNotEmpty ? payloads.first.id : null;
      _runAt = DateTime.now().add(const Duration(minutes: 5));
    }

    _loaded = true;
  }

  String _normalizeTriggerForEditor(String trigger) {
    if (trigger == 'app_launch') return 'app_foreground';
    return trigger;
  }

  @override
  Widget build(BuildContext context) {
    final payloadsAsync = ref.watch(payloadsControllerProvider);
    final schedulesCtrl = ref.read(schedulerControllerProvider.notifier);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? 'New Schedule' : 'Edit Schedule'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: () async {
                final payloads = payloadsAsync.value ?? const <Payload>[];
                if (_payloadId == null && payloads.isNotEmpty) {
                  _payloadId = payloads.first.id;
                }
                await _save(schedulesCtrl, payloads);
              },
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Save'),
            ),
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
                Icon(Icons.error_outline, size: 64, color: cs.error),
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
            return const EmptyState(
              title: 'No payloads available',
              subtitle: 'Create a payload first, then create a schedule.',
              icon: Icons.inventory_2_outlined,
            );
          }

          _loadIfNeeded(payloads, schedulesCtrl);

          final selectedPayload = _findPayload(payloads, _payloadId) ?? payloads.first;
          _payloadId = selectedPayload.id;
          _syncParamControllers(selectedPayload);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SectionCard(
                icon: Icons.settings,
                title: 'Basic Configuration',
                color: cs.primary,
                children: [
                  TextField(
                    controller: _name,
                    decoration: InputDecoration(
                      labelText: 'Schedule Name',
                      hintText: 'e.g., Morning Routine',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.label),
                      filled: true,
                      fillColor: cs.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _payloadId,
                    decoration: InputDecoration(
                      labelText: 'Payload',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.inventory_2),
                      filled: true,
                      fillColor: cs.surfaceContainerHighest,
                    ),
                    items: payloads
                        .map((p) => DropdownMenuItem(
                              value: p.id,
                              child: Text(p.name, overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _payloadId = v),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SectionCard(
                icon: Icons.flash_on,
                title: 'Trigger Type',
                color: cs.primary,
                children: [
                  _TriggerSelector(
                    value: _trigger,
                    onChanged: (v) => setState(() => _trigger = v),
                  ),
                  const SizedBox(height: 12),
                  _TriggerExplanation(trigger: _trigger),
                ],
              ),
              const SizedBox(height: 16),
              if (_trigger == 'one_time') ...[
                _SectionCard(
                  icon: Icons.event,
                  title: 'Schedule Time',
                  color: cs.secondary,
                  children: [
                    InkWell(
                      onTap: () => _pickDateTime(context),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cs.primary.withOpacity(0.3), width: 2),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: cs.primary,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(Icons.access_time, color: cs.onPrimary, size: 24),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Execution Time',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _runAt == null ? 'Tap to set' : _formatDateTime(_runAt!),
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: cs.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.edit_calendar, color: cs.primary),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              _SectionCard(
                icon: Icons.access_time_filled,
                title: 'Time Window (Optional)',
                color: cs.primary,
                children: [
                  Text(
                    'Restrict execution to specific hours of the day',
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _windowStart,
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: 'Start Time',
                            hintText: '09:00',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.wb_twilight),
                            filled: true,
                            fillColor: cs.surfaceContainerHighest,
                          ),
                          onTap: () => _pickTime(context, _windowStart),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.arrow_forward, color: cs.onSurfaceVariant),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _windowEnd,
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: 'End Time',
                            hintText: '17:00',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.nightlight),
                            filled: true,
                            fillColor: cs.surfaceContainerHighest,
                          ),
                          onTap: () => _pickTime(context, _windowEnd),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (selectedPayload.parameters.isNotEmpty) ...[
                const SizedBox(height: 16),
                _SectionCard(
                  icon: Icons.tune,
                  title: 'Parameter Overrides',
                  color: cs.secondary,
                  children: [
                    for (int i = 0; i < selectedPayload.parameters.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      TextField(
                        controller: _paramCtrls[selectedPayload.parameters[i].key],
                        decoration: InputDecoration(
                          labelText: selectedPayload.parameters[i].label,
                          hintText: selectedPayload.parameters[i].defaultValue,
                          helperText:
                              'Default: ${selectedPayload.parameters[i].defaultValue}',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.code),
                          filled: true,
                          fillColor: cs.surfaceContainerHighest,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              const SizedBox(height: 80),
            ],
          );
        },
      ),
    );
  }

  Payload? _findPayload(List<Payload> items, String? id) {
    if (id == null) return null;
    for (final p in items) {
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

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _pickDateTime(BuildContext context) async {
    final now = DateTime.now();
    final initial = _runAt ?? now.add(const Duration(minutes: 5));

    final date = await showDatePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
      initialDate: initial,
    );

    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );

    if (time == null) return;

    setState(() {
      _runAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _pickTime(BuildContext context, TextEditingController ctrl) async {
    final initial = _parseTime(ctrl.text) ?? TimeOfDay.now();
    final time = await showTimePicker(context: context, initialTime: initial);
    if (time == null) return;
    ctrl.text = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  TimeOfDay? _parseTime(String s) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s.trim());
    if (m == null) return null;
    final hh = int.tryParse(m.group(1)!) ?? -1;
    final mm = int.tryParse(m.group(2)!) ?? -1;
    if (hh < 0 || hh > 23 || mm < 0 || mm > 59) return null;
    return TimeOfDay(hour: hh, minute: mm);
  }

  Future<void> _save(SchedulerController ctrl, List<Payload> payloads) async {
    final payloadId = _payloadId ?? (payloads.isNotEmpty ? payloads.first.id : null);
    if (payloadId == null) return;

    final params = <String, String>{};
    final payload = _findPayload(payloads, payloadId);
    if (payload != null) {
      for (final p in payload.parameters) {
        params[p.key] = _paramCtrls[p.key]?.text ?? p.defaultValue;
      }
    }

    final windowStart = _windowStart.text.trim().isEmpty ? null : _windowStart.text.trim();
    final windowEnd = _windowEnd.text.trim().isEmpty ? null : _windowEnd.text.trim();

    if (widget.isNew) {
      await ctrl.createNew(
        payloadId: payloadId,
        name: _name.text.trim().isEmpty ? 'Schedule' : _name.text.trim(),
        trigger: _trigger,
        runAt: _trigger == 'one_time' ? _runAt : null,
        windowStart: windowStart,
        windowEnd: windowEnd,
        params: params,
      );
    } else {
      final existing = ctrl.byId(widget.taskId!);
      if (existing == null) return;

      final updated = existing.copyWith(
        payloadId: payloadId,
        name: _name.text.trim().isEmpty ? existing.name : _name.text.trim(),
        trigger: _trigger,
        runAt: _trigger == 'one_time' ? _runAt : null,
        windowStart: windowStart,
        windowEnd: windowEnd,
        params: params,
      );
      await ctrl.upsert(updated);
    }

    if (!mounted) return;
    Navigator.of(context).pop();
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.children,
  });

  final IconData icon;
  final String title;
  final Color color;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _TriggerSelector extends StatelessWidget {
  const _TriggerSelector({
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final triggers = [
      _TriggerOption(
        value: 'one_time',
        icon: Icons.event,
        label: 'One-time',
        subtitle: 'Specific date & time',
        color: cs.primary,
      ),
      _TriggerOption(
        value: 'app_cold_start',
        icon: Icons.power_settings_new,
        label: 'App Start',
        subtitle: 'Cold start only',
        color: cs.secondary,
      ),
      _TriggerOption(
        value: 'app_foreground',
        icon: Icons.open_in_new,
        label: 'App Open',
        subtitle: 'Foreground entry',
        color: cs.primary,
      ),
      _TriggerOption(
        value: 'device_connected',
        icon: Icons.usb,
        label: 'Session Armed',
        subtitle: 'USB gadget active',
        color: cs.primary,
      ),
    ];

    return Column(
      children: [
        for (int i = 0; i < triggers.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _TriggerTile(
            option: triggers[i],
            selected: value == triggers[i].value,
            onTap: () => onChanged(triggers[i].value),
          ),
        ],
      ],
    );
  }
}

class _TriggerOption {
  const _TriggerOption({
    required this.value,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
  });

  final String value;
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
}

class _TriggerTile extends StatelessWidget {
  const _TriggerTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _TriggerOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? option.color.withOpacity(0.15) : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? option.color : cs.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: selected ? option.color : cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                option.icon,
                color: selected ? cs.onPrimary : cs.onSurfaceVariant,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.label,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: selected ? option.color : cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    option.subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Radio<bool>(
              value: true,
              groupValue: selected,
              onChanged: (_) => onTap(),
              activeColor: option.color,
            ),
          ],
        ),
      ),
    );
  }
}

class _TriggerExplanation extends StatelessWidget {
  const _TriggerExplanation({required this.trigger});

  final String trigger;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    String title;
    String explanation;
    IconData icon;
    Color color;

    switch (trigger) {
      case 'one_time':
        title = 'One-time Execution';
        explanation =
            'Runs once at the specified date and time (if within the optional time window).';
        icon = Icons.event;
        color = cs.primary;
        break;
      case 'app_cold_start':
        title = 'App Start (Cold Start)';
        explanation =
            'Runs once when TapDucky starts from a cold start. It does not run when returning from background.';
        icon = Icons.power_settings_new;
        color = cs.primary;
        break;
      case 'app_foreground':
        title = 'App Open (Foreground)';
        explanation =
            'Runs when TapDucky comes to the foreground (switching back to the app). It can run multiple times.';
        icon = Icons.open_in_new;
        color = cs.primary;
        break;
      case 'device_connected':
        title = 'Session Armed Trigger';
        explanation =
            'Runs when the HID session is armed (USB gadget binds to UDC). This fires when you tap "Arm Session".';
        icon = Icons.usb;
        color = cs.primary;
        break;
      default:
        title = 'Unknown Trigger';
        explanation = 'Unknown trigger type.';
        icon = Icons.help_outline;
        color = cs.onSurfaceVariant;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.1),
            color.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: color,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  explanation,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

