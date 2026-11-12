import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';

/// Sorts measurements spatially by [ModuleMeasurement.xPositionCm] ascending.
/// Tie-breaker 1: [ModuleMeasurement.measuredAt] ascending (parsed as DateTime, fallback to String).
/// Tie-breaker 2: [ModuleMeasurement.id] ascending.
List<ModuleMeasurement> sortMeasurementsSpatially(
  List<ModuleMeasurement> measurements,
) {
  final copy = List<ModuleMeasurement>.from(measurements);
  copy.sort((a, b) {
    final xCmp = a.xPositionCm.compareTo(b.xPositionCm);
    if (xCmp != 0) return xCmp;

    final dtA = DateTime.tryParse(a.measuredAt);
    final dtB = DateTime.tryParse(b.measuredAt);
    if (dtA != null && dtB != null) {
      final dtCmp = dtA.compareTo(dtB);
      if (dtCmp != 0) return dtCmp;
    } else {
      final strCmp = a.measuredAt.compareTo(b.measuredAt);
      if (strCmp != 0) return strCmp;
    }

    return a.id.compareTo(b.id);
  });
  return copy;
}

/// Deduplicates measurements spatially so that for each physical rail coordinate [xPositionCm]
/// (within [toleranceCm], default 0.5 cm), strictly the latest measurement by [measuredAt]
/// (tie-breaker by [id]) is retained.
/// The resulting list is sorted strictly by [xPositionCm] ascending.
List<ModuleMeasurement> deduplicateMeasurementsSpatially(
  List<ModuleMeasurement> measurements, {
  double toleranceCm = 0.5,
}) {
  if (measurements.isEmpty) return const [];
  if (measurements.length == 1) {
    return List<ModuleMeasurement>.from(measurements);
  }

  // First sort spatially (ascending by X, then ascending by measuredAt)
  final sorted = sortMeasurementsSpatially(measurements);

  final List<ModuleMeasurement> deduplicated = [];

  for (final m in sorted) {
    if (deduplicated.isEmpty) {
      deduplicated.add(m);
      continue;
    }

    final last = deduplicated.last;
    // Check if within tolerance of the same physical position
    if ((m.xPositionCm - last.xPositionCm).abs() <= toleranceCm) {
      // Determine which one is more recent
      final dtM = DateTime.tryParse(m.measuredAt);
      final dtLast = DateTime.tryParse(last.measuredAt);
      bool useCurrent = false;

      if (dtM != null && dtLast != null) {
        if (dtM.isAfter(dtLast) ||
            (dtM.isAtSameMomentAs(dtLast) && m.id.compareTo(last.id) > 0)) {
          useCurrent = true;
        }
      } else {
        final cmp = m.measuredAt.compareTo(last.measuredAt);
        if (cmp > 0 || (cmp == 0 && m.id.compareTo(last.id) > 0)) {
          useCurrent = true;
        }
      }

      if (useCurrent) {
        deduplicated[deduplicated.length - 1] = m;
      }
    } else {
      deduplicated.add(m);
    }
  }

  return deduplicated;
}

/// Filters [measurements] to strictly contain only the frames belonging to the
/// current/latest inspection.
///
/// Priority:
/// 1. If [latestInspection] has a non-empty `inspection.id` and at least one
///    measurement in [measurements] matches that `inspectionId`, returns only
///    measurements with `m.inspectionId == latestInspection.inspection.id`.
/// 2. Otherwise, if [latestMeasurement] has a non-empty `inspectionId`, filters
///    by `latestMeasurement.inspectionId`.
/// 3. Otherwise, determines the most recent measurement in [measurements] by
///    `measuredAt` (with fallback to the first non-empty `inspectionId`) and
///    filters by its `inspectionId`.
List<ModuleMeasurement> filterMeasurementsForCurrentInspection({
  required List<ModuleMeasurement> measurements,
  LatestInspection? latestInspection,
  ModuleMeasurement? latestMeasurement,
}) {
  if (measurements.isEmpty) {
    return latestMeasurement != null ? [latestMeasurement] : const [];
  }

  String? targetInspectionId;
  final latestInspId = latestInspection?.inspection.id;
  if (latestInspId != null &&
      latestInspId.isNotEmpty &&
      measurements.any((m) => m.inspectionId == latestInspId)) {
    targetInspectionId = latestInspId;
  } else if (latestMeasurement != null &&
      latestMeasurement.inspectionId.isNotEmpty &&
      measurements.any((m) => m.inspectionId == latestMeasurement.inspectionId)) {
    targetInspectionId = latestMeasurement.inspectionId;
  } else {
    ModuleMeasurement? mostRecent;
    DateTime? mostRecentDt;
    for (final m in measurements) {
      if (m.inspectionId.isEmpty) continue;
      final dt = DateTime.tryParse(m.measuredAt);
      if (mostRecent == null) {
        mostRecent = m;
        mostRecentDt = dt;
      } else if (dt != null && (mostRecentDt == null || dt.isAfter(mostRecentDt))) {
        mostRecent = m;
        mostRecentDt = dt;
      }
    }
    targetInspectionId = mostRecent?.inspectionId;
  }

  if (targetInspectionId == null || targetInspectionId.isEmpty) {
    return measurements;
  }

  return measurements
      .where((m) => m.inspectionId == targetInspectionId)
      .toList();
}

