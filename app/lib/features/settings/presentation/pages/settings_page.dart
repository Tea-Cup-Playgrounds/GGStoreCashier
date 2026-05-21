import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gg_store_cashier/core/router/app_router.dart';
import 'package:gg_store_cashier/core/provider/auth_provider.dart';
import 'package:gg_store_cashier/core/router/role_guard.dart';
import '../../../../core/theme/app_theme.dart';
import 'package:go_router/go_router.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final isKaryawan = user?.isEmployee ?? false;
    final isAdminOrAbove = RoleGuard.isAdminOrAbove(user);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _StoreProfileHeader(),
            const SizedBox(height: 28),
            const _SectionLabel('Store'),
            const SizedBox(height: 8),
            _SettingsGroup(tiles: [
              _SettingsTile(
                title: 'Store Profile',
                subtitle: 'Profil toko utama Anda',
                icon: Icons.storefront_outlined,
                onTap: () {},
              ),
              if (isAdminOrAbove)
                _SettingsTile(
                  title: RoleGuard.isSuperAdmin(user) ? 'Branch Management' : 'My Branch',
                  subtitle:
                      RoleGuard.isSuperAdmin(user) ? 'Lihat dan kelola semua cabang' : 'Edit informasi cabang Anda',
                  icon: Icons.business_outlined,
                  onTap: () {
                    final branchId = user?.branchId ?? 0;
                    context.push(
                      AppRouter.branchEdit.replaceFirst(':id', '$branchId'),
                    );
                  },
                ),
            ]),
            const SizedBox(height: 28),
            const _SectionLabel('Devices'),
            const SizedBox(height: 8),
            _SettingsGroup(tiles: [
              _SettingsTile(
                title: 'Barcode Scanner',
                subtitle: 'Zebra DS9308 - Terhubung',
                icon: Icons.qr_code_scanner,
                statusColor: AppTheme.success,
                onTap: () => context.push(AppRouter.scannerDevices),
              ),
              _SettingsTile(
                title: 'Receipt Printer',
                subtitle: 'Epson TM-T88VI - Tidak terhubung',
                icon: Icons.print_outlined,
                statusColor: AppTheme.mutedForeground,
                onTap: () => context.push(AppRouter.printerDevices),
              ),
            ]),
            const SizedBox(height: 28),
            const _SectionLabel('Preferences'),
            const SizedBox(height: 8),
            _SettingsGroup(tiles: [
              _SettingsTile(
                title: 'Notifications',
                subtitle: 'Push & notifikasi peringatan',
                icon: Icons.notifications_none_outlined,
                onTap: () {},
              ),
              _SettingsTile(
                title: 'Appearance',
                subtitle: 'Tema & tampilan',
                icon: Icons.palette_outlined,
                onTap: () => context.push(AppRouter.apprearance),
              ),
            ]),
            const SizedBox(height: 28),
            const _SectionLabel('Support'),
            const SizedBox(height: 8),
            _SettingsGroup(tiles: [
              if (!isKaryawan) ...[
                _SettingsTile(
                  title: 'User Management',
                  subtitle: 'Kelola pengguna dan hak akses',
                  icon: Icons.people_outline,
                  onTap: () => context.push(AppRouter.userManagement),
                ),
                _SettingsTile(
                  title: 'Vouchers',
                  subtitle: 'Buat dan kelola voucher diskon',
                  icon: Icons.local_offer_outlined,
                  onTap: () => context.push(AppRouter.voucherManagement),
                ),
              ],
              _SettingsTile(
                title: 'Privacy & Security',
                subtitle: 'Kata sandi, autentikasi dua faktor',
                icon: Icons.security_outlined,
                onTap: () {},
              ),
              _SettingsTile(
                title: 'Help Center',
                subtitle: 'FAQ, hubungi dukungan',
                icon: Icons.help_outline,
                onTap: () {},
              ),
            ]),
            const SizedBox(height: 32),
            _SignOutButton(ref: ref),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'Versi 1.0.0',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

// ── Settings group ────────────────────────────────────────────────────────────

class _SettingsGroup extends StatelessWidget {
  final List<Widget> tiles;
  const _SettingsGroup({required this.tiles});

  @override
  Widget build(BuildContext context) {
    final visibleTiles = tiles.whereType<_SettingsTile>().toList();
    if (visibleTiles.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 0.8,
        ),
        boxShadow: Theme.of(context).brightness == Brightness.light
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Column(
        children: [
          for (int i = 0; i < visibleTiles.length; i++) ...[
            visibleTiles[i],
            if (i < visibleTiles.length - 1)
              Divider(
                height: 1,
                indent: 56,
                endIndent: 0,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
          ],
        ],
      ),
    );
  }
}

// ── Settings tile ─────────────────────────────────────────────────────────────

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
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: cs.onSurfaceVariant),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
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
            if (statusColor != null)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Store profile header ──────────────────────────────────────────────────────

class _StoreProfileHeader extends StatelessWidget {
  const _StoreProfileHeader();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
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
              : [cs.primaryContainer, cs.secondaryContainer, cs.surface],
        ),
        border: Border.all(color: cs.outlineVariant, width: 0.8),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Row(
        children: [
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
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Flagship Store', style: Theme.of(context).textTheme.headlineSmall),
                Text(
                  'Cabang Downtown',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.gold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'ID Toko: STORE001',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.gold,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sign out button ───────────────────────────────────────────────────────────

class _SignOutButton extends StatefulWidget {
  final WidgetRef ref;
  const _SignOutButton({required this.ref});

  @override
  State<_SignOutButton> createState() => _SignOutButtonState();
}

class _SignOutButtonState extends State<_SignOutButton> {
  bool _isLoading = false;

  Future<void> _handleSignOut() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _SignOutDialog(isLoading: _isLoading),
    );

    if (shouldLogout == true && mounted) {
      setState(() => _isLoading = true);
      await widget.ref.read(authProvider.notifier).logout();
      if (mounted) {
        setState(() => _isLoading = false);
        context.go(AppRouter.login);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.destructive.withValues(alpha: 0.25),
          width: 0.8,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _isLoading ? null : _handleSignOut,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.destructive.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(8),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.destructive,
                        ),
                      )
                    : const Icon(
                        Icons.logout_rounded,
                        size: 20,
                        color: AppTheme.destructive,
                      ),
              ),
              const SizedBox(width: 14),
              Text(
                _isLoading ? 'Keluar...' : 'Sign Out',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppTheme.destructive,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sign out dialog ───────────────────────────────────────────────────────────

class _SignOutDialog extends StatefulWidget {
  final bool isLoading;
  const _SignOutDialog({required this.isLoading});

  @override
  State<_SignOutDialog> createState() => _SignOutDialogState();
}

class _SignOutDialogState extends State<_SignOutDialog> {
  bool _confirming = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sign Out'),
      content: const Text('Apakah Anda yakin ingin keluar dari akun ini?'),
      actions: [
        TextButton(
          onPressed: _confirming ? null : () => Navigator.of(context).pop(false),
          child: const Text('Batal'),
        ),
        TextButton(
          onPressed: _confirming
              ? null
              : () async {
                  setState(() => _confirming = true);
                  Navigator.of(context).pop(true);
                },
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.destructive,
          ),
          child: _confirming
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.destructive,
                  ),
                )
              : const Text('Keluar'),
        ),
      ],
    );
  }
}
