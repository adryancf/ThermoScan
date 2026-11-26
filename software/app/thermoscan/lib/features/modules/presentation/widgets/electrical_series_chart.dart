import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';

enum ElectricalChartMetric {
  power,
  voltage,
  current,
}

class ElectricalSeriesChart extends StatefulWidget {
  const ElectricalSeriesChart({
    super.key,
    required this.points,
    required this.metric,
    required this.range,
    this.height = 200,
  });

  final List<PowerSeriesPoint> points;
  final ElectricalChartMetric metric;
  final String range;
  final double height;

  @override
  State<ElectricalSeriesChart> createState() => _ElectricalSeriesChartState();
}

class _ElectricalSeriesChartState extends State<ElectricalSeriesChart> {
  int? _selectedIndex;

  double? _valueOf(PowerSeriesPoint p) {
    switch (widget.metric) {
      case ElectricalChartMetric.power:
        return p.powerW;
      case ElectricalChartMetric.voltage:
        return p.voltageV;
      case ElectricalChartMetric.current:
        return p.currentA;
    }
  }

  Color get _lineColor {
    switch (widget.metric) {
      case ElectricalChartMetric.power:
        return AppColors.primary;
      case ElectricalChartMetric.voltage:
        return AppColors.accent;
      case ElectricalChartMetric.current:
        return AppColors.secondary;
    }
  }

  String _formatAxisValue(double v) {
    switch (widget.metric) {
      case ElectricalChartMetric.power:
        return v >= 100 ? '${v.toStringAsFixed(0)}W' : '${v.toStringAsFixed(1)}W';
      case ElectricalChartMetric.voltage:
        return '${v.toStringAsFixed(1)}V';
      case ElectricalChartMetric.current:
        return v.abs() < 1.0
            ? '${(v * 1000).toStringAsFixed(0)}mA'
            : '${v.toStringAsFixed(2)}A';
    }
  }