/// Checks whether [frame] is associated with [anomaly].
///
/// Primary rule: if [anomaly.originMeasurementId] or [anomaly.confirmingMeasurementIds]
/// is non-empty, associates strictly by measurement ID.
/// Fallback rule (only when both ID fields are empty): uses the half-open physical FOV
/// interval `[frame.xPositionCm - 2.5, frame.xPositionCm + 2.5)`.
bool isFrameAssociatedWithAnomaly(
  ModuleMeasurement frame,
  ConfirmedAnomaly anomaly,
) {
  final hasExplicitIds =
      anomaly.originMeasurementId.isNotEmpty ||
      anomaly.confirmingMeasurementIds.isNotEmpty;

  if (hasExplicitIds) {
    if (frame.id.isEmpty) return false;
    return frame.id == anomaly.originMeasurementId ||
        anomaly.confirmingMeasurementIds.contains(frame.id);
  }

  final minX = frame.xPositionCm - ThermalCoverageInfo.halfFovCm;
  final maxX = frame.xPositionCm + ThermalCoverageInfo.halfFovCm;
  return anomaly.xPositionCm >= minX && anomaly.xPositionCm < maxX;
}

/// Returns all [ConfirmedAnomaly] items associated with [frame].
List<ConfirmedAnomaly> getFrameAssociatedAnomalies(
  ModuleMeasurement frame,
  List<ConfirmedAnomaly> confirmedAnomalies,
) {
  return confirmedAnomalies
      .where((anomaly) => isFrameAssociatedWithAnomaly(frame, anomaly))
      .toList();
}

/// Returns the 1-based labels (`H1`, `H2`, ...) of all anomalies associated with [frame].
List<String> getFrameAnomalyLabels(
  ModuleMeasurement frame,
  List<ConfirmedAnomaly> confirmedAnomalies,
) {
  final labels = <String>[];
  for (var i = 0; i < confirmedAnomalies.length; i++) {
    if (isFrameAssociatedWithAnomaly(frame, confirmedAnomalies[i])) {
      labels.add('H${i + 1}');
    }
  }
  return labels;
}

/// Finds anomalies that declare explicit origin/confirming measurement IDs
/// but have none of those measurements present in [loadedMeasurements].
List<ConfirmedAnomaly> findAnomaliesWithoutLoadedConfirmingFrames(
  List<ConfirmedAnomaly> confirmedAnomalies,
  List<ModuleMeasurement> loadedMeasurements,
) {
  final loadedIds = loadedMeasurements
      .map((m) => m.id)
      .where((id) => id.isNotEmpty)
      .toSet();

  return confirmedAnomalies.where((anomaly) {
    final hasExplicitIds =
        anomaly.originMeasurementId.isNotEmpty ||
        anomaly.confirmingMeasurementIds.isNotEmpty;
    if (!hasExplicitIds) return false;

    final matchesOrigin =
        anomaly.originMeasurementId.isNotEmpty &&
        loadedIds.contains(anomaly.originMeasurementId);
    final matchesConfirming = anomaly.confirmingMeasurementIds.any(
      loadedIds.contains,
    );
    return !matchesOrigin && !matchesConfirming;
  }).toList();
}

/// Expected scan coverage and pagination completeness diagnostics.
class ThermalCoverageInfo {
  const ThermalCoverageInfo({
    required this.panelLengthCm,
    required this.loadedMeasurementsCount,
    this.totalInspectionMeasurements,
    this.panelCount,
    this.panelSpacingCm,
    this.focusedPanelIndex,
  });

  static const double stepCm = 2.0;
  static const double fovCm = 5.0;
  static const double halfFovCm = fovCm / 2.0;
  static const int sensorRows = 24;
  static const int sensorCols = 32;
  static const int sensorPixelCount = sensorRows * sensorCols;

  final double? panelLengthCm;
  final int loadedMeasurementsCount;
  final int? totalInspectionMeasurements;
  final int? panelCount;
  final double? panelSpacingCm;
  final int? focusedPanelIndex;

  bool get hasConfiguredPanelLength =>
      panelLengthCm != null && panelLengthCm! > 0;

  int get effectivePanelCount =>
      (panelCount != null && panelCount! > 0) ? panelCount! : 1;

  double get effectivePanelSpacingCm =>
      (panelSpacingCm != null && panelSpacingCm! >= 0) ? panelSpacingCm! : 0.0;

  /// Expected number of acquisitions:
  /// For focused panel: `ceil(panelLengthCm / 2.0) + 1`.
  /// For full multi-panel string: `panelCount * (ceil(panelLengthCm / 2.0) + 1)`.
  int? get expectedAcquisitions {
    if (!hasConfiguredPanelLength) return null;
    final perPanel = (panelLengthCm! / stepCm).ceil() + 1;
    if (focusedPanelIndex != null) return perPanel;
    return effectivePanelCount * perPanel;
  }

