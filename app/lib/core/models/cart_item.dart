import 'product.dart';

class CartItem {
  final String id;
  final Product product;
  final int quantity;
  final double price;

  const CartItem({
    required this.id,
    required this.product,
    required this.quantity,
    required this.price,
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
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product': product.toJson(),
      'quantity': quantity,
      'price': price,
    };
  }

  CartItem copyWith({
    String? id,
    Product? product,
    int? quantity,
    double? price,
  }) {
    return CartItem(
      id: id ?? this.id,
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      price: price ?? this.price,
    );
  }

  double get subtotal => price * quantity;
  
  CartItem incrementQuantity() => copyWith(quantity: quantity + 1);
  CartItem decrementQuantity() => copyWith(quantity: quantity - 1);
}