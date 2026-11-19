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
  /// Indonesian decimals use a comma, and a trailing ",0" is dropped (Rp2 Jt, not Rp2,0 Jt).
  static String formatToCompactRupiah(num amount) {
    final abs = amount.abs();
    final sign = amount < 0 ? '-' : '';
    String compact(num value, String unit) {
      var text = value.toStringAsFixed(1).replaceAll('.', ',');
      if (text.endsWith(',0')) text = text.substring(0, text.length - 2);
      return '${sign}Rp$text $unit';
    }

    if (abs >= 1000000000) return compact(abs / 1000000000, 'M');
    if (abs >= 1000000) return compact(abs / 1000000, 'Jt');
    if (abs >= 1000) return compact(abs / 1000, 'rb');
    return formatToRupiah(amount);
  }
}
