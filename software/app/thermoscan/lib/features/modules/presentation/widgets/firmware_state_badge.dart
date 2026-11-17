import 'package:flutter/material.dart';

class FirmwareStateDisplayInfo {
  const FirmwareStateDisplayInfo({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;
}

FirmwareStateDisplayInfo firmwareStateDisplayInfo(
  String? state,
  String? detail,
) {
  final normalizedState = (state ?? '').trim().toUpperCase();
  final normalizedDetail = (detail ?? '').trim().toLowerCase();

  switch (normalizedState) {
    case 'IDLE':
      return const FirmwareStateDisplayInfo(
        label: 'Idle',
        color: Colors.teal,
        icon: Icons.check_circle_outline,
      );
    case 'SCANNING':
      return const FirmwareStateDisplayInfo(
        label: 'Scanning',
        color: Colors.blue,
        icon: Icons.radar,
      );
    case 'CLEANING':
      return const FirmwareStateDisplayInfo(
        label: 'Cleaning',
        color: Colors.cyan,
        icon: Icons.cleaning_services,
      );
    case 'HOMING':
      return const FirmwareStateDisplayInfo(
        label: 'Homing',
        color: Colors.indigo,
        icon: Icons.home_outlined,
      );
    case 'VERIFYING':
    case 'VERIFICATION':
      return const FirmwareStateDisplayInfo(
        label: 'Verifying Conditions',
        color: Colors.blueGrey,
        icon: Icons.fact_check_outlined,
      );
    case 'WAITING_VERIFICATION':
      final label = switch (normalizedDetail) {
        'cooldown_wait' => 'Waiting (Cooldown)',
        'solar_window_closed' => 'Waiting (Low Solar Angle)',
        'insufficient_water' => 'Waiting (Low Water)',
        'high_baseline_temp' => 'Waiting (High Baseline Temp)',
        _ => 'Waiting Verification',
      };
      return FirmwareStateDisplayInfo(
        label: label,
        color: Colors.amber.shade800,
        icon: Icons.hourglass_top_rounded,
      );
    case 'ERROR_HALT':
      final label = switch (normalizedDetail) {
        'limits_check_failed' || 'homing_failed' => 'Error (Homing / Limits Failed)',
        'thermal_sensor_failed' => 'Error (Thermal Sensor Failed)',
        'water_depleted' => 'Error (Water Depleted)',
        _ => 'Error (Halted)',
      };
      return FirmwareStateDisplayInfo(
        label: label,
        color: Colors.red.shade700,
        icon: Icons.error_outline,
      );
    default:
      final fallback = normalizedState.isEmpty ? 'Unknown State' : normalizedState;
      return FirmwareStateDisplayInfo(
        label: fallback,
        color: Colors.grey.shade700,
        icon: Icons.memory_outlined,
      );
  }
}

class FirmwareStateBadge extends StatelessWidget {
  const FirmwareStateBadge({
    super.key,
    required this.firmwareState,
    this.firmwareStateDetail,
    this.compact = false,
  });

  final String? firmwareState;
  final String? firmwareStateDetail;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (firmwareState == null || firmwareState!.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final info = firmwareStateDisplayInfo(firmwareState, firmwareStateDetail);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: info.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: info.color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(info.icon, size: compact ? 13 : 15, color: info.color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              info.label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: info.color,
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
