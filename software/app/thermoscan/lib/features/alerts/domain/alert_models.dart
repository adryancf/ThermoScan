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
      panelIndex: (json['panel_index'] as num?)?.toInt(),
      localXPositionCm: (json['local_x_position_cm'] as num?)?.toDouble(),
      xPositionCm: (json['x_position_cm'] as num?)?.toDouble(),
      deltaC: (json['delta_c'] as num?)?.toDouble(),
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
