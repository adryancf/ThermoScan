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

  bool get hasConfiguredPanelLength =>
      panelLengthCm != null && panelLengthCm! > 0;

  /// Expected number of acquisitions for `0..panelLengthCm` at 2 cm step:
  /// `ceil(panelLengthCm / 2.0) + 1`.
  int? get expectedAcquisitions {
    if (!hasConfiguredPanelLength) return null;
    return (panelLengthCm! / stepCm).ceil() + 1;
  }

  /// Expected total thermal coverage span in cm (`[-2.5, panelLengthCm + 2.5]` -> `panelLengthCm + 5.0`).
  double? get expectedThermalCoverageCm {
    if (!hasConfiguredPanelLength) return null;
    return panelLengthCm! + fovCm;
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
  });

  factory ThermalPanoramaData.fromMeasurements({
    required List<ModuleMeasurement> measurements,
    List<ConfirmedAnomaly> confirmedAnomalies = const [],
    double? panelLengthCm,
    int? totalInspectionMeasurements,
  }) {
    final sorted = sortMeasurementsSpatially(measurements);
    final coverage = ThermalCoverageInfo(
      panelLengthCm: panelLengthCm,
      loadedMeasurementsCount: sorted.length,
      totalInspectionMeasurements: totalInspectionMeasurements,
    );

    final effectivePanelLength =
        (panelLengthCm != null && panelLengthCm > 0) ? panelLengthCm : 20.0;

    double minFrameX = 0.0;
    double maxFrameX = effectivePanelLength;
    if (sorted.isNotEmpty) {
      minFrameX = sorted.first.xPositionCm;
      maxFrameX = sorted.first.xPositionCm;
      for (final m in sorted) {
        if (m.xPositionCm < minFrameX) minFrameX = m.xPositionCm;
        if (m.xPositionCm > maxFrameX) maxFrameX = m.xPositionCm;
      }
    }

    final minDomainX = sorted.isEmpty
        ? -ThermalCoverageInfo.halfFovCm
        : math.min(
            -ThermalCoverageInfo.halfFovCm,
            minFrameX - ThermalCoverageInfo.halfFovCm,
          );
    final maxDomainX = sorted.isEmpty
        ? effectivePanelLength + ThermalCoverageInfo.halfFovCm
        : math.max(
            effectivePanelLength + ThermalCoverageInfo.halfFovCm,
            maxFrameX + ThermalCoverageInfo.halfFovCm,
          );

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
    );
  }

  final List<ModuleMeasurement> sortedMeasurements;
  final List<ConfirmedAnomaly> confirmedAnomalies;
  final ThermalCoverageInfo coverageInfo;
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
  }) {
    if (row < 0 || row >= ThermalCoverageInfo.sensorRows) {
      return const ThermalCellResolution(status: ThermalCellStatus.uncovered);
    }

    final candidates = <_CoveringFrameCandidate>[];
    for (var i = 0; i < sortedMeasurements.length; i++) {
      final m = sortedMeasurements[i];
      if (!hasValidThermalMatrix(m)) continue;
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
    );
  }

  /// Maps a valid temperature [tempC] to a color along [AppColors.thermalSpectrum].
  /// Never maps invalid temperatures (`NaN` / `Infinite`) to thermal colors.
  Color colorForTemperature(double tempC) {
    if (!isValidPixelValue(tempC) || !hasValidTemperatures) {
      return ThermalPanoramaPainter.unresolvedInvalidColor;
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

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..color = uncoveredBackgroundColor
      ..style = PaintingStyle.fill;
    canvas.drawRect(Offset.zero & size, bgPaint);

    if (!panorama.hasAnyThermalMatrix || panorama.gridColumns <= 0) {
      return;
    }

    final rows = ThermalCoverageInfo.sensorRows;
    final cols = panorama.gridColumns;
    final cellW = size.width / cols;
    final cellH = size.height / rows;
    final cellPaint = Paint()..style = PaintingStyle.fill;

    for (var r = 0; r < rows; r++) {
      final rowCells = panorama.gridCells[r];
      final top = r * cellH;
      for (var c = 0; c < cols; c++) {
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

  @override
  bool shouldRepaint(covariant ThermalPanoramaPainter oldDelegate) {
    return oldDelegate.panorama != panorama;
  }
}
