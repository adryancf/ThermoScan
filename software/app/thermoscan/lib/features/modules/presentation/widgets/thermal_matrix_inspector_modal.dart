import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';
import 'package:thermoscan/features/modules/presentation/widgets/thermal_panorama_painter.dart';

/// CustomPainter that renders the 32×24 single frame matrix plus an interactive
/// crosshair highlighting the currently selected `(selectedCol, selectedRow)` pixel.
class SingleFrameThermalMatrixPainter extends SingleFrameMatrixPainter {
  const SingleFrameThermalMatrixPainter({
    required super.thermalFrame,
    required super.colorForTemperature,
    required this.selectedCol,
    required this.selectedRow,
  });

  final int selectedCol;
  final int selectedRow;

  @override
  void paint(Canvas canvas, Size size) {
    super.paint(canvas, size);

    const cols = ThermalCoverageInfo.sensorCols;
    const rows = ThermalCoverageInfo.sensorRows;
    final cellW = size.width / cols;
    final cellH = size.height / rows;

    final col = selectedCol.clamp(0, cols - 1);
    final row = selectedRow.clamp(0, rows - 1);
    final cx = (col + 0.5) * cellW;
    final cy = (row + 0.5) * cellH;

    final crosshairGuidePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.65)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), crosshairGuidePaint);
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), crosshairGuidePaint);

    final cellRect = Rect.fromLTWH(col * cellW, row * cellH, cellW, cellH);
    final outerBorderPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.85)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke;
    final innerBorderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    canvas.drawRect(cellRect.inflate(1.0), outerBorderPaint);
    canvas.drawRect(cellRect.inflate(1.0), innerBorderPaint);
  }

  @override
  bool shouldRepaint(covariant SingleFrameThermalMatrixPainter oldDelegate) {
    return super.shouldRepaint(oldDelegate) ||
        oldDelegate.selectedCol != selectedCol ||
        oldDelegate.selectedRow != selectedRow;
  }
}

/// Finds the hottest valid pixel `(col, row, temp)` in a 32×24 thermal frame.
({int col, int row, double temp}) findPeakThermalPixel(
  List<double?>? thermalFrame, {
  double fallbackTemp = 0.0,
}) {
  if (thermalFrame != null &&
      thermalFrame.length == ThermalCoverageInfo.sensorPixelCount) {
    var bestIdx = 0;
    double? bestVal;
    for (var i = 0; i < thermalFrame.length; i++) {
      final v = thermalFrame[i];
      if (ThermalPanoramaData.isValidPixelValue(v)) {
        if (bestVal == null || v! > bestVal) {
          bestVal = v;
          bestIdx = i;
        }
      }
    }
    final row = bestIdx ~/ ThermalCoverageInfo.sensorCols;
    final col = bestIdx % ThermalCoverageInfo.sensorCols;
    return (
      col: col.clamp(0, ThermalCoverageInfo.sensorCols - 1),
      row: row.clamp(0, ThermalCoverageInfo.sensorRows - 1),
      temp: bestVal ?? fallbackTemp,
    );
  }
  return (col: 16, row: 12, temp: fallbackTemp);
}

/// Returns the valid temperature at `(col, row)` in a 32×24 frame, or `null` if unavailable.
double? getThermalPixelTemp(
  List<double?>? thermalFrame,
  int col,
  int row,
) {
  if (thermalFrame != null &&
      thermalFrame.length == ThermalCoverageInfo.sensorPixelCount) {
    final idx = (row.clamp(0, ThermalCoverageInfo.sensorRows - 1) *
            ThermalCoverageInfo.sensorCols) +
        col.clamp(0, ThermalCoverageInfo.sensorCols - 1);
    final val = thermalFrame[idx];
    if (ThermalPanoramaData.isValidPixelValue(val)) {
      return val;
    }
  }
  return null;
}

