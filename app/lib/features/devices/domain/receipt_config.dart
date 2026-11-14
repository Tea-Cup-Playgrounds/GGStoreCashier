import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The receipt template set in Pengaturan → Tampilan Struk (receipt_editor_page.dart), stored under
/// [prefsKey]. Empty branch / address / phone mean "use the branch's own data from the sale".
class ReceiptConfig {
  static const prefsKey = 'receipt_config';

  /// Receipt sections, in the order they are printed (the editor can reorder and hide them).
  /// 'logo' is not printed: thermal printers get the store name as text instead.
  static const defaultSections = ['logo', 'header', 'contact', 'divider', 'items', 'totals', 'payment', 'divider', 'barcode', 'footer'];

  final String storeName;
  final String branch;
  final String address;
  final String phone;
  final String footer;
  final String taxLabel;
  final String discountLabel;
  final String voucherLabel;
  final bool taxEnabled;
  final bool discountEnabled;
  final bool voucherEnabled;
  final bool showCashierName;
  final bool showTransactionId;
  final bool showDateTime;

  /// true = 80mm paper (48 characters a line), false = 58mm (32).
  final bool wide;

  /// Visible sections in print order.
  final List<String> sections;

  const ReceiptConfig({
    this.storeName = 'GG Store',
    this.branch = '',
    this.address = '',
    this.phone = '',
    this.footer = 'Terima kasih atas kunjungan Anda',
    this.taxLabel = 'PPN',
    this.discountLabel = 'Diskon',
    this.voucherLabel = 'Voucher',
    this.taxEnabled = true,
    this.discountEnabled = true,
    this.voucherEnabled = true,
    this.showCashierName = true,
    this.showTransactionId = true,
    this.showDateTime = true,
    this.wide = false,
    this.sections = defaultSections,
  });

  /// Characters per line in the printer's normal font.
  int get charsPerLine => wide ? 48 : 32;

  bool shows(String section) => sections.contains(section);

  /// The editor's saved map. Older saves have only `paperSizeIndex` (0–2 are 58mm, 3–4 are 80mm).
  factory ReceiptConfig.fromJson(Map<String, dynamic> m) {
    String text(String key, String fallback) => m[key] is String ? m[key] as String : fallback;
    bool flag(String key) => m[key] is bool ? m[key] as bool : true;
    final paper = m['paperWidth'];
    final sections = m['sections'] is List
        ? [
            for (final s in m['sections'] as List)
              if (s is Map && s['visible'] != false && s['type'] is String) s['type'] as String,
          ]
        : defaultSections;
    const d = ReceiptConfig();
    return ReceiptConfig(
      storeName: text('storeName', d.storeName),
      branch: text('branch', d.branch),
      address: text('address', d.address),
      phone: text('phone', d.phone),
      footer: text('footer', d.footer),
      taxLabel: text('taxLabel', d.taxLabel),
      discountLabel: text('discountLabel', d.discountLabel),
      voucherLabel: text('voucherLabel', d.voucherLabel),
      taxEnabled: flag('taxEnabled'),
      discountEnabled: flag('discountEnabled'),
      voucherEnabled: flag('voucherEnabled'),
      showCashierName: flag('showCashierName'),
      showTransactionId: flag('showTransactionId'),
      showDateTime: flag('showDateTime'),
      wide: paper is String ? paper == 'mm80' : ((m['paperSizeIndex'] as num?)?.toInt() ?? 0) >= 3,
      sections: sections,
    );
  }

  static Future<ReceiptConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    if (raw == null) return const ReceiptConfig();
    try {
      return ReceiptConfig.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return const ReceiptConfig();
    }
  }
}
