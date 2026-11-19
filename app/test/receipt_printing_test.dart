// Receipts: layout from a real API sale, ESC/POS bytes, and sending them to a network printer.
// Run: flutter test test/receipt_printing_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gg_store_cashier/core/services/offline_sale_number.dart';
import 'package:gg_store_cashier/features/devices/data/receipt_printer.dart';
import 'package:gg_store_cashier/features/devices/domain/esc_pos.dart';
import 'package:gg_store_cashier/features/devices/domain/receipt.dart';
import 'package:gg_store_cashier/features/devices/domain/receipt_config.dart';
import 'package:gg_store_cashier/features/devices/domain/receipt_layout.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A sale exactly as POST /api/sales returned it (phone with IMEI, 2 tempered glass, customer).
Map<String, dynamic> _fixture() =>
    Map<String, dynamic>.from(jsonDecode(File('test/fixtures/sale_with_imei.json').readAsStringSync()) as Map);

List<String> _text(List<ReceiptRow> rows, int width) => [
      for (final r in rows)
        switch (r) {
          TextRow() => r.text,
          DividerRow() => '-' * width,
          QrRow() => '[QR ${r.data}]',
        },
    ];

void main() {
  group('receipt from an API sale', () {
    final receipt = ReceiptData.fromSale(_fixture());

    test('reads lines, totals, payments and the branch', () {
      expect(receipt.number, 'INV-BR01-261114-0003');
      expect(receipt.items, hasLength(2));
      expect(receipt.items.first.name, contains('351234560000028'), reason: 'IMEI is part of the line name');
      expect(receipt.total, 2049000);
      expect(receipt.tax, closeTo(203054.05, 0.001));
      expect(receipt.change, 51000);
      expect(receipt.paid, 2100000);
      expect(receipt.payments.single.name, 'Tunai');
      expect(receipt.customer, 'Budi Pelanggan');
      expect(receipt.cashier, 'Kasir Cabang Satu');
      expect(receipt.locationName, 'Cabang 1');
    });

    for (final wide in [false, true]) {
      test('fits ${wide ? 80 : 58} mm paper', () {
        final config = ReceiptConfig(wide: wide);
        final rows = ReceiptLayout.build(receipt, config);
        for (final row in rows.whereType<TextRow>()) {
          final max = row.large ? config.charsPerLine ~/ 2 : config.charsPerLine;
          expect(row.text.length, lessThanOrEqualTo(max), reason: '"${row.text}"');
        }
        final lines = _text(rows, config.charsPerLine);
        expect(lines, contains(predicate<String>((l) => l.startsWith('TOTAL') && l.endsWith('2.049.000'))));
        expect(lines, contains(predicate<String>((l) => l.startsWith('Termasuk PPN') && l.endsWith('203.054,05'))));
        expect(lines, contains(predicate<String>((l) => l.startsWith('Kembali') && l.endsWith('51.000'))));
        expect(lines, contains(predicate<String>((l) => l.startsWith('No') && l.endsWith('INV-BR01-261114-0003'))));
        expect(lines, contains('[QR INV-BR01-261114-0003]'));
        expect(lines.join('\n'), contains('351234560000028'));
      });
    }

    test('hidden sections and switched-off details are left out', () {
      const config = ReceiptConfig(sections: ['header', 'items', 'totals'], showCashierName: false, taxEnabled: false);
      final lines = _text(ReceiptLayout.build(receipt, config), config.charsPerLine);
      expect(lines.any((l) => l.startsWith('Kasir')), isFalse);
      expect(lines.any((l) => l.contains('PPN')), isFalse);
      expect(lines.any((l) => l.startsWith('[QR')), isFalse);
      expect(lines.any((l) => l.contains('Terima kasih')), isFalse);
      expect(lines.any((l) => l.startsWith('Tunai')), isFalse);
    });

    test('a reprint is marked as a copy', () {
      final lines = _text(ReceiptLayout.build(receipt.asCopy(), const ReceiptConfig()), 32);
      expect(lines, contains('** SALINAN **'));
    });
  });

  group('receipt of a sale not on the server yet', () {
    final offline = ReceiptData(
      number: 'OFF-BR01-261114-K7QX-001',
      date: DateTime(2026, 11, 14, 9, 30),
      items: const [ReceiptItem(name: 'Charger 20W USB-C', qty: 2, unitPrice: 85000, total: 170000)],
      subtotal: 170000,
      total: 170000,
      payments: const [ReceiptPayment(name: 'Tunai', amount: 200000)],
      change: 30000,
      offline: true,
    );

    test('says it is offline and that prices include PPN (amount not known yet)', () {
      final lines = _text(ReceiptLayout.build(offline, const ReceiptConfig()), 32);
      expect(lines, contains('(transaksi offline)'));
      expect(lines, contains('Harga sudah termasuk PPN'));
      expect(lines, contains(predicate<String>((l) => l.endsWith('OFF-BR01-261114-K7QX-001'))));
    });

    test('without a number it shows a reference to look the sale up', () {
      final pending = ReceiptData(date: DateTime(2026), reference: 'A1B2C3D4', items: const [], subtotal: 0, total: 0, offline: true);
      final lines = _text(ReceiptLayout.build(pending, const ReceiptConfig()), 32);
      expect(lines, contains(predicate<String>((l) => l.startsWith('No') && l.endsWith('menunggu server'))));
      expect(lines, contains(predicate<String>((l) => l.startsWith('Ref') && l.endsWith('A1B2C3D4'))));
      expect(lines.any((l) => l.startsWith('[QR')), isFalse);
    });

    test('tax added on top of prices is listed before the total', () {
      final onTop = ReceiptData(date: DateTime(2026), items: const [], subtotal: 100000, tax: 11000, total: 111000);
      final lines = _text(ReceiptLayout.build(onTop, const ReceiptConfig()), 32);
      final taxLine = lines.indexWhere((l) => l.startsWith('PPN'));
      final totalLine = lines.indexWhere((l) => l.startsWith('TOTAL'));
      expect(taxLine, greaterThanOrEqualTo(0));
      expect(taxLine, lessThan(totalLine));
    });
  });

  group('layout helpers', () {
    test('money: thousands with dots, cents only when present', () {
      expect(ReceiptLayout.money(2049000), '2.049.000');
      expect(ReceiptLayout.money(203054.05), '203.054,05');
      expect(ReceiptLayout.money(-5000), '-5.000');
      expect(ReceiptLayout.money(0), '0');
    });

    test('long names wrap and long words are cut', () {
      expect(ReceiptLayout.wrap('HP Android Demo X 4/64GB (351234560000028)', 20).every((l) => l.length <= 20), isTrue);
      expect(ReceiptLayout.wrap('A' * 45, 20), ['A' * 20, 'A' * 20, 'A' * 5]);
    });
  });

  group('ESC/POS', () {
    test('initializes, feeds and cuts', () {
      final bytes = EscPos.encode(const [TextRow('Halo')], charsPerLine: 32);
      expect(bytes.take(2), [0x1B, 0x40]);
      expect(bytes.sublist(bytes.length - 4), [0x1D, 0x56, 0x42, 0x00]);
      expect(utf8.decode(bytes.where((b) => b >= 0x20 && b < 0x7F).toList()), contains('Halo'));
    });

    test('opens the cash drawer only when asked', () {
      const drawer = [0x1B, 0x70, 0x00, 0x19, 0xFA];
      bool hasDrawer(List<int> b) => String.fromCharCodes(b).contains(String.fromCharCodes(drawer));
      expect(hasDrawer(EscPos.encode(const [], charsPerLine: 32)), isFalse);
      expect(hasDrawer(EscPos.encode(const [], charsPerLine: 32, openDrawer: true)), isTrue);
    });

    test('QR code stores its data with the right length', () {
      final qr = EscPos.qr('INV-1');
      final store = String.fromCharCodes(qr).indexOf(String.fromCharCodes([0x1D, 0x28, 0x6B, 8, 0, 0x31, 0x50, 0x30]));
      expect(store, greaterThan(0), reason: 'length = 5 data bytes + 3');
      expect(String.fromCharCodes(qr), contains('INV-1'));
    });

    test('non-ASCII text cannot reach the printer as raw bytes', () {
      expect(EscPos.text('José – Café'), 'Jose - Cafe'.codeUnits);
      expect(EscPos.text('東京'), '??'.codeUnits);
      expect(EscPos.text('a\x1Bb'), 'a?b'.codeUnits, reason: 'a control character in a name is not sent');
    });
  });

  group('network printer', () {
    test('receives exactly the receipt bytes', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final received = Completer<List<int>>();
      server.listen((socket) async {
        final data = <int>[];
        await socket.forEach(data.addAll);
        received.complete(data);
      });
      final bytes = ReceiptPrinter.bytesFor(ReceiptData.fromSale(_fixture()), const ReceiptConfig(), openDrawer: true);
      await NetworkPrinterTransport('127.0.0.1', port: server.port).send(bytes);
      expect(await received.future.timeout(const Duration(seconds: 5)), bytes);
      await server.close();
    });

    test('a printer that is off gives a message for the cashier', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      await server.close(); // nothing listening there now
      await expectLater(
        NetworkPrinterTransport('127.0.0.1', port: port, timeout: const Duration(seconds: 2)).send([1, 2, 3]),
        throwsA(isA<PrinterException>().having((e) => e.message, 'message', contains('tidak bisa dihubungi'))),
      );
    });
  });

  group('settings', () {
    test('editor template: old saves with only a paper index, hidden sections', () {
      final config = ReceiptConfig.fromJson({
        'storeName': 'Toko HP Jaya',
        'paperSizeIndex': 3,
        'sections': [
          {'type': 'header', 'visible': true},
          {'type': 'barcode', 'visible': false},
          {'type': 'footer', 'visible': true},
        ],
      });
      expect(config.wide, isTrue);
      expect(config.charsPerLine, 48);
      expect(config.sections, ['header', 'footer']);
      expect(config.storeName, 'Toko HP Jaya');
      expect(ReceiptConfig.fromJson({'paperWidth': 'mm58', 'paperSizeIndex': 4}).wide, isFalse);
    });

    test('printer settings round-trip', () {
      const s = PrinterSettings(connection: PrinterConnection.network, address: '192.168.1.50', port: 9100, autoPrint: true);
      final back = PrinterSettings.fromJson(s.toJson());
      expect(back.connection, PrinterConnection.network);
      expect(back.label, '192.168.1.50:9100');
      expect(back.autoPrint, isTrue);
      expect(const PrinterSettings().isConfigured, isFalse);
    });
  });

  group('offline sale numbers', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('count up per day with a fixed device part', () async {
      final day1 = DateTime(2026, 11, 14);
      final a = await OfflineSaleNumber.next('BR01', now: day1);
      final b = await OfflineSaleNumber.next('BR01', now: day1);
      final c = await OfflineSaleNumber.next('br-02', now: DateTime(2026, 11, 15));
      final pattern = RegExp(r'^OFF-([A-Z0-9]+)-(\d{6})-([A-Z2-9]{4})-(\d{3})$');
      for (final n in [a, b, c]) {
        expect(pattern.hasMatch(n), isTrue, reason: n);
        expect(n.length, lessThanOrEqualTo(40), reason: 'sales.number is varchar(40)');
      }
      expect(a, endsWith('-001'));
      expect(b, endsWith('-002'));
      expect(c, startsWith('OFF-BR02-261115-'));
      expect(c, endsWith('-001'), reason: 'a new day starts again at 001');
      expect(pattern.firstMatch(a)!.group(3), pattern.firstMatch(c)!.group(3), reason: 'same device');
    });
  });
}
