// What a scanned code means at the cashier. Run: flutter test test/scan_code_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gg_store_cashier/core/helper/scan_code.dart';
import 'package:gg_store_cashier/core/models/product.dart';

Product _product(String id, String name, {String? barcode, String? sku, String? category}) {
  final now = DateTime(2026);
  return Product(
      id: id, name: name, barcode: barcode, sku: sku, category: category, costPrice: 0, sellPrice: 0, stock: 1, createdAt: now, updatedAt: now);
}

void main() {
  final products = [
    _product('1', 'Charger 20W USB-C', barcode: '8991234500011', sku: 'CHG-20W', category: 'Aksesoris'),
    _product('2', 'Kabel Data USB-C 1m', barcode: '8991234500028', sku: 'KBL-C1M', category: 'Aksesoris'),
    _product('3', 'Pulsa', sku: 'PULSA'),
  ];

  test('a product barcode or SKU finds the product', () {
    expect(ScanCode.findProduct(products, '8991234500028')?.id, '2');
    expect(ScanCode.findProduct(products, 'chg-20w')?.id, '1', reason: 'SKU in any case');
    expect(ScanCode.findProduct(products, ' 8991234500011\r\n')?.id, '1', reason: 'scanner line ends ignored');
    expect(ScanCode.findProduct(products, '899123450001'), isNull, reason: 'only exact matches');
    expect(ScanCode.findProduct(products, ''), isNull);
  });

  test('IMEI and serial numbers are looked up as units', () {
    expect(ScanCode.looksLikeUnitCode('351234560000028'), isTrue);
    expect(ScanCode.looksLikeUnitCode('SN-ABC/12345'), isTrue);
    expect(ScanCode.looksLikeUnitCode('abc'), isFalse);
    expect(ScanCode.looksLikeUnitCode('two words'), isFalse);
  });

  test('the search box matches name, category, barcode and SKU', () {
    List<String> search(String q) => products.where((p) => ScanCode.matchesSearch(p, q)).map((p) => p.id).toList();
    expect(search('kabel'), ['2']);
    expect(search('aksesoris'), ['1', '2']);
    expect(search('KBL'), ['2']);
    expect(search('89912345000'), ['1', '2']);
    expect(search('  '), ['1', '2', '3']);
  });
}
