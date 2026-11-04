import 'package:flutter/material.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';
import 'package:thermoscan/features/modules/presentation/widgets/thermal_panorama_painter.dart';

/// SCR-10: Physical Thermal Frames & Radiometric Telemetry Metrics
class RadiometricScanCard extends StatelessWidget {
  const RadiometricScanCard({
    super.key,
    required this.module,
    this.latestMeasurement,
    this.latestInspection,
    this.measurements,
  });

  final PvModule module;
  final ModuleMeasurement? latestMeasurement;
  final LatestInspection? latestInspection;
  final List<ModuleMeasurement>? measurements;

  @override
  Widget build(BuildContext context) {
    final m = latestMeasurement;
    final insp = latestInspection;
    final rawMeasurements =
        measurements ?? (m != null ? [m] : <ModuleMeasurement>[]);

    if (m == null && insp == null && rawMeasurements.isEmpty) {
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
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.grid_view_rounded,
                color: AppColors.primary,
                size: 28,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Awaiting Radiometric Telemetry',
              style: AppTypography.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'No thermal frames or electrical readings recorded yet by the ESP32. Real telemetry and physical frames will appear here upon the first hardware inspection scan.',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final confirmedAnomalies = insp?.confirmedAnomalies ?? const [];
    final hasConfirmedHotspots = confirmedAnomalies.isNotEmpty;

    final panorama = ThermalPanoramaData.fromMeasurements(
      measurements: rawMeasurements,
      confirmedAnomalies: confirmedAnomalies,
      panelLengthCm: module.panelLengthCm,
      totalInspectionMeasurements: insp?.totalMeasurements,
    );
    final sortedMeasurements = panorama.sortedMeasurements;
    final coverage = panorama.coverageInfo;

    final peakTemp = sortedMeasurements.isNotEmpty
        ? sortedMeasurements
              .map((e) => e.maxTemperatureC)
              .reduce((a, b) => a > b ? a : b)
        : (m?.maxTemperatureC ?? 0.0);
    final baselineTemp = insp?.inspection.baselineTemperatureC;
    final double? voltage =
        m?.voltageV ??
        (sortedMeasurements.isNotEmpty
            ? sortedMeasurements.first.voltageV
            : null);
    final double? current =
        m?.currentA ??
        (sortedMeasurements.isNotEmpty
            ? sortedMeasurements.first.currentA
            : null);
    final double? power =
        m?.powerW ??
        (sortedMeasurements.isNotEmpty
            ? sortedMeasurements.first.powerW
            : (voltage != null && current != null ? voltage * current : null));
    final xPos =
        m?.xPositionCm ??
        (sortedMeasurements.isNotEmpty
            ? sortedMeasurements.first.xPositionCm
            : 0.0);

    final delta = (peakTemp > 0 && baselineTemp != null && baselineTemp > 0)
        ? (peakTemp - baselineTemp)
        : null;

    final panelLength =
        (module.panelLengthCm != null && module.panelLengthCm! > 0)
        ? module.panelLengthCm!
        : 20.0;

    final String deltaText;
    if (hasConfirmedHotspots) {
      deltaText = delta != null
          ? 'Delta: +${delta.toStringAsFixed(1)}°C (Hotspot)'
          : 'Hotspot Confirmed';
    } else {
      deltaText = delta != null
          ? 'Delta: ${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}°C (Normal)'
          : 'Delta: N/A';
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(
                      Icons.grid_view_rounded,
                      color: AppColors.secondary,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Radiometric Thermal Panorama',
                        style: AppTypography.caption.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: hasConfirmedHotspots
                      ? AppColors.errorBackground
                      : AppColors.successBackground,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: hasConfirmedHotspots
                        ? AppColors.errorBorder
                        : AppColors.successBorder,
                  ),
                ),
                child: Text(
                  deltaText,
                  style: AppTypography.caption.copyWith(
                    color: hasConfirmedHotspots
                        ? AppColors.error
                        : AppColors.success,
                    fontWeight: FontWeight.w800,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 2D Thermal Viewport with Real Thermal Panorama & Physical Frames on X-Ruler
          Container(
            height: 200,
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
                            usableW,
                          );

                      double xToPx(double xCm) =>
                          padLeft + ((xCm - panorama.minDomainX) * pxPerCm);

                      return Stack(
                        children: [
                          // Real 2D Thermal Mosaic Layer (only when valid 32x24 thermal_frame exists)
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
                          else if (sortedMeasurements.isNotEmpty)
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
                                    'No thermal_frame matrix available',
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
                                    panelLength: panelLength,
                                    xToPx: xToPx,
                                    maxWidth: w,
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Physical Frame FOV Strips ([x_i - 2.5, x_i + 2.5] cm)
                          Positioned(
                            top: 36,
                            left: 0,
                            right: 0,
                            bottom: 34,
                            child: sortedMeasurements.isEmpty
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
                                    children: sortedMeasurements
                                        .asMap()
                                        .entries
                                        .map((entry) {
                                          final idx = entry.key;
                                          final meas = entry.value;
                                          final leftEdgeCm =
                                              meas.xPositionCm -
                                              ThermalCoverageInfo.halfFovCm;
                                          final leftPx = xToPx(leftEdgeCm);
                                          final associatedAnomalies =
                                              getFrameAssociatedAnomalies(
                                                meas,
                                                confirmedAnomalies,
                                              );
                                          final isFrameConfirmed =
                                              associatedAnomalies.isNotEmpty;

                                          return Positioned(
                                            key: Key('fov_strip_${idx + 1}'),
                                            left: leftPx.clamp(
                                              0.0,
                                              w - framePxWidth,
                                            ),
                                            width: framePxWidth,
                                            top: 0,
                                            bottom: 0,
                                            child: Container(
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: isFrameConfirmed
                                                    ? AppColors.error
                                                          .withValues(
                                                            alpha: 0.18,
                                                          )
                                                    : Colors.white.withValues(
                                                        alpha: 0.06,
                                                      ),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: isFrameConfirmed
                                                      ? AppColors.error
                                                      : Colors.white.withValues(
                                                          alpha: 0.45,
                                                        ),
                                                  width: isFrameConfirmed
                                                      ? 1.5
                                                      : 1,
                                                ),
                                              ),
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 3,
                                                          vertical: 1,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: isFrameConfirmed
                                                          ? AppColors.error
                                                                .withValues(
                                                                  alpha: 0.85,
                                                                )
                                                          : Colors.black
                                                                .withValues(
                                                                  alpha: 0.55,
                                                                ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            3,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      'F${idx + 1} (${meas.xPositionCm.toStringAsFixed(0)}cm)',
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 8,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                  ),
                                                  Text(
                                                    '${meas.maxTemperatureC.toStringAsFixed(1)}°C',
                                                    style: TextStyle(
                                                      color: isFrameConfirmed
                                                          ? AppColors
                                                                .errorBackground
                                                          : Colors.white,
                                                      fontSize: 8.5,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        })
                                        .toList(),
                                  ),
                          ),

                          // Confirmed Hotspot Target Markers (Strictly from latestInspection.confirmedAnomalies)
                          ...confirmedAnomalies.asMap().entries.map((entry) {
                            final anomIdx = entry.key;
                            final anomaly = entry.value;
                            final anomalyPx = xToPx(
                              anomaly.xPositionCm,
                            ).clamp(14.0, w - 24.0);
                            return Positioned(
                              key: Key('rail_hotspot_marker_${anomIdx + 1}'),
                              top: 28,
                              left: anomalyPx - 10,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppColors.error,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: AppColors.error,
                                          blurRadius: 8,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: const Center(
                                      child: Icon(
                                        Icons.priority_high_rounded,
                                        color: Colors.white,
                                        size: 12,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.75,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: AppColors.error,
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      'HOTSPOT ${anomaly.xPositionCm.toStringAsFixed(1)}cm',
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 8,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      );
                    },
                  ),

                  // Live Metadata Badges
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
          const SizedBox(height: 12),

          // Calibrated Thermal Scale Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              height: 10,
              decoration: BoxDecoration(
                color: panorama.hasValidTemperatures
                    ? null
                    : ThermalPanoramaPainter.unresolvedInvalidColor,
                gradient: panorama.hasValidTemperatures
                    ? const LinearGradient(
                        colors: AppColors.thermalSpectrum,
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 4),
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
                      ? 'Baseline: ${baselineTemp.toStringAsFixed(1)}°C'
                      : 'Mid: ${((panorama.minValidTempC! + panorama.maxValidTempC!) / 2.0).toStringAsFixed(1)}°C',
                  style: AppTypography.caption.copyWith(fontSize: 10),
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
                    'Baseline: ${baselineTemp.toStringAsFixed(1)}°C',
                    style: AppTypography.caption.copyWith(fontSize: 10),
                  ),
              ],
            ),

          // Explicit Diagnostic & Coverage State Notices
          ..._buildStateNotices(
            panorama: panorama,
            coverage: coverage,
          ),

          const SizedBox(height: 14),

          // Physical Thermal Frames (5 cm Sectors • Step 2 cm)
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
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: sortedMeasurements.isEmpty
                  ? [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(10),
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
                  : sortedMeasurements.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final f = entry.value;
                      final anomalyLabels = getFrameAnomalyLabels(
                        f,
                        confirmedAnomalies,
                      );
                      final isConfirmed = anomalyLabels.isNotEmpty;

                      final vStr = f.voltageV != null
                          ? '${f.voltageV!.toStringAsFixed(1)}V'
                          : 'N/A';
                      final iStr = f.currentA != null
                          ? '${f.currentA!.toStringAsFixed(2)}A'
                          : 'N/A';
                      final pStr = f.powerW != null
                          ? '${f.powerW!.toStringAsFixed(1)}W'
                          : 'N/A';

                      final fovStart =
                          f.xPositionCm - ThermalCoverageInfo.halfFovCm;
                      final fovEnd =
                          f.xPositionCm + ThermalCoverageInfo.halfFovCm;

                      return Container(
                        key: Key('thermal_frame_card_${idx + 1}'),
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isConfirmed
                              ? AppColors.errorBackground
                              : AppColors.background,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isConfirmed
                                ? AppColors.error
                                : AppColors.border,
                            width: isConfirmed ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isConfirmed
                                      ? Icons.warning_amber_rounded
                                      : Icons.check_circle_outline_rounded,
                                  size: 14,
                                  color: isConfirmed
                                      ? AppColors.error
                                      : AppColors.success,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'F${idx + 1} (X=${f.xPositionCm.toStringAsFixed(1)} cm)',
                                  style: AppTypography.caption.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: isConfirmed
                                        ? AppColors.error
                                        : AppColors.textPrimary,
                                  ),
                                ),
                                if (isConfirmed) ...[
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.error,
                                      borderRadius: BorderRadius.circular(3),
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
                                      padding: const EdgeInsets.only(left: 3),
                                      child: Container(
                                        key: Key(
                                          'frame_${idx + 1}_badge_$label',
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.textPrimary,
                                          borderRadius: BorderRadius.circular(
                                            3,
                                          ),
                                        ),
                                        child: Text(
                                          label,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 8,
                                            fontWeight: FontWeight.w700,
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
                            Text(
                              '$vStr • $iStr • $pStr',
                              style: AppTypography.caption.copyWith(
                                fontSize: 9.0,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
            ),
          ),
          const SizedBox(height: 16),

          // 4 Key Telemetry Metrics Grid with Baseline Temperature
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  label: 'Peak Temperature',
                  value: '${peakTemp.toStringAsFixed(1)}°C',
                  subtext: hasConfirmedHotspots
                      ? (delta != null
                            ? 'Delta: +${delta.toStringAsFixed(1)}°C (Hotspot)'
                            : 'Hotspot confirmed')
                      : (peakTemp < 60.0 ? 'Normal curve' : 'Exceeds 60°C'),
                  isWarning: hasConfirmedHotspots,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricTile(
                  label: 'Baseline Temperature',
                  value: baselineTemp != null && baselineTemp > 0
                      ? '${baselineTemp.toStringAsFixed(1)}°C'
                      : 'N/A',
                  subtext: 'Inspection reference baseline',
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
                  label: 'DC Voltage & Current',
                  value: (voltage == null && current == null)
                      ? 'N/A'
                      : '${voltage != null ? "${voltage.toStringAsFixed(1)} V" : "N/A"} · ${current != null ? "${current.toStringAsFixed(2)} A" : "N/A"}',
                  subtext: 'Array electrical output',
                  isWarning: false,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricTile(
                  label: 'Active Power',
                  value: power != null ? '${power.toStringAsFixed(1)} W' : 'N/A',
                  subtext: (voltage != null && current != null)
                      ? 'Calculated (V × I)'
                      : 'Yield output',
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
              'Measurements without thermal_frame (${panorama.framesWithoutMatrixCount} of $loadedCount)',
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
              'Invalid pixels detected: ${panorama.totalInvalidPixelsInFrames} (${panorama.complementedCellCount} complemented, ${panorama.unresolvedInvalidCellCount} unresolved)',
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
              'Anomaly confirming measurements not loaded (${panorama.anomaliesWithoutLoadedConfirmingFrames.length})',
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
              'Partial data loaded (pagination): $loadedCount of ${coverage.totalInspectionMeasurements} measurements',
          isWarning: true,
        ),
      );
    }

    if (coverage.isIncompleteCoverage) {
      notices.add(
        _buildNoticeBanner(
          key: const Key('notice_incomplete_coverage'),
          icon: Icons.short_text_rounded,
          text:
              'Incomplete coverage: $loadedCount of ${coverage.expectedAcquisitions} expected acquisitions',
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
              'Exceeded expected coverage: $loadedCount of ${coverage.expectedAcquisitions} expected acquisitions',
          isWarning: false,
        ),
      );
    }

    if (notices.isEmpty) return const [];
    return [
      const SizedBox(height: 8),
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
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isWarning ? AppColors.warningBackground : AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isWarning ? AppColors.warningBorder : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 14,
            color: isWarning ? AppColors.warning : AppColors.textSecondary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: AppTypography.caption.copyWith(
                fontSize: 10,
                color: isWarning ? AppColors.warning : AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildRulerTicks({
    required double panelLength,
    required double Function(double xCm) xToPx,
    required double maxWidth,
  }) {
    final widgets = <Widget>[];
    final step = panelLength <= 20.0 ? 5.0 : 10.0;
    for (double x = 0; x <= panelLength; x += step) {
      final leftPx = xToPx(x);
      widgets.add(
        Positioned(
          left: (leftPx - 8).clamp(4.0, maxWidth - 28.0),
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
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: isWarning ? AppColors.error : AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
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
