import 'dart:developer' as dev;

import 'access.dart';

class User {
  final int id;
  final String name;
  final String username;

  /// Per-location roles and permissions from login (refreshed by accessProvider). Stored with the
  /// user so the app knows what the user may do while offline.
  final UserAccess access;
  final DateTime? lastActiveAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const User({
    required this.id,
    required this.name,
    required this.username,
    this.access = UserAccess.empty,
    this.lastActiveAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    try {
      return User(
        id: _parseInt(json['id']),
        name: _parseString(json['name']) ?? 'Unknown',
        username: _parseString(json['username']) ?? 'unknown',
        access: json['access'] is Map
            ? UserAccess.fromJson(Map<String, dynamic>.from(json['access'] as Map))
            : UserAccess.empty,
        lastActiveAt: _parseDateTime(json['last_active_at'] ?? json['lastActiveAt']),
        createdAt: _parseDateTime(json['created_at'] ?? json['createdAt']) ?? DateTime.now(),
        updatedAt: _parseDateTime(json['updated_at'] ?? json['updatedAt']) ?? DateTime.now(),
      );
    } catch (e) {
      dev.log('Error parsing User from JSON: $e');
      dev.log('JSON data: $json');
      rethrow;
    }
  }

  // Helper methods for safe parsing
  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static String? _parseString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value.isEmpty ? null : value;
    return value.toString();
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (e) {
        dev.log('Error parsing DateTime: $value, error: $e');
        return null;
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'username': username,
      'access': access.toJson(),
      'last_active_at': lastActiveAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  User copyWith({
    int? id,
    String? name,
    String? username,
    UserAccess? access,
    DateTime? lastActiveAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      username: username ?? this.username,
      access: access ?? this.access,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get isOwner => access.isOwner;

  /// The location the user normally works at (see [UserAccess.defaultLocationId]).
  int? get defaultLocationId => access.defaultLocationId;
}
