/// What the signed-in user may do, per location. Mirrors `Access` in API/src/services/access.js;
/// the server always re-checks, this only decides what the UI offers.
class AccessAssignment {
  /// null = the role applies at every location.
  final int? locationId;
  final String? locationName;
  final String? locationType;
  final int roleId;
  final String? roleCode;
  final String roleName;
  final Set<String> permissions;

  const AccessAssignment({
    required this.locationId,
    this.locationName,
    this.locationType,
    required this.roleId,
    this.roleCode,
    required this.roleName,
    required this.permissions,
  });

  factory AccessAssignment.fromJson(Map<String, dynamic> json) {
    return AccessAssignment(
      locationId: json['locationId'] as int?,
      locationName: json['locationName'] as String?,
      locationType: json['locationType'] as String?,
      roleId: json['roleId'] as int,
      roleCode: json['roleCode'] as String?,
      roleName: json['roleName'] as String? ?? '',
      permissions: ((json['permissions'] as List?) ?? const []).map((p) => p.toString()).toSet(),
    );
  }

  Map<String, dynamic> toJson() => {
        'locationId': locationId,
        'locationName': locationName,
        'locationType': locationType,
        'roleId': roleId,
        'roleCode': roleCode,
        'roleName': roleName,
        'permissions': permissions.toList(),
      };
}

class UserAccess {
  final bool isOwner;
  final List<AccessAssignment> assignments;

  const UserAccess({required this.isOwner, required this.assignments});

  static const empty = UserAccess(isOwner: false, assignments: []);

  factory UserAccess.fromJson(Map<String, dynamic> json) {
    return UserAccess(
      isOwner: json['isOwner'] == true,
      assignments: ((json['assignments'] as List?) ?? const [])
          .map((a) => AccessAssignment.fromJson(Map<String, dynamic>.from(a as Map)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'isOwner': isOwner,
        'assignments': assignments.map((a) => a.toJson()).toList(),
      };

  /// The location the user normally works at: their first branch, else their first location of any
  /// type; null for users who only have global (every-location) assignments.
  int? get defaultLocationId {
    final located = assignments.where((a) => a.locationId != null);
    final branch = located.where((a) => a.locationType == 'branch');
    if (branch.isNotEmpty) return branch.first.locationId;
    return located.isEmpty ? null : located.first.locationId;
  }

  /// Role names for display, e.g. "Branch Manager · Cashier".
  String get roleLabel {
    if (isOwner) return 'Owner';
    final names = assignments.map((a) => a.roleName).toSet();
    return names.isEmpty ? 'Tanpa akses' : names.join(' · ');
  }

  /// With [locationId]: may the user do this there? Without: anywhere?
  bool can(String permission, [int? locationId]) {
    if (isOwner) return true;
    return assignments.any((a) =>
        a.permissions.contains(permission) &&
        (locationId == null || a.locationId == null || a.locationId == locationId));
  }

  /// Location ids where the user holds [permission], or null for "every location".
  Set<int>? locationsFor(String permission) {
    if (isOwner) return null;
    final matching = assignments.where((a) => a.permissions.contains(permission));
    if (matching.any((a) => a.locationId == null)) return null;
    return matching.map((a) => a.locationId!).toSet();
  }

  /// Cost prices are only shown to people who manage stock or read reports there (same rule as the API).
  bool canSeeCost(int locationId) =>
      can('stock.adjust', locationId) ||
      can('reports.view_location', locationId) ||
      can('purchases.manage', locationId) ||
      can('accounting.view', locationId);
}
