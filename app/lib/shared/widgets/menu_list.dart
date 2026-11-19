import 'package:material_ui/material_ui.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';

// Menu-style screens (Keuangan, Pengaturan): gold group labels over separate bordered tiles.

/// Upper-case gold label above a group of [MenuTile]s.
class MenuGroupLabel extends StatelessWidget {
  final String text;
  const MenuGroupLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
        child: Semantics(
          header: true,
          child: Text(text.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(letterSpacing: 1.2, fontWeight: FontWeight.w700, color: AppTheme.gold)),
        ),
      );
}

/// A tappable menu entry: icon badge, title, one-line description, chevron.
///
/// [statusColor] puts a coloured dot before the subtitle when the subtitle reports a state
/// (printer connected, transactions waiting). [destructive] is for sign-out style actions: red,
/// and no chevron because it does not open a page.
class MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Color? statusColor;
  final bool destructive;
  final Widget? leading;

  const MenuTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.statusColor,
    this.destructive = false,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = destructive ? AppTheme.destructive : AppTheme.gold;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: destructive ? AppTheme.destructive.withValues(alpha: 0.35) : cs.outlineVariant, width: 0.8),
          ),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Center(child: leading ?? Icon(icon, color: accent)),
          ),
          title: Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: destructive ? AppTheme.destructive : null)),
          subtitle: statusColor == null
              ? Text(subtitle)
              : Row(children: [
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                  ),
                  Expanded(child: Text(subtitle)),
                ]),
          trailing: destructive ? null : const Icon(Icons.chevron_right_rounded),
          onTap: onTap,
        ),
      ),
    );
  }
}
