import 'package:material_ui/material_ui.dart';

import '../../../../core/helper/imei_validator.dart';
import '../../../../shared/widgets/barcode_scanner_page.dart';
import '../../../../shared/widgets/scan_key_listener.dart';

/// Pengaturan → Scanner Barcode: how barcode scanning works at the cashier, and a place to try a
/// scanner (USB / Bluetooth scanners act as a keyboard, so there is nothing to pair in the app).
class ScannerDevicesPage extends StatefulWidget {
  const ScannerDevicesPage({super.key});

  @override
  State<ScannerDevicesPage> createState() => _ScannerDevicesPageState();
}

class _ScannerDevicesPageState extends State<ScannerDevicesPage> {
  final _field = TextEditingController();
  final _focus = FocusNode();
  String? _last;
  String? _source;

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _show(String code, String source) {
    final value = code.trim();
    if (value.isEmpty) return;
    setState(() {
      _last = value;
      _source = source;
    });
    _field.clear();
  }

  String _describe(String code) {
    final digits = ImeiValidator.normalize(code);
    if (RegExp(r'^\d{15}$').hasMatch(digits)) {
      return ImeiValidator.isValid(digits) ? 'IMEI yang valid' : '15 digit, tapi check digit IMEI tidak cocok';
    }
    if (RegExp(r'^\d{13}$').hasMatch(digits)) return 'Barcode EAN-13 (barcode produk)';
    if (RegExp(r'^\d{8}$').hasMatch(digits)) return 'Barcode EAN-8';
    return '${code.length} karakter';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Scaffold(
      appBar: AppBar(title: const Text('Scanner Barcode')),
      body: ScanKeyListener(
        onScan: (code) => _show(code, 'scanner'),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _Tip(
              icon: Icons.qr_code_scanner,
              title: 'Kamera HP',
              text: 'Tekan ikon scan di kolom pencarian Kasir. Bisa membaca barcode produk, QR, dan IMEI di dus HP.',
            ),
            const _Tip(
              icon: Icons.usb,
              title: 'Scanner USB atau Bluetooth',
              text: 'Scanner bekerja seperti keyboard. USB: colok lewat kabel OTG. Bluetooth: pasangkan di pengaturan '
                  'Bluetooth HP (mode HID / keyboard). Pastikan scanner mengirim Enter setelah kode (pengaturan bawaan '
                  'hampir semua scanner). Lalu scan saja di halaman Kasir.',
            ),
            const _Tip(
              icon: Icons.add_shopping_cart,
              title: 'Yang terjadi saat scan di Kasir',
              text: 'Barcode / SKU produk menambah 1 barang ke keranjang. IMEI atau nomor seri menambah unit HP itu '
                  '(butuh koneksi). Jasa dan pulsa tetap minta harga diisi.',
            ),
            const SizedBox(height: 16),
            Text('Coba scanner', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('Scan sesuatu: hasilnya muncul di bawah.', style: muted),
            const SizedBox(height: 12),
            TextField(
              controller: _field,
              focusNode: _focus,
              decoration: InputDecoration(
                hintText: 'Scan atau ketik kode lalu Enter',
                prefixIcon: const Icon(Icons.keyboard_outlined),
                suffixIcon: IconButton(
                  tooltip: 'Scan dengan kamera',
                  icon: const Icon(Icons.photo_camera_outlined),
                  onPressed: () async {
                    final code = await scanWithCamera(context, title: 'Coba scan');
                    if (code != null) _show(code, 'kamera');
                  },
                ),
              ),
              onSubmitted: (code) {
                _show(code, 'kolom ini');
                _focus.requestFocus();
              },
            ),
            const SizedBox(height: 16),
            if (_last != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.check_circle, color: Colors.green),
                  title: SelectableText(_last!, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                  subtitle: Text('${_describe(_last!)} · dari $_source'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _Tip({required this.icon, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text(text)),
      ),
    );
  }
}
