import 'package:material_ui/material_ui.dart';

import 'script_reference_data.dart';

class ScriptReferenceScreen extends StatefulWidget {
  const ScriptReferenceScreen({super.key});

  @override
  State<ScriptReferenceScreen> createState() => _ScriptReferenceScreenState();
}

class _ScriptReferenceScreenState extends State<ScriptReferenceScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final rows = <(String, ScriptReferenceEntry?)>[];
    for (final section in scriptReference.entries) {
      final entries = section.value.where((entry) {
        return section.key.toLowerCase().contains(query) ||
            entry.syntax.toLowerCase().contains(query) ||
            entry.description.toLowerCase().contains(query);
      });
      if (entries.isEmpty) continue;
      rows.add((section.key, null));
      rows.addAll(entries.map((entry) => (section.key, entry)));
    }

    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: const Text('DuckyScript reference'),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      labelText: 'Search commands and variables',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: () => setState(_search.clear),
                              icon: const Icon(Icons.clear),
                            ),
                    ),
                  ),
                ),
                Expanded(
                  child: rows.isEmpty
                      ? const Center(child: Text('No matching entries.'))
                      : ListView.builder(
                          key: ValueKey(query),
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          itemCount: rows.length,
                          itemBuilder: (context, index) {
                            final (section, entry) = rows[index];
                            if (entry == null) {
                              return Padding(
                                padding: const EdgeInsets.only(
                                  top: 16,
                                  bottom: 12,
                                ),
                                child: Semantics(
                                  header: true,
                                  child: Text(
                                    section,
                                    style: theme.textTheme.titleMedium,
                                  ),
                                ),
                              );
                            }
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SelectableText(
                                    entry.syntax,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(entry.description),
                                ],
                              ),
                            );
                          },
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
