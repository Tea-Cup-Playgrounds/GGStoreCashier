import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/provider/auth_provider.dart';
import '../../../../core/widgets/api_config_dialog.dart';
import '../../../../core/helper/screen_type_utils.dart';
import '../../../../core/constants/screen_breakpoints.dart';
import '../../../../shared/widgets/custom_button.dart';
import '../../../../shared/widgets/text_input.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _rememberMe = false;

  late AnimationController _logoAnimationController;
  late AnimationController _formAnimationController;
  late Animation<double> _logoScaleAnimation;
  late Animation<Offset> _formSlideAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
  }

  void _setupAnimations() {
    _logoAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _formAnimationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _logoScaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _logoAnimationController,
      curve: Curves.elasticOut,
    ));

    _formSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _formAnimationController,
      curve: Curves.easeOutCubic,
    ));

    // Start animations
    _logoAnimationController.forward();
    Future.delayed(const Duration(milliseconds: 200), () {
      _formAnimationController.forward();
    });
  }

  @override
  void dispose() {
    _logoAnimationController.dispose();
    _formAnimationController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final authNotifier = ref.read(authProvider.notifier);
    final success = await authNotifier.login(
      _usernameController.text.trim(),
      _passwordController.text,
    );

    if (success && mounted) {
      context.go(AppRouter.home);
    }
  }

  String? _validateUsername(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Username is required';
    }
    if (value.trim().length < 3) {
      return 'Username must be at least 3 characters';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final screenType = getScreenType(context);
    final orientation = getOrientation(context);
    final isLandscape = orientation == OrientationType.landscape;

    // Scale everything down in landscape for a desktop-like compact view
    final horizontalPadding = isLandscape ? 24.0 : Breakpoints.getHorizontalPadding(screenType, orientation);
    final logoSize = isLandscape ? 64.0 : (screenType == ScreenType.tablet ? 140.0 : 120.0);
    final maxWidth = screenType == ScreenType.tablet ? 500.0 : 400.0;
    final spacing = isLandscape ? 12.0 : (screenType == ScreenType.tablet ? 40.0 : 32.0);
    final titleScale = isLandscape ? 0.75 : 1.0;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Breakpoints.maxContentWidth),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: isLandscape ? 8.0 : 24.0),
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxWidth),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildLogo(logoSize),
                              SizedBox(height: spacing),
                              _buildTitle(screenType, titleScale),
                              SizedBox(height: spacing + (isLandscape ? 4 : 16)),
                              _buildErrorBanner(authState),
                              _buildForm(authState, spacing),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  _buildFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Shared sub-widgets ───────────────────────────────────────────────────────

  Widget _buildLogo(double size) {
    return ScaleTransition(
      scale: _logoScaleAnimation,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppTheme.gold.withOpacity(0.1),
          borderRadius: BorderRadius.circular(size / 2),
          border: Border.all(color: AppTheme.gold.withOpacity(0.3), width: 2),
        ),
        child: Icon(Icons.store, size: size / 2, color: AppTheme.gold),
      ),
    );
  }

  Widget _buildTitle(ScreenType screenType, [double scale = 1.0]) {
    final baseSize = screenType == ScreenType.tablet ? 40.0 : null;
    final subSize = screenType == ScreenType.tablet ? 18.0 : null;
    return Column(
      children: [
        Text(
          'Welcome Back',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            color: AppTheme.foreground,
            fontWeight: FontWeight.bold,
            fontSize: baseSize != null ? baseSize * scale : (Theme.of(context).textTheme.displaySmall!.fontSize! * scale),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Sign in to your account',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: AppTheme.mutedForeground,
            fontSize: subSize != null ? subSize * scale : (Theme.of(context).textTheme.bodyLarge!.fontSize! * scale),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBanner(dynamic authState) {
    if (authState.error == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: AppTheme.destructive.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.destructive.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline, color: AppTheme.destructive, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  authState.error!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.destructive,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (authState.remainingAttempts != null && authState.remainingAttempts! > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Remaining attempts: ${authState.remainingAttempts}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.destructive),
            ),
          ],
          if (authState.isLockedOut) ...[
            const SizedBox(height: 8),
            Text(
              'Account locked for ${ref.read(authProvider.notifier).getRemainingLockoutMinutes()} minutes',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.destructive,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildForm(dynamic authState, double spacing) {
    return SlideTransition(
      position: _formSlideAnimation,
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            TextInput(
              controller: _usernameController,
              label: 'Username',
              hintText: 'Enter your username',
              prefixIcon: Icons.person_outline,
              validator: _validateUsername,
              keyboardType: TextInputType.text,
            ),
            const SizedBox(height: 24),
            TextInput(
              controller: _passwordController,
              label: 'Password',
              hintText: 'Enter your password',
              prefixIcon: Icons.lock_outline,
              obscureText: _obscurePassword,
              validator: _validatePassword,
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword ? Icons.visibility : Icons.visibility_off,
                  color: AppTheme.mutedForeground,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Checkbox(
                  value: _rememberMe,
                  onChanged: (v) => setState(() => _rememberMe = v ?? false),
                  activeColor: AppTheme.gold,
                ),
                Text(
                  'Remember me',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.foreground),
                ),
              ],
            ),
            SizedBox(height: spacing),
            CustomButton(
              text: 'Sign In',
              fullWidth: true,
              isLoading: authState.isLoading,
              onPressed: (authState.isLockedOut && !ref.read(authProvider.notifier).isLockoutExpired())
                  ? null
                  : _handleLogin,
              variant: ButtonVariant.primary,
              size: ButtonSize.large,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'GG Store Cashier v1.0.0',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.mutedForeground),
        ),
        TextButton(
          onPressed: () => showDialog(
            context: context,
            builder: (context) => const ApiConfigDialog(),
          ),
          child: Text(
            'API Config',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.gold),
          ),
        ),
      ],
    );
  }
}