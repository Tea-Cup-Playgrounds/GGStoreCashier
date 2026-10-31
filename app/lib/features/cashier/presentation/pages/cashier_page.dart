import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/models/product.dart';
import '../../../../core/models/cart_item.dart';
import '../../../../core/helper/screen_type_utils.dart';
import '../../../../core/constants/screen_breakpoints.dart';
import '../../../../core/helper/currency_formatter.dart';
import '../../../../core/services/product_service.dart';
import '../../../../core/services/catalog_service.dart';
import '../../../../core/services/sales_service.dart';
import '../../../../core/services/cache_manager.dart';
import '../../../../core/models/catalog.dart';
import '../../../../core/models/sales.dart';
import '../../../../core/services/voucher_service.dart';
import '../../../../core/services/connectivity_monitor.dart';
import '../../../../core/services/offline_queue.dart';
import '../../../../core/provider/realtime_provider.dart';
import '../../../../core/router/app_router.dart';
import '../../../../shared/widgets/custom_button.dart';
import '../../../../shared/widgets/pull_to_refresh.dart';
import '../../../../shared/widgets/quantity_picker_modal.dart';
import '../widgets/product_card.dart';
import '../widgets/cart_item_widget.dart';
import '../widgets/coupon_card.dart';
import '../widgets/payment_success_view.dart';
import '../widgets/payment_sheet.dart';
import '../widgets/shift_sheet.dart';
import '../widgets/service_item_dialog.dart';
import '../providers/cashier_location_provider.dart';
import '../../../warehouse/presentation/widgets/unit_picker_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

enum CashierView { products, cart, coupon, success }

class CashierPage extends ConsumerStatefulWidget {
  const CashierPage({super.key});

  @override
  ConsumerState<CashierPage> createState() => _CashierPageState();
}

class _CashierPageState extends ConsumerState<CashierPage> with TickerProviderStateMixin {
  CashierView _currentView = CashierView.products;
  final List<CartItem> _cart = [];
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _couponController = TextEditingController();

  Map<String, dynamic>? _appliedCoupon;
  bool _isApplyingCoupon = false;
  bool _isProcessingPayment = false;
  SaleResult? _lastSale;
  // Sale id generated here, so a retried checkout (or the offline queue) never creates two sales.
  String _transactionUuid = const Uuid().v4();

  // Location, payment methods and shift of this cashier
  int? _loadedLocationId;
  List<PaymentMethod> _methods = [];
  CashSession? _shift;
  ProviderSubscription<Location?>? _locationSub;

  // Products state
  List<Product> _products = [];
  bool _isLoadingProducts = true;
  String? _productsError;

