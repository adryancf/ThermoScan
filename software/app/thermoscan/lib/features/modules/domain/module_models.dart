class ModulePermissions {
  const ModulePermissions({
    required this.canEditGeometryAndLocation,
    required this.canEditSolarAngle,
    required this.canEditInterval,
    required this.canManageAccess,
    this.canDelete = false,
  });

  final bool canEditGeometryAndLocation;
  final bool canEditSolarAngle;
  final bool canEditInterval;
  final bool canManageAccess;
  final bool canDelete;

  bool get canEditAnyField =>
      canEditGeometryAndLocation || canEditSolarAngle || canEditInterval;

  factory ModulePermissions.fromJson(Map<String, dynamic> json) {
    return ModulePermissions(
      canEditGeometryAndLocation:
          json['can_edit_geometry_and_location'] as bool? ?? false,
      canEditSolarAngle: json['can_edit_solar_angle'] as bool? ?? false,
      canEditInterval: json['can_edit_interval'] as bool? ?? false,
      canManageAccess: json['can_manage_access'] as bool? ?? false,
      canDelete: json['can_delete'] as bool? ?? false,
    );
  }
}

class PvModule {
  const PvModule({
    required this.id,
    required this.companyId,
    required this.installerTechnicianId,
    required this.installerName,
    required this.installerEmail,
    required this.name,
    required this.macAddress,
    required this.isActive,
    required this.monitoringStatus,
    this.panelLengthCm,
    this.panelWidthCm,
    this.panelCount,
    this.panelSpacingCm,
    this.latitude,
    this.longitude,
    this.elevationM,
    this.azimuthDeg,
    this.tiltDeg,
    this.azimuthSource,
    this.tiltSource,
    this.minimumSolarAngleDeg,
    required this.inspectionIntervalDays,
    this.reservoirNominalCapacityMl,
    this.configuredAt,
    required this.createdAt,
    required this.updatedAt,
    required this.userRelationship,
    required this.permissions,
    this.operationalEmailEnabled,
  });

  final String id;
  final String companyId;
  final String installerTechnicianId;
  final String installerName;
  final String installerEmail;
  final String name;
  final String macAddress;
  final bool isActive;
  final String monitoringStatus;
  final double? panelLengthCm;
  final double? panelWidthCm;
  final int? panelCount;
  final double? panelSpacingCm;
  final double? latitude;
  final double? longitude;
  final double? elevationM;
  final double? azimuthDeg;
  final double? tiltDeg;
  final String? azimuthSource;
  final String? tiltSource;
  final double? minimumSolarAngleDeg;
  final int inspectionIntervalDays;
  final double? reservoirNominalCapacityMl;
  final String? configuredAt;
  final String createdAt;
  final String updatedAt;
  final String userRelationship;
  final ModulePermissions permissions;
  final bool? operationalEmailEnabled;

  bool get isPendingConfiguration =>
      monitoringStatus == 'pending_configuration';
  bool get isActiveMonitoring => monitoringStatus == 'active';

  String get monitoringStatusLabel {
    switch (monitoringStatus) {
      case 'active':
        return 'Active';
      case 'pending_configuration':
        return 'Pending Config';
      case 'maintenance':
        return 'Maintenance';
      case 'inactive':
        return 'Inactive';
      default:
        return monitoringStatus;
    }
  }

  String get relationshipLabel {
    switch (userRelationship) {
      case 'manager':
        return 'Company Manager';
      case 'installer_technician':
        return 'Installer Technician';
      case 'shared_technician':
        return 'Shared Technician';
      case 'assigned_client':
        return 'Assigned Client';
      default:
        return userRelationship;
    }
  }

