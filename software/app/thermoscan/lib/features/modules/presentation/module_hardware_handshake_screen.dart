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

/// Post-installation Hardware Handshake & Checklist Screen (Abordagem A)
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

class _ModuleHardwareHandshakeScreenState
    extends ConsumerState<ModuleHardwareHandshakeScreen> {
  Timer? _pollTimer;

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
        title: 'Hardware Handshake',
        role: user?.role,
        showBack: true,
        onBack: () => context.go('/modules/${widget.moduleId}'),
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
                'ESP32 Hardware Handshake',
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
                  final subBWarning = status.isConfigured && !subBPassed;
                  final step1Passed = subAPassed && subBPassed;
                  final step1Warning = subAPassed && !subBPassed;

                  return Column(
                    children: [
                      // Item 1: Configuration Sync (Two-Phase Verification)
                      _buildTwoPhaseConfigCard(
                        title: '1. Configuration Sync',
                        description: step1Passed
                            ? 'Geometria confirmada no servidor e sincronizada na ESP32.'
                            : (subAPassed
                                ? 'Configuração salva no servidor. Aguardando confirmação da ESP32.'
                                : 'Pendente de configuração inicial de geometria.'),
                        isPassed: step1Passed,
                        isWarning: step1Warning,
                        subAPassed: subAPassed,
                        subBPassed: subBPassed,
                        subBWarning: subBWarning,
                        syncInfo: sync,
                      ),
                      const SizedBox(height: 10),

                      // Item 2: Wi-Fi & HTTPS REST Handshake
                      _buildChecklistCard(
                        title: '2. Wi-Fi & HTTPS REST Connection',
                        description: status.isOnline
                            ? 'ESP32 connected. Telemetry sync acknowledged by API Go.'
                            : 'Awaiting device ping. Ensure ESP32 is powered on and connected to local Wi-Fi.',
                        isPassed: status.isOnline,
                        isWarning: !status.isOnline,
                        icon: Icons.wifi_rounded,
                      ),
                      const SizedBox(height: 10),

                      // Item 3: Capacitive Water Sensor
                      _buildChecklistCard(
                        title: '3. Binary Water Level Sensor',
                        description: status.waterAvailable == true
                            ? 'Water level: OK (water_available=true). Wash cycles permitted.'
                            : status.waterAvailable == false
                                ? 'Water level: Insufficient. Cleaning cycles locked until tank refill.'
                                : 'Awaiting first water reserve reading from capacitive probe.',
                        isPassed: status.waterAvailable == true,
                        isWarning: status.waterAvailable == false,
                        icon: Icons.water_drop_rounded,
                      ),
                      const SizedBox(height: 10),

                      // Item 4: Limit Switches & Thermal Camera
                      _buildChecklistCard(
                        title: '4. Hardware Interlocks & Radiometer',
                        description: status.limitsCheckPassed
                            ? 'Microswitches NC homed. MLX90640 radiometric sensor initialized.'
                            : 'Awaiting sensor self-test and rail homing sequence.',
                        isPassed: status.limitsCheckPassed,
                        isWarning: false,
                        icon: Icons.check_circle_outline_rounded,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),

              // Finish & Proceed Button
              PrimaryButton(
                label: 'View Module Overview',
                icon: Icons.arrow_forward_rounded,
                onPressed: () {
                  context.pushReplacement('/modules/${widget.moduleId}');
                },
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
                      : AppColors.background),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.bodySmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
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
    required bool subAPassed,
    required bool subBPassed,
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
                          : AppColors.background),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.tune_rounded, color: iconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.bodySmall.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
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
                // Sub-item A: Salvo no Servidor
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
                      child: Text(
                        'Sub-item A: Salvo no Servidor',
                        style: AppTypography.bodySmall.copyWith(
                          fontWeight: FontWeight.w600,
                          color: subAPassed
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    Text(
                      subAPassed ? 'Configurado' : 'Pendente',
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
                // Sub-item B: Confirmado na ESP32
                Row(
                  children: [
                    Icon(
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
                            'Sub-item B: Confirmado na ESP32',
                            style: AppTypography.bodySmall.copyWith(
                              fontWeight: FontWeight.w600,
                              color: subBPassed
                                  ? AppColors.textPrimary
                                  : (subBWarning
                                      ? AppColors.warning
                                      : AppColors.textSecondary),
                            ),
                          ),
                          if (subBWarning) ...[
                            const SizedBox(height: 2),
                            Text(
                              syncInfo.isFailed
                                  ? 'Falha: ${syncInfo.configApplyError ?? "Erro ao aplicar"}'
                                  : 'Aguardando sincronização (v${syncInfo.configAppliedVersion} no device, v${syncInfo.configVersion} no server)',
                              style: AppTypography.caption.copyWith(
                                fontSize: 10.5,
                                color: AppColors.warning,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Text(
                      subBPassed
                          ? 'v${syncInfo.configAppliedVersion} OK'
                          : (syncInfo.isFailed ? 'Erro' : 'Pendente'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: subBPassed
                            ? AppColors.success
                            : (subBWarning
                                ? AppColors.warning
                                : AppColors.textSecondary),
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
