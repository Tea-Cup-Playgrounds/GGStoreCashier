import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/models/product.dart';
import '../../../../core/helper/currency_formatter.dart';
import '../../../../core/services/product_service.dart';

class ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onAdd;

  const ProductCard({
    super.key,
    required this.product,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    const double infoHeight = 96.0;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.outlineVariant,
          width: isDark ? 0.8 : 1.0,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final imageHeight = (constraints.maxHeight - infoHeight).clamp(40.0, constraints.maxWidth.toDouble());

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Image ────────────────────────────────────────────────────
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: imageHeight,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Background tint
                      Container(
                        color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F4F0),
                      ),
                      product.image != null && product.image!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: ProductService.getProductImageUrl(product.image),
                              fit: BoxFit.cover,
                              placeholder: (context, url) => const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.gold,
                                ),
                              ),
                              errorWidget: (context, url, error) => Image.asset(
                                ProductService.getPlaceholderImage(),
                                fit: BoxFit.cover,
                              ),
                            )
                          : Image.asset(
                              ProductService.getPlaceholderImage(),
                              fit: BoxFit.cover,
                            ),

                      // Stock badge
                      if (product.isLowStock)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: product.isOutOfStock ? AppTheme.destructive : AppTheme.warning,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              product.isOutOfStock ? 'Habis' : 'Stok Tipis',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),

                      // Category badge
                      if (product.category != null)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              product.category!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),

                      // Out of stock overlay
                      if (product.isOutOfStock)
                        Container(
                          color: Colors.black.withValues(alpha: 0.45),
                          child: const Center(
                            child: Icon(Icons.block, color: Colors.white54, size: 32),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // ── Info ─────────────────────────────────────────────────────
              SizedBox(
                height: infoHeight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        product.name,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              CurrencyFormatter.formatToRupiah(product.sellPrice),
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: AppTheme.gold,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                          GestureDetector(
                            onTap: product.isOutOfStock ? null : onAdd,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: product.isOutOfStock ? cs.outlineVariant : AppTheme.gold,
                                shape: BoxShape.circle,
                                boxShadow: product.isOutOfStock
                                    ? null
                                    : [
                                        BoxShadow(
                                          color: AppTheme.gold.withValues(alpha: 0.4),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                              ),
                              child: Icon(
                                Icons.add,
                                size: 15,
                                color:
                                    product.isOutOfStock ? cs.onSurfaceVariant : (isDark ? Colors.black : Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
