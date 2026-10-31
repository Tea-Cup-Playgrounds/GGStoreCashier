// Models for /api/locations, /api/catalog and /api/stock.
// MySQL DECIMAL columns arrive as strings, so numbers go through _toDouble/_toInt.

double _toDouble(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

double? _toNullableDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

int _toInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}

int? _toNullableInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  return int.tryParse(value.toString());
}

DateTime? _toDate(dynamic value) => value == null ? null : DateTime.tryParse(value.toString());

class Location {
  final int id;
  final String? code;
  final String name;
  final String type; // 'branch' | 'warehouse'
  final bool isActive;

  const Location({required this.id, this.code, required this.name, required this.type, this.isActive = true});

  bool get isWarehouse => type == 'warehouse';

  String get label => code != null ? '$code · $name' : name;

  factory Location.fromJson(Map<String, dynamic> json) => Location(
        id: _toInt(json['id']),
        code: json['code'] as String?,
        name: json['name']?.toString() ?? '',
        type: json['type']?.toString() ?? 'branch',
        isActive: json['is_active'] != false,
      );
}

class Brand {
  final int id;
  final String name;

  const Brand({required this.id, required this.name});

  factory Brand.fromJson(Map<String, dynamic> json) => Brand(id: _toInt(json['id']), name: json['name'].toString());
}

enum SerialType { imei, imeiDual, serial }

SerialType? serialTypeFromApi(String? value) => switch (value) {
      'imei' => SerialType.imei,
      'imei_dual' => SerialType.imeiDual,
      'serial' => SerialType.serial,
      _ => null,
    };

String serialTypeToApi(SerialType type) => switch (type) {
      SerialType.imei => 'imei',
      SerialType.imeiDual => 'imei_dual',
      SerialType.serial => 'serial',
    };

String serialTypeLabel(SerialType type) => switch (type) {
      SerialType.imei => 'IMEI',
      SerialType.imeiDual => 'IMEI ganda (dual SIM)',
      SerialType.serial => 'Nomor seri',
    };

class ProductVariant {
  final int id;
  final int productId;
  final String sku;
  final String? barcode;
  final String? name;
  final Map<String, dynamic>? attributes;
  final double basePrice;
  final double? minPrice;
  final bool isActive;

  // Present when the list was requested for a location.
  final int? onHand;
  final double? sellPrice;
  final double? locationPrice;
  final double? avgCost;
  final int? reorderLevel;

  const ProductVariant({
    required this.id,
    required this.productId,
    required this.sku,
    this.barcode,
    this.name,
    this.attributes,
    required this.basePrice,
    this.minPrice,
    this.isActive = true,
    this.onHand,
    this.sellPrice,
    this.locationPrice,
    this.avgCost,
    this.reorderLevel,
  });

  factory ProductVariant.fromJson(Map<String, dynamic> json) => ProductVariant(
        id: _toInt(json['id']),
        productId: _toInt(json['product_id']),
        sku: json['sku']?.toString() ?? '',
        barcode: json['barcode'] as String?,
        name: json['name'] as String?,
        attributes: json['attributes'] is Map ? Map<String, dynamic>.from(json['attributes'] as Map) : null,
        basePrice: _toDouble(json['base_price']),
        minPrice: _toNullableDouble(json['min_price']),
        isActive: json['is_active'] != false,
        onHand: _toNullableInt(json['on_hand']),
        sellPrice: _toNullableDouble(json['sell_price']),
        locationPrice: _toNullableDouble(json['location_price']),
        avgCost: _toNullableDouble(json['avg_cost']),
        reorderLevel: _toNullableInt(json['reorder_level']),
      );

  /// Effective price at the requested location, or the base price.
  double get price => sellPrice ?? basePrice;

  bool get isOutOfStock => (onHand ?? 0) <= 0;
  bool get isLowStock => !isOutOfStock && (onHand ?? 0) <= (reorderLevel ?? 5);
}

