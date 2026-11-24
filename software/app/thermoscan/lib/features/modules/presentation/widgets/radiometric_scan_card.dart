import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/features/modules/domain/inspection_routine_bundle.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';
import 'package:thermoscan/features/modules/presentation/widgets/thermal_matrix_inspector_modal.dart';
import 'package:thermoscan/features/modules/presentation/widgets/thermal_panorama_painter.dart';

/// SCR-10: Physical Thermal Frames & Radiometric Telemetry Metrics
class RadiometricScanCard extends StatefulWidget {
  const RadiometricScanCard({
    super.key,
    required this.module,
    this.latestMeasurement,
    this.latestInspection,
    this.measurements,
    this.verificationMeasurements,
    this.postCleaningResult,
    this.hotspotSummaries,
    this.initiallyExpanded,
    this.showDetailedSections = false,
    this.deduplicateSpatially = true,
    this.fallbackBaselineTempC,
    this.fallbackConfirmedAnomalies,
  });

  final PvModule module;
  final ModuleMeasurement? latestMeasurement;
  final LatestInspection? latestInspection;
  final List<ModuleMeasurement>? measurements;
  final List<ModuleMeasurement>? verificationMeasurements;
  final String? postCleaningResult;
  final List<HotspotVerificationSummary>? hotspotSummaries;
  final bool? initiallyExpanded;
  final bool showDetailedSections;
  final bool deduplicateSpatially;
  final double? fallbackBaselineTempC;
  final List<ConfirmedAnomaly>? fallbackConfirmedAnomalies;

  @override
  State<RadiometricScanCard> createState() => _RadiometricScanCardState();
}

class _RadiometricScanCardState extends State<RadiometricScanCard> {
  final bool _fitToScan = true;
  bool _showRestoredView = true;
  int? _selectedFrameIndex;
  int? _focusedPanelIndex;
  int? _selectedHotspotIndex;
  late bool _isAdvancedExpanded;
  bool _isProfileCurveExpanded = false;
  bool _isHotspotSummaryExpanded = false;
  int _timelineFrameIndex = 0;
  bool _timelineInitialized = false;
  int? _lastFramesCount;
  String? _lastFirstFrameId;
  Timer? _playbackTimer;
  int _playTicksRemaining = 0;

  bool get _isPlaying => _playbackTimer != null && _playbackTimer!.isActive;

  @override
  void initState() {
    super.initState();
    // Progressive disclosure: collapsed by default for regular clients,
    // and expanded for technicians, installers, or test suites.
    _isAdvancedExpanded = widget.initiallyExpanded ??
        (widget.module.userRelationship != 'assigned_client' &&
            widget.module.userRelationship != 'client');
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    super.dispose();
  }

  int? _resolveHotspotFrameIndex(
    List<ModuleMeasurement> sortedFrames,
    List<ConfirmedAnomaly> visibleAnomalies,
    double? baselineTemp,
  ) {
    if (sortedFrames.isEmpty || visibleAnomalies.isEmpty) return null;

    int? bestIdx;
    double? bestTemp;
    for (var i = 0; i < sortedFrames.length; i++) {
      final f = sortedFrames[i];
      if (visibleAnomalies.any((a) => isFrameAssociatedWithAnomaly(f, a))) {
        if (bestIdx == null || f.maxTemperatureC > bestTemp!) {
          bestIdx = i;
          bestTemp = f.maxTemperatureC;
        }
      }
    }
    if (bestIdx != null) return bestIdx;
    final targetX = visibleAnomalies.first.xPositionCm;
    var closestIdx = 0;
    var minDiff = (sortedFrames.first.xPositionCm - targetX).abs();
    for (var i = 1; i < sortedFrames.length; i++) {
      final diff = (sortedFrames[i].xPositionCm - targetX).abs();
      if (diff < minDiff) {
        minDiff = diff;
        closestIdx = i;
      }
    }
    return closestIdx;
  }

  ({ModuleMeasurement? measurement, double? peak, double? delta})
      _resolveAnomalyMetrics({
    required ConfirmedAnomaly anomaly,
    required List<ModuleMeasurement> displayedMeasurements,
    required Map<int, double> panelBaselines,
    required double? fallbackBaseline,
    required double? fallbackDelta,
  }) {
    ModuleMeasurement? anomMeas;
    for (final fm in displayedMeasurements) {
      if (isFrameAssociatedWithAnomaly(fm, anomaly)) {
        anomMeas = fm;
        break;
      }
    }
    final anomPeak = anomMeas?.maxTemperatureC;
    final double? anomBaseline;
    if (anomMeas != null) {
      anomBaseline = resolveFrameBaseline(
        anomMeas,
        panelBaselines,
        fallbackBaseline,
        widget.module,
      );
    } else {
      final pIdx = (anomaly.panelIndex != null && anomaly.panelIndex! > 0)
          ? anomaly.panelIndex!
          : widget.module.resolvePanelPosition(anomaly.xPositionCm).panelIndex;
      anomBaseline = (pIdx > 0 ? panelBaselines[pIdx] : null) ?? fallbackBaseline;
    }
    final anomDelta =
        (anomPeak != null && anomBaseline != null && anomBaseline > 0)
            ? (anomPeak - anomBaseline)
            : fallbackDelta;
    return (measurement: anomMeas, peak: anomPeak, delta: anomDelta);
  }