  /// Expected total thermal coverage span in cm.
  /// For focused panel: `panelLengthCm + 5.0`.
  /// For full string: `(panelCount * panelLengthCm) + ((panelCount - 1) * panelSpacingCm) + 5.0`.
  double? get expectedThermalCoverageCm {
    if (!hasConfiguredPanelLength) return null;
    if (focusedPanelIndex != null) return panelLengthCm! + fovCm;
    final totalRail = (effectivePanelCount * panelLengthCm!) +
        ((effectivePanelCount - 1) * effectivePanelSpacingCm);
    return totalRail + fovCm;
  }

  /// True when the inspection reports more total measurements than currently loaded in memory.
  bool get isPartiallyLoadedByPagination =>
      totalInspectionMeasurements != null &&
      totalInspectionMeasurements! > loadedMeasurementsCount;

  /// True when all available inspection measurements are loaded (not truncated by pagination),
  /// yet the count is below [expectedAcquisitions].
  bool get isIncompleteCoverage {
    final expected = expectedAcquisitions;
    if (expected == null || isPartiallyLoadedByPagination) return false;
    return loadedMeasurementsCount < expected;
  }

  /// True when more measurements were recorded than [expectedAcquisitions].
  bool get isExceededCoverage {
    final expected = expectedAcquisitions;
    if (expected == null) return false;
    return loadedMeasurementsCount > expected;
  }
}

/// Boundary coordinates of an individual panel on the continuous mechanical rail.
class PanelBound {
  const PanelBound({
    required this.panelIndex,
    required this.startXCm,
    required this.endXCm,
  });

  final int panelIndex;
  final double startXCm;
  final double endXCm;

  double get lengthCm => endXCm - startXCm;

  bool contains(double xCm) => xCm >= startXCm && xCm <= endXCm;
}

/// Boundary coordinates of an empty mechanical gap between adjacent panels.
class GapInterval {
  const GapInterval({
    required this.afterPanelIndex,
    required this.startXCm,
    required this.endXCm,
  });

  final int afterPanelIndex;
  final double startXCm;
  final double endXCm;

  double get widthCm => endXCm - startXCm;

  bool contains(double xCm) => xCm > startXCm && xCm < endXCm;
}

enum ThermalCellStatus {
  /// Valid temperature directly from the nearest-center covering frame.
  valid,

  /// Nearest-center covering frame had an invalid pixel (`null`/`NaN`/`Infinite`),
  /// and an overlapping neighbor frame supplied a valid temperature.
  complemented,

  /// Covered by at least one frame with a `thermal_frame`, but all covering frames
  /// had invalid pixels at this coordinate.
  unresolvedInvalid,

  /// No frame with a 768-pixel `thermal_frame` covers this coordinate.
  uncovered,
}

class ThermalCellResolution {
  const ThermalCellResolution({
    required this.status,
    this.temperatureC,
    this.sourceFrameIndex,
  });

  final ThermalCellStatus status;
  final double? temperatureC;
  final int? sourceFrameIndex;

  bool get hasValidTemperature =>
      (status == ThermalCellStatus.valid ||
          status == ThermalCellStatus.complemented) &&
      temperatureC != null;

  bool get wasComplemented => status == ThermalCellStatus.complemented;
  bool get isUnresolvedInvalid => status == ThermalCellStatus.unresolvedInvalid;
  bool get isUncovered => status == ThermalCellStatus.uncovered;
}

class _CoveringFrameCandidate {
  const _CoveringFrameCandidate({
    required this.frameIndex,
    required this.measurement,
    required this.distanceToCenterCm,
  });

  final int frameIndex;
  final ModuleMeasurement measurement;
  final double distanceToCenterCm;
}

/// Holds the spatially sorted measurements, resolved 2D thermal panorama grid,
/// calibrated temperature range, and diagnostic counters.
class ThermalPanoramaData {
  ThermalPanoramaData._({
    required this.sortedMeasurements,
    required this.confirmedAnomalies,
    required this.coverageInfo,
    required this.minDomainX,
    required this.maxDomainX,
    required this.gridColumns,
    required this.gridCells,
    required this.framesWithValidMatrixCount,
    required this.framesWithoutMatrixCount,
    required this.totalInvalidPixelsInFrames,
    required this.complementedCellCount,
    required this.unresolvedInvalidCellCount,
    required this.minValidTempC,
    required this.maxValidTempC,
    required this.anomaliesWithoutLoadedConfirmingFrames,
    required this.panelBounds,
    required this.gapIntervals,
    this.focusedPanelIndex,
    required this.panelCount,
    required this.panelSpacingCm,
    required this.totalRailLengthCm,
    this.baselineTempC,
    this.hotspotDeltaThresholdC = 8.0,
  });