  late AnimationController _viewAnimationController;
  ProviderSubscription<RealtimeProductState>? _realtimeSub;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Guard: only register once
    _realtimeSub ??= ref.listenManual(realtimeProductProvider, (previous, next) {
      if (next.lastUpdateTime != previous?.lastUpdateTime) {
        _loadProducts();
      }
    });
    // Load once the selling location is known, and again when the cashier switches location.
    _locationSub ??= ref.listenManual<Location?>(cashierLocationProvider, (previous, next) {
      if (next != null && next.id != _loadedLocationId) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadProducts();
        });
      }
    }, fireImmediately: true);
  }

  Future<void> _loadProducts({bool forceRefresh = false}) async {
    final location = ref.read(cashierLocationProvider);
    if (location == null) return;
    setState(() {
      _isLoadingProducts = true;
      _productsError = null;
    });

    try {
      final catalog = await CatalogService.getProducts(locationId: location.id);
      if (!mounted) return;
      setState(() {
        _products = [
          for (final p in catalog)
            for (final v in p.variants) Product.fromCatalog(p, v, locationId: location.id),
        ];
        _loadedLocationId = location.id;
        _isLoadingProducts = false;
      });
      // Keep the cached goods list fresh for offline selling.
      ProductService.getProducts(branchId: location.id, forceRefresh: true).ignore();
      _loadPaymentMethods(location.id).ignore();
      _loadShift(location.id).ignore();
    } catch (e) {
      // Offline: fall back to the cached goods list (no services / pulsa, no IMEI checks).
      try {
        final cached = await ProductService.getProducts(branchId: location.id);
        if (!mounted) return;
        setState(() {
          _products = cached;
          _loadedLocationId = location.id;
          _isLoadingProducts = false;
        });
        _loadPaymentMethods(location.id).ignore();
        _toast('Offline — menampilkan daftar produk tersimpan');
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _productsError = e.toString();
          _isLoadingProducts = false;
        });
      }
    }
  }

  String _methodsCacheKey(int locationId) => 'payment_methods:$locationId';

  /// Payment methods are cached so cash can still be taken offline.
  Future<void> _loadPaymentMethods(int locationId) async {
    try {
      final methods = await SalesService.getPaymentMethods(locationId);
      await CacheManager.put(_methodsCacheKey(locationId), [
        for (final m in methods) {'id': m.id, 'name': m.name, 'type': m.type, 'requires_reference': m.requiresReference},
      ]);
      if (mounted) setState(() => _methods = methods);
    } catch (_) {
      final cached = CacheManager.get(_methodsCacheKey(locationId));
      if (cached != null && mounted) {
        setState(() => _methods = (cached.data as List)
            .map((e) => PaymentMethod.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList());
      }
    }
  }

  Future<void> _loadShift(int locationId) async {
    try {
      final shift = await SalesService.currentShift(locationId);
      if (mounted) setState(() => _shift = shift);
    } catch (_) {
      // Shifts are optional; selling continues without one.
    }
  }

  Future<void> _openShiftSheet() async {
    final location = ref.read(cashierLocationProvider);
    if (location == null) return;
    final (changed, session) = await ShiftSheet.show(context, locationId: location.id, session: _shift);
    if (changed && mounted) setState(() => _shift = session);
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? AppTheme.destructive : null,
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _setupAnimations() {
    _viewAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    // _slideAnimation = Tween<Offset>(
    //   begin: const Offset(1, 0),
    //   end: Offset.zero,
    // ).animate(CurvedAnimation(
    //   parent: _viewAnimationController,
    //   curve: Curves.easeOutCubic,
    // ));
  }

  @override
  void dispose() {
    _realtimeSub?.close();
    _locationSub?.close();
    _viewAnimationController.dispose();
    _searchController.dispose();
    _couponController.dispose();
    super.dispose();
  }

  Future<void> _addToCart(Product product) async {
    if (product.isOutOfStock) return;

    // Services / pulsa: price and note typed at the counter, one line each.
    if (!product.hasStock) {
      final entry = await showServiceItemDialog(context, product);
      if (entry == null || !mounted) return;
      setState(() => _cart.add(CartItem(
            id: '${product.id}-${const Uuid().v4()}',
            product: product,
            quantity: 1,
            price: entry.$1,
            note: entry.$2.isEmpty ? null : entry.$2,
          )));
      _toast('${product.name} ditambahkan');
      return;
    }

    // Phones: the cashier picks (or scans) the exact IMEI units being sold.
    if (product.isSerialized) {
      await _pickUnits(product);
      return;
    }

    // Find existing qty in cart to set as initial value
    final existing = _cart.where((i) => i.id == product.id).firstOrNull;
    final alreadyInCart = existing?.quantity ?? 0;
    final remainingStock = product.stock - alreadyInCart;
    if (remainingStock <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Stok "${product.name}" sudah habis ditambahkan'),
        backgroundColor: AppTheme.warning,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      return;
    }

    final qty = await showQuantityPickerModal(
      context,
      productName: product.name,
      unitPrice: product.sellPrice,
      maxStock: remainingStock,
      imageUrl: product.image,
    );

    if (qty == null || qty <= 0) return;

    setState(() {
      final existingIndex = _cart.indexWhere((item) => item.id == product.id);
      if (existingIndex >= 0) {
        _cart[existingIndex] = _cart[existingIndex].copyWith(quantity: _cart[existingIndex].quantity + qty);
      } else {
        _cart.add(CartItem.fromProduct(product, quantity: qty));
      }
    });

    // Cart notification above bottom nav
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '$qty × ${product.name} ditambahkan',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: () {
                ScaffoldMessenger.of(context).clearSnackBars();
                _changeView(CashierView.cart);
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Lihat', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ],
        ),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
        padding: const EdgeInsets.only(left: 12, right: 4, top: 6, bottom: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  Future<void> _pickUnits(Product product) async {
    if (ConnectivityMonitor.instance.currentStatus == ConnectivityStatus.offline) {
      _toast('HP / barang ber-IMEI butuh koneksi untuk memeriksa unit', error: true);
      return;
    }
    final location = ref.read(cashierLocationProvider);
    if (location == null) return;
    final existing = _cart.where((i) => i.id == product.id).firstOrNull;
    final units = await UnitPickerSheet.show(
      context,
      locationId: location.id,
      variantId: int.parse(product.id),
      title: product.name,
      selected: existing?.unitIds.toSet() ?? const {},
    );
    if (units == null || !mounted) return;
    setState(() {
      _cart.removeWhere((i) => i.id == product.id);
      if (units.isNotEmpty) {
        _cart.add(CartItem(id: product.id, product: product, quantity: units.length, price: product.sellPrice, unitIds: units.toList()));
      }
    });
  }

  void _updateCartItemQuantity(String id, int delta) {
    final index = _cart.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final item = _cart[index];
    // IMEI items change by picking units, not by count.
    if (item.product.isSerialized) {
      _pickUnits(item.product);
      return;
    }
    setState(() {
      final newQuantity = item.quantity + delta;
      if (newQuantity <= 0) {
        _cart.removeAt(index);
      } else {
        // Cap at available stock (services and pulsa have none)
        final capped = item.product.hasStock ? newQuantity.clamp(1, item.product.stock) : newQuantity;
        _cart[index] = item.copyWith(quantity: capped);
      }
    });
  }

  void _removeFromCart(String id) {
    setState(() {
      _cart.removeWhere((item) => item.id == id);
    });
  }

  Future<void> _applyCoupon() async {
    final code = _couponController.text.trim().toUpperCase();
    if (code.isEmpty) return;

    setState(() => _isApplyingCoupon = true);

    try {
      final voucher = await VoucherService.validate(code);
      if (mounted) {
        setState(() {
          _isApplyingCoupon = false;
          _appliedCoupon = {
            'code': voucher.code,
            'discount': voucher.discountType == 'percent' ? voucher.discountValue : null,
            'fixedDiscount': voucher.discountType == 'fixed' ? voucher.discountValue : null,
            'discountType': voucher.discountType,
            'description': voucher.description ?? voucher.discountLabel,
          };
          _currentView = CashierView.cart;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Voucher $code berhasil diterapkan!'),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isApplyingCoupon = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is DioException
              ? (e.response?.data?['error'] ?? 'Voucher tidak valid atau sudah kadaluarsa')
              : 'Voucher tidak valid atau sudah kadaluarsa'),
          backgroundColor: AppTheme.destructive,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ));
      }
    }
  }

  /// Prices the cart on the server, takes payment in [PaymentSheet] and records the sale.
  /// Offline (or if the connection drops while saving) the sale goes to the offline queue;
  /// its id makes the later upload safe to repeat.
  Future<void> _processPayment() async {
    if (_cart.isEmpty) return;
    final location = ref.read(cashierLocationProvider);
    if (location == null) {
      _toast('Anda belum ditugaskan ke cabang untuk berjualan', error: true);
      return;
    }
    final offline = ConnectivityMonitor.instance.currentStatus == ConnectivityStatus.offline;
    final lines = _cart.map((i) => i.toSaleLine()).toList();
    final voucherCode = _appliedCoupon?['code'] as String?;

    double total = _total;
    var requireCustomer = _cart.any((i) => i.product.isSerialized);
    if (!offline) {
      setState(() => _isProcessingPayment = true);
      try {
        final quote = await SalesService.quote({
          'location_id': location.id,
          'lines': lines,
          if (voucherCode != null) 'voucher_code': voucherCode,
        });
        total = (quote['grand_total'] as num).toDouble();
        requireCustomer = quote['requires_customer'] == true;
      } on ApiException catch (e) {
        _toast(e.message, error: true);
        return;
      } finally {
        if (mounted) setState(() => _isProcessingPayment = false);
      }
      if (_methods.isEmpty) await _loadPaymentMethods(location.id);
    }
    if (_methods.isEmpty) {
      _toast('Metode pembayaran belum tersedia — periksa koneksi', error: true);
      return;
    }
    if (!mounted) return;

    final result = await PaymentSheet.show(context, total: total, methods: _methods, requireCustomer: requireCustomer, offline: offline);
    if (result == null || !mounted) return;

    final body = <String, dynamic>{
      'id': _transactionUuid,
      'location_id': location.id,
      if (_shift != null && _shift!.isOpen && _shift!.locationId == location.id) 'cash_session_id': _shift!.id,
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
      'lines': lines,
      if (voucherCode != null) 'voucher_code': voucherCode,
      'payments': result.payments.map((p) => p.toJson()).toList(),
      ...?result.customer?.toSaleJson(),
    };

    if (offline) {
      await _queueOffline(body);
      return;
    }

    setState(() => _isProcessingPayment = true);
    try {
      final sale = await SalesService.createSale(body);
      if (!mounted) return;
      setState(() {
        _lastSale = sale;
        _isProcessingPayment = false;
        _currentView = CashierView.success;
      });
      if (_shift != null) _loadShift(location.id).ignore();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isProcessingPayment = false);
      if (e.statusCode == null) {
        // No answer from the server: it may or may not have been saved. The queue retries with the
        // same id, which the API treats as the same sale.
        await _queueOffline(body);
      } else {
        _toast(e.message, error: true);
      }
    }
  }

  Future<void> _queueOffline(Map<String, dynamic> body) async {
    final entry = OfflineTransactionEntry()
      ..uuid = body['id'] as String
      ..payload = body
      ..createdAt = DateTime.now()
      ..retryCount = 0
      ..status = 'pending';
    await OfflineQueue.enqueue(entry);
    _toast('Transaksi disimpan — akan dikirim saat online');
    _resetTransaction();
  }

  void _resetTransaction() {
    setState(() {
      _cart.clear();
      _appliedCoupon = null;
      _couponController.clear();
      _currentView = CashierView.products;
      _transactionUuid = const Uuid().v4();
      _lastSale = null;
    });
  }

  double get _subtotal => _cart.fold(0, (sum, item) => sum + item.subtotal);

  double get _discount {
    if (_appliedCoupon == null) return 0;
    if (_appliedCoupon!['discountType'] == 'fixed') {
      final fixed = (_appliedCoupon!['fixedDiscount'] as num?)?.toDouble() ?? 0;
      return fixed > _subtotal ? _subtotal : fixed;
    }
    // percent
    final pct = (_appliedCoupon!['discount'] as num?)?.toDouble() ?? 0;
    return _subtotal * (pct / 100);
  }

  double get _total => _subtotal - _discount;

  /// Label for the applied voucher card ("10% OFF" / "Rp5.000 OFF").
  String get _couponLabel {
    final coupon = _appliedCoupon;
    if (coupon == null) return '';
    if (coupon['discountType'] == 'fixed') {
      return '${CurrencyFormatter.formatToRupiah((coupon['fixedDiscount'] as num?) ?? 0)} OFF';
    }
    return '${coupon['discount']}% OFF';
  }

  List<Product> get _filteredProducts {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) return _products;

    return _products.where((product) {
      return product.name.toLowerCase().contains(query) || (product.category?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final screenType = getScreenType(context);
    final orientation = getOrientation(context);

    // Watch connectivity so the offline banner / payment options update.
    ref.watch(connectivityProvider);
    final salesLocations = ref.watch(salesLocationsProvider);
    final location = ref.watch(cashierLocationProvider);

    if (salesLocations.hasValue && salesLocations.value!.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Kasir')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('Anda belum ditugaskan ke cabang yang boleh melakukan penjualan.', textAlign: TextAlign.center),
          ),
        ),
      );
    }

    if (_currentView == CashierView.success) {
      return PaymentSuccessView(
        total: _lastSale?.grandTotal ?? _total,
        appliedCoupon: _appliedCoupon,
        saleNumber: _lastSale?.number,
        change: _lastSale?.changeTotal ?? 0,
        onNewTransaction: _resetTransaction,
      );
    }

    // Use split-screen for tablets
    final isTablet = screenType == ScreenType.tablet;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(
          isTablet ? 'Penjualan Baru' : _getAppBarTitle(),
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        actions: [
          if ((salesLocations.valueOrNull?.length ?? 0) > 1)
            PopupMenuButton<int>(
              tooltip: 'Lokasi penjualan',
              onSelected: (id) {
                if (_cart.isNotEmpty) {
                  _toast('Kosongkan keranjang sebelum pindah lokasi', error: true);
                  return;
                }
                ref.read(selectedCashierLocationProvider.notifier).state = id;
              },
              itemBuilder: (_) => [
                for (final l in salesLocations.value!) PopupMenuItem(value: l.id, child: Text(l.label)),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(children: [
                  const Icon(Icons.storefront_outlined, size: 18),
                  const SizedBox(width: 4),
                  Text(location?.code ?? '-', style: const TextStyle(fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          IconButton(
            tooltip: _shift?.isOpen == true ? 'Shift berjalan' : 'Buka shift',
            onPressed: _openShiftSheet,
            icon: Badge(
              isLabelVisible: _shift?.isOpen == true,
              smallSize: 8,
              backgroundColor: AppTheme.success,
              child: const Icon(Icons.point_of_sale_outlined),
            ),
          ),
          if (!isTablet && _currentView == CashierView.products && _cart.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Stack(
                children: [
                  IconButton(
                    onPressed: () => _changeView(CashierView.cart),
                    icon: const Icon(Icons.shopping_cart_outlined),
                  ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: AppTheme.gold,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        '${_cart.length}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.surface,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (!isTablet && _currentView != CashierView.products && _currentView != CashierView.coupon)
            IconButton(
              onPressed: () => _changeView(CashierView.products),
              icon: const Icon(Icons.close),
            ),
        ],
      ),
      body: isTablet ? _buildTabletLayout(orientation) : _buildPhoneLayout(),
    );
  }

  // Tablet split-screen layout
  Widget _buildTabletLayout(OrientationType orientation) {
    final isLandscape = orientation == OrientationType.landscape;

    return LayoutBuilder(
      builder: (context, constraints) {
        final leftWidth = isLandscape ? constraints.maxWidth * 0.6 : constraints.maxWidth * 0.5;

        return Row(
          children: [
            // Left: Products
            SizedBox(
              width: leftWidth,
              child: Column(
                children: [
                  // Search
                  Container(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        hintText: 'Cari produk...',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) => setState(() {}),
                    ),
                  ),
                  // Products Grid
                  Expanded(
                    child: _isLoadingProducts
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(color: AppTheme.gold),
                                SizedBox(height: 16),
                                Text('Memuat produk...'),
                              ],
                            ),
                          )
                        : _productsError != null
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.error_outline,
                                      size: 64,
                                      color: AppTheme.destructive,
                                    ),
                                    const SizedBox(height: 16),
                                    const Text('Gagal memuat produk'),
                                    const SizedBox(height: 16),
                                    CustomButton(
                                      text: 'Coba Lagi',
                                      icon: Icons.refresh,
                                      onPressed: _loadProducts,
                                    ),
                                  ],
                                ),
                              )
                            : _filteredProducts.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.inventory_2_outlined,
                                          size: 64,
                                          color: AppTheme.mutedForeground.withValues(alpha: 0.5),
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          _searchController.text.isNotEmpty
                                              ? 'Produk tidak ditemukan'
                                              : 'Belum ada produk',
                                          style: const TextStyle(
                                            color: AppTheme.mutedForeground,
                                            fontSize: 18,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : PullToRefresh(
                                    onRefresh: () => _loadProducts(forceRefresh: true),
                                    child: GridView.builder(
                                      padding: const EdgeInsets.all(16),
                                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: isLandscape ? 3 : 2,
                                        crossAxisSpacing: 12,
                                        mainAxisSpacing: 12,
                                        childAspectRatio: 0.72,
                                      ),
                                      itemCount: _filteredProducts.length,
                                      itemBuilder: (context, index) {
                                        final product = _filteredProducts[index];
                                        return ProductCard(
                                          product: product,
                                          onAdd: () => _addToCart(product),
                                        );
                                      },
                                    ),
                                  ),
                  ),
                ],
              ),
            ),

            // Divider
            Container(
              width: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),

            // Right: Cart & Summary
            Expanded(
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Ringkasan Pesanan',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        if (_cart.isNotEmpty)
                          Text(
                            '${_cart.fold(0, (sum, item) => sum + item.quantity)} item',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: AppTheme.mutedForeground,
                                ),
                          ),
                      ],
                    ),
                  ),

                  // Cart Items
                  Expanded(
                    child: _cart.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.shopping_cart_outlined,
                                  size: 64,
                                  color: AppTheme.mutedForeground.withValues(alpha: 0.5),
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'Keranjang kosong',
                                  style: TextStyle(
                                    color: AppTheme.mutedForeground,
                                    fontSize: 18,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _cart.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final item = _cart[index];
                              return CartItemWidget(
                                cartItem: item,
                                onIncrease: (id) => _updateCartItemQuantity(id, 1),
                                onDecrease: (id) => _updateCartItemQuantity(id, -1),
                                onRemove: _removeFromCart,
                              );
                            },
                          ),
                  ),

                  // Summary & Payment
                  if (_cart.isNotEmpty)
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardTheme.color,
                        border: Border(
                          top: BorderSide(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Coupon
                            if (_appliedCoupon != null)
                              CouponCard(
                                code: _appliedCoupon!['code'],
                                discount: _couponLabel,
                                description: _appliedCoupon!['description'],
                                isApplied: true,
                              )
                            else
                              CustomButton(
                                text: 'Tambah Voucher',
                                variant: ButtonVariant.outline,
                                icon: Icons.local_offer_outlined,
                                onPressed: () => _changeView(CashierView.coupon),
                                fullWidth: true,
                              ),

                            const SizedBox(height: 16),

                            // Price Summary
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppTheme.muted.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('Subtotal'),
                                      Text(
                                        CurrencyFormatter.formatToRupiah(_subtotal),
                                        style: const TextStyle(fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                  if (_discount > 0) ...[
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'Diskon',
                                          style: TextStyle(color: AppTheme.success),
                                        ),
                                        Text(
                                          CurrencyFormatter.formatToRupiah(_discount),
                                          style: const TextStyle(
                                            color: AppTheme.success,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  const Divider(),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Total',
                                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                      Text(
                                        CurrencyFormatter.formatToRupiah(_total),
                                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: AppTheme.gold,
                                              fontSize: 24,
                                            ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Tombol Proses Pembayaran
                            CustomButton(
                              text: 'Bayar',
                              icon: Icons.check_circle_outline,
                              onPressed: _isProcessingPayment ? null : _processPayment,
                              isLoading: _isProcessingPayment,
                              fullWidth: true,
                              size: ButtonSize.large,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // Phone layout (original)
  Widget _buildPhoneLayout() {
    return Column(
      children: [
        if (_currentView == CashierView.products) _buildSearchBar(),
        Expanded(child: _buildCurrentView()),
      ],
    );
  }

  String _getAppBarTitle() {
    switch (_currentView) {
      case CashierView.products:
        return 'Penjualan Baru';
      case CashierView.cart:
        return 'Keranjang';
      case CashierView.coupon:
        return 'Terapkan Voucher';
      case CashierView.success:
        return 'Pembayaran Berhasil';
    }
  }

  Widget _buildSearchBar() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      color: cs.surface,
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Cari produk...',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                )
              : null,
          filled: true,
          fillColor: cs.surfaceContainerHighest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
        onChanged: (value) => setState(() {}),
      ),
    );
  }

  Widget _buildCurrentView() {
    switch (_currentView) {
      case CashierView.products:
        return _buildProductsView();
      case CashierView.cart:
        return _buildCartView();
      case CashierView.coupon:
        return _buildCouponView();
      case CashierView.success:
        return const SizedBox(); // Handled in main build method
    }
  }

  Widget _buildProductsView() {
    if (_isLoadingProducts) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppTheme.gold),
            const SizedBox(height: 16),
            Text(
              'Memuat produk...',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    if (_productsError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 56, color: AppTheme.destructive),
              const SizedBox(height: 16),
              Text('Gagal memuat produk', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                _productsError!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              CustomButton(text: 'Coba Lagi', icon: Icons.refresh, onPressed: _loadProducts),
            ],
          ),
        ),
      );
    }

    if (_filteredProducts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isNotEmpty ? 'Produk tidak ditemukan' : 'Belum ada produk',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    return PullToRefresh(
      onRefresh: () => _loadProducts(forceRefresh: true),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 0.72,
          ),
          itemCount: _filteredProducts.length,
          itemBuilder: (context, index) {
            final product = _filteredProducts[index];
            return ProductCard(
              product: product,
              onAdd: () => _addToCart(product),
            );
          },
        ),
      ), // Padding
    ); // PullToRefresh
  }

  Widget _buildCartView() {
    return Column(
      children: [
        Expanded(
          child: _cart.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.shopping_cart_outlined,
                        size: 64,
                        color: AppTheme.mutedForeground.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Keranjang kosong',
                        style: TextStyle(
                          color: AppTheme.mutedForeground,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _cart.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = _cart[index];
                    return CartItemWidget(
                      cartItem: item,
                      onIncrease: (id) => _updateCartItemQuantity(id, 1),
                      onDecrease: (id) => _updateCartItemQuantity(id, -1),
                      onRemove: _removeFromCart,
                      onQuantityChanged: (id, qty) {
                        setState(() {
                          final index = _cart.indexWhere((i) => i.id == id);
                          if (index >= 0) {
                            _cart[index] = _cart[index].copyWith(quantity: qty);
                          }
                        });
                      },
                    );
                  },
                ),
        ),
        if (_cart.isNotEmpty) _buildCartSummary(),
      ],
    );
  }

  Widget _buildCartSummary() {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant, width: 0.8)),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, -3),
                ),
              ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Voucher ──────────────────────────────────────────────
              if (_appliedCoupon != null)
                CouponCard(
                  code: _appliedCoupon!['code'],
                  discount: _couponLabel,
                  description: _appliedCoupon!['description'],
                  isApplied: true,
                )
              else
                OutlinedButton.icon(
                  onPressed: () async {
                    final result = await context.push<Map<String, dynamic>>(
                      AppRouter.cashierCoupon,
                    );
                    if (result != null && mounted) {
                      setState(() => _appliedCoupon = result);
                    }
                  },
                  icon: const Icon(Icons.local_offer_outlined, size: 16),
                  label: const Text('Tambah Voucher'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 40),
                    side: BorderSide(color: cs.outlineVariant),
                    foregroundColor: cs.onSurfaceVariant,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
              const SizedBox(height: 12),

              // ── Price rows ────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outlineVariant, width: 0.8),
                ),
                child: Column(
                  children: [
                    _PriceRow(
                      label: 'Subtotal',
                      value: CurrencyFormatter.formatToRupiah(_subtotal),
                    ),
                    if (_discount > 0) ...[
                      const SizedBox(height: 6),
                      _PriceRow(
                        label: 'Diskon',
                        value: '- ${CurrencyFormatter.formatToRupiah(_discount)}',
                        valueColor: AppTheme.success,
                        labelColor: AppTheme.success,
                      ),
                    ],
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Divider(height: 1, color: cs.outlineVariant),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        Text(
                          CurrencyFormatter.formatToRupiah(_total),
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.gold,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ── Pay button ────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isProcessingPayment ? null : _processPayment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.gold,
                    foregroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.black : Colors.white,
                    disabledBackgroundColor: AppTheme.gold.withValues(alpha: 0.4),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isProcessingPayment
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.check_circle_outline, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'Bayar  •  ${CurrencyFormatter.formatToRupiah(_total)}',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCouponView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Back button header
        Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
                width: 0.8,
              ),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: () => _changeView(CashierView.cart),
                icon: const Icon(Icons.arrow_back),
              ),
              Text(
                'Terapkan Voucher',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Masukkan Kode Voucher',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _couponController,
                      decoration: InputDecoration(
                        hintText: 'Contoh: DISKON20',
                        prefixIcon: const Icon(Icons.local_offer_outlined, size: 20),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      textCapitalization: TextCapitalization.characters,
                      onSubmitted: (_) => _isApplyingCoupon ? null : _applyCoupon(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  CustomButton(
                    text: 'Terapkan',
                    onPressed: _isApplyingCoupon ? null : _applyCoupon,
                    isLoading: _isApplyingCoupon,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _changeView(CashierView newView) {
    setState(() {
      _currentView = newView;
    });
    _viewAnimationController.forward(from: 0);
  }
}

class _PriceRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? labelColor;
  final Color? valueColor;

  const _PriceRow({
    required this.label,
    required this.value,
    this.labelColor,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: labelColor ?? Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: valueColor,
              ),
        ),
      ],
    );
  }
}
