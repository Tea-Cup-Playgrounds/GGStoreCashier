import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/models/product.dart';
import '../../../../core/models/cart_item.dart';
import '../../../../core/models/transaction_model.dart';
import '../../../../core/models/voucher.dart';
import '../../../../core/helper/screen_type_utils.dart';
import '../../../../core/constants/screen_breakpoints.dart';
import '../../../../core/helper/currency_formatter.dart';
import '../../../../core/services/product_service.dart';
import '../../../../core/services/voucher_service.dart';
import '../../../../core/services/connectivity_monitor.dart';
import '../../../../core/services/offline_queue.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/provider/auth_provider.dart';
import '../../../../core/provider/realtime_provider.dart';
import '../../../../core/provider/realtime_store_provider.dart';
import '../../../../core/provider/socket_provider.dart';
import '../../../../shared/widgets/custom_button.dart';
import '../../../../shared/widgets/pull_to_refresh.dart';
import '../../../../shared/widgets/quantity_picker_modal.dart';
import '../widgets/product_card.dart';
import '../widgets/cart_item_widget.dart';
import '../widgets/coupon_card.dart';
import '../widgets/payment_success_view.dart';
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

  Map<String, dynamic>? _appliedCoupon;
  bool _isProcessingPayment = false;
  int? _lastTransactionId;
  String _selectedPaymentMethod = 'cash';
  String _transactionUuid = const Uuid().v4();

  // Products state — only needed to track loading/error; actual list comes from store
  bool _isLoadingProducts = true;
  String? _productsError;

  late AnimationController _viewAnimationController;
  ProviderSubscription<RealtimeTransactionState>? _realtimeTransactionSub;

  // Payment methods — cash always enabled; card/transfer/e-wallet require connectivity
  List<Map<String, dynamic>> get _paymentMethods {
    final isOffline = ConnectivityMonitor.instance.currentStatus == ConnectivityStatus.offline;
    return [
      {'value': 'cash', 'label': 'Tunai', 'icon': Icons.payments_outlined, 'enabled': true},
      {'value': 'card', 'label': 'Kartu', 'icon': Icons.credit_card, 'enabled': !isOffline},
      {'value': 'transfer', 'label': 'Transfer Bank', 'icon': Icons.account_balance, 'enabled': !isOffline},
      {'value': 'e-wallet', 'label': 'E-Wallet', 'icon': Icons.wallet, 'enabled': !isOffline},
    ];
  }

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _loadProducts();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Guard: only register once
    _realtimeTransactionSub ??= ref.listenManual(realtimeTransactionProvider, (previous, next) {
      if (next.lastPayment != null && next.lastUpdateTime != previous?.lastUpdateTime) {
        // Show a toast when a payment comes in from another terminal.
        if (mounted) {
          final method = next.lastPayment!['method'] ?? '';
          final amount = next.lastPayment!['amount'];
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Row(
              children: [
                const Icon(Icons.receipt_long, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Transaksi selesai: ${CurrencyFormatter.formatToRupiah((amount as num).toDouble())} via $method',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ));
        }
      }
    });
  }

  Future<void> _loadProducts({bool forceRefresh = false}) async {
    setState(() {
      _isLoadingProducts = true;
      _productsError = null;
    });
    try {
      final user = ref.read(authProvider).user;
      final branchId = (user != null && !user.isSuperAdmin) ? user.branchId : null;
      // Seed SQLite store — productStoreProvider picks up changes within 500 ms
      final products = await ProductService.getProducts(
        branchId: branchId,
        forceRefresh: forceRefresh,
      );
      await ref.read(productStoreProvider(branchId).notifier).seedFromHttp(products);
      if (mounted) setState(() => _isLoadingProducts = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _productsError = e.toString();
          _isLoadingProducts = false;
        });
      }
    }
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
    _realtimeTransactionSub?.close();
    _viewAnimationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Called when a product in the cart has been updated via WS.
  /// Warns the cashier if available stock dropped below cart quantity.
  void _handleCartConflict(Product updated) {
    final cartIdx = _cart.indexWhere((c) => c.id == updated.id);
    if (cartIdx < 0) return;
    final cartItem = _cart[cartIdx];
    if (updated.stock < cartItem.quantity) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Stok "${updated.name}" berkurang! Tersedia: ${updated.stock}, di keranjang: ${cartItem.quantity}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ]),
        backgroundColor: AppTheme.warning,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        action: SnackBarAction(
          label: 'Sesuaikan',
          textColor: Colors.white,
          onPressed: () {
            setState(() {
              _cart[cartIdx] = cartItem.copyWith(quantity: updated.stock);
            });
          },
        ),
      ));
    }
  }

  Future<void> _addToCart(Product product) async {
    if (product.isOutOfStock) return;

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

  void _updateCartItemQuantity(String id, int delta) {
    setState(() {
      final index = _cart.indexWhere((item) => item.id == id);
      if (index >= 0) {
        final item = _cart[index];
        final newQuantity = item.quantity + delta;
        if (newQuantity <= 0) {
          _cart.removeAt(index);
        } else {
          // Cap at available stock
          final capped = newQuantity.clamp(1, item.product.stock);
          _cart[index] = item.copyWith(quantity: capped);
        }
      }
    });
  }

  void _removeFromCart(String id) {
    setState(() {
      _cart.removeWhere((item) => item.id == id);
    });
  }

  Future<void> _processPayment(String method) async {
    if (_cart.isEmpty) return;

    // Validate all product IDs are parseable before sending
    for (final item in _cart) {
      final pid = int.tryParse(item.product.id);
      if (pid == null || pid <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('ID produk tidak valid untuk "${item.product.name}"'),
          backgroundColor: AppTheme.destructive,
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
    }

    // Check connectivity — route offline transactions to the local queue
    if (ConnectivityMonitor.instance.currentStatus == ConnectivityStatus.offline) {
      final user = ref.read(authProvider).user;
      final items = _cart
          .map((item) => {
                'product_id': int.parse(item.product.id),
                'qty': item.quantity,
                'price': item.price,
              })
          .toList();

      final branchId = user?.isSuperAdmin == true ? _cart.first.product.branchId : user?.branchId;

      final transaction = TransactionModel(
        uuid: _transactionUuid,
        items: items,
        discount: _discount,
        paymentMethod: method,
        total: _total,
        branchId: branchId,
        createdAt: DateTime.now(),
      );

      final entry = OfflineTransactionEntry()
        ..uuid = transaction.uuid
        ..payload = transaction.toHiveMap()
        ..createdAt = transaction.createdAt
        ..retryCount = 0
        ..status = 'pending';

      await OfflineQueue.enqueue(entry);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Transaksi disimpan — akan dikirim saat online'),
          behavior: SnackBarBehavior.floating,
        ));
        _resetTransaction();
      }
      return;
    }

    setState(() => _isProcessingPayment = true);

    try {
      final token = await AuthService.getToken();
      final user = ref.read(authProvider).user;

      final dio = Dio(BaseOptions(
        baseUrl: ApiConfig.apiUrl,
        headers: {'Authorization': 'Bearer $token', ...ApiConfig.defaultHeaders},
        connectTimeout: ApiConfig.connectTimeout,
        receiveTimeout: ApiConfig.receiveTimeout,
      ));

      final items = _cart
          .map((item) => {
                'product_id': int.parse(item.product.id),
                'qty': item.quantity,
                'price': item.price,
              })
          .toList();

      final body = <String, dynamic>{
        'items': items,
        'discount': _discount,
        'payment_method': method,
        'payment_amount': _total,
        if (_appliedCoupon != null) 'voucher_code': _appliedCoupon!['code'],
      };

      // Superadmin has branch_id = 0 in DB — must send the product's branch
      // Use the first cart item's branch as the transaction branch
      if (user != null && user.isSuperAdmin) {
        final firstBranchId = _cart.first.product.branchId;
        if (firstBranchId != null && firstBranchId > 0) {
          body['branch_id'] = firstBranchId;
        }
      }

      final response = await dio.post('/api/transactions', data: body);

      if (mounted) {
        setState(() {
          _lastTransactionId = response.data['transactionId'];
          _isProcessingPayment = false;
          _currentView = CashierView.success;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessingPayment = false);
        String msg = 'Pembayaran gagal';
        if (e is DioException && e.response?.data != null) {
          msg = e.response!.data['error'] ?? msg;
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: AppTheme.destructive,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  void _resetTransaction() {
    setState(() {
      _cart.clear();
      _appliedCoupon = null;
      _currentView = CashierView.products;
      _transactionUuid = const Uuid().v4();
    });
    _loadProducts(forceRefresh: true);
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

  List<Product> get _filteredProducts {
    // NOTE: call _getFilteredProducts(storeProducts) from build() where you have ref.watch.
    // This getter is kept for backward compat; it reads (not watches) the store.
    final user = ref.read(authProvider).user;
    final branchId = (user != null && !user.isSuperAdmin) ? user.branchId : null;
    final all = ref.read(productStoreProvider(branchId));
    return _applySearchFilter(all);
  }

  List<Product> _applySearchFilter(List<Product> all) {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) return all;
    return all
        .where((p) => p.name.toLowerCase().contains(query) || (p.category?.toLowerCase().contains(query) ?? false))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final screenType = getScreenType(context);
    final orientation = getOrientation(context);

    // Watch connectivity — triggers rebuild when status changes and gates payment methods
    final connectivityAsync = ref.watch(connectivityProvider);
    final connectivityStatus = connectivityAsync.valueOrNull ?? ConnectivityMonitor.instance.currentStatus;

    // If offline and an online-only method is selected, reset to cash
    if (connectivityStatus == ConnectivityStatus.offline && _selectedPaymentMethod != 'cash') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedPaymentMethod = 'cash');
      });
    }

    // Watch product store — detects stock changes every 500 ms via WS.
    // Check if any cart item's stock has dropped below its current quantity.
    final user = ref.read(authProvider).user;
    final branchId = (user != null && !user.isSuperAdmin) ? user.branchId : null;
    final storeProducts = ref.watch(productStoreProvider(branchId));
    if (_cart.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        for (final updated in storeProducts) {
          _handleCartConflict(updated);
        }
      });
    }

    if (_currentView == CashierView.success) {
      return PaymentSuccessView(
        total: _total,
        appliedCoupon: _appliedCoupon,
        transactionId: _lastTransactionId,
        onNewTransaction: _resetTransaction,
      );
    }

    // Use split-screen for tablets
    final isTablet = screenType == ScreenType.tablet;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isTablet ? 'Penjualan Baru' : _getAppBarTitle(),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(width: 8),
            _LiveDot(provider: socketConnectionProvider),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        actions: [
          if (!isTablet && _currentView == CashierView.products)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Stack(
                children: [
                  IconButton(
                    onPressed: () => _changeView(CashierView.cart),
                    icon: const Icon(Icons.shopping_cart_outlined),
                  ),
                  if (_cart.isNotEmpty)
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
                    child: _isLoadingProducts && _filteredProducts.isEmpty
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
                        : _productsError != null && _filteredProducts.isEmpty
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
                                      onPressed: () => _loadProducts(forceRefresh: true),
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
                                discount: '${_appliedCoupon!['discount']}% OFF',
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

                            // Payment Method Dropdown
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                border: Border.all(color: AppTheme.border),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _selectedPaymentMethod,
                                  isExpanded: true,
                                  icon: const Icon(Icons.arrow_drop_down),
                                  items: _paymentMethods.map((method) {
                                    final enabled = method['enabled'] as bool;
                                    return DropdownMenuItem<String>(
                                      value: method['value'],
                                      enabled: enabled,
                                      child: Row(
                                        children: [
                                          Icon(method['icon'] as IconData,
                                              size: 20, color: enabled ? null : AppTheme.mutedForeground),
                                          const SizedBox(width: 12),
                                          Text(method['label'] as String,
                                              style: TextStyle(color: enabled ? null : AppTheme.mutedForeground)),
                                          if (!enabled) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppTheme.muted.withValues(alpha: 0.4),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: const Text('Soon',
                                                  style: TextStyle(fontSize: 10, color: AppTheme.mutedForeground)),
                                            ),
                                          ],
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() => _selectedPaymentMethod = value);
                                    }
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Tombol Proses Pembayaran
                            CustomButton(
                              text: 'Proses Pembayaran',
                              icon: Icons.check_circle_outline,
                              onPressed: _isProcessingPayment ? null : () => _processPayment(_selectedPaymentMethod),
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
    final user = ref.read(authProvider).user;
    final branchId = (user != null && !user.isSuperAdmin) ? user.branchId : null;
    // Watch the SQLite-backed store — updates every 500 ms via WS
    final filtered = _applySearchFilter(ref.watch(productStoreProvider(branchId)));

    if (_isLoadingProducts && filtered.isEmpty) {
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

    if (_productsError != null && filtered.isEmpty) {
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
              CustomButton(
                text: 'Coba Lagi',
                icon: Icons.refresh,
                onPressed: () => _loadProducts(forceRefresh: true),
              ),
            ],
          ),
        ),
      );
    }

    if (filtered.isEmpty) {
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
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final product = filtered[index];
            return ProductCard(
              product: product,
              onAdd: () => _addToCart(product),
            );
          },
        ),
      ),
    );
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
                  discount: '${_appliedCoupon!['discount']}% OFF',
                  description: _appliedCoupon!['description'],
                  isApplied: true,
                )
              else
                OutlinedButton.icon(
                  onPressed: () => _changeView(CashierView.coupon),
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

              // ── Payment method ────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cs.outlineVariant, width: 0.8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedPaymentMethod,
                    isExpanded: true,
                    icon: Icon(Icons.keyboard_arrow_down_rounded, color: cs.onSurfaceVariant),
                    items: _paymentMethods.map((method) {
                      final enabled = method['enabled'] as bool;
                      return DropdownMenuItem<String>(
                        value: method['value'],
                        enabled: enabled,
                        child: Row(
                          children: [
                            Icon(method['icon'] as IconData,
                                size: 18, color: enabled ? cs.onSurface : cs.onSurfaceVariant.withValues(alpha: 0.4)),
                            const SizedBox(width: 10),
                            Text(
                              method['label'] as String,
                              style: TextStyle(
                                fontSize: 14,
                                color: enabled ? null : cs.onSurfaceVariant.withValues(alpha: 0.4),
                              ),
                            ),
                            if (!enabled) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Segera',
                                  style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedPaymentMethod = value);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // ── Pay button ────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isProcessingPayment ? null : () => _processPayment(_selectedPaymentMethod),
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
                              'Proses Pembayaran  •  ${CurrencyFormatter.formatToRupiah(_total)}',
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
    return _VoucherPickerView(
      subtotal: _subtotal,
      onBack: () => _changeView(CashierView.cart),
      onSelected: (voucher) {
        setState(() {
          _appliedCoupon = {
            'code': voucher.code,
            'discount': voucher.discountType == 'percent' ? voucher.discountValue : null,
            'fixedDiscount': voucher.discountType == 'fixed' ? voucher.discountValue : null,
            'discountType': voucher.discountType,
            'description': voucher.description ?? voucher.discountLabel,
          };
          _currentView = CashierView.cart;
        });
      },
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

// ─────────────────────────────────────────────────────────────────────────────
// Shared live-connection indicator dot
// ─────────────────────────────────────────────────────────────────────────────

/// A small animated dot that shows the Socket.IO connection status.
/// Green = live, Red = disconnected / reconnecting.
class _LiveDot extends ConsumerWidget {
  final ProviderBase<AsyncValue<bool>> provider;
  const _LiveDot({required this.provider});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLive = ref.watch(provider).valueOrNull ?? false;
    return Tooltip(
      message: isLive ? 'Live updates aktif' : 'Tidak terhubung — data mungkin tidak terbaru',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isLive ? AppTheme.success : AppTheme.destructive,
          boxShadow: isLive
              ? [BoxShadow(color: AppTheme.success.withValues(alpha: 0.5), blurRadius: 6, spreadRadius: 1)]
              : null,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Voucher picker — shows ALL vouchers; unavailable ones are greyed with reason
// ─────────────────────────────────────────────────────────────────────────────

class _VoucherPickerView extends StatefulWidget {
  final double subtotal;
  final VoidCallback onBack;
  final ValueChanged<Voucher> onSelected;

  const _VoucherPickerView({
    required this.subtotal,
    required this.onBack,
    required this.onSelected,
  });

  @override
  State<_VoucherPickerView> createState() => _VoucherPickerViewState();
}

class _VoucherPickerViewState extends State<_VoucherPickerView> {
  List<Voucher> _vouchers = [];
  bool _loading = true;
  String? _error;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await VoucherService.getAllForCashier();
      if (mounted) {
        setState(() {
          _vouchers = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  List<Voucher> get _filtered {
    if (_query.isEmpty) return _vouchers;
    final q = _query.toLowerCase();
    return _vouchers
        .where((v) => v.code.toLowerCase().contains(q) || (v.description?.toLowerCase().contains(q) ?? false))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        // ── Header ────────────────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: cs.outlineVariant, width: 0.8)),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back),
              ),
              Text('Pilih Voucher',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),

        // ── Search ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Cari kode atau deskripsi...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      })
                  : null,
              filled: true,
              fillColor: cs.surfaceContainerHighest,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ),

        // ── List ──────────────────────────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.gold))
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, size: 40, color: AppTheme.destructive),
                          const SizedBox(height: 12),
                          Text('Gagal memuat voucher', style: Theme.of(context).textTheme.bodyMedium),
                          const SizedBox(height: 12),
                          TextButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Coba Lagi'),
                          ),
                        ],
                      ),
                    )
                  : _filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.local_offer_outlined,
                                  size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.35)),
                              const SizedBox(height: 12),
                              Text(
                                _query.isNotEmpty ? 'Voucher tidak ditemukan' : 'Belum ada voucher tersedia',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 80),
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _VoucherPickerTile(
                            voucher: _filtered[i],
                            subtotal: widget.subtotal,
                            onTap: _filtered[i].canUse ? () => widget.onSelected(_filtered[i]) : null,
                          ),
                        ),
        ),
      ],
    );
  }
}

