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
    case 'BOOT_INIT':
      return const FirmwareStateDisplayInfo(
        label: 'Initializing',
        color: Colors.blueGrey,
        icon: Icons.power_settings_new,
      );
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
    case 'ANALYZING':
      return const FirmwareStateDisplayInfo(
        label: 'Analyzing',
        color: Colors.deepPurple,
        icon: Icons.analytics_outlined,
      );
    case 'SYNCING':
      return const FirmwareStateDisplayInfo(
        label: 'Syncing',
        color: Colors.lightBlue,
        icon: Icons.sync,
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
        'camera_recovery_failed' => 'Error (Camera Recovery Failed)',
        'cleaning_crash_loop' => 'Error (Cleaning Crash Loop)',
        'water_depleted' ||
        'water_depleted_during_cleaning' =>
          'Error (Water Depleted)',
        _ => 'Error (Halted)',
      };
      return FirmwareStateDisplayInfo(
        label: label,
        color: Colors.red.shade700,
        icon: Icons.error_outline,
      );
    case 'SCAN_ABORTED':
      final label = switch (normalizedDetail) {
        'network_disconnected' => 'Scan Aborted (Network Disconnected)',
        'telemetry_upload_failed' => 'Scan Aborted (Upload Failed)',
        'panel_result_rejected' => 'Scan Aborted (Panel Rejected)',
        _ => 'Scan Aborted',
      };
      return FirmwareStateDisplayInfo(
        label: label,
        color: Colors.deepOrange.shade700,
        icon: Icons.cancel_outlined,
      );
    case 'ABORT_SYNCED':
      return FirmwareStateDisplayInfo(
        label: 'Abort Synced',
        color: Colors.blueGrey.shade700,
        icon: Icons.cloud_done_outlined,
      );
    case 'CAMERA_FAIL':
      return FirmwareStateDisplayInfo(
        label: 'Camera Capture Failed',
        color: Colors.red.shade600,
        icon: Icons.videocam_off_outlined,
      );
    case 'CLEANING_REFUSED':
      final label = switch (normalizedDetail) {
        'insufficient_water' => 'Cleaning Refused (Insufficient Water)',
        'thermal_shock_risk' => 'Cleaning Refused (Thermal Shock Risk)',
        'target_in_gap' => 'Cleaning Refused (Target in Gap)',
        'max_attempts_exceeded' => 'Cleaning Refused (Max Attempts)',
        _ => 'Cleaning Refused',
      };
      return FirmwareStateDisplayInfo(
        label: label,
        color: Colors.orange.shade800,
        icon: Icons.block_outlined,
      );
    case 'MANUAL_CLEANING':
      return const FirmwareStateDisplayInfo(
        label: 'Manual Cleaning',
        color: Colors.cyan,
        icon: Icons.cleaning_services_outlined,
      );
    case 'INIT_WARNING':
      return FirmwareStateDisplayInfo(
        label: 'Init Warning',
        color: Colors.amber.shade900,
        icon: Icons.warning_amber_rounded,
      );
    case 'RESET_REQUESTED':
      return FirmwareStateDisplayInfo(
        label: 'Reset Requested...',
        color: Colors.red.shade700,
        icon: Icons.restart_alt,
      );
    case 'MANUAL_CLEANING_PENDING':
      return FirmwareStateDisplayInfo(
        label: 'Cleaning Requested...',
        color: Colors.cyan.shade700,
        icon: Icons.cleaning_services_outlined,
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
