import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/cache_manager.dart';
import '../../../../core/services/connectivity_monitor.dart';
import '../../../../core/services/pending_operations_queue.dart';

class UserManagementState {
  final List<Map<String, dynamic>> users;
  final bool isLoading;
  final String? error;
  final bool isStale;
  final int currentPage;
  final int totalPages;
  final String? searchQuery;
  final String? roleFilter;
  final String? branchFilter;

  const UserManagementState({
    this.users = const [],
    this.isLoading = false,
    this.error,
    this.isStale = false,
    this.currentPage = 1,
    this.totalPages = 1,
    this.searchQuery,
    this.roleFilter,
    this.branchFilter,
  });

  UserManagementState copyWith({
    List<Map<String, dynamic>>? users,
    bool? isLoading,
    String? error,
    bool? isStale,
    int? currentPage,
    int? totalPages,
    String? searchQuery,
    String? roleFilter,
    String? branchFilter,
  }) {
    return UserManagementState(
      users: users ?? this.users,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      isStale: isStale ?? this.isStale,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      searchQuery: searchQuery ?? this.searchQuery,
      roleFilter: roleFilter ?? this.roleFilter,
      branchFilter: branchFilter ?? this.branchFilter,
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

  Future<void> loadUsers({int page = 1, int limit = 10}) async {
    const cacheKey = 'users:list';

    final noFilters = (state.searchQuery == null || state.searchQuery!.isEmpty) &&
        state.roleFilter == null &&
        state.branchFilter == null;

    try {
      state = state.copyWith(isLoading: true, error: null);

      // Cache hit — only when no filters are active
      if (noFilters && CacheManager.isValid(cacheKey)) {
        final entry = CacheManager.get(cacheKey);
        if (entry != null) {
          final users = (entry.data as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          state = state.copyWith(users: users, isLoading: false, isStale: entry.isStale);
          return;
        }
      }

      final queryParams = <String, dynamic>{'page': page, 'limit': limit};
      if (state.searchQuery?.isNotEmpty == true) queryParams['search'] = state.searchQuery;
      if (state.roleFilter != null) queryParams['role'] = state.roleFilter;
      if (state.branchFilter != null) queryParams['branch_id'] = state.branchFilter;

      final response = await _dio.get('/api/users', queryParameters: queryParams);

      if (response.statusCode == 200) {
        final data = response.data;
        final users = List<Map<String, dynamic>>.from(data['users'] ?? []);
        final pagination = data['pagination'] ?? {};

        if (noFilters) {
          await CacheManager.put(cacheKey, users);
        }

        state = state.copyWith(
          users: users,
          isLoading: false,
          isStale: false,
          currentPage: pagination['page'] ?? 1,
          totalPages: pagination['totalPages'] ?? 1,
        );
      } else {
        state = state.copyWith(isLoading: false, error: 'Gagal memuat pengguna');
      }
    } catch (e) {
      if (e is DioException && noFilters) {
        final entry = CacheManager.get(cacheKey);
        if (entry != null) {
          entry.isStale = true;
          await entry.save();
          final users = (entry.data as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          state = state.copyWith(users: users, isLoading: false, isStale: true);
          return;
        }
        // No cache — check if offline and give a friendly message
        if (_isOffline) {
          state = state.copyWith(
            isLoading: false,
            error: 'Kamu sedang offline dan belum ada data tersimpan.',
          );
          return;
        }
      }
      state = state.copyWith(isLoading: false, error: _errorMessage(e));
    }
  }

  /// Creates a user. When offline, queues the operation and adds optimistically to local state.
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

      // Optimistic local update
      final optimistic = Map<String, dynamic>.from(userData)
        ..['id'] = op.id
        ..['_pending'] = true;
      final updated = [...state.users, optimistic];
      state = state.copyWith(users: updated);
      await _updateUsersCache(updated);
      return;
    }

    final response = await _dio.post('/api/users', data: userData);
    if (response.statusCode != 201) {
      throw Exception(response.data['error'] ?? 'Gagal membuat pengguna');
    }
    await CacheManager.invalidate('users:list');
    await loadUsers();
  }

  /// Updates a user. When offline, queues and applies optimistically.
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

      // Optimistic local update
      final updated = state.users.map((u) {
        if (u['id'].toString() == userId.toString()) {
          return {...u, ...userData, '_pending': true};
        }
        return u;
      }).toList();
      state = state.copyWith(users: updated);
      await _updateUsersCache(updated);
      return;
    }

    final response = await _dio.put('/api/users/$userId', data: userData);
    if (response.statusCode != 200) {
      throw Exception(response.data['error'] ?? 'Gagal memperbarui pengguna');
    }
    await CacheManager.invalidate('users:list');
    await loadUsers();
  }

  /// Deletes a user. When offline, queues and removes optimistically.
  Future<void> deleteUser(int userId) async {
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

      // Optimistic local removal
      final updated = state.users
          .where((u) => u['id'].toString() != userId.toString())
          .toList();
      state = state.copyWith(users: updated);
      await _updateUsersCache(updated);
      return;
    }

    final response = await _dio.delete('/api/users/$userId');
    if (response.statusCode != 200) {
      throw Exception(response.data['error'] ?? 'Gagal menghapus pengguna');
    }
    await CacheManager.invalidate('users:list');
    await loadUsers();
  }

  Future<void> _updateUsersCache(List<Map<String, dynamic>> users) async {
    await CacheManager.put('users:list', users);
  }

  void searchUsers(String query) {
    state = state.copyWith(searchQuery: query);
    loadUsers();
  }

  void filterUsers({String? role, String? branchId}) {
    state = state.copyWith(roleFilter: role, branchFilter: branchId);
    loadUsers();
  }

  void clearFilters() {
    state = state.copyWith(searchQuery: null, roleFilter: null, branchFilter: null);
    loadUsers();
  }

  String _errorMessage(dynamic error) {
    if (error is DioException) {
      if (error.response?.data?['error'] != null) return error.response!.data['error'];
      if (error.response?.statusCode == 401) return 'Authentication failed. Please login again.';
      if (error.response?.statusCode == 403) return 'You do not have permission to access this resource.';
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Connection timeout. Please check your internet connection.';
        case DioExceptionType.connectionError:
          return _isOffline
              ? 'Kamu sedang offline dan belum ada data tersimpan.'
              : 'Cannot connect to server. Please check your network.';
        default:
          return 'An unexpected error occurred.';
      }
    }
    return error.toString();
  }
}

final userManagementProvider =
    StateNotifierProvider<UserManagementNotifier, UserManagementState>(
  (ref) => UserManagementNotifier(),
);
