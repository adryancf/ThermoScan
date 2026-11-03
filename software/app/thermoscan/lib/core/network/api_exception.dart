import 'package:dio/dio.dart';

class ApiException implements Exception {
  const ApiException({
    required this.message,
    this.code,
    this.statusCode,
  });

  final String message;
  final String? code;
  final int? statusCode;

  factory ApiException.fromDioException(DioException err) {
    final response = err.response;
    final statusCode = response?.statusCode;
    final data = response?.data;

    if (data is Map<String, dynamic>) {
      final rawError = data['error'];
      final rawCode = data['code'] as String?;

      if (rawError is String && rawError.trim().isNotEmpty) {
        return ApiException(
          message: _humanizeError(rawError, rawCode),
          code: rawCode,
          statusCode: statusCode,
        );
      }
      if (rawError is Map<String, dynamic>) {
        final nestedMsg = rawError['message'] as String?;
        final nestedCode = rawError['code'] as String? ?? rawCode;
        if (nestedMsg != null && nestedMsg.trim().isNotEmpty) {
          return ApiException(
            message: _humanizeError(nestedMsg, nestedCode),
            code: nestedCode,
            statusCode: statusCode,
          );
        }
      }
    }

    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.connectionError) {
      return ApiException(
        message:
            'Unable to reach the ThermoScan server. Verify the backend is running.',
        code: 'NETWORK_ERROR',
        statusCode: statusCode,
      );
    }

    return ApiException(
      message: 'An unexpected error occurred. Please try again.',
      code: 'UNKNOWN_ERROR',
      statusCode: statusCode,
    );
  }

  static String _humanizeError(String rawMessage, String? code) {
    switch (code) {
      case 'INVALID_CREDENTIALS':
        return 'Invalid email or password.';
      case 'ACCOUNT_INACTIVE':
        return 'This account is inactive. Contact your company Manager.';
      case 'INVALID_CURRENT_PASSWORD':
        return 'Current password is incorrect.';
      case 'SAME_PASSWORD':
        return 'New password must be different from your current password.';
      case 'WEAK_PASSWORD':
        return 'Password must be at least 8 characters long.';
      case 'EMAIL_CONFLICT':
        return 'This email address is already registered.';
      case 'MAC_CONFLICT':
        return 'A module with this MAC address is already registered.';
      case 'MODULE_MANAGER_REQUIRED':
        return 'At least one active responsible Manager is required.';
      case 'PASSWORD_CHANGE_REQUIRED':
        return 'You must change your temporary password before continuing.';
      case 'FORBIDDEN':
        return 'You do not have permission to perform this action.';
      case 'MODULE_HAS_PENDING_OPERATIONS':
        return 'Module cannot be deleted while physical operations or inspections are scheduled or in progress.';
      case 'MODULE_HAS_HISTORY':
        return 'Installer technicians cannot delete modules with operational history.';
      default:
        // Capitalize first letter if needed
        if (rawMessage.isEmpty) return 'Request failed.';
        final trimmed = rawMessage.trim();
        final capitalized =
            trimmed[0].toUpperCase() + trimmed.substring(1);
        return capitalized.endsWith('.') ? capitalized : '$capitalized.';
    }
  }

  @override
  String toString() => message;
}
