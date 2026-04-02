import 'package:intl/intl.dart';

/// Central date formatting utility.
/// All display dates in the app should go through here.
class DateFormatter {
  DateFormatter._();

  static final _display   = DateFormat('dd-MM-yy');      // 03-04-26
  static final _full      = DateFormat('dd-MM-yyyy');    // 03-04-2026
  static final _chartAxis = DateFormat('dd/MM');         // 03/04  — compact for chart axes
  static final _apiDate   = DateFormat('yyyy-MM-dd');    // 2026-04-03 — for API params

  /// Format any value (DateTime, ISO String, or null) to dd-MM-yy.
  /// Returns '—' if the value cannot be parsed.
  static String format(dynamic value) {
    final dt = _parse(value);
    return dt != null ? _display.format(dt) : '—';
  }

  /// Full year variant: dd-MM-yyyy
  static String formatFull(dynamic value) {
    final dt = _parse(value);
    return dt != null ? _full.format(dt) : '—';
  }

  /// Compact form for chart axis labels: dd/MM
  static String formatAxis(dynamic value) {
    final dt = _parse(value);
    return dt != null ? _chartAxis.format(dt) : '';
  }

  /// yyyy-MM-dd for sending to the API
  static String toApiDate(DateTime dt) => _apiDate.format(dt);

  static DateTime? _parse(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}
