class Voucher {
  final int id;
  final String code;
  final String? description;
  final String? targetType; // 'categories' | 'product' | null
  final int? targetId;
  final String discountType; // 'percent' | 'fixed'
  final double discountValue;
  final String? validFrom;
  final String? validTo;
  final bool isActive;

  const Voucher({
    required this.id,
    required this.code,
    this.description,
    this.targetType,
    this.targetId,
    required this.discountType,
    required this.discountValue,
    this.validFrom,
    this.validTo,
    required this.isActive,
  });

  factory Voucher.fromJson(Map<String, dynamic> j) => Voucher(
        id: _int(j['id']),
        code: j['code']?.toString() ?? '',
        description: j['description']?.toString(),
        targetType: j['target_type']?.toString(),
        targetId: _nullInt(j['target_id']),
        discountType: j['discount_type']?.toString() ?? 'percent',
        discountValue: _double(j['discount_value']),
        validFrom: j['valid_from']?.toString(),
        validTo: j['valid_to']?.toString(),
        isActive: j['is_active'] == 1 || j['is_active'] == true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'description': description,
        'target_type': targetType,
        'target_id': targetId,
        'discount_type': discountType,
        'discount_value': discountValue,
        'valid_from': validFrom,
        'valid_to': validTo,
        'is_active': isActive ? 1 : 0,
      };

  /// Human-readable discount label, e.g. "20% OFF" or "Rp 10.000 OFF"
  String get discountLabel =>
      discountType == 'percent' ? '${discountValue.toStringAsFixed(0)}% OFF' : 'Rp ${discountValue.toStringAsFixed(0)} OFF';

  static int _int(dynamic v) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static int? _nullInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }

  static double _double(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }
}
