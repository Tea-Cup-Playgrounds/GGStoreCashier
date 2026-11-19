import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gg_store_cashier/core/router/app_router.dart';
import 'package:gg_store_cashier/core/provider/auth_provider.dart';
import 'package:gg_store_cashier/core/provider/access_provider.dart';
import 'package:gg_store_cashier/core/models/access.dart';
import 'package:gg_store_cashier/core/models/branch.dart';
import 'package:gg_store_cashier/core/services/branch_service.dart';
import 'package:gg_store_cashier/core/services/offline_queue.dart';
import 'package:gg_store_cashier/features/devices/data/receipt_printer.dart';
import 'package:gg_store_cashier/features/warehouse/presentation/widgets/status_badge.dart';
import 'package:gg_store_cashier/shared/widgets/menu_list.dart';
import '../../../../core/theme/app_theme.dart';
import 'package:go_router/go_router.dart';

/// Pengaturan, laid out like Keuangan: who is signed in at the top, then grouped menus. Every role
/// sees the same structure; entries they may not use are left out rather than shown disabled.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final user = ref.watch(authProvider).user;
    final access = ref.watch(currentAccessProvider);
    final ownLocation = user?.defaultLocationId;
    // Owners pick which branch to edit; others edit their own location when allowed.
    final canEditBranches = access.isOwner || access.locationsFor('locations.manage') == null;
    final canEditOwnBranch = ownLocation != null && access.can('locations.manage', ownLocation);
    final unsynced = ref.watch(pendingOfflineCountProvider).valueOrNull ?? 0;
    final printer = ref.watch(printerSettingsProvider).valueOrNull;
    final canUsers = access.can('users.manage');
    final canVouchers = access.can('vouchers.manage');

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Pengaturan', style: TextStyle(fontWeight: FontWeight.w600)),
          Text('${access.roleLabel} · ${_locationSummary(access)}', style: Theme.of(context).textTheme.bodySmall),
        ]),
        backgroundColor: cs.surface,
        elevation: 0,
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _AccountCard(name: user?.name ?? '—', username: user?.username ?? '', access: access),
          if (canEditBranches || canEditOwnBranch) ...[
            const MenuGroupLabel('Toko'),
            MenuTile(
              icon: Icons.storefront_outlined,
              title: canEditBranches ? 'Cabang' : 'Cabang Saya',
              subtitle: canEditBranches ? 'Pilih cabang untuk mengubah nama, alamat, telepon' : 'Ubah nama, alamat dan telepon cabang Anda',
              onTap: () async {
                final branchId = canEditBranches ? await _pickBranch(context) : ownLocation;
                if (branchId == null || !context.mounted) return;
                context.push(AppRouter.branchEdit.replaceFirst(':id', '$branchId'));
              },
            ),
          ],
          const MenuGroupLabel('Perangkat'),
          MenuTile(
            icon: Icons.print_outlined,
            title: 'Printer Struk',
            subtitle: printer == null
                ? 'Memuat...'
                : printer.isConfigured
                    ? '${printer.label}${printer.autoPrint ? ' · cetak otomatis' : ''}'
                    : 'Belum diatur',
            statusColor: printer == null ? null : (printer.isConfigured ? AppTheme.success : AppTheme.warning),
            onTap: () => context.push(AppRouter.printerDevices),
          ),
          MenuTile(
            icon: Icons.receipt_long_outlined,
            title: 'Tampilan Struk',
            subtitle: 'Nama toko, alamat, catatan kaki, ukuran kertas',
            onTap: () => context.push(AppRouter.receiptEditor),
          ),
          MenuTile(
            icon: Icons.qr_code_scanner,
            title: 'Scanner Barcode',
            subtitle: 'Kamera HP atau scanner USB / Bluetooth',
            onTap: () => context.push(AppRouter.scannerDevices),
          ),
          const MenuGroupLabel('Aplikasi'),
          MenuTile(
            icon: Icons.cloud_upload_outlined,
            title: 'Sinkronisasi',
            subtitle: unsynced == 0 ? 'Semua transaksi sudah terkirim' : '$unsynced transaksi belum terkirim',
            statusColor: unsynced == 0 ? AppTheme.success : AppTheme.warning,
            onTap: () => context.push(AppRouter.syncQueue),
          ),
          MenuTile(
            icon: Icons.palette_outlined,
            title: 'Tampilan',
            subtitle: 'Tema terang atau gelap',
            onTap: () => context.push(AppRouter.apprearance),
          ),
          if (canUsers || canVouchers) ...[
            const MenuGroupLabel('Administrasi'),
            if (canUsers)
              MenuTile(
                icon: Icons.people_outline,
                title: 'Pengguna',
                subtitle: 'Tambah pengguna, atur peran per lokasi',
                onTap: () => context.push(AppRouter.userManagement),
              ),
            if (canVouchers)
              MenuTile(
                icon: Icons.local_offer_outlined,
                title: 'Voucher',
                subtitle: 'Buat dan kelola voucher diskon',
                onTap: () => context.push(AppRouter.voucherManagement),
              ),
          ],
          const MenuGroupLabel('Akun'),
          const _SignOutTile(),
          const SizedBox(height: 8),
          Center(
            child: Text('GG Store Cashier · versi 1.0.0',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

/// "Semua lokasi" for users with every location, else the locations they are assigned to.
String _locationSummary(UserAccess access) {
  if (access.isOwner || access.assignments.any((a) => a.locationId == null)) return 'Semua lokasi';
  final names = access.assignments.map((a) => a.locationName).whereType<String>().toSet();
  return names.isEmpty ? 'Tanpa lokasi' : names.join(', ');
}

// ── account ───────────────────────────────────────────────────────────────────

/// Who is signed in and where they may work: one row per role assignment.
class _AccountCard extends StatelessWidget {
  final String name;
  final String username;
  final UserAccess access;
  const _AccountCard({required this.name, required this.username, required this.access});

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.length == 1 ? parts.first.substring(0, 1) : '${parts.first[0]}${parts.last[0]}').toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final rows = access.isOwner
        ? const [('Owner', 'Semua lokasi')]
        : [for (final a in access.assignments) (a.roleName, a.locationName ?? 'Semua lokasi')];

    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: AppTheme.gold.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
            child: Center(
              child: Text(_initials, style: text.titleMedium?.copyWith(color: AppTheme.gold, fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (username.isNotEmpty) Text('@$username', style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
        ]),
        const Divider(height: 24),
        if (rows.isEmpty)
          Text('Belum punya peran. Minta admin memberi akses.', style: text.bodySmall?.copyWith(color: AppTheme.warning))
        else
          for (final (role, location) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Icon(location == 'Semua lokasi' ? Icons.apartment_outlined : Icons.storefront_outlined, size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(child: Text(location, style: const TextStyle(fontWeight: FontWeight.w500))),
                Text(role, style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
      ]),
    );
  }
}

/// Lets an owner choose which branch to edit. Returns its id, or null when dismissed or unavailable.
Future<int?> _pickBranch(BuildContext context) async {
  List<Branch> branches;
  try {
    branches = await BranchService.getBranches();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal memuat daftar cabang. Periksa koneksi lalu coba lagi.')));
    }
    return null;
  }
  if (!context.mounted) return null;
  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const ListTile(title: Text('Pilih cabang', style: TextStyle(fontWeight: FontWeight.w600))),
          for (final b in branches)
            ListTile(
              leading: const Icon(Icons.storefront_outlined, color: AppTheme.gold),
              title: Text(b.name),
              subtitle: b.address == null || b.address!.isEmpty ? null : Text(b.address!),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).pop(b.id),
            ),
        ],
      ),
    ),
  );
}

