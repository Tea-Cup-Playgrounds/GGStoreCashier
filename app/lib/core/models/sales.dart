// Models for /api/sales, /api/customers and /api/cash-sessions.

import 'json_parse.dart';

class PaymentMethod {
  final int id;
  final String name;
  final String type; // cash | qris | ewallet | card | transfer
  final bool requiresReference;

  const PaymentMethod({required this.id, required this.name, required this.type, this.requiresReference = false});

  factory PaymentMethod.fromJson(Map<String, dynamic> json) => PaymentMethod(
        id: parseInt(json['id']),
        name: json['name']?.toString() ?? '',
        type: json['type']?.toString() ?? 'cash',
        requiresReference: json['requires_reference'] == true,
      );

  bool get isCash => type == 'cash';
}

class Customer {
  final String id;
  final String name;
  final String? phone;

  const Customer({required this.id, required this.name, this.phone});

  factory Customer.fromJson(Map<String, dynamic> json) =>
      Customer(id: json['id'].toString(), name: json['name']?.toString() ?? '', phone: json['phone'] as String?);

  String get label => phone == null ? name : '$name · $phone';
}

/// A customer chosen at checkout: either existing ([id]) or new ([name] + [phone]),
/// which the API registers together with the sale.
class CustomerChoice {
  final String? id;
  final String name;
  final String? phone;

  CustomerChoice.existing(Customer c)
      : id = c.id,
        name = c.name,
        phone = c.phone;

  const CustomerChoice.newCustomer({required this.name, this.phone}) : id = null;

  Map<String, dynamic> toSaleJson() =>
      id != null ? {'customer_id': id} : {'customer': {'name': name, if (phone != null && phone!.isNotEmpty) 'phone': phone}};
}

class CashSessionMethodTotal {
  final String name;
  final String type;
  final double amount;

  const CashSessionMethodTotal({required this.name, required this.type, required this.amount});

  factory CashSessionMethodTotal.fromJson(Map<String, dynamic> json) => CashSessionMethodTotal(
        name: json['name']?.toString() ?? '',
        type: json['type']?.toString() ?? '',
        amount: parseDouble(json['amount']),
      );
}

class CashSession {
  final String id;
  final int locationId;
  final String status; // open | closed
  final DateTime? openedAt;
  final DateTime? closedAt;
  final String? openedByName;
  final double openingCash;
  final double? countedCash;
  final double? difference;
  final int salesCount;
  final double salesTotal;
  final double expectedCash;
  final List<CashSessionMethodTotal> byMethod;

  const CashSession({
    required this.id,
    required this.locationId,
    required this.status,
    this.openedAt,
    this.closedAt,
    this.openedByName,
    this.openingCash = 0,
    this.countedCash,
    this.difference,
    this.salesCount = 0,
    this.salesTotal = 0,
    this.expectedCash = 0,
    this.byMethod = const [],
  });

  factory CashSession.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'] is Map ? Map<String, dynamic>.from(json['summary'] as Map) : const <String, dynamic>{};
    return CashSession(
      id: json['id'].toString(),
      locationId: parseInt(json['location_id']),
      status: json['status']?.toString() ?? 'open',
      openedAt: parseDate(json['opened_at']),
      closedAt: parseDate(json['closed_at']),
      openedByName: json['opened_by_name'] as String?,
      openingCash: parseDouble(json['opening_cash']),
      countedCash: parseNullableDouble(json['counted_cash']),
      difference: parseNullableDouble(json['difference']),
      salesCount: parseInt(summary['sales_count']),
      salesTotal: parseDouble(summary['sales_total']),
      expectedCash: parseDouble(summary['expected_cash']),
      byMethod: parseList(summary['by_method'], CashSessionMethodTotal.fromJson),
    );
  }

  bool get isOpen => status == 'open';
}

/// The stored sale as returned after checkout (enough for the receipt / success screen).
class SaleResult {
  final String id;
  final String number;
  final double grandTotal;
  final double taxTotal;
  final double discountTotal;
  final double paidTotal;
  final double changeTotal;
  final String? customerName;

  const SaleResult({
    required this.id,
    required this.number,
    required this.grandTotal,
    this.taxTotal = 0,
    this.discountTotal = 0,
    this.paidTotal = 0,
    this.changeTotal = 0,
    this.customerName,
  });

  factory SaleResult.fromJson(Map<String, dynamic> json) => SaleResult(
        id: json['id'].toString(),
        number: json['number']?.toString() ?? '',
        grandTotal: parseDouble(json['grand_total']),
        taxTotal: parseDouble(json['tax_total']),
        discountTotal: parseDouble(json['discount_total']),
        paidTotal: parseDouble(json['paid_total']),
        changeTotal: parseDouble(json['change_total']),
        customerName: json['customer_name'] as String?,
      );
}

/// One payment line entered at checkout.
class PaymentEntry {
  final PaymentMethod method;
  final double amount;
  final String? reference;

  const PaymentEntry({required this.method, required this.amount, this.reference});

  Map<String, dynamic> toJson() => {
        'payment_method_id': method.id,
        'amount': amount,
        if (reference != null && reference!.isNotEmpty) 'reference': reference,
      };
}
