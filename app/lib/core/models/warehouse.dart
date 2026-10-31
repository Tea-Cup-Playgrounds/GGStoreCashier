// Models for /api/purchasing, /api/transfers and /api/opnames.

import 'catalog.dart' show SerialType, serialTypeFromApi;
import 'json_parse.dart';

class Supplier {
  final int id;
  final String code;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
  final bool isActive;
  final double outstanding;

  const Supplier({
    required this.id,
    required this.code,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.notes,
    this.isActive = true,
    this.outstanding = 0,
  });

  factory Supplier.fromJson(Map<String, dynamic> json) => Supplier(
        id: parseInt(json['id']),
        code: json['code']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        address: json['address'] as String?,
        notes: json['notes'] as String?,
        isActive: json['is_active'] != false,
        outstanding: parseDouble(json['outstanding']),
      );
}

// ── goods receipts ───────────────────────────────────────────────────────────

class ReceiptUnit {
  final String? id;
  final String? imei1;
  final String? imei2;
  final String? serialNumber;
  final String conditionGrade;
  final String? unitId;

  const ReceiptUnit({this.id, this.imei1, this.imei2, this.serialNumber, this.conditionGrade = 'new', this.unitId});

  factory ReceiptUnit.fromJson(Map<String, dynamic> json) => ReceiptUnit(
        id: json['id']?.toString(),
        imei1: json['imei1'] as String?,
        imei2: json['imei2'] as String?,
        serialNumber: json['serial_number'] as String?,
        conditionGrade: json['condition_grade']?.toString() ?? 'new',
        unitId: json['unit_id'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'imei1': imei1,
        'imei2': imei2,
        'serial_number': serialNumber,
        'condition_grade': conditionGrade,
      };
}

class ReceiptItem {
  final String? id;
  final int variantId;
  final String name;
  final String? sku;
  final bool isSerialized;
  final SerialType? serialType;
  final int qty;
  final double unitCost;
  final double taxRate;
  final double taxAmount;
  final double lineTotal;
  final List<ReceiptUnit> units;

  const ReceiptItem({
    this.id,
    required this.variantId,
    required this.name,
    this.sku,
    this.isSerialized = false,
    this.serialType,
    required this.qty,
    required this.unitCost,
    this.taxRate = 0,
    this.taxAmount = 0,
    this.lineTotal = 0,
    this.units = const [],
  });

  factory ReceiptItem.fromJson(Map<String, dynamic> json) => ReceiptItem(
        id: json['id']?.toString(),
        variantId: parseInt(json['variant_id']),
        name: json['name']?.toString() ?? '',
        sku: json['sku'] as String?,
        isSerialized: json['is_serialized'] == true,
        serialType: serialTypeFromApi(json['serial_type'] as String?),
        qty: parseInt(json['qty']),
        unitCost: parseDouble(json['unit_cost']),
        taxRate: parseDouble(json['tax_rate']),
        taxAmount: parseDouble(json['tax_amount']),
        lineTotal: parseDouble(json['line_total']),
        units: parseList(json['units'], ReceiptUnit.fromJson),
      );
}

class SupplierPayment {
  final String id;
  final double amount;
  final String method;
  final String? reference;
  final String? paidAt;
  final String? note;
  final String? createdByName;

  const SupplierPayment({
    required this.id,
    required this.amount,
    required this.method,
    this.reference,
    this.paidAt,
    this.note,
    this.createdByName,
  });

