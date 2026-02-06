import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../../core/constants/app_constants.dart';

class UserManagementState {
  final List<Map<String, dynamic>> users;
  final bool isLoading;
  final String? error;
  final int currentPage;
  final int totalPages;
  final String? searchQuery;
  final String? roleFilter;
  final String? branchFilter;

  const UserManagementState({
    this.users = const [],
    this.isLoading = false,
    this.error,
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
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      searchQuery: searchQuery ?? this.searchQuery,
      roleFilter: roleFilter ?? this.roleFilter,
      branchFilter: branchFilter ?? this.branchFilter,
    );
  }
}

class UserManagementNotifier extends StateNotifier<UserManagementState> {
  UserManagementNotifier() : super(const UserManagementState());

  final _dio = Dio(BaseOptions(
    baseUrl: AppConstants.baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  Future<void> loadUsers({
    int page = 1,
    int limit = 10,
  }) async {
    try {
      state = state.copyWith(isLoading: true, error: null);

      final queryParams = <String, dynamic>{
        'page': page,
        'limit': limit,
      };

      if (state.searchQuery != null && state.searchQuery!.isNotEmpty) {
        queryParams['search'] = state.searchQuery;
      }

      if (state.roleFilter != null) {
        queryParams['role'] = state.roleFilter;
      }

      if (state.branchFilter != null) {
        queryParams['branch_id'] = state.branchFilter;
      }

      final response = await _dio.get(
        '/api/users',
        queryParameters: queryParams,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final users = List<Map<String, dynamic>>.from(data['users'] ?? []);
        final pagination = data['pagination'] ?? {};

        state = state.copyWith(
          users: users,
          isLoading: false,
          currentPage: pagination['page'] ?? 1,
          totalPages: pagination['totalPages'] ?? 1,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          error: 'Failed to load users',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: _getErrorMessage(e),
      );
    }
  }

  Future<void> createUser(Map<String, dynamic> userData) async {
    try {
      final response = await _dio.post(
        '/api/users',
        data: userData,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode != 201) {
        throw Exception(response.data['error'] ?? 'Failed to create user');
      }

      // Reload users after creation
      await loadUsers();
    } catch (e) {
      throw Exception(_getErrorMessage(e));
    }
  }

  Future<void> updateUser(int userId, Map<String, dynamic> userData) async {
    try {
      final response = await _dio.put(
        '/api/users/$userId',
        data: userData,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode != 200) {
        throw Exception(response.data['error'] ?? 'Failed to update user');
      }

      // Reload users after update
      await loadUsers();
    } catch (e) {
      throw Exception(_getErrorMessage(e));
    }
  }

  Future<void> deleteUser(int userId) async {
    try {
      final response = await _dio.delete(
        '/api/users/$userId',
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode != 200) {
        throw Exception(response.data['error'] ?? 'Failed to delete user');
      }

      // Reload users after deletion
      await loadUsers();
    } catch (e) {
      throw Exception(_getErrorMessage(e));
    }
  }

  void searchUsers(String query) {
    state = state.copyWith(searchQuery: query);
    loadUsers();
  }

  void filterUsers({String? role, String? branchId}) {
    state = state.copyWith(
      roleFilter: role,
      branchFilter: branchId,
    );
    loadUsers();
  }

  void clearFilters() {
    state = state.copyWith(
      searchQuery: null,
      roleFilter: null,
      branchFilter: null,
    );
    loadUsers();
  }

  String _getErrorMessage(dynamic error) {
    if (error is DioException) {
      if (error.response?.data != null && error.response?.data['error'] != null) {
        return error.response!.data['error'];
      }
      
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Connection timeout. Please check your internet connection.';
        case DioExceptionType.badResponse:
          return 'Server error. Please try again later.';
        case DioExceptionType.cancel:
          return 'Request was cancelled.';
        case DioExceptionType.unknown:
          return 'Network error. Please check your connection.';
        default:
          return 'An unexpected error occurred.';
      }
    }
    return error.toString();
  }
}

final userManagementProvider = StateNotifierProvider<UserManagementNotifier, UserManagementState>(
  (ref) => UserManagementNotifier(),
);