import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/payload.dart';
import '../../state/controllers/payloads_controller.dart';
import '../../state/controllers/scheduler_controller.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/payload_parameter_field.dart';
import '../../widgets/payload_picker.dart';

class ScheduleEditorScreen extends ConsumerStatefulWidget {
  const ScheduleEditorScreen._({super.key, required this.isNew, this.taskId});

  const ScheduleEditorScreen.newTask({Key? key})
    : this._(key: key, isNew: true);

  const ScheduleEditorScreen.edit({Key? key, required String taskId})
    : this._(key: key, isNew: false, taskId: taskId);

  final bool isNew;
  final String? taskId;

  @override
  ConsumerState<ScheduleEditorScreen> createState() =>
      _ScheduleEditorScreenState();
}

class _ScheduleEditorScreenState extends ConsumerState<ScheduleEditorScreen> {
  final _name = TextEditingController();
  final _windowStart = TextEditingController();
  final _windowEnd = TextEditingController();

  String _trigger = 'one_time';
  String? _payloadId;
  DateTime? _runAt;
  final _parameterControllers = <String, Map<String, TextEditingController>>{};
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _windowStart.dispose();
    _windowEnd.dispose();
    for (final controllers in _parameterControllers.values) {
      for (final controller in controllers.values) {
        controller.dispose();
      }
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
        _parameterControllers[t.payloadId] = {
          for (final entry in t.params.entries)
            entry.key: TextEditingController(text: entry.value),
        };
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
    final schedules = widget.isNew
        ? null
        : ref.watch(schedulerControllerProvider);
    final schedulesCtrl = ref.read(schedulerControllerProvider.notifier);
    final canEdit = widget.isNew || schedulesCtrl.byId(widget.taskId!) != null;
    final availablePayloads = payloadsAsync.value;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isNew ? 'New Schedule' : 'Edit Schedule',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: TextButton(
              onPressed:
                  canEdit &&
                      !_saving &&
                      availablePayloads != null &&
                      availablePayloads.isNotEmpty
                  ? () => _save(schedulesCtrl, availablePayloads)
                  : null,
              child: const Text('Save'),
            ),
          ),
        ],
      ),
      body: schedules?.isLoading == true && !canEdit
          ? const Center(child: CircularProgressIndicator())
          : !canEdit
          ? const Center(child: Text('Schedule unavailable'))
          : payloadsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: cs.error),
                      const SizedBox(height: 16),
                      Text(
                        'Failed to load payloads',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
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

                final selectedPayload =
                    _findPayload(payloads, _payloadId) ?? payloads.first;
                _payloadId = selectedPayload.id;
                final parameterControllers = _controllersFor(selectedPayload);

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _SectionCard(
                      icon: Icons.settings,
                      title: 'Schedule details',
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
                        PayloadPicker(
                          payloads: payloads,
                          selected: selectedPayload,
                          onChanged: (payload) =>
                              setState(() => _payloadId = payload.id),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      icon: Icons.flash_on,
                      title: 'Trigger',
                      color: cs.primary,
                      children: [
                        _TriggerSelector(
                          value: _trigger,
                          onChanged: (v) => setState(() => _trigger = v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_trigger == 'one_time') ...[
                      _SectionCard(
                        icon: Icons.event,
                        title: 'Schedule time',
                        color: cs.secondary,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _pickDateTime(context),
                            icon: const Icon(Icons.edit_calendar),
                            label: Text(
                              _runAt == null
                                  ? 'Choose date and time'
                                  : _formatDateTime(_runAt!),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                    _SectionCard(
                      icon: Icons.access_time_filled,
                      title: 'Time window',
                      color: cs.primary,
                      children: [
                        const Text(
                          'Optional. Limits when the schedule can run.',
                        ),
                        const SizedBox(height: 12),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final start = _timeField(
                              'Start time',
                              _windowStart,
                            );
                            final end = _timeField('End time', _windowEnd);
                            if (constraints.maxWidth <
                                MediaQuery.textScalerOf(context).scale(320)) {
                              return Column(
                                children: [
                                  start,
                                  const SizedBox(height: 12),
                                  end,
                                ],
                              );
                            }
                            return Row(
                              children: [
                                Expanded(child: start),
                                const SizedBox(width: 12),
                                Expanded(child: end),
                              ],
                            );
                          },
                        ),
                        if (_windowStart.text.isNotEmpty ||
                            _windowEnd.text.isNotEmpty)
                          TextButton(
                            onPressed: () => setState(() {
                              _windowStart.clear();
                              _windowEnd.clear();
                            }),
                            child: const Text('Clear time window'),
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
                          for (final parameter in selectedPayload.parameters)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: PayloadParameterField(
                                key: ValueKey((
                                  selectedPayload.id,
                                  parameter.key,
                                )),
                                parameter: parameter,
                                controller:
                                    parameterControllers[parameter.key]!,
                              ),
                            ),
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

  Map<String, TextEditingController> _controllersFor(Payload payload) {
    final controllers = _parameterControllers.putIfAbsent(payload.id, () => {});
    for (final parameter in payload.parameters) {
      controllers.putIfAbsent(
        parameter.key,
        () => TextEditingController(text: parameter.defaultValue),
      );
    }
    return controllers;
  }

  Widget _timeField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      readOnly: true,
      onTap: () => _pickTime(context, controller),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: const Icon(Icons.schedule),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _pickDateTime(BuildContext context) async {
    final now = DateTime.now();
    final initial = _runAt ?? now.add(const Duration(minutes: 5));

    final first = now.subtract(const Duration(days: 1));
    final last = now.add(const Duration(days: 365));
    final date = await showDatePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      initialDate: initial.isBefore(first) || initial.isAfter(last)
          ? now
          : initial,
    );

    if (date == null || !context.mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );

    if (time == null || !mounted) return;

    setState(() {
      _runAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _pickTime(
    BuildContext context,
    TextEditingController ctrl,
  ) async {
    final initial = _parseTime(ctrl.text) ?? TimeOfDay.now();
    final time = await showTimePicker(context: context, initialTime: initial);
    if (time == null || !mounted) return;
    setState(() {
      ctrl.text =
          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    });
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
    final payloadId =
        _payloadId ?? (payloads.isNotEmpty ? payloads.first.id : null);
    if (_saving || payloadId == null) return;

    final params = <String, String>{};
    final payload = _findPayload(payloads, payloadId);
    if (payload != null) {
      final controllers = _controllersFor(payload);
      for (final p in payload.parameters) {
        params[p.key] = controllers[p.key]?.text ?? p.defaultValue;
      }
    }

    final windowStart = _windowStart.text.trim().isEmpty
        ? null
        : _windowStart.text.trim();
    final windowEnd = _windowEnd.text.trim().isEmpty
        ? null
        : _windowEnd.text.trim();

    setState(() => _saving = true);
    try {
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
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save the schedule')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
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
  const _TriggerSelector({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return RadioGroup<String>(
      groupValue: value,
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
      child: const Column(
        children: [
          RadioListTile<String>(
            contentPadding: EdgeInsets.zero,
            value: 'one_time',
            secondary: Icon(Icons.event),
            title: Text('One time'),
            subtitle: Text('At the selected date and time'),
          ),
          RadioListTile<String>(
            contentPadding: EdgeInsets.zero,
            value: 'app_cold_start',
            secondary: Icon(Icons.power_settings_new),
            title: Text('App start'),
            subtitle: Text('When TapDucky starts from a closed state'),
          ),
          RadioListTile<String>(
            contentPadding: EdgeInsets.zero,
            value: 'app_foreground',
            secondary: Icon(Icons.open_in_new),
            title: Text('App open'),
            subtitle: Text('Each time TapDucky comes to the foreground'),
          ),
          RadioListTile<String>(
            contentPadding: EdgeInsets.zero,
            value: 'device_connected',
            secondary: Icon(Icons.usb),
            title: Text('Session armed'),
            subtitle: Text('When a USB HID session is armed'),
          ),
        ],
      ),
    );
  }
}
