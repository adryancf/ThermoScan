import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/core/widgets/app_buttons.dart';
import 'package:thermoscan/core/widgets/status_chips.dart';
import 'package:thermoscan/core/widgets/top_app_bar.dart';
import 'package:thermoscan/features/auth/presentation/auth_controller.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';
import 'package:thermoscan/features/modules/presentation/modules_controller.dart';
import 'package:thermoscan/features/modules/presentation/widgets/radiometric_scan_card.dart';
import 'package:thermoscan/features/modules/presentation/widgets/thermal_panorama_painter.dart';

/// SCR-10 Dedicated Screen: Thermal Inspection Studio
///
/// Provides a dedicated workspace for high-resolution radiometric MLX90640 analysis,
/// thermal gradient exploration, multi-frame traversal (F1..Fn), and dual-frame anomaly confirmation.
class ModuleThermalInspectionScreen extends ConsumerWidget {
  const ModuleThermalInspectionScreen({
    super.key,
    required this.moduleId,
  });

  final String moduleId;

  String _formatIsoDate(String? iso) {
    if (iso == null || iso.isEmpty) return 'No timestamp';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final d = dt.toLocal();
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    final year = d.year;
    final hour = d.hour.toString().padLeft(2, '0');
    final minute = d.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final detailsAsync = ref.watch(moduleDetailsProvider(moduleId));
    final measurementsAsync = ref.watch(moduleMeasurementsProvider(moduleId));
    final latestInspectionAsync = ref.watch(latestInspectionProvider(moduleId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: ThermoScanAppBar(
        title: 'Thermal Inspection Studio',
        role: user?.role,
        showBack: true,
        onBack: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/modules/$moduleId');
          }
        },
        trailingAction: IconButton(
          tooltip: 'Refresh Studio Data',
          icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
          onPressed: () {
            ref.invalidate(moduleDetailsProvider(moduleId));
            ref.invalidate(moduleMeasurementsProvider(moduleId));
            ref.invalidate(latestInspectionProvider(moduleId));
          },
        ),
      ),
      body: detailsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: AppColors.error,
                    size: 44,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Failed to Load Module Telemetry',
                    style: AppTypography.h3,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    err.toString(),
                    style: AppTypography.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  PrimaryButton(
                    label: 'Retry',
                    fullWidth: false,
                    onPressed: () {
                      ref.invalidate(moduleDetailsProvider(moduleId));
                      ref.invalidate(moduleMeasurementsProvider(moduleId));
                      ref.invalidate(latestInspectionProvider(moduleId));
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        data: (details) {
          final mod = details.module;
          final measurements =
              measurementsAsync.valueOrNull ?? const <ModuleMeasurement>[];
          final latestInspection = latestInspectionAsync.valueOrNull;
          final rawLatestMeasurement =
              measurements.isNotEmpty ? measurements.first : null;
          final currentMeasurements = filterMeasurementsForCurrentInspection(
            measurements: measurements,
            latestInspection: latestInspection,
            latestMeasurement: rawLatestMeasurement,
          );
          final latestMeasurement = currentMeasurements.isNotEmpty
              ? currentMeasurements.first
              : rawLatestMeasurement;

          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async {
              ref.invalidate(moduleDetailsProvider(moduleId));
              ref.invalidate(moduleMeasurementsProvider(moduleId));
              ref.invalidate(latestInspectionProvider(moduleId));
              await ref.read(moduleDetailsProvider(moduleId).future);
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Studio Header Card
                  _buildStudioHeader(
                    context,
                    mod: mod,
                    latestMeasurement: latestMeasurement,
                    latestInspection: latestInspection,
                    totalMeasurements: currentMeasurements.length,
                  ),
                  const SizedBox(height: 16),

                  // 2. High-Precision Radiometric Scan Card (SCR-10 Studio)
                  RadiometricScanCard(
                    module: mod,
                    latestMeasurement: latestMeasurement,
                    latestInspection: latestInspection,
                    measurements: measurementsAsync.valueOrNull,
                    initiallyExpanded: true,
                  ),
                  const SizedBox(height: 20),

                  // 3. Technical Studio Guide & Information Card
                  _buildTechnicalGuideCard(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStudioHeader(
    BuildContext context, {
    required PvModule mod,
    required ModuleMeasurement? latestMeasurement,
    required LatestInspection? latestInspection,
    required int totalMeasurements,
  }) {
    final confirmedCount = latestInspection?.confirmedAnomalies.length ?? 0;
    final lastSyncTimestamp = latestInspection?.inspection.finishedAt ??
        latestMeasurement?.measuredAt;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.thermostat_auto_rounded,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mod.name,
                      style: AppTypography.h3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'MAC: ${mod.macAddress} • ${mod.panelCount ?? 1} panel(s)',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(
                isActive: mod.isActive,
                activeLabel: 'Operational',
                inactiveLabel: 'Disabled',
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              _buildMetricBadge(
                icon: Icons.filter_frames_rounded,
                label: 'Frames Available',
                value: '$totalMeasurements frames',
              ),
              _buildMetricBadge(
                icon: Icons.warning_amber_rounded,
                label: 'Confirmed Hotspots',
                value: '$confirmedCount anomaly(s)',
                valueColor: confirmedCount > 0 ? AppColors.error : AppColors.success,
              ),
              _buildMetricBadge(
                icon: Icons.schedule_rounded,
                label: 'Last Inspection',
                value: _formatIsoDate(lastSyncTimestamp),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricBadge({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
          ),
          Text(
            value,
            style: AppTypography.caption.copyWith(
              color: valueColor ?? AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTechnicalGuideCard() {
    return Container(
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
            children: [
              const Icon(
                Icons.science_outlined,
                size: 20,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Radiometric Studio Inspection Guide',
                style: AppTypography.h3.copyWith(fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildGuideItem(
            title: 'MLX90640 Radiometric Array (32×24)',
            description:
                'Every pixel corresponds to an calibrated radiometric temperature reading (768 points per frame). Color ramps scale automatically between ambient cold and peak hot spots.',
          ),
          const SizedBox(height: 10),
          _buildGuideItem(
            title: 'Dual-Frame Persistence Confirmation',
            description:
                'To eliminate false positives caused by momentary cloud edges, glints, or transient specular reflection, anomalies require thermal persistence across consecutive frames before confirmation.',
          ),
          const SizedBox(height: 10),
          _buildGuideItem(
            title: 'Interactive Studio Exploration',
            description:
                'Toggle zoom mode to view full frame dimensions or crop to active PV surface. Click on frame indicators (F1..Fn) or individual cells in the matrix to inspect exact telemetry at that coordinate.',
          ),
        ],
      ),
    );
  }

  Widget _buildGuideItem({
    required String title,
    required String description,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.bodySmall.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          description,
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