  factory ThermalPanoramaData.fromMeasurements({
    required List<ModuleMeasurement> measurements,
    List<ConfirmedAnomaly> confirmedAnomalies = const [],
    double? panelLengthCm,
    int? panelCount,
    double? panelSpacingCm,
    int? focusedPanelIndex,
    int? totalInspectionMeasurements,
    double? baselineTempC,
    double hotspotDeltaThresholdC = 8.0,
    bool fitToScannedRange = false,
    bool deduplicateSpatially = true,
  }) {
    final sorted = deduplicateSpatially
        ? deduplicateMeasurementsSpatially(measurements)
        : sortMeasurementsSpatially(measurements);

    final effectivePanelLength =
        (panelLengthCm != null && panelLengthCm > 0) ? panelLengthCm : 20.0;
    final effectiveCount =
        (panelCount != null && panelCount > 0) ? panelCount : 1;
    final effectiveSpacing =
        (panelSpacingCm != null && panelSpacingCm >= 0) ? panelSpacingCm : 0.0;

    final bounds = <PanelBound>[];
    final gaps = <GapInterval>[];
    for (var p = 1; p <= effectiveCount; p++) {
      final startX = (p - 1) * (effectivePanelLength + effectiveSpacing);
      final endX = startX + effectivePanelLength;
      bounds.add(PanelBound(panelIndex: p, startXCm: startX, endXCm: endX));
      if (p < effectiveCount && effectiveSpacing > 0) {
        gaps.add(
          GapInterval(
            afterPanelIndex: p,
            startXCm: endX,
            endXCm: endX + effectiveSpacing,
          ),
        );
      }
    }
    final totalRail = (effectiveCount * effectivePanelLength) +
        ((effectiveCount - 1) * effectiveSpacing);

    final coverage = ThermalCoverageInfo(
      panelLengthCm: panelLengthCm,
      loadedMeasurementsCount: sorted.length,
      totalInspectionMeasurements: totalInspectionMeasurements,
      panelCount: panelCount,
      panelSpacingCm: panelSpacingCm,
      focusedPanelIndex: focusedPanelIndex,
    );

    double minFrameX = 0.0;
    double maxFrameX = totalRail;
    if (sorted.isNotEmpty) {
      minFrameX = sorted.first.xPositionCm;
      maxFrameX = sorted.first.xPositionCm;
      for (final m in sorted) {
        if (m.xPositionCm < minFrameX) minFrameX = m.xPositionCm;
        if (m.xPositionCm > maxFrameX) maxFrameX = m.xPositionCm;
      }
    }

    final double minDomainX;
    final double maxDomainX;

    if (focusedPanelIndex != null &&
        focusedPanelIndex >= 1 &&
        focusedPanelIndex <= bounds.length) {
      final targetPanel = bounds[focusedPanelIndex - 1];
      if (fitToScannedRange && sorted.isNotEmpty) {
        minDomainX = math.max(
          targetPanel.startXCm,
          minFrameX - ThermalCoverageInfo.halfFovCm,
        );
        maxDomainX = math.min(
          targetPanel.endXCm,
          maxFrameX + ThermalCoverageInfo.halfFovCm,
        );
      } else {
        minDomainX = targetPanel.startXCm - ThermalCoverageInfo.halfFovCm;
        maxDomainX = targetPanel.endXCm + ThermalCoverageInfo.halfFovCm;
      }
    } else if (fitToScannedRange && sorted.isNotEmpty) {
      minDomainX = minFrameX - ThermalCoverageInfo.halfFovCm;
      maxDomainX = maxFrameX + ThermalCoverageInfo.halfFovCm;
    } else {
      minDomainX = sorted.isEmpty
          ? -ThermalCoverageInfo.halfFovCm
          : math.min(
              -ThermalCoverageInfo.halfFovCm,
              minFrameX - ThermalCoverageInfo.halfFovCm,
            );
      maxDomainX = sorted.isEmpty
          ? totalRail + ThermalCoverageInfo.halfFovCm
          : math.max(
              totalRail + ThermalCoverageInfo.halfFovCm,
              maxFrameX + ThermalCoverageInfo.halfFovCm,
            );
    }

    var framesWithMatrix = 0;
    var framesWithoutMatrix = 0;
    var totalInvalidInFrames = 0;
    double? minTemp;
    double? maxTemp;

    for (final m in sorted) {
      final tf = m.thermalFrame;
      if (tf != null && tf.length == ThermalCoverageInfo.sensorPixelCount) {
        framesWithMatrix++;
        for (final v in tf) {
          if (isValidPixelValue(v)) {
            final val = v!;
            if (minTemp == null || val < minTemp) minTemp = val;
            if (maxTemp == null || val > maxTemp) maxTemp = val;
          } else {
            totalInvalidInFrames++;
          }
        }
      } else {
        framesWithoutMatrix++;
      }
    }

    final domainSpan = (maxDomainX - minDomainX).clamp(5.0, double.infinity);
    const colWidthCm =
        ThermalCoverageInfo.fovCm / ThermalCoverageInfo.sensorCols;
    final gridCols = (domainSpan / colWidthCm).ceil().clamp(32, 1600);
    final actualColStepCm = domainSpan / gridCols;

    var complementedCount = 0;
    var unresolvedCount = 0;

    final cells = List<List<ThermalCellResolution>>.generate(
      ThermalCoverageInfo.sensorRows,
      (row) => List<ThermalCellResolution>.generate(gridCols, (col) {
        final xCm = minDomainX + (col + 0.5) * actualColStepCm;
        final res = resolveCellAtStatic(
          sortedMeasurements: sorted,
          xCm: xCm,
          row: row,
          gapIntervals: gaps,
          panelBounds: bounds,
        );
        if (res.wasComplemented) {
          complementedCount++;
        } else if (res.isUnresolvedInvalid) {
          unresolvedCount++;
        }
        return res;
      }, growable: false),
      growable: false,
    );

    final unlinkedAnomalies = findAnomaliesWithoutLoadedConfirmingFrames(
      confirmedAnomalies,
      sorted,
    );

    return ThermalPanoramaData._(
      sortedMeasurements: sorted,
      confirmedAnomalies: confirmedAnomalies,
      coverageInfo: coverage,
      minDomainX: minDomainX,
      maxDomainX: maxDomainX,
      gridColumns: gridCols,
      gridCells: cells,
      framesWithValidMatrixCount: framesWithMatrix,
      framesWithoutMatrixCount: framesWithoutMatrix,
      totalInvalidPixelsInFrames: totalInvalidInFrames,
      complementedCellCount: complementedCount,
      unresolvedInvalidCellCount: unresolvedCount,
      minValidTempC: minTemp,
      maxValidTempC: maxTemp,
      anomaliesWithoutLoadedConfirmingFrames: unlinkedAnomalies,
      panelBounds: bounds,
      gapIntervals: gaps,
      focusedPanelIndex: focusedPanelIndex,
      panelCount: effectiveCount,
      panelSpacingCm: effectiveSpacing,
      totalRailLengthCm: totalRail,
      baselineTempC: baselineTempC,
      hotspotDeltaThresholdC: hotspotDeltaThresholdC,
    );
  }