  String _formatTimeLabel(DateTime dt) {
    final local = dt.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    if (widget.range == '1h' || widget.range == '24h') {
      return '$hh:$mm';
    }
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[local.month - 1]} ${local.day}';
  }

  String _formatFullTimestamp(DateTime dt) {
    final local = dt.toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final ss = local.second.toString().padLeft(2, '0');
    return '${months[local.month - 1]} ${local.day}, $hh:$mm:$ss';
  }

  void _updateSelection(Offset localPos, double width) {
    final pts = widget.points;
    if (pts.isEmpty) return;
    const leftPad = 48.0;
    const rightPad = 12.0;
    final chartWidth = math.max(1.0, width - leftPad - rightPad);
    final clampedX = (localPos.dx - leftPad).clamp(0.0, chartWidth);
    if (pts.length == 1) {
      setState(() => _selectedIndex = 0);
      return;
    }
    final ratio = clampedX / chartWidth;
    final idx = (ratio * (pts.length - 1)).round().clamp(0, pts.length - 1);
    if (_selectedIndex != idx) {
      setState(() => _selectedIndex = idx);
    }
  }

  @override
  Widget build(BuildContext context) {
    final validValues = widget.points
        .map(_valueOf)
        .whereType<double>()
        .where((v) => !v.isNaN && !v.isInfinite)
        .toList();

    if (widget.points.isEmpty || validValues.isEmpty) {
      return Container(
        height: widget.height,
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.show_chart_rounded,
              color: AppColors.textSecondary,
              size: 28,
            ),
            const SizedBox(height: 6),
            Text(
              'No electrical readings recorded for this period yet.',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final selectedIdx = (_selectedIndex != null &&
            _selectedIndex! >= 0 &&
            _selectedIndex! < widget.points.length)
        ? _selectedIndex!
        : null;
    final selectedPoint =
        selectedIdx != null ? widget.points[selectedIdx] : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selectedPoint != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  _formatFullTimestamp(selectedPoint.bucketAt),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  formatElectricalPower(selectedPoint.powerW),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  formatElectricalVoltage(selectedPoint.voltageV),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  formatElectricalCurrent(selectedPoint.currentA),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) =>
                  _updateSelection(d.localPosition, constraints.maxWidth),
              onHorizontalDragUpdate: (d) =>
                  _updateSelection(d.localPosition, constraints.maxWidth),
              child: SizedBox(
                height: widget.height,
                width: constraints.maxWidth,
                child: CustomPaint(
                  painter: _ElectricalChartPainter(
                    points: widget.points,
                    valueOf: _valueOf,
                    lineColor: _lineColor,
                    formatY: _formatAxisValue,
                    formatX: _formatTimeLabel,
                    selectedIndex: selectedIdx,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _ElectricalChartPainter extends CustomPainter {
  _ElectricalChartPainter({
    required this.points,
    required this.valueOf,
    required this.lineColor,
    required this.formatY,
    required this.formatX,
    this.selectedIndex,
  });

  final List<PowerSeriesPoint> points;
  final double? Function(PowerSeriesPoint) valueOf;
  final Color lineColor;
  final String Function(double) formatY;
  final String Function(DateTime) formatX;
  final int? selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 48.0;
    const rightPad = 12.0;
    const topPad = 12.0;
    const bottomPad = 24.0;

    final chartRect = Rect.fromLTWH(
      leftPad,
      topPad,
      math.max(1.0, size.width - leftPad - rightPad),
      math.max(1.0, size.height - topPad - bottomPad),
    );

    double minV = double.infinity;
    double maxV = double.negativeInfinity;
    for (final p in points) {
      final v = valueOf(p);
      if (v != null && !v.isNaN && !v.isInfinite) {
        if (v < minV) minV = v;
        if (v > maxV) maxV = v;
      }
    }
    if (!minV.isFinite || !maxV.isFinite) return;

    final rawMin = math.min(0.0, minV);
    final paddedMax = maxV > 0 ? maxV * 1.1 : math.max(0.0, maxV);
    final rawMax = paddedMax <= rawMin ? rawMin + 1.0 : paddedMax;
    final span = rawMax - rawMin;

    final gridPaint = Paint()
      ..color = AppColors.border.withValues(alpha: 0.7)
      ..strokeWidth = 1;

    const gridSteps = 3;
    for (var i = 0; i <= gridSteps; i++) {
      final t = i / gridSteps;
      final y = chartRect.bottom - t * chartRect.height;
      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        gridPaint,
      );

      final labelVal = rawMin + t * span;
      final tp = TextPainter(
        text: TextSpan(
          text: formatY(labelVal),
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: leftPad - 6);
      tp.paint(
        canvas,
        Offset(leftPad - tp.width - 6, y - tp.height / 2),
      );
    }

    double xForIndex(int idx) {
      if (points.length <= 1) return chartRect.center.dx;
      return chartRect.left + (idx / (points.length - 1)) * chartRect.width;
    }

    double yForValue(double v) {
      final norm = ((v - rawMin) / span).clamp(0.0, 1.0);
      return chartRect.bottom - norm * chartRect.height;
    }

    // Build contiguous line & area segments (skipping null sensor readings cleanly)
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final areaPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          lineColor.withValues(alpha: 0.16),
          lineColor.withValues(alpha: 0.01),
        ],
      ).createShader(chartRect)
      ..style = PaintingStyle.fill;

    Path? linePath;
    Path? areaPath;
    double? segStartX;
    double? lastX;
    double? lastY;
    var segCount = 0;

    void flushSegment() {
      if (linePath == null) return;
      if (segCount == 1 && lastX != null && lastY != null) {
        final dotPaint = Paint()..color = lineColor;
        canvas.drawCircle(Offset(lastX!, lastY!), 3.5, dotPaint);
      } else if (segCount > 1 && segStartX != null && lastX != null) {
        areaPath!
          ..lineTo(lastX!, chartRect.bottom)
          ..lineTo(segStartX!, chartRect.bottom)
          ..close();
        canvas.drawPath(areaPath!, areaPaint);
        canvas.drawPath(linePath!, linePaint);
      }
      linePath = null;
      areaPath = null;
      segStartX = null;
      lastX = null;
      lastY = null;
      segCount = 0;
    }

    for (var i = 0; i < points.length; i++) {
      final v = valueOf(points[i]);
      if (v == null || v.isNaN || v.isInfinite) {
        // Skip N/A buckets without breaking the chart line
        continue;
      }
      final x = xForIndex(i);
      final y = yForValue(v);
      if (linePath == null) {
        linePath = Path()..moveTo(x, y);
        areaPath = Path()..moveTo(x, y);
        segStartX = x;
      } else {
        linePath!.lineTo(x, y);
        areaPath!.lineTo(x, y);
      }
      lastX = x;
      lastY = y;
      segCount++;
    }
    flushSegment();

    // X-axis labels (start, mid, end)
    final xIndices = points.length == 1
        ? [0]
        : points.length == 2
            ? [0, 1]
            : [0, points.length ~/ 2, points.length - 1];
    for (final idx in xIndices) {
      final label = formatX(points[idx].bucketAt);
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final rawX = xForIndex(idx) - tp.width / 2;
      final maxX = math.max(chartRect.left, chartRect.right - tp.width);
      final clampedX = rawX.clamp(chartRect.left, maxX);
      tp.paint(canvas, Offset(clampedX, chartRect.bottom + 6));
    }

    // Selected point guide & dot
    if (selectedIndex != null &&
        selectedIndex! >= 0 &&
        selectedIndex! < points.length) {
      final p = points[selectedIndex!];
      final v = valueOf(p);
      final x = xForIndex(selectedIndex!);
      final guidePaint = Paint()
        ..color = lineColor.withValues(alpha: 0.45)
        ..strokeWidth = 1.2;
      canvas.drawLine(
        Offset(x, chartRect.top),
        Offset(x, chartRect.bottom),
        guidePaint,
      );
      if (v != null && !v.isNaN && !v.isInfinite) {
        final y = yForValue(v);
        canvas.drawCircle(Offset(x, y), 5, Paint()..color = AppColors.surface);
        canvas.drawCircle(Offset(x, y), 3.5, Paint()..color = lineColor);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ElectricalChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.selectedIndex != selectedIndex;
  }
}
