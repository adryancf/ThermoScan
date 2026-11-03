import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thermoscan/core/network/api_client.dart';
import 'package:thermoscan/core/network/api_exception.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';

final moduleRepositoryProvider = Provider<ModuleRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return ModuleRepository(dio: dio);
});

class ModuleRepository {
  const ModuleRepository({required this.dio});

  final Dio dio;

  Future<List<ModuleManagerItem>> listCompanyManagers() async {
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/modules/company-managers',
      );
      final rawList = response.data?['managers'] as List<dynamic>? ?? const [];
      return rawList
          .whereType<Map<String, dynamic>>()
          .map(ModuleManagerItem.fromJson)
          .toList();
    } on DioException catch (err) {
      throw ApiException.fromDioException(err);
    }
  }

  Future<List<ModuleClientItem>> listCompanyClientOptions() async {
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/modules/company-clients',
      );
      final rawList = response.data?['clients'] as List<dynamic>? ?? const [];
      return rawList
          .whereType<Map<String, dynamic>>()
          .map(ModuleClientItem.fromJson)
          .toList();
    } on DioException catch (err) {
      throw ApiException.fromDioException(err);
    }
  }

  Future<List<PvModule>> listModules({
    int limit = 100,
    int offset = 0,
  }) async {
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/modules',
        queryParameters: {
          'limit': limit,
          'offset': offset,
        },
      );
      final rawList = response.data?['modules'] as List<dynamic>? ?? const [];
      return rawList
          .whereType<Map<String, dynamic>>()
          .map(PvModule.fromJson)
          .toList();
    } on DioException catch (err) {
      throw ApiException.fromDioException(err);
    }
  }

  Future<ModuleDetails> getModuleDetails(String moduleId) async {
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/modules/$moduleId',
      );
      return ModuleDetails.fromJson(response.data ?? const {});
    } on DioException catch (err) {
      throw ApiException.fromDioException(err);
    }
  }

  Future<ModuleDetails> createModule({
    required String name,
    required String macAddress,
    List<String> managerIds = const [],
    List<String>? clientIds,
    double? panelLengthCm,
    double? panelWidthCm,
    int? panelCount,
    double? panelSpacingCm,
    double? latitude,
    double? longitude,
    double? elevationM,
    double? azimuthDeg,
    double? tiltDeg,
    String? azimuthSource,
    String? tiltSource,
    double? minimumSolarAngleDeg,
    int? inspectionIntervalDays,
    double? reservoirNominalCapacityMl,
  }) async {
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '/modules',
        data: {
          'name': name.trim(),
          'mac_address': macAddress.trim(),
          'manager_ids': managerIds,
          'client_ids': ?clientIds,
          'panel_length_cm': ?panelLengthCm,
          'panel_width_cm': ?panelWidthCm,
          'panel_count': ?panelCount,
          'panel_spacing_cm': ?panelSpacingCm,
          'latitude': ?latitude,
          'longitude': ?longitude,
          'elevation_m': ?elevationM,
          'azimuth_deg': ?azimuthDeg,
          'tilt_deg': ?tiltDeg,
          'azimuth_source': ?azimuthSource,
          'tilt_source': ?tiltSource,
          'minimum_solar_angle_deg': ?minimumSolarAngleDeg,
          'inspection_interval_days': ?inspectionIntervalDays,
          'reservoir_nominal_capacity_ml': ?reservoirNominalCapacityMl,
        },
      );
      return ModuleDetails.fromJson(response.data ?? const {});
    } on DioException catch (err) {
      throw ApiException.fromDioException(err);
    }
  }

  Future<ModuleDetails> updateConfiguration({
    required String moduleId,
    required Map<String, dynamic> payload,
  }) async {
    try {
      final response = await dio.patch<Map<String, dynamic>>(
        '/modules/$moduleId/configuration',
        data: payload,
      );
      return ModuleDetails.fromJson(response.data ?? const {});
    } on DioException catch (err) {
      throw ApiException.fromDioException(err);
    }
  }

  Future<List<IntervalChangeLogItem>> listIntervalChangeLogs(
    String moduleId, {
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/modules/$moduleId/interval-logs',
        queryParameters: {
          'limit': limit,
          'offset': offset,
        },
      );
      final rawList = response.data?['logs'] as List<dynamic>? ?? const [];
      return rawList
          .whereType<Map<String, dynamic>>()
          .map(IntervalChangeLogItem.fromJson)
          .toList();
    } on DioException catch (err) {
      throw ApiException.fromDioException(err);
    }
  }

  Future<ModuleDetails> setModuleManagers({
    required String moduleId,
    required List<String> managerIds,
  }) async {
    try {
      final response = await dio.put<Map<String, dynamic>>(
        '/modules/$moduleId/managers',
        data: {'manager_ids': managerIds},
      );
      return ModuleDetails.fromJson(response.data ?? const {});
    } on DioException catch (err) {
      throw ApiException.fromDioException(err);
    }
  }

  Future<ModuleDetails> setTechnicianAccess({
    required String moduleId,
    required String technicianId,
    required bool canView,
  }) async {
    try {
      final response = await dio.put<Map<String, dynamic>>(
        '/modules/$moduleId/technicians/$technicianId',
        data: {'can_view': canView},
      );
      return ModuleDetails.fromJson(response.data ?? const {});
    } on DioException catch (err) {
      throw ApiException.fromDioException(err);
    }
  }

  Future<ModuleDetails> setModuleClients({
    required String moduleId,
    required List<String> clientIds,
  }) async {
    try {
      final response = await dio.put<Map<String, dynamic>>(
        '/modules/$moduleId/clients',
        data: {'client_ids': clientIds},
      );
      return ModuleDetails.fromJson(response.data ?? const {});
    } on DioException catch (err) {
      throw ApiException.fromDioException(err);
    }
  }

  Future<ModuleDetails> updateClientEmailPreference({
    required String moduleId,
    required bool operationalEmailEnabled,
  }) async {
    try {
      final response = await dio.patch<Map<String, dynamic>>(
        '/modules/$moduleId/email-preferences',
        data: {'operational_email_enabled': operationalEmailEnabled},
      );
      return ModuleDetails.fromJson(response.data ?? const {});
    } on DioException catch (err) {
      throw ApiException.fromDioException(err);
    }
  }

  Future<void> deleteModule({required String moduleId}) async {
    try {
      await dio.delete('/modules/$moduleId');
    } on DioException catch (err) {
      throw ApiException.fromDioException(err);
    }
  }

  Future<List<ModuleMeasurement>> listMeasurements({
    required String moduleId,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/modules/$moduleId/measurements',
        queryParameters: {'limit': limit, 'offset': offset},
      );
      final rawList =
          response.data?['measurements'] as List<dynamic>? ?? const [];
      return rawList
          .whereType<Map<String, dynamic>>()
          .map(ModuleMeasurement.fromJson)
          .toList();
    } on DioException catch (err) {
      throw ApiException.fromDioException(err);
    }
  }

  Future<List<ModuleCleaning>> listCleanings({
    required String moduleId,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/modules/$moduleId/cleanings',
        queryParameters: {'limit': limit, 'offset': offset},
      );
      final rawList =
          response.data?['cleanings'] as List<dynamic>? ?? const [];
      return rawList
          .whereType<Map<String, dynamic>>()
          .map(ModuleCleaning.fromJson)
          .toList();
    } on DioException catch (err) {
      throw ApiException.fromDioException(err);
    }
  }

  Future<ModuleThermalMap?> getLatestThermalMap({
    required String moduleId,
  }) async {
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/modules/$moduleId/thermal-map',
      );
      final rawMap = response.data?['thermal_map'] as Map<String, dynamic>?;
      if (rawMap == null) return null;
      return ModuleThermalMap.fromJson(rawMap);
    } on DioException catch (err) {
      throw ApiException.fromDioException(err);
    }
  }
}
