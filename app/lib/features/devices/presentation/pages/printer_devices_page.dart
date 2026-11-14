import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/snackbar_service.dart';
import '../../data/receipt_printer.dart';
import '../../domain/receipt_config.dart';
import '../../domain/receipt_layout.dart';
import '../widgets/receipt_preview.dart';

/// Pengaturan → Printer Struk: which printer this device prints receipts on (a paired Bluetooth
/// printer or one on the network), automatic printing, the cash drawer, and a test print.
class PrinterDevicesPage extends StatefulWidget {
  const PrinterDevicesPage({super.key});

  @override
  State<PrinterDevicesPage> createState() => _PrinterDevicesPageState();
}

class _PrinterDevicesPageState extends State<PrinterDevicesPage> {
  PrinterSettings _settings = const PrinterSettings();
  ReceiptConfig _config = const ReceiptConfig();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '9100');

  List<BluetoothInfo>? _paired;
  bool _loadingPaired = false;
  String? _pairedError;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await PrinterSettings.load();
    final config = await ReceiptConfig.load();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _config = config;
      if (settings.connection == PrinterConnection.network) {
        _host.text = settings.address;
        _port.text = '${settings.port}';
      }
    });
    if (settings.connection == PrinterConnection.bluetooth) _loadPaired();
  }

  Future<void> _loadPaired() async {
    setState(() {
      _loadingPaired = true;
      _pairedError = null;
    });
    try {
      final paired = await BluetoothPrinterTransport.pairedPrinters();
      if (mounted) setState(() => _paired = paired);
    } on PrinterException catch (e) {
      if (mounted) setState(() => _pairedError = e.message);
    } finally {
      if (mounted) setState(() => _loadingPaired = false);
    }
  }

  /// The settings as filled in on this page (not saved yet).
  PrinterSettings get _current {
    if (_settings.connection == PrinterConnection.network) {
      return _settings.copyWith(address: _host.text.trim(), port: int.tryParse(_port.text.trim()) ?? 9100, name: '');
    }
    return _settings;
  }

  Future<void> _save() async {
    final s = _current;
    if (s.connection != PrinterConnection.none && !s.isConfigured) {
      SnackBarService.error(s.connection == PrinterConnection.bluetooth ? 'Pilih printer Bluetooth dulu' : 'Isi alamat IP printer');
      return;
    }
    await s.save();
    SnackBarService.success('Pengaturan printer disimpan');
  }

  Future<void> _testPrint() async {
    final s = _current;
    if (!s.isConfigured) {
      SnackBarService.error('Pilih printer dulu');
      return;
    }
    setState(() => _testing = true);
    try {
      await ReceiptPrinter.printReceipt(ReceiptLayout.sample(), settings: s);
      SnackBarService.success('Struk tes terkirim ke printer');
    } on PrinterException catch (e) {
      SnackBarService.error(e.message);
    } catch (e) {
      SnackBarService.error('Gagal mencetak: $e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _setConnection(PrinterConnection c) {
    setState(() => _settings = _settings.copyWith(connection: c, address: c == _settings.connection ? null : '', name: ''));
    if (c == PrinterConnection.bluetooth && _paired == null) _loadPaired();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Scaffold(
      appBar: AppBar(title: const Text('Printer Struk')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Sambungan', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          SegmentedButton<PrinterConnection>(
            segments: const [
              ButtonSegment(value: PrinterConnection.bluetooth, icon: Icon(Icons.bluetooth), label: Text('Bluetooth')),
              ButtonSegment(value: PrinterConnection.network, icon: Icon(Icons.lan_outlined), label: Text('Jaringan')),
              ButtonSegment(value: PrinterConnection.none, label: Text('Tidak ada')),
            ],
            selected: {_settings.connection},
            onSelectionChanged: (s) => _setConnection(s.first),
          ),
          const SizedBox(height: 12),
          if (_settings.connection == PrinterConnection.bluetooth) ..._bluetoothSection(muted),
          if (_settings.connection == PrinterConnection.network) ..._networkSection(muted),
          const SizedBox(height: 16),
          Card(
            child: Column(children: [
              SwitchListTile(
                title: const Text('Cetak otomatis setelah pembayaran'),
                value: _settings.autoPrint,
                onChanged: (v) => setState(() => _settings = _settings.copyWith(autoPrint: v)),
              ),
              SwitchListTile(
                title: const Text('Buka laci kas saat mencetak penjualan'),
                subtitle: const Text('Untuk laci kas yang dicolok ke printer'),
                value: _settings.openDrawer,
                onChanged: (v) => setState(() => _settings = _settings.copyWith(openDrawer: v)),
              ),
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('Tampilan struk'),
                subtitle: Text('Kertas ${_config.wide ? '80' : '58'} mm · nama toko, alamat, catatan kaki'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await context.push(AppRouter.receiptEditor);
                  final config = await ReceiptConfig.load();
                  if (mounted) setState(() => _config = config);
                },
              ),
            ]),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _testing ? null : _testPrint,
                icon: _testing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.print_outlined),
                label: const Text('Cetak tes'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(onPressed: _save, icon: const Icon(Icons.check), label: const Text('Simpan')),
            ),
          ]),
          const SizedBox(height: 24),
          Text('Contoh struk', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ReceiptPreview(rows: ReceiptLayout.build(ReceiptLayout.sample(), _config), charsPerLine: _config.charsPerLine),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  List<Widget> _bluetoothSection(TextStyle? muted) => [
        Text(
          'Pasangkan printer dulu di pengaturan Bluetooth HP (PIN biasanya 0000 atau 1234), lalu pilih di sini. '
          'Printer thermal 58/80 mm biasa (Bluetooth klasik) didukung.',
          style: muted,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _loadingPaired ? null : _loadPaired,
            icon: _loadingPaired
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            label: const Text('Muat printer yang sudah dipasangkan'),
          ),
        ),
        if (_pairedError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_pairedError!, style: const TextStyle(color: AppTheme.destructive)),
          ),
        if (_paired != null && _paired!.isEmpty && _pairedError == null)
          Text('Belum ada perangkat Bluetooth yang dipasangkan.', style: muted),
        if (_paired != null)
          RadioGroup<String>(
            groupValue: _settings.address,
            onChanged: (mac) {
              final device = _paired!.firstWhere((d) => d.macAdress == mac);
              setState(() => _settings = _settings.copyWith(address: device.macAdress, name: device.name));
            },
            child: Column(children: [
              for (final d in _paired!)
                RadioListTile<String>(
                  value: d.macAdress,
                  title: Text(d.name.isEmpty ? 'Tanpa nama' : d.name),
                  subtitle: Text(d.macAdress),
                  secondary: const Icon(Icons.print_outlined),
                ),
            ]),
          ),
        if (_settings.address.isNotEmpty && !(_paired?.any((d) => d.macAdress == _settings.address) ?? false))
          ListTile(
            leading: const Icon(Icons.print_outlined),
            title: Text(_settings.label),
            subtitle: Text('${_settings.address} · tersimpan'),
          ),
      ];

  List<Widget> _networkSection(TextStyle? muted) => [
        Text('Printer LAN / Wi-Fi di jaringan yang sama dengan HP ini (port ESC/POS biasanya 9100).', style: muted),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: _host,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Alamat IP', hintText: '192.168.1.50'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _port,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Port'),
            ),
          ),
        ]),
      ];
}
