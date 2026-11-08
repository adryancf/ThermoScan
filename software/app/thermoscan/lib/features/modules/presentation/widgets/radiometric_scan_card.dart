import 'package:flutter/material.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';
import 'package:thermoscan/features/modules/presentation/widgets/thermal_panorama_painter.dart';

/// SCR-10: Physical Thermal Frames & Radiometric Telemetry Metrics
class RadiometricScanCard extends StatefulWidget {
  const RadiometricScanCard({
    super.key,
    required this.module,
    this.latestMeasurement,
    this.latestInspection,
    this.measurements,
    this.initiallyExpanded,
  });

  final PvModule module;
  final ModuleMeasurement? latestMeasurement;
  final LatestInspection? latestInspection;
  final List<ModuleMeasurement>? measurements;
  final bool? initiallyExpanded;

  @override
  State<RadiometricScanCard> createState() => _RadiometricScanCardState();
}

class _RadiometricScanCardState extends State<RadiometricScanCard> {
  bool _fitToScan = true;
  int? _selectedFrameIndex;
  int? _focusedPanelIndex;
  int? _selectedHotspotIndex;
  late bool _isAdvancedExpanded;

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

    final sortedRaw = sortMeasurementsSpatially(rawMeasurements);
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
      fitToScannedRange: _fitToScan,
    );
    final displayedMeasurements = panorama.sortedMeasurements;

    final coverage = panorama.coverageInfo;

    final peakTemp = displayedMeasurements.isNotEmpty
        ? displayedMeasurements
            .map((e) => e.maxTemperatureC)
            .reduce((a, b) => a > b ? a : b)
        : (_focusedPanelIndex == null ? (m?.maxTemperatureC ?? 0.0) : 0.0);

    InspectionPanelResult? focusedPanelResult;
    final pResults = insp?.panelResults;
    if (_focusedPanelIndex != null && pResults != null) {
      for (final pr in pResults) {
        if (pr.panelIndex == _focusedPanelIndex) {
          focusedPanelResult = pr;
          break;
        }
      }
    }
    final baselineTemp = focusedPanelResult?.baselineTemperatureC ??
        insp?.inspection.baselineTemperatureC;

    final ModuleMeasurement? selectedMeas = (_selectedFrameIndex != null &&
            _selectedFrameIndex! >= 0 &&
            _selectedFrameIndex! < displayedMeasurements.length)
        ? displayedMeasurements[_selectedFrameIndex!]
        : null;
    final ModuleMeasurement? refMeas = selectedMeas ??
        (_focusedPanelIndex != null
            ? (displayedMeasurements.isNotEmpty
                ? displayedMeasurements.first
                : null)
            : (m ??
                (displayedMeasurements.isNotEmpty
                    ? displayedMeasurements.first
                    : null)));

    final double? voltage = refMeas?.voltageV;
    final double? current = refMeas?.currentA;
    final double? power = refMeas?.powerW ??
        (voltage != null && current != null ? voltage * current : null);
    final double xPos = refMeas?.xPositionCm ?? 0.0;

    // Relative delta above baseline (strictly relative, never fixed threshold)
    final delta = (peakTemp > 0 && baselineTemp != null && baselineTemp > 0)
        ? (peakTemp - baselineTemp)
        : null;

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
      padding: const EdgeInsets.all(14),
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
                            'Radiometric Thermal Panorama',
                            style: AppTypography.caption.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Continuous radiometric scan & MLX90640 map',
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
                  color: hasConfirmedHotspots
                      ? AppColors.errorBackground
                      : AppColors.successBackground,
                  borderRadius: BorderRadius.circular(8),
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
          const SizedBox(height: 8),

          // Multi-Panel String Selector Chips
          if (widget.module.panelCount != null &&
              widget.module.panelCount! > 1) ...[
            _buildPanelSelector(
              widget.module.panelCount!,
              confirmedAnomalies,
            ),
            const SizedBox(height: 8),
          ],

          // Scale / Zoom Controls & Position Overview on the Rail
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (displayedMeasurements.isNotEmpty)
                Text(
                  'Range: ${panorama.minDomainX.toStringAsFixed(1)} to ${panorama.maxDomainX.toStringAsFixed(1)} cm (${panorama.domainSpanCm.toStringAsFixed(1)} cm)',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                  ),
                )
              else
                const SizedBox.shrink(),
              InkWell(
                key: const Key('toggle_zoom_mode'),
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  setState(() {
                    _fitToScan = !_fitToScan;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _fitToScan ? Icons.zoom_in_rounded : Icons.zoom_out_map_rounded,
                        size: 13,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _fitToScan
                            ? 'Zoom: Scan Area'
                            : (_focusedPanelIndex != null
                                ? 'Zoom: Panel $_focusedPanelIndex'
                                : ((widget.module.panelCount != null &&
                                        widget.module.panelCount! > 1)
                                    ? 'Zoom: Entire String'
                                    : 'Zoom: Full Panel')),
                        style: AppTypography.caption.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
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
            ),

          const SizedBox(height: 6),

          // 2D Thermal Viewport with Real Thermal Panorama
          Container(
            height: 175,
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
                                              w - padLeft - (approxBadgeHalfW * 2),
                                            ),
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
                                            w - padLeft - 28.0,
                                          ),
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
                                                      .clamp(16.0, usableW),
                                                )
                                              : framePxWidth;
                                          final minLeftPx = pb != null
                                              ? xToPx(pb.startXCm).clamp(
                                                  0.0,
                                                  w - stripWidthPx,
                                                )
                                              : 0.0;
                                          final maxLeftPx = pb != null
                                              ? (xToPx(pb.endXCm) - stripWidthPx)
                                                  .clamp(minLeftPx, w - stripWidthPx)
                                              : (w - stripWidthPx);
                                          final clampedLeftPx = rawLeftPx.clamp(
                                            minLeftPx,
                                            maxLeftPx,
                                          );

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
                                                  if (_selectedFrameIndex == idx) {
                                                    _selectedFrameIndex = null;
                                                  } else {
                                                    _selectedFrameIndex = idx;
                                                  }
                                                });
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
                            ).clamp(14.0, w - 30.0);

                            ModuleMeasurement? anomMeas;
                            for (final fm in displayedMeasurements) {
                              if (isFrameAssociatedWithAnomaly(fm, anomaly)) {
                                anomMeas = fm;
                                break;
                              }
                            }
                            final anomPeak = anomMeas?.maxTemperatureC;
                            final anomDelta = (anomPeak != null &&
                                    baselineTemp != null &&
                                    baselineTemp > 0)
                                ? (anomPeak - baselineTemp)
                                : delta;

                            final deltaStr = anomDelta != null
                                ? '+${anomDelta.toStringAsFixed(1)}°C'
                                : '+ΔT°C';
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
                              left: (anomalyPx - 11).clamp(2.0, w - 80.0),
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    if (_selectedHotspotIndex == anomIdx) {
                                      _selectedHotspotIndex = null;
                                    } else {
                                      _selectedHotspotIndex = anomIdx;
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
                                    const SizedBox(height: 3),
                                    // Friendly, legible label
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isPopoverSelected
                                            ? AppColors.error
                                            : Colors.black.withValues(
                                                alpha: 0.85,
                                              ),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: isPopoverSelected
                                              ? Colors.white
                                              : AppColors.error,
                                          width: 1.0,
                                        ),
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            primaryHotspotLabel,
                                            style: TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 8,
                                              color: Colors.white,
                                              fontWeight: isPopoverSelected
                                                  ? FontWeight.w900
                                                  : FontWeight.w700,
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

                                ModuleMeasurement? anomMeas;
                                for (final fm in displayedMeasurements) {
                                  if (isFrameAssociatedWithAnomaly(fm, anomaly)) {
                                    anomMeas = fm;
                                    break;
                                  }
                                }
                                final anomPeak = anomMeas?.maxTemperatureC;
                                final anomDelta = (anomPeak != null &&
                                        baselineTemp != null &&
                                        baselineTemp > 0)
                                    ? (anomPeak - baselineTemp)
                                    : delta;

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
                                                'Peak: ${anomPeak != null ? "${anomPeak.toStringAsFixed(1)}°C" : "N/A"}${anomDelta != null ? " • +${anomDelta.toStringAsFixed(1)}°C above baseline" : ""}',
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
          const SizedBox(height: 12),

          // Calibrated Semantic Thermal Scale Bar
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
                    'Baseline: ${baselineTemp.toStringAsFixed(1)}°C',
                    style: AppTypography.caption.copyWith(fontSize: 10),
                  ),
              ],
            ),

          // Confirmed Hotspot Dual-Frame Confirmation Explainer
          if (hasConfirmedHotspots) ...[
            const SizedBox(height: 10),
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

          const SizedBox(height: 8),

          // Progressive Disclosure Accordion: Advanced Telemetry & Frame Inspector
          _buildAdvancedTelemetryAccordion(
            displayedMeasurements: displayedMeasurements,
            visibleAnomalies: visibleAnomalies,
            coverage: coverage,
            panorama: panorama,
          ),

          const SizedBox(height: 10),

          // 4 Key Telemetry Metrics Grid (Flat, border-only, zero drop shadows)
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
                      : (delta != null
                          ? (delta >= 10.0
                              ? 'Delta: +${delta.toStringAsFixed(1)}°C (Elevated)'
                              : 'Nominal (+${delta.toStringAsFixed(1)}°C ΔT)')
                          : 'Nominal baseline curve'),
                  isWarning: hasConfirmedHotspots,
                  deltaBadge: hasConfirmedHotspots
                      ? 'HOTSPOT ΔT'
                      : (delta != null && delta >= 10.0 ? 'ELEVATED' : null),
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

  /// Progressive Disclosure Accordion containing MLX90640 frame carousel and 32x24 inspector.
  Widget _buildAdvancedTelemetryAccordion({
    required List<ModuleMeasurement> displayedMeasurements,
    required List<ConfirmedAnomaly> visibleAnomalies,
    required ThermalCoverageInfo coverage,
    required ThermalPanoramaData panorama,
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                          'Advanced Telemetry & Frame Inspector',
                          style: AppTypography.caption.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          'Inspect individual MLX90640 32×24 matrix frames and electrical readings',
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                  const SizedBox(height: 4),
                  Text(
                    'Tap a frame to inspect its 32×24 matrix and exact sensor readings',
                    style: AppTypography.caption.copyWith(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),

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

                              return InkWell(
                                key: Key('thermal_frame_card_${idx + 1}'),
                                borderRadius: BorderRadius.circular(10),
                                onTap: () {
                                  setState(() {
                                    if (_selectedFrameIndex == idx) {
                                      _selectedFrameIndex = null;
                                    } else {
                                      _selectedFrameIndex = idx;
                                    }
                                  });
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
                                ),
                              );
                            }).toList(),
                    ),
                  ),

                  // Selected Single-Frame 32x24 Matrix Inspector
                  if (_selectedFrameIndex != null &&
                      _selectedFrameIndex! < displayedMeasurements.length) ...[
                    const SizedBox(height: 12),
                    _buildSelectedFrameInspector(
                      frameIndex: _selectedFrameIndex!,
                      measurement: displayedMeasurements[_selectedFrameIndex!],
                      panorama: panorama,
                      confirmedAnomalies: visibleAnomalies,
                    ),
                  ],
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

  /// Explainer banner showing which frames confirmed each hotspot.
  Widget _buildHotspotConfirmationSummary({
    required List<ConfirmedAnomaly> confirmedAnomalies,
    required List<ModuleMeasurement> sortedMeasurements,
  }) {
    return Container(
      key: const Key('hotspot_confirmation_summary'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.errorBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.errorBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: AppColors.error,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                'Dual-Frame Hotspot Confirmation',
                style: AppTypography.caption.copyWith(
                  color: AppColors.error,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
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
                  fontSize: 10.5,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  /// Inspector panel for viewing the isolated 32x24 matrix of the selected frame.
  Widget _buildSelectedFrameInspector({
    required int frameIndex,
    required ModuleMeasurement measurement,
    required ThermalPanoramaData panorama,
    required List<ConfirmedAnomaly> confirmedAnomalies,
  }) {
    final tf = measurement.thermalFrame;
    final hasMatrix = tf != null && tf.length == ThermalCoverageInfo.sensorPixelCount;
    final anomalyLabels = getFrameAnomalyLabels(measurement, confirmedAnomalies);
    final isConfirmed = anomalyLabels.isNotEmpty;

    return Container(
      key: const Key('selected_frame_inspector'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isConfirmed ? AppColors.error : AppColors.primary,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isConfirmed ? AppColors.error : AppColors.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'F${frameIndex + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Selected Frame (X = ${measurement.xPositionCm.toStringAsFixed(1)} cm)',
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (measurement.panelIndex != null ||
                      measurement.localXPositionCm != null) ...[
                    const SizedBox(width: 6),
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
                ],
              ),
              InkWell(
                onTap: () => setState(() => _selectedFrameIndex = null),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      const Icon(Icons.close_rounded, size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 2),
                      Text(
                        'Close',
                        style: AppTypography.caption.copyWith(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 32x24 Pure Thermal Matrix View
          if (hasMatrix) ...[
            Container(
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CustomPaint(
                  key: const Key('single_frame_matrix_canvas'),
                  painter: SingleFrameMatrixPainter(
                    thermalFrame: tf,
                    colorForTemperature: panorama.colorForTemperature,
                  ),
                ),
              ),
            ),
          ] else ...[
            Container(
              height: 60,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: const Center(
                child: Text(
                  'No 32×24 matrix data in this acquisition',
                  style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
                ),
              ),
            ),
          ],

          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Span: ${(measurement.xPositionCm - 2.5).toStringAsFixed(1)} - ${(measurement.xPositionCm + 2.5).toStringAsFixed(1)} cm',
                style: AppTypography.caption.copyWith(fontSize: 10, color: AppColors.textSecondary),
              ),
              Text(
                'Peak: ${measurement.maxTemperatureC.toStringAsFixed(1)}°C',
                style: AppTypography.caption.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isConfirmed ? AppColors.error : AppColors.textPrimary,
                ),
              ),
              Text(
                '${measurement.voltageV?.toStringAsFixed(1) ?? "N/A"}V • ${measurement.currentA?.toStringAsFixed(2) ?? "N/A"}A • ${measurement.powerW?.toStringAsFixed(1) ?? "N/A"}W',
                style: AppTypography.caption.copyWith(fontSize: 10, color: AppColors.primary),
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
          left: (leftPx - 10).clamp(2.0, maxWidth - 28.0),
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
