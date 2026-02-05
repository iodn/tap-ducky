import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/usb_ids_db.dart';

Future<UsbProduct?> showUsbIdSelectorDialog(BuildContext context, WidgetRef ref) async {
  final dbAsync = await ref.read(usbIdsDbProvider.future);
  return showDialog<UsbProduct>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _UsbIdSelectorDialog(db: dbAsync),
  );
}

class _UsbIdSelectorDialog extends StatefulWidget {
  const _UsbIdSelectorDialog({required this.db});

  final UsbIdsDb db;

  @override
  State<_UsbIdSelectorDialog> createState() => _UsbIdSelectorDialogState();
}

class _UsbIdSelectorDialogState extends State<_UsbIdSelectorDialog> with TickerProviderStateMixin {
  late final TabController _tabs;

  final TextEditingController _vendorQuery = TextEditingController();
  final TextEditingController _productQuery = TextEditingController();
  final TextEditingController _globalProductQuery = TextEditingController();

  Timer? _debounce;

  bool _vendorLoading = false;
  Object? _vendorError;
  List<UsbVendor> _vendors = const [];

  UsbVendor? _selectedVendor;

  bool _vendorProductsLoading = false;
  Object? _vendorProductsError;
  List<UsbProduct> _vendorProducts = const [];

  bool _globalProductsLoading = false;
  Object? _globalProductsError;
  List<UsbProduct> _globalProducts = const [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);

    _vendorQuery.addListener(() {
      _schedule(() async {
        await _loadVendors(_vendorQuery.text);
      });
    });

    _productQuery.addListener(() {
      final v = _selectedVendor;
      if (v == null) return;
      _schedule(() async {
        await _loadProductsForVendor(v.vid, _productQuery.text);
      });
    });

    _globalProductQuery.addListener(() {
      _schedule(() async {
        await _loadGlobalProducts(_globalProductQuery.text);
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _vendorQuery.dispose();
    _productQuery.dispose();
    _globalProductQuery.dispose();
    _tabs.dispose();
    super.dispose();
  }

  void _schedule(Future<void> Function() fn) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      fn();
    });
  }

  Future<void> _loadVendors(String query) async {
    final q = query.trim();
    if (q.length < 2) {
      setState(() {
        _vendorLoading = false;
        _vendorError = null;
        _vendors = const [];
      });
      return;
    }

    setState(() {
      _vendorLoading = true;
      _vendorError = null;
    });

    try {
      final res = await widget.db.searchVendors(q);
      if (!mounted) return;
      setState(() {
        _vendorLoading = false;
        _vendors = res;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _vendorLoading = false;
        _vendorError = e;
        _vendors = const [];
      });
    }
  }

  Future<void> _loadProductsForVendor(int vid, String query) async {
    setState(() {
      _vendorProductsLoading = true;
      _vendorProductsError = null;
    });

    try {
      final res = await widget.db.searchProductsByVendor(vid, query);
      if (!mounted) return;
      setState(() {
        _vendorProductsLoading = false;
        _vendorProducts = res;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _vendorProductsLoading = false;
        _vendorProductsError = e;
        _vendorProducts = const [];
      });
    }
  }

  Future<void> _loadGlobalProducts(String query) async {
    final q = query.trim();
    if (q.length < 2) {
      setState(() {
        _globalProductsLoading = false;
        _globalProductsError = null;
        _globalProducts = const [];
      });
      return;
    }

    setState(() {
      _globalProductsLoading = true;
      _globalProductsError = null;
    });

    try {
      final res = await widget.db.searchProductsByName(q);
      if (!mounted) return;
      setState(() {
        _globalProductsLoading = false;
        _globalProducts = res;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _globalProductsLoading = false;
        _globalProductsError = e;
        _globalProducts = const [];
      });
    }
  }

