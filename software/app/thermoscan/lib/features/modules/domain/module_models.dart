double? _parseDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

int? _parseInt(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

class PanelSegmentGeometry {
  const PanelSegmentGeometry({
    this.panelIndex,
    required this.startXCm,
    required this.endXCm,
    required this.isGap,
    double? lengthCm,
    required this.label,
  }) : lengthCm = lengthCm ?? (endXCm - startXCm);

  final int? panelIndex;
  final double startXCm;
  final double endXCm;
  final bool isGap;
  final double lengthCm;
  final String label;

  bool contains(double xCm) =>
      isGap ? (xCm > startXCm && xCm < endXCm) : (xCm >= startXCm && xCm <= endXCm);
}

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
    this.totalLengthCm,
    this.powerSensors,
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
    this.configurationSync,
    this.pingIntervalSeconds,
    this.onlineWindowSeconds,
    this.lastPingAt,
    bool isOnline = false,
  }) : _explicitIsOnline = isOnline;

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
  final double? totalLengthCm;
  final List<dynamic>? powerSensors;
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
  final ConfigurationSyncInfo? configurationSync;
  final int? pingIntervalSeconds;
  final int? onlineWindowSeconds;
  final String? lastPingAt;
  final bool _explicitIsOnline;

  bool get isOnline {
    if (lastPingAt != null &&
        onlineWindowSeconds != null &&
        onlineWindowSeconds! > 0) {
      final pingDate = DateTime.tryParse(lastPingAt!);
      if (pingDate != null) {
        final diff =
            DateTime.now().toUtc().difference(pingDate.toUtc()).inSeconds;
        return diff <= onlineWindowSeconds!;
      }
    }
    return _explicitIsOnline;
  }

  bool get isPendingConfiguration =>
      monitoringStatus == 'pending_configuration';
  bool get isActiveMonitoring => monitoringStatus == 'active';

  double get calculatedTotalLengthCm {
    if (totalLengthCm != null && totalLengthCm! > 0) return totalLengthCm!;
    final count = panelCount ?? 1;
    final len = panelLengthCm ?? 100.0;
    final spc = panelSpacingCm ?? 2.0;
    return (count * len) + ((count - 1) * spc);
  }

  ({double startCm, double endCm}) getPanelBounds(int panelIndex) {
    final len = panelLengthCm ?? 100.0;
    final spc = panelSpacingCm ?? 2.0;
    final start = (panelIndex - 1) * (len + spc);
    return (startCm: start, endCm: start + len);
  }

  ({int panelIndex, double localXCm, bool inGap}) resolvePanelPosition(double xCm) {
    final count = panelCount ?? 1;
    final len = panelLengthCm ?? 100.0;
    final spc = panelSpacingCm ?? 2.0;
    for (var p = 1; p <= count; p++) {
      final start = (p - 1) * (len + spc);
      final end = start + len;
      if (xCm >= start - 1e-3 && xCm <= end + 1e-3) {
        final local = (xCm - start).clamp(0.0, len);
        return (panelIndex: p, localXCm: local, inGap: false);
      }
      if (p < count && xCm > end && xCm < start + len + spc) {
        return (panelIndex: 0, localXCm: xCm - start, inGap: true);
      }
    }
    return (panelIndex: 1, localXCm: xCm, inGap: false);
  }

  List<PanelSegmentGeometry> get panelSegments {
    final count = (panelCount != null && panelCount! > 0) ? panelCount! : 1;
    final len = (panelLengthCm != null && panelLengthCm! > 0) ? panelLengthCm! : 100.0;
    final spc = (panelSpacingCm != null && panelSpacingCm! >= 0) ? panelSpacingCm! : 0.0;
    final segments = <PanelSegmentGeometry>[];
    for (var p = 1; p <= count; p++) {
      final start = (p - 1) * (len + spc);
      final end = start + len;
      segments.add(
        PanelSegmentGeometry(
          panelIndex: p,
          startXCm: start,
          endXCm: end,
          isGap: false,
          lengthCm: len,
          label: 'Painel $p',
        ),
      );
      if (p < count && spc > 0) {
        segments.add(
          PanelSegmentGeometry(
            panelIndex: null,
            startXCm: end,
            endXCm: end + spc,
            isGap: true,
            lengthCm: spc,
            label: 'GAP ${spc.toStringAsFixed(0)}cm',
          ),
        );
      }
    }
    return segments;
  }

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
      totalLengthCm: (json['total_length_cm'] as num?)?.toDouble(),
      powerSensors: json['power_sensors'] as List<dynamic>?,
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
      configurationSync: (json['configuration_sync'] ?? json['configurationSync']) is Map<String, dynamic>
          ? ConfigurationSyncInfo.fromJson(
              (json['configuration_sync'] ?? json['configurationSync']) as Map<String, dynamic>,
            )
          : null,
      pingIntervalSeconds: (json['ping_interval_seconds'] ?? json['pingIntervalSeconds'] as num?)?.toInt(),
      onlineWindowSeconds: (json['online_window_seconds'] ?? json['onlineWindowSeconds'] as num?)?.toInt(),
      lastPingAt: (json['last_ping_at'] ?? json['lastPingAt']) as String?,
      isOnline: json['is_online'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'company_id': companyId,
      'installer_technician_id': installerTechnicianId,
      'installer_name': installerName,
      'installer_email': installerEmail,
      'name': name,
      'mac_address': macAddress,
      'is_active': isActive,
      'monitoring_status': monitoringStatus,
      if (panelLengthCm != null) 'panel_length_cm': panelLengthCm,
      if (panelWidthCm != null) 'panel_width_cm': panelWidthCm,
      if (panelCount != null) 'panel_count': panelCount,
      if (panelSpacingCm != null) 'panel_spacing_cm': panelSpacingCm,
      if (totalLengthCm != null) 'total_length_cm': totalLengthCm,
      if (powerSensors != null) 'power_sensors': powerSensors,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (elevationM != null) 'elevation_m': elevationM,
      if (azimuthDeg != null) 'azimuth_deg': azimuthDeg,
      if (tiltDeg != null) 'tilt_deg': tiltDeg,
      if (azimuthSource != null) 'azimuth_source': azimuthSource,
      if (tiltSource != null) 'tilt_source': tiltSource,
      if (minimumSolarAngleDeg != null) 'minimum_solar_angle_deg': minimumSolarAngleDeg,
      'inspection_interval_days': inspectionIntervalDays,
      if (reservoirNominalCapacityMl != null) 'reservoir_nominal_capacity_ml': reservoirNominalCapacityMl,
      if (configuredAt != null) 'configured_at': configuredAt,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'user_relationship': userRelationship,
      'permissions': {
        'can_edit_geometry_and_location': permissions.canEditGeometryAndLocation,
        'can_edit_solar_angle': permissions.canEditSolarAngle,
        'can_edit_interval': permissions.canEditInterval,
        'can_manage_access': permissions.canManageAccess,
        'can_delete': permissions.canDelete,
      },
      if (operationalEmailEnabled != null) 'operational_email_enabled': operationalEmailEnabled,
      if (configurationSync != null) 'configuration_sync': configurationSync!.toJson(),
      if (pingIntervalSeconds != null) 'ping_interval_seconds': pingIntervalSeconds,
      if (onlineWindowSeconds != null) 'online_window_seconds': onlineWindowSeconds,
      if (lastPingAt != null) 'last_ping_at': lastPingAt,
    };
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
    this.deviceStatus,
    this.configurationSync,
    this.pingIntervalSeconds,
    this.onlineWindowSeconds,
  });

  final PvModule module;
  final List<ModuleManagerItem> responsibleManagers;
  final List<ModuleManagerItem> companyManagers;
  final List<ModuleTechnicianAccess> companyTechnicians;
  final List<ModuleClientAccess> companyClients;
  final DeviceStatus? deviceStatus;
  final ConfigurationSyncInfo? configurationSync;
  final int? pingIntervalSeconds;
  final int? onlineWindowSeconds;

  ConfigurationSyncInfo? get effectiveConfigurationSync =>
      configurationSync ??
      deviceStatus?.effectiveConfigurationSync ??
      module.configurationSync;

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

    final devStatusRaw = json['device_status'] ?? json['deviceStatus'];
    final devStatus = devStatusRaw is Map<String, dynamic>
        ? DeviceStatus.fromJson(devStatusRaw)
        : null;

    final syncRaw = json['configuration_sync'] ??
        json['configurationSync'] ??
        modJson['configuration_sync'] ??
        modJson['configurationSync'] ??
        (devStatusRaw is Map<String, dynamic>
            ? (devStatusRaw['configuration_sync'] ?? devStatusRaw['configurationSync'])
            : null);
    final configSync = syncRaw is Map<String, dynamic>
        ? ConfigurationSyncInfo.fromJson(syncRaw)
        : devStatus?.configurationSync;

    final pingInterval = (json['ping_interval_seconds'] ??
        json['pingIntervalSeconds'] ??
        modJson['ping_interval_seconds'] ??
        modJson['pingIntervalSeconds'] as num?)?.toInt() ??
        devStatus?.pingIntervalSeconds;

    final onlineWindow = (json['online_window_seconds'] ??
        json['onlineWindowSeconds'] ??
        modJson['online_window_seconds'] ??
        modJson['onlineWindowSeconds'] as num?)?.toInt() ??
        devStatus?.onlineWindowSeconds;

    return ModuleDetails(
      module: PvModule.fromJson(modJson),
      responsibleManagers: respMgrs,
      companyManagers: compMgrs,
      companyTechnicians: compTechs,
      companyClients: compClients,
      deviceStatus: devStatus,
      configurationSync: configSync,
      pingIntervalSeconds: pingInterval,
      onlineWindowSeconds: onlineWindow,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'module': module.toJson(),
      'responsible_managers': responsibleManagers.map((m) => {
        'id': m.id,
        'name': m.name,
        'email': m.email,
        'is_active': m.isActive,
        'is_default_manager': m.isDefaultManager,
        if (m.assignedAt != null) 'assigned_at': m.assignedAt,
      }).toList(),
      'company_managers': companyManagers.map((m) => {
        'id': m.id,
        'name': m.name,
        'email': m.email,
        'is_active': m.isActive,
        'is_default_manager': m.isDefaultManager,
        if (m.assignedAt != null) 'assigned_at': m.assignedAt,
      }).toList(),
      'company_technicians': companyTechnicians.map((t) => {
        'id': t.id,
        'name': t.name,
        'email': t.email,
        'is_active': t.isActive,
        'is_installer': t.isInstaller,
        'can_view': t.canView,
      }).toList(),
      'company_clients': companyClients.map((c) => {
        'id': c.id,
        'name': c.name,
        'email': c.email,
        'is_active': c.isActive,
        'is_assigned': c.isAssigned,
        'operational_email_enabled': c.operationalEmailEnabled,
      }).toList(),
      if (deviceStatus != null) 'device_status': deviceStatus!.toJson(),
      if (configurationSync != null) 'configuration_sync': configurationSync!.toJson(),
      if (pingIntervalSeconds != null) 'ping_interval_seconds': pingIntervalSeconds,
      if (onlineWindowSeconds != null) 'online_window_seconds': onlineWindowSeconds,
    };
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
    this.panelIndex,
    this.localXPositionCm,
    required this.measuredAt,
    required this.xPositionCm,
    required this.maxTemperatureC,
    this.voltageV,
    this.currentA,
    this.powerW,
    this.thermalFrame,
    required this.receivedAt,
  });

  final String id;
  final String moduleId;
  final String inspectionId;
  final String sourceEventId;
  final int? panelIndex;
  final double? localXPositionCm;
  final String measuredAt;
  final double xPositionCm;
  final double maxTemperatureC;
  final double? voltageV;
  final double? currentA;
  final double? powerW;
  final List<double?>? thermalFrame;
  final String receivedAt;

  factory ModuleMeasurement.fromJson(Map<String, dynamic> json) {
    List<double?>? frame;
    if (json['thermal_frame'] is List) {
      frame = (json['thermal_frame'] as List)
          .map((e) => e == null ? null : (e as num).toDouble())
          .toList();
    }

    final rawV = json['voltage_v'];
    final rawI = json['current_a'];
    final rawP = json['power_w'];

    return ModuleMeasurement(
      id: json['id'] as String? ?? '',
      moduleId: json['module_id'] as String? ?? '',
      inspectionId: json['inspection_id'] as String? ?? '',
      sourceEventId: json['source_event_id'] as String? ?? '',
      panelIndex: _parseInt(json['panel_index']),
      localXPositionCm: _parseDouble(json['local_x_position_cm']),
      measuredAt: json['measured_at'] as String? ?? '',
      xPositionCm: _parseDouble(json['x_position_cm']) ?? 0.0,
      maxTemperatureC: _parseDouble(json['max_temperature_c']) ?? 0.0,
      voltageV: _parseDouble(rawV),
      currentA: _parseDouble(rawI),
      powerW: _parseDouble(rawP),
      thermalFrame: frame,
      receivedAt: json['received_at'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'module_id': moduleId,
      'inspection_id': inspectionId,
      'source_event_id': sourceEventId,
      if (panelIndex != null) 'panel_index': panelIndex,
      if (localXPositionCm != null) 'local_x_position_cm': localXPositionCm,
      'measured_at': measuredAt,
      'x_position_cm': xPositionCm,
      'max_temperature_c': maxTemperatureC,
      if (voltageV != null) 'voltage_v': voltageV,
      if (currentA != null) 'current_a': currentA,
      if (powerW != null) 'power_w': powerW,
      if (thermalFrame != null) 'thermal_frame': thermalFrame,
      'received_at': receivedAt,
    };
  }
}

