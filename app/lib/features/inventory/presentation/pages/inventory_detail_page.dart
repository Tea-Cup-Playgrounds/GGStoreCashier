import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
// import '../../../../shared/widgets/bottom_navigation.dart'; // Halaman Detail biasanya tidak memiliki BottomNav

class InventoryDetailPage extends StatelessWidget {
  final String productId;

  const InventoryDetailPage({
    super.key,
    required this.productId,
  });

  @override
  Widget build(BuildContext context) {
    // Data Dummy (Contoh)
    const productName = 'Signature Watch';
    const sku = 'WAT-001';
    const category = 'Accessories';
    const stock = '15';
    const price = '299,99';
    const description = 'Premium stainless steel watch with gold accents';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        // Tombol kembali otomatis
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.foreground),
          onPressed: () => Navigator.of(context).pop(),
        ),
        // Judul dan Subtitle Kustom
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Edit Item',
              style: Theme.of(context).textTheme.headlineMedium!.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.foreground,
                  ),
            ),
            Text(
              productId, // Menggunakan productId (WAT-001) sebagai subtitle
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                    color: AppTheme.mutedForeground,
                  ),
            ),
          ],
        ),
        backgroundColor: AppTheme.background,
        elevation: 0,
        actions: [
          // Tombol Hapus (Warna Destructive)
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppTheme.destructive),
            onPressed: () {
              // TODO: Aksi Hapus Item
            },
          ),
          const SizedBox(width: 8.0),
        ],
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Gambar Produk
            Center(
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.all_inbox_outlined, // Icon placeholder
                  size: 64,
                  color: AppTheme.mutedForeground,
                ),
              ),
            ),
            const SizedBox(height: 32.0),

            // 2. Form Input
            // Product Name
            _buildLabel(context, 'Product Name'),
            _buildTextField(context, initialValue: productName),
            const SizedBox(height: 16.0),

            // SKU & Category (Satu Baris)
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel(context, 'SKU'),
                      _buildTextField(context,
                          initialValue: sku,
                          readOnly: true), // SKU biasanya read-only
                    ],
                  ),
                ),
                const SizedBox(width: 16.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel(context, 'Category'),
                      _buildTextField(context, initialValue: category),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16.0),

            // Stock Quantity & Price (Satu Baris)
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel(context, 'Stock Quantity'),
                      _buildTextField(context,
                          initialValue: stock,
                          keyboardType: TextInputType.number),
                    ],
                  ),
                ),
                const SizedBox(width: 16.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel(context, 'Price (\$)'),
                      _buildTextField(context,
                          initialValue: price,
                          keyboardType: TextInputType.number),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16.0),

            // Description
            _buildLabel(context, 'Description'),
            _buildTextField(
              context,
              initialValue: description,
              maxLines: 4,
            ),
            const SizedBox(height: 32.0),

            // Tombol Save (Contoh Aksi)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  // TODO: Aksi Simpan Perubahan
                },
                child: const Text('Save Changes'),
              ),
            ),
          ],
        ),
      ),
      // Halaman detail tidak menggunakan BottomNavigation
      // bottomNavigationBar: const BottomNavigation(),
    );
  }

  // Helper Widget untuk Label Form
  Widget _buildLabel(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleMedium!.copyWith(
              color: AppTheme.foreground,
              fontWeight: FontWeight.w500,
            ),
      ),
    );
  }

  // Helper Widget untuk TextFormField
  Widget _buildTextField(
    BuildContext context, {
    required String initialValue,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    bool readOnly = false,
  }) {
    // Menggunakan TextFormField untuk mendapatkan styling dari ThemeData
    return TextFormField(
      initialValue: initialValue,
      maxLines: maxLines,
      keyboardType: keyboardType,
      readOnly: readOnly,
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: const InputDecoration(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }
}
