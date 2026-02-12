import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Text input formatter for Rupiah currency
/// Formats input as: Rp1.000.000
class RupiahInputFormatter extends TextInputFormatter {
  final NumberFormat _formatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp',
    decimalDigits: 0,
  );

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    // Remove all non-digit characters
    String digitsOnly = newValue.text.replaceAll(RegExp(r'[^\d]'), '');

    if (digitsOnly.isEmpty) {
      return newValue.copyWith(text: '');
    }

    // Parse the number
    final number = int.tryParse(digitsOnly);
    if (number == null) {
      return oldValue;
    }

    // Format with Rupiah
    final formatted = _formatter.format(number);

    // Calculate new cursor position
    final int newCursorPosition = formatted.length;

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: newCursorPosition),
    );
  }

  /// Extract numeric value from formatted Rupiah string
  static int? parseRupiah(String formattedValue) {
    if (formattedValue.isEmpty) return null;
    
    // Remove all non-digit characters
    String digitsOnly = formattedValue.replaceAll(RegExp(r'[^\d]'), '');
    
    if (digitsOnly.isEmpty) return null;
    
    return int.tryParse(digitsOnly);
  }

  /// Extract numeric value as double from formatted Rupiah string
  static double? parseRupiahAsDouble(String formattedValue) {
    final intValue = parseRupiah(formattedValue);
    return intValue?.toDouble();
  }
}
