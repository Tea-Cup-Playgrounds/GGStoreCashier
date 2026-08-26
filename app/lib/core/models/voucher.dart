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
  final int? maxUses; // null = unlimited
  final int usedCount;

  // Computed from server — set when fetched via the enriched endpoints
  final bool? isAvailable;
  final String? unavailableReason;

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
    this.maxUses,
    this.usedCount = 0,
    this.isAvailable,
    this.unavailableReason,
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
        maxUses: _nullInt(j['max_uses']),
        usedCount: _int(j['used_count'] ?? 0),
        isAvailable: j['is_available'] == null ? null : (j['is_available'] == true || j['is_available'] == 1),
        unavailableReason: j['unavailable_reason']?.toString(),
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
        'max_uses': maxUses,
        'used_count': usedCount,
      };

  /// Whether this voucher can be applied right now (client-side check).
  /// Mirrors the server logic; `isAvailable` from the server is preferred when present.
  bool get canUse {
    if (isAvailable != null) return isAvailable!;
    if (!isActive) return false;
    final today = DateTime.now();
    if (validFrom != null) {
      final from = DateTime.tryParse(validFrom!);
      if (from != null && today.isBefore(from)) return false;
    }
    if (validTo != null) {
      final to = DateTime.tryParse(validTo!);
      if (to != null && today.isAfter(to.add(const Duration(days: 1)))) return false;
    }
    if (maxUses != null && usedCount >= maxUses!) return false;
    return true;
  }

  /// Human-readable reason the voucher cannot be used (client-side fallback).
  String? get whyUnavailable {
    if (unavailableReason != null) return unavailableReason;
    if (canUse) return null;
    if (!isActive) return 'Voucher tidak aktif';
    final today = DateTime.now();
    if (validFrom != null) {
      final from = DateTime.tryParse(validFrom!);
      if (from != null && today.isBefore(from)) {
        return 'Belum berlaku (mulai ${_fmtDate(from)})';
      }
    }
    if (validTo != null) {
      final to = DateTime.tryParse(validTo!);
      if (to != null && today.isAfter(to.add(const Duration(days: 1)))) {
        return 'Sudah kadaluarsa (${_fmtDate(to)})';
      }
    }
    if (maxUses != null && usedCount >= maxUses!) {
      return 'Batas penggunaan habis ($usedCount/$maxUses)';
    }
    return 'Tidak dapat digunakan';
  }

  /// Human-readable discount label, e.g. "20% OFF" or "Rp 10.000 OFF"
  String get discountLabel => discountType == 'percent'
      ? '${discountValue.toStringAsFixed(0)}% OFF'
      : 'Rp ${discountValue.toStringAsFixed(0)} OFF';

  /// Usage progress string, e.g. "12/50 kali" or "Tak terbatas"
  String get usageLabel {
    if (maxUses == null) return 'Tak terbatas';
    return '$usedCount/$maxUses kali';
  }

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

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
