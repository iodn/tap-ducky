import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/router.dart';
import '../../data/models/payload.dart';
import '../../state/controllers/execution_controller.dart';
import '../../state/controllers/hid_status_controller.dart';
import '../../state/controllers/payloads_controller.dart';
import '../../state/providers.dart';
import '../../widgets/confirm_dialog.dart';

@immutable
class PayloadsUiState {
  const PayloadsUiState({
    required this.selectedTag,
    required this.searchQuery,
    required this.selectionMode,
    required this.selectedIds,
  });

  final String? selectedTag;
  final String searchQuery;
  final bool selectionMode;
  final Set<String> selectedIds;

  factory PayloadsUiState.initial() => const PayloadsUiState(
        selectedTag: null,
        searchQuery: '',
        selectionMode: false,
        selectedIds: <String>{},
      );

  PayloadsUiState copyWith({
    String? selectedTag,
    bool clearSelectedTag = false,
    String? searchQuery,
    bool? selectionMode,
    Set<String>? selectedIds,
  }) {
    return PayloadsUiState(
      selectedTag: clearSelectedTag ? null : (selectedTag ?? this.selectedTag),
      searchQuery: searchQuery ?? this.searchQuery,
      selectionMode: selectionMode ?? this.selectionMode,
      selectedIds: selectedIds ?? this.selectedIds,
    );
  }
}

final payloadsUiProvider =
    NotifierProvider<PayloadsUiController, PayloadsUiState>(PayloadsUiController.new);

class PayloadsUiController extends Notifier<PayloadsUiState> {
  @override
  PayloadsUiState build() => PayloadsUiState.initial();

  void setTag(String? tag) {
    state = state.copyWith(selectedTag: tag, clearSelectedTag: tag == null);
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query.trim());
  }

  void clearFilters() {
    state = state.copyWith(
      clearSelectedTag: true,
      searchQuery: '',
    );
  }

  void enterSelectionMode({String? selectId}) {
    final ids = Set<String>.from(state.selectedIds);
    if (selectId != null) ids.add(selectId);
    state = state.copyWith(selectionMode: true, selectedIds: ids);
  }

  void exitSelectionMode() {
    state = state.copyWith(selectionMode: false, selectedIds: <String>{});
  }

  void toggleSelection(String id) {
    final updated = Set<String>.from(state.selectedIds);
    if (updated.contains(id)) {
      updated.remove(id);
    } else {
      updated.add(id);
    }
    state = state.copyWith(selectedIds: updated);
  }

  void clearSelection() {
    state = state.copyWith(selectedIds: <String>{});
  }
}

class PayloadsScreen extends ConsumerStatefulWidget {
  const PayloadsScreen({super.key});

  @override
  ConsumerState<PayloadsScreen> createState() => _PayloadsScreenState();
}

