import 'product.dart';

class CartItem {
  final String id;
  final Product product;
  final int quantity;
  final double price;

  /// IMEI units picked for a serialized product (quantity == unitIds.length).
  final List<String> unitIds;

  /// What the line is for, e.g. the phone number topped up with pulsa.
  final String? note;

  const CartItem({
    required this.id,
    required this.product,
    required this.quantity,
    required this.price,
    this.unitIds = const [],
    this.note,
  });

  factory CartItem.fromProduct(Product product, {int quantity = 1}) {
    return CartItem(
      id: product.id,
      product: product,
      quantity: quantity,
      price: product.sellPrice,
    );
  }

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      id: json['id'] as String,
      product: Product.fromJson(json['product'] as Map<String, dynamic>),
      quantity: json['quantity'] as int,
      price: (json['price'] as num).toDouble(),
      unitIds: ((json['unit_ids'] as List?) ?? const []).map((e) => e.toString()).toList(),
      note: json['note'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product': product.toJson(),
      'quantity': quantity,
      'price': price,
      'unit_ids': unitIds,
      'note': note,
    };
  }

  /// The line as POST /api/sales expects it. Prices of goods come from the catalog on the
  /// server; services / digital items send the price typed at the counter.
  Map<String, dynamic> toSaleLine() {
    return {
      'variant_id': int.parse(product.id),
      if (product.isSerialized) 'unit_ids': unitIds else 'qty': quantity,
      if (!product.hasStock) 'unit_price': price,
      if (note != null && note!.isNotEmpty) 'description': note,
    };
  }

  CartItem copyWith({
    String? id,
    Product? product,
    int? quantity,
    double? price,
    List<String>? unitIds,
    String? note,
  }) {
    return CartItem(
      id: id ?? this.id,
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      price: price ?? this.price,
      unitIds: unitIds ?? this.unitIds,
      note: note ?? this.note,
    );
  }

  double get subtotal => price * quantity;

  CartItem incrementQuantity() => copyWith(quantity: quantity + 1);
  CartItem decrementQuantity() => copyWith(quantity: quantity - 1);
}
