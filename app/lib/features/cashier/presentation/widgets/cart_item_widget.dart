import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/models/cart_item.dart';
import '../../../../core/helper/currency_formatter.dart';
import '../../../../core/services/product_service.dart';
import '../../../../shared/widgets/quantity_picker_modal.dart';

class CartItemWidget extends StatelessWidget {
  final CartItem cartItem;
  final Function(String) onIncrease;
  final Function(String) onDecrease;
  final Function(String) onRemove;
  final Function(String, int)? onQuantityChanged;

  const CartItemWidget({
    super.key,
    required this.cartItem,
    required this.onIncrease,
    required this.onDecrease,
    required this.onRemove,
    this.onQuantityChanged,
  });

  Future<void> _showDeleteConfirm(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Item'),
        content: Text(
          'Hapus "${cartItem.product.name}" dari keranjang?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.destructive,
            ),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      onRemove(cartItem.id);
    }
  }

  Future<void> _showQtyPicker(BuildContext context) async {
    final product = cartItem.product;
    final qty = await showQuantityPickerModal(
      context,
      productName: product.name,
      unitPrice: cartItem.price,
      maxStock: product.stock,
      initialQty: cartItem.quantity,
      imageUrl: product.image,
    );
    if (qty != null && qty > 0) {
      onQuantityChanged?.call(cartItem.id, qty);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final product = cartItem.product;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant, width: 0.8),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Product image ─────────────────────────────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 56,
                height: 56,
                child: product.image != null && product.image!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: ProductService.getProductImageUrl(product.image),
                        fit: BoxFit.cover,
                        placeholder: (_, __) => _placeholder(isDark),
                        errorWidget: (_, __, ___) => _placeholder(isDark),
                      )
                    : _placeholder(isDark),
              ),
            ),
            const SizedBox(width: 12),

            // ── Name + price ──────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${CurrencyFormatter.formatToRupiah(cartItem.price)} / item',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    CurrencyFormatter.formatToRupiah(cartItem.subtotal),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppTheme.gold,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // ── Controls column ───────────────────────────────────────
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // +/- with tappable qty number
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2A2A2A) : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cs.outlineVariant, width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _QtyBtn(
                        icon: Icons.remove_rounded,
                        onTap: () {
                          if (cartItem.quantity == 1) {
                            _showDeleteConfirm(context);
                          } else {
                            onDecrease(cartItem.id);
                          }
                        },
                      ),
                      // Tappable qty number → opens picker modal
                      GestureDetector(
                        onTap: () => _showQtyPicker(context),
                        child: Container(
                          width: 36,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppTheme.gold.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${cartItem.quantity}',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.gold,
                                ),
                          ),
                        ),
                      ),
                      _QtyBtn(
                        icon: Icons.add_rounded,
                        onTap: () => onIncrease(cartItem.id),
                        isPrimary: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),

                // Delete button
                GestureDetector(
                  onTap: () => _showDeleteConfirm(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.destructive.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppTheme.destructive.withValues(alpha: 0.2),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.delete_outline_rounded,
                          size: 16,
                          color: AppTheme.destructive.withValues(alpha: 0.8),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Hapus',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: AppTheme.destructive.withValues(alpha: 0.8),
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(bool isDark) => Container(
        color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF0EDE6),
        child: const Center(
          child: Icon(Icons.image_outlined, color: AppTheme.mutedForeground, size: 22),
        ),
      );
}

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isPrimary;

  const _QtyBtn({
    required this.icon,
    required this.onTap,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: isPrimary ? AppTheme.gold : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 16,
          color: isPrimary
              ? (Theme.of(context).brightness == Brightness.dark ? Colors.black : Colors.white)
              : Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}
