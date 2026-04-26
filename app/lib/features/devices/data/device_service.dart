import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DeviceConnectionType { bluetooth, wifi, usb }

enum DeviceCategory { printer, scanner }

class PairedDevice {
  final String id;
  final String name;
  final DeviceConnectionType connectionType;
  final DeviceCategory category;
  bool isConnected;

  PairedDevice({
    required this.id,
    required this.name,
    required this.connectionType,
    required this.category,
    this.isConnected = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'connectionType': connectionType.name,
        'category': category.name,
        'isConnected': isConnected,
      };

  factory PairedDevice.fromJson(Map<String, dynamic> j) => PairedDevice(
        id: j['id'],
        name: j['name'],
        connectionType: DeviceConnectionType.values.firstWhere((e) => e.name == j['connectionType']),
        category: DeviceCategory.values.firstWhere((e) => e.name == j['category']),
        isConnected: j['isConnected'] ?? false,
      );
}

class DiscoveredDevice {
  final String id;
  final String name;
  final DeviceConnectionType connectionType;
  final int? rssi;

  const DiscoveredDevice({
    required this.id,
    required this.name,
    required this.connectionType,
    this.rssi,
  });
}

class DeviceService {
  static const _prefsKey = 'paired_devices';

  // ── Persistence ────────────────────────────────────────────────────────────

  static Future<List<PairedDevice>> loadPaired() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? [];
    return raw.map((s) => PairedDevice.fromJson(jsonDecode(s))).toList();
  }

  static Future<void> savePaired(List<PairedDevice> devices) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefsKey,
      devices.map((d) => jsonEncode(d.toJson())).toList(),
    );
  }

  static Future<void> addPaired(PairedDevice device) async {
    final list = await loadPaired();
    list.removeWhere((d) => d.id == device.id);
    list.add(device);
    await savePaired(list);
  }

  static Future<void> removePaired(String deviceId) async {
    final list = await loadPaired();
    list.removeWhere((d) => d.id == deviceId);
    await savePaired(list);
  }

  // ── Permissions ────────────────────────────────────────────────────────────

  static Future<bool> requestBluetoothPermissions() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();
      return statuses.values.every((s) => s.isGranted);
    }
    return true;
  }

  // ── Bluetooth Scan ─────────────────────────────────────────────────────────

  /// Scans for nearby Bluetooth devices for [duration] seconds.
  /// Returns a stream of discovered devices.
  static Stream<DiscoveredDevice> scanBluetooth({
    Duration duration = const Duration(seconds: 5),
  }) async* {
    final granted = await requestBluetoothPermissions();
    if (!granted) return;

    try {
      final isOn = await FlutterBluePlus.adapterState.first;
      if (isOn != BluetoothAdapterState.on) return;

      await FlutterBluePlus.startScan(timeout: duration);

      await for (final results in FlutterBluePlus.scanResults) {
        for (final r in results) {
          final name = r.device.platformName.isNotEmpty
              ? r.device.platformName
              : 'Unknown (${r.device.remoteId.str.substring(0, 8)})';
          yield DiscoveredDevice(
            id: r.device.remoteId.str,
            name: name,
            connectionType: DeviceConnectionType.bluetooth,
            rssi: r.rssi,
          );
        }
      }
    } catch (e) {
      debugPrint('BT scan error: $e');
    } finally {
      await FlutterBluePlus.stopScan();
    }
  }

  /// Returns current Bluetooth adapter state stream.
  static Stream<BluetoothAdapterState> get adapterState =>
      FlutterBluePlus.adapterState;
}
