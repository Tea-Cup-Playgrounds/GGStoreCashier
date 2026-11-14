import '../models/product.dart';

/// What a scanned (or typed) code refers to at the cashier.
class ScanCode {
  /// Removes the line ends and spaces scanners add around a code.
  static String normalize(String raw) => raw.replaceAll(RegExp(r'[\r\n\t]'), '').trim();

  /// The product whose barcode or SKU is exactly [code] (letters in any case).
  static Product? findProduct(Iterable<Product> products, String code) {
    final wanted = normalize(code).toUpperCase();
    if (wanted.isEmpty) return null;
    for (final p in products) {
      if (p.barcode?.toUpperCase() == wanted || p.sku?.toUpperCase() == wanted) return p;
    }
    return null;
  }

  /// Could be a phone's IMEI or a serial number (looked up among the units in stock).
  static bool looksLikeUnitCode(String code) => RegExp(r'^[A-Za-z0-9/-]{6,50}$').hasMatch(normalize(code));

  /// Search box text matches the product's name, category, barcode or SKU.
  static bool matchesSearch(Product p, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return p.name.toLowerCase().contains(q) ||
        (p.category?.toLowerCase().contains(q) ?? false) ||
        (p.barcode?.toLowerCase().contains(q) ?? false) ||
        (p.sku?.toLowerCase().contains(q) ?? false);
  }
}
