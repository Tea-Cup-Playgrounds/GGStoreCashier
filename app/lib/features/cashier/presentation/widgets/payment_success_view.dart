import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/custom_button.dart';
import '../../../../core/helper/currency_formatter.dart';
import '../../../devices/data/receipt_printer.dart';
import '../../../devices/domain/receipt.dart';
import '../../../devices/presentation/widgets/sale_receipt_sheet.dart';

import 'package:gg_store_cashier/core/services/error_handler.dart';
class PaymentSuccessView extends StatefulWidget {
  final double total;
  final Map<String, dynamic>? appliedCoupon;
  final String? saleNumber;
  final double change;

  /// The sale's receipt, for printing / showing. Printed right away when automatic printing is on.
  final ReceiptData? receipt;

  /// The sale is stored on this device and goes to the server later.
  final bool savedOffline;
  final VoidCallback onNewTransaction;

  const PaymentSuccessView({
    super.key,
    required this.total,
    this.appliedCoupon,
    this.saleNumber,
    this.change = 0,
    this.receipt,
    this.savedOffline = false,
    required this.onNewTransaction,
  });

  @override
  State<PaymentSuccessView> createState() => _PaymentSuccessViewState();
}

class _PaymentSuccessViewState extends State<PaymentSuccessView> with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _slideController;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  final AudioPlayer _audioPlayer = AudioPlayer();

  PrinterSettings? _printer;
  bool _printing = false;
  int _printedCount = 0;
  String? _printError;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _startAnimations();
    _initPrinter();
  }

  Future<void> _initPrinter() async {
    final printer = await PrinterSettings.load();
    if (!mounted) return;
    setState(() => _printer = printer);
    if (printer.autoPrint && printer.isConfigured && widget.receipt != null) _print();
  }

  /// The first print of a sale also opens the cash drawer (when that is switched on); later
  /// prints are marked as copies.
  Future<void> _print() async {
    final receipt = widget.receipt;
    if (receipt == null || _printing) return;
    setState(() {
      _printing = true;
      _printError = null;
    });
    try {
      final first = _printedCount == 0;
      await ReceiptPrinter.printReceipt(first ? receipt : receipt.asCopy(), openDrawer: first);
      if (mounted) setState(() => _printedCount++);
    } catch (e) {
      if (mounted) setState(() => _printError = e is PrinterException ? e.message : ErrorHandler.describeAs('Gagal mencetak', e));
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<void> _setUpPrinter() async {
    await context.push(AppRouter.printerDevices);
    final printer = await PrinterSettings.load();
    if (mounted) setState(() => _printer = printer);
  }

  Widget _buildPrintRow(BuildContext context) {
    final receipt = widget.receipt;
    if (receipt == null) return const SizedBox.shrink();
    final configured = _printer?.isConfigured ?? false;
    final status = _printing
        ? 'Mencetak struk...'
        : _printError ?? (_printedCount > 0 ? 'Struk tercetak${_printedCount > 1 ? ' ($_printedCount×)' : ''}' : null);
    return Column(
      children: [
        if (status != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              status,
              textAlign: TextAlign.center,
              style: TextStyle(color: _printError != null ? AppTheme.destructive : AppTheme.mutedForeground, fontSize: 13),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => SaleReceiptSheet.showReceipt(context, receipt),
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: const Text('Lihat struk'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: configured
                  ? FilledButton.icon(
                      onPressed: _printing ? null : _print,
                      icon: const Icon(Icons.print_outlined, size: 18),
                      label: Text(_printedCount == 0 ? 'Cetak struk' : 'Cetak lagi'),
                    )
                  : OutlinedButton.icon(
                      onPressed: _setUpPrinter,
                      icon: const Icon(Icons.print_disabled_outlined, size: 18),
                      label: const Text('Atur printer'),
                    ),
            ),
          ],
        ),
      ],
    );
  }

  void _setupAnimations() {
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOut,
    ));
  }

  void _startAnimations() {
    _scaleController.forward();
    Future.delayed(const Duration(milliseconds: 200), () {
      _slideController.forward();
    });
    _audioPlayer.play(AssetSource('payment_success.mp3'));
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _slideController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        // Scrolls on short screens; on tall ones the spacers keep it centred as before.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),

              // Success Icon
              AnimatedBuilder(
                animation: _scaleAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [AppTheme.gold, AppTheme.goldLight],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.gold.withValues(alpha: 0.4),
                            blurRadius: 30,
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.check,
                        size: 60,
                        color: Theme.of(context).colorScheme.surface,
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 32),

              // Success Text
              SlideTransition(
                position: _slideAnimation,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Column(
                    children: [
                      Text(
                        'Pembayaran Berhasil',
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.savedOffline
                            ? 'Tersimpan di perangkat ini — dikirim ke server otomatis'
                            : 'Transaksi berhasil diselesaikan',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: widget.savedOffline ? AppTheme.warning : AppTheme.mutedForeground,
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // Payment Details
              SlideTransition(
                position: _slideAnimation,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppTheme.background,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Total Dibayar',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: AppTheme.mutedForeground,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          CurrencyFormatter.formatToRupiah(widget.total),
                          style: Theme.of(context).textTheme.displayMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.gold,
                              ),
                        ),
                        if (widget.appliedCoupon != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppTheme.success.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Voucher ${widget.appliedCoupon!['code']} diterapkan',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppTheme.success,
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                          ),
                        ],
                        if (widget.change > 0) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Kembalian ${CurrencyFormatter.formatToRupiah(widget.change)}',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: AppTheme.success,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                        if (widget.saleNumber != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            widget.saleNumber!,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppTheme.mutedForeground,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),
              const Spacer(),

              // Receipt + New Transaction buttons
              SlideTransition(
                position: _slideAnimation,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Column(
                    children: [
                      if (widget.receipt != null) ...[
                        _buildPrintRow(context),
                        const SizedBox(height: 12),
                      ],
                      CustomButton(
                        text: 'Transaksi Baru',
                        onPressed: widget.onNewTransaction,
                        fullWidth: true,
                        size: ButtonSize.extraLarge,
                      ),
                      const SizedBox(height: 12),
                      CustomButton(
                        text: 'Kembali ke Beranda',
                        variant: ButtonVariant.outline,
                        icon: Icons.home_outlined,
                        onPressed: () => context.go('/home'),
                        fullWidth: true,
                        size: ButtonSize.large,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 100), // Space for bottom navigation
            ],
          ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
