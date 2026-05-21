import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_theme.dart';
import '../../core/helper/currency_formatter.dart';
import '../../core/services/product_service.dart';

/// Shows a bottom sheet modal to pick quantity before adding to cart.
/// Returns the chosen quantity, or null if dismissed.
Future<int?> showQuantityPickerModal(
  BuildContext context, {
  required String productName,
  required double unitPrice,
  required int maxStock,
  int initialQty = 1,
  String? imageUrl,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _QuantityPickerSheet(
      productName: productName,
      unitPrice: unitPrice,
      maxStock: maxStock,
      initialQty: initialQty,
      imageUrl: imageUrl,
    ),
  );
}

class _QuantityPickerSheet extends StatefulWidget {
  final String productName;
  final double unitPrice;
  final int maxStock;
  final int initialQty;
  final String? imageUrl;

  const _QuantityPickerSheet({
    required this.productName,
    required this.unitPrice,
    required this.maxStock,
    required this.initialQty,
    this.imageUrl,
  });

  @override
  State<_QuantityPickerSheet> createState() => _QuantityPickerSheetState();
}

class _QuantityPickerSheetState extends State<_QuantityPickerSheet> {
  late int _qty;
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _qty = widget.initialQty.clamp(1, widget.maxStock);
    _controller = TextEditingController(text: '$_qty');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _fallbackIcon(bool isDark) => Container(
        color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF0EDE6),
        child: const Center(
          child: Icon(Icons.shopping_bag_outlined, color: AppTheme.gold, size: 24),
        ),
      );

  void _setQty(int value) {
    final clamped = value.clamp(1, widget.maxStock);
    setState(() {
      _qty = clamped;
      _controller.text = '$clamped';
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final subtotal = widget.unitPrice * _qty;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.15),
              blurRadius: 24,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Handle ────────────────────────────────────────────────
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Product info ──────────────────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product image or fallback icon
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: widget.imageUrl != null && widget.imageUrl!.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: ProductService.getProductImageUrl(widget.imageUrl),
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Container(
                                  color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF0EDE6),
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppTheme.gold,
                                    ),
                                  ),
                                ),
                                errorWidget: (_, __, ___) => _fallbackIcon(isDark),
                              )
                            : _fallbackIcon(isDark),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.productName,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                CurrencyFormatter.formatToRupiah(widget.unitPrice),
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: AppTheme.gold,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              Text(
                                ' / item',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Stock badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: widget.maxStock <= 5
                            ? AppTheme.warning.withValues(alpha: 0.12)
                            : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: widget.maxStock <= 5 ? AppTheme.warning.withValues(alpha: 0.3) : cs.outlineVariant,
                        ),
                      ),
                      child: Text(
                        'Stok: ${widget.maxStock}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: widget.maxStock <= 5 ? AppTheme.warning : cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // ── Divider ───────────────────────────────────────────────
                Divider(color: cs.outlineVariant, height: 1),
                const SizedBox(height: 24),

                // ── Quantity row ──────────────────────────────────────────
                Row(
                  children: [
                    Text(
                      'Jumlah',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                    const Spacer(),
                    _QtyButton(
                      icon: Icons.remove_rounded,
                      onTap: _qty > 1 ? () => _setQty(_qty - 1) : null,
                    ),
                    const SizedBox(width: 12),
                    // Qty display / input
                    GestureDetector(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => _QtyInputDialog(
                            current: _qty,
                            max: widget.maxStock,
                            onConfirm: (v) => _setQty(v),
                          ),
                        );
                      },
                      child: Container(
                        width: 64,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2A2A2A) : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cs.outlineVariant),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '$_qty',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _QtyButton(
                      icon: Icons.add_rounded,
                      onTap: _qty < widget.maxStock ? () => _setQty(_qty + 1) : null,
                      isPrimary: true,
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ── Subtotal card ─────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.gold.withValues(alpha: 0.07) : AppTheme.gold.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.gold.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Subtotal',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$_qty item${_qty > 1 ? 's' : ''}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                      Text(
                        CurrencyFormatter.formatToRupiah(subtotal),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: AppTheme.gold,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Add to cart button ────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(_qty),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.gold,
                      foregroundColor: isDark ? Colors.black : Colors.white,
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.shopping_cart_outlined, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          'Tambah ke Keranjang',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
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

// ── Qty +/- button ────────────────────────────────────────────────────────────

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool isPrimary;

  const _QtyButton({
    required this.icon,
    this.onTap,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onTap != null;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: !enabled
              ? cs.surfaceContainerHighest.withValues(alpha: 0.5)
              : isPrimary
                  ? AppTheme.gold
                  : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: !enabled
                ? cs.outlineVariant.withValues(alpha: 0.5)
                : isPrimary
                    ? AppTheme.gold
                    : cs.outlineVariant,
          ),
          boxShadow: enabled && isPrimary
              ? [
                  BoxShadow(
                    color: AppTheme.gold.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Icon(
          icon,
          size: 20,
          color: !enabled
              ? cs.onSurfaceVariant.withValues(alpha: 0.3)
              : isPrimary
                  ? (cs.brightness == Brightness.dark ? Colors.black : Colors.white)
                  : cs.onSurface,
        ),
      ),
    );
  }
}

// ── Qty input dialog (tap on number to type) ──────────────────────────────────

class _QtyInputDialog extends StatefulWidget {
  final int current;
  final int max;
  final ValueChanged<int> onConfirm;

  const _QtyInputDialog({
    required this.current,
    required this.max,
    required this.onConfirm,
  });

  @override
  State<_QtyInputDialog> createState() => _QtyInputDialogState();
}

class _QtyInputDialogState extends State<_QtyInputDialog> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: '${widget.current}');
    _ctrl.selection = TextSelection(baseOffset: 0, extentOffset: _ctrl.text.length);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Masukkan Jumlah'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          hintText: '1 – ${widget.max}',
          suffixText: 'Maks ${widget.max}',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        TextButton(
          onPressed: () {
            final v = int.tryParse(_ctrl.text) ?? widget.current;
            widget.onConfirm(v.clamp(1, widget.max));
            Navigator.of(context).pop();
          },
          child: const Text('OK'),
        ),
      ],
    );
  }
}
