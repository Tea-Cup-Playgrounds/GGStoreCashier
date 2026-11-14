// What goes on a printed receipt, independent of the printer. Built from a sale as the API returns
// it (GET/POST /api/sales) or, for a sale still waiting to be sent, from the cart on this device.

import '../../../core/models/json_parse.dart';

class ReceiptItem {
  final String name;
  final double qty;
  final double unitPrice;

  /// Discount on this line (voucher and manual discounts included).
  final double discount;
  final double total;

  const ReceiptItem({required this.name, required this.qty, required this.unitPrice, this.discount = 0, required this.total});
}

class ReceiptPayment {
  final String name;
  final double amount;
  final String? reference;

  const ReceiptPayment({required this.name, required this.amount, this.reference});
}

class ReceiptData {
  /// Sale number (INV-…, or OFF-… for a sale numbered on this device). Null while the server
  /// hasn't answered yet; [reference] identifies the sale then.
  final String? number;
  final String? reference;
  final DateTime date;
  final String? cashier;
  final String? customer;
  final String? locationName;
  final String? locationAddress;
  final String? locationPhone;
  final List<ReceiptItem> items;
  final double subtotal;
  final double discount;

  /// PPN inside the total. Null when not known (sale not on the server yet).
  final double? tax;
  final double total;
  final List<ReceiptPayment> payments;
  final double change;
  final String? voucherCode;

  /// Made without a connection / not on the server yet.
  final bool offline;

  /// A reprint ("SALINAN").
  final bool copy;

  const ReceiptData({
    this.number,
    this.reference,
    required this.date,
    this.cashier,
    this.customer,
    this.locationName,
    this.locationAddress,
    this.locationPhone,
    required this.items,
    required this.subtotal,
    this.discount = 0,
    this.tax,
    required this.total,
    this.payments = const [],
    this.change = 0,
    this.voucherCode,
    this.offline = false,
    this.copy = false,
  });

  double get paid => payments.fold(0, (sum, p) => sum + p.amount);

  ReceiptData asCopy() => ReceiptData(
        number: number,
        reference: reference,
        date: date,
        cashier: cashier,
        customer: customer,
        locationName: locationName,
        locationAddress: locationAddress,
        locationPhone: locationPhone,
        items: items,
        subtotal: subtotal,
        discount: discount,
        tax: tax,
        total: total,
        payments: payments,
        change: change,
        voucherCode: voucherCode,
        offline: offline,
        copy: true,
      );

  /// A sale as the API returns it (`sale` in POST /api/sales and GET /api/sales/:id).
  factory ReceiptData.fromSale(Map<String, dynamic> sale) {
    List<Map<String, dynamic>> list(String key) =>
        ((sale[key] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return ReceiptData(
      number: sale['number']?.toString(),
      date: DateTime.tryParse(sale['occurred_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      cashier: sale['cashier_name'] as String?,
      customer: sale['customer_name'] as String?,
      locationName: sale['location_name'] as String?,
      locationAddress: sale['location_address'] as String?,
      locationPhone: sale['location_phone'] as String?,
      items: [
        for (final l in list('lines'))
          ReceiptItem(
            name: l['description']?.toString() ?? '',
            qty: parseDouble(l['qty']),
            unitPrice: parseDouble(l['unit_price']),
            discount: parseDouble(l['discount']),
            total: parseDouble(l['line_total']),
          ),
      ],
      subtotal: parseDouble(sale['subtotal']),
      discount: parseDouble(sale['discount_total']),
      tax: parseDouble(sale['tax_total']),
      total: parseDouble(sale['grand_total']),
      payments: [
        for (final p in list('payments'))
          ReceiptPayment(name: p['method_name']?.toString() ?? '', amount: parseDouble(p['amount']), reference: p['reference'] as String?),
      ],
      change: parseDouble(sale['change_total']),
      voucherCode: sale['voucher_code'] as String?,
    );
  }
}
