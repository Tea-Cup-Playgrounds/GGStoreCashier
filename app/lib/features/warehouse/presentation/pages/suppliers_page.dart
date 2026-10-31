import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gg_store_cashier/core/helper/currency_formatter.dart';
import 'package:gg_store_cashier/core/models/access.dart';
import 'package:gg_store_cashier/core/models/warehouse.dart';
import 'package:gg_store_cashier/core/provider/access_provider.dart';
import 'package:gg_store_cashier/core/services/warehouse_service.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';
import 'package:gg_store_cashier/shared/utils/snackbar_service.dart';
import 'package:gg_store_cashier/shared/widgets/custom_button.dart';
import 'package:gg_store_cashier/shared/widgets/text_input.dart';

class SuppliersPage extends ConsumerStatefulWidget {
  const SuppliersPage({super.key});

  @override
  ConsumerState<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends ConsumerState<SuppliersPage> {
  final _search = TextEditingController();
  List<Supplier> _suppliers = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final suppliers = await WarehouseService.getSuppliers(includeInactive: true);
      if (mounted) setState(() => _suppliers = suppliers);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit([Supplier? supplier]) async {
    final saved = await SupplierFormSheet.show(context, supplier: supplier);
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final access = ref.watch(accessProvider).valueOrNull ?? UserAccess.empty;
    final canManage = access.can('suppliers.manage');
    final q = _search.text.trim().toLowerCase();
    final visible = q.isEmpty
        ? _suppliers
        : _suppliers.where((s) => s.name.toLowerCase().contains(q) || s.code.toLowerCase().contains(q) || (s.phone ?? '').contains(q)).toList();

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        title: const Text('Supplier', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: cs.surface,
        elevation: 0,
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => _edit(),
              backgroundColor: AppTheme.gold,
              foregroundColor: Colors.black,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Supplier Baru'),
            )
          : null,
      body: Column(
        children: [
          Container(
            color: cs.surface,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: 'Cari nama, kode, atau telepon', prefixIcon: Icon(Icons.search), isDense: true),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.gold))
                : _error != null
                    ? Center(child: Text(_error!))
                    : visible.isEmpty
                        ? Center(child: Text('Belum ada supplier', style: TextStyle(color: cs.onSurfaceVariant)))
                        : RefreshIndicator(
                            color: AppTheme.gold,
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                              itemCount: visible.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, i) {
                                final s = visible[i];
                                return Material(
                                  color: cs.surface,
                                  borderRadius: BorderRadius.circular(12),
                                  child: ListTile(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(color: cs.outlineVariant, width: 0.8),
                                    ),
                                    onTap: canManage ? () => _edit(s) : null,
                                    title: Text(s.name, style: TextStyle(fontWeight: FontWeight.w600, color: s.isActive ? null : cs.onSurfaceVariant)),
                                    subtitle: Text([s.code, if (s.phone != null) s.phone!, if (!s.isActive) 'Nonaktif'].join(' · ')),
                                    trailing: s.outstanding > 0
                                        ? Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Text('Hutang', style: Theme.of(context).textTheme.labelSmall),
                                              Text(CurrencyFormatter.formatToRupiah(s.outstanding),
                                                  style: const TextStyle(color: AppTheme.destructive, fontWeight: FontWeight.w700)),
                                            ],
                                          )
                                        : null,
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

/// Create (no [supplier]) or edit a supplier. Returns true when saved.
class SupplierFormSheet extends StatefulWidget {
  final Supplier? supplier;
  const SupplierFormSheet({super.key, this.supplier});

  static Future<bool?> show(BuildContext context, {Supplier? supplier}) => showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => SupplierFormSheet(supplier: supplier),
      );

  @override
  State<SupplierFormSheet> createState() => _SupplierFormSheetState();
}

class _SupplierFormSheetState extends State<SupplierFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.supplier?.name ?? '');
  late final _code = TextEditingController(text: widget.supplier?.code ?? '');
  late final _phone = TextEditingController(text: widget.supplier?.phone ?? '');
  late final _email = TextEditingController(text: widget.supplier?.email ?? '');
  late final _address = TextEditingController(text: widget.supplier?.address ?? '');
  late bool _active = widget.supplier?.isActive ?? true;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _code, _phone, _email, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final fields = {
      'name': _name.text.trim(),
      if (_code.text.trim().isNotEmpty) 'code': _code.text.trim(),
      'phone': _phone.text.trim(),
      'email': _email.text.trim(),
      'address': _address.text.trim(),
      'is_active': _active,
    };
    try {
      if (widget.supplier == null) {
        await WarehouseService.createSupplier(fields);
      } else {
        await WarehouseService.updateSupplier(widget.supplier!.id, fields);
      }
      SnackBarService.success('Supplier disimpan');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      SnackBarService.error(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.supplier == null ? 'Supplier Baru' : 'Edit Supplier',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              TextInput(
                label: 'Nama *',
                controller: _name,
                prefixIcon: Icons.business_outlined,
                validator: (v) => v == null || v.trim().isEmpty ? 'Nama wajib diisi' : null,
              ),
              const SizedBox(height: 12),
              TextInput(label: 'Kode', hintText: 'Otomatis bila kosong', controller: _code, prefixIcon: Icons.tag),
              const SizedBox(height: 12),
              TextInput(label: 'Telepon', controller: _phone, keyboardType: TextInputType.phone, prefixIcon: Icons.phone_outlined),
              const SizedBox(height: 12),
              TextInput(label: 'Email', controller: _email, keyboardType: TextInputType.emailAddress, prefixIcon: Icons.email_outlined),
              const SizedBox(height: 12),
              TextInput(label: 'Alamat', controller: _address, maxLines: 2, prefixIcon: Icons.location_on_outlined),
              if (widget.supplier != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Aktif'),
                  value: _active,
                  activeThumbColor: AppTheme.gold,
                  onChanged: (v) => setState(() => _active = v),
                ),
              const SizedBox(height: 16),
              CustomButton(text: 'Simpan', isLoading: _saving, onPressed: _saving ? null : _save, fullWidth: true),
            ],
          ),
        ),
      ),
    );
  }
}
