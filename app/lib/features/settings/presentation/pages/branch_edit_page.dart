import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/models/branch.dart';
import '../../../../core/services/branch_service.dart';
import '../../../../core/services/connectivity_monitor.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/custom_button.dart';
import '../../../../shared/widgets/text_input.dart';

class BranchEditPage extends ConsumerStatefulWidget {
  final int branchId;
  const BranchEditPage({super.key, required this.branchId});

  @override
  ConsumerState<BranchEditPage> createState() => _BranchEditPageState();
}

class _BranchEditPageState extends ConsumerState<BranchEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();

  Branch? _branch;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isFetchingLocation = false;
  bool _isStale = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBranch();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadBranch() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final branch = await BranchService.getBranch(widget.branchId);
      if (mounted) {
        setState(() {
          _branch = branch;
          _nameController.text = branch.name;
          _addressController.text = branch.address ?? '';
          _phoneController.text = branch.phone ?? '';
          _isStale = BranchService.lastFetchWasStale;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _autofillAddress() async {
    setState(() => _isFetchingLocation = true);
    try {
      final result = await LocationService.getCurrentLocation();
      if (mounted && result.address != null && result.address!.isNotEmpty) {
        _addressController.text = result.address!;
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not determine address from location'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: AppTheme.destructive,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } finally {
      if (mounted) setState(() => _isFetchingLocation = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final savedOnline = await BranchService.updateBranch(
        widget.branchId,
        _nameController.text.trim(),
        _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
        _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
      );
      if (mounted) {
        final msg = savedOnline
            ? 'Branch updated successfully'
            : 'Perubahan disimpan — akan dikirim saat online';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: savedOnline ? AppTheme.success : Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: AppTheme.destructive,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isOffline = ref.watch(connectivityProvider).valueOrNull == ConnectivityStatus.offline;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Edit Branch'),
            if (_isStale) ...[
              const SizedBox(width: 8),
              const Tooltip(
                message: 'Data mungkin tidak terbaru',
                child: Icon(Icons.cloud_off, size: 14, color: Colors.orange),
              ),
            ],
          ],
        ),
        backgroundColor: cs.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.gold))
          : _error != null
              ? _buildError()
              : _buildForm(cs, isOffline),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 56, color: AppTheme.destructive),
            const SizedBox(height: 16),
            Text('Failed to load branch', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(_error!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            CustomButton(text: 'Retry', icon: Icons.refresh, onPressed: _loadBranch),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(ColorScheme cs, bool isOffline) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Offline notice
            if (isOffline)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.4)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.wifi_off, size: 14, color: Colors.orange),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Kamu offline — perubahan akan disimpan dan dikirim saat online',
                        style: TextStyle(fontSize: 12, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),

            // Header card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.gold.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.gold.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.gold.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.storefront_outlined, color: AppTheme.gold, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Branch ID: ${widget.branchId}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: cs.onSurface.withOpacity(0.5))),
                        Text(_branch?.name ?? '',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            TextInput(
              controller: _nameController,
              label: 'Branch Name',
              hintText: 'e.g. Downtown Branch',
              prefixIcon: Icons.storefront_outlined,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Name is required';
                if (v.trim().length < 2) return 'Name must be at least 2 characters';
                return null;
              },
            ),

            const SizedBox(height: 20),

            TextInput(
              controller: _addressController,
              label: 'Address',
              hintText: 'e.g. Jl. Sudirman No. 1, Jakarta',
              prefixIcon: Icons.location_on_outlined,
              maxLines: 3,
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isFetchingLocation ? null : _autofillAddress,
                icon: _isFetchingLocation
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.gold))
                    : const Icon(Icons.my_location, size: 18),
                label: Text(_isFetchingLocation ? 'Getting location...' : 'Use current location'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.gold,
                  side: BorderSide(color: AppTheme.gold.withOpacity(0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),

            const SizedBox(height: 20),

            TextInput(
              controller: _phoneController,
              label: 'Phone',
              hintText: 'e.g. +62 21 1234 5678',
              prefixIcon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              validator: (v) {
                if (v != null && v.trim().isNotEmpty) {
                  if (!RegExp(r'^[+\d\s\-()]{6,20}$').hasMatch(v.trim())) {
                    return 'Enter a valid phone number';
                  }
                }
                return null;
              },
            ),

            const SizedBox(height: 40),

            CustomButton(
              text: isOffline ? 'Simpan (akan disinkronkan)' : 'Save Changes',
              icon: isOffline ? Icons.cloud_upload_outlined : Icons.save_outlined,
              fullWidth: true,
              isLoading: _isSaving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}
