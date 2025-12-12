import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class CouponCard extends StatelessWidget {
  final String code;
  final String discount;
  final String description;
  final String? expiresAt;
  final bool isApplied;
  final VoidCallback? onTap;

  const CouponCard({
    super.key,
    required this.code,
    required this.discount,
    required this.description,
    this.expiresAt,
    this.isApplied = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isApplied ? AppTheme.success.withOpacity(0.1) : AppTheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isApplied ? AppTheme.success : AppTheme.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isApplied 
                    ? AppTheme.success.withOpacity(0.2)
                    : AppTheme.gold.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isApplied ? Icons.check_circle : Icons.local_offer_outlined,
                color: isApplied ? AppTheme.success : AppTheme.gold,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        code,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isApplied ? AppTheme.success : AppTheme.gold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isApplied 
                              ? AppTheme.success 
                              : AppTheme.gold,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          discount,
                          style: const TextStyle(
                            color: AppTheme.background,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.mutedForeground,
                    ),
                  ),
                  if (expiresAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Expires: $expiresAt',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.mutedForeground,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (isApplied)
              const Icon(
                Icons.check_circle,
                color: AppTheme.success,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}