  final List<ModuleMeasurement> sortedMeasurements;
  final List<ConfirmedAnomaly> confirmedAnomalies;
  final ThermalCoverageInfo coverageInfo;
  final double? baselineTempC;
  final double hotspotDeltaThresholdC;
  final double minDomainX;
  final double maxDomainX;
  final int gridColumns;

  /// 2D resolved cells indexed as `gridCells[row][col]`.
  final List<List<ThermalCellResolution>> gridCells;

  final int framesWithValidMatrixCount;
  final int framesWithoutMatrixCount;
  final int totalInvalidPixelsInFrames;
  final int complementedCellCount;
  final int unresolvedInvalidCellCount;
  final double? minValidTempC;
  final double? maxValidTempC;
  final List<ConfirmedAnomaly> anomaliesWithoutLoadedConfirmingFrames;

  final List<PanelBound> panelBounds;
  final List<GapInterval> gapIntervals;
  final int? focusedPanelIndex;
  final int panelCount;
  final double panelSpacingCm;
  final double totalRailLengthCm;

  double get domainSpanCm =>
      (maxDomainX - minDomainX).clamp(5.0, double.infinity);

  bool get hasAnyThermalMatrix => framesWithValidMatrixCount > 0;
  bool get hasValidTemperatures =>
      minValidTempC != null && maxValidTempC != null;
  bool get hasInvalidPixels =>
      totalInvalidPixelsInFrames > 0 ||
      complementedCellCount > 0 ||
      unresolvedInvalidCellCount > 0;

  static bool isValidPixelValue(double? value) =>
      value != null && !value.isNaN && !value.isInfinite;

  static bool hasValidThermalMatrix(ModuleMeasurement measurement) =>
      measurement.thermalFrame != null &&
      measurement.thermalFrame!.length == ThermalCoverageInfo.sensorPixelCount;