class _PayloadsScreenState extends ConsumerState<PayloadsScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(payloadsControllerProvider);
    final ui = ref.watch(payloadsUiProvider);
    final hid = ref.watch(hidStatusControllerProvider);
    final exec = ref.watch(executionControllerProvider);

    Map<String, String> defaultParams(Payload p) {
      final out = <String, String>{};
      for (final param in p.parameters) {
        out[param.key] = param.defaultValue;
      }
      return out;
    }

    final canRunNow = hid.rootAvailable && hid.hidSupported && hid.sessionArmed && !exec.isRunning;

    final itemsCount = async.maybeWhen(data: (items) => items.length, orElse: () => 0);
    final hasItems = itemsCount > 0;

    return Scaffold(
      appBar: AppBar(
        title: ui.selectionMode
            ? Text('${ui.selectedIds.length} selected')
            : const Text('Payloads'),
        leading: ui.selectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => ref.read(payloadsUiProvider.notifier).exitSelectionMode(),
              )
            : null,
        actions: ui.selectionMode
            ? [
                IconButton(
                  icon: const Icon(Icons.play_arrow),
                  tooltip: canRunNow ? 'Run first selected' : 'Arm session to run',
                  onPressed: (!canRunNow || ui.selectedIds.isEmpty)
                      ? null
                      : () {
                          final items = async.value ?? const <Payload>[];
                          final id = ui.selectedIds.first;
                          final p = items.where((e) => e.id == id).cast<Payload?>().firstWhere(
                                (e) => e != null,
                                orElse: () => null,
                              );
                          if (p == null) return;
                          ref.read(executionControllerProvider.notifier).runPayload(p, defaultParams(p));
                        },
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  tooltip: 'Delete selected',
                  onPressed: ui.selectedIds.isEmpty ? null : () => _deleteSelected(context),
                ),
              ]
            : [
                IconButton(
                  tooltip: 'Search',
                  onPressed: () => _showSearchSheet(context),
                  icon: const Icon(Icons.search),
                ),
                IconButton(
                  tooltip: 'GitHub Store',
                  onPressed: () => context.go(const PayloadsStoreRoute().location),
                  icon: const Icon(Icons.cloud_download),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'export_all') {
                      await _exportAll(context, async.value ?? []);
                    } else if (v == 'import') {
                      await _importFromClipboard(context);
                    } else if (v == 'store') {
                      if (context.mounted) context.go(const PayloadsStoreRoute().location);
                    } else if (v == 'manage_store') {
                      if (context.mounted) context.go(const PayloadsManageSourcesRoute().location);
                    } else if (v == 'select') {
                      ref.read(payloadsUiProvider.notifier).enterSelectionMode();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'export_all', child: Text('Export all')),
                    PopupMenuItem(value: 'import', child: Text('Import from clipboard')),
                    PopupMenuItem(value: 'store', child: Text('Open GitHub Store')),
                    PopupMenuItem(value: 'manage_store', child: Text('Manage Sources')),
                    PopupMenuDivider(),
                    PopupMenuItem(value: 'select', child: Text('Select multiple')),
                  ],
                ),
              ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 16),
                Text('Failed to load payloads', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text('$e', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final storage = ref.read(prefsStorageProvider).maybeWhen(data: (s) => s, orElse: () => null);
              if (storage != null) {
                final flag = storage.getString('tapducky.ui.tip.import_store_shown') ?? '';
                if (flag != '1' && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      behavior: SnackBarBehavior.floating,
                      showCloseIcon: true,
                      content: const Text('Tip: Import payloads from the GitHub Store'),
                      action: SnackBarAction(
                        label: 'Open',
                        onPressed: () => context.go(const PayloadsStoreRoute().location),
                      ),
                      duration: const Duration(seconds: 5),
                    ),
                  );
                  storage.setString('tapducky.ui.tip.import_store_shown', '1');
                }
              }
            });

            return _EmptyStateWizard(
              onCreateTap: () => context.go('${const PayloadsRoute().location}/new'),
              onImportTap: () => _importFromClipboard(context),
              onOpenStoreTap: () => context.go(const PayloadsStoreRoute().location),
            );
          }

          final allTags = _extractAllTags(items);
          final filtered = _filterPayloads(items, ui.selectedTag, ui.searchQuery);

          return Column(
            children: [
              if (allTags.isNotEmpty) _TagFilterBar(tags: allTags, selectedTag: ui.selectedTag),
              if (ui.searchQuery.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Row(
                    children: [
                      const Icon(Icons.search, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Searching: "${ui.searchQuery}"',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          ref.read(payloadsUiProvider.notifier).setSearchQuery('');
                          _searchCtrl.clear();
                        },
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: filtered.isEmpty
                    ? _EmptyFilterResult(
                        query: ui.searchQuery,
                        tag: ui.selectedTag,
                        onClear: () {
                          ref.read(payloadsUiProvider.notifier).clearFilters();
                          _searchCtrl.clear();
                        },
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          ref.invalidate(payloadsControllerProvider);
                          await Future.delayed(const Duration(milliseconds: 500));
                        },
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: filtered.length,
                          itemBuilder: (context, i) {
                            final p = filtered[i];
                            final isSelected = ui.selectedIds.contains(p.id);

                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              child: _PayloadCard(
                                payload: p,
                                isSelected: isSelected,
                                selectionMode: ui.selectionMode,
                                canRun: canRunNow,
                                onTap: () {
                                  if (ui.selectionMode) {
                                    ref.read(payloadsUiProvider.notifier).toggleSelection(p.id);
                                  } else {
                                    context.go('${const PayloadsRoute().location}/${p.id}/edit');
                                  }
                                },
                                onLongPress: () {
                                  if (!ui.selectionMode) {
                                    ref.read(payloadsUiProvider.notifier).enterSelectionMode(selectId: p.id);
                                  }
                                },
                                onRun: canRunNow
                                    ? () {
                                        ref.read(executionControllerProvider.notifier).runPayload(p, defaultParams(p));
                                      }
                                    : null,
                                onDuplicate: () => _duplicate(p.id),
                                onExport: () => _exportOne(context, p),
                                onDelete: p.isBuiltin ? null : () => _delete(context, p),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: ui.selectionMode || !hasItems
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.go('${const PayloadsRoute().location}/new'),
              icon: const Icon(Icons.add),
              label: const Text('New Payload'),
            ),
    );
  }

  List<String> _extractAllTags(List<Payload> items) {
    final tags = <String>{};
    for (final p in items) {
      tags.addAll(p.tags);
    }
    final sorted = tags.toList()..sort();
    return sorted;
  }

  List<Payload> _filterPayloads(List<Payload> items, String? tag, String query) {
    var filtered = items;
    if (tag != null) {
      filtered = filtered.where((p) => p.tags.contains(tag)).toList();
    }
    if (query.isNotEmpty) {
      final lower = query.toLowerCase();
      filtered = filtered.where((p) {
        final hay = '${p.name} ${p.description} ${p.tags.join(' ')} ${p.script}'.toLowerCase();
        return hay.contains(lower);
      }).toList();
    }
    return filtered;
  }

  Future<void> _duplicate(String id) async {
    await ref.read(payloadsControllerProvider.notifier).duplicate(id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payload duplicated')),
      );
    }
  }

  Future<void> _delete(BuildContext context, Payload payload) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete payload',
      message: 'Delete "${payload.name}"? This cannot be undone.',
      confirmLabel: 'Delete',
      dangerous: true,
    );
    if (!ok) return;
    await ref.read(payloadsControllerProvider.notifier).delete(payload.id);
  }

  Future<void> _deleteSelected(BuildContext context) async {
    final ids = ref.read(payloadsUiProvider).selectedIds;
    final ok = await showConfirmDialog(
      context,
      title: 'Delete payloads',
      message: 'Delete ${ids.length} payload(s)? This cannot be undone.',
      confirmLabel: 'Delete',
      dangerous: true,
    );
    if (!ok) return;
    for (final id in ids) {
      await ref.read(payloadsControllerProvider.notifier).delete(id);
    }
    ref.read(payloadsUiProvider.notifier).exitSelectionMode();
  }

  Future<void> _exportOne(BuildContext context, Payload payload) async {
    final data = payload.exportJson();
    await Share.share(data, subject: 'TapDucky payload: ${payload.name}');
  }

  Future<void> _exportAll(BuildContext context, List<Payload> payloads) async {
    if (payloads.isEmpty) return;
    final pack = {
      'format': 'tapducky_payload_pack',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'items': payloads.map((e) => e.toJson()).toList(),
    };
    final data = const JsonEncoder.withIndent(' ').convert(pack);
    await Share.share(data, subject: 'TapDucky payload pack');
  }

  Future<void> _importFromClipboard(BuildContext context) async {
    final ctrl = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import payload(s)'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Paste payload JSON or a payload pack JSON below:'),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLines: 10,
                decoration: const InputDecoration(
                  hintText: '{"id": "...", "name": "...", ...}',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(ctrl.text),
            child: const Text('Import'),
          ),
        ],
      ),
    );

    if (res == null || res.trim().isEmpty) return;

    try {
      final decoded = jsonDecode(res);
      final incoming = <Payload>[];

      if (decoded is Map && decoded['items'] is List) {
        for (final it in (decoded['items'] as List)) {
          if (it is Map) incoming.add(Payload.fromJson(it.cast<String, dynamic>()));
        }
      } else if (decoded is Map) {
        incoming.add(Payload.fromJson(decoded.cast<String, dynamic>()));
      } else if (decoded is List) {
        for (final it in decoded) {
          if (it is Map) incoming.add(Payload.fromJson(it.cast<String, dynamic>()));
        }
      }

      if (incoming.isEmpty) throw const FormatException('No payloads found in input.');
      await ref.read(payloadsControllerProvider.notifier).importMany(incoming);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported ${incoming.length} payload(s).')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $e')),
      );
    }
  }

  void _showSearchSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Search payloads',
                    hintText: 'Name, tags, script content...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() {});
                            },
                          )
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (v) {
                    ref.read(payloadsUiProvider.notifier).setSearchQuery(v);
                    Navigator.pop(context);
                  },
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      ref.read(payloadsUiProvider.notifier).setSearchQuery(_searchCtrl.text);
                      Navigator.pop(context);
                    },
                    child: const Text('Search'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TagFilterBar extends ConsumerWidget {
  const _TagFilterBar({required this.tags, required this.selectedTag});

  final List<String> tags;
  final String? selectedTag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: tags.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          if (i == 0) {
            return FilterChip(
              label: const Text('All'),
              selected: selectedTag == null,
              onSelected: (_) => ref.read(payloadsUiProvider.notifier).setTag(null),
            );
          }
          final tag = tags[i - 1];
          return FilterChip(
            label: Text(tag),
            selected: selectedTag == tag,
            onSelected: (_) => ref.read(payloadsUiProvider.notifier).setTag(tag),
          );
        },
      ),
    );
  }
}