  factory PvModule.fromJson(Map<String, dynamic> json) {
    final permsRaw = json['permissions'];
    return PvModule(
      id: json['id'] as String? ?? '',
      companyId: json['company_id'] as String? ?? '',
      installerTechnicianId: json['installer_technician_id'] as String? ?? '',
      installerName: json['installer_name'] as String? ?? '',
      installerEmail: json['installer_email'] as String? ?? '',
      name: json['name'] as String? ?? '',
      macAddress: json['mac_address'] as String? ?? '',
      isActive: json['is_active'] as bool? ?? true,
      monitoringStatus:
          json['monitoring_status'] as String? ?? 'pending_configuration',
      panelLengthCm: (json['panel_length_cm'] as num?)?.toDouble(),
      panelWidthCm: (json['panel_width_cm'] as num?)?.toDouble(),
      panelCount: (json['panel_count'] as num?)?.toInt(),
      panelSpacingCm: (json['panel_spacing_cm'] as num?)?.toDouble(),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      elevationM: (json['elevation_m'] as num?)?.toDouble(),
      azimuthDeg: (json['azimuth_deg'] as num?)?.toDouble(),
      tiltDeg: (json['tilt_deg'] as num?)?.toDouble(),
      azimuthSource: json['azimuth_source'] as String?,
      tiltSource: json['tilt_source'] as String?,
      minimumSolarAngleDeg:
          (json['minimum_solar_angle_deg'] as num?)?.toDouble(),
      inspectionIntervalDays:
          (json['inspection_interval_days'] as num?)?.toInt() ?? 1,
      reservoirNominalCapacityMl:
          (json['reservoir_nominal_capacity_ml'] as num?)?.toDouble(),
      configuredAt: json['configured_at'] as String?,
      createdAt: json['created_at'] as String? ?? '',
      updatedAt: json['updated_at'] as String? ?? '',
      userRelationship: json['user_relationship'] as String? ?? '',
      permissions: permsRaw is Map<String, dynamic>
          ? ModulePermissions.fromJson(permsRaw)
          : const ModulePermissions(
              canEditGeometryAndLocation: false,
              canEditSolarAngle: false,
              canEditInterval: false,
              canManageAccess: false,
            ),
      operationalEmailEnabled: json['operational_email_enabled'] as bool?,
    );
  }
}

class ModuleManagerItem {
  const ModuleManagerItem({
    required this.id,
    required this.name,
    required this.email,
    required this.isActive,
    required this.isDefaultManager,
    this.assignedAt,
  });

  final String id;
  final String name;
  final String email;
  final bool isActive;
  final bool isDefaultManager;
  final String? assignedAt;

  factory ModuleManagerItem.fromJson(Map<String, dynamic> json) {
    return ModuleManagerItem(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      isActive: json['is_active'] as bool? ?? true,
      isDefaultManager: json['is_default_manager'] as bool? ?? false,
      assignedAt: json['assigned_at'] as String?,
    );
  }
}

class ModuleTechnicianAccess {
  const ModuleTechnicianAccess({
    required this.id,
    required this.name,
    required this.email,
    required this.isActive,
    required this.isInstaller,
    required this.canView,
  });

  final String id;
  final String name;
  final String email;
  final bool isActive;
  final bool isInstaller;
  final bool canView;

  factory ModuleTechnicianAccess.fromJson(Map<String, dynamic> json) {
    return ModuleTechnicianAccess(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      isActive: json['is_active'] as bool? ?? true,
      isInstaller: json['is_installer'] as bool? ?? false,
      canView: json['can_view'] as bool? ?? false,
    );
  }
}

class ModuleClientItem {
  const ModuleClientItem({
    required this.id,
    required this.name,
    required this.email,
    required this.isActive,
  });

  final String id;
  final String name;
  final String email;
  final bool isActive;