  /// Resolves the temperature and cell status at physical coordinate [xCm] and sensor [row] (`0..23`).
  ///
  /// 1. Finds all frames with a 768-element `thermal_frame` covering `[x_i - 2.5, x_i + 2.5]`.
  /// 2. Orders candidates by distance to frame center `|xCm - x_i|` ascending (tie-breaking by lower index).
  /// 3. Selects the first valid (non-null, finite) pixel temperature.
  /// 4. If the nearest-center frame had an invalid pixel and a neighbor frame provided a valid pixel,
  ///    returns [ThermalCellStatus.complemented].
  /// 5. If all covering frames had invalid pixels at `(xCm, row)`, returns [ThermalCellStatus.unresolvedInvalid].
  static ThermalCellResolution resolveCellAtStatic({
    required List<ModuleMeasurement> sortedMeasurements,
    required double xCm,
    required int row,
    List<GapInterval> gapIntervals = const [],
    List<PanelBound> panelBounds = const [],
  }) {
    if (row < 0 || row >= ThermalCoverageInfo.sensorRows) {
      return const ThermalCellResolution(status: ThermalCellStatus.uncovered);
    }

    // Never resolve thermal heat inside an inter-panel gap
    if (gapIntervals.any((g) => g.contains(xCm))) {
      return const ThermalCellResolution(status: ThermalCellStatus.uncovered);
    }

    // For multi-panel arrays, never resolve outside physical panel boundaries
    if (panelBounds.length > 1 && !panelBounds.any((b) => b.contains(xCm))) {
      return const ThermalCellResolution(status: ThermalCellStatus.uncovered);
    }

    final candidates = <_CoveringFrameCandidate>[];
    for (var i = 0; i < sortedMeasurements.length; i++) {
      final m = sortedMeasurements[i];
      if (!hasValidThermalMatrix(m)) continue;

      if (panelBounds.length > 1 || m.panelIndex != null) {
        PanelBound? mBound;
        if (m.panelIndex != null &&
            m.panelIndex! >= 1 &&
            m.panelIndex! <= panelBounds.length) {
          mBound = panelBounds[m.panelIndex! - 1];
        } else if (panelBounds.length > 1) {
          for (final b in panelBounds) {
            if (b.contains(m.xPositionCm)) {
              mBound = b;
              break;
            }
          }
        }
        if (mBound != null && !mBound.contains(xCm)) {
          continue;
        }
      }

      final startX = m.xPositionCm - ThermalCoverageInfo.halfFovCm;
      final endX = m.xPositionCm + ThermalCoverageInfo.halfFovCm;
      if (xCm >= startX && xCm <= endX) {
        candidates.add(
          _CoveringFrameCandidate(
            frameIndex: i,
            measurement: m,
            distanceToCenterCm: (xCm - m.xPositionCm).abs(),
          ),
        );
      }
    }

    if (candidates.isEmpty) {
      return const ThermalCellResolution(status: ThermalCellStatus.uncovered);
    }

    candidates.sort((a, b) {
      final distCmp = a.distanceToCenterCm.compareTo(b.distanceToCenterCm);
      if (distCmp != 0) return distCmp;
      return a.frameIndex.compareTo(b.frameIndex);
    });

    var skippedInvalidCandidate = false;
    for (final candidate in candidates) {
      final startX =
          candidate.measurement.xPositionCm - ThermalCoverageInfo.halfFovCm;
      final relativeX = (xCm - startX) / ThermalCoverageInfo.fovCm;
      final col = (relativeX * ThermalCoverageInfo.sensorCols).floor().clamp(
        0,
        ThermalCoverageInfo.sensorCols - 1,
      );
      final pixelIdx = row * ThermalCoverageInfo.sensorCols + col;
      final pixelVal = candidate.measurement.thermalFrame![pixelIdx];

      if (isValidPixelValue(pixelVal)) {
        return ThermalCellResolution(
          status: skippedInvalidCandidate
              ? ThermalCellStatus.complemented
              : ThermalCellStatus.valid,
          temperatureC: pixelVal,
          sourceFrameIndex: candidate.frameIndex,
        );
      } else {
        skippedInvalidCandidate = true;
      }
    }

    return const ThermalCellResolution(
      status: ThermalCellStatus.unresolvedInvalid,
    );
  }

  /// Resolves the cell at physical coordinate [xCm] and sensor [row] (`0..23`).
  ThermalCellResolution resolveAt(double xCm, int row) {
    return resolveCellAtStatic(
      sortedMeasurements: sortedMeasurements,
      xCm: xCm,
      row: row,
      gapIntervals: gapIntervals,
      panelBounds: panelBounds,
    );
  }

  /// Generates a calibrated gradient reflecting the isotherm color ramp for scale bars.
  List<Color> get scaleGradientColors {
    if (baselineTempC != null && baselineTempC! > 0) {
      return const [
        AppColors.thermalCold, // Deep blue
        AppColors.thermalCool, // Cyan (at normal elevation)
        AppColors.thermalMid,  // Amber (approaching hotspot)
        AppColors.thermalWarm, // Bright Orange (Hotspot threshold trigger)
        AppColors.thermalHot,  // Crimson Red
        Color(0xFFFFFFFF),     // White peak
      ];
    }
    return AppColors.thermalSpectrum;
  }