/// Computes `(min, avg, max)` from all valid pixels in a thermal matrix.
({double min, double avg, double max})? computeThermalMatrixStats(
  List<double?>? thermalFrame,
) {
  if (thermalFrame == null || thermalFrame.isEmpty) return null;
  double? minT;
  double? maxT;
  var sum = 0.0;
  var count = 0;
  for (final val in thermalFrame) {
    if (ThermalPanoramaData.isValidPixelValue(val)) {
      final v = val!;
      if (minT == null || v < minT) minT = v;
      if (maxT == null || v > maxT) maxT = v;
      sum += v;
      count++;
    }
  }
  if (count == 0 || minT == null || maxT == null) return null;
  return (min: minT, avg: sum / count, max: maxT);
}

/// Maps a temperature to [AppColors.thermalSpectrum] across `[minTemp, maxTemp]`.
Color thermalSpectrumColorForTemperature(
  double tempC, {
  required double minTemp,
  required double maxTemp,
}) {
  if (!ThermalPanoramaData.isValidPixelValue(tempC)) {
    return ThermalPanoramaPainter.unresolvedInvalidColor;
  }
  final span = maxTemp - minTemp;
  final normalized =
      span.abs() < 1e-6 ? 0.5 : ((tempC - minTemp) / span).clamp(0.0, 1.0);
  const spectrum = AppColors.thermalSpectrum;
  if (spectrum.length == 1) return spectrum.first;

  final scaled = normalized * (spectrum.length - 1);
  final lowerIdx = scaled.floor().clamp(0, spectrum.length - 1);
  final upperIdx = scaled.ceil().clamp(0, spectrum.length - 1);
  final t = scaled - lowerIdx;
  return Color.lerp(spectrum[lowerIdx], spectrum[upperIdx], t) ??
      spectrum[lowerIdx];
}

String formatThermalTimestamp(String? iso) {
  if (iso == null || iso.isEmpty) return 'Recent';
  final dt = DateTime.tryParse(iso)?.toLocal();
  if (dt == null) return iso;

  final now = DateTime.now();
  final isToday =
      dt.year == now.year && dt.month == now.month && dt.day == now.day;

  final hour12 = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
  final minuteStr = dt.minute.toString().padLeft(2, '0');
  final ampm = dt.hour >= 12 ? 'PM' : 'AM';
  final timeStr = '$hour12:$minuteStr $ampm';

  if (isToday) {
    return 'Today at $timeStr';
  }
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year} at $timeStr';
}

/// Reusable interactive 32×24 thermal matrix viewer with tap/drag pixel crosshair,
/// color ramp legend, optional Min/Avg/Max summary stats, and live pixel telemetry.
class InteractiveThermalMatrixView extends StatefulWidget {
  const InteractiveThermalMatrixView({
    super.key,
    required this.thermalFrame,
    required this.colorForTemperature,
    this.fallbackPeakTemp,
    this.baselineTemp,
    this.hotspotDeltaThresholdC = 8.0,
    this.minTemp,
    this.avgTemp,
    this.maxTemp,
    this.scaleColors = AppColors.thermalSpectrum,
    this.showStatsRow = true,
    this.showColorScale = true,
    this.canvasHeight = 160,
    this.frameIdentity,
    this.canvasKey = const Key('single_frame_matrix_canvas'),
    this.telemetryKey = const Key('selected_pixel_telemetry'),
  });

  final List<double?> thermalFrame;
  final Color Function(double tempC) colorForTemperature;
  final double? fallbackPeakTemp;
  final double? baselineTemp;
  final double hotspotDeltaThresholdC;
  final double? minTemp;
  final double? avgTemp;
  final double? maxTemp;
  final List<Color> scaleColors;
  final bool showStatsRow;
  final bool showColorScale;
  final double canvasHeight;
  final Object? frameIdentity;
  final Key canvasKey;
  final Key telemetryKey;

  @override
  State<InteractiveThermalMatrixView> createState() =>
      _InteractiveThermalMatrixViewState();
}

