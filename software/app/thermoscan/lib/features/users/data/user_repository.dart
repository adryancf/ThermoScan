import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thermoscan/core/network/api_client.dart';
import 'package:thermoscan/core/network/api_exception.dart';
import 'package:thermoscan/features/users/domain/user_models.dart';

final userRepositoryProvider = Provider<UserRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return UserRepository(dio: dio);
});

class UserRepository {
  const UserRepository({required this.dio});

  final Dio dio;

  Future<List<CompanyUser>> listUsers({
    String? role,
    int limit = 100,
    int offset = 0,
  }) async {
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/users',
        queryParameters: {
          if (role != null && role.isNotEmpty) 'role': role,
          'limit': limit,
          'offset': offset,
        },
      );
      final rawList = response.data?['users'] as List<dynamic>? ?? const [];
      return rawList
          .whereType<Map<String, dynamic>>()
          .map(CompanyUser.fromJson)
          .toList();
    } on DioException catch (err) {
      throw ApiException.fromDioException(err);
    }
  }

  Future<CompanyUserDetails> getUserDetails(String userId) async {
    try {
      final response = await dio.get<Map<String, dynamic>>('/users/$userId');
      return CompanyUserDetails.fromJson(response.data ?? const {});
    } on DioException catch (err) {
      throw ApiException.fromDioException(err);
    }
  }

  Future<CreateCompanyUserResult> createUser({
    required String name,
    required String email,
    required String role,
    List<String> managerIds = const [],
  }) async {
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '/users',
        data: {
          'name': name.trim(),
          'email': email.trim(),
          'role': role,
          if (role == 'technician') 'manager_ids': managerIds,
        },
      );
      return CreateCompanyUserResult.fromJson(response.data ?? const {});
    } on DioException catch (err) {
      throw ApiException.fromDioException(err);
    }
  }

  Future<CompanyUser> setUserStatus({
    required String userId,
    required bool isActive,
  }) async {
    try {
      final response = await dio.patch<Map<String, dynamic>>(
        '/users/$userId/status',
        data: {'is_active': isActive},
      );
      return CompanyUser.fromJson(response.data ?? const {});
    } on DioException catch (err) {
      throw ApiException.fromDioException(err);
    }
  }

  Future<ResetCompanyUserPasswordResult> resetUserPassword({
    required String userId,
  }) async {
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '/users/$userId/reset-password',
      );
      return ResetCompanyUserPasswordResult.fromJson(
        response.data ?? const {},
      );
    } on DioException catch (err) {
      throw ApiException.fromDioException(err);
    }
  }

  Future<List<AssignedManagerSummary>> setTechnicianManagers({
    required String technicianId,
    required List<String> managerIds,
  }) async {
    try {
      final response = await dio.put<Map<String, dynamic>>(
        '/users/$technicianId/managers',
        data: {'manager_ids': managerIds},
      );
      final rawList = response.data?['managers'] as List<dynamic>? ?? const [];
      return rawList
          .whereType<Map<String, dynamic>>()
          .map(AssignedManagerSummary.fromJson)
          .toList();
    } on DioException catch (err) {
      throw ApiException.fromDioException(err);
    }
  }

  Future<void> deleteUser({required String userId}) async {
    try {
      await dio.delete('/users/$userId');
    } on DioException catch (err) {
      throw ApiException.fromDioException(err);
    }
  }
}
