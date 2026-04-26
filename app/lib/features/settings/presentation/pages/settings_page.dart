import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gg_store_cashier/core/router/app_router.dart';
import 'package:gg_store_cashier/core/provider/auth_provider.dart';
import 'package:gg_store_cashier/core/router/role_guard.dart';
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
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final isKaryawan = user?.isEmployee ?? false;
    final isAdminOrAbove = RoleGuard.isAdminOrAbove(user);
    
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Pengaturan'),
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
              _buildSectionTitle(context, 'Toko'),
              const SizedBox(height: 8.0),
              _SettingsTile(
                title: 'Profil Toko',
                subtitle: 'Flagship Store - Downtown',
                icon: Icons.storefront_outlined,
                onTap: () {
                  // TODO: Implement navigation
                },
              ),
              // Branch edit tile — visible to admin and superadmin only
              if (isAdminOrAbove) ...[
                const SizedBox(height: 8.0),
                _SettingsTile(
                  title: RoleGuard.isSuperAdmin(user)
                      ? 'Manajemen Cabang'
                      : 'Cabang Saya',
                  subtitle: RoleGuard.isSuperAdmin(user)
                      ? 'Lihat dan edit semua cabang'
                      : 'Edit informasi cabang Anda',
                  icon: Icons.business_outlined,
                  onTap: () {
                    final branchId = user?.branchId ?? 0;
                    context.push(
                      AppRouter.branchEdit.replaceFirst(':id', '$branchId'),
                    );
                  },
                ),
              ],
              const SizedBox(height: 32.0),

              // 3. BAGIAN DEVICES
              _buildSectionTitle(context, 'Perangkat'),
              const SizedBox(height: 8.0),
              _SettingsTile(
                title: 'Manajer Perangkat',
                subtitle: 'Printer, scanner & perangkat nirkabel',
                icon: Icons.devices_outlined,
                onTap: () {
                  context.push(AppRouter.deviceManager);
                },
              ),
              if (RoleGuard.isSuperAdmin(user)) ...[
                const SizedBox(height: 8.0),
                _SettingsTile(
                  title: 'Editor Struk',
                  subtitle: 'Sesuaikan tata letak & ukuran kertas struk',
                  icon: Icons.receipt_long_outlined,
                  onTap: () {
                    context.push(AppRouter.receiptEditor);
                  },
                ),
              ],
              const SizedBox(height: 32.0),

              // 4. BAGIAN PREFERENCES
              _buildSectionTitle(context, 'Preferensi'),
              const SizedBox(height: 8.0),
              _SettingsTile(
                title: 'Notifikasi',
                subtitle: 'Push & peringatan',
                icon: Icons.notifications_none_outlined,
                onTap: () {
                  // TODO: Implement navigation
                },
              ),
              const SizedBox(height: 8.0),
              _SettingsTile(
                title: 'Tampilan',
                subtitle: 'Mode gelap',
                icon: Icons.light_mode_outlined,
                onTap: () {
                  context.push(AppRouter.apprearance);
                },
              ),
              const SizedBox(height: 32.0),

              // 5. BAGIAN SUPPORT
              _buildSectionTitle(context, 'Dukungan'),
              const SizedBox(height: 8.0),
              // Hide "User Management" for karyawan
              if (!isKaryawan) ...[
                _SettingsTile(
                  title: 'Manajemen Pengguna',
                  subtitle: 'Kelola pengguna dan hak akses',
                  icon: Icons.people_outline,
                  onTap: () {
                    context.push(AppRouter.userManagement);
                  },
                ),
                const SizedBox(height: 8.0),
                _SettingsTile(
                  title: 'Voucher',
                  subtitle: 'Buat dan kelola voucher diskon',
                  icon: Icons.local_offer_outlined,
                  onTap: () {
                    context.push(AppRouter.voucherManagement);
                  },
                ),
                const SizedBox(height: 8.0),
              ],
              _SettingsTile(
                title: 'Privasi & Keamanan',
                subtitle: 'Password, 2FA',
                icon: Icons.security_outlined,
                onTap: () {
                  // TODO: Implement navigation
                },
              ),
              const SizedBox(height: 8.0),
              _SettingsTile(
                title: 'Pusat Bantuan',
                subtitle: 'FAQ, hubungi dukungan',
                icon: Icons.help_outline,
                onTap: () {
                  // TODO: Implement navigation
                },
              ),
              const SizedBox(height: 32.0),

              // 6. SIGN OUT BUTTON
              Center(
                child: TextButton.icon(
                  onPressed: () async {
                    // Show confirmation dialog
                    final shouldLogout = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Keluar'),
                        content: const Text('Apakah Anda yakin ingin keluar?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Batal'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('Keluar'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.destructive,
                            ),
                          ),
                        ],
                      ),
                    );

                    if (shouldLogout == true) {
                      await ref.read(authProvider.notifier).logout();
                      if (context.mounted) {
                        context.go(AppRouter.login);
                      }
                    }
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Keluar'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.destructive, // Warna merah
                  ),
                ),
              ),

              const SizedBox(height: 16.0),
              Center(
                child: Text(
                  'Versi 1.0.0',
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
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Store ID: STORE001',
                  style: Theme.of(context).textTheme.bodySmall!.copyWith(
                        color: AppTheme.gold,
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