/// Stock of one variant at one location (from GET /api/catalog/products/:id).
class LocationStock {
  final int locationId;
  final String? locationCode;
  final String locationName;
  final String locationType;
  final int variantId;
  final int onHand;
  final double sellPrice;
  final double? locationPrice;
  final double? avgCost;

  const LocationStock({
    required this.locationId,
    this.locationCode,
    required this.locationName,
    required this.locationType,
    required this.variantId,
    required this.onHand,
    required this.sellPrice,
    this.locationPrice,
    this.avgCost,
  });

  factory LocationStock.fromJson(Map<String, dynamic> json) => LocationStock(
        locationId: _toInt(json['location_id']),
        locationCode: json['location_code'] as String?,
        locationName: json['location_name']?.toString() ?? '',
        locationType: json['location_type']?.toString() ?? 'branch',
        variantId: _toInt(json['variant_id']),
        onHand: _toInt(json['on_hand']),
        sellPrice: _toDouble(json['sell_price']),
        locationPrice: _toNullableDouble(json['location_price']),
        avgCost: _toNullableDouble(json['avg_cost']),
      );
}

class CatalogProduct {
  final int id;
  final String name;
  final String? description;
  final int? categoryId;
  final String? categoryName;
  final int? brandId;
  final String? brandName;
  final String kind; // 'goods' | 'service' | 'digital'
  final bool isSerialized;
  final SerialType? serialType;
  final int warrantyMonths;
  final int? taxRateId;
  final String? image;
  final bool isActive;
  final List<ProductVariant> variants;
  final List<LocationStock> stock;

  const CatalogProduct({
    required this.id,
    required this.name,
    this.description,
    this.categoryId,
    this.categoryName,
    this.brandId,
    this.brandName,
    this.kind = 'goods',
    this.isSerialized = false,
    this.serialType,
    this.warrantyMonths = 0,
    this.taxRateId,
    this.image,
    this.isActive = true,
    this.variants = const [],
    this.stock = const [],
  });

  factory CatalogProduct.fromJson(Map<String, dynamic> json) => CatalogProduct(
        id: _toInt(json['id']),
        name: json['name']?.toString() ?? '',
        description: json['description'] as String?,
        categoryId: _toNullableInt(json['category_id']),
        categoryName: json['category_name'] as String?,
        brandId: _toNullableInt(json['brand_id']),
        brandName: json['brand_name'] as String?,
        kind: json['kind']?.toString() ?? 'goods',
        isSerialized: json['is_serialized'] == true,
        serialType: serialTypeFromApi(json['serial_type'] as String?),
        warrantyMonths: _toInt(json['warranty_months']),
        taxRateId: _toNullableInt(json['tax_rate_id']),
        image: json['image'] as String?,
        isActive: json['is_active'] != false,
        variants: ((json['variants'] as List?) ?? const [])
            .map((v) => ProductVariant.fromJson(Map<String, dynamic>.from(v as Map)))
            .toList(),
        stock: ((json['stock'] as List?) ?? const [])
            .map((s) => LocationStock.fromJson(Map<String, dynamic>.from(s as Map)))
            .toList(),
      );

  bool get hasStock => kind == 'goods';

  /// Total on-hand at the location the list was requested for.
  int get onHand => variants.fold(0, (sum, v) => sum + (v.onHand ?? 0));

  bool get isOutOfStock => hasStock && onHand <= 0;
  bool get isLowStock => hasStock && !isOutOfStock && variants.any((v) => v.isLowStock);

  String variantLabel(ProductVariant v) => v.name == null || v.name!.isEmpty ? name : '$name ${v.name}';

  ({double min, double max}) get priceRange {
    if (variants.isEmpty) return (min: 0, max: 0);
    final prices = variants.map((v) => v.price);
    return (min: prices.reduce((a, b) => a < b ? a : b), max: prices.reduce((a, b) => a > b ? a : b));
  }
}

class ProductUnit {
  final String id;
  final int variantId;
  final String name;
  final String? sku;
  final int? locationId;
  final String? locationCode;
  final String? locationName;
  final String? imei1;
  final String? imei2;
  final String? serialNumber;
  final String status;
  final String conditionGrade;
  final double? unitCost;
  final double sellPrice;
  final String? notes;
  final DateTime? createdAt;

