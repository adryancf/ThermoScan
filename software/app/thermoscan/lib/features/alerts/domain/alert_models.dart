double? _parseAlertDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

int? _parseAlertInt(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

class FieldAlert {
  const FieldAlert({
    required this.id,
    required this.moduleId,
    required this.moduleName,
    required this.severity,
    required this.type,
    required this.title,
    required this.description,
    required this.metaText,
    this.panelIndex,
    this.localXPositionCm,
    this.xPositionCm,
    this.deltaC,
    required this.createdAt,
  });

  final String id;
  final String moduleId;
  final String moduleName;
  final String severity;
  final String type;
  final String title;
  final String description;
  final String metaText;
  final int? panelIndex;
  final double? localXPositionCm;
  final double? xPositionCm;
  final double? deltaC;
  final String createdAt;

  bool get isCritical => severity == 'critical';

  String get formattedPanelLocation {
    final parts = <String>['Array $moduleName'];
    if (panelIndex != null) {
      parts.add('Panel $panelIndex');
    }
    if (localXPositionCm != null && xPositionCm != null) {
      parts.add(
        '${localXPositionCm!.toStringAsFixed(1)} cm along panel (${xPositionCm!.toStringAsFixed(1)} cm on track)',
      );
    } else if (localXPositionCm != null) {
      parts.add('${localXPositionCm!.toStringAsFixed(1)} cm along panel');
    } else if (xPositionCm != null) {
      parts.add('${xPositionCm!.toStringAsFixed(1)} cm on track');
    }
    return parts.join(' • ');
  }

  factory FieldAlert.fromJson(Map<String, dynamic> json) {
    return FieldAlert(
      id: json['id'] as String? ?? '',
      moduleId: json['module_id'] as String? ?? '',
      moduleName: json['module_name'] as String? ?? 'Solar Array',
      severity: json['severity'] as String? ?? 'warning',
      type: json['type'] as String? ?? 'unknown',
      title: json['title'] as String? ?? 'Field Alert',
      description: json['description'] as String? ?? '',
      metaText: json['meta_text'] as String? ?? '',
      panelIndex: _parseAlertInt(json['panel_index']),
      localXPositionCm: _parseAlertDouble(
        json['local_x_position_cm'] ?? json['local_x_cm'],
      ),
      xPositionCm: _parseAlertDouble(json['x_position_cm']),
      deltaC: _parseAlertDouble(json['delta_c']),
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}

class AlertsSummary {
  const AlertsSummary({
    required this.total,
    required this.critical,
    required this.warning,
    required this.alerts,
  });

  final int total;
  final int critical;
  final int warning;
  final List<FieldAlert> alerts;

  factory AlertsSummary.fromJson(Map<String, dynamic> json) {
    final rawList = json['alerts'] as List<dynamic>? ?? const [];
    return AlertsSummary(
      total: (json['total'] as num?)?.toInt() ?? 0,
      critical: (json['critical'] as num?)?.toInt() ?? 0,
      warning: (json['warning'] as num?)?.toInt() ?? 0,
      alerts: rawList
          .whereType<Map<String, dynamic>>()
          .map(FieldAlert.fromJson)
          .toList(),
    );
  }
}
