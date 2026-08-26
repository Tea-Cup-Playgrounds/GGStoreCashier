import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/provider/auth_provider.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/snackbar_service.dart';
import '../../../../shared/widgets/custom_button.dart';

const _biometricKey = 'biometric_login_enabled';

class PrivacySecurityPage extends ConsumerStatefulWidget {
  const PrivacySecurityPage({super.key});

  @override
  ConsumerState<PrivacySecurityPage> createState() => _PrivacySecurityPageState();
}

class _PrivacySecurityPageState extends ConsumerState<PrivacySecurityPage> {
  final _localAuth = LocalAuthentication();
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  List<BiometricType> _availableBiometrics = [];

  @override
  void initState() {
    super.initState();
    _initBiometric();
  }

  Future<void> _initBiometric() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      final biometrics = await _localAuth.getAvailableBiometrics();
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(_biometricKey) ?? false;
      if (mounted) {
        setState(() {
          _biometricAvailable = canCheck || isDeviceSupported;
          _availableBiometrics = biometrics;
          _biometricEnabled = enabled && _biometricAvailable;
        });
      }
    } catch (_) {}
  }

  String get _biometricLabel {
    if (_availableBiometrics.contains(BiometricType.face)) return 'Face Recognition';
    if (_availableBiometrics.contains(BiometricType.fingerprint)) return 'Fingerprint';
    if (_availableBiometrics.contains(BiometricType.strong)) return 'Biometric';
    return 'Device Security (PIN/Password)';
  }

  IconData get _biometricIcon {
    if (_availableBiometrics.contains(BiometricType.face)) return Icons.face_outlined;
    if (_availableBiometrics.contains(BiometricType.fingerprint)) return Icons.fingerprint;
    return Icons.lock_outlined;
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value) {
      // Prompt once to confirm device credential works before enabling
      try {
        final authenticated = await _localAuth.authenticate(
          localizedReason: 'Konfirmasi untuk mengaktifkan login biometrik',
          options: const AuthenticationOptions(
            biometricOnly: false,
            stickyAuth: true,
          ),
        );
        if (!authenticated) return;
      } catch (e) {
        if (mounted) SnackBarService.error('Autentikasi gagal: ${e.toString()}');
        return;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricKey, value);
    if (mounted) setState(() => _biometricEnabled = value);
    if (mounted) {
      SnackBarService.success(value ? 'Login biometrik diaktifkan' : 'Login biometrik dinonaktifkan');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = ref.watch(authProvider).user;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        title: const Text('Privasi & Keamanan'),
        backgroundColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Profile section ───────────────────────────────────────
            const _SectionLabel('PROFIL'),
            const SizedBox(height: 8),
            _SecurityGroup(children: [
              _SecurityTile(
                icon: Icons.person_outline,
                title: 'Ganti Nama',
                subtitle: user?.name ?? '-',
                onTap: () => _showEditDialog(
                  context: context,
                  title: 'Ganti Nama',
                  label: 'Nama Lengkap',
                  initialValue: user?.name ?? '',
                  field: 'name',
                ),
              ),
              _SecurityTile(
                icon: Icons.alternate_email,
                title: 'Ganti Username',
                subtitle: '@${user?.username ?? '-'}',
                onTap: () => _showEditDialog(
                  context: context,
                  title: 'Ganti Username',
                  label: 'Username',
                  initialValue: user?.username ?? '',
                  field: 'username',
                ),
              ),
            ]),
            const SizedBox(height: 24),

            // ── Password section ──────────────────────────────────────
            const _SectionLabel('PASSWORD'),
            const SizedBox(height: 8),
            _SecurityGroup(children: [
              _SecurityTile(
                icon: Icons.lock_outline,
                title: 'Ganti Password',
                subtitle: 'Ubah kata sandi akun Anda',
                onTap: () => _showChangePasswordDialog(context),
              ),
            ]),
            const SizedBox(height: 24),

            // ── Biometric section ─────────────────────────────────────
            const _SectionLabel('LOGIN KEAMANAN PERANGKAT'),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outlineVariant, width: 0.8),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(_biometricIcon, size: 20, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_biometricLabel, style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 2),
                          Text(
                            _biometricAvailable
                                ? 'Gunakan keamanan perangkat untuk masuk'
                                : 'Tidak tersedia di perangkat ini',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: _biometricEnabled,
                      onChanged: _biometricAvailable ? _toggleBiometric : null,
                      activeTrackColor: AppTheme.gold,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Edit name / username dialog ──────────────────────────────────────────

  void _showEditDialog({
    required BuildContext context,
    required String title,
    required String label,
    required String initialValue,
    required String field,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _EditFieldSheet(
        title: title,
        label: label,
        initialValue: initialValue,
        field: field,
        onSaved: () => _reloadUser(),
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _ChangePasswordSheet(onSaved: () {}),
    );
  }

  Future<void> _reloadUser() async {
    // Refresh auth state by re-hydrating from server
    final token = await AuthService.getToken();
    if (token == null) return;
    try {
      final dio = Dio(BaseOptions(
        baseUrl: ApiConfig.apiUrl,
        headers: {'Authorization': 'Bearer $token', ...ApiConfig.defaultHeaders},
      ));
      final res = await dio.get('/api/auth/me');
      final user = res.data['user'];
      // Update SharedPreferences cached user
      await AuthService.saveUser(user);
      if (mounted) {
        // Force re-hydrate auth state
        ref.read(authProvider.notifier).refreshUser(user);
      }
    } catch (_) {}
  }
}

// ── Edit field sheet ──────────────────────────────────────────────────────────

class _EditFieldSheet extends StatefulWidget {
  final String title;
  final String label;
  final String initialValue;
  final String field;
  final VoidCallback onSaved;

  const _EditFieldSheet({
    required this.title,
    required this.label,
    required this.initialValue,
    required this.field,
    required this.onSaved,
  });

  @override
  State<_EditFieldSheet> createState() => _EditFieldSheetState();
}

class _EditFieldSheetState extends State<_EditFieldSheet> {
  late TextEditingController _controller;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = _controller.text.trim();
    if (value.isEmpty || value == widget.initialValue) {
      Navigator.pop(context);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final token = await AuthService.getToken();
      final dio = Dio(BaseOptions(
        baseUrl: ApiConfig.apiUrl,
        headers: {'Authorization': 'Bearer $token', ...ApiConfig.defaultHeaders},
      ));
      await dio.put('/api/users/me/profile', data: {widget.field: value});
      if (mounted) {
        Navigator.pop(context);
        SnackBarService.success('${widget.title} berhasil diperbarui');
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        final msg = (e is DioException) ? (e.response?.data?['error'] ?? 'Gagal menyimpan') : 'Gagal menyimpan';
        SnackBarService.error(msg);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 20, 16, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Text(widget.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: widget.label,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.gold, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          CustomButton(
            text: 'Simpan',
            fullWidth: true,
            size: ButtonSize.large,
            isLoading: _isLoading,
            onPressed: _isLoading ? null : _save,
          ),
        ],
      ),
    );
  }
}

// ── Change password sheet ─────────────────────────────────────────────────────

class _ChangePasswordSheet extends StatefulWidget {
  final VoidCallback onSaved;
  const _ChangePasswordSheet({required this.onSaved});

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _isLoading = false;
  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_newCtrl.text != _confirmCtrl.text) {
      SnackBarService.error('Konfirmasi password tidak cocok');
      return;
    }
    if (_newCtrl.text.length < 8) {
      SnackBarService.error('Password minimal 8 karakter');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final token = await AuthService.getToken();
      final dio = Dio(BaseOptions(
        baseUrl: ApiConfig.apiUrl,
        headers: {'Authorization': 'Bearer $token', ...ApiConfig.defaultHeaders},
      ));
      await dio.put('/api/users/me/profile', data: {
        'currentPassword': _currentCtrl.text,
        'newPassword': _newCtrl.text,
      });
      if (mounted) {
        Navigator.pop(context);
        SnackBarService.success('Password berhasil diperbarui');
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        final msg = (e is DioException)
            ? (e.response?.data?['error'] ?? 'Gagal mengganti password')
            : 'Gagal mengganti password';
        SnackBarService.error(msg);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 20, 16, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 16),
          Text('Ganti Password', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          _PwdField(
              ctrl: _currentCtrl,
              label: 'Password Saat Ini',
              show: _showCurrent,
              onToggle: () => setState(() => _showCurrent = !_showCurrent)),
          const SizedBox(height: 12),
          _PwdField(
              ctrl: _newCtrl,
              label: 'Password Baru',
              show: _showNew,
              onToggle: () => setState(() => _showNew = !_showNew)),
          const SizedBox(height: 12),
          _PwdField(
              ctrl: _confirmCtrl,
              label: 'Konfirmasi Password Baru',
              show: _showConfirm,
              onToggle: () => setState(() => _showConfirm = !_showConfirm)),
          const SizedBox(height: 8),
          Text('Min. 8 karakter, kombinasi huruf besar, kecil, angka.',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 20),
          CustomButton(
            text: 'Perbarui Password',
            fullWidth: true,
            size: ButtonSize.large,
            isLoading: _isLoading,
            onPressed: _isLoading ? null : _save,
          ),
        ],
      ),
    );
  }
}

class _PwdField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final bool show;
  final VoidCallback onToggle;
  const _PwdField({required this.ctrl, required this.label, required this.show, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      obscureText: !show,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.gold, width: 2),
        ),
        suffixIcon: IconButton(
          icon: Icon(show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
          onPressed: onToggle,
        ),
      ),
    );
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              )),
    );
  }
}

class _SecurityGroup extends StatelessWidget {
  final List<Widget> children;
  const _SecurityGroup({required this.children});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant, width: 0.8),
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1) Divider(height: 1, indent: 56, color: cs.outlineVariant),
          ],
        ],
      ),
    );
  }
}

class _SecurityTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _SecurityTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 20, color: cs.onSurfaceVariant),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }
}
