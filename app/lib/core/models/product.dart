class Product {
  final String id;
  final String name;
  final String? barcode;
  final int? categoryId;
  final double costPrice;
  final double sellPrice;
  final int stock;
  final int? branchId;
  final int? supplierId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? image;
  final String? category;

  const Product({
    required this.id,
    required this.name,
    this.barcode,
    this.categoryId,
    required this.costPrice,
    required this.sellPrice,
    required this.stock,
    this.branchId,
    this.supplierId,
    required this.createdAt,
    required this.updatedAt,
    this.image,
    this.category,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    // Helper function to parse price (handles both string and number)
    double parsePrice(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    return Product(
      id: json['id'].toString(),
      name: json['name'] as String,
      barcode: json['barcode'] as String?,
      categoryId: json['category_id'] as int?,
      costPrice: parsePrice(json['cost_price']),
      sellPrice: parsePrice(json['sell_price']),
      stock: json['stock'] as int,
      branchId: json['branch_id'] as int?,
      supplierId: json['supplier_id'] as int?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      image: json['product_image'] as String?,
      category: json['category_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'barcode': barcode,
      'category_id': categoryId,
      'cost_price': costPrice,
      'sell_price': sellPrice,
      'stock': stock,
      'branch_id': branchId,
      'supplier_id': supplierId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'image': image,
      'category': category,
    };
  }

  Product copyWith({
    String? id,
    String? name,
    String? barcode,
    int? categoryId,
    double? costPrice,
    double? sellPrice,
    int? stock,
    int? branchId,
    int? supplierId,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? image,
    String? category,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      barcode: barcode ?? this.barcode,
      categoryId: categoryId ?? this.categoryId,
      costPrice: costPrice ?? this.costPrice,
      sellPrice: sellPrice ?? this.sellPrice,
      stock: stock ?? this.stock,
      branchId: branchId ?? this.branchId,
      supplierId: supplierId ?? this.supplierId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      image: image ?? this.image,
      category: category ?? this.category,
    );
  }

  bool get isLowStock => stock <= 5;
  bool get isOutOfStock => stock <= 0;
  
  double get profitMargin => sellPrice - costPrice;
  double get profitPercentage => (profitMargin / costPrice) * 100;
}