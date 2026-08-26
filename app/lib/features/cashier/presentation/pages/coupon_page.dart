import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../../../core/helper/date_formatter.dart';
import '../../../../core/models/voucher.dart';
import '../../../../core/services/voucher_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/custom_button.dart';
import '../../../../shared/widgets/pull_to_refresh.dart';

/// Cashier voucher picker — shows active vouchers as a selectable list.
/// Pops with a Map<String, dynamic> coupon result on selection, or null on cancel.
class CouponPage extends StatefulWidget {
  const CouponPage({super.key});

  @override
  State<CouponPage> createState() => _CouponPageState();
}

class _CouponPageState extends State<CouponPage> {
  List<Voucher> _vouchers = [];
  bool _isLoading = true;
  String? _error;
  int? _selectedId;

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
      final all = await VoucherService.getAll();
      // Show only active vouchers that haven't expired
      final now = DateTime.now();
      final active = all.where((v) {
        if (!v.isActive) return false;
        if (v.validTo != null) {
          try {
            final expiry = DateTime.parse(v.validTo!);
            if (expiry.isBefore(now)) return false;
          } catch (_) {}
        }
        return true;
      }).toList();

      if (mounted) {
        setState(() {
          _vouchers = active;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is DioException ? (e.response?.data?['error'] ?? 'Gagal memuat voucher') : 'Gagal memuat voucher';
          _isLoading = false;
        });
      }
    }
  }

  void _apply() {
    if (_selectedId == null) return;
    final voucher = _vouchers.firstWhere((v) => v.id == _selectedId);
    Navigator.of(context).pop({
      'code': voucher.code,
      'discount': voucher.discountType == 'percent' ? voucher.discountValue : null,
      'fixedDiscount': voucher.discountType == 'fixed' ? voucher.discountValue : null,
      'discountType': voucher.discountType,
      'description': voucher.description ?? voucher.discountLabel,
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        title: const Text('Pilih Voucher'),
        backgroundColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          // ── Content ───────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.gold))
                : _error != null
                    ? _buildError()
                    : _vouchers.isEmpty
                        ? _buildEmpty(cs)
                        : PullToRefresh(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                              itemCount: _vouchers.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (_, i) => _VoucherCard(
                                voucher: _vouchers[i],
                                isSelected: _vouchers[i].id == _selectedId,
                                isDark: isDark,
                                onTap: () => setState(() {
                                  _selectedId = _vouchers[i].id == _selectedId ? null : _vouchers[i].id;
                                }),
                              ),
                            ),
                          ),
          ),

          // ── Bottom action bar ──────────────────────────────────────
          SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: cs.surface,
                border: Border(top: BorderSide(color: cs.outlineVariant, width: 0.8)),
              ),
              child: CustomButton(
                text: _selectedId != null ? 'Terapkan Voucher' : 'Pilih Voucher',
                fullWidth: true,
                size: ButtonSize.large,
                onPressed: _selectedId != null ? _apply : null,
              ),
            ),
          ),
        ],
      ),
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
            const Icon(Icons.error_outline, size: 48, color: AppTheme.destructive),
            const SizedBox(height: 16),
            Text('Gagal memuat voucher', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(_error!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            CustomButton(text: 'Coba Lagi', icon: Icons.refresh, onPressed: _load),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.local_offer_outlined, size: 56, color: cs.onSurfaceVariant.withValues(alpha: 0.35)),
          const SizedBox(height: 16),
          Text('Tidak ada voucher aktif',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  )),
          const SizedBox(height: 6),
          Text('Voucher aktif akan muncul di sini.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

// ── Voucher card ─────────────────────────────────────────────────────────────

class _VoucherCard extends StatelessWidget {
  final Voucher voucher;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _VoucherCard({
    required this.voucher,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accentColor = isSelected ? AppTheme.gold : cs.outlineVariant;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.gold.withValues(alpha: 0.06) : cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: accentColor,
            width: isSelected ? 2 : 0.8,
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
            // Discount badge
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppTheme.gold.withValues(alpha: isSelected ? 0.18 : 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      voucher.discountType == 'percent' ? '${voucher.discountValue.toStringAsFixed(0)}%' : 'Rp',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: AppTheme.gold,
                            fontWeight: FontWeight.bold,
                            fontSize: voucher.discountType == 'percent' ? 16 : 12,
                          ),
                    ),
                    if (voucher.discountType == 'fixed')
                      Text(
                        _shortAmount(voucher.discountValue),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppTheme.gold,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    Text('OFF',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppTheme.gold.withValues(alpha: 0.7),
                              fontSize: 9,
                            )),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    voucher.code,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isSelected ? AppTheme.gold : null,
                        ),
                  ),
                  if (voucher.description != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      voucher.description!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (voucher.validTo != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.schedule_outlined, size: 12, color: cs.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          'Berlaku hingga ${DateFormatter.format(voucher.validTo)}',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // Selection indicator
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
                color: isSelected ? AppTheme.gold.withValues(alpha: 0.15) : Colors.transparent,
              ),
              child: isSelected ? const Center(child: Icon(Icons.check, size: 13, color: AppTheme.gold)) : null,
            ),
          ],
        ),
      ),
    );
  }

  String _shortAmount(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(0)}jt';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}rb';
    return v.toStringAsFixed(0);
  }
}