  void _toggleTimelinePlayback(List<ModuleMeasurement> sortedFrames) {
    if (sortedFrames.isEmpty) return;
    if (_isPlaying) {
      setState(() {
        _playbackTimer?.cancel();
        _playbackTimer = null;
      });
      return;
    }

    setState(() {
      _playTicksRemaining = sortedFrames.length;
      _selectedFrameIndex = _timelineFrameIndex;
    });

    _playbackTimer = Timer.periodic(const Duration(milliseconds: 450), (timer) {
      if (!mounted || sortedFrames.isEmpty) {
        timer.cancel();
        _playbackTimer = null;
        return;
      }
      setState(() {
        _timelineFrameIndex = (_timelineFrameIndex + 1) % sortedFrames.length;
        _selectedFrameIndex = _timelineFrameIndex;
        _playTicksRemaining--;
        if (_playTicksRemaining <= 0 ||
            _timelineFrameIndex >= sortedFrames.length - 1) {
          timer.cancel();
          _playbackTimer = null;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.latestMeasurement;
    final insp = widget.latestInspection;
    final allMeasurements =
        widget.measurements ?? (m != null ? [m] : <ModuleMeasurement>[]);
    final rawMeasurements = filterMeasurementsForCurrentInspection(
      measurements: allMeasurements,
      latestInspection: insp,
      latestMeasurement: m,
    );

    final verifMeas =
        widget.verificationMeasurements ?? const <ModuleMeasurement>[];
    final bool hasPostCleaning = verifMeas.isNotEmpty;
    final bool isHotspotResolved = widget.postCleaningResult == 'resolved';
    final summaries =
        widget.hotspotSummaries ?? const <HotspotVerificationSummary>[];
    final summaryByAnomalyId = <String, HotspotVerificationSummary>{
      for (final s in summaries) s.anomaly.id: s,
    };

    final effectiveMeasurements = (hasPostCleaning && _showRestoredView)
        ? fuseRoutineWithVerificationMeasurements(
            routineMeasurements: rawMeasurements,
            verificationMeasurements: verifMeas,
          )
        : rawMeasurements;

    if (m == null && insp == null && effectiveMeasurements.isEmpty) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.grid_view_rounded,
                color: AppColors.primary,
                size: 28,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Waiting for First Scan',
              style: AppTypography.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'No thermal readings recorded yet by the robot. Temperature maps and electrical readings will appear here after the first inspection scan.',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final isInspScheduled = insp?.inspection.status == 'scheduled';
    final rawAnomalies = (!isInspScheduled && insp != null)
        ? insp.confirmedAnomalies
        : (widget.fallbackConfirmedAnomalies ??
            insp?.confirmedAnomalies ??
            const []);
    final List<ConfirmedAnomaly> confirmedAnomalies;
    if (hasPostCleaning && _showRestoredView) {
      confirmedAnomalies = rawAnomalies.where((a) {
        if (a.isCleared) return false;
        final summary = summaryByAnomalyId[a.id];
        if (summary != null) {
          return !summary.isCleared;
        }
        if (isHotspotResolved) return false;
        return true;
      }).toList();
    } else if (!hasPostCleaning) {
      confirmedAnomalies = rawAnomalies.where((a) => !a.isCleared).toList();
    } else {
      confirmedAnomalies = rawAnomalies;
    }
    final visibleAnomalies = _focusedPanelIndex == null
        ? confirmedAnomalies
        : confirmedAnomalies.where((a) {
            if (a.panelIndex != null) {
              return a.panelIndex == _focusedPanelIndex;
            }
            return widget.module
                    .resolvePanelPosition(a.xPositionCm)
                    .panelIndex ==
                _focusedPanelIndex;
          }).toList();
    final hasConfirmedHotspots = visibleAnomalies.isNotEmpty;

    final sortedRaw = sortMeasurementsSpatially(effectiveMeasurements);
    final focusedBounds = _focusedPanelIndex != null
        ? widget.module.getPanelBounds(_focusedPanelIndex!)
        : null;
    final filteredInputMeasurements = _focusedPanelIndex == null
        ? sortedRaw
        : sortedRaw.where((meas) {
            if (meas.panelIndex != null) {
              return meas.panelIndex == _focusedPanelIndex;
            }
            if (focusedBounds != null) {
              return meas.xPositionCm >= focusedBounds.startCm &&
                  meas.xPositionCm <= focusedBounds.endCm;
            }
            return true;
          }).toList();

    final panelBaselines = !isInspScheduled
        ? buildPanelBaselineMap(insp?.panelResults)
        : const <int, double>{};
    final globalBaselineTemp =
        ((!isInspScheduled && insp?.inspection.baselineTemperatureC != null)
            ? insp!.inspection.baselineTemperatureC
            : null) ??
        widget.fallbackBaselineTempC ??
        insp?.inspection.baselineTemperatureC;
    final baselineTemp = (_focusedPanelIndex != null
            ? panelBaselines[_focusedPanelIndex!]
            : null) ??
        globalBaselineTemp;

    final panorama = ThermalPanoramaData.fromMeasurements(
      measurements: filteredInputMeasurements,
      confirmedAnomalies: visibleAnomalies,
      panelLengthCm: widget.module.panelLengthCm,
      panelCount: widget.module.panelCount,
      panelSpacingCm: widget.module.panelSpacingCm,
      focusedPanelIndex: _focusedPanelIndex,
      totalInspectionMeasurements: _focusedPanelIndex == null
          ? insp?.totalMeasurements
          : null,
      baselineTempC: baselineTemp,
      panelBaselines: panelBaselines,
      hotspotDeltaThresholdC: widget.module.hotspotThresholdDeltaC,
      fitToScannedRange: _fitToScan,
      deduplicateSpatially: widget.deduplicateSpatially,
    );
    final displayedMeasurements = panorama.sortedMeasurements;

    final coverage = panorama.coverageInfo;

    final peakTemp = displayedMeasurements.isNotEmpty
        ? displayedMeasurements
            .map((e) => e.maxTemperatureC)
            .reduce((a, b) => a > b ? a : b)
        : (_focusedPanelIndex == null ? (m?.maxTemperatureC ?? 0.0) : 0.0);

    final hotspotIndex = _resolveHotspotFrameIndex(
      displayedMeasurements,
      visibleAnomalies,
      baselineTemp,
    );
    if (displayedMeasurements.isNotEmpty) {
      final firstId = displayedMeasurements.first.id;
      if (!_timelineInitialized ||
          _lastFramesCount != displayedMeasurements.length ||
          _lastFirstFrameId != firstId) {
        _timelineInitialized = true;
        _lastFramesCount = displayedMeasurements.length;
        _lastFirstFrameId = firstId;
        _timelineFrameIndex =
            hotspotIndex ?? (displayedMeasurements.length - 1);
      }
      final clampedIdx = _timelineFrameIndex.clamp(
        0,
        displayedMeasurements.length - 1,
      );
      if (_timelineFrameIndex != clampedIdx) {
        _timelineFrameIndex = clampedIdx;
      }
    } else {
      _timelineFrameIndex = 0;
    }

    final ModuleMeasurement? selectedMeas = (_selectedFrameIndex != null &&
            _selectedFrameIndex! >= 0 &&
            _selectedFrameIndex! < displayedMeasurements.length)
        ? displayedMeasurements[_selectedFrameIndex!]
        : null;

    // Determine the best stable electrical reading across displayed panel frames
    ModuleMeasurement? bestElecMeas;
    for (final dm in displayedMeasurements) {
      if (dm.voltageV != null || dm.currentA != null || dm.powerW != null) {
        if (bestElecMeas == null) {
          bestElecMeas = dm;
        } else {
          final currP = dm.powerW ?? 0.0;
          final bestP = bestElecMeas.powerW ?? 0.0;
          if (currP > bestP ||
              (currP == bestP && (dm.voltageV ?? 0.0) > (bestElecMeas.voltageV ?? 0.0))) {
            bestElecMeas = dm;
          }
        }
      }
    }

    final double? voltage = bestElecMeas?.voltageV ?? m?.voltageV;
    final double? current = bestElecMeas?.currentA ?? m?.currentA;
    final double? power = bestElecMeas?.powerW ??
        (voltage != null && current != null ? voltage * current : m?.powerW);
    final double xPos = selectedMeas?.xPositionCm ??
        (displayedMeasurements.isNotEmpty
            ? displayedMeasurements.first.xPositionCm
            : (m?.xPositionCm ?? 0.0));

    // Relative delta above each frame's own panel baseline (never global average when per-panel baselines exist)
    final delta = computeMaxPerPanelDelta(
      measurements: displayedMeasurements,
      panelBaselines: panelBaselines,
      fallbackBaseline: baselineTemp,
      module: widget.module,
      fallbackMeasurement: _focusedPanelIndex == null ? m : null,
      panelBounds: panorama.panelBounds,
    );

    final String deltaText;
    final bool hasAnyRemainingActive = confirmedAnomalies.isNotEmpty;
    final bool isErrorBadge = (hasPostCleaning && !_showRestoredView && rawAnomalies.isNotEmpty) ||
        hasConfirmedHotspots ||
        (hasPostCleaning && _showRestoredView && hasAnyRemainingActive);

    if (hasPostCleaning && _showRestoredView) {
      if (!hasAnyRemainingActive) {
        final onlyClearedLater = summaries.isNotEmpty &&
            summaries.every((s) => s.isResolvedLater);
        deltaText = onlyClearedLater
            ? 'After Cleaning · Cleared Later'
            : 'After Cleaning · Hotspot Healed';
      } else {
        deltaText = delta != null
            ? 'After Cleaning · Persistent (+${delta.toStringAsFixed(1)}°C)'
            : 'After Cleaning · Hotspot Persistent';
      }
    } else if (hasPostCleaning && !_showRestoredView) {
      deltaText = delta != null
          ? 'Before Cleaning · +${delta.toStringAsFixed(1)}°C Hotspot'
          : 'Before Cleaning (Pre-Cleaning)';
    } else if (rawAnomalies.isNotEmpty && rawAnomalies.every((a) => a.isCleared)) {
      deltaText = rawAnomalies.any((a) => a.isResolvedLater)
          ? 'Cleared in Later Scan'
          : 'Hotspot Resolved';
    } else if (hasConfirmedHotspots) {
      deltaText = delta != null
          ? '+${delta.toStringAsFixed(1)}°C above normal (Hotspot)'
          : 'Hotspot Confirmed';
    } else {
      deltaText = delta != null
          ? '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}°C (Normal)'
          : 'Normal';
    }

    final bool showVerdictBanner = summaries.any(
      (s) =>
          s.cleaning != null ||
          s.afterTempC != null ||
          s.isResolved ||
          s.isResolvedLater ||
          s.isUnresolved,
    );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Title and Status Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(
                      Icons.grid_view_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Panel Heat Map',
                            style: AppTypography.caption.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            hasPostCleaning && _showRestoredView
                                ? 'After cleaning: routine scan fused with verification frames'
                                : 'Full temperature scan across your solar panels',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 10,
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isErrorBadge
                      ? AppColors.errorBackground
                      : AppColors.successBackground,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isErrorBadge
                        ? AppColors.errorBorder
                        : AppColors.successBorder,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      deltaText,
                      style: AppTypography.caption.copyWith(
                        color: isErrorBadge
                            ? AppColors.error
                            : AppColors.success,
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Post-Cleaning Restoration Toggle (STRICTLY rendered when post-cleaning verification exists)
          if (hasPostCleaning) ...[
            Container(
              key: const Key('post_cleaning_toggle_bar'),
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      key: const Key('toggle_restored_view'),
                      onTap: () => setState(() {
                        _showRestoredView = true;
                        _selectedHotspotIndex = null;
                        _selectedFrameIndex = null;
                      }),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: _showRestoredView
                              ? AppColors.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.auto_fix_high_rounded,
                              size: 14,
                              color: _showRestoredView
                                  ? Colors.white
                                  : AppColors.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'After Cleaning',
                              style: AppTypography.caption.copyWith(
                                color: _showRestoredView
                                    ? Colors.white
                                    : AppColors.textSecondary,
                                fontWeight: _showRestoredView
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                fontSize: 11,
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
                      key: const Key('toggle_original_scan'),
                      onTap: () => setState(() {
                        _showRestoredView = false;
                        _selectedHotspotIndex = null;
                        _selectedFrameIndex = null;
                      }),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: !_showRestoredView
                              ? AppColors.surface
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: !_showRestoredView
                              ? Border.all(color: AppColors.border)
                              : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.history_rounded,
                              size: 14,
                              color: !_showRestoredView
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Before Cleaning',
                              style: AppTypography.caption.copyWith(
                                color: !_showRestoredView
                                    ? AppColors.textPrimary
                                    : AppColors.textSecondary,
                                fontWeight: !_showRestoredView
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                fontSize: 11,
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
            const SizedBox(height: 8),
          ],

          // Post-Cleaning Verdict Banner (above heat map)
          if (showVerdictBanner) ...[
            _buildPostCleaningVerdictBanner(
              summaries: summaries,
              sortedRaw: sortedRaw,
              displayedMeasurements: displayedMeasurements,
            ),
            const SizedBox(height: 8),
          ],

          // Multi-Panel String Selector Chips
          if (widget.module.panelCount != null &&
              widget.module.panelCount! > 1) ...[
            _buildPanelSelector(
              widget.module.panelCount!,
              confirmedAnomalies,
            ),
            const SizedBox(height: 8),
          ],

          // Position / Range Overview on the Rail
          if (displayedMeasurements.isNotEmpty) ...[
            Text(
              'Range: ${panorama.minDomainX.toStringAsFixed(1)} to ${panorama.maxDomainX.toStringAsFixed(1)} cm (${panorama.domainSpanCm.toStringAsFixed(1)} cm)',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 2),
          ],
          const SizedBox(height: 4),

          // Mini Rail Progress Bar
          if (displayedMeasurements.isNotEmpty &&
              widget.module.panelLengthCm != null &&
              widget.module.panelLengthCm! > 0)
            _buildRailProgressOverview(
              minFrameX: displayedMeasurements.first.xPositionCm,
              maxFrameX: displayedMeasurements.last.xPositionCm,
              panelLengthCm: widget.module.panelLengthCm!,
              panelCount: widget.module.panelCount,
              panelSpacingCm: widget.module.panelSpacingCm,
              focusedPanelIndex: _focusedPanelIndex,
              panelBounds: panorama.panelBounds,
              coverage: coverage,
              loadedCount: displayedMeasurements.length,
            ),

          const SizedBox(height: 4),

          // 2D Thermal Viewport with Real Thermal Panorama
          Container(
            height: 145,
            width: double.infinity,
            decoration: BoxDecoration(
              color: ThermalPanoramaPainter.uncoveredBackgroundColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final w = constraints.maxWidth;
                      const padLeft = 12.0;
                      final usableW = (w - (padLeft * 2)).clamp(
                        10.0,
                        double.infinity,
                      );
                      final domainSpan = panorama.domainSpanCm;
                      final pxPerCm = usableW / domainSpan;
                      final framePxWidth =
                          (ThermalCoverageInfo.fovCm * pxPerCm).clamp(
                            18.0,
                            math.max(18.0, usableW),
                          ).toDouble();

                      double xToPx(double xCm) =>
                          padLeft + ((xCm - panorama.minDomainX) * pxPerCm);

                      return Stack(
                        children: [
                          // Real 2D Thermal Mosaic Layer
                          if (panorama.hasAnyThermalMatrix)
                            Positioned(
                              top: 36,
                              left: padLeft,
                              right: padLeft,
                              bottom: 34,
                              child: CustomPaint(
                                key: const Key('thermal_panorama_canvas'),
                                painter: ThermalPanoramaPainter(
                                  panorama: panorama,
                                ),
                              ),
                            )
                          else if (displayedMeasurements.isNotEmpty)
                            Positioned(
                              top: 36,
                              left: padLeft,
                              right: padLeft,
                              bottom: 34,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.65),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.25,
                                      ),
                                    ),
                                  ),
                                  child: const Text(
                                    'Detailed heat map grid not available',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                          // Ruler Rail at the top
                          Positioned(
                            top: 8,
                            left: 0,
                            right: 0,
                            child: SizedBox(
                              height: 24,
                              child: Stack(
                                children: [
                                  Positioned(
                                    top: 14,
                                    left: padLeft,
                                    right: padLeft,
                                    child: Container(
                                      height: 1.5,
                                      color: Colors.white.withValues(
                                        alpha: 0.4,
                                      ),
                                    ),
                                  ),
                                  ..._buildRulerTicks(
                                    minDomainX: panorama.minDomainX,
                                    maxDomainX: panorama.maxDomainX,
                                    xToPx: xToPx,
                                    maxWidth: w,
                                  ),
                                  // Panel & Gap indicators along the top ruler
                                  if (panorama.panelBounds.length > 1) ...[
                                    ...panorama.panelBounds
                                        .where((pb) =>
                                            _focusedPanelIndex == null ||
                                            pb.panelIndex == _focusedPanelIndex)
                                        .map((pb) {
                                      final startPx = xToPx(pb.startXCm);
                                      final endPx = xToPx(pb.endXCm);
                                      final panelPxW = endPx - startPx;
                                      final centerPx = (startPx + endPx) / 2.0;
                                      final String headerText;
                                      if (panelPxW >= 95) {
                                        headerText =
                                            'PANEL ${pb.panelIndex} (${pb.startXCm.toStringAsFixed(0)}–${pb.endXCm.toStringAsFixed(0)} cm)';
                                      } else if (panelPxW >= 52) {
                                        headerText =
                                            'P${pb.panelIndex} (${pb.startXCm.toStringAsFixed(0)}–${pb.endXCm.toStringAsFixed(0)}cm)';
                                      } else {
                                        headerText = 'P${pb.panelIndex}';
                                      }
                                      final approxBadgeHalfW =
                                          (headerText.length * 2.4).clamp(
                                            14.0,
                                            80.0,
                                          );
                                      return Positioned(
                                        key: Key(
                                          'ruler_panel_header_${pb.panelIndex}',
                                        ),
                                        left: (centerPx - approxBadgeHalfW)
                                            .clamp(
                                              padLeft,
                                              math.max(
                                                padLeft,
                                                w - padLeft - (approxBadgeHalfW * 2),
                                              ),
                                            ).toDouble(),
                                        top: 0,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withValues(
                                              alpha: 0.85,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            headerText,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 7.5,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      );
                                    }),
                                    if (_focusedPanelIndex == null)
                                      ...panorama.gapIntervals.map((gap) {
                                        final centerPx =
                                            xToPx((gap.startXCm + gap.endXCm) / 2.0);
                                        return Positioned(
                                          key: Key(
                                            'ruler_gap_badge_${gap.afterPanelIndex}',
                                          ),
                                          left: (centerPx - 14).clamp(
                                            padLeft,
                                            math.max(padLeft, w - padLeft - 28.0),
                                          ).toDouble(),
                                          top: 1,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 3,
                                              vertical: 0.5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.black.withValues(
                                                alpha: 0.85,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(3),
                                              border: Border.all(
                                                color: Colors.white24,
                                                width: 0.5,
                                              ),
                                            ),
                                            child: Text(
                                              'GAP ${gap.widthCm.toStringAsFixed(0)}cm',
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 6.5,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        );
                                      }),
                                  ],
                                ],
                              ),
                            ),
                          ),

                          // Physical Frame FOV Strips (Clean overlay without blocking the thermal mosaic)
                          Positioned(
                            top: 36,
                            left: 0,
                            right: 0,
                            bottom: 34,
                            child: displayedMeasurements.isEmpty
                                ? Center(
                                    child: Text(
                                      'Awaiting physical frames from carriage scan',
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.7,
                                        ),
                                        fontSize: 10,
                                      ),
                                    ),
                                  )
                                : Stack(
                                    children: displayedMeasurements
                                        .asMap()
                                        .entries
                                        .map((entry) {
                                          final idx = entry.key;
                                          final meas = entry.value;

                                          PanelBound? pb;
                                          if (panorama.panelBounds.length > 1 ||
                                              _focusedPanelIndex != null ||
                                              meas.panelIndex != null) {
                                            final pIdx = meas.panelIndex ??
                                                _focusedPanelIndex;
                                            if (pIdx != null &&
                                                pIdx >= 1 &&
                                                pIdx <=
                                                    panorama.panelBounds.length) {
                                              pb = panorama.panelBounds[pIdx - 1];
                                            } else {
                                              for (final b
                                                  in panorama.panelBounds) {
                                                if (b.contains(
                                                  meas.xPositionCm,
                                                )) {
                                                  pb = b;
                                                  break;
                                                }
                                              }
                                            }
                                          }

                                          final rawLeftCm = meas.xPositionCm -
                                              ThermalCoverageInfo.halfFovCm;
                                          final rawRightCm = meas.xPositionCm +
                                              ThermalCoverageInfo.halfFovCm;
                                          final leftEdgeCm = pb != null
                                              ? rawLeftCm.clamp(
                                                  pb.startXCm,
                                                  pb.endXCm,
                                                )
                                              : rawLeftCm;
                                          final rightEdgeCm = pb != null
                                              ? rawRightCm.clamp(
                                                  pb.startXCm,
                                                  pb.endXCm,
                                                )
                                              : rawRightCm;

                                          final rawLeftPx = xToPx(leftEdgeCm);
                                          final rawRightPx = xToPx(rightEdgeCm);
                                          final stripWidthPx = pb != null
                                              ? (rawRightPx - rawLeftPx).clamp(
                                                  16.0,
                                                  (xToPx(pb.endXCm) -
                                                          xToPx(pb.startXCm))
                                                      .clamp(16.0, math.max(16.0, usableW)),
                                                ).toDouble()
                                              : framePxWidth;
                                          final minLeftPx = pb != null
                                              ? xToPx(pb.startXCm).clamp(
                                                  0.0,
                                                  math.max(0.0, w - stripWidthPx),
                                                ).toDouble()
                                              : 0.0;
                                          final safeMaxBound =
                                              math.max(minLeftPx, w - stripWidthPx);
                                          final maxLeftPx = pb != null
                                              ? (xToPx(pb.endXCm) - stripWidthPx)
                                                  .clamp(minLeftPx, safeMaxBound).toDouble()
                                              : (w - stripWidthPx);
                                          final safeMaxLeft =
                                              math.max(minLeftPx, maxLeftPx);
                                          final clampedLeftPx = rawLeftPx.clamp(
                                            minLeftPx,
                                            safeMaxLeft,
                                          ).toDouble();

                                          final associatedAnomalies =
                                              getFrameAssociatedAnomalies(
                                                meas,
                                                visibleAnomalies,
                                              );
                                          final isFrameConfirmed =
                                              associatedAnomalies.isNotEmpty;
                                          final isSelected =
                                              _selectedFrameIndex == idx;

                                          return Positioned(
                                            key: Key('fov_strip_${idx + 1}'),
                                            left: clampedLeftPx,
                                            width: stripWidthPx,
                                            top: 0,
                                            bottom: 0,
                                            child: GestureDetector(
                                              behavior: HitTestBehavior.opaque,
                                              onTap: () {
                                                setState(() {
                                                  _playbackTimer?.cancel();
                                                  _playbackTimer = null;
                                                  _selectedFrameIndex = idx;
                                                  _timelineFrameIndex = idx;
                                                });
                                                _showFrameInspectorModal(
                                                  context,
                                                  displayedMeasurements,
                                                  idx,
                                                  panorama.minValidTempC ?? 20.0,
                                                  panorama.maxValidTempC ??
                                                      peakTemp,
                                                  baselineTemp,
                                                  panorama: panorama,
                                                  confirmedAnomalies:
                                                      visibleAnomalies,
                                                  panelBaselines: panelBaselines,
                                                );
                                              },
                                              child: AnimatedContainer(
                                                duration: const Duration(
                                                  milliseconds: 180,
                                                ),
                                                margin: const EdgeInsets.symmetric(
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: isSelected
                                                      ? (isFrameConfirmed
                                                          ? AppColors.error
                                                              .withValues(
                                                              alpha: 0.2,
                                                            )
                                                          : AppColors.primary
                                                              .withValues(
                                                              alpha: 0.15,
                                                            ))
                                                      : Colors.transparent,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  border: Border.all(
                                                    color: isSelected
                                                        ? (isFrameConfirmed
                                                            ? AppColors.error
                                                            : AppColors.primary)
                                                        : (isFrameConfirmed
                                                            ? AppColors.error
                                                                .withValues(
                                                                alpha: 0.6,
                                                              )
                                                            : Colors.white
                                                                .withValues(
                                                                alpha: 0.15,
                                                              )),
                                                    width: isSelected
                                                        ? 1.8
                                                        : (isFrameConfirmed
                                                            ? 1.2
                                                            : 0.6),
                                                  ),
                                                ),
                                                child: stripWidthPx < 28.0
                                                    ? Center(
                                                        child: Text(
                                                          'F${idx + 1}',
                                                          style:
                                                              const TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 7.5,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                          ),
                                                        ),
                                                      )
                                                    : Align(
                                                        alignment: Alignment
                                                            .topCenter,
                                                        child: Container(
                                                          margin:
                                                              const EdgeInsets
                                                                  .only(top: 2),
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                            horizontal: 3,
                                                            vertical: 0.5,
                                                          ),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: Colors.black
                                                                .withValues(
                                                              alpha: 0.55,
                                                            ),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                              3,
                                                            ),
                                                          ),
                                                          child: Text(
                                                            'F${idx + 1} (${meas.xPositionCm.toStringAsFixed(0)}cm)',
                                                            style:
                                                                const TextStyle(
                                                              color:
                                                                  Colors.white,
                                                              fontSize: 7.5,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                              ),
                                            ),
                                          );
                                        })
                                        .toList(),
                                    ),
                          ),

                          // Confirmed Hotspot Target Markers (Clean, legible, zero shadows)
                          ...visibleAnomalies.asMap().entries.map((entry) {
                            final anomIdx = entry.key;
                            final anomaly = entry.value;
                            final anomalyPx = xToPx(
                              anomaly.xPositionCm,
                            ).clamp(14.0, math.max(14.0, w - 30.0)).toDouble();

                            final anomMetrics = _resolveAnomalyMetrics(
                              anomaly: anomaly,
                              displayedMeasurements: displayedMeasurements,
                              panelBaselines: panelBaselines,
                              fallbackBaseline: baselineTemp,
                              fallbackDelta: delta,
                            );
                            final anomDelta = anomMetrics.delta;

                            final deltaStr = anomDelta != null
                                ? '+${anomDelta.toStringAsFixed(1)}°C'
                                : '+10.0°C';
                            final panelPart = anomaly.panelIndex != null
                                ? 'Panel ${anomaly.panelIndex}'
                                : '';

                            final primaryHotspotLabel =
                                anomaly.panelIndex != null
                                    ? 'Hotspot • $panelPart • $deltaStr'
                                    : 'HOTSPOT ${anomaly.xPositionCm.toStringAsFixed(1)}cm';

                            final isPopoverSelected =
                                _selectedHotspotIndex == anomIdx;

                            return Positioned(
                              key: Key('rail_hotspot_marker_${anomIdx + 1}'),
                              top: 26,
                              left: (anomalyPx - 11).clamp(2.0, math.max(2.0, w - 80.0)).toDouble(),
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    if (_selectedHotspotIndex == anomIdx) {
                                      _selectedHotspotIndex = null;
                                    } else {
                                      _selectedHotspotIndex = anomIdx;
                                      final frameIdx = displayedMeasurements.indexWhere(
                                        (m) => isFrameAssociatedWithAnomaly(m, anomaly),
                                      );
                                      if (frameIdx >= 0) {
                                        _playbackTimer?.cancel();
                                        _playbackTimer = null;
                                        _timelineFrameIndex = frameIdx;
                                        _selectedFrameIndex = frameIdx;
                                      }
                                    }
                                  });
                                },
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Clean flat pinpoint target (No drop shadow)
                                    Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: AppColors.error,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2,
                                        ),
                                      ),
                                      child: const Center(
                                        child: Icon(
                                          Icons.priority_high_rounded,
                                          color: Colors.white,
                                          size: 13,
                                        ),
                                      ),
                                    ),
                                    // Friendly, legible label (Shown exclusively on tap to prevent canvas clutter)
                                    if (isPopoverSelected) ...[
                                      const SizedBox(height: 3),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(
                                            alpha: 0.90,
                                          ),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(
                                            color: AppColors.error,
                                            width: 1.0,
                                          ),
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              primaryHotspotLabel,
                                              style: const TextStyle(
                                                fontFamily: 'monospace',
                                                fontSize: 8,
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            if (anomaly.panelIndex != null)
                                              Text(
                                                'HOTSPOT ${anomaly.xPositionCm.toStringAsFixed(1)}cm',
                                                style: const TextStyle(
                                                  fontFamily: 'monospace',
                                                  fontSize: 7,
                                                  color: Colors.white70,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          }),

                          // Interactive Popover Card upon tapping a hotspot marker
                          if (_selectedHotspotIndex != null &&
                              _selectedHotspotIndex! < visibleAnomalies.length) ...[
                            Builder(
                              builder: (context) {
                                final anomaly =
                                    visibleAnomalies[_selectedHotspotIndex!];
                                final globalIdx =
                                    confirmedAnomalies.indexOf(anomaly);
                                final hNumber =
                                    (globalIdx >= 0 ? globalIdx : _selectedHotspotIndex!) +
                                        1;

                                final anomMetrics = _resolveAnomalyMetrics(
                                  anomaly: anomaly,
                                  displayedMeasurements: displayedMeasurements,
                                  panelBaselines: panelBaselines,
                                  fallbackBaseline: baselineTemp,
                                  fallbackDelta: delta,
                                );
                                final anomPeak = anomMetrics.peak;
                                final anomDelta = anomMetrics.delta;

                                return Positioned(
                                  key: Key(
                                    'hotspot_popover_${_selectedHotspotIndex! + 1}',
                                  ),
                                  left: 16,
                                  right: 16,
                                  bottom: 36,
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppColors.surface,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: AppColors.error,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            color: AppColors.errorBackground,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: const Icon(
                                            Icons.warning_amber_rounded,
                                            color: AppColors.error,
                                            size: 18,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                'Hotspot H$hNumber Confirmed',
                                                style: AppTypography.caption
                                                    .copyWith(
                                                  fontWeight: FontWeight.w800,
                                                  color: AppColors.error,
                                                  fontSize: 11,
                                                ),
                                              ),
                                              Text(
                                                'Panel ${anomaly.panelIndex ?? 1} • X = ${anomaly.xPositionCm.toStringAsFixed(1)} cm${anomaly.localXPositionCm != null ? " (local: ${anomaly.localXPositionCm!.toStringAsFixed(1)} cm)" : ""}',
                                                style: AppTypography.caption
                                                    .copyWith(
                                                  fontSize: 9.5,
                                                  color: AppColors.textPrimary,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              Text(
                                                'Peak: ${anomPeak != null ? "${anomPeak.toStringAsFixed(1)}°C" : "N/A"}${anomDelta != null ? " • +${anomDelta.toStringAsFixed(1)}°C above normal" : ""}',
                                                style: AppTypography.caption
                                                    .copyWith(
                                                  fontSize: 9.0,
                                                  color: AppColors.textSecondary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        InkWell(
                                          onTap: () {
                                            setState(() {
                                              _selectedHotspotIndex = null;
                                            });
                                          },
                                          child: const Padding(
                                            padding: EdgeInsets.all(4),
                                            child: Icon(
                                              Icons.close_rounded,
                                              size: 16,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      );
                    },
                  ),

                  // Live Rail Metadata Badges
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: _buildBadge(
                      'X: ${xPos.toStringAsFixed(1)} cm (Step 2cm • Span 5cm)',
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: _buildBadge(
                      'T_max: ${peakTemp.toStringAsFixed(1)}°C',
                      highlight: hasConfirmedHotspots,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),

          // Calibrated Semantic Thermal Scale Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                color: panorama.hasValidTemperatures
                    ? null
                    : ThermalPanoramaPainter.unresolvedInvalidColor,
                gradient: panorama.hasValidTemperatures
                    ? LinearGradient(
                        colors: panorama.scaleGradientColors,
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 2),
          if (panorama.hasValidTemperatures)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Min: ${panorama.minValidTempC!.toStringAsFixed(1)}°C',
                  style: AppTypography.caption.copyWith(fontSize: 10),
                ),
                Text(
                  baselineTemp != null && baselineTemp > 0
                      ? 'Normal: ${baselineTemp.toStringAsFixed(1)}°C'
                      : 'Mid: ${((panorama.minValidTempC! + panorama.maxValidTempC!) / 2.0).toStringAsFixed(1)}°C',
                  style: AppTypography.caption.copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  'Max: ${panorama.maxValidTempC!.toStringAsFixed(1)}°C',
                  style: AppTypography.caption.copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: hasConfirmedHotspots
                        ? AppColors.error
                        : AppColors.textPrimary,
                  ),
                ),
              ],
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Scale: N/A (No valid thermal pixels)',
                  style: AppTypography.caption.copyWith(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (baselineTemp != null && baselineTemp > 0)
                  Text(
                    'Normal: ${baselineTemp.toStringAsFixed(1)}°C',
                    style: AppTypography.caption.copyWith(fontSize: 10),
                  ),
              ],
            ),

          // Robot Carriage Timeline Scrubber (Item 1)
          if (displayedMeasurements.isNotEmpty) ...[
            const SizedBox(height: 4),
            _buildRobotTimelineScrubber(
              context: context,
              sortedFrames: displayedMeasurements,
              hotspotIndex: hotspotIndex,
              minTemp: panorama.minValidTempC ?? 20.0,
              maxTemp: panorama.maxValidTempC ?? peakTemp,
              baselineTemp: baselineTemp,
              panorama: panorama,
              confirmedAnomalies: visibleAnomalies,
              panelBaselines: panelBaselines,
            ),
          ],

          // Confirmed Hotspot Dual-Frame Confirmation Explainer
          if (hasConfirmedHotspots) ...[
            const SizedBox(height: 4),
            _buildHotspotConfirmationSummary(
              confirmedAnomalies: visibleAnomalies,
              sortedMeasurements: displayedMeasurements,
            ),
          ],

          // Explicit Diagnostic & Coverage State Notices
          ..._buildStateNotices(
            panorama: panorama,
            coverage: coverage,
          ),

          // Progressive Disclosure Accordion: Advanced Telemetry & Frame Inspector (Only when requested)
          if (widget.showDetailedSections) ...[
            const SizedBox(height: 4),
            _buildAdvancedTelemetryAccordion(
              context: context,
              displayedMeasurements: displayedMeasurements,
              visibleAnomalies: visibleAnomalies,
              coverage: coverage,
              panorama: panorama,
              peakTemp: peakTemp,
              baselineTemp: baselineTemp,
              panelBaselines: panelBaselines,
            ),
          ],

          // 1D Thermal Profile Curve Collapsible Accordion (Item 3, closed by default)
          if (displayedMeasurements.isNotEmpty) ...[
            const SizedBox(height: 6),
            _buildThermalProfileCurveAccordion(
              sortedFrames: displayedMeasurements,
              baselineTemp: baselineTemp,
              panelBaselines: panelBaselines,
              panelBounds: panorama.panelBounds,
              hotspotDeltaThresholdC: widget.module.hotspotThresholdDeltaC,
            ),
          ],

          const SizedBox(height: 8),

          // 4 Key Telemetry Metrics Grid (Flat, border-only, zero drop shadows)
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  label: 'Peak Temperature',
                  value: '${peakTemp.toStringAsFixed(1)}°C',
                  subtext: hasConfirmedHotspots
                      ? (delta != null
                          ? '+${delta.toStringAsFixed(1)}°C above normal (Hotspot)'
                          : 'Hotspot confirmed')
                      : (delta != null
                          ? '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}°C (Normal)'
                          : 'Within normal range'),
                  isWarning: hasConfirmedHotspots,
                  deltaBadge: hasConfirmedHotspots ? 'HOTSPOT' : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricTile(
                  label: 'Normal Temperature',
                  value: baselineTemp != null && baselineTemp > 0
                      ? '${baselineTemp.toStringAsFixed(1)}°C'
                      : 'N/A',
                  subtext: 'Average panel temperature',
                  isWarning: false,
                  valueColor: AppColors.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  label: _focusedPanelIndex != null
                      ? 'P$_focusedPanelIndex Voltage & Curr'
                      : 'DC Voltage & Current',
                  value: (voltage == null && current == null)
                      ? 'N/A'
                      : '${voltage != null ? "${voltage.toStringAsFixed(2)} V" : "N/A"} · ${current != null ? "${(current * 1000).toStringAsFixed(1)} mA" : "N/A"}',
                  subtext: _focusedPanelIndex != null
                      ? 'Panel $_focusedPanelIndex output'
                      : 'Panel electrical output',
                  isWarning: false,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricTile(
                  label: _focusedPanelIndex != null
                      ? 'P$_focusedPanelIndex Power'
                      : 'Active Power',
                  value: power != null ? '${power.toStringAsFixed(2)} W' : 'N/A',
                  subtext: _focusedPanelIndex != null
                      ? 'Panel $_focusedPanelIndex peak yield'
                      : ((voltage != null && current != null)
                          ? 'Operational yield (V × I)'
                          : 'Operational yield'),
                  isWarning: false,
                  valueColor: AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Progressive Disclosure Accordion containing MLX90640 frame carousel and 32x24 inspector.
  Widget _buildAdvancedTelemetryAccordion({
    required BuildContext context,
    required List<ModuleMeasurement> displayedMeasurements,
    required List<ConfirmedAnomaly> visibleAnomalies,
    required ThermalCoverageInfo coverage,
    required ThermalPanoramaData panorama,
    required double peakTemp,
    required double? baselineTemp,
    Map<int, double> panelBaselines = const {},
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: const Key('toggle_advanced_telemetry'),
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              setState(() {
                _isAdvancedExpanded = !_isAdvancedExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Row(
                children: [
                  const Icon(
                    Icons.tune_rounded,
                    color: AppColors.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Detailed Scan Sections & Readings',
                          style: AppTypography.caption.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          'Thermal sensor grids and electrical yield',
                          style: AppTypography.caption.copyWith(
                            fontSize: 9.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${displayedMeasurements.length} frames',
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _isAdvancedExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_isAdvancedExpanded) ...[
            const Divider(height: 1, thickness: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Thermal Frames (5 cm Sectors)',
                        style: AppTypography.caption.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (coverage.hasConfiguredPanelLength)
                        Text(
                          'Expected: ${coverage.expectedAcquisitions} frames (${coverage.expectedThermalCoverageCm!.toStringAsFixed(1)} cm)',
                          style: AppTypography.caption.copyWith(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tap a frame to inspect its 32×24 matrix and exact sensor readings',
                    style: AppTypography.caption.copyWith(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),

                  // Horizontal frames carousel (Preserves thermal_frame_card_1, 2... keys for tests)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: displayedMeasurements.isEmpty
                          ? [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Text(
                                  'No frames recorded yet',
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ]
                          : displayedMeasurements.asMap().entries.map((entry) {
                              final idx = entry.key;
                              final f = entry.value;
                              final anomalyLabels = getFrameAnomalyLabels(
                                f,
                                visibleAnomalies,
                              );
                              final isConfirmed = anomalyLabels.isNotEmpty;
                              final isSelected = _selectedFrameIndex == idx;

                              final fovStart =
                                  f.xPositionCm - ThermalCoverageInfo.halfFovCm;
                              final fovEnd =
                                  f.xPositionCm + ThermalCoverageInfo.halfFovCm;

                              return InkWell(
                                key: Key('thermal_frame_card_${idx + 1}'),
                                borderRadius: BorderRadius.circular(10),
                                onTap: () {
                                  setState(() {
                                    _playbackTimer?.cancel();
                                    _playbackTimer = null;
                                    _selectedFrameIndex = idx;
                                    _timelineFrameIndex = idx;
                                  });
                                  _showFrameInspectorModal(
                                    context,
                                    displayedMeasurements,
                                    idx,
                                    panorama.minValidTempC ?? 20.0,
                                    panorama.maxValidTempC ?? peakTemp,
                                    baselineTemp,
                                    panorama: panorama,
                                    confirmedAnomalies: visibleAnomalies,
                                    panelBaselines: panelBaselines,
                                  );
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? (isConfirmed
                                            ? AppColors.errorBackground
                                            : AppColors.primarySoft)
                                        : (isConfirmed
                                            ? AppColors.errorBackground
                                            : AppColors.surface),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isSelected
                                          ? (isConfirmed
                                              ? AppColors.error
                                              : AppColors.primary)
                                          : (isConfirmed
                                              ? AppColors.error
                                              : AppColors.border),
                                      width: isSelected
                                          ? 2.0
                                          : (isConfirmed ? 1.5 : 1.0),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            isConfirmed
                                                ? Icons.warning_amber_rounded
                                                : Icons
                                                    .check_circle_outline_rounded,
                                            size: 14,
                                            color: isConfirmed
                                                ? AppColors.error
                                                : AppColors.success,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'F${idx + 1} (X=${f.xPositionCm.toStringAsFixed(1)} cm)',
                                            style:
                                                AppTypography.caption.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: isConfirmed
                                                  ? AppColors.error
                                                  : AppColors.textPrimary,
                                            ),
                                          ),
                                          if ((widget.module.panelCount !=
                                                      null &&
                                                  widget.module.panelCount! >
                                                      1) ||
                                              f.panelIndex != null ||
                                              f.localXPositionCm != null) ...[
                                            const SizedBox(width: 4),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 4,
                                                vertical: 1,
                                              ),
                                              decoration: BoxDecoration(
                                                color: AppColors.primarySoft,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                'Panel ${f.panelIndex ?? 1}${f.localXPositionCm != null ? " • Local: ${f.localXPositionCm!.toStringAsFixed(1)} cm" : ""}',
                                                style: const TextStyle(
                                                  color: AppColors.primary,
                                                  fontSize: 8,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ],
                                          if (isConfirmed) ...[
                                            const SizedBox(width: 4),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 4,
                                                vertical: 1,
                                              ),
                                              decoration: BoxDecoration(
                                                color: AppColors.error,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: const Text(
                                                'HOTSPOT',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 8,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                            ...anomalyLabels.map(
                                              (label) => Padding(
                                                padding: const EdgeInsets.only(
                                                  left: 3,
                                                ),
                                                child: Container(
                                                  key: Key(
                                                    'frame_${idx + 1}_badge_$label',
                                                  ),
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 4,
                                                    vertical: 1,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        AppColors.textPrimary,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      4,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    label,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 8,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Peak: ${f.maxTemperatureC.toStringAsFixed(1)}°C • Span: ${fovStart.toStringAsFixed(1)}-${fovEnd.toStringAsFixed(1)} cm',
                                        style: AppTypography.caption.copyWith(
                                          fontSize: 9.5,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Mini rail indicator showing the scanned interval relative to full panel or string length.
  Widget _buildRailProgressOverview({
    required double minFrameX,
    required double maxFrameX,
    required double panelLengthCm,
    int? panelCount,
    double? panelSpacingCm,
    int? focusedPanelIndex,
    List<PanelBound> panelBounds = const [],
    ThermalCoverageInfo? coverage,
    int loadedCount = 0,
  }) {
    final effectiveCount =
        (panelCount != null && panelCount > 0) ? panelCount : 1;
    final effectiveSpacing =
        (panelSpacingCm != null && panelSpacingCm >= 0) ? panelSpacingCm : 0.0;
    final totalRail = (effectiveCount * panelLengthCm) +
        ((effectiveCount - 1) * effectiveSpacing);

    final PanelBound? focusedBound = (focusedPanelIndex != null &&
            focusedPanelIndex >= 1 &&
            focusedPanelIndex <= panelBounds.length)
        ? panelBounds[focusedPanelIndex - 1]
        : null;

    final double startRatio;
    final double endRatio;
    final String coverageLabel;

    if (focusedBound != null) {
      startRatio =
          ((minFrameX - ThermalCoverageInfo.halfFovCm - focusedBound.startXCm) /
                  panelLengthCm)
              .clamp(0.0, 1.0);
      endRatio =
          ((maxFrameX + ThermalCoverageInfo.halfFovCm - focusedBound.startXCm) /
                  panelLengthCm)
              .clamp(0.0, 1.0);
      coverageLabel =
          'Rail Scan Coverage: ${minFrameX.toStringAsFixed(1)} to ${maxFrameX.toStringAsFixed(1)} cm of ${panelLengthCm.toStringAsFixed(0)} cm (Panel $focusedPanelIndex • ${focusedBound.startXCm.toStringAsFixed(0)}–${focusedBound.endXCm.toStringAsFixed(0)} cm)';
    } else {
      startRatio =
          ((minFrameX - ThermalCoverageInfo.halfFovCm) / totalRail).clamp(0.0, 1.0);
      endRatio =
          ((maxFrameX + ThermalCoverageInfo.halfFovCm) / totalRail).clamp(0.0, 1.0);
      coverageLabel =
          'Rail Scan Coverage: ${minFrameX.toStringAsFixed(1)} to ${maxFrameX.toStringAsFixed(1)} cm of ${totalRail.toStringAsFixed(0)} cm (${effectiveCount > 1 ? "$effectiveCount panels" : "Single panel"})';
    }
    final widthRatio = (endRatio - startRatio).clamp(0.02, 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  coverageLabel,
                  style: AppTypography.caption.copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${(widthRatio * 100).toStringAsFixed(0)}% scanned',
                style: AppTypography.caption.copyWith(
                  fontSize: 10,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          LayoutBuilder(
            builder: (context, constraints) {
              final barWidth = constraints.maxWidth;
              return Stack(
                children: [
                  Container(
                    height: 5,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Positioned(
                    left: startRatio * barWidth,
                    width: widthRatio * barWidth,
                    child: Container(
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          if (coverage != null && coverage.isIncompleteCoverage) ...[
            const SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Partial scan: $loadedCount of ${coverage.expectedAcquisitions} sections recorded',
                  key: const Key('notice_incomplete_coverage'),
                  style: AppTypography.caption.copyWith(
                    fontSize: 9.5,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (coverage.hasConfiguredPanelLength)
                  Text(
                    'Expected: ${coverage.expectedAcquisitions} frames (${coverage.expectedThermalCoverageCm!.toStringAsFixed(1)} cm)',
                    style: AppTypography.caption.copyWith(
                      fontSize: 9.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPostCleaningVerdictBanner({
    required List<HotspotVerificationSummary> summaries,
    required List<ModuleMeasurement> sortedRaw,
    required List<ModuleMeasurement> displayedMeasurements,
  }) {
    final total = summaries.length;
    final resolvedCount = summaries.where((s) => s.isResolved).length;
    final resolvedLaterCount = summaries.where((s) => s.isResolvedLater).length;
    final unresolvedCount = summaries.where((s) => s.isUnresolved).length;
    final pendingCount =
        summaries.where((s) => s.isPendingVerification).length;
    final unwashedCount = summaries.where((s) => s.isUnwashed).length;
    final clearedTotal = resolvedCount + resolvedLaterCount;

    final String title;
    final Color bg;
    final Color border;
    final Color accent;
    final IconData icon;

    if (unresolvedCount == 0 && pendingCount == 0 && unwashedCount == 0) {
      if (resolvedCount == 0 && resolvedLaterCount > 0) {
        title = 'Unresolved by Wash · Cleared in Later Scan';
        bg = AppColors.primarySoft.withValues(alpha: 0.65);
        border = AppColors.primary.withValues(alpha: 0.35);
        accent = AppColors.primary;
        icon = Icons.verified_outlined;
      } else if (resolvedLaterCount > 0) {
        title = 'Post-Cleaning Verified · All Hotspots Cleared';
        bg = AppColors.successBackground;
        border = AppColors.successBorder;
        accent = AppColors.success;
        icon = Icons.task_alt_rounded;
      } else {
        title = total == 1
            ? 'Post-Cleaning Verified · Hotspot Resolved'
            : 'Post-Cleaning Verified · All Hotspots Resolved';
        bg = AppColors.successBackground;
        border = AppColors.successBorder;
        accent = AppColors.success;
        icon = Icons.task_alt_rounded;
      }
    } else if (clearedTotal > 0) {
      title = 'Post-Cleaning Check · $clearedTotal of $total Resolved';
      bg = AppColors.warningBackground;
      border = AppColors.warningBorder;
      accent = AppColors.warning;
      icon = Icons.rule_rounded;
    } else if (unresolvedCount > 0) {
      title = total == 1
          ? 'Post-Cleaning Check · Hotspot Still Present'
          : 'Post-Cleaning Check · $unresolvedCount Unresolved';
      bg = AppColors.errorBackground;
      border = AppColors.errorBorder;
      accent = AppColors.error;
      icon = Icons.warning_amber_rounded;
    } else {
      title = 'Post-Cleaning Check · Verification Pending';
      bg = AppColors.primarySoft.withValues(alpha: 0.65);
      border = AppColors.primary.withValues(alpha: 0.35);
      accent = AppColors.primary;
      icon = Icons.hourglass_top_rounded;
    }

    return Container(
      key: const Key('post_cleaning_verdict_banner'),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.caption.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...summaries.asMap().entries.map((entry) {
            final idx = entry.key;
            final s = entry.value;
            final pIdx = (s.anomaly.panelIndex != null &&
                    s.anomaly.panelIndex! > 0)
                ? s.anomaly.panelIndex!
                : widget.module
                    .resolvePanelPosition(s.anomaly.xPositionCm)
                    .panelIndex;

            final String tempPart;
            if (s.afterTempC != null) {
              final d = s.deltaChangeC!;
              final dSign = d >= 0 ? '+' : '';
              tempPart =
                  '${s.beforeTempC.toStringAsFixed(1)} °C → ${s.afterTempC!.toStringAsFixed(1)} °C ($dSign${d.toStringAsFixed(1)} °C)';
            } else {
              tempPart = '${s.beforeTempC.toStringAsFixed(1)} °C';
            }

            final String outcomeLabel;
            final Color rowColor;
            switch (s.outcome) {
              case 'resolved':
                outcomeLabel = 'Resolved';
                rowColor = AppColors.success;
                break;
              case 'resolved_later':
                outcomeLabel = 'Cleared in Later Scan';
                rowColor = AppColors.primary;
                break;
              case 'unresolved':
                outcomeLabel = 'Unresolved';
                rowColor = AppColors.error;
                break;
              case 'pending_verification':
                outcomeLabel = 'Pending';
                rowColor = AppColors.warning;
                break;
              default:
                outcomeLabel = 'Unwashed';
                rowColor = AppColors.textSecondary;
            }

            final rowText =
                'P$pIdx · X = ${s.anomaly.xPositionCm.toStringAsFixed(1)} cm: $tempPart · $outcomeLabel';

            return Padding(
              padding: EdgeInsets.only(top: idx == 0 ? 0 : 4),
              child: InkWell(
                key: Key('verdict_hotspot_row_${idx + 1}'),
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  final switchPanelToAll = _focusedPanelIndex != null &&
                      pIdx > 0 &&
                      _focusedPanelIndex != pIdx;
                  final targetFrames = switchPanelToAll
                      ? sortedRaw
                      : displayedMeasurements;
                  if (targetFrames.isEmpty) return;

                  int bestIdx = 0;
                  double bestDist = double.infinity;
                  for (var i = 0; i < targetFrames.length; i++) {
                    final f = targetFrames[i];
                    final samePanel = f.panelIndex == null ||
                        f.panelIndex! <= 0 ||
                        pIdx <= 0 ||
                        f.panelIndex == pIdx;
                    final dist = (f.xPositionCm - s.anomaly.xPositionCm).abs() +
                        (samePanel ? 0.0 : 10000.0);
                    if (dist < bestDist) {
                      bestDist = dist;
                      bestIdx = i;
                    }
                  }

                  setState(() {
                    _playbackTimer?.cancel();
                    _playbackTimer = null;
                    if (switchPanelToAll) {
                      _focusedPanelIndex = null;
                    }
                    _timelineFrameIndex = bestIdx;
                    _selectedFrameIndex = bestIdx;
                  });
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: border.withValues(alpha: 0.6)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: rowColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          rowText,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.my_location_rounded,
                        size: 13,
                        color: rowColor,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPanelSelector(
    int panelCount,
    List<ConfirmedAnomaly> confirmedAnomalies,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildPanelChip(
            key: const Key('panel_chip_all'),
            label: 'All Panels',
            badgeText: '$panelCount',
            isSelected: _focusedPanelIndex == null,
            hasAnomaly: false,
            onTap: () => setState(() {
              _focusedPanelIndex = null;
              _selectedFrameIndex = null;
              _selectedHotspotIndex = null;
            }),
          ),
          for (var p = 1; p <= panelCount; p++) ...[
            const SizedBox(width: 6),
            _buildPanelChip(
              key: Key('panel_chip_$p'),
              label: 'Panel $p',
              isSelected: _focusedPanelIndex == p,
              hasAnomaly: confirmedAnomalies.any((a) {
                if (a.panelIndex != null) return a.panelIndex == p;
                return widget.module
                        .resolvePanelPosition(a.xPositionCm)
                        .panelIndex ==
                    p;
              }),
              onTap: () => setState(() {
                _focusedPanelIndex = p;
                _selectedFrameIndex = null;
                _selectedHotspotIndex = null;
              }),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPanelChip({
    Key? key,
    required String label,
    String? badgeText,
    required bool isSelected,
    required bool hasAnomaly,
    required VoidCallback onTap,
  }) {
    final borderColor = isSelected
        ? AppColors.primary
        : (hasAnomaly ? AppColors.error : AppColors.border);
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : (hasAnomaly ? AppColors.errorBackground : AppColors.surface),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: borderColor,
            width: (isSelected || hasAnomaly) ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppTypography.caption.copyWith(
                fontSize: 11,
                fontWeight: (isSelected || hasAnomaly)
                    ? FontWeight.w700
                    : FontWeight.w500,
                color: isSelected
                    ? Colors.white
                    : (hasAnomaly ? AppColors.error : AppColors.textSecondary),
              ),
            ),
            if (badgeText != null) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.22)
                      : AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: isSelected ? Colors.white : AppColors.primary,
                  ),
                ),
              ),
            ],
            if (hasAnomaly) ...[
              const SizedBox(width: 5),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : AppColors.error,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Explainer banner showing which frames confirmed each hotspot (Option A: Compact & Collapsible).
  Widget _buildHotspotConfirmationSummary({
    required List<ConfirmedAnomaly> confirmedAnomalies,
    required List<ModuleMeasurement> sortedMeasurements,
  }) {
    final count = confirmedAnomalies.length;
    final isMultiple = count > 1;

    return Container(
      key: const Key('hotspot_confirmation_summary'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () {
              setState(() {
                _isHotspotSummaryExpanded = !_isHotspotSummaryExpanded;
              });
            },
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.error,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isMultiple
                        ? '$count Hotspots Confirmed (Double-Checked)'
                        : 'Confirmed Hotspot (Double-Checked)',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.error,
                      fontWeight: FontWeight.w800,
                      fontSize: 10.5,
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _isHotspotSummaryExpanded ? 'Hide' : 'Details',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.error,
                        fontWeight: FontWeight.w700,
                        fontSize: 9.5,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      _isHotspotSummaryExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 15,
                      color: AppColors.error,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_isHotspotSummaryExpanded || !isMultiple) ...[
            const SizedBox(height: 3),
            ...confirmedAnomalies.asMap().entries.map((entry) {
              final idx = entry.key;
              final anomaly = entry.value;
              final confirmingFrames = sortedMeasurements
                  .asMap()
                  .entries
                  .where((mEntry) => isFrameAssociatedWithAnomaly(mEntry.value, anomaly))
                  .map((mEntry) => 'F${mEntry.key + 1} (${mEntry.value.xPositionCm.toStringAsFixed(1)} cm)')
                  .toList();

              final framesText = confirmingFrames.isNotEmpty
                  ? confirmingFrames.join(' and ')
                  : 'Overlapping frames';

              final panelStr = anomaly.panelIndex != null
                  ? 'Panel ${anomaly.panelIndex} • '
                  : '';
              final localStr = anomaly.localXPositionCm != null
                  ? ' (local: ${anomaly.localXPositionCm!.toStringAsFixed(1)} cm)'
                  : '';

              return Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '• ${panelStr}H${idx + 1} at X=${anomaly.xPositionCm.toStringAsFixed(1)} cm$localStr confirmed by: $framesText',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 10,
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  /// Item 1: Interactive Robot Carriage Timeline Scrubber.
  Widget _buildRobotTimelineScrubber({
    required BuildContext context,
    required List<ModuleMeasurement> sortedFrames,
    required int? hotspotIndex,
    required double minTemp,
    required double maxTemp,
    required double? baselineTemp,
    required ThermalPanoramaData panorama,
    required List<ConfirmedAnomaly> confirmedAnomalies,
    Map<int, double> panelBaselines = const {},
  }) {
    final total = sortedFrames.length;
    final activeIndex = _timelineFrameIndex.clamp(0, total - 1);
    final activeFrame = sortedFrames[activeIndex];
    final isHotspotFrame = confirmedAnomalies.any(
      (a) => isFrameAssociatedWithAnomaly(activeFrame, a),
    );
    final alignX = total > 1 ? -1.0 + (2.0 * (activeIndex / (total - 1))) : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                key: const Key('scrubber_frame_selector_chip'),
                borderRadius: BorderRadius.circular(5),
                onTap: () {
                  _showQuickFrameSelector(
                    context: context,
                    sortedFrames: sortedFrames,
                    activeIndex: activeIndex,
                    confirmedAnomalies: confirmedAnomalies,
                    minTemp: minTemp,
                    maxTemp: maxTemp,
                    baselineTemp: baselineTemp,
                    panorama: panorama,
                    panelBaselines: panelBaselines,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isHotspotFrame ? AppColors.error : AppColors.primary,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'F${activeIndex + 1}/$total',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 1),
                      const Icon(
                        Icons.arrow_drop_down_rounded,
                        color: Colors.white,
                        size: 13,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'X = ${activeFrame.xPositionCm.toStringAsFixed(1)} cm',
                style: AppTypography.caption.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'T_max = ${activeFrame.maxTemperatureC.toStringAsFixed(1)}°C',
                style: AppTypography.caption.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isHotspotFrame ? AppColors.error : AppColors.primary,
                ),
              ),
              const Spacer(),
              if (hotspotIndex != null) ...[
                InkWell(
                  key: const Key('jump_to_hotspot_button'),
                  borderRadius: BorderRadius.circular(6),
                  onTap: () {
                    setState(() {
                      _playbackTimer?.cancel();
                      _playbackTimer = null;
                      _timelineFrameIndex = hotspotIndex.clamp(0, total - 1);
                      _selectedFrameIndex = _timelineFrameIndex;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2.5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.errorBackground,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.errorBorder),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.local_fire_department_rounded,
                          size: 11,
                          color: AppColors.error,
                        ),
                        SizedBox(width: 3),
                        Text(
                          'Hotspot',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: AppColors.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              InkWell(
                key: const Key('inspect_frame_modal_button'),
                borderRadius: BorderRadius.circular(6),
                onTap: () {
                  setState(() {
                    _playbackTimer?.cancel();
                    _playbackTimer = null;
                    _selectedFrameIndex = activeIndex;
                    _timelineFrameIndex = activeIndex;
                  });
                  _showFrameInspectorModal(
                    context,
                    sortedFrames,
                    activeIndex,
                    minTemp,
                    maxTemp,
                    baselineTemp,
                    panorama: panorama,
                    confirmedAnomalies: confirmedAnomalies,
                    panelBaselines: panelBaselines,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2.5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.grid_on_rounded,
                        size: 11,
                        color: AppColors.primary,
                      ),
                      SizedBox(width: 3),
                      Text(
                        '32×24',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              InkWell(
                key: const Key('robot_timeline_prev_button'),
                borderRadius: BorderRadius.circular(6),
                onTap: () {
                  setState(() {
                    _playbackTimer?.cancel();
                    _playbackTimer = null;
                    _timelineFrameIndex = (activeIndex - 1).clamp(0, total - 1);
                    _selectedFrameIndex = _timelineFrameIndex;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(
                    Icons.chevron_left_rounded,
                    size: 16,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                key: const Key('robot_timeline_play_button'),
                borderRadius: BorderRadius.circular(6),
                onTap: () => _toggleTimelinePlayback(sortedFrames),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: _isPlaying ? AppColors.primary : AppColors.surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _isPlaying ? AppColors.primary : AppColors.border,
                    ),
                  ),
                  child: Icon(
                    _isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 16,
                    color: _isPlaying ? Colors.white : AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                key: const Key('robot_timeline_next_button'),
                borderRadius: BorderRadius.circular(6),
                onTap: () {
                  setState(() {
                    _playbackTimer?.cancel();
                    _playbackTimer = null;
                    _timelineFrameIndex = (activeIndex + 1).clamp(0, total - 1);
                    _selectedFrameIndex = _timelineFrameIndex;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final trackWidth = constraints.maxWidth.clamp(
                      1.0,
                      double.infinity,
                    );
                    void scrubAt(double dx) {
                      final ratio = (dx / trackWidth).clamp(0.0, 1.0);
                      final newIdx = total > 1
                          ? (ratio * (total - 1)).round().clamp(0, total - 1)
                          : 0;
                      setState(() {
                        _playbackTimer?.cancel();
                        _playbackTimer = null;
                        _timelineFrameIndex = newIdx;
                        _selectedFrameIndex = newIdx;
                      });
                    }

                    return GestureDetector(
                      key: const Key('robot_timeline_scrubber'),
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) =>
                          scrubAt(details.localPosition.dx),
                      onHorizontalDragUpdate: (details) =>
                          scrubAt(details.localPosition.dx),
                      child: SizedBox(
                        height: 24,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              height: 6,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: AppColors.border,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: total > 1
                                    ? (activeIndex / (total - 1)).clamp(
                                        0.0,
                                        1.0,
                                      )
                                    : 1.0,
                                child: Container(
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: isHotspotFrame
                                        ? AppColors.error
                                        : AppColors.primary,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                            AnimatedAlign(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              alignment: Alignment(alignX, 0.0),
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: isHotspotFrame
                                      ? AppColors.error
                                      : AppColors.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 1.5,
                                  ),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.precision_manufacturing_rounded,
                                    key: Key('robot_timeline_icon'),
                                    size: 13,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Item 3: 1D Thermal Profile Curve in a Collapsible Accordion (Closed by Default).
  Widget _buildThermalProfileCurveAccordion({
    required List<ModuleMeasurement> sortedFrames,
    required double? baselineTemp,
    Map<int, double> panelBaselines = const {},
    List<PanelBound> panelBounds = const [],
    double hotspotDeltaThresholdC = 8.0,
  }) {
    final activeIndex = _timelineFrameIndex.clamp(0, sortedFrames.length - 1);
    final threshold =
        hotspotDeltaThresholdC > 0 ? hotspotDeltaThresholdC : 8.0;
    final distinctBaselines = <double>{};
    for (final f in sortedFrames) {
      final b = resolveFrameBaseline(
        f,
        panelBaselines,
        baselineTemp,
        widget.module,
        panelBounds: panelBounds,
      );
      if (b != null && b > 0) {
        distinctBaselines.add(double.parse(b.toStringAsFixed(2)));
      }
    }
    final String? curveSubtitle;
    if (distinctBaselines.length > 1) {
      curveSubtitle =
          'Per-panel Normal • Alert: +${threshold.toStringAsFixed(1)}°C';
    } else {
      final singleBase = distinctBaselines.length == 1
          ? distinctBaselines.first
          : baselineTemp;
      curveSubtitle = (singleBase != null && singleBase > 0)
          ? 'Normal: ${singleBase.toStringAsFixed(1)}°C • Alert Level: ${(singleBase + threshold).toStringAsFixed(1)}°C'
          : null;
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: const Key('thermal_profile_curve_toggle'),
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              setState(() {
                _isProfileCurveExpanded = !_isProfileCurveExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Row(
                children: [
                  const Icon(
                    Icons.show_chart_rounded,
                    color: AppColors.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Temperature Chart Along Panel',
                      style: AppTypography.caption.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Icon(
                    _isProfileCurveExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_isProfileCurveExpanded) ...[
            const Divider(height: 1, thickness: 1, color: AppColors.border),
            Container(
              key: const Key('thermal_profile_curve_card'),
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          'Highest Temperature by Position along the Track',
                          style: AppTypography.caption.copyWith(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (curveSubtitle != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          curveSubtitle,
                          style: AppTypography.caption.copyWith(
                            fontSize: 9.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 150,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: _ThermalProfileCurvePainter(
                        sortedFrames: sortedFrames,
                        activeFrameIndex: activeIndex,
                        baselineTempC: baselineTemp,
                        panelBaselines: panelBaselines,
                        panelBounds: panelBounds,
                        hotspotDeltaThresholdC: threshold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Quick Frame Selector Modal Bottom Sheet (tap on Fx/y scrubber chip).
  void _showQuickFrameSelector({
    required BuildContext context,
    required List<ModuleMeasurement> sortedFrames,
    required int activeIndex,
    required List<ConfirmedAnomaly> confirmedAnomalies,
    required double minTemp,
    required double maxTemp,
    required double? baselineTemp,
    required ThermalPanoramaData panorama,
    Map<int, double> panelBaselines = const {},
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.65,
          ),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Row(
                children: [
                  const Icon(
                    Icons.view_timeline_outlined,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Jump to Section (${sortedFrames.length} frames)',
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Select any section along the rail to inspect instantly:',
                style: AppTypography.caption.copyWith(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              // Scrollable Wrap of frame chips
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: sortedFrames.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final frame = entry.value;
                      final isSelected = idx == activeIndex;
                      final isHotspot = confirmedAnomalies.any(
                        (a) => isFrameAssociatedWithAnomaly(frame, a),
                      );

                      return InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          setState(() {
                            _playbackTimer?.cancel();
                            _playbackTimer = null;
                            _timelineFrameIndex = idx;
                            _selectedFrameIndex = idx;
                          });
                          Navigator.of(ctx).pop();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? (isHotspot
                                    ? AppColors.error
                                    : AppColors.primary)
                                : (isHotspot
                                    ? AppColors.errorBackground
                                    : AppColors.background),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected
                                  ? (isHotspot
                                      ? AppColors.error
                                      : AppColors.primary)
                                  : (isHotspot
                                      ? AppColors.errorBorder
                                      : AppColors.border),
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isHotspot) ...[
                                Icon(
                                  Icons.local_fire_department_rounded,
                                  size: 11,
                                  color: isSelected ? Colors.white : AppColors.error,
                                ),
                                const SizedBox(width: 3),
                              ],
                              Text(
                                'F${idx + 1}',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: isSelected
                                      ? Colors.white
                                      : (isHotspot
                                          ? AppColors.error
                                          : AppColors.textPrimary),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${frame.xPositionCm.toStringAsFixed(0)}cm',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  color: isSelected
                                      ? Colors.white.withValues(alpha: 0.8)
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Footer Action: Inspect current frame matrix 32x24
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _showFrameInspectorModal(
                      context,
                      sortedFrames,
                      activeIndex,
                      minTemp,
                      maxTemp,
                      baselineTemp,
                      panorama: panorama,
                      confirmedAnomalies: confirmedAnomalies,
                      panelBaselines: panelBaselines,
                    );
                  },
                  icon: const Icon(Icons.grid_on_rounded, size: 14),
                  label: Text('Inspect 32×24 Matrix for F${activeIndex + 1}'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    textStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Item 2: 32×24 Matrix Inspector in a Modal Bottom Sheet with Pixel Crosshair.
  void _showFrameInspectorModal(
    BuildContext context,
    List<ModuleMeasurement> sortedFrames,
    int initialFrameIndex,
    double minTemp,
    double maxTemp,
    double? baselineTemp, {
    required ThermalPanoramaData panorama,
    required List<ConfirmedAnomaly> confirmedAnomalies,
    Map<int, double> panelBaselines = const {},
  }) {
    if (sortedFrames.isEmpty) return;
    var currentFrameIndex = initialFrameIndex.clamp(0, sortedFrames.length - 1);
    final effectivePanelBaselines =
        panelBaselines.isNotEmpty ? panelBaselines : panorama.panelBaselines;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            final measurement = sortedFrames[currentFrameIndex];
            final tf = measurement.thermalFrame;
            final activeFrameBaseline = resolveFrameBaseline(
              measurement,
              effectivePanelBaselines,
              baselineTemp,
              widget.module,
              panelBounds: panorama.panelBounds,
            );
            final frameDelta =
                (activeFrameBaseline != null && activeFrameBaseline > 0)
                    ? (measurement.maxTemperatureC - activeFrameBaseline)
                    : null;
            final anomalyLabels = getFrameAnomalyLabels(
              measurement,
              confirmedAnomalies,
            );
            final isConfirmed = anomalyLabels.isNotEmpty;

            return SafeArea(
              child: SingleChildScrollView(
                child: Container(
                  key: const Key('selected_frame_inspector'),
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isConfirmed ? AppColors.error : AppColors.primary,
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isConfirmed
                                        ? AppColors.error
                                        : AppColors.primary,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'F${currentFrameIndex + 1}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                Text(
                                  'Selected Frame (X = ${measurement.xPositionCm.toStringAsFixed(1)} cm)',
                                  style: AppTypography.caption.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                if (measurement.panelIndex != null ||
                                    measurement.localXPositionCm != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.primarySoft,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '${measurement.panelIndex != null ? "Panel ${measurement.panelIndex}" : ""}${measurement.panelIndex != null && measurement.localXPositionCm != null ? " • " : ""}${measurement.localXPositionCm != null ? "Local: ${measurement.localXPositionCm!.toStringAsFixed(1)} cm" : ""}',
                                      style: const TextStyle(
                                        color: AppColors.primary,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              Navigator.of(modalContext).pop();
                              if (mounted) {
                                setState(() {
                                  _selectedFrameIndex = null;
                                });
                              }
                            },
                            icon: const Icon(
                              Icons.close_rounded,
                              size: 14,
                              color: AppColors.textSecondary,
                            ),
                            label: Text(
                              'Close',
                              style: AppTypography.caption.copyWith(
                                fontSize: 10,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Modal Frame Navigation (< Prev / Next >)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          InkWell(
                            key: const Key('modal_prev_frame_button'),
                            borderRadius: BorderRadius.circular(6),
                            onTap: currentFrameIndex > 0
                                ? () {
                                    final nextIdx = currentFrameIndex - 1;
                                    setModalState(() {
                                      currentFrameIndex = nextIdx;
                                    });
                                    if (mounted) {
                                      setState(() {
                                        _selectedFrameIndex = nextIdx;
                                        _timelineFrameIndex = nextIdx;
                                      });
                                    }
                                  }
                                : null,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Text(
                                '< Prev',
                                style: AppTypography.caption.copyWith(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: currentFrameIndex > 0
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                          Text(
                            'Frame ${currentFrameIndex + 1} of ${sortedFrames.length} • Range ${minTemp.toStringAsFixed(1)}–${maxTemp.toStringAsFixed(1)}°C',
                            style: AppTypography.caption.copyWith(
                              fontSize: 10,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          InkWell(
                            key: const Key('modal_next_frame_button'),
                            borderRadius: BorderRadius.circular(6),
                            onTap: currentFrameIndex < sortedFrames.length - 1
                                ? () {
                                    final nextIdx = currentFrameIndex + 1;
                                    setModalState(() {
                                      currentFrameIndex = nextIdx;
                                    });
                                    if (mounted) {
                                      setState(() {
                                        _selectedFrameIndex = nextIdx;
                                        _timelineFrameIndex = nextIdx;
                                      });
                                    }
                                  }
                                : null,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Text(
                                'Next >',
                                style: AppTypography.caption.copyWith(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: currentFrameIndex <
                                          sortedFrames.length - 1
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Shared Interactive 32x24 Thermal Matrix View with Pixel Crosshair
                      InteractiveThermalMatrixView(
                        thermalFrame: tf ?? const <double?>[],
                        colorForTemperature: (tempC) =>
                            panorama.colorForTemperature(
                          tempC,
                          baselineOverrideC: activeFrameBaseline,
                        ),
                        fallbackPeakTemp: measurement.maxTemperatureC,
                        baselineTemp: activeFrameBaseline,
                        hotspotDeltaThresholdC:
                            widget.module.hotspotThresholdDeltaC,
                        scaleColors: panorama.scaleGradientColors,
                        showStatsRow: true,
                        showColorScale: true,
                        canvasHeight: 150,
                        frameIdentity: '${measurement.id}_$currentFrameIndex',
                      ),
                      const SizedBox(height: 8),

                      SizedBox(
                        width: double.infinity,
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Text(
                              'Span: ${(measurement.xPositionCm - 2.5).toStringAsFixed(1)} - ${(measurement.xPositionCm + 2.5).toStringAsFixed(1)} cm',
                              style: AppTypography.caption.copyWith(
                                fontSize: 10,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            Text(
                              frameDelta != null
                                  ? 'Peak: ${measurement.maxTemperatureC.toStringAsFixed(1)}°C (${frameDelta >= 0 ? '+' : ''}${frameDelta.toStringAsFixed(1)} °C)'
                                  : 'Peak: ${measurement.maxTemperatureC.toStringAsFixed(1)}°C',
                              style: AppTypography.caption.copyWith(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: isConfirmed
                                    ? AppColors.error
                                    : AppColors.textPrimary,
                              ),
                            ),
                            if ((measurement.voltageV ?? 0.0) > 0.05)
                              Text(
                                '${measurement.voltageV!.toStringAsFixed(2)}V • ${measurement.currentA != null ? "${(measurement.currentA! * 1000).toStringAsFixed(1)}mA" : "0.0mA"}',
                                style: AppTypography.caption.copyWith(
                                  fontSize: 10,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<Widget> _buildStateNotices({
    required ThermalPanoramaData panorama,
    required ThermalCoverageInfo coverage,
  }) {
    final notices = <Widget>[];
    final loadedCount = panorama.sortedMeasurements.length;

    if (loadedCount > 0 && panorama.framesWithoutMatrixCount > 0) {
      notices.add(
        _buildNoticeBanner(
          key: const Key('notice_missing_thermal_frame'),
          icon: Icons.grid_off_rounded,
          text:
              'Summary temperature only (${panorama.framesWithoutMatrixCount} of $loadedCount sections)',
          isWarning: false,
        ),
      );
    }

    if (panorama.hasInvalidPixels) {
      notices.add(
        _buildNoticeBanner(
          key: const Key('notice_invalid_pixels'),
          icon: Icons.auto_fix_high_outlined,
          text:
              '${panorama.totalInvalidPixelsInFrames} sensor points smoothed from nearby scans',
          isWarning: panorama.unresolvedInvalidCellCount > 0,
        ),
      );
    }

    if (panorama.anomaliesWithoutLoadedConfirmingFrames.isNotEmpty) {
      notices.add(
        _buildNoticeBanner(
          key: const Key('notice_unlinked_anomalies'),
          icon: Icons.link_off_rounded,
          text:
              'Hotspot verification frames pending (${panorama.anomaliesWithoutLoadedConfirmingFrames.length})',
          isWarning: true,
        ),
      );
    }

    if (coverage.isPartiallyLoadedByPagination) {
      notices.add(
        _buildNoticeBanner(
          key: const Key('notice_partial_pagination'),
          icon: Icons.filter_list_rounded,
          text:
              'Showing $loadedCount of ${coverage.totalInspectionMeasurements} scan points',
          isWarning: true,
        ),
      );
    }

    if (coverage.isExceededCoverage) {
      notices.add(
        _buildNoticeBanner(
          key: const Key('notice_exceeded_coverage'),
          icon: Icons.info_outline_rounded,
          text:
              'Extended scan: $loadedCount sections recorded (${coverage.expectedAcquisitions} expected)',
          isWarning: false,
        ),
      );
    }

    if (notices.isEmpty) return const [];
    return [
      const SizedBox(height: 4),
      ...notices,
    ];
  }

  Widget _buildNoticeBanner({
    required Key key,
    required IconData icon,
    required String text,
    required bool isWarning,
  }) {
    return Container(
      key: key,
      width: double.infinity,
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isWarning
            ? AppColors.warning.withValues(alpha: 0.07)
            : AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isWarning
              ? AppColors.warning.withValues(alpha: 0.25)
              : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 13,
            color: isWarning ? AppColors.warning : AppColors.textSecondary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: AppTypography.caption.copyWith(
                fontSize: 10,
                color: isWarning ? AppColors.warning : AppColors.textSecondary,
                fontWeight: isWarning ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildRulerTicks({
    required double minDomainX,
    required double maxDomainX,
    required double Function(double xCm) xToPx,
    required double maxWidth,
  }) {
    final widgets = <Widget>[];
    final span = maxDomainX - minDomainX;

    double step;
    if (span <= 12.0) {
      step = 2.0;
    } else if (span <= 30.0) {
      step = 5.0;
    } else if (span <= 80.0) {
      step = 10.0;
    } else {
      step = 20.0;
    }

    final startTick = (minDomainX / step).ceil() * step;
    for (double x = startTick; x <= maxDomainX; x += step) {
      final leftPx = xToPx(x);
      widgets.add(
        Positioned(
          left: (leftPx - 10).clamp(2.0, math.max(2.0, maxWidth - 28.0)).toDouble(),
          top: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${x.toInt()}cm',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 7.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Container(
                width: 1,
                height: 4,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      );
    }
    return widgets;
  }

  Widget _buildBadge(String text, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.error.withValues(alpha: 0.85)
            : Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required String subtext,
    bool isWarning = false,
    Color? valueColor,
    String? deltaBadge,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isWarning ? AppColors.errorBackground : AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isWarning ? AppColors.errorBorder : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: AppTypography.caption.copyWith(
                  color: isWarning ? AppColors.error : AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
              if (deltaBadge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    deltaBadge,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTypography.h3.copyWith(
              color: isWarning
                  ? AppColors.error
                  : (valueColor ?? AppColors.textPrimary),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtext,
            style: AppTypography.caption.copyWith(
              color: isWarning ? AppColors.error : AppColors.textSecondary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

/// Item 3: CustomPainter for the 1D Thermal Profile Curve along the rail.
class _ThermalProfileCurvePainter extends CustomPainter {
  const _ThermalProfileCurvePainter({
    required this.sortedFrames,
    required this.activeFrameIndex,
    this.baselineTempC,
    this.panelBaselines = const {},
    this.panelBounds = const [],
    this.hotspotDeltaThresholdC = 8.0,
  });

  final List<ModuleMeasurement> sortedFrames;
  final int activeFrameIndex;
  final double? baselineTempC;
  final Map<int, double> panelBaselines;
  final List<PanelBound> panelBounds;
  final double hotspotDeltaThresholdC;

  void _drawDashedHorizontalLine(
    Canvas canvas,
    double y,
    double left,
    double right,
    Paint paint,
  ) {
    const dashWidth = 5.0;
    const dashSpace = 4.0;
    var x = left;
    while (x < right) {
      final endX = math.min(x + dashWidth, right);
      canvas.drawLine(Offset(x, y), Offset(endX, y), paint);
      x += dashWidth + dashSpace;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..color = AppColors.surface
      ..style = PaintingStyle.fill;
    final bgRRect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(8),
    );
    canvas.drawRRect(bgRRect, bgPaint);

    if (sortedFrames.isEmpty) return;

    const padLeft = 34.0;
    const padRight = 14.0;
    const padTop = 14.0;
    const padBottom = 22.0;
    final plotW = math.max(10.0, size.width - padLeft - padRight);
    final plotH = math.max(10.0, size.height - padTop - padBottom);

    var minTemp = sortedFrames.first.maxTemperatureC;
    var maxTemp = sortedFrames.first.maxTemperatureC;
    for (final f in sortedFrames) {
      if (f.maxTemperatureC < minTemp) minTemp = f.maxTemperatureC;
      if (f.maxTemperatureC > maxTemp) maxTemp = f.maxTemperatureC;
    }

    final threshold =
        hotspotDeltaThresholdC > 0 ? hotspotDeltaThresholdC : 8.0;
    final resolvedBaselines = <double?>[
      for (final f in sortedFrames)
        resolveFrameBaseline(
          f,
          panelBaselines,
          baselineTempC,
          null,
          panelBounds: panelBounds,
        ),
    ];

    for (final base in resolvedBaselines) {
      if (base != null && base > 0) {
        minTemp = math.min(minTemp, base);
        maxTemp = math.max(maxTemp, base + threshold);
      }
    }

    final minY = minTemp - 2.0;
    final maxY = math.max(minY + 6.0, maxTemp + 2.0);
    final spanY = maxY - minY;

    double tempToY(double t) {
      final ratio = ((t - minY) / spanY).clamp(0.0, 1.0);
      return padTop + plotH * (1.0 - ratio);
    }

    final minXCm = sortedFrames.first.xPositionCm;
    final maxXCm = sortedFrames.last.xPositionCm;
    final spanXCm = maxXCm - minXCm;

    double indexToX(int idx) {
      if (sortedFrames.length <= 1) return padLeft + plotW / 2.0;
      if (spanXCm > 1e-6) {
        final ratio =
            ((sortedFrames[idx].xPositionCm - minXCm) / spanXCm).clamp(
          0.0,
          1.0,
        );
        return padLeft + ratio * plotW;
      }
      return padLeft + (idx / (sortedFrames.length - 1)) * plotW;
    }

    // Subtle horizontal grid lines & Y labels
    final gridPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 0.8;
    for (final ratio in [0.0, 0.5, 1.0]) {
      final tVal = minY + ratio * spanY;
      final y = tempToY(tVal);
      canvas.drawLine(Offset(padLeft, y), Offset(padLeft + plotW, y), gridPaint);
      final tp = TextPainter(
        text: TextSpan(
          text: '${tVal.toStringAsFixed(0)}°',
          style: const TextStyle(
            fontSize: 8.5,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(4, y - tp.height / 2));
    }

    // Dashed per-panel Baseline & Threshold lines
    final basePaint = Paint()
      ..color = AppColors.secondary
      ..strokeWidth = 1.2;
    final threshPaint = Paint()
      ..color = AppColors.error
      ..strokeWidth = 1.2;

    var segStart = 0;
    while (segStart < sortedFrames.length) {
      final segBase = resolvedBaselines[segStart];
      var segEnd = segStart;
      while (segEnd + 1 < sortedFrames.length &&
          resolvedBaselines[segEnd + 1] == segBase) {
        segEnd++;
      }
      if (segBase != null && segBase > 0) {
        final leftX = segStart == 0
            ? padLeft
            : (indexToX(segStart - 1) + indexToX(segStart)) / 2.0;
        final rightX = segEnd == sortedFrames.length - 1
            ? padLeft + plotW
            : (indexToX(segEnd) + indexToX(segEnd + 1)) / 2.0;
        _drawDashedHorizontalLine(
          canvas,
          tempToY(segBase),
          leftX,
          rightX,
          basePaint,
        );
        _drawDashedHorizontalLine(
          canvas,
          tempToY(segBase + threshold),
          leftX,
          rightX,
          threshPaint,
        );
      }
      segStart = segEnd + 1;
    }

    // Plot curve and points
    final points = <Offset>[
      for (var i = 0; i < sortedFrames.length; i++)
        Offset(indexToX(i), tempToY(sortedFrames[i].maxTemperatureC)),
    ];

    if (points.length > 1) {
      final fillPath = Path()..moveTo(points.first.dx, padTop + plotH);
      for (final p in points) {
        fillPath.lineTo(p.dx, p.dy);
      }
      fillPath.lineTo(points.last.dx, padTop + plotH);
      fillPath.close();

      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.primary.withValues(alpha: 0.22),
            AppColors.primary.withValues(alpha: 0.02),
          ],
        ).createShader(Rect.fromLTWH(padLeft, padTop, plotW, plotH))
        ..style = PaintingStyle.fill;
      canvas.drawPath(fillPath, fillPaint);

      final linePath = Path()..moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length; i++) {
        linePath.lineTo(points[i].dx, points[i].dy);
      }
      final linePaint = Paint()
        ..color = AppColors.primary
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(linePath, linePaint);
    }

    for (var i = 0; i < points.length; i++) {
      final pt = points[i];
      final frame = sortedFrames[i];
      final isElevated = isMeasurementElevated(
        frame,
        panelBaselines: panelBaselines,
        fallbackBaseline: baselineTempC,
        panelBounds: panelBounds,
        hotspotDeltaThresholdC: threshold,
      );
      final isActive = i == activeFrameIndex;

      if (isActive) {
        final ringPaint = Paint()
          ..color = (isElevated ? AppColors.error : AppColors.primary)
              .withValues(alpha: 0.25)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(pt, 8.0, ringPaint);
        final ringStrokePaint = Paint()
          ..color = isElevated ? AppColors.error : AppColors.primary
          ..strokeWidth = 1.8
          ..style = PaintingStyle.stroke;
        canvas.drawCircle(pt, 6.5, ringStrokePaint);
      }

      final dotPaint = Paint()
        ..color = isElevated ? AppColors.error : AppColors.primary
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pt, isActive ? 4.0 : 3.0, dotPaint);

      // X-axis labels for first, active, and last frames
      if (i == 0 || i == points.length - 1 || isActive) {
        final xLabel =
            'F${i + 1} (${sortedFrames[i].xPositionCm.toStringAsFixed(0)}cm)';
        final tp = TextPainter(
          text: TextSpan(
            text: xLabel,
            style: TextStyle(
              fontSize: 8.0,
              fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
              color: isActive ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final labelX = (pt.dx - tp.width / 2).clamp(
          padLeft,
          math.max(padLeft, size.width - padRight - tp.width),
        ).toDouble();
        tp.paint(canvas, Offset(labelX, padTop + plotH + 4));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ThermalProfileCurvePainter oldDelegate) {
    return oldDelegate.sortedFrames != sortedFrames ||
        oldDelegate.activeFrameIndex != activeFrameIndex ||
        oldDelegate.baselineTempC != baselineTempC ||
        oldDelegate.panelBaselines != panelBaselines ||
        oldDelegate.panelBounds != panelBounds ||
        oldDelegate.hotspotDeltaThresholdC != hotspotDeltaThresholdC;
  }
}