class ModuleInspection {
  const ModuleInspection({
    required this.id,
    required this.moduleId,
    required this.sourceEventId,
    required this.type,
    this.cleaningOperationId,
    this.baselineTemperatureC,
    required this.scheduledFor,
    this.startedAt,
    this.finishedAt,
    required this.status,
    this.verificationResult,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String moduleId;
  final String sourceEventId;
  final String type;
  final String? cleaningOperationId;
  final double? baselineTemperatureC;
  final String scheduledFor;
  final String? startedAt;
  final String? finishedAt;
  final String status;
  final String? verificationResult;
  final String createdAt;
  final String updatedAt;

  factory ModuleInspection.fromJson(Map<String, dynamic> json) {
    return ModuleInspection(
      id: json['id'] as String? ?? '',
      moduleId: json['module_id'] as String? ?? '',
      sourceEventId: json['source_event_id'] as String? ?? '',
      type: json['type'] as String? ?? 'scheduled',
      cleaningOperationId: json['cleaning_operation_id'] as String?,
      baselineTemperatureC: (json['baseline_temperature_c'] as num?)?.toDouble(),
      scheduledFor: json['scheduled_for'] as String? ?? '',
      startedAt: json['started_at'] as String?,
      finishedAt: json['finished_at'] as String?,
      status: json['status'] as String? ?? 'completed',
      verificationResult: json['verification_result'] as String?,
      createdAt: json['created_at'] as String? ?? '',
      updatedAt: json['updated_at'] as String? ?? '',
    );
  }
}

class ConfirmedAnomaly {
  const ConfirmedAnomaly({
    required this.id,
    required this.moduleId,
    required this.originMeasurementId,
    required this.confirmingMeasurementIds,
    required this.sourceEventId,
    this.panelIndex,
    this.localXPositionCm,
    required this.xPositionCm,
    required this.detectedAt,
    required this.status,
    required this.actuatedAttemptsCount,
    required this.retryPending,
    this.closedAt,
  });

  final String id;
  final String moduleId;
  final String originMeasurementId;
  final List<String> confirmingMeasurementIds;
  final String sourceEventId;
  final int? panelIndex;
  final double? localXPositionCm;
  final double xPositionCm;
  final String detectedAt;
  final String status;
  final int actuatedAttemptsCount;
  final bool retryPending;
  final String? closedAt;

  factory ConfirmedAnomaly.fromJson(Map<String, dynamic> json) {
    final rawConfirming = json['confirming_measurement_ids'] as List<dynamic>? ?? [];
    return ConfirmedAnomaly(
      id: json['id'] as String? ?? '',
      moduleId: json['module_id'] as String? ?? '',
      originMeasurementId: json['origin_measurement_id'] as String? ?? '',
      confirmingMeasurementIds: rawConfirming.map((e) => e.toString()).toList(),
      sourceEventId: json['source_event_id'] as String? ?? '',
      panelIndex: _parseInt(json['panel_index']),
      localXPositionCm: _parseDouble(json['local_x_position_cm']),
      xPositionCm: _parseDouble(json['x_position_cm']) ?? 0.0,
      detectedAt: json['detected_at'] as String? ?? '',
      status: json['status'] as String? ?? 'open',
      actuatedAttemptsCount: _parseInt(json['actuated_attempts_count']) ?? 0,
      retryPending: json['retry_pending'] as bool? ?? false,
      closedAt: json['closed_at'] as String?,
    );
  }
}

class InspectionPanelResult {
  const InspectionPanelResult({
    required this.inspectionId,
    required this.moduleId,
    required this.panelIndex,
    required this.baselineTemperatureC,
    required this.truncatedByMemory,
    required this.finishedAt,
    required this.createdAt,
  });

  final String inspectionId;
  final String moduleId;
  final int panelIndex;
  final double baselineTemperatureC;
  final bool truncatedByMemory;
  final String finishedAt;
  final String createdAt;

  factory InspectionPanelResult.fromJson(Map<String, dynamic> json) {
    return InspectionPanelResult(
      inspectionId: json['inspection_id'] as String? ?? '',
      moduleId: json['module_id'] as String? ?? '',
      panelIndex: (json['panel_index'] as num?)?.toInt() ?? 1,
      baselineTemperatureC: double.tryParse(json['baseline_temperature_c']?.toString() ?? '') ?? 0.0,
      truncatedByMemory: json['truncated_by_memory'] as bool? ?? false,
      finishedAt: json['finished_at'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}

class LatestInspection {
  const LatestInspection({
    required this.inspection,
    required this.totalMeasurements,
    required this.confirmedAnomalies,
    this.panelResults,
  });

  final ModuleInspection inspection;
  final int totalMeasurements;
  final List<ConfirmedAnomaly> confirmedAnomalies;
  final List<InspectionPanelResult>? panelResults;

  factory LatestInspection.fromJson(Map<String, dynamic> json) {
    final inspJson = json['inspection'] as Map<String, dynamic>? ?? {};
    final anomsJson = json['confirmed_anomalies'] as List<dynamic>? ?? [];
    final panelsJson = json['panel_results'] as List<dynamic>?;
    return LatestInspection(
      inspection: ModuleInspection.fromJson(inspJson),
      totalMeasurements: (json['total_measurements'] as num?)?.toInt() ?? 0,
      confirmedAnomalies: anomsJson
          .map((a) => ConfirmedAnomaly.fromJson(a as Map<String, dynamic>))
          .toList(),
      panelResults: panelsJson
          ?.whereType<Map<String, dynamic>>()
          .map(InspectionPanelResult.fromJson)
          .toList(),
    );
  }
}

class PagedMeasurements {
  const PagedMeasurements({
    required this.page,
    required this.limit,
    required this.totalCount,
    required this.totalPages,
    required this.hasNextPage,
    required this.measurements,
  });

  final int page;
  final int limit;
  final int totalCount;
  final int totalPages;
  final bool hasNextPage;
  final List<ModuleMeasurement> measurements;

  factory PagedMeasurements.fromJson(Map<String, dynamic> json) {
    final pag = json['pagination'] as Map<String, dynamic>? ?? {};
    final items = json['measurements'] as List<dynamic>? ?? [];
    return PagedMeasurements(
      page: (pag['page'] as num?)?.toInt() ?? 1,
      limit: (pag['limit'] as num?)?.toInt() ?? 10,
      totalCount: (pag['total_count'] as num?)?.toInt() ?? 0,
      totalPages: (pag['total_pages'] as num?)?.toInt() ?? 1,
      hasNextPage: pag['has_next_page'] as bool? ?? false,
      measurements: items
          .map((m) => ModuleMeasurement.fromJson(m as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ModuleCleaning {
  const ModuleCleaning({
    required this.id,
    required this.moduleId,
    required this.anomalyEventId,
    required this.sourceEventId,
    this.panelIndex,
    this.localXPositionCm,
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
  final int? panelIndex;
  final double? localXPositionCm;
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
      panelIndex: _parseInt(json['panel_index']),
      localXPositionCm: _parseDouble(
        json['local_x_position_cm'] ?? json['local_target_x_position_cm'],
      ),
      targetXPositionCm: _parseDouble(json['target_x_position_cm']) ?? 0.0,
      pumpActuated: json['pump_actuated'] as bool? ?? false,
      attemptNumber: _parseInt(json['attempt_number']),
      startedAt: json['started_at'] as String?,
      endedAt: json['ended_at'] as String?,
      durationSeconds: _parseDouble(json['duration_seconds']),
      estimatedWaterVolumeMl: _parseDouble(json['estimated_water_volume_ml']),
      status: json['status'] as String? ?? 'scheduled',
      failureReason: json['failure_reason'] as String?,
      postCleaningResult: json['post_cleaning_result'] as String? ?? 'pending',
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}


class ConfigurationSyncInfo {
  const ConfigurationSyncInfo({
    required this.state,
    required this.configVersion,
    required this.configAppliedVersion,
    this.configAppliedAt,
    this.configApplyError,
  });

  /// Sync state: 'synced', 'pending', or 'failed'
  final String state;
  final int configVersion;
  final int configAppliedVersion;
  final DateTime? configAppliedAt;
  final String? configApplyError;

  bool get isSynced =>
      state == 'synced' ||
      (configVersion > 0 && configAppliedVersion == configVersion && !isFailed);
  bool get isPending =>
      state == 'pending' || (configAppliedVersion < configVersion && !isFailed);
  bool get isFailed =>
      state == 'failed' ||
      (configApplyError != null && configApplyError!.isNotEmpty);

  factory ConfigurationSyncInfo.fromJson(Map<String, dynamic> json) {
    DateTime? parsedAppliedAt;
    final rawDate = json['config_applied_at'] ?? json['configAppliedAt'];
    if (rawDate is String && rawDate.isNotEmpty) {
      parsedAppliedAt = DateTime.tryParse(rawDate);
    } else if (rawDate is DateTime) {
      parsedAppliedAt = rawDate;
    }

    final rawError =
        (json['config_apply_error'] ?? json['configApplyError']) as String?;
    final version =
        (json['config_version'] ?? json['configVersion'] as num?)?.toInt() ?? 1;
    final appliedVersion =
        (json['config_applied_version'] ?? json['configAppliedVersion'] as num?)
                ?.toInt() ??
            0;

    String rawState = (json['state'] as String? ?? '').toLowerCase().trim();
    if (rawState.isEmpty) {
      if (rawError != null && rawError.isNotEmpty) {
        rawState = 'failed';
      } else if (appliedVersion >= version && version > 0) {
        rawState = 'synced';
      } else {
        rawState = 'pending';
      }
    }

    return ConfigurationSyncInfo(
      state: rawState,
      configVersion: version,
      configAppliedVersion: appliedVersion,
      configAppliedAt: parsedAppliedAt,
      configApplyError: rawError,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'state': state,
      'config_version': configVersion,
      'config_applied_version': configAppliedVersion,
      if (configAppliedAt != null)
        'config_applied_at': configAppliedAt!.toIso8601String(),
      if (configApplyError != null) 'config_apply_error': configApplyError,
    };
  }
}

class DeviceStatus {
  const DeviceStatus({
    required this.moduleId,
    required this.macAddress,
    required this.monitoringStatus,
    required this.isConfigured,
    this.configuredAt,
    bool isOnline = false,
    this.lastSeenAt,
    this.lastPingAt,
    this.waterAvailable,
    required this.waterStatus,
    required this.limitsCheckPassed,
    required this.thermalSensorActive,
    this.latestMeasurementAt,
    this.configurationSync,
    this.pingIntervalSeconds,
    this.onlineWindowSeconds,
  }) : _explicitIsOnline = isOnline;

  final String moduleId;
  final String macAddress;
  final String monitoringStatus;
  final bool isConfigured;
  final String? configuredAt;
  final bool _explicitIsOnline;
  final String? lastSeenAt;
  final String? lastPingAt;
  final bool? waterAvailable;
  final String waterStatus;
  final bool limitsCheckPassed;
  final bool thermalSensorActive;
  final String? latestMeasurementAt;
  final ConfigurationSyncInfo? configurationSync;
  final int? pingIntervalSeconds;
  final int? onlineWindowSeconds;

  bool get isOnline {
    if (lastPingAt != null &&
        onlineWindowSeconds != null &&
        onlineWindowSeconds! > 0) {
      final pingDate = DateTime.tryParse(lastPingAt!);
      if (pingDate != null) {
        final diff =
            DateTime.now().toUtc().difference(pingDate.toUtc()).inSeconds;
        return diff <= onlineWindowSeconds!;
      }
    }
    return _explicitIsOnline;
  }

  ConfigurationSyncInfo get effectiveConfigurationSync {
    if (configurationSync != null) return configurationSync!;
    if (isConfigured) {
      DateTime? appliedAt;
      if (configuredAt != null && configuredAt!.isNotEmpty) {
        appliedAt = DateTime.tryParse(configuredAt!);
      }
      return ConfigurationSyncInfo(
        state: 'synced',
        configVersion: 1,
        configAppliedVersion: 1,
        configAppliedAt: appliedAt,
      );
    }
    return const ConfigurationSyncInfo(
      state: 'pending',
      configVersion: 1,
      configAppliedVersion: 0,
    );
  }

  factory DeviceStatus.fromJson(Map<String, dynamic> json) {
    final syncRaw = json['configuration_sync'] ?? json['configurationSync'];
    ConfigurationSyncInfo? syncInfo;
    if (syncRaw is Map<String, dynamic>) {
      syncInfo = ConfigurationSyncInfo.fromJson(syncRaw);
    } else if (json.containsKey('config_version') ||
        json.containsKey('config_applied_version')) {
      syncInfo = ConfigurationSyncInfo.fromJson(json);
    }

    return DeviceStatus(
      moduleId: json['module_id'] as String? ?? '',
      macAddress: json['mac_address'] as String? ?? '',
      monitoringStatus:
          json['monitoring_status'] as String? ?? 'pending_configuration',
      isConfigured: json['is_configured'] as bool? ?? false,
      configuredAt: json['configured_at'] as String?,
      isOnline: json['is_online'] as bool? ?? false,
      lastSeenAt: json['last_seen_at'] as String?,
      lastPingAt: (json['last_ping_at'] ?? json['lastPingAt']) as String?,
      waterAvailable: json['water_available'] as bool?,
      waterStatus: json['water_status'] as String? ?? 'unknown',
      limitsCheckPassed: json['limits_check_passed'] as bool? ?? false,
      thermalSensorActive: json['thermal_sensor_active'] as bool? ?? false,
      latestMeasurementAt: json['latest_measurement_at'] as String?,
      configurationSync: syncInfo,
      pingIntervalSeconds: (json['ping_interval_seconds'] ??
              json['pingIntervalSeconds'] as num?)
          ?.toInt(),
      onlineWindowSeconds: (json['online_window_seconds'] ??
              json['onlineWindowSeconds'] as num?)
          ?.toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'module_id': moduleId,
      'mac_address': macAddress,
      'monitoring_status': monitoringStatus,
      'is_configured': isConfigured,
      if (configuredAt != null) 'configured_at': configuredAt,
      'is_online': isOnline,
      if (lastSeenAt != null) 'last_seen_at': lastSeenAt,
      if (lastPingAt != null) 'last_ping_at': lastPingAt,
      if (waterAvailable != null) 'water_available': waterAvailable,
      'water_status': waterStatus,
      'limits_check_passed': limitsCheckPassed,
      'thermal_sensor_active': thermalSensorActive,
      if (latestMeasurementAt != null)
        'latest_measurement_at': latestMeasurementAt,
      if (configurationSync != null)
        'configuration_sync': configurationSync!.toJson(),
      if (pingIntervalSeconds != null)
        'ping_interval_seconds': pingIntervalSeconds,
      if (onlineWindowSeconds != null)
        'online_window_seconds': onlineWindowSeconds,
    };
  }
}