// ── sign out ──────────────────────────────────────────────────────────────────

class _SignOutTile extends ConsumerStatefulWidget {
  const _SignOutTile();

  @override
  ConsumerState<_SignOutTile> createState() => _SignOutTileState();
}

class _SignOutTileState extends ConsumerState<_SignOutTile> {
  bool _isLoading = false;

  Future<void> _handleSignOut() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _SignOutDialog(),
    );

    if (shouldLogout == true && mounted) {
      setState(() => _isLoading = true);
      await ref.read(authProvider.notifier).logout();
      if (mounted) {
        setState(() => _isLoading = false);
        context.go(AppRouter.login);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MenuTile(
      icon: Icons.logout_rounded,
      title: _isLoading ? 'Keluar...' : 'Keluar',
      subtitle: 'Akhiri sesi di perangkat ini',
      destructive: true,
      leading: _isLoading
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.destructive))
          : null,
      onTap: _isLoading ? null : _handleSignOut,
    );
  }
}

class _SignOutDialog extends StatefulWidget {
  const _SignOutDialog();

  @override
  State<_SignOutDialog> createState() => _SignOutDialogState();
}

class _SignOutDialogState extends State<_SignOutDialog> {
  bool _confirming = false;

  @override
  Widget build(BuildContext context) {
    final unsynced = OfflineQueue.unsyncedCount;
    return AlertDialog(
      title: const Text('Keluar dari akun?'),
      content: Text(unsynced == 0
          ? 'Anda perlu masuk lagi untuk memakai aplikasi di perangkat ini.'
          : 'Masih ada $unsynced transaksi yang belum terkirim. Transaksi tetap tersimpan di perangkat ini '
              'dan dikirim otomatis setelah ada yang login lagi (tercatat atas nama kasir yang menjualnya).\n\n'
              'Tetap keluar?'),
      actions: [
        TextButton(
          onPressed: _confirming ? null : () => Navigator.of(context).pop(false),
          child: const Text('Batal'),
        ),
        TextButton(
          onPressed: _confirming
              ? null
              : () {
                  setState(() => _confirming = true);
                  Navigator.of(context).pop(true);
                },
          style: TextButton.styleFrom(foregroundColor: AppTheme.destructive),
          child: const Text('Keluar'),
        ),
      ],
    );
  }
}
