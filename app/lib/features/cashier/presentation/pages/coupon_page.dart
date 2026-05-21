import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/voucher_service.dart';
import '../../../../shared/widgets/custom_button.dart';

/// Standalone page for entering a voucher code.
/// Pops with a Map<String, dynamic> coupon result on success, or null on cancel.
class CouponPage extends StatefulWidget {
  const CouponPage({super.key});

  @override
  State<CouponPage> createState() => _CouponPageState();
}

class _CouponPageState extends State<CouponPage> {
  final _controller = TextEditingController();
  bool _isApplying = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final code = _controller.text.trim().toUpperCase();
    if (code.isEmpty) return;

    setState(() {
      _isApplying = true;
      _error = null;
    });

    try {
      final voucher = await VoucherService.validate(code);
      if (mounted) {
        Navigator.of(context).pop({
          'code': voucher.code,
          'discount': voucher.discountType == 'percent' ? voucher.discountValue : null,
          'fixedDiscount': voucher.discountType == 'fixed' ? voucher.discountValue : null,
          'discountType': voucher.discountType,
          'description': voucher.description ?? voucher.discountLabel,
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isApplying = false;
          _error = e is DioException
              ? (e.response?.data?['error'] ?? 'Voucher tidak valid atau sudah kadaluarsa')
              : 'Voucher tidak valid atau sudah kadaluarsa';
        });
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
        title: const Text('Terapkan Voucher'),
        backgroundColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Info card ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.gold.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.gold.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.gold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.local_offer_outlined, color: AppTheme.gold, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Masukkan kode voucher untuk mendapatkan diskon pada transaksi ini.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Label ─────────────────────────────────────────────────
            Text(
              'Kode Voucher',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),

            // ── Input + button ────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textCapitalization: TextCapitalization.characters,
                    onSubmitted: (_) => _isApplying ? null : _apply(),
                    decoration: InputDecoration(
                      hintText: 'Contoh: DISKON20',
                      prefixIcon: const Icon(Icons.confirmation_number_outlined, size: 20),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF2A2A2A) : cs.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: cs.outlineVariant),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: cs.outlineVariant),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.gold, width: 2),
                      ),
                      errorText: _error,
                      errorMaxLines: 2,
                    ),
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 52,
                  child: CustomButton(
                    text: 'Terapkan',
                    onPressed: _isApplying ? null : _apply,
                    isLoading: _isApplying,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