  /// Maps a valid temperature [tempC] to an isotherm-enhanced radiometric color.
  /// When a [baselineTempC] is available:
  /// - Temperatures <= (baseline + 0.4 * delta): Deep cold blues to cyan.
  /// - Temperatures between (baseline + 0.4 * delta) and (baseline + delta): Warm transition (cyan to golden amber).
  /// - Temperatures >= (baseline + delta) (ISOTHERM ZONE): Immediate bright thermal alarm (hot orange -> vivid red -> incandescent white).
  /// Falls back to linear interpolation along [AppColors.thermalSpectrum] when baseline is not available.
  Color colorForTemperature(double tempC) {
    if (!isValidPixelValue(tempC) || !hasValidTemperatures) {
      return ThermalPanoramaPainter.unresolvedInvalidColor;
    }

    if (baselineTempC != null && baselineTempC! > 0) {
      final base = baselineTempC!;
      final delta = hotspotDeltaThresholdC > 0 ? hotspotDeltaThresholdC : 8.0;
      final alarmT = base + delta;
      final midT = base + (delta * 0.4);
      final floorT = math.min(base - 3.0, (minValidTempC ?? base) - 1.0);
      final ceilT = math.max(alarmT + 6.0, (maxValidTempC ?? alarmT) + 1.0);

      // 1. Cold / Normal operational band (up to 40% of delta over baseline):
      if (tempC <= midT) {
        final span = midT - floorT;
        final t = span > 0 ? ((tempC - floorT) / span).clamp(0.0, 1.0) : 0.0;
        return Color.lerp(
          AppColors.thermalCold,
          AppColors.thermalCool,
          t,
        )!;
      }

      // 2. Moderate warm elevation band (between 40% and 100% of delta over baseline):
      if (tempC < alarmT) {
        final span = alarmT - midT;
        final t = span > 0 ? ((tempC - midT) / span).clamp(0.0, 1.0) : 0.0;
        return Color.lerp(
          AppColors.thermalCool,
          AppColors.thermalMid,
          t,
        )!;
      }

      // 3. ISOTHERM ALARM ZONE: Hotspot reached or exceeded!
      // High-visibility alarm ramp: Bright Orange -> Vivid Crimson Red -> Pure White core
      final span = ceilT - alarmT;
      final t = span > 0 ? ((tempC - alarmT) / span).clamp(0.0, 1.0) : 0.0;
      if (t < 0.5) {
        final subT = t * 2.0;
        return Color.lerp(AppColors.thermalWarm, AppColors.thermalHot, subT)!;
      } else {
        final subT = (t - 0.5) * 2.0;
        return Color.lerp(AppColors.thermalHot, const Color(0xFFFFFFFF), subT)!;
      }
    }

    final minT = minValidTempC!;
    final maxT = maxValidTempC!;
    final span = maxT - minT;
    final double normalized = span.abs() < 1e-6
        ? 0.5
        : ((tempC - minT) / span).clamp(0.0, 1.0);

    const spectrum = AppColors.thermalSpectrum;
    if (spectrum.length == 1) return spectrum.first;

    final scaled = normalized * (spectrum.length - 1);
    final lowerIdx = scaled.floor().clamp(0, spectrum.length - 1);
    final upperIdx = scaled.ceil().clamp(0, spectrum.length - 1);
    final t = scaled - lowerIdx;

    return Color.lerp(spectrum[lowerIdx], spectrum[upperIdx], t) ??
        spectrum[lowerIdx];
  }
}

/// CustomPainter that renders the 2D radiometric thermal panorama mosaic.
class ThermalPanoramaPainter extends CustomPainter {
  const ThermalPanoramaPainter({
    required this.panorama,
  });

  final ThermalPanoramaData panorama;

  /// Distinct neutral slate color for unresolved invalid sensor pixels (`null` / `NaN`).
  static const Color unresolvedInvalidColor = Color(0xFF374151);

  /// Dark rail background color for uncovered regions.
  static const Color uncoveredBackgroundColor = Color(0xFF0F1B2D);

  /// Dark slotted color for physical inter-panel gaps.
  static const Color gapSpacerColor = Color(0xFF060B14);
  static const Color gapBorderColor = Color(0xFF1E293B);

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..color = uncoveredBackgroundColor
      ..style = PaintingStyle.fill;
    canvas.drawRect(Offset.zero & size, bgPaint);

    final domainSpan = panorama.domainSpanCm;
    final pxPerCm = size.width / domainSpan;

    if (panorama.hasAnyThermalMatrix && panorama.gridColumns > 0) {
      final rows = ThermalCoverageInfo.sensorRows;
      final cols = panorama.gridColumns;
      final cellW = size.width / cols;
      final cellH = size.height / rows;
      final colStepCm = domainSpan / cols;
      final cellPaint = Paint()..style = PaintingStyle.fill;

      for (var r = 0; r < rows; r++) {
        final rowCells = panorama.gridCells[r];
        final top = r * cellH;
        for (var c = 0; c < cols; c++) {
          final xCm = panorama.minDomainX + (c + 0.5) * colStepCm;

          // Strictly clip thermal cells to physical panel boundaries and out of gaps
          if (panorama.gapIntervals.any((g) => g.contains(xCm))) {
            continue;
          }
          if (panorama.panelBounds.isNotEmpty) {
            if (panorama.focusedPanelIndex != null &&
                panorama.focusedPanelIndex! >= 1 &&
                panorama.focusedPanelIndex! <= panorama.panelBounds.length) {
              if (!panorama.panelBounds[panorama.focusedPanelIndex! - 1]
                  .contains(xCm)) {
                continue;
              }
            } else if (!panorama.panelBounds.any((b) => b.contains(xCm))) {
              continue;
            }
          }

          final cell = rowCells[c];
          if (cell.isUncovered) continue;

          if (cell.isUnresolvedInvalid) {
            cellPaint.color = unresolvedInvalidColor;
          } else if (cell.hasValidTemperature) {
            cellPaint.color = panorama.colorForTemperature(cell.temperatureC!);
          } else {
            continue;
          }

          final left = c * cellW;
          // Slight +0.4 px overlap avoids subpixel hairline seams between adjacent cells
          canvas.drawRect(
            Rect.fromLTWH(left, top, cellW + 0.4, cellH + 0.4),
            cellPaint,
          );
        }
      }
    }

