import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/provider/auth_provider.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/snackbar_service.dart';

class CategoryManagementPage extends ConsumerStatefulWidget {
  const CategoryManagementPage({super.key});

  @override
  ConsumerState<CategoryManagementPage> createState() => _CategoryManagementPageState();
}

class _CategoryManagementPageState extends ConsumerState<CategoryManagementPage> {
  List<Map<String, dynamic>> _categories = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filtered {
    if (_searchQuery.isEmpty) return _categories;
    final q = _searchQuery.toLowerCase();
    return _categories.where((c) {
      final name = (c['name'] as String? ?? '').toLowerCase();
      final desc = (c['description'] as String? ?? '').toLowerCase();
      return name.contains(q) || desc.contains(q);
    }).toList();
  }

  Future<void> _loadCategories() async {
    setState(() => _isLoading = true);
    try {
      final token = await AuthService.getToken();
      final dio = Dio(BaseOptions(
        baseUrl: ApiConfig.apiUrl,
        headers: {'Authorization': 'Bearer $token', ...ApiConfig.defaultHeaders},
      ));
      final response = await dio.get('/api/categories');
      if (mounted) {
        setState(() {
          _categories = List<Map<String, dynamic>>.from(response.data['categories']);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      if (mounted) SnackBarService.error('Gagal memuat kategori');
    }
  }

  Future<void> _openForm({Map<String, dynamic>? category}) async {
    final result = await context.push<bool>(
      AppRouter.categoryForm,
      extra: category,
    );
    if (result == true) _loadCategories();
  }

  Future<void> _deleteCategory(int id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Kategori'),
        content: Text('Hapus kategori "$name"? Tindakan ini tidak dapat dibatalkan.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.destructive),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final token = await AuthService.getToken();
      final dio = Dio(BaseOptions(
        baseUrl: ApiConfig.apiUrl,
        headers: {'Authorization': 'Bearer $token', ...ApiConfig.defaultHeaders},
      ));
      await dio.delete('/api/categories/$id');
      if (mounted) {
        SnackBarService.success('Kategori berhasil dihapus');
        _loadCategories();
      }
    } catch (e) {
      if (mounted) {
        String msg = 'Gagal menghapus kategori';
        if (e is DioException && e.response?.data != null) {
          msg = e.response!.data['error'] ?? msg;
        }
        SnackBarService.error(msg);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final user = ref.watch(authProvider).user;
    final role = user?.role ?? 'karyawan';
    final canAddEdit = role == 'admin' || role == 'superadmin';
    final canDelete = role == 'superadmin';

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.gold));
    }

    if (_categories.isEmpty) {
      return _EmptyState(
        canAdd: canAddEdit,
        onAdd: () => _openForm(),
      );
    }

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      body: Column(
        children: [
          // ── Search bar ───────────────────────────────────────────────
          Container(
            color: cs.surface,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Cari kategori...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() {
                          _searchController.clear();
                          _searchQuery = '';
                        }),
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
            ),
          ),

          // ── List ─────────────────────────────────────────────────────
          Expanded(
            child: _filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off_rounded, size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                        const SizedBox(height: 12),
                        Text(
                          'Kategori tidak ditemukan',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                    itemCount: _filtered.length,
                    itemBuilder: (context, index) {
                      final cat = _filtered[index];
                      return _CategoryTile(
                        category: cat,
                        canEdit: canAddEdit,
                        canDelete: canDelete,
                        onEdit: () => _openForm(category: cat),
                        onDelete: () => _deleteCategory(cat['id'], cat['name']),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: canAddEdit
          ? FloatingActionButton(
              onPressed: () => _openForm(),
              backgroundColor: AppTheme.gold,
              foregroundColor: isDark ? Colors.black : Colors.white,
              child: const Icon(Icons.add_rounded),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool canAdd;
  final VoidCallback onAdd;

  const _EmptyState({required this.canAdd, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.gold.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.gold.withValues(alpha: 0.2)),
              ),
              child: const Icon(Icons.category_outlined, size: 36, color: AppTheme.gold),
            ),
            const SizedBox(height: 20),
            Text(
              'Belum ada kategori',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Tambahkan kategori untuk mengelompokkan produk Anda.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
            if (canAdd) ...[
              const SizedBox(height: 28),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Tambah Kategori Pertama', style: TextStyle(fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.gold,
                    foregroundColor: isDark ? Colors.black : Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Category tile ─────────────────────────────────────────────────────────────

class _CategoryTile extends StatelessWidget {
  final Map<String, dynamic> category;
  final bool canEdit;
  final bool canDelete;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CategoryTile({
    required this.category,
    required this.canEdit,
    required this.canDelete,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant, width: 0.8),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // ── Image ──────────────────────────────────────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 56,
                height: 56,
                child: category['category_image'] != null
                    ? Image.network(
                        '${ApiConfig.apiUrl}/uploads/categories/${category['category_image']}',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholder(cs),
                      )
                    : _placeholder(cs),
              ),
            ),
            const SizedBox(width: 14),

            // ── Text ───────────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category['name'],
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  if (category['description'] != null && (category['description'] as String).isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      category['description'],
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),

            // ── Actions ────────────────────────────────────────────────
            if (canEdit || canDelete)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (canEdit)
                    _ActionBtn(
                      icon: Icons.edit_outlined,
                      color: cs.onSurfaceVariant,
                      onTap: onEdit,
                      tooltip: 'Edit',
                    ),
                  if (canDelete)
                    _ActionBtn(
                      icon: Icons.delete_outline_rounded,
                      color: AppTheme.destructive,
                      onTap: onDelete,
                      tooltip: 'Hapus',
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(ColorScheme cs) => Container(
        color: cs.surfaceContainerHighest,
        child: Icon(Icons.category_outlined, color: cs.onSurfaceVariant, size: 26),
      );
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;

  const _ActionBtn({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 36,
          margin: const EdgeInsets.only(left: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.15)),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}
