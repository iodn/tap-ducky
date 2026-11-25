import 'package:material_ui/material_ui.dart';

import '../data/models/payload.dart';
import 'configuration_page.dart';

/// Shows the full payload name on long press and opens a searchable list.
class PayloadPicker extends StatelessWidget {
  const PayloadPicker({
    super.key,
    required this.payloads,
    required this.selected,
    required this.onChanged,
  });

  final List<Payload> payloads;
  final Payload? selected;
  final ValueChanged<Payload> onChanged;

  @override
  Widget build(BuildContext context) {
    final name = selected?.name;
    return Tooltip(
      message: name ?? 'Choose a payload',
      excludeFromSemantics: true,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          alignment: AlignmentDirectional.centerStart,
          minimumSize: const Size(0, 56),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: payloads.isEmpty
            ? null
            : () async {
                final picked = await showConfigurationPage<Payload>(
                  context,
                  (_) => _PayloadPickerPage(
                    payloads: payloads,
                    selectedId: selected?.id,
                  ),
                );
                if (context.mounted && picked != null) onChanged(picked);
              },
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Payload',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    name ?? 'Choose a payload',
                    style: Theme.of(context).textTheme.bodyMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}

class _PayloadPickerPage extends StatefulWidget {
  const _PayloadPickerPage({required this.payloads, this.selectedId});

  final List<Payload> payloads;
  final String? selectedId;

  @override
  State<_PayloadPickerPage> createState() => _PayloadPickerPageState();
}

class _PayloadPickerPageState extends State<_PayloadPickerPage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final matches = query.isEmpty
        ? widget.payloads
        : widget.payloads.where((p) {
            return p.name.toLowerCase().contains(query) ||
                p.description.toLowerCase().contains(query) ||
                p.tags.any((tag) => tag.toLowerCase().contains(query));
          }).toList();

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: const Text('Choose payload'),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: CustomScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  sliver: SliverToBoxAdapter(
                    child: TextField(
                      controller: _search,
                      onChanged: (value) => setState(() => _query = value),
                      decoration: InputDecoration(
                        labelText: 'Search payloads',
                        prefixIcon: const Icon(Icons.search),
                        border: const OutlineInputBorder(),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                onPressed: () {
                                  _search.clear();
                                  setState(() => _query = '');
                                },
                                icon: const Icon(Icons.clear),
                              ),
                      ),
                    ),
                  ),
                ),
                if (matches.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No matching payloads',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else
                  SliverList.builder(
                    itemCount: matches.length,
                    itemBuilder: (context, index) {
                      final payload = matches[index];
                      final selected = payload.id == widget.selectedId;
                      return Tooltip(
                        message: payload.name,
                        excludeFromSemantics: true,
                        child: ListTile(
                          title: Text(
                            payload.name,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: payload.description.isEmpty
                              ? null
                              : Text(
                                  payload.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          trailing: selected ? const Icon(Icons.check) : null,
                          selected: selected,
                          onTap: () => Navigator.pop(context, payload),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
