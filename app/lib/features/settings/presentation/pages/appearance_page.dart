import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gg_store_cashier/core/provider/theme_provider.dart';
import '../../../../core/theme/app_theme.dart';

class AppearancePage extends ConsumerWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        title: const Text('Appearance'),
        backgroundColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Preview card ───────────────────────────────────────────────
            _PreviewCard(isDark: isDark),
            const SizedBox(height: 24),

            // ── Theme options ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 10),
              child: Text(
                'THEME',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                    ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outlineVariant, width: 0.8),
                boxShadow: isDark
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Column(
                children: [
                  _ThemeOptionTile(
                    title: 'Light',
                    subtitle: 'Clean and bright interface',
                    icon: Icons.light_mode_outlined,
                    isSelected: !isDark,
                    onTap: () => ref.read(themeProvider.notifier).setTheme(ThemeMode.light),
                  ),
                  Divider(
                    height: 1,
                    indent: 56,
                    color: cs.outlineVariant,
                  ),
                  _ThemeOptionTile(
                    title: 'Dark',
                    subtitle: 'Easy on the eyes at night',
                    icon: Icons.dark_mode_outlined,
                    isSelected: isDark,
                    onTap: () => ref.read(themeProvider.notifier).setTheme(ThemeMode.dark),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Preview card ──────────────────────────────────────────────────────────────

class _PreviewCard extends StatelessWidget {
  final bool isDark;
  const _PreviewCard({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF302805), const Color(0xFF1F1F1F)]
              : [cs.primaryContainer, cs.secondaryContainer],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant, width: 0.8),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.gold.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.gold.withOpacity(0.4)),
            ),
            child: Icon(
              isDark ? Icons.nights_stay_rounded : Icons.wb_sunny_rounded,
              color: AppTheme.gold,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isDark ? 'Dark Mode' : 'Light Mode',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  isDark ? 'Currently active' : 'Currently active',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.gold.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Active',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppTheme.gold,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Theme option tile ─────────────────────────────────────────────────────────

class _ThemeOptionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeOptionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.gold.withOpacity(0.15) : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 20,
                color: isSelected ? AppTheme.gold : cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: isSelected ? AppTheme.gold : null,
                          fontWeight: isSelected ? FontWeight.w600 : null,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppTheme.gold : cs.outlineVariant,
                  width: isSelected ? 2 : 1.5,
                ),
                color: isSelected ? AppTheme.gold.withOpacity(0.15) : Colors.transparent,
              ),
              child: isSelected
                  ? const Center(
                      child: Icon(Icons.check, size: 13, color: AppTheme.gold),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
