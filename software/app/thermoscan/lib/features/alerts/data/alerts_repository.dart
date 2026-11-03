import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thermoscan/core/network/api_client.dart';
import 'package:thermoscan/core/network/api_exception.dart';
import 'package:thermoscan/features/alerts/domain/alert_models.dart';

final alertsRepositoryProvider = Provider<AlertsRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return AlertsRepository(dio: dio);
});

class AlertsRepository {
  const AlertsRepository({required this.dio});

  final Dio dio;

  Future<AlertsSummary> listAlerts() async {
    try {
      final response = await dio.get<Map<String, dynamic>>('/alerts');
      return AlertsSummary.fromJson(response.data ?? const {});
    } on DioException catch (err) {
      throw ApiException.fromDioException(err);
    }
  }
}
