import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:gg_store_cashier/core/helper/currency_formatter.dart';
import 'package:gg_store_cashier/core/models/catalog.dart';
import 'package:gg_store_cashier/core/services/catalog_service.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';

/// Stock history of one variant at one location.
class MovementsSheet extends StatelessWidget {
  final Location location;
  final String variantLabel;
  final int variantId;

  const MovementsSheet({super.key, required this.location, required this.variantLabel, required this.variantId});

  static Future<void> show(BuildContext context, {required Location location, required String variantLabel, required int variantId}) =>
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => MovementsSheet(location: location, variantLabel: variantLabel, variantId: variantId),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Riwayat Stok', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            Text('$variantLabel · ${location.label}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<StockMovement>>(
                future: CatalogService.getMovements(locationId: location.id, variantId: variantId),
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator(color: AppTheme.gold));
                  }
                  if (snap.hasError) return Center(child: Text(snap.error.toString()));
                  final moves = snap.data!;
                  if (moves.isEmpty) {
                    return Center(child: Text('Belum ada riwayat', style: TextStyle(color: cs.onSurfaceVariant)));
                  }
                  return ListView.separated(
                    controller: scrollController,
                    itemCount: moves.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final m = moves[i];
                      final positive = m.qtyChange > 0;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: (positive ? AppTheme.success : AppTheme.destructive).withValues(alpha: 0.12),
                          child: Text('${positive ? '+' : ''}${m.qtyChange}',
                              style: TextStyle(
                                  color: positive ? AppTheme.success : AppTheme.destructive, fontWeight: FontWeight.w700)),
                        ),
                        title: Text(movementReasonLabel(m.reason), style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text([
                          if (m.imei1 != null || m.serialNumber != null) (m.imei1 ?? m.serialNumber)!,
                          if (m.note != null && m.note!.isNotEmpty) m.note!,
                          [
                            if (m.createdAt != null) DateFormat('dd-MM-yy HH:mm').format(m.createdAt!.toLocal()),
                            if (m.userName != null) m.userName!,
                          ].join(' · '),
                        ].join('\n')),
                        trailing: m.unitCost != null
                            ? Text(CurrencyFormatter.formatToRupiah(m.unitCost!), style: Theme.of(context).textTheme.labelSmall)
                            : null,
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
