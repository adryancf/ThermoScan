import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/core/widgets/app_buttons.dart';
import 'package:thermoscan/core/widgets/top_app_bar.dart';
import 'package:thermoscan/features/auth/presentation/auth_controller.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';
import 'package:thermoscan/features/modules/presentation/modules_controller.dart';

/// Post-installation Device Verification & Checklist Screen
class ModuleHardwareHandshakeScreen extends ConsumerStatefulWidget {
  const ModuleHardwareHandshakeScreen({
    super.key,
    required this.moduleId,
  });

  final String moduleId;

  @override
  ConsumerState<ModuleHardwareHandshakeScreen> createState() =>
      _ModuleHardwareHandshakeScreenState();
}

/// Backward compatibility alias
typedef ModuleDeviceVerificationScreen = ModuleHardwareHandshakeScreen;

class _ModuleHardwareHandshakeScreenState
    extends ConsumerState<ModuleHardwareHandshakeScreen> {
  Timer? _pollTimer;

  void _showCommunicationFlowModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.hub_outlined,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Text('Device Verification Flow', style: AppTypography.h3),
              ],
            ),
            const SizedBox(height: 14),
            _buildFlowStep(
              '1. Cloud Setup',
              'Module dimensions, tilt angle and solar coordinates are registered in the cloud.',
            ),
            _buildFlowStep(
              '2. ESP32 Wi-Fi Sync',
              'ESP32 connects to Wi-Fi and downloads the active operating parameters.',
            ),
            _buildFlowStep(
              '3. Safety Checks',
              'Carriage homing switches and fluid sensor confirm safe conditions.',
            ),
            _buildFlowStep(
              '4. Ready for Scans',
              'Module enters active monitoring, ready for autonomous inspections.',
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Understood',
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlowStep(String stepTitle, String stepDesc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle_outline_rounded,
            color: AppColors.success,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stepTitle,
                  style: AppTypography.bodySmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  stepDesc,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // Poll every 4 seconds for device heartbeat/sync
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) {
        ref.invalidate(moduleDeviceStatusProvider(widget.moduleId));
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final detailsAsync = ref.watch(moduleDetailsProvider(widget.moduleId));
    final statusAsync = ref.watch(moduleDeviceStatusProvider(widget.moduleId));

    final mod = detailsAsync.valueOrNull?.module;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: ThermoScanAppBar(
        title: 'Device Verification',
        role: user?.role,
        showBack: true,
        onBack: () => context.go('/modules/${widget.moduleId}'),
        trailingAction: IconButton(
          tooltip: 'Communication Flow Help',
          icon: const Icon(Icons.help_outline_rounded, color: AppColors.primary),
          onPressed: () => _showCommunicationFlowModal(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text(
                'ESP32 Device Verification',
                style: AppTypography.h2,
              ),
              const SizedBox(height: 4),
              Text(
                'Verifying live Wi-Fi connectivity, safety interlocks and cloud sync',
                style: AppTypography.bodySmall,
              ),
              const SizedBox(height: 20),

              // Module Identity Summary Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                mod?.name ?? 'Photovoltaic Module',
                                style: AppTypography.h3,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'MAC: ${mod?.macAddress ?? 'Awaiting...'}',
                                style: AppTypography.dataValue.copyWith(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        statusAsync.when(
                          loading: () => const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          ),
                          error: (_, _) => _buildStatusChip(
                            'OFFLINE',
                            AppColors.errorBackground,
                            AppColors.errorBorder,
                            AppColors.error,
                          ),
                          data: (status) => status.isOnline
                              ? _buildStatusChip(
                                  'ONLINE',
                                  AppColors.successBackground,
                                  AppColors.successBorder,
                                  AppColors.success,
                                )
                              : _buildStatusChip(
                                  'AWAITING SYNC',
                                  AppColors.warningBackground,
                                  AppColors.warningBorder,
                                  AppColors.warning,
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Checklist Section
              Text(
                'System Initialization Checklist',
                style: AppTypography.h3,
              ),
              const SizedBox(height: 12),

              statusAsync.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                ),
                error: (err, _) => Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    'Failed to read device status: $err',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                ),
                data: (status) {
                  final sync = status.effectiveConfigurationSync;
                  final subAPassed = status.isConfigured;
                  final subBPassed = status.isConfigured &&
                      (sync.configAppliedVersion == sync.configVersion) &&
                      !sync.isFailed;
                  final subBWarning = status.isConfigured && sync.isFailed;
                  final subBLoading = status.isConfigured && !subBPassed && !sync.isFailed;
                  final step1Passed = subAPassed && subBPassed;
                  final step1Warning = subBWarning;
                  final step1Loading = !step1Passed && !step1Warning;

                  final step2Passed = status.isOnline;
                  final step2Loading = step1Passed && !step2Passed;

                  final step3Passed = status.waterAvailable == true;
                  final step3Warning = status.waterAvailable == false;
                  final step3Loading = step2Passed && status.waterAvailable == null;

                  final step4Passed = status.limitsCheckPassed;
                  final step4Loading = step2Passed && !step4Passed;

                  return Column(
                    children: [
                      // Item 1: Configuration Sync (Clean 2-step setup)
                      _buildTwoPhaseConfigCard(
                        title: '1. System Configuration & Setup',
                        description: step1Passed
                            ? 'Geometry saved in cloud and verified on ESP32.'
                            : (subAPassed
                                ? 'Configuration saved in cloud. Awaiting ESP32 confirmation.'
                                : 'Pending initial geometry configuration.'),
                        isPassed: step1Passed,
                        isWarning: step1Warning,
                        isLoading: step1Loading,
                        subAPassed: subAPassed,
                        subBPassed: subBPassed,
                        subBLoading: subBLoading,
                        subBWarning: subBWarning,
                        syncInfo: sync,
                      ),
                      const SizedBox(height: 10),

                      // Item 2: Wi-Fi & HTTPS REST Connection
                      _buildChecklistCard(
                        title: '2. Wi-Fi & HTTPS Connection',
                        description: status.isOnline
                            ? 'ESP32 connected. Telemetry sync acknowledged by cloud API.'
                            : 'Awaiting device ping. Ensure ESP32 is powered on and connected to Wi-Fi.',
                        isPassed: status.isOnline,
                        isLoading: step2Loading,
                        isWarning: false,
                        icon: Icons.wifi_rounded,
                      ),
                      const SizedBox(height: 10),

                      // Item 3: Capacitive Water Sensor
                      _buildChecklistCard(
                        title: '3. Water Reservoir Sensor',
                        description: status.waterAvailable == true
                            ? 'Water level: OK. Cleaning cycles permitted.'
                            : status.waterAvailable == false
                                ? 'Water level: Insufficient. Cleaning locked until tank refill.'
                                : 'Awaiting fluid level reading from capacitive probe.',
                        isPassed: step3Passed,
                        isWarning: step3Warning,
                        isLoading: step3Loading,
                        icon: Icons.water_drop_rounded,
                      ),
                      const SizedBox(height: 10),

                      // Item 4: Limit Switches & Thermal Camera
                      _buildChecklistCard(
                        title: '4. Hardware Safety & Radiometer',
                        description: status.limitsCheckPassed
                            ? 'Homing limit switches verified. Thermal sensor initialized.'
                            : 'Awaiting sensor self-test and rail homing sequence.',
                        isPassed: status.limitsCheckPassed,
                        isWarning: false,
                        isLoading: step4Loading,
                        icon: Icons.check_circle_outline_rounded,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),

              // Two Navigation Action Buttons (Back to Modules + Overview)
              Row(
                children: [
                  Expanded(
                    child: SecondaryButton(
                      label: 'Modules List',
                      icon: Icons.list_alt_rounded,
                      onPressed: () {
                        ref.invalidate(modulesListProvider);
                        context.go('/modules');
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PrimaryButton(
                      label: 'Module Overview',
                      icon: Icons.arrow_forward_rounded,
                      onPressed: () {
                        context.go('/modules/${widget.moduleId}');
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(
    String label,
    Color bg,
    Color border,
    Color text,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          color: text,
          fontWeight: FontWeight.w800,
          fontSize: 10,
        ),
      ),
    );
  }

  Widget _buildChecklistCard({
    required String title,
    required String description,
    required bool isPassed,
    required bool isWarning,
    bool isLoading = false,
    required IconData icon,
  }) {
    Color iconColor = AppColors.textSecondary;
    Color borderColor = AppColors.border;
    Widget statusWidget = const Icon(
      Icons.radio_button_unchecked_rounded,
      color: AppColors.textSecondary,
      size: 22,
    );

    if (isPassed) {
      iconColor = AppColors.success;
      borderColor = AppColors.successBorder;
      statusWidget = const Icon(
        Icons.check_circle_rounded,
        color: AppColors.success,
        size: 22,
      );
    } else if (isWarning) {
      iconColor = AppColors.warning;
      borderColor = AppColors.warningBorder;
      statusWidget = const Icon(
        Icons.warning_amber_rounded,
        color: AppColors.warning,
        size: 22,
      );
    } else if (isLoading) {
      iconColor = AppColors.primary;
      borderColor = AppColors.primary.withValues(alpha: 0.5);
      statusWidget = const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2.2,
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isPassed
                  ? AppColors.successBackground
                  : (isWarning
                      ? AppColors.warningBackground
                      : (isLoading
                          ? AppColors.primarySoft
                          : AppColors.background)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: AppTypography.bodySmall.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (isLoading)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Awaiting...',
                          style: AppTypography.caption.copyWith(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          statusWidget,
        ],
      ),
    );
  }

  Widget _buildTwoPhaseConfigCard({
    required String title,
    required String description,
    required bool isPassed,
    required bool isWarning,
    bool isLoading = false,
    required bool subAPassed,
    required bool subBPassed,
    bool subBLoading = false,
    required bool subBWarning,
    required ConfigurationSyncInfo syncInfo,
  }) {
    Color iconColor = AppColors.textSecondary;
    Color borderColor = AppColors.border;
    Widget statusWidget = const Icon(
      Icons.radio_button_unchecked_rounded,
      color: AppColors.textSecondary,
      size: 22,
    );

    if (isPassed) {
      iconColor = AppColors.success;
      borderColor = AppColors.successBorder;
      statusWidget = const Icon(
        Icons.check_circle_rounded,
        color: AppColors.success,
        size: 22,
      );
    } else if (isWarning) {
      iconColor = AppColors.warning;
      borderColor = AppColors.warningBorder;
      statusWidget = const Icon(
        Icons.warning_amber_rounded,
        color: AppColors.warning,
        size: 22,
      );
    } else if (isLoading) {
      iconColor = AppColors.primary;
      borderColor = AppColors.primary.withValues(alpha: 0.5);
      statusWidget = const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2.2,
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isPassed
                      ? AppColors.successBackground
                      : (isWarning
                          ? AppColors.warningBackground
                          : (isLoading
                              ? AppColors.primarySoft
                              : AppColors.background)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.tune_rounded, color: iconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: AppTypography.bodySmall.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (isLoading)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primarySoft,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Awaiting...',
                              style: AppTypography.caption.copyWith(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              statusWidget,
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                // Step 1: Cloud Settings Saved
                Row(
                  children: [
                    Icon(
                      subAPassed
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: subAPassed
                          ? AppColors.success
                          : AppColors.textSecondary,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Step 1: Cloud Settings Saved',
                            style: AppTypography.bodySmall.copyWith(
                              fontWeight: FontWeight.w600,
                              color: subAPassed
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                            ),
                          ),
                          Text(
                            subAPassed
                                ? 'Dimensions and limits registered'
                                : 'Awaiting geometry configuration',
                            style: AppTypography.caption.copyWith(
                              fontSize: 10.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      subAPassed ? 'Ready' : 'Pending',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: subAPassed
                            ? AppColors.success
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(height: 1),
                ),
                // Step 2: Device Synchronized
                Row(
                  children: [
                    subBLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppColors.primary,
                              ),
                            ),
                          )
                        : Icon(
                            subBPassed
                                ? Icons.check_circle_rounded
                                : (subBWarning
                                    ? Icons.warning_amber_rounded
                                    : Icons.radio_button_unchecked_rounded),
                            color: subBPassed
                                ? AppColors.success
                                : (subBWarning
                                    ? AppColors.warning
                                    : AppColors.textSecondary),
                            size: 18,
                          ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Step 2: Device Synchronized',
                            style: AppTypography.bodySmall.copyWith(
                              fontWeight: FontWeight.w600,
                              color: subBPassed
                                  ? AppColors.textPrimary
                                  : (subBWarning
                                      ? AppColors.warning
                                      : (subBLoading
                                          ? AppColors.primary
                                          : AppColors.textSecondary)),
                            ),
                          ),
                          Text(
                            subBPassed
                                ? 'Settings downloaded and applied to ESP32'
                                : (subBWarning
                                    ? 'Failed: ${syncInfo.configApplyError ?? "Error applying configuration"}'
                                    : (subBLoading
                                        ? 'Connecting to device and applying settings...'
                                        : 'Awaiting device to connect')),
                            style: AppTypography.caption.copyWith(
                              fontSize: 10.5,
                              color: subBWarning
                                  ? AppColors.warning
                                  : (subBLoading
                                      ? AppColors.primary
                                      : AppColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      subBPassed
                          ? 'Synced'
                          : (syncInfo.isFailed
                              ? 'Failed'
                              : (subBLoading ? 'Syncing...' : 'Pending')),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: subBPassed
                            ? AppColors.success
                            : (subBWarning
                                ? AppColors.warning
                                : (subBLoading
                                    ? AppColors.primary
                                    : AppColors.textSecondary)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

