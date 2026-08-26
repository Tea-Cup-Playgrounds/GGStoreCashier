class Branch {
  final int id;
  final String name;
  final String? address;
  final String? phone;
  final double targetPendapatan;

  const Branch({
    required this.id,
    required this.name,
    this.address,
    this.phone,
    this.targetPendapatan = 0,
  });

  factory Branch.fromJson(Map<String, dynamic> json) {
    double parseD(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0;
    }

    return Branch(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? 0,
      name: json['name']?.toString() ?? '',
      address: json['address']?.toString(),
      phone: json['phone']?.toString(),
      targetPendapatan: parseD(json['target_pendapatan']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'address': address,
        'phone': phone,
        'target_pendapatan': targetPendapatan,
      };

  Branch copyWith({
    String? name,
    String? address,
    String? phone,
    double? targetPendapatan,
  }) =>
      Branch(
        id: id,
        name: name ?? this.name,
        address: address ?? this.address,
        phone: phone ?? this.phone,
        targetPendapatan: targetPendapatan ?? this.targetPendapatan,
      );
}
