import 'package:flutter/material.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';

/// Small colored label for document states (draft, sent, paid, ...).
class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const StatusBadge(this.label, {super.key, required this.color});

  /// Colors used across warehouse documents.
  static Color colorFor(String status) => switch (status) {
        'posted' || 'received' || 'approved' || 'paid' => AppTheme.success,
        'sent' || 'counting' || 'partial' => AppTheme.warning,
        'partially_received' || 'unpaid' => AppTheme.destructive,
        'cancelled' => Colors.grey,
        _ => AppTheme.goldDark,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700)),
    );
  }
}

/// A titled white card used on the warehouse detail pages.
class SectionCard extends StatelessWidget {
  final String? title;
  final Widget child;
  final Widget? trailing;

  const SectionCard({super.key, this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Row(children: [
              Expanded(
                child: Text(title!, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
              if (trailing != null) trailing!,
            ]),
            const SizedBox(height: 8),
          ],
          child,
        ],
      ),
    );
  }
}
