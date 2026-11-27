import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/db/usb_ids_db.dart';
import '../../widgets/configuration_page.dart';

class UsbIdReferenceScreen extends ConsumerStatefulWidget {
  const UsbIdReferenceScreen({super.key});

  @override
  ConsumerState<UsbIdReferenceScreen> createState() =>
      _UsbIdReferenceScreenState();
}

class _UsbIdReferenceScreenState extends ConsumerState<UsbIdReferenceScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  Future<List<UsbProduct>>? _results;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _search(String input) {
    _debounce?.cancel();
    final query = input.trim();
    setState(() {
      _query = query;
      _results = null;
    });
    if (query.length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 250), () {
      setState(() {
        _results = ref
            .read(usbIdsDbProvider.future)
            .then((db) => db.searchProducts(query));
      });
    });
  }

  String _idPair(UsbProduct product) => '${product.vidHex}:${product.pidHex}';

  Future<void> _copy(String value) async {
    try {
      await Clipboard.setData(ClipboardData(text: value));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Copied $value'),
            duration: const Duration(seconds: 2),
          ),
        );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not copy the USB ID.')),
      );
    }
  }

  Future<void> _showProduct(UsbProduct product) async {
    final selected = await showConfigurationPage<String>(
      context,
      (context) => Scaffold(
        appBar: AppBar(
          leading: const CloseButton(),
          title: const Text('USB product'),
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                product.productName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(product.vendorName),
              const SizedBox(height: 12),
              for (final (label, value) in [
                ('Vendor ID (VID)', product.vidHex),
                ('Product ID (PID)', product.pidHex),
              ])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(label),
                  subtitle: Text(value),
                  trailing: IconButton(
                    tooltip: 'Copy $label',
                    icon: const Icon(Icons.copy_outlined),
                    onPressed: () => Navigator.pop(context, value),
                  ),
                ),
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context, _idPair(product)),
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copy VID:PID'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted && selected != null) await _copy(selected);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: const Text('USB ID reference'),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: TextField(
                controller: _controller,
                onChanged: _search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  labelText: 'Vendor, product, or VID:PID',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _controller.clear();
                            _search('');
                          },
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  "Reference only. TapDucky sessions keep Android's USB identity.",
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            Expanded(
              child: _query.length < 2
                  ? const Center(child: Text('Enter at least two characters.'))
                  : FutureBuilder<List<UsbProduct>>(
                      future: _results,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snapshot.hasError) {
                          return Center(
                            child: TextButton(
                              onPressed: () => _search(_query),
                              child: const Text('Search failed. Try again'),
                            ),
                          );
                        }
                        final products = snapshot.requireData;
                        if (products.isEmpty) {
                          return const Center(
                            child: Text('No matching products.'),
                          );
                        }
                        return ListView.separated(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          itemCount: products.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final product = products[index];
                            return ListTile(
                              title: Text(product.productName),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(product.vendorName),
                                  Text(
                                    _idPair(product),
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () => _showProduct(product),
                              trailing: IconButton(
                                tooltip: 'Copy VID:PID',
                                icon: const Icon(Icons.copy_outlined),
                                onPressed: () => _copy(_idPair(product)),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
