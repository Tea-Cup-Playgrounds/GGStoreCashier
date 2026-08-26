import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/helper/currency_formatter.dart';
import '../../../../core/models/branch.dart';
import '../../../../core/services/branch_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/custom_button.dart';
import '../../../../shared/widgets/text_input.dart';

class BranchManagementPage extends ConsumerStatefulWidget {
  const BranchManagementPage({super.key});
  @override
  ConsumerState<BranchManagementPage> createState() => _BranchManagementPageState();
}

class _BranchManagementPageState extends ConsumerState<BranchManagementPage> {
  bool _loading = true;
  List<Branch> _branches = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await BranchService.getBranches();
      if (mounted) {
        setState(() {
          _branches = list;
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

  void _openEdit(Branch branch) async {
    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _BranchEditSheet(branch: branch),
    );
    if (updated == true) _load();
  }

  void _openCreate() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _BranchCreateSheet(),
    );
    if (created == true) _load();
  }

  void _confirmDelete(Branch branch) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Cabang'),
        content: Text('Yakin ingin menghapus cabang "${branch.name}"?\n\n'
            'Cabang tidak dapat dihapus jika masih memiliki pengguna atau produk.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await BranchService.deleteBranch(branch.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Cabang berhasil dihapus'),
                    backgroundColor: AppTheme.success,
                    behavior: SnackBarBehavior.floating,
                  ));
                  _load();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(e.toString().replaceFirst('Exception: ', '')),
                    backgroundColor: AppTheme.destructive,
                    behavior: SnackBarBehavior.floating,
                  ));
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.destructive),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Manajemen Cabang'),
        backgroundColor: cs.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        backgroundColor: AppTheme.gold,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Cabang Baru'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.gold))
          : _error != null
              ? _buildError()
              : _buildList(cs),
    );
  }

  Widget _buildError() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 48, color: AppTheme.destructive),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          ElevatedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Coba Lagi')),
        ]),
      );

  Widget _buildList(ColorScheme cs) {
    if (_branches.isEmpty) {
      return const Center(child: Text('Belum ada cabang terdaftar.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: _branches.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final b = _branches[i];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.gold.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                  child: Text(
                b.name.isNotEmpty ? b.name[0].toUpperCase() : '?',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.gold),
              )),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(b.name, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              if (b.address != null && b.address!.isNotEmpty)
                Text(b.address!,
                    style: Theme.of(context).textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (b.targetPendapatan > 0)
                Text('Target: ${CurrencyFormatter.formatToCompactRupiah(b.targetPendapatan)}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppTheme.gold)),
            ])),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              color: AppTheme.mutedForeground,
              onPressed: () => _openEdit(b),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              color: AppTheme.destructive.withValues(alpha: 0.7),
              onPressed: () => _confirmDelete(b),
            ),
          ]),
        );
      },
    );
  }
}

// ── Edit sheet ────────────────────────────────────────────────────────────────

class _BranchEditSheet extends StatefulWidget {
  final Branch branch;
  const _BranchEditSheet({required this.branch});
  @override
  State<_BranchEditSheet> createState() => _BranchEditSheetState();
}

class _BranchEditSheetState extends State<_BranchEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _phone;
  late final TextEditingController _target;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.branch.name);
    _address = TextEditingController(text: widget.branch.address ?? '');
    _phone = TextEditingController(text: widget.branch.phone ?? '');
    _target = TextEditingController(
      text: widget.branch.targetPendapatan > 0 ? widget.branch.targetPendapatan.toInt().toString() : '',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final targetVal = double.tryParse(_target.text.replaceAll(RegExp(r'[^\d]'), ''));
      await BranchService.updateBranch(
        widget.branch.id,
        _name.text.trim(),
        _address.text.trim().isEmpty ? null : _address.text.trim(),
        _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        targetPendapatan: targetVal,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: AppTheme.destructive,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) => _BranchFormSheet(
        formKey: _formKey,
        title: 'Edit Cabang',
        nameController: _name,
        addressController: _address,
        phoneController: _phone,
        targetController: _target,
        saving: _saving,
        onSave: _save,
        submitLabel: 'Simpan Perubahan',
      );
}

// ── Create sheet (branch + admin) ─────────────────────────────────────────────

class _BranchCreateSheet extends StatefulWidget {
  const _BranchCreateSheet();
  @override
  State<_BranchCreateSheet> createState() => _BranchCreateSheetState();
}

