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
  ConsumerState<VoucherManagementPage> createState() => _VoucherManagementPageState();
}

class _VoucherManagementPageState extends ConsumerState<VoucherManagementPage> {
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
      if (mounted) {
        setState(() {
          _vouchers = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
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
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.destructive),
            child: const Text('Hapus'),
          ),
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
    final isDark = cs.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        title: const Text('Manajemen Voucher'),
        backgroundColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: Colors.transparent,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SizedBox(
              height: 36,
              child: ElevatedButton.icon(
                onPressed: () => _showForm(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Tambah'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.gold,
                  foregroundColor: isDark ? Colors.black : Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.gold))
          : _error != null
              ? _buildError()
              : _buildList(cs, isDark),
    );
  }

  Widget _buildError() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 56, color: AppTheme.destructive),
            const SizedBox(height: 16),
            Text('Gagal memuat voucher', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(_error!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            CustomButton(text: 'Coba Lagi', icon: Icons.refresh, onPressed: _load),
          ],
        ),
      ),
    );
  }

  Widget _buildList(ColorScheme cs, bool isDark) {
    if (_vouchers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.local_offer_outlined, size: 56, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text('Belum ada voucher', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Tap "Tambah" untuk membuat voucher baru.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ),
      );
    }

    return PullToRefresh(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _vouchers.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _VoucherTile(
          voucher: _vouchers[i],
          isDark: isDark,
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
  final bool isDark;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _VoucherTile({
    required this.voucher,
    required this.isDark,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isActive = voucher.isActive;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? cs.outlineVariant : cs.outlineVariant.withValues(alpha: 0.4),
          width: 0.8,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Row(
        children: [
          // Icon badge
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isActive ? AppTheme.gold.withValues(alpha: 0.1) : cs.onSurface.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.local_offer_outlined,
              color: isActive ? AppTheme.gold : cs.onSurface.withValues(alpha: 0.3),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        voucher.code,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isActive ? AppTheme.gold : cs.onSurface.withValues(alpha: 0.4),
                            ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _badge(
                      context,
                      voucher.discountLabel,
                      isActive ? AppTheme.gold : cs.onSurface.withValues(alpha: 0.3),
                    ),
                    const SizedBox(width: 4),
                    _badge(
                      context,
                      isActive ? 'Aktif' : 'Nonaktif',
                      isActive ? AppTheme.success : cs.onSurface.withValues(alpha: 0.3),
                    ),
                  ],
                ),
                if (voucher.description != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    voucher.description!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (voucher.validFrom != null || voucher.validTo != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    '${DateFormatter.format(voucher.validFrom)} → ${DateFormatter.format(voucher.validTo)}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ),

          // Actions
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ActionBtn(
                icon: Icons.edit_outlined,
                color: cs.onSurfaceVariant,
                onTap: onEdit,
                tooltip: 'Edit',
              ),
              _ActionBtn(
                icon: Icons.delete_outline_rounded,
                color: AppTheme.destructive,
                onTap: onDelete,
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
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;

  const _ActionBtn({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 34,
          height: 34,
          margin: const EdgeInsets.only(left: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.15)),
          ),
          child: Icon(icon, size: 17, color: color),
        ),
      ),
    );
  }
}