  factory ModuleClientItem.fromJson(Map<String, dynamic> json) {
    return ModuleClientItem(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

class ModuleClientAccess {
  const ModuleClientAccess({
    required this.id,
    required this.name,
    required this.email,
    required this.isActive,
    required this.isAssigned,
    required this.operationalEmailEnabled,
  });

  final String id;
  final String name;
  final String email;
  final bool isActive;
  final bool isAssigned;
  final bool operationalEmailEnabled;

  factory ModuleClientAccess.fromJson(Map<String, dynamic> json) {
    return ModuleClientAccess(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      isActive: json['is_active'] as bool? ?? true,
      isAssigned: json['is_assigned'] as bool? ?? false,
      operationalEmailEnabled:
          json['operational_email_enabled'] as bool? ?? true,
    );
  }
}

class ModuleDetails {
  const ModuleDetails({
    required this.module,
    required this.responsibleManagers,
    required this.companyManagers,
    required this.companyTechnicians,
    required this.companyClients,
  });

  final PvModule module;
  final List<ModuleManagerItem> responsibleManagers;
  final List<ModuleManagerItem> companyManagers;
  final List<ModuleTechnicianAccess> companyTechnicians;
  final List<ModuleClientAccess> companyClients;

  factory ModuleDetails.fromJson(Map<String, dynamic> json) {
    final modJson = json['module'] as Map<String, dynamic>? ?? const {};
    final respMgrs = (json['responsible_managers'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ModuleManagerItem.fromJson)
        .toList();
    final compMgrs = (json['company_managers'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ModuleManagerItem.fromJson)
        .toList();
    final compTechs =
        (json['company_technicians'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ModuleTechnicianAccess.fromJson)
            .toList();
    final compClients = (json['company_clients'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ModuleClientAccess.fromJson)
        .toList();

    return ModuleDetails(
      module: PvModule.fromJson(modJson),
      responsibleManagers: respMgrs,
      companyManagers: compMgrs,
      companyTechnicians: compTechs,
      companyClients: compClients,
    );
  }
}

class IntervalChangeLogItem {
  const IntervalChangeLogItem({
    required this.id,
    required this.moduleId,
    required this.authorUserId,
    required this.authorName,
    required this.authorEmail,
    required this.authorRole,
    required this.previousIntervalDays,
    required this.newIntervalDays,
    required this.changedAt,
  });

  final String id;
  final String moduleId;
  final String authorUserId;
  final String authorName;
  final String authorEmail;
  final String authorRole;
  final int previousIntervalDays;
  final int newIntervalDays;
  final String changedAt;

  factory IntervalChangeLogItem.fromJson(Map<String, dynamic> json) {
    return IntervalChangeLogItem(
      id: json['id'] as String? ?? '',
      moduleId: json['module_id'] as String? ?? '',
      authorUserId: json['author_user_id'] as String? ?? '',
      authorName: json['author_name'] as String? ?? '',
      authorEmail: json['author_email'] as String? ?? '',
      authorRole: json['author_role'] as String? ?? '',
      previousIntervalDays:
          (json['previous_interval_days'] as num?)?.toInt() ?? 1,
      newIntervalDays: (json['new_interval_days'] as num?)?.toInt() ?? 1,
      changedAt: json['changed_at'] as String? ?? '',
    );
  }
}

class ModuleMeasurement {
  const ModuleMeasurement({
    required this.id,
    required this.moduleId,
    required this.inspectionId,
    required this.sourceEventId,
    required this.measuredAt,
    required this.xPositionCm,
    required this.baselineTemperatureC,
    required this.maxTemperatureC,
    required this.hotspotDetected,
    required this.hotspotConfirmed,
    required this.voltageV,
    required this.currentA,
    required this.powerW,
    required this.receivedAt,
  });

  final String id;
  final String moduleId;
  final String inspectionId;
  final String sourceEventId;
  final String measuredAt;
  final double xPositionCm;
  final double baselineTemperatureC;
  final double maxTemperatureC;
  final bool hotspotDetected;
  final bool hotspotConfirmed;
  final double voltageV;
  final double currentA;
  final double powerW;
  final String receivedAt;

  factory ModuleMeasurement.fromJson(Map<String, dynamic> json) {
    return ModuleMeasurement(
      id: json['id'] as String? ?? '',
      moduleId: json['module_id'] as String? ?? '',
      inspectionId: json['inspection_id'] as String? ?? '',
      sourceEventId: json['source_event_id'] as String? ?? '',
      measuredAt: json['measured_at'] as String? ?? '',
      xPositionCm: double.tryParse(json['x_position_cm']?.toString() ?? '') ?? 0.0,
      baselineTemperatureC: double.tryParse(json['baseline_temperature_c']?.toString() ?? '') ?? 0.0,
      maxTemperatureC: double.tryParse(json['max_temperature_c']?.toString() ?? '') ?? 0.0,
      hotspotDetected: json['hotspot_detected'] as bool? ?? false,
      hotspotConfirmed: json['hotspot_confirmed'] as bool? ?? false,
      voltageV: double.tryParse(json['voltage_v']?.toString() ?? '') ?? 0.0,
      currentA: double.tryParse(json['current_a']?.toString() ?? '') ?? 0.0,
      powerW: double.tryParse(json['power_w']?.toString() ?? '') ?? 0.0,
      receivedAt: json['received_at'] as String? ?? '',
    );
  }
}

class ModuleCleaning {
  const ModuleCleaning({
    required this.id,
    required this.moduleId,
    required this.anomalyEventId,
    required this.sourceEventId,
    required this.targetXPositionCm,
    required this.pumpActuated,
    this.attemptNumber,
    this.startedAt,
    this.endedAt,
    this.durationSeconds,
    this.estimatedWaterVolumeMl,
    required this.status,
    this.failureReason,
    required this.postCleaningResult,
    required this.createdAt,
  });

  final String id;
  final String moduleId;
  final String anomalyEventId;
  final String sourceEventId;
  final double targetXPositionCm;
  final bool pumpActuated;
  final int? attemptNumber;
  final String? startedAt;
  final String? endedAt;
  final double? durationSeconds;
  final double? estimatedWaterVolumeMl;
  final String status;
  final String? failureReason;
  final String postCleaningResult;
  final String createdAt;

  factory ModuleCleaning.fromJson(Map<String, dynamic> json) {
    return ModuleCleaning(
      id: json['id'] as String? ?? '',
      moduleId: json['module_id'] as String? ?? '',
      anomalyEventId: json['anomaly_event_id'] as String? ?? '',
      sourceEventId: json['source_event_id'] as String? ?? '',
      targetXPositionCm: double.tryParse(json['target_x_position_cm']?.toString() ?? '') ?? 0.0,
      pumpActuated: json['pump_actuated'] as bool? ?? false,
      attemptNumber: (json['attempt_number'] as num?)?.toInt(),
      startedAt: json['started_at'] as String?,
      endedAt: json['ended_at'] as String?,
      durationSeconds: double.tryParse(json['duration_seconds']?.toString() ?? ''),
      estimatedWaterVolumeMl: double.tryParse(json['estimated_water_volume_ml']?.toString() ?? ''),
      status: json['status'] as String? ?? 'scheduled',
      failureReason: json['failure_reason'] as String?,
      postCleaningResult: json['post_cleaning_result'] as String? ?? 'pending',
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}

class ThermalBand {
  const ThermalBand({
    required this.bandIndex,
    required this.startXCm,
    required this.endXCm,
    required this.maxTemperatureC,
    required this.avgTemperatureC,
    required this.hasHotspot,
  });

  final int bandIndex;
  final double startXCm;
  final double endXCm;
  final double maxTemperatureC;
  final double avgTemperatureC;
  final bool hasHotspot;

  String get label => 'F$bandIndex (${startXCm.toStringAsFixed(0)}-${endXCm.toStringAsFixed(0)}cm)';

  factory ThermalBand.fromJson(Map<String, dynamic> json) {
    return ThermalBand(
      bandIndex: (json['band_index'] as num?)?.toInt() ?? 1,
      startXCm: (json['start_x_cm'] as num?)?.toDouble() ?? 0.0,
      endXCm: (json['end_x_cm'] as num?)?.toDouble() ?? 5.0,
      maxTemperatureC: (json['max_temperature_c'] as num?)?.toDouble() ?? 0.0,
      avgTemperatureC: (json['avg_temperature_c'] as num?)?.toDouble() ?? 0.0,
      hasHotspot: json['has_hotspot'] as bool? ?? false,
    );
  }
}

class ModuleThermalMap {
  const ModuleThermalMap({
    required this.id,
    required this.inspectionId,
    required this.widthPixels,
    required this.heightPixels,
    required this.algorithmVersion,
    required this.generatedAt,
    this.temperatures,
    this.bands = const [],
  });

  final String id;
  final String inspectionId;
  final int widthPixels;
  final int heightPixels;
  final String algorithmVersion;
  final String generatedAt;
  final List<dynamic>? temperatures;
  final List<ThermalBand> bands;

  factory ModuleThermalMap.fromJson(Map<String, dynamic> json) {
    final rawBands = json['bands'] as List<dynamic>?;
    final parsedBands = rawBands != null
        ? rawBands
            .map((b) => ThermalBand.fromJson(b as Map<String, dynamic>))
            .toList()
        : <ThermalBand>[];

    return ModuleThermalMap(
      id: json['id'] as String? ?? '',
      inspectionId: json['inspection_id'] as String? ?? '',
      widthPixels: (json['width_pixels'] as num?)?.toInt() ?? 32,
      heightPixels: (json['height_pixels'] as num?)?.toInt() ?? 24,
      algorithmVersion: json['algorithm_version'] as String? ?? 'v1',
      generatedAt: json['generated_at'] as String? ?? '',
      temperatures: json['temperatures_c'] as List<dynamic>?,
      bands: parsedBands,
    );
  }
}

class DeviceStatus {
  const DeviceStatus({
    required this.moduleId,
    required this.macAddress,
    required this.monitoringStatus,
    required this.isConfigured,
    this.configuredAt,
    required this.isOnline,
    this.lastSeenAt,
    this.waterAvailable,
    required this.waterStatus,
    required this.limitsCheckPassed,
    required this.thermalSensorActive,
    this.latestMeasurementAt,
  });

  final String moduleId;
  final String macAddress;
  final String monitoringStatus;
  final bool isConfigured;
  final String? configuredAt;
  final bool isOnline;
  final String? lastSeenAt;
  final bool? waterAvailable;
  final String waterStatus;
  final bool limitsCheckPassed;
  final bool thermalSensorActive;
  final String? latestMeasurementAt;

  factory DeviceStatus.fromJson(Map<String, dynamic> json) {
    return DeviceStatus(
      moduleId: json['module_id'] as String? ?? '',
      macAddress: json['mac_address'] as String? ?? '',
      monitoringStatus:
          json['monitoring_status'] as String? ?? 'pending_configuration',
      isConfigured: json['is_configured'] as bool? ?? false,
      configuredAt: json['configured_at'] as String?,
      isOnline: json['is_online'] as bool? ?? false,
      lastSeenAt: json['last_seen_at'] as String?,
      waterAvailable: json['water_available'] as bool?,
      waterStatus: json['water_status'] as String? ?? 'unknown',
      limitsCheckPassed: json['limits_check_passed'] as bool? ?? false,
      thermalSensorActive: json['thermal_sensor_active'] as bool? ?? false,
      latestMeasurementAt: json['latest_measurement_at'] as String?,
    );
  }
}