  const ProductUnit({
    required this.id,
    required this.variantId,
    required this.name,
    this.sku,
    this.locationId,
    this.locationCode,
    this.locationName,
    this.imei1,
    this.imei2,
    this.serialNumber,
    required this.status,
    required this.conditionGrade,
    this.unitCost,
    required this.sellPrice,
    this.notes,
    this.createdAt,
  });

  factory ProductUnit.fromJson(Map<String, dynamic> json) => ProductUnit(
        id: json['id'].toString(),
        variantId: _toInt(json['variant_id']),
        name: json['name']?.toString() ?? '',
        sku: json['sku'] as String?,
        locationId: _toNullableInt(json['location_id']),
        locationCode: json['location_code'] as String?,
        locationName: json['location_name'] as String?,
        imei1: json['imei1'] as String?,
        imei2: json['imei2'] as String?,
        serialNumber: json['serial_number'] as String?,
        status: json['status']?.toString() ?? 'in_stock',
        conditionGrade: json['condition_grade']?.toString() ?? 'new',
        unitCost: _toNullableDouble(json['unit_cost']),
        sellPrice: _toDouble(json['sell_price']),
        notes: json['notes'] as String?,
        createdAt: _toDate(json['created_at']),
      );

  /// The best identifier to show: IMEI 1, else serial, else a placeholder.
  String get identifier => imei1 ?? serialNumber ?? 'Belum ada IMEI/serial';

  bool get hasIdentifier => imei1 != null || serialNumber != null;
}

String unitStatusLabel(String status) => switch (status) {
      'in_stock' => 'Tersedia',
      'in_transit' => 'Dalam pengiriman',
      'reserved' => 'Dipesan',
      'sold' => 'Terjual',
      'returned' => 'Diretur',
      'in_service' => 'Servis',
      'defective' => 'Rusak',
      'written_off' => 'Dihapus',
      _ => status,
    };

String conditionLabel(String grade) => grade == 'new' ? 'Baru' : 'Bekas $grade';

class StockMovement {
  final String id;
  final int variantId;
  final String name;
  final String? imei1;
  final String? serialNumber;
  final int qtyChange;
  final double? unitCost;
  final String reason;
  final String? refType;
  final String? refId;
  final String? note;
  final String? userName;
  final DateTime? createdAt;

  const StockMovement({
    required this.id,
    required this.variantId,
    required this.name,
    this.imei1,
    this.serialNumber,
    required this.qtyChange,
    this.unitCost,
    required this.reason,
    this.refType,
    this.refId,
    this.note,
    this.userName,
    this.createdAt,
  });

  factory StockMovement.fromJson(Map<String, dynamic> json) => StockMovement(
        id: json['id'].toString(),
        variantId: _toInt(json['variant_id']),
        name: json['name']?.toString() ?? '',
        imei1: json['imei1'] as String?,
        serialNumber: json['serial_number'] as String?,
        qtyChange: _toInt(json['qty_change']),
        unitCost: _toNullableDouble(json['unit_cost']),
        reason: json['reason']?.toString() ?? '',
        refType: json['ref_type'] as String?,
        refId: json['ref_id'] as String?,
        note: json['note'] as String?,
        userName: json['user_name'] as String?,
        createdAt: _toDate(json['created_at']),
      );
}

String movementReasonLabel(String reason) => switch (reason) {
      'purchase' => 'Pembelian',
      'purchase_return' => 'Retur pembelian',
      'sale' => 'Penjualan',
      'sale_return' => 'Retur penjualan',
      'transfer_out' => 'Transfer keluar',
      'transfer_in' => 'Transfer masuk',
      'adjustment' => 'Penyesuaian',
      'opname' => 'Stok opname',
      'trade_in' => 'Tukar tambah',
      'service_part' => 'Sparepart servis',
      'write_off' => 'Penghapusan',
      _ => reason,
    };
