import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/models/product.dart';
import '../../../../core/models/cart_item.dart';
import '../../../../core/helper/screen_type_utils.dart';
import '../../../../core/constants/screen_breakpoints.dart';
import '../../../../shared/widgets/custom_button.dart';
import '../widgets/product_card.dart';
import '../widgets/cart_item_widget.dart';
import '../widgets/coupon_card.dart';
import '../widgets/payment_success_view.dart';

enum CashierView { products, cart, coupon, success }

class CashierPage extends StatefulWidget {
  const CashierPage({super.key});

  @override
  State<CashierPage> createState() => _CashierPageState();
}

class _CashierPageState extends State<CashierPage>
    with TickerProviderStateMixin {
  CashierView _currentView = CashierView.products;
  final List<CartItem> _cart = [];
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _couponController = TextEditingController();

  Map<String, dynamic>? _appliedCoupon;
  bool _isApplyingCoupon = false;
  String _selectedPaymentMethod = 'cash';

  late AnimationController _viewAnimationController;
  // late Animation<Offset> _slideAnimation;

  // Payment methods from database
  final List<Map<String, dynamic>> _paymentMethods = [
    {'value': 'cash', 'label': 'Cash', 'icon': Icons.payments_outlined},
    {'value': 'card', 'label': 'Card', 'icon': Icons.credit_card},
    {'value': 'transfer', 'label': 'Bank Transfer', 'icon': Icons.account_balance},
    {'value': 'e-wallet', 'label': 'E-Wallet', 'icon': Icons.wallet},
  ];

  // Sample products
  final List<Product> _products = [
    Product(
      id: '1',
      name: 'Signature Watch',
      sellPrice: 100.99,
      costPrice: 200.00,
      stock: 15,
      category: 'Accessories',
      image: '',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
    Product(
      id: '2',
      name: 'Leather Wallet',
      sellPrice: 89.99,
      costPrice: 60.00,
      stock: 28,
      category: 'Accessories',
      image: '',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
    Product(
      id: '3',
      name: 'Premium Sunglasses',
      sellPrice: 149.99,
      costPrice: 100.00,
      stock: 4,
      category: 'Eyewear',
      image: '',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
    Product(
      id: '4',
      name: 'Gold Bracelet',
      sellPrice: 199.99,
      costPrice: 150.00,
      stock: 12,
      category: 'Jewelry',
      image: '',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
    Product(
      id: '5',
      name: 'Silk Scarf',
      sellPrice: 79.99,
      costPrice: 50.00,
      stock: 22,
      category: 'Apparel',
      image: '',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
    Product(
      id: '6',
      name: 'Diamond Earrings',
      sellPrice: 449.99,
      costPrice: 300.00,
      stock: 8,
      category: 'Jewelry',
      image: '',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _setupAnimations();
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
    _viewAnimationController.dispose();
    _searchController.dispose();
    _couponController.dispose();
    super.dispose();
  }

  void _addToCart(Product product) {
    setState(() {
      final existingIndex = _cart.indexWhere((item) => item.id == product.id);
      if (existingIndex >= 0) {
        _cart[existingIndex] = _cart[existingIndex].incrementQuantity();
      } else {
        _cart.add(CartItem.fromProduct(product));
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${product.name} added to cart'),
        backgroundColor: AppTheme.gold,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _updateCartItemQuantity(String id, int delta) {
    setState(() {
      final index = _cart.indexWhere((item) => item.id == id);
      if (index >= 0) {
        final newQuantity = _cart[index].quantity + delta;
        if (newQuantity <= 0) {
          _cart.removeAt(index);
        } else {
          _cart[index] = _cart[index].copyWith(quantity: newQuantity);
        }
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

    // Simulate API call
    await Future.delayed(const Duration(milliseconds: 1000));

    setState(() {
      _isApplyingCoupon = false;
      if (code == 'GOLD20' || code == 'VIP15') {
        _appliedCoupon = {
          'code': code,
          'discount': code == 'GOLD20' ? 20 : 15,
          'description': code == 'GOLD20'
              ? 'Premium member discount'
              : 'VIP customer exclusive',
        };
        _currentView = CashierView.cart;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Coupon $code applied successfully!'),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Invalid or expired coupon code'),
            backgroundColor: AppTheme.destructive,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    });
  }

  Future<void> _processPayment(String method) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Processing payment via $method...'),
        backgroundColor: AppTheme.gold,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );

    await Future.delayed(const Duration(milliseconds: 1500));

    setState(() {
      _currentView = CashierView.success;
    });
  }

  void _resetTransaction() {
    setState(() {
      _cart.clear();
      _appliedCoupon = null;
      _couponController.clear();
      _currentView = CashierView.products;
    });
  }

  double get _subtotal => _cart.fold(0, (sum, item) => sum + item.subtotal);

  double get _discount {
    if (_appliedCoupon == null) return 0;
    return _subtotal * (_appliedCoupon!['discount'] / 100);
  }

  double get _total => _subtotal - _discount;

  List<Product> get _filteredProducts {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) return _products;

    return _products.where((product) {
      return product.name.toLowerCase().contains(query) ||
          (product.category?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final screenType = getScreenType(context);
    final orientation = getOrientation(context);
    
    if (_currentView == CashierView.success) {
      return PaymentSuccessView(
        total: _total,
        appliedCoupon: _appliedCoupon,
        onNewTransaction: _resetTransaction,
      );
    }

    // Use split-screen for tablets
    final isTablet = screenType == ScreenType.tablet;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(isTablet ? 'New Sale' : _getAppBarTitle()),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        actions: [
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
                        '${_cart.fold(0, (sum, item) => sum + item.quantity)}',
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
          if (!isTablet && _currentView != CashierView.products)
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
        final leftWidth = isLandscape 
            ? constraints.maxWidth * 0.6 
            : constraints.maxWidth * 0.5;
        
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
                        hintText: 'Search products...',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) => setState(() {}),
                    ),
                  ),
                  // Products Grid
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: isLandscape ? 3 : 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.8,
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
                          'Order Summary',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_cart.isNotEmpty)
                          Text(
                            '${_cart.fold(0, (sum, item) => sum + item.quantity)} items',
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
                                  color: AppTheme.mutedForeground.withOpacity(0.5),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Cart is empty',
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
                                text: 'Add Coupon',
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
                                color: AppTheme.muted.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('Subtotal'),
                                      Text(
                                        '\$${_subtotal.toStringAsFixed(2)}',
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
                                          'Discount',
                                          style: TextStyle(color: AppTheme.success),
                                        ),
                                        Text(
                                          '-\$${_discount.toStringAsFixed(2)}',
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
                                        '\$${_total.toStringAsFixed(2)}',
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
                                    return DropdownMenuItem<String>(
                                      value: method['value'],
                                      child: Row(
                                        children: [
                                          Icon(method['icon'] as IconData, size: 20),
                                          const SizedBox(width: 12),
                                          Text(method['label'] as String),
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
                            
                            // Process Payment Button
                            CustomButton(
                              text: 'Process Payment',
                              icon: Icons.check_circle_outline,
                              onPressed: () => _processPayment(_selectedPaymentMethod),
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
        return 'New Sale';
      case CashierView.cart:
        return 'Cart';
      case CashierView.coupon:
        return 'Apply Coupon';
      case CashierView.success:
        return 'Payment Success';
    }
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _searchController,
        decoration: const InputDecoration(
          hintText: 'Search products...',
          prefixIcon: Icon(Icons.search),
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
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 0.8,
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
    );
  }

  Widget _buildCartView() {
    return Column(
      children: [
        Expanded(
          child: _cart.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.shopping_cart_outlined,
                        size: 64,
                        color: AppTheme.mutedForeground,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Your cart is empty',
                        style: TextStyle(
                          color: AppTheme.mutedForeground,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _cart.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
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
        if (_cart.isNotEmpty) _buildCartSummary(),
      ],
    );
  }

  Widget _buildCartSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        border: Border(
            top: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant)),
      ),
      child: Column(
        children: [
          // Coupon Section
          if (_appliedCoupon != null)
            CouponCard(
              code: _appliedCoupon!['code'],
              discount: '${_appliedCoupon!['discount']}% OFF',
              description: _appliedCoupon!['description'],
              isApplied: true,
            )
          else
            CustomButton(
              text: 'Add Coupon / Voucher',
              variant: ButtonVariant.outline,
              icon: Icons.local_offer_outlined,
              onPressed: () => _changeView(CashierView.coupon),
              fullWidth: true,
            ),

          const SizedBox(height: 16),

          // Totals
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Subtotal'),
                    Text('\$${_subtotal.toStringAsFixed(2)}'),
                  ],
                ),
                if (_discount > 0) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Discount',
                          style: TextStyle(color: AppTheme.success)),
                      Text(
                        '-\$${_discount.toStringAsFixed(2)}',
                        style: const TextStyle(color: AppTheme.success),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Divider(color: Theme.of(context).colorScheme.outlineVariant),
                const SizedBox(height: 8),
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
                      '\$${_total.toStringAsFixed(2)}',
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
                  return DropdownMenuItem<String>(
                    value: method['value'],
                    child: Row(
                      children: [
                        Icon(method['icon'] as IconData, size: 20),
                        const SizedBox(width: 12),
                        Text(method['label'] as String),
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

          // Process Payment Button
          CustomButton(
            text: 'Process Payment',
            icon: Icons.check_circle_outline,
            onPressed: () => _processPayment(_selectedPaymentMethod),
            fullWidth: true,
            size: ButtonSize.large,
          ),
        ],
      ),
    );
  }

  Widget _buildCouponView() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Enter Coupon Code',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _couponController,
                  decoration: const InputDecoration(
                    hintText: 'e.g. GOLD20',
                  ),
                  textCapitalization: TextCapitalization.characters,
                ),
              ),
              const SizedBox(width: 12),
              CustomButton(
                text: _isApplyingCoupon ? 'Applying...' : 'Apply',
                onPressed: _isApplyingCoupon ? null : _applyCoupon,
                isLoading: _isApplyingCoupon,
              ),
            ],
          ),
          const SizedBox(height: 32),
          Text(
            'Available Coupons',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          const CouponCard(
            code: 'GOLD20',
            discount: '20% OFF',
            description: 'Premium member discount',
            expiresAt: 'Dec 31, 2024',
          ),
          const SizedBox(height: 12),
          const CouponCard(
            code: 'VIP15',
            discount: '15% OFF',
            description: 'VIP customer exclusive',
            expiresAt: 'Jan 15, 2025',
          ),
        ],
      ),
    );
  }

  void _changeView(CashierView newView) {
    setState(() {
      _currentView = newView;
    });
    _viewAnimationController.forward(from: 0);
  }
}
