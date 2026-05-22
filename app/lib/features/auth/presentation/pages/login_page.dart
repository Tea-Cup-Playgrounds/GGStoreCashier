import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/provider/auth_provider.dart';
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
    _logoScaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoAnimationController,
        curve: Curves.elasticOut,
      ),
    );
    _formSlideAnimation = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _formAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );
    _logoAnimationController.forward();
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _formAnimationController.forward();
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
    final success = await ref.read(authProvider.notifier).login(
          _usernameController.text.trim(),
          _passwordController.text,
          rememberMe: _rememberMe,
        );
    if (success && mounted) {
      context.go(AppRouter.home);
    }
  }

  String? _validateUsername(String? value) {
    if (value == null || value.trim().isEmpty) return 'Username Wajib Diisi';
    if (value.trim().length < 3) return 'Username minimal 3 karakter';
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Password Wajib Diisi';
    if (value.length < 6) return 'Password minimal 6 karakter';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final screenType = getScreenType(context);
    final orientation = getOrientation(context);

    final logoSize = screenType == ScreenType.tablet ? 140.0 : 120.0;
    final spacing = screenType == ScreenType.tablet ? 36.0 : 24.0;
    final hPad = Breakpoints.getHorizontalPadding(screenType, orientation).clamp(20.0, 48.0);

    final isLocked = authState.isLockedOut && !ref.read(authProvider.notifier).isLockoutExpired();
    final canSubmit = !authState.isLoading && !isLocked;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 24),
              child: ConstrainedBox(
                // Ensure content fills the screen so Spacers work for centering
                constraints: BoxConstraints(minHeight: (constraints.maxHeight - 48).clamp(0.0, double.infinity)),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Spacer(),

                      // ── Logo ──────────────────────────────────────────
                      Center(
                        child: ScaleTransition(
                          scale: _logoScaleAnimation,
                          child: Image.asset(
                            'assets/images/GG_Logo.webp',
                            width: logoSize,
                            height: logoSize,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.store,
                              size: logoSize * 0.6,
                              color: const Color(0xFFD4AF37),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: spacing),

                      // ── Title ─────────────────────────────────────────
                      Text(
                        'Selamat Datang',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: screenType == ScreenType.tablet ? 40 : null,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Silakan masuk ke akun Anda',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontSize: screenType == ScreenType.tablet ? 18 : null,
                            ),
                      ),
                      SizedBox(height: spacing),

                      // ── Error Banner ──────────────────────────────────
                      if (authState.error != null) ...[
                        _ErrorBanner(
                          message: authState.error!,
                          remainingAttempts: authState.remainingAttempts,
                          isLockedOut: authState.isLockedOut,
                          lockoutMinutes:
                              authState.isLockedOut ? ref.read(authProvider.notifier).getRemainingLockoutMinutes() : 0,
                        ),
                        const SizedBox(height: 16),
                      ],

                      // ── Form ──────────────────────────────────────────
                      SlideTransition(
                        position: _formSlideAnimation,
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextInput(
                                controller: _usernameController,
                                label: 'Username',
                                hintText: 'Masukkan username anda',
                                prefixIcon: Icons.person_outline,
                                validator: _validateUsername,
                                keyboardType: TextInputType.text,
                              ),
                              const SizedBox(height: 16),
                              TextInput(
                                controller: _passwordController,
                                label: 'Password',
                                hintText: 'Masukkan password anda',
                                prefixIcon: Icons.lock_outline,
                                obscureText: _obscurePassword,
                                validator: _validatePassword,
                                suffixIcon: IconButton(
                                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                  icon: Icon(
                                    _obscurePassword ? Icons.visibility : Icons.visibility_off,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Checkbox(
                                    value: _rememberMe,
                                    onChanged: (v) => setState(() => _rememberMe = v ?? false),
                                  ),
                                  Text(
                                    'Remember me',
                                    style: Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              CustomButton(
                                text: 'Sign In',
                                fullWidth: true,
                                isLoading: authState.isLoading,
                                onPressed: canSubmit ? _handleLogin : null,
                                variant: ButtonVariant.primary,
                                size: ButtonSize.large,
                              ),
                            ],
                          ),
                        ),
                      ),

                      const Spacer(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── Error Banner ──────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String message;
  final int? remainingAttempts;
  final bool isLockedOut;
  final int lockoutMinutes;

  const _ErrorBanner({
    required this.message,
    this.remainingAttempts,
    required this.isLockedOut,
    required this.lockoutMinutes,
  });

  @override
  Widget build(BuildContext context) {
    const errorColor = Color(0xFFEF4444);
    const errorBg = Color(0xFFFEF2F2);
    const errorBorder = Color(0xFFFCA5A5);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? errorColor.withValues(alpha: 0.12) : errorBg;
    final borderColor = isDark ? errorColor.withValues(alpha: 0.35) : errorBorder;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline, color: errorColor, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: errorColor,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
            ],
          ),
          if (remainingAttempts != null && remainingAttempts! > 0) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Text(
                'Sisa percobaan: $remainingAttempts',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: errorColor),
              ),
            ),
          ],
          if (isLockedOut && lockoutMinutes > 0) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Text(
                'Akun terkunci selama $lockoutMinutes menit',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: errorColor,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
