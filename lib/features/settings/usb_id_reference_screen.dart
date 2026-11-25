import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/db/usb_ids_db.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: const Text('USB ID reference'),
      ),
      body: SafeArea(
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
                              subtitle: Text(
                                '${product.vendorName}\n${product.vidHex}:${product.pidHex}',
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
