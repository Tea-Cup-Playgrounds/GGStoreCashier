import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/models/voucher.dart';
import '../../../../core/services/voucher_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/helper/date_formatter.dart';
import '../../../../shared/widgets/custom_button.dart';
import '../../../../shared/widgets/pull_to_refresh.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_router.dart';

class VoucherManagementPage extends ConsumerStatefulWidget {
  const VoucherManagementPage({super.key});

  @override
  ConsumerState<VoucherManagementPage> createState() =>
      _VoucherManagementPageState();
}

class _VoucherManagementPageState
    extends ConsumerState<VoucherManagementPage> {
  List<Voucher> _vouchers = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final list = await VoucherService.getAll();
      if (mounted) setState(() {
        _vouchers = list;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _showForm([Voucher? voucher]) async {
    bool? result;
    if (voucher == null) {
      result = await context.push<bool>(AppRouter.voucherCreate);
    } else {
      result = await context.push<bool>(
        AppRouter.voucherEdit.replaceFirst(':id', '${voucher.id}'),
        extra: voucher,
      );
    }
    if (result == true) _load();
  }

  Future<void> _delete(Voucher v) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Voucher'),
        content: Text('Hapus voucher "${v.code}"? Tindakan ini tidak dapat dibatalkan.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hapus',
                  style: TextStyle(color: AppTheme.destructive))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await VoucherService.delete(v.id);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: AppTheme.destructive,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Manajemen Voucher'),
        backgroundColor: cs.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: CustomButton(
              text: 'Tambah Voucher',
              icon: Icons.add,
              onPressed: () => _showForm(),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.gold))
          : _error != null
              ? _buildError()
              : _buildList(cs),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 56, color: AppTheme.destructive),
          const SizedBox(height: 16),
          Text('Gagal memuat voucher',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(_error!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.6)),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          CustomButton(text: 'Coba Lagi', icon: Icons.refresh, onPressed: _load),
        ],
      ),
    );
  }

  Widget _buildList(ColorScheme cs) {
    if (_vouchers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.local_offer_outlined,
                size: 64, color: cs.onSurface.withOpacity(0.3)),
            const SizedBox(height: 16),
            Text('Belum ada voucher',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Ketuk "Tambah Voucher" untuk membuat voucher baru.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface.withOpacity(0.6))),
          ],
        ),
      );
    }

    return PullToRefresh(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _vouchers.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _VoucherTile(
          voucher: _vouchers[i],
          onEdit: () => _showForm(_vouchers[i]),
          onDelete: () => _delete(_vouchers[i]),
        ),
      ),
    );
  }
}

// ── Tile ──────────────────────────────────────────────────────────────────────

class _VoucherTile extends StatelessWidget {
  final Voucher voucher;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _VoucherTile({
    required this.voucher,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isActive = voucher.isActive;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? cs.outlineVariant : cs.outlineVariant.withOpacity(0.4),
        ),
      ),
      child: Row(
        children: [
          // Icon badge
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isActive
                  ? AppTheme.gold.withOpacity(0.1)
                  : cs.onSurface.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.local_offer_outlined,
              color: isActive ? AppTheme.gold : cs.onSurface.withOpacity(0.3),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(voucher.code,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isActive ? AppTheme.gold : cs.onSurface.withOpacity(0.4))),
                    const SizedBox(width: 8),
                    _badge(context, voucher.discountLabel,
                        isActive ? AppTheme.gold : cs.onSurface.withOpacity(0.3)),
                    const SizedBox(width: 6),
                    _badge(
                      context,
                      isActive ? 'Aktif' : 'Nonaktif',
                      isActive ? AppTheme.success : cs.onSurface.withOpacity(0.3),
                    ),
                  ],
                ),
                if (voucher.description != null) ...[
                  const SizedBox(height: 4),
                  Text(voucher.description!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.6)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
                if (voucher.validFrom != null || voucher.validTo != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${DateFormatter.format(voucher.validFrom)} → ${DateFormatter.format(voucher.validTo)}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.45)),
                  ),
                ],
              ],
            ),
          ),

          // Actions
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(Icons.edit_outlined,
                    size: 20, color: cs.onSurface.withOpacity(0.6)),
                onPressed: onEdit,
                tooltip: 'Edit',
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 20, color: AppTheme.destructive),
                onPressed: onDelete,
                tooltip: 'Hapus',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _badge(BuildContext context, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: color, fontWeight: FontWeight.w600)),
    );
  }
}
