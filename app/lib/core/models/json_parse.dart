// Lenient JSON readers for API models. MySQL DECIMAL columns arrive as strings, ids sometimes
// as strings, so numbers are parsed from either.

double parseDouble(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

double? parseNullableDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

int parseInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}

int? parseNullableInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  return int.tryParse(value.toString());
}

DateTime? parseDate(dynamic value) => value == null ? null : DateTime.tryParse(value.toString());

List<T> parseList<T>(dynamic value, T Function(Map<String, dynamic>) parse) =>
    ((value as List?) ?? const []).map((e) => parse(Map<String, dynamic>.from(e as Map))).toList();
