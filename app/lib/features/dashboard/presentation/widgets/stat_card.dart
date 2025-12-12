import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final double? trend;
  final bool isPositive;
  final bool isHighlighted;

  const StatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.trend,
    this.isPositive = true,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isHighlighted ? AppTheme.gold.withOpacity(0.1) : AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isHighlighted ? AppTheme.gold.withOpacity(0.3) : AppTheme.border,
        ),
        boxShadow: isHighlighted
            ? [
                BoxShadow(
                  color: AppTheme.gold.withOpacity(0.1),
                  blurRadius: 20,
                  spreadRadius: 0,
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isHighlighted
                      ? AppTheme.gold.withOpacity(0.2)
                      : AppTheme.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: isHighlighted ? AppTheme.gold : AppTheme.mutedForeground,
                ),
              ),
              const Spacer(),
              if (trend != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isPositive
                        ? AppTheme.success.withOpacity(0.1)
                        : AppTheme.destructive.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPositive ? Icons.trending_up : Icons.trending_down,
                        size: 12,
                        color: isPositive ? AppTheme.success : AppTheme.destructive,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${trend!.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isPositive ? AppTheme.success : AppTheme.destructive,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: isHighlighted ? AppTheme.gold : AppTheme.foreground,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppTheme.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}