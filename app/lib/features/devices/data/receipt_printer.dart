import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/esc_pos.dart';
import '../domain/receipt.dart';
import '../domain/receipt_config.dart';
import '../domain/receipt_layout.dart';

enum PrinterConnection { none, bluetooth, network }

/// The receipt printer chosen on this device (Pengaturan → Printer), stored in SharedPreferences.
class PrinterSettings {
  static const prefsKey = 'printer_settings';

  final PrinterConnection connection;

  /// Bluetooth: the printer's MAC address. Network: its IP address or host name.
  final String address;
  final String name;
  final int port;

  /// Print as soon as a sale is paid.
  final bool autoPrint;

  /// Open the cash drawer plugged into the printer when printing a sale.
  final bool openDrawer;

  const PrinterSettings({
    this.connection = PrinterConnection.none,
    this.address = '',
    this.name = '',
    this.port = 9100,
    this.autoPrint = false,
    this.openDrawer = false,
  });

  bool get isConfigured => connection != PrinterConnection.none && address.isNotEmpty;

  String get label => switch (connection) {
        PrinterConnection.none => 'Belum diatur',
        PrinterConnection.bluetooth => name.isNotEmpty ? name : address,
        PrinterConnection.network => '$address:$port',
      };

  PrinterSettings copyWith({PrinterConnection? connection, String? address, String? name, int? port, bool? autoPrint, bool? openDrawer}) =>
      PrinterSettings(
        connection: connection ?? this.connection,
        address: address ?? this.address,
        name: name ?? this.name,
        port: port ?? this.port,
        autoPrint: autoPrint ?? this.autoPrint,
        openDrawer: openDrawer ?? this.openDrawer,
      );

  Map<String, dynamic> toJson() => {
        'connection': connection.name,
        'address': address,
        'name': name,
        'port': port,
        'autoPrint': autoPrint,
        'openDrawer': openDrawer,
      };

  factory PrinterSettings.fromJson(Map<String, dynamic> j) => PrinterSettings(
        connection: PrinterConnection.values.firstWhere((c) => c.name == j['connection'], orElse: () => PrinterConnection.none),
        address: j['address']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        port: (j['port'] as num?)?.toInt() ?? 9100,
        autoPrint: j['autoPrint'] == true,
        openDrawer: j['openDrawer'] == true,
      );

  static Future<PrinterSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    if (raw == null) return const PrinterSettings();
    try {
      return PrinterSettings.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return const PrinterSettings();
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, jsonEncode(toJson()));
    printerSettingsChanged.value++;
  }
}

/// Bumped whenever the printer settings are saved, so screens showing the printer can refresh.
final printerSettingsChanged = ValueNotifier<int>(0);

/// The saved printer settings, reloaded after every save.
final printerSettingsProvider = FutureProvider<PrinterSettings>((ref) {
  void reload() => ref.invalidateSelf();
  printerSettingsChanged.addListener(reload);
  ref.onDispose(() => printerSettingsChanged.removeListener(reload));
  return PrinterSettings.load();
});

/// A printing problem, with a message for the cashier (Indonesian).
class PrinterException implements Exception {
  final String message;
  const PrinterException(this.message);

  @override
  String toString() => message;
}

/// Somewhere ESC/POS bytes can be sent.
abstract class PrinterTransport {
  Future<void> send(List<int> bytes);
}

/// A printer on the network (LAN / Wi-Fi), raw TCP on port 9100 like almost every ESC/POS printer.
class NetworkPrinterTransport implements PrinterTransport {
  final String host;
  final int port;
  final Duration timeout;

  const NetworkPrinterTransport(this.host, {this.port = 9100, this.timeout = const Duration(seconds: 5)});

  @override
  Future<void> send(List<int> bytes) async {
    Socket socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
    } on SocketException {
      throw PrinterException('Printer $host:$port tidak bisa dihubungi. Pastikan printer menyala dan satu jaringan dengan HP ini.');
    }
    try {
      socket.add(bytes);
      await socket.flush().timeout(timeout);
    } catch (_) {
      throw const PrinterException('Gagal mengirim struk ke printer jaringan');
    } finally {
      await socket.close().timeout(timeout, onTimeout: () => socket.destroy());
    }
  }
}

/// A Bluetooth printer already paired in the phone's Bluetooth settings (classic Bluetooth / SPP,
/// which is what most 58mm and 80mm thermal printers use).
class BluetoothPrinterTransport implements PrinterTransport {
  final String mac;

  const BluetoothPrinterTransport(this.mac);

  /// Android 12+ asks for "Nearby devices" before an app may connect.
  static Future<void> ensurePermission() async {
    if (!Platform.isAndroid) return;
    final status = await Permission.bluetoothConnect.request();
    if (!status.isGranted) {
      throw const PrinterException('Izin Bluetooth ("Perangkat sekitar") belum diberikan untuk aplikasi ini');
    }
  }

  static Future<List<BluetoothInfo>> pairedPrinters() async {
    await ensurePermission();
    if (!await PrintBluetoothThermal.bluetoothEnabled) throw const PrinterException('Bluetooth HP sedang mati');
    return PrintBluetoothThermal.pairedBluetooths;
  }

  @override
  Future<void> send(List<int> bytes) async {
    await ensurePermission();
    if (!await PrintBluetoothThermal.bluetoothEnabled) throw const PrinterException('Bluetooth HP sedang mati');
    if (!await PrintBluetoothThermal.connectionStatus) {
      final connected = await PrintBluetoothThermal.connect(macPrinterAddress: mac);
      if (!connected) throw const PrinterException('Tidak bisa terhubung ke printer. Pastikan printer menyala dan tidak dipakai HP lain.');
    }
    if (!await PrintBluetoothThermal.writeBytes(bytes)) {
      // The connection may have dropped (printer turned off and on): reconnect once.
      await PrintBluetoothThermal.disconnect;
      final connected = await PrintBluetoothThermal.connect(macPrinterAddress: mac);
      if (!connected || !await PrintBluetoothThermal.writeBytes(bytes)) {
        throw const PrinterException('Gagal mengirim struk ke printer Bluetooth');
      }
    }
  }
}

/// Prints receipts on the printer set up on this device, with the template from the receipt editor.
class ReceiptPrinter {
  static PrinterTransport transportFor(PrinterSettings s) => switch (s.connection) {
        PrinterConnection.bluetooth => BluetoothPrinterTransport(s.address),
        PrinterConnection.network => NetworkPrinterTransport(s.address, port: s.port),
        PrinterConnection.none => throw const PrinterException('Printer belum diatur (Pengaturan → Printer Struk)'),
      };

  /// Printer bytes for [receipt] with [config].
  static List<int> bytesFor(ReceiptData receipt, ReceiptConfig config, {bool openDrawer = false}) =>
      EscPos.encode(ReceiptLayout.build(receipt, config), charsPerLine: config.charsPerLine, openDrawer: openDrawer);

  /// Prints [receipt]. [settings] defaults to the saved ones (the printer page passes unsaved ones
  /// for its test print). Throws [PrinterException].
  static Future<void> printReceipt(ReceiptData receipt, {PrinterSettings? settings, bool openDrawer = false}) async {
    final s = settings ?? await PrinterSettings.load();
    if (!s.isConfigured) throw const PrinterException('Printer belum diatur (Pengaturan → Printer Struk)');
    final config = await ReceiptConfig.load();
    await transportFor(s).send(bytesFor(receipt, config, openDrawer: openDrawer && s.openDrawer));
  }
}
