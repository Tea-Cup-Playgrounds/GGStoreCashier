import 'package:intl/intl.dart';

class CurrencyFormatter {
  static final NumberFormat _rupiahFormat = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp',
    decimalDigits: 0,
  );

  /// Format a number to Rupiah currency format
  /// Example: 150000 -> Rp150.000
  static String formatToRupiah(num amount) {
    return _rupiahFormat.format(amount);
  }

  /// Format a number to Rupiah currency format with decimal places
  /// Example: 150000.50 -> Rp150.000,50
  static String formatToRupiahWithDecimal(num amount, {int decimalDigits = 2}) {
    final formatter = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp',
      decimalDigits: decimalDigits,
    );
    return formatter.format(amount);
  }

  /// Format a number to compact Rupiah format
  /// Example: 1500000 -> Rp1,5 Jt
  static String formatToCompactRupiah(num amount) {
    if (amount >= 1000000000) {
      return 'Rp${(amount / 1000000000).toStringAsFixed(1)} M';
    } else if (amount >= 1000000) {
      return 'Rp${(amount / 1000000).toStringAsFixed(1)} Jt';
    } else if (amount >= 1000) {
      return 'Rp${(amount / 1000).toStringAsFixed(1)} Rb';
    }
    return formatToRupiah(amount);
  }
}