class _BranchCreateSheetState extends State<_BranchCreateSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _target = TextEditingController();
  final _aName = TextEditingController();
  final _aUser = TextEditingController();
  final _aPass = TextEditingController();
  bool _saving = false;
  bool _obscure = true;

  @override
  void dispose() {
    for (final c in [_name, _address, _phone, _target, _aName, _aUser, _aPass]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final targetVal = double.tryParse(_target.text.replaceAll(RegExp(r'[^\d]'), ''));
      await BranchService.createBranchWithAdmin(
        name: _name.text.trim(),
        address: _address.text.trim().isEmpty ? null : _address.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        targetPendapatan: targetVal,
        adminName: _aName.text.trim(),
        adminUsername: _aUser.text.trim(),
        adminPassword: _aPass.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppTheme.destructive,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (_, sc) => Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Form(
            key: _formKey,
            child: ListView(controller: sc, padding: const EdgeInsets.all(20), children: [
              _handle(context),
              Text('Cabang Baru', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Buat cabang dan admin pertamanya sekaligus.', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 20),

              // ── Branch fields ──
              _sectionLabel(context, 'Data Cabang', Icons.storefront_outlined),
              const SizedBox(height: 10),
              TextInput(
                  controller: _name,
                  label: 'Nama Cabang',
                  hintText: 'cth. Cabang Semarang',
                  prefixIcon: Icons.storefront_outlined,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null),
              const SizedBox(height: 12),
              TextInput(
                  controller: _address,
                  label: 'Alamat (opsional)',
                  hintText: 'cth. Jl. Pemuda No. 10',
                  prefixIcon: Icons.location_on_outlined,
                  maxLines: 2),
              const SizedBox(height: 12),
              TextInput(
                  controller: _phone,
                  label: 'Telepon (opsional)',
                  hintText: 'cth. 024-1234567',
                  prefixIcon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone),
              const SizedBox(height: 12),
              TextInput(
                controller: _target,
                label: 'Target Pendapatan (opsional)',
                hintText: 'cth. 10000000',
                prefixIcon: Icons.flag_outlined,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 24),

              // ── Admin fields ──
              _sectionLabel(context, 'Admin Pertama', Icons.manage_accounts_outlined),
              const SizedBox(height: 10),
              TextInput(
                  controller: _aName,
                  label: 'Nama Admin',
                  hintText: 'cth. Budi Santoso',
                  prefixIcon: Icons.person_outline,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null),
              const SizedBox(height: 12),
              TextInput(
                  controller: _aUser,
                  label: 'Username',
                  hintText: 'cth. admin_semarang',
                  prefixIcon: Icons.alternate_email,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Wajib diisi';
                    if (!RegExp(r'^[a-zA-Z0-9_\-\.]{3,30}$').hasMatch(v.trim())) {
                      return 'Hanya huruf, angka, _ - . (3-30 karakter)';
                    }
                    return null;
                  }),
              const SizedBox(height: 12),
              // Password field with visibility toggle
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 4),
                  child: Text('Password',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                ),
                TextFormField(
                  controller: _aPass,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    hintText: 'Min. 8 karakter',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Wajib diisi';
                    if (v.length < 8) return 'Minimal 8 karakter';
                    return null;
                  },
                ),
              ]),
              const SizedBox(height: 28),
              CustomButton(
                text: 'Buat Cabang & Admin',
                icon: Icons.check_circle_outline,
                fullWidth: true,
                isLoading: _saving,
                onPressed: _save,
              ),
              const SizedBox(height: 20),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Shared form shell ─────────────────────────────────────────────────────────

class _BranchFormSheet extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final String title;
  final TextEditingController nameController;
  final TextEditingController addressController;
  final TextEditingController phoneController;
  final TextEditingController targetController;
  final bool saving;
  final VoidCallback onSave;
  final String submitLabel;

  const _BranchFormSheet({
    required this.formKey,
    required this.title,
    required this.nameController,
    required this.addressController,
    required this.phoneController,
    required this.targetController,
    required this.saving,
    required this.onSave,
    required this.submitLabel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (_, sc) => Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Form(
            key: formKey,
            child: ListView(controller: sc, padding: const EdgeInsets.all(20), children: [
              _handle(context),
              Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              TextInput(
                  controller: nameController,
                  label: 'Nama Cabang',
                  hintText: 'cth. Cabang Pusat',
                  prefixIcon: Icons.storefront_outlined,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null),
              const SizedBox(height: 12),
              TextInput(
                  controller: addressController,
                  label: 'Alamat',
                  hintText: 'cth. Jl. Sudirman No. 1',
                  prefixIcon: Icons.location_on_outlined,
                  maxLines: 2),
              const SizedBox(height: 12),
              TextInput(
                  controller: phoneController,
                  label: 'Telepon',
                  hintText: 'cth. 024-1234567',
                  prefixIcon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone),
              const SizedBox(height: 12),
              TextInput(
                controller: targetController,
                label: 'Target Pendapatan',
                hintText: 'cth. 10000000',
                prefixIcon: Icons.flag_outlined,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 28),
              CustomButton(
                text: submitLabel,
                icon: Icons.save_outlined,
                fullWidth: true,
                isLoading: saving,
                onPressed: onSave,
              ),
              const SizedBox(height: 20),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

Widget _handle(BuildContext context) => Center(
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );

Widget _sectionLabel(BuildContext context, String label, IconData icon) => Row(children: [
      Icon(icon, size: 16, color: AppTheme.gold),
      const SizedBox(width: 6),
      Text(label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: AppTheme.gold)),
    ]);
