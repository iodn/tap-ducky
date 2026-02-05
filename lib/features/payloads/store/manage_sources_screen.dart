import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/services/github_store/models.dart';
import '../../../state/controllers/payloads_store_controller.dart';

class ManageSourcesScreen extends ConsumerStatefulWidget {
  const ManageSourcesScreen({super.key});

  @override
  ConsumerState<ManageSourcesScreen> createState() => _ManageSourcesScreenState();
}

class _ManageSourcesScreenState extends ConsumerState<ManageSourcesScreen> {
  final Set<int> _selected = <int>{};
  bool _editMode = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(payloadsStoreControllerProvider);
    final ctrl = ref.read(payloadsStoreControllerProvider.notifier);
    final sources = state.sources;

    final hasSelection = _selected.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Sources'),
        actions: [
          if (!_editMode)
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.tune),
              onPressed: () => setState(() {
                _editMode = true;
                _selected.clear();
              }),
            )
          else ...[
            IconButton(
              tooltip: 'Select all',
              onPressed: sources.isEmpty
                  ? null
                  : () => setState(() {
                        if (_selected.length == sources.length) {
                          _selected.clear();
                        } else {
                          _selected
                            ..clear()
                            ..addAll(List.generate(sources.length, (i) => i));
                        }
                      }),
              icon: const Icon(Icons.select_all),
            ),
            IconButton(
              tooltip: 'Delete selected',
              onPressed: !hasSelection
                  ? null
                  : () async {
                      final toRemove = _selected.toList()..sort((a, b) => b.compareTo(a));
                      for (final idx in toRemove) {
                        if (idx >= 0 && idx < sources.length) {
                          await ctrl.removeSource(sources[idx]);
                        }
                      }
                      if (mounted) {
                        setState(() => _selected.clear());
                      }
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Removed ${toRemove.length} source(s)'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
              icon: const Icon(Icons.delete_outline),
            ),
            IconButton(
              tooltip: 'Done',
              icon: const Icon(Icons.check),
              onPressed: () => setState(() {
                _editMode = false;
                _selected.clear();
              }),
            ),
          ],
        ],
      ),
      body: sources.isEmpty
          ? _EmptyState(
              title: 'No sources yet',
              subtitle: 'Add a source from the store screen, then manage it here.',
              icon: Icons.bookmarks_outlined,
            )
          : Column(
              children: [
                if (_editMode)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.55),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 18, color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Reorder sources, rename, or select multiple to delete.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: _editMode
                      ? ReorderableListView.builder(
                          itemCount: sources.length,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          onReorder: (oldIndex, newIndex) async {
                            final list = [...sources];
                            var ni = newIndex;
                            if (ni > oldIndex) ni -= 1;
                            final item = list.removeAt(oldIndex);
                            list.insert(ni, item);
                            await ctrl.setSources(list);
                          },
                          itemBuilder: (context, index) {
                            final r = sources[index];
                            return _SourceTile(
                              key: ValueKey('${r.owner}/${r.repo}/${r.branch}/${r.path}'),
                              repo: r,
                              index: index,
                              editMode: true,
                              selected: _selected.contains(index),
                              onToggleSelected: (v) => setState(() {
                                if (v) {
                                  _selected.add(index);
                                } else {
                                  _selected.remove(index);
                                }
                              }),
                              onRename: () => _rename(context, r),
                              onRemove: () => _confirmRemove(context, r),
                              showDragHandle: true,
                            );
                          },
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: sources.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final r = sources[index];
                            return Dismissible(
                              key: ValueKey('dismiss-${r.owner}/${r.repo}/${r.branch}/${r.path}'),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                color: theme.colorScheme.errorContainer,
                                child: Icon(Icons.delete_outline, color: theme.colorScheme.onErrorContainer),
                              ),
                              confirmDismiss: (_) => _confirmRemove(context, r),
                              onDismissed: (_) async {
                                // Already removed via confirm dialog
                              },
                              child: _SourceTile(
                                repo: r,
                                index: index,
                                editMode: false,
                                selected: false,
                                onToggleSelected: (_) {},
                                onRename: () => _rename(context, r),
                                onRemove: () => _confirmRemove(context, r),
                                showDragHandle: false,
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Future<bool> _confirmRemove(BuildContext context, RepoRef refRepo) async {
    final ctrl = ref.read(payloadsStoreControllerProvider.notifier);
    final alias =
        (refRepo.alias?.trim().isNotEmpty == true) ? refRepo.alias!.trim() : '${refRepo.owner}/${refRepo.repo}';

    final res = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove source'),
        content: Text('Remove "$alias" from your sources?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (res == true) {
      await ctrl.removeSource(refRepo);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Source removed'), behavior: SnackBarBehavior.floating),
        );
      }
      return true;
    }
    return false;
  }

  Future<void> _rename(BuildContext context, RepoRef refRepo) async {
    final ctrl = ref.read(payloadsStoreControllerProvider.notifier);
    final current = refRepo.alias ?? '${refRepo.owner}/${refRepo.repo}';
    final textCtrl = TextEditingController(text: current);

    final res = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final bottom = MediaQuery.of(context).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Rename source', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                refRepo.originalUrl,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: textCtrl,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Display name',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => Navigator.of(context).pop(textCtrl.text.trim()),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(textCtrl.text.trim()),
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    if (res == null) return;
    await ctrl.updateSourceAlias(refRepo, res);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Source renamed'), behavior: SnackBarBehavior.floating),
      );
    }
  }
}

class _SourceTile extends StatelessWidget {
  final RepoRef repo;
  final int index;
  final bool editMode;
  final bool selected;
  final ValueChanged<bool> onToggleSelected;
  final VoidCallback onRename;
  final Future<bool> Function() onRemove;
  final bool showDragHandle;

  const _SourceTile({
    super.key,
    required this.repo,
    required this.index,
    required this.editMode,
    required this.selected,
    required this.onToggleSelected,
    required this.onRename,
    required this.onRemove,
    required this.showDragHandle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final alias =
        (repo.alias?.trim().isNotEmpty == true) ? repo.alias!.trim() : '${repo.owner}/${repo.repo}';

    final subtitle = repo.originalUrl;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: editMode
          ? Checkbox(
              value: selected,
              onChanged: (v) => onToggleSelected(v == true),
            )
          : CircleAvatar(
              radius: 18,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              child: Icon(Icons.source_outlined, size: 18, color: theme.colorScheme.onSurfaceVariant),
            ),
      title: Text(alias, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Rename',
            onPressed: onRename,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Remove',
            onPressed: () async {
              await onRemove();
            },
            icon: const Icon(Icons.delete_outline),
          ),
          if (showDragHandle) const ReorderableDragStartListener(index: 0, child: SizedBox.shrink()),
        ],
      ),
      onTap: editMode ? () => onToggleSelected(!selected) : onRename,
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _EmptyState({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