  void _selectVendor(UsbVendor v) {
    setState(() {
      _selectedVendor = v;
      _vendorProducts = const [];
      _vendorProductsError = null;
      _productQuery.text = '';
    });
    _loadProductsForVendor(v.vid, '');
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Select VID/PID'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(null),
          ),
          bottom: TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: 'Vendor → Product'),
              Tab(text: 'Search product'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabs,
          children: [
            _buildVendorFlow(context),
            _buildGlobalFlow(context),
          ],
        ),
      ),
    );
  }

  Widget _buildVendorFlow(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selected = _selectedVendor;

    if (selected == null) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Type a vendor name (e.g., Logitech, Apple, Samsung), then pick a product.',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _vendorQuery,
                  decoration: InputDecoration(
                    labelText: 'Vendor name',
                    prefixIcon: const Icon(Icons.store),
                    suffixIcon: _vendorQuery.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(() => _vendorQuery.text = ''),
                          ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _vendorLoading
                ? const Center(child: CircularProgressIndicator())
                : _vendorError != null
                    ? Center(child: Text('Failed to search vendors: $_vendorError'))
                    : _vendorQuery.text.trim().length < 2
                        ? Center(
                            child: Text(
                              'Enter at least 2 characters to search.',
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                          )
                        : _vendors.isEmpty
                            ? Center(
                                child: Text(
                                  'No vendors found.',
                                  style: TextStyle(color: cs.onSurfaceVariant),
                                ),
                              )
                            : ListView.separated(
                                itemCount: _vendors.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (context, i) {
                                  final v = _vendors[i];
                                  return ListTile(
                                    leading: _IdPill(label: 'VID', value: v.vidHex),
                                    title: Text(v.name),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => _selectVendor(v),
                                  );
                                },
                              ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _selectedVendor = null;
                        _vendorProducts = const [];
                        _vendorProductsError = null;
                        _productQuery.text = '';
                      });
                    },
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Back to vendors',
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      selected.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _IdPill(label: 'VID', value: selected.vidHex),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _productQuery,
                decoration: InputDecoration(
                  labelText: 'Product name (within vendor)',
                  prefixIcon: const Icon(Icons.usb),
                  suffixIcon: _productQuery.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(() => _productQuery.text = ''),
                        ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _vendorProductsLoading
              ? const Center(child: CircularProgressIndicator())
              : _vendorProductsError != null
                  ? Center(child: Text('Failed to load products: $_vendorProductsError'))
                  : _vendorProducts.isEmpty
                      ? Center(
                          child: Text(
                            'No products found for this vendor.',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _vendorProducts.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final p = _vendorProducts[i];
                            return ListTile(
                              leading: _IdPill(label: 'PID', value: p.pidHex),
                              title: Text(p.productName),
                              subtitle: Text('${p.vendorName} • ${p.vidHex}:${p.pidHex}'),
                              onTap: () => Navigator.of(context).pop(p),
                            );
                          },
                        ),
        ),
      ],
    );
  }

  Widget _buildGlobalFlow(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Search by product name (e.g., “Keyboard”, “Gamepad”, “Receiver”). Results include vendor and IDs.',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _globalProductQuery,
                decoration: InputDecoration(
                  labelText: 'Product name',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _globalProductQuery.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(() => _globalProductQuery.text = ''),
                        ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _globalProductsLoading
              ? const Center(child: CircularProgressIndicator())
              : _globalProductsError != null
                  ? Center(child: Text('Failed to search products: $_globalProductsError'))
                  : _globalProductQuery.text.trim().length < 2
                      ? Center(
                          child: Text(
                            'Enter at least 2 characters to search.',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        )
                      : _globalProducts.isEmpty
                          ? Center(
                              child: Text(
                                'No products found.',
                                style: TextStyle(color: cs.onSurfaceVariant),
                              ),
                            )
                          : ListView.separated(
                              itemCount: _globalProducts.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final p = _globalProducts[i];
                                return ListTile(
                                  leading: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _IdPill(label: 'VID', value: p.vidHex),
                                      const SizedBox(height: 6),
                                      _IdPill(label: 'PID', value: p.pidHex),
                                    ],
                                  ),
                                  title: Text(p.productName),
                                  subtitle: Text('${p.vendorName} • ${p.vidHex}:${p.pidHex}'),
                                  onTap: () => Navigator.of(context).pop(p),
                                );
                              },
                            ),
        ),
      ],
    );
  }
}

class _IdPill extends StatelessWidget {
  const _IdPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