// ── Single voucher row in the picker ─────────────────────────────────────────

class _VoucherPickerTile extends StatelessWidget {
  final Voucher voucher;
  final double subtotal;
  final VoidCallback? onTap; // null = unavailable

  const _VoucherPickerTile({
    required this.voucher,
    required this.subtotal,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final available = onTap != null;
    final reason = voucher.whyUnavailable;

    // Compute preview discount
    String discountPreview = '';
    if (available) {
      final amt = voucher.discountType == 'fixed'
          ? voucher.discountValue.clamp(0, subtotal)
          : subtotal * (voucher.discountValue / 100);
      discountPreview = '- ${CurrencyFormatter.formatToCompactRupiah(amt)}';
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedOpacity(
        opacity: available ? 1.0 : 0.5,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: available ? AppTheme.gold.withValues(alpha: 0.06) : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: available ? AppTheme.gold.withValues(alpha: 0.30) : cs.outlineVariant.withValues(alpha: 0.5),
              width: available ? 1.5 : 0.8,
            ),
          ),
          child: Row(
            children: [
              // Icon badge
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: available ? AppTheme.gold.withValues(alpha: 0.12) : cs.onSurface.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.local_offer_outlined,
                  size: 20,
                  color: available ? AppTheme.gold : cs.onSurface.withValues(alpha: 0.3),
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
                                  color: available ? AppTheme.gold : cs.onSurface.withValues(alpha: 0.4),
                                ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _Chip(
                          voucher.discountLabel,
                          available ? AppTheme.gold : cs.onSurfaceVariant,
                        ),
                      ],
                    ),
                    if (voucher.description != null && voucher.description!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        voucher.description!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        // Usage counter
                        _Chip(
                          voucher.usageLabel,
                          available ? cs.onSurfaceVariant : cs.onSurface.withValues(alpha: 0.3),
                          filled: false,
                        ),
                        // Validity
                        if (voucher.validTo != null) ...[
                          const SizedBox(width: 6),
                          _Chip(
                            's/d ${_shortDate(voucher.validTo!)}',
                            available ? cs.onSurfaceVariant : cs.onSurface.withValues(alpha: 0.3),
                            filled: false,
                          ),
                        ],
                        // Unavailable reason badge
                        if (!available && reason != null) ...[
                          const SizedBox(width: 6),
                          _Chip(reason, AppTheme.destructive),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Right: discount preview or lock icon
              const SizedBox(width: 8),
              if (available && discountPreview.isNotEmpty)
                Text(
                  discountPreview,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppTheme.success,
                        fontWeight: FontWeight.bold,
                      ),
                )
              else if (!available)
                Icon(Icons.lock_outline, size: 18, color: cs.onSurface.withValues(alpha: 0.3)),
            ],
          ),
        ),
      ),
    );
  }

  static String _shortDate(String iso) {
    try {
      final d = DateTime.parse(iso);
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    } catch (_) {
      return iso;
    }
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final bool filled;

  const _Chip(this.label, this.color, {this.filled = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: filled ? color.withValues(alpha: 0.3) : color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: filled ? FontWeight.w600 : FontWeight.normal,
            ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