class _InteractiveThermalMatrixViewState
    extends State<InteractiveThermalMatrixView> {
  late int _selectedCol;
  late int _selectedRow;

  @override
  void initState() {
    super.initState();
    _resetToPeakPixel();
  }

  @override
  void didUpdateWidget(covariant InteractiveThermalMatrixView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.frameIdentity != oldWidget.frameIdentity ||
        widget.thermalFrame != oldWidget.thermalFrame) {
      _resetToPeakPixel();
    }
  }

  void _resetToPeakPixel() {
    final peak = findPeakThermalPixel(
      widget.thermalFrame,
      fallbackTemp: widget.fallbackPeakTemp ?? 0.0,
    );
    _selectedCol = peak.col;
    _selectedRow = peak.row;
  }

  void _selectAt(Offset localPos, Size canvasSize) {
    final w = canvasSize.width <= 0 ? 1.0 : canvasSize.width;
    final h = canvasSize.height <= 0 ? 1.0 : canvasSize.height;
    final col = ((localPos.dx / w) * ThermalCoverageInfo.sensorCols)
        .floor()
        .clamp(0, ThermalCoverageInfo.sensorCols - 1);
    final row = ((localPos.dy / h) * ThermalCoverageInfo.sensorRows)
        .floor()
        .clamp(0, ThermalCoverageInfo.sensorRows - 1);
    if (col != _selectedCol || row != _selectedRow) {
      setState(() {
        _selectedCol = col;
        _selectedRow = row;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasMatrix =
        widget.thermalFrame.length == ThermalCoverageInfo.sensorPixelCount;
    final computed = computeThermalMatrixStats(widget.thermalFrame);
    final effectiveMin = widget.minTemp ?? computed?.min;
    final effectiveAvg = widget.avgTemp ?? computed?.avg;
    final effectiveMax = widget.maxTemp ?? computed?.max ?? widget.fallbackPeakTemp;

    final rawPixelTemp = getThermalPixelTemp(
      widget.thermalFrame,
      _selectedCol,
      _selectedRow,
    );
    final double? pixelTemp =
        rawPixelTemp ?? (hasMatrix ? null : widget.fallbackPeakTemp);
    final double? pixelDelta =
        (pixelTemp != null && widget.baselineTemp != null && widget.baselineTemp! > 0)
            ? (pixelTemp - widget.baselineTemp!)
            : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showStatsRow &&
            (effectiveMin != null ||
                effectiveAvg != null ||
                effectiveMax != null)) ...[
          Row(
            children: [
              Expanded(
                child: _ThermalStatChip(
                  label: 'Min',
                  value: effectiveMin != null
                      ? '${effectiveMin.toStringAsFixed(1)}°C'
                      : 'N/A',
                  color: AppColors.thermalCold,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _ThermalStatChip(
                  label: 'Avg',
                  value: effectiveAvg != null
                      ? '${effectiveAvg.toStringAsFixed(1)}°C'
                      : 'N/A',
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _ThermalStatChip(
                  label: 'Max',
                  value: effectiveMax != null
                      ? '${effectiveMax.toStringAsFixed(1)}°C'
                      : 'N/A',
                  color: AppColors.thermalHot,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Container(
          height: widget.canvasHeight,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final canvasSize = Size(
                  math.max(1.0, constraints.maxWidth),
                  math.max(1.0, constraints.maxHeight),
                );
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => _selectAt(d.localPosition, canvasSize),
                  onPanUpdate: (d) => _selectAt(d.localPosition, canvasSize),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CustomPaint(
                        key: widget.canvasKey,
                        painter: SingleFrameThermalMatrixPainter(
                          thermalFrame:
                              hasMatrix ? widget.thermalFrame : const <double?>[],
                          colorForTemperature: widget.colorForTemperature,
                          selectedCol: _selectedCol,
                          selectedRow: _selectedRow,
                        ),
                      ),
                      if (!hasMatrix)
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'No 32×24 matrix data in this acquisition',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        if (widget.showColorScale && widget.scaleColors.isNotEmpty) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              height: 6,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: widget.scaleColors),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                effectiveMin != null
                    ? '${effectiveMin.toStringAsFixed(1)}°C'
                    : 'Cool',
                style: AppTypography.caption.copyWith(
                  fontSize: 9.5,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                'Tap or drag pixel to inspect',
                style: AppTypography.caption.copyWith(
                  fontSize: 9.5,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                effectiveMax != null
                    ? '${effectiveMax.toStringAsFixed(1)}°C'
                    : 'Hot',
                style: AppTypography.caption.copyWith(
                  fontSize: 9.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Container(
          key: widget.telemetryKey,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Pixel (Col $_selectedCol, Row $_selectedRow)',
                style: AppTypography.caption.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                pixelTemp != null ? '${pixelTemp.toStringAsFixed(1)} °C' : 'N/A',
                style: AppTypography.caption.copyWith(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
              if (pixelDelta != null)
                Text(
                  '${pixelDelta >= 0 ? '+' : ''}${pixelDelta.toStringAsFixed(1)} °C vs Normal',
                  style: AppTypography.caption.copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: pixelDelta >=
                            (widget.hotspotDeltaThresholdC > 0
                                ? widget.hotspotDeltaThresholdC
                                : 8.0)
                        ? AppColors.error
                        : AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ThermalStatChip extends StatelessWidget {
  const _ThermalStatChip({
    required this.label,
    required this.value,
    required this.color,
    this.chipKey,
  });

  final String label;
  final String value;
  final Color color;
  final Key? chipKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: chipKey,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.caption.copyWith(
              fontSize: 10,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppTypography.dataValue.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays a clean pop-up dialog inspecting a captured 32×24 [LocalizedReading].
Future<void> showLocalizedReadingDialog(
  BuildContext context,
  LocalizedReading reading,
) {
  final matrix = reading.thermalMatrix.cast<double?>();
  final computed = computeThermalMatrixStats(matrix);
  final minT = reading.minTemperatureC;
  final maxT = reading.maxTemperatureC;
  final scaleMin = computed?.min ?? minT;
  final scaleMax = computed?.max ?? maxT;

  final positionLabel = reading.panelIndex != null
      ? 'X = ${reading.xPositionCm.toStringAsFixed(1)} cm (Panel P${reading.panelIndex})'
      : 'X = ${reading.xPositionCm.toStringAsFixed(1)} cm';

  return showDialog<void>(
    context: context,
    builder: (dialogCtx) => Dialog(
      key: const Key('localized_reading_dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.grid_on_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Localized Thermal Reading',
                          style: AppTypography.h3.copyWith(fontSize: 16),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          positionLabel,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formatThermalTimestamp(reading.effectiveTimestamp),
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('localized_reading_close_icon'),
                    onPressed: () => Navigator.of(dialogCtx).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                    tooltip: 'Close',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Summary metrics: Min / Avg / Max °C
              Row(
                children: [
                  Expanded(
                    child: _ThermalStatChip(
                      chipKey: const Key('localized_stat_min'),
                      label: 'Min Temp',
                      value: '${reading.minTemperatureC.toStringAsFixed(1)}°C',
                      color: AppColors.thermalCold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ThermalStatChip(
                      chipKey: const Key('localized_stat_avg'),
                      label: 'Avg Temp',
                      value: '${reading.avgTemperatureC.toStringAsFixed(1)}°C',
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ThermalStatChip(
                      chipKey: const Key('localized_stat_max'),
                      label: 'Max Temp',
                      value: '${reading.maxTemperatureC.toStringAsFixed(1)}°C',
                      color: AppColors.thermalHot,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Shared Interactive 32×24 Thermal Matrix
              InteractiveThermalMatrixView(
                thermalFrame: matrix,
                colorForTemperature: (tempC) =>
                    thermalSpectrumColorForTemperature(
                  tempC,
                  minTemp: math.min(minT, scaleMin),
                  maxTemp: math.max(maxT, scaleMax),
                ),
                fallbackPeakTemp: reading.maxTemperatureC,
                minTemp: reading.minTemperatureC,
                avgTemp: reading.avgTemperatureC,
                maxTemp: reading.maxTemperatureC,
                showStatsRow: false,
                canvasHeight: 180,
                frameIdentity:
                    '${reading.moduleId}_${reading.xPositionCm}_${reading.effectiveTimestamp}',
              ),
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  key: const Key('localized_reading_close_button'),
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