class _PayloadCard extends StatefulWidget {
  const _PayloadCard({
    required this.payload,
    required this.isSelected,
    required this.selectionMode,
    required this.canRun,
    required this.onTap,
    required this.onLongPress,
    required this.onRun,
    required this.onDuplicate,
    required this.onExport,
    required this.onDelete,
  });

  final Payload payload;
  final bool isSelected;
  final bool selectionMode;
  final bool canRun;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onRun;
  final VoidCallback onDuplicate;
  final VoidCallback onExport;
  final VoidCallback? onDelete;

  @override
  State<_PayloadCard> createState() => _PayloadCardState();
}

class _PayloadCardState extends State<_PayloadCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: widget.isSelected ? 4 : 1,
      color: widget.isSelected ? cs.primaryContainer.withOpacity(0.3) : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (widget.selectionMode)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Checkbox(
                        value: widget.isSelected,
                        onChanged: (_) => widget.onTap(),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: widget.payload.isBuiltin ? cs.tertiaryContainer : cs.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      widget.payload.isBuiltin ? Icons.lock : Icons.code,
                      color: widget.payload.isBuiltin ? cs.onTertiaryContainer : cs.onPrimaryContainer,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.payload.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.payload.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            widget.payload.description,
                            style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurfaceVariant,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!widget.selectionMode) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                      onPressed: () => setState(() => _expanded = !_expanded),
                      tooltip: _expanded ? 'Collapse' : 'Expand preview',
                    ),
                  ],
                ],
              ),
            ),
            if (widget.payload.tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: widget.payload.tags.map((tag) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.secondaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        tag,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: cs.onSecondaryContainer,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            if (_expanded)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
                        Icon(Icons.code, size: 14, color: cs.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Text(
                          'Script Preview',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.payload.script.trim().isEmpty
                          ? '(empty script)'
                          : widget.payload.script.split('\n').take(10).join('\n'),
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 10,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            if (!widget.selectionMode)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: widget.onRun,
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: const Text('Run'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      onPressed: widget.onDuplicate,
                      icon: const Icon(Icons.content_copy, size: 18),
                      tooltip: 'Duplicate',
                    ),
                    IconButton.outlined(
                      onPressed: widget.onExport,
                      icon: const Icon(Icons.ios_share, size: 18),
                      tooltip: 'Export',
                    ),
                    if (widget.onDelete != null)
                      IconButton.outlined(
                        onPressed: widget.onDelete,
                        icon: Icon(Icons.delete, size: 18, color: cs.error),
                        tooltip: 'Delete',
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyStateWizard extends StatelessWidget {
  const _EmptyStateWizard({
    required this.onCreateTap,
    required this.onImportTap,
    required this.onOpenStoreTap,
  });

  final VoidCallback onCreateTap;
  final VoidCallback onImportTap;
  final VoidCallback onOpenStoreTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.inventory_2, size: 64, color: cs.primary),
            ),
            const SizedBox(height: 24),
            Text(
              'Your Script Library',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              'Create, organize, and execute your custom HID payloads',
              style: TextStyle(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: const [
                    _WizardStep(
                      number: '1',
                      title: 'Create a Payload',
                      description: 'Write DuckyScript commands or use templates',
                      icon: Icons.edit_note,
                    ),
                    SizedBox(height: 16),
                    _WizardStep(
                      number: '2',
                      title: 'Organize with Tags',
                      description: 'Group payloads by category or purpose',
                      icon: Icons.label,
                    ),
                    SizedBox(height: 16),
                    _WizardStep(
                      number: '3',
                      title: 'Execute & Share',
                      description: 'Run on target or export to share',
                      icon: Icons.rocket_launch,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onCreateTap,
                icon: const Icon(Icons.add),
                label: const Text('Create Your First Payload'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onImportTap,
                icon: const Icon(Icons.download),
                label: const Text('Import Existing Payloads'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onOpenStoreTap,
                icon: const Icon(Icons.cloud_download),
                label: const Text('Import from GitHub Store'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WizardStep extends StatelessWidget {
  const _WizardStep({
    required this.number,
    required this.title,
    required this.description,
    required this.icon,
  });

  final String number;
  final String title;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Icon(icon, size: 20, color: cs.onPrimaryContainer),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyFilterResult extends StatelessWidget {
  const _EmptyFilterResult({
    required this.query,
    required this.tag,
    required this.onClear,
  });

  final String query;
  final String? tag;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 64, color: cs.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'No payloads found',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              query.isNotEmpty
                  ? 'No results for "$query"'
                  : tag != null
                      ? 'No payloads with tag "$tag"'
                      : 'Try adjusting your filters',
              style: TextStyle(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.clear_all),
              label: const Text('Clear Filters'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeedDialFAB extends StatelessWidget {
  const _SpeedDialFAB({
    required this.controller,
    required this.onNewTap,
    required this.onImportTap,
    required this.onExportAllTap,
  });

  final AnimationController controller;
  final VoidCallback onNewTap;
  final VoidCallback onImportTap;
  final VoidCallback onExportAllTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ScaleTransition(
          scale: CurvedAnimation(parent: controller, curve: Curves.easeOut),
          child: FloatingActionButton.small(
            heroTag: 'fab_export',
            onPressed: () {
              controller.reverse();
              onExportAllTap();
            },
            tooltip: 'Export all',
            child: const Icon(Icons.ios_share),
          ),
        ),
        const SizedBox(height: 12),
        ScaleTransition(
          scale: CurvedAnimation(parent: controller, curve: Curves.easeOut),
          child: FloatingActionButton.small(
            heroTag: 'fab_import',
            onPressed: () {
              controller.reverse();
              onImportTap();
            },
            tooltip: 'Import',
            child: const Icon(Icons.download),
          ),
        ),
        const SizedBox(height: 12),
        FloatingActionButton.extended(
          heroTag: 'fab_main',
          onPressed: () {
            if (controller.isCompleted) {
              controller.reverse();
            } else {
              controller.forward();
            }
          },
          icon: AnimatedIcon(
            icon: AnimatedIcons.menu_close,
            progress: controller,
          ),
          label: const Text('New'),
        ),
      ],
    );
  }
}
