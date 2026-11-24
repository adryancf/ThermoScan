import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/core/widgets/top_app_bar.dart';
import 'package:thermoscan/features/auth/presentation/auth_controller.dart';
import 'package:thermoscan/features/modules/domain/inspection_routine_bundle.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';
import 'package:thermoscan/features/modules/presentation/modules_controller.dart';
import 'package:thermoscan/features/modules/presentation/widgets/module_sub_nav_bar.dart';
import 'package:thermoscan/features/modules/presentation/widgets/thermal_panorama_painter.dart';

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
  bool _showOnlyValid = true;
  bool _onlyWithHotspots = false;
  int _visibleBundlesCount = 8;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final detailsAsync = ref.watch(moduleDetailsProvider(widget.moduleId));
    final latestInspectionAsync =
        ref.watch(latestInspectionProvider(widget.moduleId));
    final allMeasurementsAsync =
        ref.watch(moduleMeasurementsProvider(widget.moduleId));
    final inspectionsAsync =
        ref.watch(moduleInspectionsProvider(widget.moduleId));
    final cleaningsAsync =
        ref.watch(moduleCleaningsProvider(widget.moduleId));

    final mod = detailsAsync.valueOrNull?.module;
    final inspectionsList =
        inspectionsAsync.valueOrNull ?? const <ModuleInspection>[];
    final cleaningsList =
        cleaningsAsync.valueOrNull ?? const <ModuleCleaning>[];
    final inspectionsMap = {for (var i in inspectionsList) i.id: i};

    final content = RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        ref.invalidate(latestInspectionProvider(widget.moduleId));
        ref.invalidate(moduleMeasurementsProvider(widget.moduleId));
        ref.invalidate(moduleInspectionsProvider(widget.moduleId));
        ref.invalidate(moduleCleaningsProvider(widget.moduleId));
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
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Inspection History',
                        style: AppTypography.h2,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Robotic thermal scans & post-cleaning results',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

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
                final hasNonScheduledInspections =
                    inspectionsList.any((i) => i.status != 'scheduled');
                if ((latestInspection == null ||
                        latestInspection.inspection.id.isEmpty) &&
                    allMeasurements.isEmpty &&
                    !hasNonScheduledInspections) {
                  return _buildEmptyState();
                }

                return _buildUnifiedInspectionTimeline(
                  latestInspection: latestInspection,
                  allMeasurements: allMeasurements,
                  mod: mod,
                  inspectionsMap: inspectionsMap,
                  cleanings: cleaningsList,
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
    required Map<String, ModuleInspection> inspectionsMap,
    required List<ModuleCleaning> cleanings,
  }) {
    // 1. Group measurements by inspectionId
    final Map<String, List<ModuleMeasurement>> grouped = {};
    for (final m in allMeasurements) {
      final key = m.inspectionId.isNotEmpty ? m.inspectionId : 'unlinked';
      grouped.putIfAbsent(key, () => []).add(m);
    }

    // 2. Ensure latestInspection is represented in grouped map
    final rawLatestId = (latestInspection != null &&
            latestInspection.inspection.id.isNotEmpty)
        ? latestInspection.inspection.id
        : null;
    if (rawLatestId != null) {
      grouped.putIfAbsent(rawLatestId, () => []);
    }

    // 3. Build routine bundles for hierarchical post-cleaning nesting
    final rawBundles = InspectionRoutineBundle.buildBundles(
      allInspections: inspectionsMap.values.toList(),
      allCleanings: cleanings,
      allMeasurements: allMeasurements,
      latestInspection: latestInspection,
    );

    final bundles = rawBundles.where((b) {
      if (b.routineInspection.status == 'scheduled' &&
          b.routineMeasurements.isEmpty &&
          b.verificationMeasurements.isEmpty) {
        return false;
      }
      return true;
    }).toList();

    final latestActiveBundle =
        InspectionRoutineBundle.getLatestActiveBundle(bundles);
    final latestId =
        latestActiveBundle?.routineInspection.id ?? rawLatestId;

    final sortedBundles = List<InspectionRoutineBundle>.from(bundles)
      ..sort((a, b) {
        if (latestId != null) {
          if (a.routineInspection.id == latestId) return -1;
          if (b.routineInspection.id == latestId) return 1;
        }
        final maxA = _maxMeasuredAt(a.routineMeasurements);
        final maxB = _maxMeasuredAt(b.routineMeasurements);
        if (maxA != null && maxB != null) {
          return maxB.compareTo(maxA);
        }
        final dtA = maxA ??
            DateTime.tryParse(a.routineInspection.scheduledFor) ??
            DateTime.tryParse(a.routineInspection.createdAt);
        final dtB = maxB ??
            DateTime.tryParse(b.routineInspection.scheduledFor) ??
            DateTime.tryParse(b.routineInspection.createdAt);
        if (dtA != null && dtB != null) {
          return dtB.compareTo(dtA);
        }
        return b.routineInspection.id.compareTo(a.routineInspection.id);
      });

    final filteredBundles = _onlyWithHotspots
        ? sortedBundles.where(_bundleHasHotspots).toList()
        : sortedBundles;
    final visibleBundles =
        filteredBundles.take(_visibleBundlesCount).toList();
    final hasMoreBundles = filteredBundles.length > visibleBundles.length;

    // 4. Fallback unbundled entries when no bundles exist
    final entries = grouped.entries.toList()
      ..sort((a, b) {
        if (rawLatestId != null) {
          if (a.key == rawLatestId) return -1;
          if (b.key == rawLatestId) return 1;
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
          const SizedBox(height: 12),
        ],

        // Segmented Filter Control: All Scans | With Hotspots
        if (sortedBundles.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    key: const Key('filter_all_scans'),
                    borderRadius: BorderRadius.circular(9),
                    onTap: () {
                      setState(() {
                        _onlyWithHotspots = false;
                        _visibleBundlesCount = 8;
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: !_onlyWithHotspots
                            ? AppColors.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.history_rounded,
                            size: 14,
                            color: !_onlyWithHotspots
                                ? Colors.white
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'All Scans (${sortedBundles.length})',
                            style: AppTypography.caption.copyWith(
                              color: !_onlyWithHotspots
                                  ? Colors.white
                                  : AppColors.textSecondary,
                              fontWeight: FontWeight.w700,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: InkWell(
                    key: const Key('filter_hotspot_scans'),
                    borderRadius: BorderRadius.circular(9),
                    onTap: () {
                      setState(() {
                        _onlyWithHotspots = true;
                        _visibleBundlesCount = 8;
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _onlyWithHotspots
                            ? AppColors.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.local_fire_department_rounded,
                            size: 14,
                            color: _onlyWithHotspots
                                ? Colors.white
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'With Hotspots',
                            style: AppTypography.caption.copyWith(
                              color: _onlyWithHotspots
                                  ? Colors.white
                                  : AppColors.textSecondary,
                              fontWeight: FontWeight.w700,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        if (sortedBundles.isNotEmpty && visibleBundles.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Text(
                  'No scans with hotspots recorded.',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _onlyWithHotspots = false;
                      _visibleBundlesCount = 8;
                    });
                  },
                  child: const Text('Show All Scans'),
                ),
              ],
            ),
          )
        else ...[
          // Timeline of Inspection Cards
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: sortedBundles.isNotEmpty
                ? visibleBundles.length
                : entries.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (sortedBundles.isNotEmpty) {
                final bundle = visibleBundles[index];
                final inspectionId = bundle.routineInspection.id;
                final isLatest =
                    latestId != null && inspectionId == latestId;
                final groupMeasurements = bundle.routineMeasurements.isNotEmpty
                    ? bundle.routineMeasurements
                    : (bundle.restoredMeasurements.isNotEmpty
                        ? bundle.restoredMeasurements
                        : (grouped[inspectionId] ??
                            const <ModuleMeasurement>[]));

                return _buildInspectionHistoryGroupCard(
                  inspectionId: inspectionId,
                  measurements: groupMeasurements,
                  isLatest: isLatest,
                  latestInspection: isLatest ? latestInspection : null,
                  mod: mod,
                  inspectionsMap: inspectionsMap,
                  bundle: bundle,
                );
              }

              final entry = entries[index];
              final inspectionId = entry.key;
              final isLatest =
                  rawLatestId != null && inspectionId == rawLatestId;
              final groupMeasurements =
                  List<ModuleMeasurement>.from(entry.value)
                    ..sort((a, b) => a.xPositionCm.compareTo(b.xPositionCm));

              return _buildInspectionHistoryGroupCard(
                inspectionId: inspectionId,
                measurements: groupMeasurements,
                isLatest: isLatest,
                latestInspection: isLatest ? latestInspection : null,
                mod: mod,
                inspectionsMap: inspectionsMap,
              );
            },
          ),
          if (sortedBundles.isNotEmpty && hasMoreBundles) ...[
            const SizedBox(height: 14),
            Center(
              child: OutlinedButton.icon(
                key: const Key('load_older_scans_button'),
                onPressed: () {
                  setState(() {
                    _visibleBundlesCount += 8;
                  });
                },
                icon: const Icon(Icons.expand_more_rounded, size: 18),
                label: const Text('Load older scans'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildCompactMetricCell({
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTypography.caption.copyWith(
            fontSize: 10,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTypography.bodySmall.copyWith(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: valueColor ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  bool _bundleHasHotspots(InspectionRoutineBundle b) {
    return b.confirmedAnomalies.isNotEmpty ||
        b.hotspotSummaries.isNotEmpty ||
        b.hasPostCleaning;
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

  ({
    String label,
    Color bg,
    Color border,
    Color fg,
    IconData icon,
  }) _resolveHistoryOutcomeBadge({
    required InspectionRoutineBundle? bundle,
    required int totalHotspots,
    required String statusStr,
  }) {
    if (statusStr == 'CANCELLED') {
      return (
        label: 'Aborted',
        bg: AppColors.warningBackground,
        border: AppColors.warningBorder,
        fg: AppColors.warning,
        icon: Icons.cancel_outlined,
      );
    }
    if (statusStr == 'FAILED') {
      return (
        label: 'Failed',
        bg: AppColors.errorBackground,
        border: AppColors.errorBorder,
        fg: AppColors.error,
        icon: Icons.error_outline_rounded,
      );
    }
    if (statusStr == 'IN_PROGRESS') {
      return (
        label: 'In Progress',
        bg: AppColors.primarySoft,
        border: AppColors.primary.withValues(alpha: 0.3),
        fg: AppColors.primary,
        icon: Icons.sync_rounded,
      );
    }

    final summaries = bundle?.hotspotSummaries ?? const [];
    if (summaries.isNotEmpty) {
      final total = summaries.length;
      final resolved = bundle!.resolvedCount;
      final resolvedLater = bundle.resolvedLaterCount;
      final unresolved = bundle.unresolvedCount;
      final pending = bundle.pendingCount;
      final cleared = resolved + resolvedLater;

      if (resolvedLater > 0 &&
          unresolved == 0 &&
          resolved == 0 &&
          pending == 0) {
        return (
          label: 'Cleared in Later Scan',
          bg: AppColors.primarySoft,
          border: AppColors.primary.withValues(alpha: 0.3),
          fg: AppColors.primary,
          icon: Icons.verified_outlined,
        );
      }
      if (cleared == total && total > 0) {
        return (
          label: total == 1 ? '1 Hotspot · Resolved' : '$total/$total Resolved',
          bg: AppColors.successBackground,
          border: AppColors.successBorder,
          fg: AppColors.success,
          icon: Icons.check_circle_outline_rounded,
        );
      }
      if (cleared > 0 && (unresolved > 0 || pending > 0)) {
        return (
          label: '$cleared/$total Resolved',
          bg: AppColors.warningBackground,
          border: AppColors.warningBorder,
          fg: AppColors.warning,
          icon: Icons.rule_rounded,
        );
      }
      if (unresolved > 0) {
        return (
          label: unresolved == 1
              ? '1 Hotspot · Unresolved'
              : '$unresolved Hotspots · Unresolved',
          bg: AppColors.errorBackground,
          border: AppColors.errorBorder,
          fg: AppColors.error,
          icon: Icons.warning_amber_rounded,
        );
      }
      if (pending > 0) {
        return (
          label: total == 1 ? '1 Hotspot · Pending' : '$total Hotspots · Pending',
          bg: AppColors.warningBackground,
          border: AppColors.warningBorder,
          fg: AppColors.warning,
          icon: Icons.hourglass_top_rounded,
        );
      }
      return (
        label: total == 1 ? '1 Hotspot' : '$total Hotspots',
        bg: AppColors.errorBackground,
        border: AppColors.errorBorder,
        fg: AppColors.error,
        icon: Icons.warning_amber_rounded,
      );
    }

    if (bundle != null && bundle.hasPostCleaning) {
      final isResolved = bundle.isHotspotResolved;
      return (
        label: isResolved ? '1 Hotspot · Resolved' : '1 Hotspot · Unresolved',
        bg: isResolved
            ? AppColors.successBackground
            : AppColors.warningBackground,
        border:
            isResolved ? AppColors.successBorder : AppColors.warningBorder,
        fg: isResolved ? AppColors.success : AppColors.warning,
        icon: isResolved
            ? Icons.check_circle_outline_rounded
            : Icons.warning_amber_rounded,
      );
    }

    if (totalHotspots > 0) {
      return (
        label: '$totalHotspots Hotspot${totalHotspots > 1 ? "s" : ""}',
        bg: AppColors.errorBackground,
        border: AppColors.errorBorder,
        fg: AppColors.error,
        icon: Icons.warning_amber_rounded,
      );
    }

    return (
      label: 'Healthy',
      bg: AppColors.successBackground,
      border: AppColors.successBorder,
      fg: AppColors.success,
      icon: Icons.check_circle_outline_rounded,
    );
  }

  Widget _buildInspectionHistoryGroupCard({
    required String inspectionId,
    required List<ModuleMeasurement> measurements,
    required bool isLatest,
    required LatestInspection? latestInspection,
    required PvModule? mod,
    required Map<String, ModuleInspection> inspectionsMap,
    InspectionRoutineBundle? bundle,
  }) {
    final inspModel = bundle?.routineInspection ?? inspectionsMap[inspectionId];
    final inspAnomalies = (inspModel != null && inspModel.confirmedAnomalies.isNotEmpty)
        ? inspModel.confirmedAnomalies
        : (isLatest
            ? (latestInspection?.confirmedAnomalies ?? const <ConfirmedAnomaly>[])
            : const <ConfirmedAnomaly>[]);
    final baselineTemp = inspModel?.baselineTemperatureC ??
        (isLatest ? latestInspection?.inspection.baselineTemperatureC : null);
    final panelResults = inspModel?.panelResults ??
        (isLatest ? latestInspection?.panelResults : null);
    final totalHotspots = inspAnomalies.length;

    final latestDt = (inspModel != null && inspModel.createdAt.isNotEmpty)
        ? (DateTime.tryParse(inspModel.finishedAt ?? '') ??
            DateTime.tryParse(inspModel.createdAt) ??
            _maxMeasuredAt(measurements))
        : (isLatest && latestInspection != null
            ? (DateTime.tryParse(latestInspection.inspection.createdAt) ??
                _maxMeasuredAt(measurements))
            : _maxMeasuredAt(measurements));

    final dateLabel = latestDt != null
        ? _formatReadableTimestamp(latestDt.toIso8601String())
        : (measurements.isNotEmpty
            ? _formatReadableTimestamp(measurements.first.measuredAt)
            : 'N/A');

    final statusStr = (inspModel?.status ??
            (isLatest && latestInspection != null
                ? latestInspection.inspection.status
                : 'completed'))
        .toUpperCase();

    final int effectivePanelCount =
        (mod?.panelCount != null && mod!.panelCount! > 0)
            ? mod.panelCount!
            : 1;
    final int? expectedSteps = (mod != null &&
            mod.panelLengthCm != null &&
            mod.panelLengthCm! > 0)
        ? ((mod.panelLengthCm! / 2.0).ceil() + 1) * effectivePanelCount
        : null;

    final int totalStepsRecorded = measurements.isNotEmpty
        ? measurements.length
        : (isLatest && latestInspection != null
            ? latestInspection.totalMeasurements
            : 0);

    final bool isInterruptedOrFailed = statusStr == 'FAILED' ||
        statusStr == 'CANCELLED' ||
        statusStr == 'IN_PROGRESS';
    final bool isCoverageIncomplete = expectedSteps != null &&
        totalStepsRecorded > 0 &&
        totalStepsRecorded < expectedSteps;
    final bool isPartial = isInterruptedOrFailed || isCoverageIncomplete;

    final String? statusPillLabel;
    final Color statusBadgeBg;
    final Color statusBadgeText;

    if (statusStr == 'IN_PROGRESS') {
      statusPillLabel = expectedSteps != null
          ? 'IN PROGRESS ($totalStepsRecorded/$expectedSteps STEPS)'
          : 'IN PROGRESS';
      statusBadgeBg = AppColors.primarySoft;
      statusBadgeText = AppColors.primary;
    } else if (statusStr == 'FAILED') {
      statusPillLabel = expectedSteps != null
          ? 'FAILED ($totalStepsRecorded/$expectedSteps STEPS)'
          : 'FAILED';
      statusBadgeBg = AppColors.errorBackground;
      statusBadgeText = AppColors.error;
    } else if (isPartial) {
      statusPillLabel = expectedSteps != null
          ? 'PARTIAL ($totalStepsRecorded/$expectedSteps STEPS)'
          : 'PARTIAL';
      statusBadgeBg = AppColors.warningBackground;
      statusBadgeText = AppColors.warning;
    } else {
      statusPillLabel = null;
      statusBadgeBg = AppColors.successBackground;
      statusBadgeText = AppColors.success;
    }

    final count = (mod?.panelCount != null && mod!.panelCount! > 0)
        ? mod.panelCount!
        : 1;
    final len = (mod?.panelLengthCm != null && mod!.panelLengthCm! > 0)
        ? mod.panelLengthCm!
        : 100.0;
    final spc = (mod?.panelSpacingCm != null && mod!.panelSpacingCm! >= 0)
        ? mod.panelSpacingCm!
        : 2.0;
    final totalLength = count * len + (count - 1) * spc;

    final Map<int, List<ModuleMeasurement>> byPanel = {};
    for (final m in measurements) {
      int effectiveP;
      if (m.panelIndex != null && m.panelIndex! > 0) {
        effectiveP = m.panelIndex!;
      } else {
        final x = m.xPositionCm;
        if (x <= 0) {
          effectiveP = 1;
        } else if (x >= totalLength) {
          effectiveP = count;
        } else {
          effectiveP = count;
          for (var p = 1; p <= count; p++) {
            final start = (p - 1) * (len + spc);
            final end = start + len;
            if (x >= start && x <= end) {
              effectiveP = p;
              break;
            }
            if (p < count && x > end && x < start + len + spc) {
              final midGap = end + spc / 2.0;
              effectiveP = (x <= midGap) ? p : p + 1;
              break;
            }
          }
        }
      }
      byPanel.putIfAbsent(effectiveP, () => []).add(m);
    }
    final sortedPanels = byPanel.keys.toList()..sort();

    final peakTemp = measurements.isNotEmpty
        ? measurements.map((m) => m.maxTemperatureC).reduce(math.max)
        : null;
    final panelBaselines = buildPanelBaselineMap(panelResults);
    final deltaT = computeMaxPerPanelDelta(
          measurements: measurements,
          panelBaselines: panelBaselines,
          fallbackBaseline: baselineTemp,
          module: mod,
        ) ??
        ((peakTemp != null && baselineTemp != null)
            ? (peakTemp - baselineTemp)
            : null);

    final totalFramesCount = measurements.isNotEmpty
        ? measurements.length
        : (isLatest && latestInspection != null
            ? latestInspection.totalMeasurements
            : 0);

    final outcomeBadge = _resolveHistoryOutcomeBadge(
      bundle: bundle,
      totalHotspots: totalHotspots,
      statusStr: statusStr,
    );

    final deltaValueStr = deltaT != null
        ? '${deltaT >= 0 ? '+' : ''}${deltaT.toStringAsFixed(1)} °C'
        : 'N/A';
    final peakValueStr =
        peakTemp != null ? '${peakTemp.toStringAsFixed(1)} °C' : 'N/A';
    final baselineValueStr = (baselineTemp != null && baselineTemp > 0)
        ? '${baselineTemp.toStringAsFixed(1)} °C'
        : 'N/A';
    final isDeltaElevated =
        deltaT != null && deltaT >= (mod?.hotspotThresholdDeltaC ?? 8.0);

    final panelElectricalRows =
        <({int panelIndex, ElectricalSummary summary})>[];
    for (final p in sortedPanels) {
      final pSummary = computeElectricalSummary(
        measurements: byPanel[p]!,
        module: mod,
        focusedPanelIndex: p,
      );
      if (pSummary.voltageV != null ||
          pSummary.currentA != null ||
          pSummary.powerW != null) {
        panelElectricalRows.add((panelIndex: p, summary: pSummary));
      }
    }

    final showNestedPostCleaning = bundle != null &&
        (bundle.hasPostCleaning ||
            bundle.hotspotSummaries
                .any((s) => s.isResolvedLater || s.cleaning != null));

    return Container(
      key: Key('history_group_$inspectionId'),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLatest
              ? AppColors.primary.withValues(alpha: 0.45)
              : AppColors.border,
          width: isLatest ? 1.25 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Clean Header: Timestamp + Status Pill + Outcome Badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      dateLabel,
                      style: AppTypography.bodySmall.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        fontSize: 13,
                      ),
                    ),
                    if (isLatest)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'LATEST',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800,
                            fontSize: 9,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    if (statusPillLabel != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: statusBadgeBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          statusPillLabel,
                          style: AppTypography.caption.copyWith(
                            color: statusBadgeText,
                            fontWeight: FontWeight.w800,
                            fontSize: 9,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: outcomeBadge.bg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: outcomeBadge.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      outcomeBadge.icon,
                      size: 12,
                      color: outcomeBadge.fg,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      outcomeBadge.label,
                      style: AppTypography.caption.copyWith(
                        color: outcomeBadge.fg,
                        fontWeight: FontWeight.w700,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Compact 3-column Telemetry Metrics Strip
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.border.withValues(alpha: 0.65),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildCompactMetricCell(
                        label: 'Peak',
                        value: peakValueStr,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 24,
                      color: AppColors.border,
                    ),
                    Expanded(
                      child: _buildCompactMetricCell(
                        label: 'Max Δ',
                        value: deltaValueStr,
                        valueColor: isDeltaElevated
                            ? AppColors.error
                            : AppColors.textPrimary,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 24,
                      color: AppColors.border,
                    ),
                    Expanded(
                      child: _buildCompactMetricCell(
                        label: 'Baseline',
                        value: baselineValueStr,
                      ),
                    ),
                  ],
                ),
                if (panelElectricalRows.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Divider(
                      height: 1,
                      color: AppColors.border.withValues(alpha: 0.7),
                    ),
                  ),
                  ...panelElectricalRows.map((entry) {
                    final s = entry.summary;
                    final vStr = s.voltageV != null
                        ? '${s.voltageV!.toStringAsFixed(2)} V'
                        : 'N/A';
                    final iStr = s.currentA != null
                        ? '${(s.currentA! * 1000).toStringAsFixed(0)} mA'
                        : 'N/A';
                    final pStr = s.powerW != null
                        ? '${s.powerW!.toStringAsFixed(2)} W'
                        : 'N/A';
                    final showPanelTag =
                        panelElectricalRows.length > 1 || count > 1;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1.5),
                      child: Row(
                        children: [
                          Icon(
                            Icons.bolt_rounded,
                            size: 13,
                            color: AppColors.primary.withValues(alpha: 0.85),
                          ),
                          const SizedBox(width: 4),
                          if (showPanelTag) ...[
                            Text(
                              'P${entry.panelIndex}',
                              style: AppTypography.caption.copyWith(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Text(
                              '$vStr · $iStr',
                              style: AppTypography.caption.copyWith(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            pStr,
                            style: AppTypography.caption.copyWith(
                              fontSize: 11.5,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),

          // Interrupted / Partial Telemetry Notice Banner
          if (isPartial && totalStepsRecorded > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.warningBackground,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.warningBorder),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 15,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This scan was interrupted before completion. The recorded readings below represent partial telemetry ($totalStepsRecorded${expectedSteps != null ? " of $expectedSteps" : ""} steps).',
                      style: AppTypography.caption.copyWith(
                        fontSize: 10.5,
                        color: AppColors.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Level 2.5: Nested Post-Cleaning Verification (Traceability)
          if (showNestedPostCleaning) ...[
            _buildNestedPostCleaningSection(bundle),
          ],

          // Direct Action Row
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              key: Key('view_thermal_map_$inspectionId'),
              onPressed: () {
                context.push(
                  '/modules/${widget.moduleId}/thermal-inspection?inspectionId=$inspectionId',
                );
              },
              icon: const Icon(
                Icons.map_outlined,
                size: 16,
                color: AppColors.primary,
              ),
              label: Text(
                'View Thermal Map',
                style: AppTypography.caption.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              style: TextButton.styleFrom(
                backgroundColor: AppColors.primarySoft.withValues(alpha: 0.65),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),

          // Level 2: Collapsed-by-default Raw Frames Expansion Tile (compact)
          if (sortedPanels.isNotEmpty) ...[
            const SizedBox(height: 6),
            Divider(
              height: 1,
              color: AppColors.border.withValues(alpha: 0.6),
            ),
            Theme(
              data: Theme.of(context).copyWith(
                dividerColor: Colors.transparent,
              ),
              child: Material(
                type: MaterialType.transparency,
                child: ExpansionTile(
                  key: Key('show_frames_tile_$inspectionId'),
                  initiallyExpanded: false,
                  dense: true,
                  visualDensity: const VisualDensity(vertical: -3),
                  tilePadding: const EdgeInsets.symmetric(horizontal: 2),
                  childrenPadding: const EdgeInsets.only(top: 6, bottom: 2),
                  title: Text(
                    'Show $totalFramesCount ${totalFramesCount == 1 ? "frame" : "frames"}',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
                  ),
                  children: sortedPanels
                      .map(
                        (p) => _buildPanelAccordion(
                          inspectionId: inspectionId,
                          panelIndex: p,
                          panelMeasurements: byPanel[p]!,
                          mod: mod,
                          latestInspection: isLatest ? latestInspection : null,
                          panelResultsOverride: panelResults,
                          inspAnomalies: inspAnomalies,
                          baselineTemp: baselineTemp,
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ],

          // Level 3: Paginated frames (when byPanel is empty)
          if (isLatest && latestInspection != null && byPanel.isEmpty) ...[
            const SizedBox(height: 8),
            _buildPaginatedInspectionBody(latestInspection, mod),
          ],
        ],
      ),
    );
  }

  Widget _buildNestedPostCleaningSection(InspectionRoutineBundle bundle) {
    final summaries = bundle.hotspotSummaries;
    final verifs = bundle.verificationInspections;
    final verifMeas = bundle.verificationMeasurements;
    final firstVerif = verifs.isNotEmpty ? verifs.first : null;

    final bool allCleared = summaries.isNotEmpty
        ? (bundle.unresolvedCount == 0 && bundle.pendingCount == 0)
        : bundle.isHotspotResolved;
    final bool onlyClearedLater = summaries.isNotEmpty &&
        bundle.resolvedLaterCount > 0 &&
        bundle.resolvedCount == 0 &&
        bundle.unresolvedCount == 0;

    final Color outcomeColor;
    final Color outcomeBorder;
    final String outcomeLabel;

    if (onlyClearedLater) {
      outcomeLabel = 'Cleared in Later Scan';
      outcomeColor = AppColors.primary;
      outcomeBorder = AppColors.primary.withValues(alpha: 0.3);
    } else if (allCleared) {
      outcomeLabel = 'Resolved';
      outcomeColor = AppColors.success;
      outcomeBorder = AppColors.successBorder;
    } else {
      outcomeLabel = 'Unresolved';
      outcomeColor = AppColors.warning;
      outcomeBorder = AppColors.warningBorder;
    }

    List<Widget> buildSummaryRows() => summaries.map((s) {
          final pIdx =
              (s.anomaly.panelIndex != null && s.anomaly.panelIndex! > 0)
                  ? s.anomaly.panelIndex!
                  : 1;
          final tempStr = s.afterTempC != null
              ? '${s.beforeTempC.toStringAsFixed(1)} °C → ${s.afterTempC!.toStringAsFixed(1)} °C'
              : '${s.beforeTempC.toStringAsFixed(1)} °C';
          final itemStatus = s.isResolved
              ? 'Resolved'
              : (s.isResolvedLater
                  ? 'Cleared in Later Scan'
                  : (s.isUnresolved ? 'Unresolved' : 'Pending'));
          return Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              'P$pIdx · X = ${s.anomaly.xPositionCm.toStringAsFixed(1)} cm: $tempStr · $itemStatus',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                fontSize: 10.5,
              ),
            ),
          );
        }).toList();

    final bool collapseSummaries = summaries.length > 2;

    return Container(
      key: Key('nested_post_cleaning_${bundle.routineInspection.id}'),
      margin: const EdgeInsets.only(top: 10),
      padding: EdgeInsets.symmetric(
        horizontal: 10,
        vertical: collapseSummaries ? 4 : 10,
      ),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: outcomeBorder.withValues(alpha: 0.6)),
      ),
      child: collapseSummaries
          ? Theme(
              data: Theme.of(context).copyWith(
                dividerColor: Colors.transparent,
              ),
              child: Material(
                type: MaterialType.transparency,
                child: ExpansionTile(
                  key: Key(
                    'nested_post_cleaning_tile_${bundle.routineInspection.id}',
                  ),
                  initiallyExpanded: false,
                  dense: true,
                  visualDensity: const VisualDensity(vertical: -4),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(top: 4, bottom: 6),
                  title: Row(
                    children: [
                      Icon(
                        onlyClearedLater
                            ? Icons.verified_outlined
                            : (allCleared
                                ? Icons.auto_fix_high_rounded
                                : Icons.warning_amber_rounded),
                        size: 15,
                        color: outcomeColor,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Post-Cleaning · ${summaries.length} hotspots',
                          style: AppTypography.caption.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                            fontSize: 11.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        outcomeLabel,
                        style: AppTypography.caption.copyWith(
                          color: outcomeColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: buildSummaryRows(),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      onlyClearedLater
                          ? Icons.verified_outlined
                          : (allCleared
                              ? Icons.auto_fix_high_rounded
                              : Icons.warning_amber_rounded),
                      size: 15,
                      color: outcomeColor,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Post-Cleaning Verification',
                        style: AppTypography.caption.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                    Text(
                      outcomeLabel,
                      style: AppTypography.caption.copyWith(
                        color: outcomeColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
                if (summaries.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  ...buildSummaryRows(),
                ] else if (firstVerif != null || verifMeas.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${verifMeas.length} verification frame(s) recorded',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ],
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
    List<InspectionPanelResult>? panelResultsOverride,
    List<ConfirmedAnomaly> inspAnomalies = const [],
    double? baselineTemp,
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
    final pResults = panelResultsOverride ?? latestInspection?.panelResults;
    if (pResults != null) {
      for (final r in pResults) {
        if (r.panelIndex == p) {
          pRes = r;
          break;
        }
      }
    }
    final bTemp = pRes?.baselineTemperatureC ??
        latestInspection?.inspection.baselineTemperatureC ??
        baselineTemp;
    final baselineStr = bTemp != null
        ? ' • Baseline: ${bTemp.toStringAsFixed(1)}°C'
        : ' • Baseline: N/A';

    ModuleMeasurement? elecMeas;
    for (final pm in panelMeasurements) {
      if (pm.voltageV != null || pm.currentA != null || pm.powerW != null) {
        if (elecMeas == null) {
          elecMeas = pm;
        } else {
          final currP = pm.powerW ?? 0.0;
          final bestP = elecMeas.powerW ?? 0.0;
          if (currP > bestP ||
              (currP == bestP && (pm.voltageV ?? 0.0) > (elecMeas.voltageV ?? 0.0))) {
            elecMeas = pm;
          }
        }
      }
    }
    final elecStr = elecMeas != null
        ? ' • Output: ${elecMeas.voltageV?.toStringAsFixed(2) ?? "N/A"}V · ${elecMeas.currentA != null ? "${(elecMeas.currentA! * 1000).toStringAsFixed(1)}mA" : "N/A"} · ${elecMeas.powerW?.toStringAsFixed(2) ?? "N/A"}W'
        : '';

    final panelHotspots = inspAnomalies.where((a) {
          if (a.panelIndex != null) return a.panelIndex == p;
          return a.xPositionCm >= pb.startCm && a.xPositionCm <= pb.endCm;
        }).length;
    final hotspotSummaryStr =
        panelHotspots > 0 ? ' • Hotspots: $panelHotspots' : '';

    // Map each physical coordinate to its latest measurement ID
    final Map<int, String> latestIdByCoord = {};
    for (final m in panelMeasurements) {
      final coordKey = (m.xPositionCm * 2).round();
      if (!latestIdByCoord.containsKey(coordKey)) {
        latestIdByCoord[coordKey] = m.id;
      } else {
        final existingId = latestIdByCoord[coordKey]!;
        final existingM =
            panelMeasurements.firstWhere((item) => item.id == existingId);
        final dtM = DateTime.tryParse(m.measuredAt);
        final dtExist = DateTime.tryParse(existingM.measuredAt);
        if (dtM != null && dtExist != null) {
          if (dtM.isAfter(dtExist) ||
              (dtM.isAtSameMomentAs(dtExist) && m.id.compareTo(existingM.id) > 0)) {
            latestIdByCoord[coordKey] = m.id;
          }
        } else if (m.measuredAt.compareTo(existingM.measuredAt) >= 0) {
          latestIdByCoord[coordKey] = m.id;
        }
      }
    }

    final hasDuplicateRetries =
        latestIdByCoord.length < panelMeasurements.length;
    final displayedItems = _showOnlyValid
        ? panelMeasurements.where((m) {
            final coordKey = (m.xPositionCm * 2).round();
            return latestIdByCoord[coordKey] == m.id;
          }).toList()
        : panelMeasurements;

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
                '${displayedItems.length}${hasDuplicateRetries ? " of ${panelMeasurements.length}" : ""} frames • Peak: ${pPeak.toStringAsFixed(1)}°C$baselineStr$elecStr$hotspotSummaryStr',
                style: AppTypography.caption.copyWith(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                ),
              ),
              children: [
                if (hasDuplicateRetries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        InkWell(
                          key: Key('toggle_valid_only_${inspectionId}_$p'),
                          onTap: () {
                            setState(() {
                              _showOnlyValid = !_showOnlyValid;
                            });
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: _showOnlyValid
                                  ? AppColors.primarySoft
                                  : AppColors.background,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: _showOnlyValid
                                    ? AppColors.primary
                                    : AppColors.border,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _showOnlyValid
                                      ? Icons.filter_alt_rounded
                                      : Icons.filter_alt_off_rounded,
                                  size: 11,
                                  color: _showOnlyValid
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _showOnlyValid
                                      ? 'Valid Only'
                                      : 'All Readings (with Retries)',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: _showOnlyValid
                                        ? AppColors.primary
                                        : AppColors.textSecondary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ...displayedItems.map((m) {
                  final isConfirmed = inspAnomalies.any(
                    (a) =>
                        a.originMeasurementId == m.id ||
                        a.confirmingMeasurementIds.contains(m.id) ||
                        (a.originMeasurementId.isEmpty &&
                            a.confirmingMeasurementIds.isEmpty &&
                            (a.xPositionCm - m.xPositionCm).abs() <= 1.0),
                  );
                  final coordKey = (m.xPositionCm * 2).round();
                  final isSuperseded = latestIdByCoord[coordKey] != m.id;

                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _buildPaginatedStepTile(
                      m,
                      isConfirmed,
                      isSuperseded: isSuperseded,
                      showValidBadge: hasDuplicateRetries && !isSuperseded,
                    ),
                  );
                }),
              ],
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

  Widget _buildPaginatedStepTile(
    ModuleMeasurement m,
    bool isConfirmed, {
    bool isSuperseded = false,
    bool showValidBadge = false,
  }) {
    return Opacity(
      opacity: isSuperseded ? 0.55 : 1.0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isConfirmed
                ? AppColors.errorBorder
                : (isSuperseded
                    ? AppColors.border.withValues(alpha: 0.5)
                    : AppColors.border),
            width: isConfirmed ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'X = ${m.xPositionCm.toStringAsFixed(1)} cm',
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isSuperseded
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                    ),
                  ),
                  if (m.panelIndex != null)
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
                  if (isSuperseded)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Text(
                        'SUPERSEDED',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else if (showValidBadge)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: AppColors.successBackground,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.successBorder),
                      ),
                      child: const Text(
                        'VALID',
                        style: TextStyle(
                          color: AppColors.success,
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  if (isConfirmed)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.errorBackground,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.errorBorder),
                      ),
                      child: Text(
                        'HOTSPOT (CONFIRMED)',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.error,
                          fontWeight: FontWeight.w800,
                          fontSize: 9,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _buildMetricChip(
              'Peak',
              '${m.maxTemperatureC.toStringAsFixed(1)}°C',
              isConfirmed ? AppColors.error : AppColors.textPrimary,
            ),
          ],
        ),
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