  factory SupplierPayment.fromJson(Map<String, dynamic> json) => SupplierPayment(
        id: json['id'].toString(),
        amount: parseDouble(json['amount']),
        method: json['method']?.toString() ?? '',
        reference: json['reference'] as String?,
        paidAt: json['paid_at'] as String?,
        note: json['note'] as String?,
        createdByName: json['created_by_name'] as String?,
      );
}

String paymentMethodLabel(String method) => switch (method) {
      'cash' => 'Tunai',
      'transfer' => 'Transfer',
      'giro' => 'Giro',
      _ => 'Lainnya',
    };

class GoodsReceipt {
  final String id;
  final String number;
  final int supplierId;
  final String supplierName;
  final int locationId;
  final String? locationCode;
  final String? locationName;
  final String? locationType;
  final String? invoiceNo;
  final String? invoiceDate;
  final String? dueDate;
  final String status; // draft | posted
  final String? paymentStatus; // unpaid | partial | paid (posted only)
  final double subtotal;
  final double taxTotal;
  final double grandTotal;
  final double paidTotal;
  final String? note;
  final int itemQty;
  final DateTime? createdAt;
  final DateTime? postedAt;
  final String? postedByName;
  final List<ReceiptItem> items;
  final List<SupplierPayment> payments;

  const GoodsReceipt({
    required this.id,
    required this.number,
    required this.supplierId,
    required this.supplierName,
    required this.locationId,
    this.locationCode,
    this.locationName,
    this.locationType,
    this.invoiceNo,
    this.invoiceDate,
    this.dueDate,
    required this.status,
    this.paymentStatus,
    this.subtotal = 0,
    this.taxTotal = 0,
    this.grandTotal = 0,
    this.paidTotal = 0,
    this.note,
    this.itemQty = 0,
    this.createdAt,
    this.postedAt,
    this.postedByName,
    this.items = const [],
    this.payments = const [],
  });

  factory GoodsReceipt.fromJson(Map<String, dynamic> json) => GoodsReceipt(
        id: json['id'].toString(),
        number: json['number']?.toString() ?? '',
        supplierId: parseInt(json['supplier_id']),
        supplierName: json['supplier_name']?.toString() ?? '',
        locationId: parseInt(json['location_id']),
        locationCode: json['location_code'] as String?,
        locationName: json['location_name'] as String?,
        locationType: json['location_type'] as String?,
        invoiceNo: json['invoice_no'] as String?,
        invoiceDate: json['invoice_date'] as String?,
        dueDate: json['due_date'] as String?,
        status: json['status']?.toString() ?? 'draft',
        paymentStatus: json['payment_status'] as String?,
        subtotal: parseDouble(json['subtotal']),
        taxTotal: parseDouble(json['tax_total']),
        grandTotal: parseDouble(json['grand_total']),
        paidTotal: parseDouble(json['paid_total']),
        note: json['note'] as String?,
        itemQty: parseInt(json['item_qty']),
        createdAt: parseDate(json['created_at']),
        postedAt: parseDate(json['posted_at']),
        postedByName: json['posted_by_name'] as String?,
        items: parseList(json['items'], ReceiptItem.fromJson),
        payments: parseList(json['payments'], SupplierPayment.fromJson),
      );

  bool get isDraft => status == 'draft';
  double get outstanding => (grandTotal - paidTotal).clamp(0, double.infinity).toDouble();
}

String receiptPaymentLabel(String? status) => switch (status) {
      'paid' => 'Lunas',
      'partial' => 'Dibayar sebagian',
      'unpaid' => 'Belum dibayar',
      _ => 'Draf',
    };

// ── transfers ────────────────────────────────────────────────────────────────

class TransferUnit {
  final String unitId;
  final String? outcome; // received | returned | written_off | null (pending / in transit)
  final String? imei1;
  final String? imei2;
  final String? serialNumber;
  final String? status;

  const TransferUnit({required this.unitId, this.outcome, this.imei1, this.imei2, this.serialNumber, this.status});

  factory TransferUnit.fromJson(Map<String, dynamic> json) => TransferUnit(
        unitId: json['unit_id'].toString(),
        outcome: json['outcome'] as String?,
        imei1: json['imei1'] as String?,
        imei2: json['imei2'] as String?,
        serialNumber: json['serial_number'] as String?,
        status: json['status'] as String?,
      );

  String get identifier => imei1 ?? serialNumber ?? 'Tanpa IMEI';

