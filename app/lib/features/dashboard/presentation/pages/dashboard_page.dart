import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/router/app_router.dart';
import '../../../../shared/widgets/bottom_navigation.dart';
import '../widgets/stat_card.dart';
import '../widgets/quick_action_card.dart';
import '../widgets/transaction_item.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late List<Animation<Offset>> _slideAnimations;
  late List<Animation<double>> _fadeAnimations;

  final List<Map<String, dynamic>> _recentTransactions = [
    {
      'id': '1',
      'time': '2 min ago',
      'items': 3,
      'total': 125.50,
      'payment': 'Card'
    },
    {
      'id': '2',
      'time': '15 min ago',
      'items': 1,
      'total': 45.00,
      'payment': 'Cash'
    },
    {
      'id': '3',
      'time': '32 min ago',
      'items': 5,
      'total': 289.99,
      'payment': 'Card'
    },
    {
      'id': '4',
      'time': '1 hr ago',
      'items': 2,
      'total': 78.25,
      'payment': 'Cash'
    },
  ];

  @override
  void initState() {
    super.initState();
    _setupAnimations();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _slideAnimations = List.generate(6, (index) {
      return Tween<Offset>(
        begin: const Offset(0, 0.3),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _animationController,
        curve: Interval(
          index * 0.1,
          0.6 + (index * 0.1),
          curve: Curves.easeOutCubic,
        ),
      ));
    });

    _fadeAnimations = List.generate(6, (index) {
      return Tween<double>(
        begin: 0.0,
        end: 1.0,
      ).animate(CurvedAnimation(
        parent: _animationController,
        curve: Interval(
          index * 0.1,
          0.6 + (index * 0.1),
          curve: Curves.easeOut,
        ),
      ));
    });

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 18) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    SlideTransition(
                      position: _slideAnimations[0],
                      child: FadeTransition(
                        opacity: _fadeAnimations[0],
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppTheme.gold.withOpacity(0.05),
                                Colors.transparent,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _getGreeting(),
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: AppTheme.mutedForeground,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Flagship Store',
                                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Stats Grid
                    SlideTransition(
                      position: _slideAnimations[1],
                      child: FadeTransition(
                        opacity: _fadeAnimations[1],
                        child: GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 2,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 1.2,
                          children: const [
                            StatCard(
                              icon: Icons.attach_money,
                              label: "Today's Sales",
                              value: '\$2,458',
                              trend: 12.5,
                              isPositive: true,
                              isHighlighted: true,
                            ),
                            StatCard(
                              icon: Icons.shopping_bag_outlined,
                              label: 'Orders',
                              value: '48',
                              trend: 8.2,
                              isPositive: true,
                            ),
                            StatCard(
                              icon: Icons.trending_up,
                              label: 'Avg. Order',
                              value: '\$51.21',
                            ),
                            StatCard(
                              icon: Icons.access_time,
                              label: 'Active Hours',
                              value: '6.5h',
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Quick Actions
                    SlideTransition(
                      position: _slideAnimations[2],
                      child: FadeTransition(
                        opacity: _fadeAnimations[2],
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Quick Actions',
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: QuickActionCard(
                                    icon: Icons.shopping_cart_outlined,
                                    label: 'New Sale',
                                    onTap: () => context.go(AppRouter.pos),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: QuickActionCard(
                                    icon: Icons.local_offer_outlined,
                                    label: 'Apply Coupon',
                                    onTap: () => context.go(AppRouter.pos),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: QuickActionCard(
                                    icon: Icons.inventory_2_outlined,
                                    label: 'Check Stock',
                                    onTap: () => context.go(AppRouter.inventory),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Recent Transactions
                    SlideTransition(
                      position: _slideAnimations[3],
                      child: FadeTransition(
                        opacity: _fadeAnimations[3],
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Recent Transactions',
                                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    // TODO: Navigate to transactions page
                                  },
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'View All',
                                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                          color: AppTheme.gold,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(
                                        Icons.chevron_right,
                                        size: 16,
                                        color: AppTheme.gold,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _recentTransactions.length,
                              separatorBuilder: (context, index) => const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final transaction = _recentTransactions[index];
                                return SlideTransition(
                                  position: _slideAnimations[4],
                                  child: FadeTransition(
                                    opacity: _fadeAnimations[4],
                                    child: TransactionItem(
                                      id: transaction['id'],
                                      time: transaction['time'],
                                      items: transaction['items'],
                                      total: transaction['total'],
                                      paymentMethod: transaction['payment'],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 100), // Bottom padding for navigation
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const BottomNavigation(),
    );
  }
}