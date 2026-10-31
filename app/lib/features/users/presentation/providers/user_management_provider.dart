import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/models/catalog.dart';
import '../../../../core/services/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/cache_manager.dart';
import '../../../../core/services/catalog_service.dart';
import '../../../../core/services/connectivity_monitor.dart';
import '../../../../core/services/pending_operations_queue.dart';
import '../../../../core/theme/app_theme.dart';

/// A role from /api/access/roles, as offered in the user form.
class AssignableRole {
  final int id;
  final String code;
  final String name;

  const AssignableRole({required this.id, required this.code, required this.name});

  bool get isOwner => code == 'owner';
}

/// Roles that can be assigned (the API still checks the acting user may grant each one).
final assignableRolesProvider = FutureProvider<List<AssignableRole>>((ref) async {
  final body = await ApiClient.request('GET', '/api/access/roles');
  return ApiClient.list(
    body,
    'roles',
    (r) => AssignableRole(id: r['id'] as int, code: r['code']?.toString() ?? '', name: r['name']?.toString() ?? ''),
  );
});

/// Locations the acting user can assign people to (their own; every location for owners).
final assignableLocationsProvider = FutureProvider<List<Location>>((ref) => CatalogService.getLocations());

/// Badge colour for a role code.
Color roleColor(String? code) {
  switch (code) {
    case 'owner':
      return AppTheme.gold;
    case 'branch_manager':
      return AppTheme.success;
    default:
      return Colors.grey;
  }
}

class UserManagementState {
  final List<Map<String, dynamic>> users;
  final bool isLoading;
  final String? error;
  final bool isStale;
  final int currentPage;
  final int totalPages;
  final String? searchQuery;
  final int? roleFilter;
  final int? locationFilter;

  const UserManagementState({
    this.users = const [],
    this.isLoading = false,
    this.error,
    this.isStale = false,
    this.currentPage = 1,
    this.totalPages = 1,
    this.searchQuery,
    this.roleFilter,
    this.locationFilter,
  });

  UserManagementState copyWith({
    List<Map<String, dynamic>>? users,
    bool? isLoading,
    String? error,
    bool? isStale,
    int? currentPage,
    int? totalPages,
    String? searchQuery,
    int? Function()? roleFilter,
    int? Function()? locationFilter,
  }) {
    return UserManagementState(
      users: users ?? this.users,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      isStale: isStale ?? this.isStale,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      searchQuery: searchQuery ?? this.searchQuery,
      roleFilter: roleFilter != null ? roleFilter() : this.roleFilter,
      locationFilter: locationFilter != null ? locationFilter() : this.locationFilter,
    );
  }
}

class UserManagementNotifier extends StateNotifier<UserManagementState> {
  UserManagementNotifier() : super(const UserManagementState()) {
    _setupDio();
  }

  final _dio = Dio(BaseOptions(
    baseUrl: AppConstants.baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {'ngrok-skip-browser-warning': 'true'},
  ));