  bool matches(String code) => code == imei1 || code == imei2 || code == serialNumber;
}

class TransferItem {
  final String id;
  final int variantId;
  final String name;
  final String? sku;
  final bool isSerialized;
  final int qtySent;
  final int? qtyReceived;
  final int qtyResolved;
  final int outstanding;
  final List<TransferUnit> units;

  const TransferItem({
    required this.id,
    required this.variantId,
    required this.name,
    this.sku,
    this.isSerialized = false,
    required this.qtySent,
    this.qtyReceived,
    this.qtyResolved = 0,
    this.outstanding = 0,
    this.units = const [],
  });

  factory TransferItem.fromJson(Map<String, dynamic> json) => TransferItem(
        id: json['id'].toString(),
        variantId: parseInt(json['variant_id']),
        name: json['name']?.toString() ?? '',
        sku: json['sku'] as String?,
        isSerialized: json['is_serialized'] == true,
        qtySent: parseInt(json['qty_sent']),
        qtyReceived: parseNullableInt(json['qty_received']),
        qtyResolved: parseInt(json['qty_resolved']),
        outstanding: parseInt(json['outstanding']),
        units: parseList(json['units'], TransferUnit.fromJson),
      );
}

class StockTransfer {
  final String id;
  final String number;
  final String status; // draft | sent | received | partially_received | cancelled
  final int fromLocationId;
  final String? fromCode;
  final String? fromName;
  final int toLocationId;
  final String? toCode;
  final String? toName;
  final String? note;
  final String? receiveNote;
  final int qtyTotal;
  final DateTime? createdAt;
  final DateTime? sentAt;
  final DateTime? receivedAt;
  final DateTime? resolvedAt;
  final String? sentByName;
  final String? receivedByName;
  final List<TransferItem> items;

  const StockTransfer({
    required this.id,
    required this.number,
    required this.status,
    required this.fromLocationId,
    this.fromCode,
    this.fromName,
    required this.toLocationId,
    this.toCode,
    this.toName,
    this.note,
    this.receiveNote,
    this.qtyTotal = 0,
    this.createdAt,
    this.sentAt,
    this.receivedAt,
    this.resolvedAt,
    this.sentByName,
    this.receivedByName,
    this.items = const [],
  });

  factory StockTransfer.fromJson(Map<String, dynamic> json) => StockTransfer(
        id: json['id'].toString(),
        number: json['number']?.toString() ?? '',
        status: json['status']?.toString() ?? 'draft',
        fromLocationId: parseInt(json['from_location_id']),
        fromCode: json['from_code'] as String?,
        fromName: json['from_name'] as String?,
        toLocationId: parseInt(json['to_location_id']),
        toCode: json['to_code'] as String?,
        toName: json['to_name'] as String?,
        note: json['note'] as String?,
        receiveNote: json['receive_note'] as String?,
        qtyTotal: parseInt(json['qty_total']),
        createdAt: parseDate(json['created_at']),
        sentAt: parseDate(json['sent_at']),
        receivedAt: parseDate(json['received_at']),
        resolvedAt: parseDate(json['resolved_at']),
        sentByName: json['sent_by_name'] as String?,
        receivedByName: json['received_by_name'] as String?,
        items: parseList(json['items'], TransferItem.fromJson),
      );

  int get outstanding => items.fold(0, (sum, i) => sum + i.outstanding);
}

String transferStatusLabel(String status) => switch (status) {
      'draft' => 'Draf',
      'sent' => 'Dikirim',
      'received' => 'Diterima',
      'partially_received' => 'Diterima sebagian',
      'cancelled' => 'Dibatalkan',
      _ => status,
    };

// ── stock opname ─────────────────────────────────────────────────────────────

class OpnameUnit {
  final String unitId;
  final bool found;
  final String? imei1;
  final String? imei2;
  final String? serialNumber;
  final String? status;

  const OpnameUnit({required this.unitId, required this.found, this.imei1, this.imei2, this.serialNumber, this.status});

  factory OpnameUnit.fromJson(Map<String, dynamic> json) => OpnameUnit(
        unitId: json['unit_id'].toString(),
        found: json['found'] == true,
        imei1: json['imei1'] as String?,
        imei2: json['imei2'] as String?,
        serialNumber: json['serial_number'] as String?,
        status: json['status'] as String?,
      );

