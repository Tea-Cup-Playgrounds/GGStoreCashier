/// Client-side IMEI check, same rule as API/src/services/stock.js: 15 digits whose last digit is
/// the Luhn check digit. Catches typos before the request is sent.
class ImeiValidator {
  static String normalize(String value) => value.replaceAll(RegExp(r'\s+'), '');

  static bool isValid(String imei) {
    if (!RegExp(r'^\d{15}$').hasMatch(imei)) return false;
    var sum = 0;
    for (var i = 0; i < 15; i++) {
      var digit = int.parse(imei[14 - i]);
      if (i.isOdd) {
        digit *= 2;
        if (digit > 9) digit -= 9;
      }
      sum += digit;
    }
    return sum % 10 == 0;
  }

  /// Form-field validator. [required] false allows empty input (warehouse receiving).
  static String? validate(String? value, {bool required = true, String label = 'IMEI'}) {
    final v = normalize(value ?? '');
    if (v.isEmpty) return required ? '$label wajib diisi' : null;
    if (!RegExp(r'^\d+$').hasMatch(v)) return '$label hanya boleh angka';
    if (v.length != 15) return '$label harus 15 digit (${v.length})';
    if (!isValid(v)) return '$label tidak valid, periksa kembali';
    return null;
  }
}