    // Draw clean panel outlines so individual panels in the string have crisp boundaries
    final panelBorderPaint = Paint()
      ..color = const Color(0xFF334155)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    for (final pb in panorama.panelBounds) {
      if (panorama.focusedPanelIndex != null &&
          pb.panelIndex != panorama.focusedPanelIndex) {
        continue;
      }
      final left = (pb.startXCm - panorama.minDomainX) * pxPerCm;
      final right = (pb.endXCm - panorama.minDomainX) * pxPerCm;
      if (right <= 0 || left >= size.width) continue;

      final panelRect = Rect.fromLTRB(
        left.clamp(0.0, size.width),
        0,
        right.clamp(0.0, size.width),
        size.height,
      );
      canvas.drawRect(panelRect, panelBorderPaint);
    }

    // Draw mechanical gap spacers on top so inter-panel gaps remain crisp and un-colored
    final gapPaint = Paint()
      ..color = gapSpacerColor
      ..style = PaintingStyle.fill;
    final gapBorderPaint = Paint()
      ..color = gapBorderColor
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final hatchPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    for (final gap in panorama.gapIntervals) {
      final left = (gap.startXCm - panorama.minDomainX) * pxPerCm;
      final right = (gap.endXCm - panorama.minDomainX) * pxPerCm;
      if (right <= 0 || left >= size.width) continue;

      final rect = Rect.fromLTRB(
        left.clamp(0.0, size.width),
        0,
        right.clamp(0.0, size.width),
        size.height,
      );
      canvas.drawRect(rect, gapPaint);

      // Subtle diagonal hatching lines inside the mechanical gap
      if (rect.width >= 2.0) {
        canvas.save();
        canvas.clipRect(rect);
        const step = 6.0;
        for (double y = -rect.width; y < size.height + rect.width; y += step) {
          canvas.drawLine(
            Offset(rect.left, y),
            Offset(rect.right, y + rect.width),
            hatchPaint,
          );
        }
        canvas.restore();
      }

      canvas.drawRect(rect, gapBorderPaint);

      // Mechanical slot center marking & label when width permits
      if (rect.width >= 14.0) {
        final gapLabel = rect.width >= 28.0
            ? 'GAP\n${gap.widthCm.toStringAsFixed(0)}cm'
            : 'GAP';
        final tp = TextPainter(
          text: TextSpan(
            text: gapLabel,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 7.5,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: rect.width);
        tp.paint(
          canvas,
          Offset(
            rect.center.dx - tp.width / 2,
            rect.center.dy - tp.height / 2,
          ),
        );
      } else if (rect.width >= 3.0) {
        final midX = rect.center.dx;
        canvas.drawLine(
          Offset(midX, 4),
          Offset(midX, size.height - 4),
          gapBorderPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant ThermalPanoramaPainter oldDelegate) {
    return oldDelegate.panorama != panorama;
  }
}

/// CustomPainter that renders an individual 32x24 matrix for a selected frame.
class SingleFrameMatrixPainter extends CustomPainter {
  const SingleFrameMatrixPainter({
    required this.thermalFrame,
    required this.colorForTemperature,
  });

  final List<double?> thermalFrame;
  final Color Function(double tempC) colorForTemperature;

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..color = ThermalPanoramaPainter.uncoveredBackgroundColor
      ..style = PaintingStyle.fill;
    canvas.drawRect(Offset.zero & size, bgPaint);

    if (thermalFrame.length != ThermalCoverageInfo.sensorPixelCount) {
      return;
    }

    final rows = ThermalCoverageInfo.sensorRows;
    final cols = ThermalCoverageInfo.sensorCols;
    final cellW = size.width / cols;
    final cellH = size.height / rows;
    final cellPaint = Paint()..style = PaintingStyle.fill;

    for (var r = 0; r < rows; r++) {
      final top = r * cellH;
      for (var c = 0; c < cols; c++) {
        final val = thermalFrame[r * cols + c];
        if (ThermalPanoramaData.isValidPixelValue(val)) {
          cellPaint.color = colorForTemperature(val!);
        } else {
          cellPaint.color = ThermalPanoramaPainter.unresolvedInvalidColor;
        }

        final left = c * cellW;
        canvas.drawRect(
          Rect.fromLTWH(left, top, cellW + 0.3, cellH + 0.3),
          cellPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant SingleFrameMatrixPainter oldDelegate) {
    return oldDelegate.thermalFrame != thermalFrame;
  }
}
