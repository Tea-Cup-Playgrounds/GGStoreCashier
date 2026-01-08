import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gg_store_cashier/core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import 'package:go_router/go_router.dart';

// Ganti StatelessWidget menjadi ConsumerWidget untuk arsitektur Riverpod
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  // Widget Pembantu untuk Judul Bagian
  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall!.copyWith(
            letterSpacing: 0.8,
          ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. HEADER PROFILE (Flagship Store)
              const _StoreProfileHeader(),
              const SizedBox(height: 32.0),

              // 2. BAGIAN STORE
              _buildSectionTitle(context, 'Store'),
              const SizedBox(height: 8.0),
              _SettingsTile(
                title: 'Store Profile',
                subtitle: 'Flagship Store - Downtown',
                icon: Icons.storefront_outlined,
                onTap: () {
                  // TODO: Implement navigation
                },
              ),
              const SizedBox(height: 32.0),

              // 3. BAGIAN DEVICES
              _buildSectionTitle(context, 'Devices'),
              const SizedBox(height: 8.0),
              _SettingsTile(
                title: 'Barcode Scanner',
                subtitle: 'Zebra DS9308 - Connected',
                icon: Icons.qr_code_scanner,
                statusColor: AppTheme.success,
                onTap: () {
                  context.push(AppRouter.scannerDevices);
                },
              ),
              const SizedBox(height: 8.0),
              _SettingsTile(
                title: 'Receipt Printer',
                subtitle: 'Epson TM-T88VI - Disconnected',
                icon: Icons.print_outlined,
                statusColor: AppTheme.mutedForeground,
                onTap: () {
                  context.push(AppRouter.printerDevices);
                },
              ),
              const SizedBox(height: 32.0),

              // 4. BAGIAN PREFERENCES
              _buildSectionTitle(context, 'Preferences'),
              const SizedBox(height: 8.0),
              _SettingsTile(
                title: 'Notifications',
                subtitle: 'Push & alerts',
                icon: Icons.notifications_none_outlined,
                onTap: () {
                  // TODO: Implement navigation
                },
              ),
              const SizedBox(height: 8.0),
              _SettingsTile(
                title: 'Appearance',
                subtitle: 'Dark mode',
                icon: Icons.light_mode_outlined,
                onTap: () {
                  context.push(AppRouter.apprearance);
                },
              ),
              const SizedBox(height: 32.0),

              // 5. BAGIAN SUPPORT
              _buildSectionTitle(context, 'Support'),
              const SizedBox(height: 8.0),
              _SettingsTile(
                title: 'Privacy & Security',
                subtitle: 'Password, 2FA',
                icon: Icons.security_outlined,
                onTap: () {
                  // TODO: Implement navigation
                },
              ),
              const SizedBox(height: 8.0),
              _SettingsTile(
                title: 'Help Center',
                subtitle: 'FAQs, contact support',
                icon: Icons.help_outline,
                onTap: () {
                  // TODO: Implement navigation
                },
              ),
              const SizedBox(height: 32.0),

              // 6. SIGN OUT BUTTON
              Center(
                child: TextButton.icon(
                  onPressed: () {
                    context.pushNamed("login");
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign Out'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.destructive, // Warna merah
                  ),
                ),
              ),

              const SizedBox(height: 16.0),
              Center(
                child: Text(
                  'Version 1.0.0',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 24.0),
            ],
          ),
        ),
      ),
    );
  }
}

// =========================================================================
// WIDGET PEMBANTU
// =========================================================================

// Widget Kustom untuk Header Profil Toko (Dengan Gradient)
class _StoreProfileHeader extends StatelessWidget {
  const _StoreProfileHeader();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  const Color(0xFF302805),
                  const Color(0xFF221C05),
                  const Color(0xFF1F1F1F),
                ]
              : [
                  scheme.primaryContainer,
                  scheme.secondaryContainer,
                  scheme.surface,
                ],
        ),
        border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant, width: 0.5),
      ),
      child: Row(
        children: [
          // Avatar (FS)
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.gold,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                'FS',
                style: Theme.of(context).textTheme.titleLarge!.copyWith(
                      color: AppTheme.background,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Detail Toko
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Flagship Store',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                'Downtown Branch',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              // Store ID
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.secondary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Store ID: STORE001',
                  style: Theme.of(context).textTheme.bodySmall!.copyWith(
                        color: AppTheme.goldLight,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Pembungkus List Settings
class _SettingsTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color? statusColor;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.statusColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      color: colors.secondary,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outline,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(
          icon,
          color: colors.onSurface.withOpacity(0.6),
          size: 24,
        ),
        title: Text(
          title,
          style: theme.textTheme.titleMedium,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            subtitle,
            style: theme.textTheme.bodySmall,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (statusColor != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: colors.onSurface.withOpacity(0.4),
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