  void _setupDio() {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await AuthService.getToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
    ));
  }

  bool get _isOffline =>
      ConnectivityMonitor.instance.currentStatus == ConnectivityStatus.offline;

  /// Adds display fields derived from `assignments`: role_label, role_code (the first role, for the
  /// badge colour) and branch_name (assigned locations).
  static Map<String, dynamic> withLabels(Map<String, dynamic> user) {
    final assignments = ((user['assignments'] as List?) ?? const [])
        .map((a) => Map<String, dynamic>.from(a as Map))
        .toList();
    final roles = assignments.map((a) => a['role_name']?.toString() ?? '').where((n) => n.isNotEmpty).toSet();
    final places = assignments.map((a) => a['location_id'] == null ? 'Semua lokasi' : a['location_name']?.toString() ?? '').toSet();
    return {
      ...user,
      'assignments': assignments,
      'role_label': roles.isEmpty ? 'Tanpa akses' : roles.join(' · '),
      'role_code': assignments.isEmpty ? null : assignments.first['role_code'],
      'branch_name': places.isEmpty ? 'Tidak ada lokasi' : places.join(', '),
    };
  }

  Future<void> loadUsers({int page = 1, int limit = 50}) async {
    // Cached per signed-in user: what a manager may see differs from what an owner sees.
    final cacheKey = 'users:list:u${(await AuthService.getCurrentUser())?.id}';

    final noFilters = (state.searchQuery == null || state.searchQuery!.isEmpty) &&
        state.roleFilter == null &&
        state.locationFilter == null;

    try {
      state = state.copyWith(isLoading: true, error: null);

      final queryParams = <String, dynamic>{'page': page, 'limit': limit};
      if (state.searchQuery?.isNotEmpty == true) queryParams['search'] = state.searchQuery;
      if (state.roleFilter != null) queryParams['role_id'] = state.roleFilter;
      if (state.locationFilter != null) queryParams['location_id'] = state.locationFilter;

      final response = await _dio.get('/api/users', queryParameters: queryParams);
      final data = response.data;
      final users = List<Map<String, dynamic>>.from(data['users'] ?? []).map(withLabels).toList();
      final pagination = data['pagination'] ?? {};

      if (noFilters) await CacheManager.put(cacheKey, users);

      state = state.copyWith(
        users: users,
        isLoading: false,
        isStale: false,
        currentPage: pagination['page'] ?? 1,
        totalPages: pagination['totalPages'] ?? 1,
      );
    } catch (e) {
      if (e is DioException && e.response == null && noFilters) {
        final entry = CacheManager.get(cacheKey);
        if (entry != null) {
          final users = (entry.data as List).map((e) => withLabels(Map<String, dynamic>.from(e as Map))).toList();
          state = state.copyWith(users: users, isLoading: false, isStale: true);
          return;
        }
        if (_isOffline) {
          state = state.copyWith(isLoading: false, error: 'Kamu sedang offline dan belum ada data tersimpan.');
          return;
        }
      }
      state = state.copyWith(isLoading: false, error: _errorMessage(e));
    }
  }

  /// Creates a user. Body: name, username, password, assignments [{location_id, role_id}].
  /// When offline, queues the operation and shows the user as pending.
  Future<void> createUser(Map<String, dynamic> userData) async {
    if (_isOffline) {
      final op = PendingOperation()
        ..id = const Uuid().v4()
        ..method = 'POST'
        ..path = '/api/users'
        ..body = userData
        ..createdAt = DateTime.now()
        ..retryCount = 0
        ..status = 'pending'
        ..description = 'Tambah pengguna';
      await PendingOperationsQueue.enqueue(op);

      // Optimistic local entry (without the password).
      final optimistic = withLabels({
        'id': op.id,
        'name': userData['name'],
        'username': userData['username'],
        'assignments': const [],
        '_pending': true,
      });
      state = state.copyWith(users: [...state.users, optimistic]);
      return;
    }

    try {
      await _dio.post('/api/users', data: userData);
    } on DioException catch (e) {
      throw Exception(_errorMessage(e));
    }
    await loadUsers();
  }

  /// Updates a user (any of name, username, password, is_active, assignments).
  Future<void> updateUser(int userId, Map<String, dynamic> userData) async {
    if (_isOffline) {
      final op = PendingOperation()
        ..id = const Uuid().v4()
        ..method = 'PUT'
        ..path = '/api/users/$userId'
        ..body = userData
        ..createdAt = DateTime.now()
        ..retryCount = 0
        ..status = 'pending'
        ..description = 'Perubahan pengguna';
      await PendingOperationsQueue.enqueue(op);

      final updated = state.users.map((u) {
        if (u['id'].toString() == userId.toString()) {
          return {...u, if (userData['name'] != null) 'name': userData['name'], if (userData['username'] != null) 'username': userData['username'], '_pending': true};
        }
        return u;
      }).toList();
      state = state.copyWith(users: updated);
      return;
    }

    try {
      await _dio.put('/api/users/$userId', data: userData);
    } on DioException catch (e) {
      throw Exception(_errorMessage(e));
    }
    await loadUsers();
  }

  /// Deletes a user and returns the API's message: users with history are deactivated instead, and a
  /// manager only removes the assignments at their own locations.
  Future<String> deleteUser(int userId) async {
    if (_isOffline) {
      final op = PendingOperation()
        ..id = const Uuid().v4()
        ..method = 'DELETE'
        ..path = '/api/users/$userId'
        ..body = {}
        ..createdAt = DateTime.now()
        ..retryCount = 0
        ..status = 'pending'
        ..description = 'Hapus pengguna';
      await PendingOperationsQueue.enqueue(op);

      state = state.copyWith(users: state.users.where((u) => u['id'].toString() != userId.toString()).toList());
      return 'Penghapusan akan dikirim saat online';
    }

    try {
      final response = await _dio.delete('/api/users/$userId');
      await loadUsers();
      return response.data['message']?.toString() ?? 'Pengguna berhasil dihapus';
    } on DioException catch (e) {
      throw Exception(_errorMessage(e));
    }
  }

  void searchUsers(String query) {
    state = state.copyWith(searchQuery: query);
    loadUsers();
  }

  void filterUsers({int? roleId, int? locationId}) {
    state = state.copyWith(roleFilter: () => roleId, locationFilter: () => locationId);
    loadUsers();
  }

  String _errorMessage(dynamic error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['error'] != null) return data['error'].toString();
      if (error.response?.statusCode == 401) return 'Sesi berakhir, silakan login kembali.';
      if (error.response?.statusCode == 403) return 'Anda tidak memiliki izin untuk tindakan ini.';
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Koneksi timeout. Periksa koneksi internet Anda.';
        case DioExceptionType.connectionError:
          return _isOffline
              ? 'Kamu sedang offline dan belum ada data tersimpan.'
              : 'Tidak dapat terhubung ke server.';
        default:
          return 'Terjadi kesalahan yang tidak terduga.';
      }
    }
    return error.toString();
  }
}

final userManagementProvider =
    StateNotifierProvider<UserManagementNotifier, UserManagementState>(
  (ref) => UserManagementNotifier(),
);