  String get identifier => imei1 ?? serialNumber ?? 'Tanpa IMEI';
}

class OpnameItem {
  final String id;
  final int variantId;
  final String name;
  final String? sku;
  final String? barcode;
  final bool isSerialized;
  final int systemQty;
  final int? countedQty;
  final int? variance;
  final String? note;
  final List<OpnameUnit> units;

  const OpnameItem({
    required this.id,
    required this.variantId,
    required this.name,
    this.sku,
    this.barcode,
    this.isSerialized = false,
    required this.systemQty,
    this.countedQty,
    this.variance,
    this.note,
    this.units = const [],
  });

  factory OpnameItem.fromJson(Map<String, dynamic> json) => OpnameItem(
        id: json['id'].toString(),
        variantId: parseInt(json['variant_id']),
        name: json['name']?.toString() ?? '',
        sku: json['sku'] as String?,
        barcode: json['barcode'] as String?,
        isSerialized: json['is_serialized'] == true,
        systemQty: parseInt(json['system_qty']),
        countedQty: parseNullableInt(json['counted_qty']),
        variance: parseNullableInt(json['variance']),
        note: json['note'] as String?,
        units: parseList(json['units'], OpnameUnit.fromJson),
      );
}

class OpnameExtra {
  final String identifier;
  final String? unitId;
  final String? unitName;
  final String? unitLocationCode;
  final String? unitStatus;

  const OpnameExtra({required this.identifier, this.unitId, this.unitName, this.unitLocationCode, this.unitStatus});

  factory OpnameExtra.fromJson(Map<String, dynamic> json) => OpnameExtra(
        identifier: json['identifier'].toString(),
        unitId: json['unit_id'] as String?,
        unitName: json['unit_name'] as String?,
        unitLocationCode: json['unit_location_code'] as String?,
        unitStatus: json['unit_status'] as String?,
      );
}

class StockOpname {
  final String id;
  final String number;
  final int locationId;
  final String? locationCode;
  final String? locationName;
  final String status; // counting | approved | cancelled
  final String? categoryName;
  final String? note;
  final int itemCount;
  final DateTime? createdAt;
  final DateTime? approvedAt;
  final String? approvedByName;
  final List<OpnameItem> items;
  final List<OpnameExtra> extras;

  const StockOpname({
    required this.id,
    required this.number,
    required this.locationId,
    this.locationCode,
    this.locationName,
    required this.status,
    this.categoryName,
    this.note,
    this.itemCount = 0,
    this.createdAt,
    this.approvedAt,
    this.approvedByName,
    this.items = const [],
    this.extras = const [],
  });

  factory StockOpname.fromJson(Map<String, dynamic> json) => StockOpname(
        id: json['id'].toString(),
        number: json['number']?.toString() ?? '',
        locationId: parseInt(json['location_id']),
        locationCode: json['location_code'] as String?,
        locationName: json['location_name'] as String?,
        status: json['status']?.toString() ?? 'counting',
        categoryName: json['category_name'] as String?,
        note: json['note'] as String?,
        itemCount: parseInt(json['item_count']),
        createdAt: parseDate(json['created_at']),
        approvedAt: parseDate(json['approved_at']),
        approvedByName: json['approved_by_name'] as String?,
        items: parseList(json['items'], OpnameItem.fromJson),
        extras: parseList(json['extras'], OpnameExtra.fromJson),
      );

  bool get isCounting => status == 'counting';
}

String opnameStatusLabel(String status) => switch (status) {
      'counting' => 'Sedang dihitung',
      'approved' => 'Disetujui',
      'cancelled' => 'Dibatalkan',
      _ => status,
    };

/// Result of scanning an IMEI during a count.
class OpnameScanResult {
  final String result; // found | already | elsewhere | unknown
  final String message;

  const OpnameScanResult({required this.result, required this.message});
}
