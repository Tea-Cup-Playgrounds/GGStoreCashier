import 'package:flutter/material.dart';
import 'package:gg_store_cashier/core/models/access.dart';
import 'package:gg_store_cashier/core/models/catalog.dart';
import '../pages/opnames_page.dart';
import '../pages/receipts_page.dart';
import '../pages/suppliers_page.dart';
import '../pages/transfers_page.dart';

/// Inventory header menu for warehouse work at [location]: goods receipts, transfers, stock
/// counts and suppliers. Each entry only shows when the user may use it there.
/// [onClosed] runs after the opened page is closed (stock may have changed).
class WarehouseMenuButton extends StatelessWidget {
  final Location location;
  final UserAccess access;
  final VoidCallback onClosed;

  const WarehouseMenuButton({super.key, required this.location, required this.access, required this.onClosed});

  @override
  Widget build(BuildContext context) {
    final entries = <(IconData, String, Widget Function())>[
      if (access.can('purchases.manage', location.id))
        (Icons.move_to_inbox_outlined, 'Penerimaan Barang', () => ReceiptsPage(location: location)),
      if (access.can('stock.view', location.id))
        (Icons.local_shipping_outlined, 'Transfer Stok', () => TransfersPage(location: location)),
      if (access.can('stock.view', location.id))
        (Icons.fact_check_outlined, 'Stok Opname', () => OpnamesPage(location: location)),
      if (access.can('suppliers.manage') || access.can('purchases.manage'))
        (Icons.business_outlined, 'Supplier', () => const SuppliersPage()),
    ];
    if (entries.isEmpty) return const SizedBox.shrink();

    return PopupMenuButton<int>(
      tooltip: 'Gudang',
      icon: const Icon(Icons.warehouse_outlined),
      onSelected: (i) async {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => entries[i].$3()));
        onClosed();
      },
      itemBuilder: (_) => [
        for (var i = 0; i < entries.length; i++)
          PopupMenuItem(
            value: i,
            child: Row(children: [Icon(entries[i].$1, size: 20), const SizedBox(width: 12), Text(entries[i].$2)]),
          ),
      ],
    );
  }
}
