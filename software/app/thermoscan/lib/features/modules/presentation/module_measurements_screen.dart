import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/core/widgets/top_app_bar.dart';
import 'package:thermoscan/features/auth/presentation/auth_controller.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';
import 'package:thermoscan/features/modules/presentation/modules_controller.dart';
import 'package:thermoscan/features/modules/presentation/widgets/module_sub_nav_bar.dart';

/// SCR-11: Module Details — Inspection History & Telemetry (Unified Timeline)
class ModuleMeasurementsScreen extends ConsumerStatefulWidget {
  const ModuleMeasurementsScreen({
    super.key,
    required this.moduleId,
    this.showAppBar = true,
  });

  final String moduleId;
  final bool showAppBar;

  @override
  ConsumerState<ModuleMeasurementsScreen> createState() =>
      _ModuleMeasurementsScreenState();
}

class ModuleMeasurementsView extends StatelessWidget {
  const ModuleMeasurementsView({
    super.key,
    required this.moduleId,
  });

  final String moduleId;

  @override
  Widget build(BuildContext context) {
    return ModuleMeasurementsScreen(
      moduleId: moduleId,
      showAppBar: false,
    );
  }
}

class _ModuleMeasurementsScreenState
    extends ConsumerState<ModuleMeasurementsScreen> {
  int _currentPage = 1;
  int? _selectedPanelFilter;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final detailsAsync = ref.watch(moduleDetailsProvider(widget.moduleId));
    final latestInspectionAsync =
        ref.watch(latestInspectionProvider(widget.moduleId));
    final allMeasurementsAsync =
        ref.watch(moduleMeasurementsProvider(widget.moduleId));

    final mod = detailsAsync.valueOrNull?.module;

    final content = RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        ref.invalidate(latestInspectionProvider(widget.moduleId));
        ref.invalidate(moduleMeasurementsProvider(widget.moduleId));
        ref.invalidate(inspectionMeasurementsPagedProvider);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Scan History',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Inspection History & Readings',
                        style: AppTypography.h2,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Recorded robotic scans, power output, and panel temperatures',
                        style: AppTypography.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            latestInspectionAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                  ),
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
                  'Failed to load inspection telemetry: $err',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ),
              data: (latestInspection) {
                final allMeasurements =
                    allMeasurementsAsync.valueOrNull ?? const <ModuleMeasurement>[];
                if ((latestInspection == null ||
                        latestInspection.inspection.id.isEmpty) &&
                    allMeasurements.isEmpty) {
                  return _buildEmptyState();
                }

                return _buildUnifiedInspectionTimeline(
                  latestInspection: latestInspection,
                  allMeasurements: allMeasurements,
                  mod: mod,
                );
              },
            ),
          ],
        ),
      ),
    );

    if (!widget.showAppBar) {
      return content;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: ThermoScanAppBar(
        title: mod != null
            ? '${mod.name} Scan History'
            : 'Scan & Measurement History',
        role: user?.role,
        showBack: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Sub-navigation bar
            if (mod != null)
              ModuleSubNavBar(
                moduleId: widget.moduleId,
                currentTab: 'measurements',
                canManageAccess: mod.permissions.canManageAccess,
                isPendingConfig: mod.isPendingConfiguration,
              ),

            // Content body
            Expanded(child: content),
          ],
        ),
      ),
    );
  }

  Widget _buildUnifiedInspectionTimeline({
    required LatestInspection? latestInspection,
    required List<ModuleMeasurement> allMeasurements,
    required PvModule? mod,
  }) {
    // 1. Group measurements by inspectionId
    final Map<String, List<ModuleMeasurement>> grouped = {};
    for (final m in allMeasurements) {
      final key = m.inspectionId.isNotEmpty ? m.inspectionId : 'unlinked';
      grouped.putIfAbsent(key, () => []).add(m);
    }

    // 2. Ensure latestInspection is represented in grouped map
    final latestId = (latestInspection != null &&
            latestInspection.inspection.id.isNotEmpty)
        ? latestInspection.inspection.id
        : null;
    if (latestId != null) {
      grouped.putIfAbsent(latestId, () => []);
    }

    // 3. Sort entries: latest inspection first, then descending by most recent measurement timestamp
    final entries = grouped.entries.toList()
      ..sort((a, b) {
        if (latestId != null) {
          if (a.key == latestId) return -1;
          if (b.key == latestId) return 1;
        }
        final maxA = _maxMeasuredAt(a.value);
        final maxB = _maxMeasuredAt(b.value);
        if (maxA != null && maxB != null) {
          return maxB.compareTo(maxA);
        }
        return b.key.compareTo(a.key);
      });

    final pCount = mod?.panelCount ?? 1;
    final pLen = mod?.panelLengthCm ?? 100.0;
    final pSpc = mod?.panelSpacingCm ?? 2.0;
    final totalRail = mod?.calculatedTotalLengthCm ?? pLen;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Level 1: Array Architecture Badge (Compact)
        if (mod != null || allMeasurements.isNotEmpty) ...[
          Container(
            key: const Key('history_array_header'),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primarySoft.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.solar_power_outlined,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Array: ${mod?.name ?? "Solar Array"}',
                        style: AppTypography.caption.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        '$pCount ${pCount > 1 ? "panels" : "panel"} (${pLen.toStringAsFixed(0)} cm/panel${pCount > 1 ? " • Gap ${pSpc.toStringAsFixed(0)} cm" : ""} • Rail ${totalRail.toStringAsFixed(0)} cm)',
                        style: AppTypography.caption.copyWith(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        // Section Title: Inspection History (Grouped by Inspection)
        if (allMeasurements.isNotEmpty) ...[
          Row(
            children: [
              const Icon(
                Icons.history_rounded,
                color: AppColors.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Recorded Inspection Scans',
                  style: AppTypography.h3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'All recorded scans and temperature readings grouped by scan session',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Timeline of Inspection Cards
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: entries.length,
          separatorBuilder: (_, _) => const SizedBox(height: 14),
          itemBuilder: (context, index) {
            final entry = entries[index];
            final inspectionId = entry.key;
            final isLatest = latestId != null && inspectionId == latestId;
            final groupMeasurements = List<ModuleMeasurement>.from(entry.value)
              ..sort((a, b) => a.xPositionCm.compareTo(b.xPositionCm));

            return _buildInspectionHistoryGroupCard(
              inspectionId: inspectionId,
              measurements: groupMeasurements,
              isLatest: isLatest,
              latestInspection: isLatest ? latestInspection : null,
              mod: mod,
            );
          },
        ),
      ],
    );
  }

  DateTime? _maxMeasuredAt(List<ModuleMeasurement> items) {
    DateTime? maxDt;
    for (final m in items) {
      final dt = DateTime.tryParse(m.measuredAt);
      if (dt != null && (maxDt == null || dt.isAfter(maxDt))) {
        maxDt = dt;
      }
    }
    return maxDt;
  }

  String _formatReadableTimestamp(String? isoString) {
    if (isoString == null || isoString.isEmpty) return 'N/A';
    final dt = DateTime.tryParse(isoString)?.toLocal();
    if (dt == null) return isoString;

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final monthName = months[dt.month - 1];
    final day = dt.day.toString().padLeft(2, '0');
    final year = dt.year;

    final hour = dt.hour;
    final min = dt.minute.toString().padLeft(2, '0');
    final ampm = hour >= 12 ? 'PM' : 'AM';
    final h12 = hour % 12 == 0 ? 12 : hour % 12;

    return '$monthName $day, $year · $h12:$min $ampm';
  }

  Widget _buildInspectionHistoryGroupCard({
    required String inspectionId,
    required List<ModuleMeasurement> measurements,
    required bool isLatest,
    required LatestInspection? latestInspection,
    required PvModule? mod,
  }) {
    final shortId = inspectionId.length > 8
        ? '${inspectionId.substring(0, 8)}...'
        : inspectionId;

    final latestDt = (isLatest && latestInspection != null)
        ? (DateTime.tryParse(latestInspection.inspection.createdAt) ??
            _maxMeasuredAt(measurements))
        : _maxMeasuredAt(measurements);

    final dateLabel = latestDt != null
        ? _formatReadableTimestamp(latestDt.toIso8601String())
        : (measurements.isNotEmpty
            ? _formatReadableTimestamp(measurements.first.measuredAt)
            : 'N/A');

    final statusStr = (isLatest && latestInspection != null
            ? latestInspection.inspection.status
            : 'completed')
        .toUpperCase();

    final scanType = (isLatest &&
            latestInspection != null &&
            latestInspection.inspection.type.isNotEmpty)
        ? '${latestInspection.inspection.type[0].toUpperCase()}${latestInspection.inspection.type.substring(1)} Scan'
        : 'Robotic Scan';

    final baselineTemp =
        isLatest ? latestInspection?.inspection.baselineTemperatureC : null;

    final Map<int, List<ModuleMeasurement>> byPanel = {};
    for (final m in measurements) {
      final p = m.panelIndex ??
          (mod != null
              ? mod.resolvePanelPosition(m.xPositionCm).panelIndex
              : 1);
      final effectiveP = p > 0 ? p : 1;
      byPanel.putIfAbsent(effectiveP, () => []).add(m);
    }
    final sortedPanels = byPanel.keys.toList()..sort();

    final peakTemp = measurements.isNotEmpty
        ? measurements.map((m) => m.maxTemperatureC).reduce(math.max)
        : null;
    final deltaT = (peakTemp != null && baselineTemp != null)
        ? (peakTemp - baselineTemp)
        : null;

    final validPowers =
        measurements.map((m) => m.powerW).whereType<double>().toList();
    final validVolts =
        measurements.map((m) => m.voltageV).whereType<double>().toList();
    final validAmps =
        measurements.map((m) => m.currentA).whereType<double>().toList();
    final avgPower = validPowers.isNotEmpty
        ? validPowers.reduce((a, b) => a + b) / validPowers.length
        : null;
    final avgVolt = validVolts.isNotEmpty
        ? validVolts.reduce((a, b) => a + b) / validVolts.length
        : null;
    final avgAmp = validAmps.isNotEmpty
        ? validAmps.reduce((a, b) => a + b) / validAmps.length
        : null;

    final totalHotspots = (isLatest && latestInspection != null)
        ? latestInspection.confirmedAnomalies.length
        : 0;

    final totalFramesCount = measurements.isNotEmpty
        ? measurements.length
        : (isLatest && latestInspection != null
            ? latestInspection.totalMeasurements
            : 0);

    return Container(
      key: Key('history_group_$inspectionId'),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLatest ? AppColors.primary : AppColors.border,
          width: isLatest ? 1.5 : 1.0,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isLatest
                            ? AppColors.primarySoft
                            : AppColors.background,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isLatest
                            ? Icons.layers_outlined
                            : Icons.calendar_today_rounded,
                        color: isLatest
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  isLatest
                                      ? 'Active Inspection'
                                      : 'Inspection $shortId',
                                  style: AppTypography.caption.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isLatest) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primarySoft,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'LATEST',
                                    style: AppTypography.caption.copyWith(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 9,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isLatest && measurements.isEmpty
                                ? 'Baseline: ${baselineTemp != null ? "${baselineTemp.toStringAsFixed(1)}°C" : "N/A"}'
                                : '$dateLabel • $scanType${baselineTemp != null ? " • Baseline: ${baselineTemp.toStringAsFixed(1)}°C" : ""}',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusStr == 'COMPLETED'
                      ? AppColors.successBackground
                      : AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusStr,
                  style: AppTypography.caption.copyWith(
                    color: statusStr == 'COMPLETED'
                        ? AppColors.success
                        : AppColors.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),

          // Executive Metrics Strip (when telemetry is recorded)
          if (measurements.isNotEmpty || (avgPower != null || peakTemp != null)) ...[
            const SizedBox(height: 12),
            _buildExecutiveMetricsStrip(
              avgPower: avgPower,
              avgVolt: avgVolt,
              avgAmp: avgAmp,
              peakTemp: peakTemp,
              deltaT: deltaT,
              totalFrames: totalFramesCount,
              hotspotCount: totalHotspots,
            ),
          ],

          // Level 2: Panel Accordions
          if (sortedPanels.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...sortedPanels.map((p) => _buildPanelAccordion(
                  inspectionId: inspectionId,
                  panelIndex: p,
                  panelMeasurements: byPanel[p]!,
                  mod: mod,
                  latestInspection: isLatest ? latestInspection : null,
                )),
          ],

          // Level 3: Paginated frames (when byPanel is empty, e.g. test 630)
          if (isLatest && latestInspection != null && byPanel.isEmpty) ...[
            const SizedBox(height: 8),
            _buildPaginatedInspectionBody(latestInspection, mod),
          ],
        ],
      ),
    );
  }

  Widget _buildExecutiveMetricsStrip({
    required double? avgPower,
    required double? avgVolt,
    required double? avgAmp,
    required double? peakTemp,
    required double? deltaT,
    required int totalFrames,
    required int hotspotCount,
  }) {
    final hasElec = avgPower != null || avgVolt != null || avgAmp != null;
    final powerText =
        avgPower != null ? '${avgPower.toStringAsFixed(3)} W' : 'N/A';
    final voltAmpText = (avgVolt != null && avgAmp != null)
        ? '${avgVolt.toStringAsFixed(3)}V · ${avgAmp.toStringAsFixed(3)}A'
        : (hasElec ? 'Partial' : 'No Elec');

    final tempText =
        peakTemp != null ? '${peakTemp.toStringAsFixed(1)}°C' : 'N/A';
    final deltaText = deltaT != null
        ? (deltaT > 0
            ? '+${deltaT.toStringAsFixed(1)}°C above normal'
            : '${deltaT.toStringAsFixed(1)}°C above normal')
        : 'Normal';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // Yield / Power
          Expanded(
            child: _buildMetricStripItem(
              icon: Icons.bolt_rounded,
              iconColor: AppColors.primary,
              label: 'Power',
              value: powerText,
              sublabel: voltAmpText,
            ),
          ),
          Container(width: 1, height: 28, color: AppColors.border),
          // Peak Temp
          Expanded(
            child: _buildMetricStripItem(
              icon: Icons.thermostat_rounded,
              iconColor: (deltaT != null && deltaT > 5.0)
                  ? AppColors.error
                  : AppColors.secondary,
              label: 'Peak Temp',
              value: tempText,
              sublabel: deltaText,
            ),
          ),
          Container(width: 1, height: 28, color: AppColors.border),
          // Frames
          Expanded(
            child: _buildMetricStripItem(
              icon: Icons.photo_camera_back_outlined,
              iconColor: AppColors.textSecondary,
              label: 'Readings',
              value: '$totalFrames',
              sublabel: 'Readings recorded',
            ),
          ),
          Container(width: 1, height: 28, color: AppColors.border),
          // Health / Anomalies
          Expanded(
            child: _buildMetricStripItem(
              icon: hotspotCount > 0
                  ? Icons.warning_amber_rounded
                  : Icons.check_circle_outline_rounded,
              iconColor:
                  hotspotCount > 0 ? AppColors.error : AppColors.success,
              label: 'Health',
              value: hotspotCount > 0
                  ? '$hotspotCount Hotspot${hotspotCount > 1 ? "s" : ""}'
                  : 'Normal',
              sublabel: hotspotCount > 0 ? 'Action req.' : '0 Anomalies',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricStripItem({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required String sublabel,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: iconColor),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  label,
                  style: AppTypography.caption.copyWith(
                    fontSize: 9.5,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppTypography.caption.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            sublabel,
            style: AppTypography.caption.copyWith(
              fontSize: 8.5,
              color: AppColors.textSecondary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildPanelAccordion({
    required String inspectionId,
    required int panelIndex,
    required List<ModuleMeasurement> panelMeasurements,
    required PvModule? mod,
    required LatestInspection? latestInspection,
  }) {
    final p = panelIndex;
    final pMinX =
        panelMeasurements.map((m) => m.xPositionCm).reduce(math.min);
    final pMaxX =
        panelMeasurements.map((m) => m.xPositionCm).reduce(math.max);
    final pPeak =
        panelMeasurements.map((m) => m.maxTemperatureC).reduce(math.max);

    final pb = mod != null
        ? mod.getPanelBounds(p)
        : (startCm: pMinX, endCm: pMaxX);

    InspectionPanelResult? pRes;
    final pResults = latestInspection?.panelResults;
    if (pResults != null) {
      for (final r in pResults) {
        if (r.panelIndex == p) {
          pRes = r;
          break;
        }
      }
    }
    final bTemp = pRes?.baselineTemperatureC ??
        latestInspection?.inspection.baselineTemperatureC;
    final baselineStr = bTemp != null
        ? ' • Baseline: ${bTemp.toStringAsFixed(1)}°C'
        : ' • Baseline: N/A';

    ModuleMeasurement? elecMeas;
    for (final pm in panelMeasurements) {
      if (pm.voltageV != null || pm.currentA != null || pm.powerW != null) {
        elecMeas = pm;
        break;
      }
    }
    final elecStr = elecMeas != null
        ? ' • Electrical Output: ${elecMeas.voltageV?.toStringAsFixed(3) ?? "N/A"}V · ${elecMeas.currentA?.toStringAsFixed(3) ?? "N/A"}A · ${elecMeas.powerW?.toStringAsFixed(3) ?? "N/A"}W'
        : '';

    final panelHotspots = latestInspection?.confirmedAnomalies.where((a) {
          if (a.panelIndex != null) return a.panelIndex == p;
          return a.xPositionCm >= pb.startCm && a.xPositionCm <= pb.endCm;
        }).length ??
        0;
    final hotspotSummaryStr =
        panelHotspots > 0 ? ' • Hotspots: $panelHotspots' : '';

    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: panelHotspots > 0
                    ? AppColors.errorBorder
                    : AppColors.border,
              ),
            ),
            child: ExpansionTile(
              key: Key('panel_accordion_${inspectionId}_$p'),
              initiallyExpanded: p == 1,
              tilePadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 2,
              ),
              childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              leading: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: panelHotspots > 0
                      ? AppColors.errorBackground
                      : AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'P$p',
                  style: TextStyle(
                    color: panelHotspots > 0
                        ? AppColors.error
                        : AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Panel $p (${pb.startCm.toStringAsFixed(0)} to ${pb.endCm.toStringAsFixed(0)} cm along track)',
                      style: AppTypography.caption.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (panelHotspots > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.errorBackground,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: AppColors.errorBorder,
                        ),
                      ),
                      child: Text(
                        '$panelHotspots HOTSPOT${panelHotspots > 1 ? "S" : ""}',
                        style: const TextStyle(
                          color: AppColors.error,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
              subtitle: Text(
                '${panelMeasurements.length} frames • Peak: ${pPeak.toStringAsFixed(1)}°C$baselineStr$elecStr$hotspotSummaryStr',
                style: AppTypography.caption.copyWith(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                ),
              ),
              children: panelMeasurements.map((m) {
                final isConfirmed = latestInspection != null &&
                    latestInspection.confirmedAnomalies.any(
                      (a) =>
                          a.originMeasurementId == m.id ||
                          a.confirmingMeasurementIds.contains(m.id) ||
                          (a.originMeasurementId.isEmpty &&
                              a.confirmingMeasurementIds.isEmpty &&
                              (a.xPositionCm - m.xPositionCm).abs() <= 1.0),
                    );
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _buildPaginatedStepTile(m, isConfirmed),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaginatedInspectionBody(
    LatestInspection latestInspection,
    PvModule? mod,
  ) {
    final insp = latestInspection.inspection;
    final pagedAsync = ref.watch(inspectionMeasurementsPagedProvider((
      moduleId: widget.moduleId,
      inspectionId: insp.id,
      page: _currentPage,
      limit: 10,
      panelIndex: _selectedPanelFilter,
    )));
    final panelCount = mod?.panelCount ?? 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (panelCount > 1) ...[
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildPaginatedPanelFilterChip(
                  label: 'All ($panelCount)',
                  panelIndex: null,
                ),
                for (var p = 1; p <= panelCount; p++) ...[
                  const SizedBox(width: 6),
                  _buildPaginatedPanelFilterChip(
                    label: 'Panel $p',
                    panelIndex: p,
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        pagedAsync.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          ),
          error: (err, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Failed to load inspection measurements: $err',
              style: AppTypography.caption.copyWith(color: AppColors.error),
            ),
          ),
          data: (paged) {
            final measurements =
                List<ModuleMeasurement>.from(paged.measurements)
                  ..sort((a, b) => a.xPositionCm.compareTo(b.xPositionCm));

            if (measurements.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    'No measurements in this inspection.',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              );
            }

            return Column(
              children: [
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: measurements.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (ctx, idx) {
                    final m = measurements[idx];
                    final isConfirmed = latestInspection.confirmedAnomalies
                        .any(
                      (a) =>
                          a.originMeasurementId == m.id ||
                          a.confirmingMeasurementIds.contains(m.id) ||
                          (a.originMeasurementId.isEmpty &&
                              a.confirmingMeasurementIds.isEmpty &&
                              (a.xPositionCm - m.xPositionCm).abs() <= 1.0),
                    );
                    return _buildPaginatedStepTile(m, isConfirmed);
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Page ${paged.page} of ${paged.totalPages} (${paged.totalCount} items)',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Row(
                      children: [
                        OutlinedButton(
                          key: const Key('btn_prev_page'),
                          onPressed: paged.page > 1
                              ? () => setState(() => _currentPage--)
                              : null,
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                          ),
                          child: const Text('Previous'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          key: const Key('btn_next_page'),
                          onPressed: paged.hasNextPage
                              ? () => setState(() => _currentPage++)
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                          ),
                          child: const Text('Next'),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildPaginatedPanelFilterChip({
    required String label,
    required int? panelIndex,
  }) {
    final isSelected = _selectedPanelFilter == panelIndex;
    return InkWell(
      key: Key('paged_panel_filter_${panelIndex ?? "all"}'),
      onTap: () {
        setState(() {
          _selectedPanelFilter = panelIndex;
          _currentPage = 1;
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.caption.copyWith(
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildPaginatedStepTile(ModuleMeasurement m, bool isConfirmed) {
    final vText =
        m.voltageV != null ? '${m.voltageV!.toStringAsFixed(3)}V' : 'N/A';
    final iText =
        m.currentA != null ? '${m.currentA!.toStringAsFixed(3)}A' : 'N/A';
    final pText =
        m.powerW != null ? '${m.powerW!.toStringAsFixed(3)}W' : 'N/A';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isConfirmed ? AppColors.errorBorder : AppColors.border,
          width: isConfirmed ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'X = ${m.xPositionCm.toStringAsFixed(1)} cm',
                style: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              if (m.panelIndex != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'P${m.panelIndex}${m.localXPositionCm != null ? " • Local: ${m.localXPositionCm!.toStringAsFixed(0)} cm" : ""}',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              if (isConfirmed) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.errorBackground,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.errorBorder),
                  ),
                  child: Text(
                    'HOTSPOT',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.error,
                      fontWeight: FontWeight.w800,
                      fontSize: 9,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: [
                  _buildMetricChip(
                    'Peak',
                    '${m.maxTemperatureC.toStringAsFixed(1)}°C',
                    isConfirmed ? AppColors.error : AppColors.textPrimary,
                  ),
                  _buildMetricChip(
                    'Volt',
                    vText,
                    AppColors.textSecondary,
                  ),
                  _buildMetricChip(
                    'Curr',
                    iText,
                    AppColors.textSecondary,
                  ),
                  _buildMetricChip(
                    'Power',
                    pText,
                    AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricChip(String label, String value, Color valueColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: AppTypography.caption.copyWith(
              fontSize: 10,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            value,
            style: AppTypography.dataValue.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.sensors_outlined,
            size: 44,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 14),
          Text(
            'No Inspection Records Yet',
            style: AppTypography.h3,
          ),
          const SizedBox(height: 6),
          Text(
            'Thermal acquisitions and electrical measurements will appear here once the ESP32 performs its scheduled solar window scans.',
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall,
          ),
        ],
      ),
    );
  }
}
