import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';
import 'package:thermoscan/features/modules/domain/solar_window_calculator.dart';

/// Ultra-slim Overview card combining Today's Solar Scan Window + Next Scan
/// without clutter or duplicate schedule labels.
class SolarWindowCompactCard extends StatelessWidget {
  const SolarWindowCompactCard({
    super.key,
    required this.window,
    required this.nextScanLabel,
    required this.onTap,
  });

  final DailySolarWindow window;
  final String nextScanLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isOpen = window.isOpenNow;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: Solar Window + Open/Closed badge | Next scan ›
            Row(
              children: [
                const Icon(
                  Icons.wb_sunny_rounded,
                  size: 15,
                  color: AppColors.secondary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Solar Window',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isOpen
                        ? AppColors.successBackground
                        : AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color:
                          isOpen ? AppColors.successBorder : AppColors.border,
                    ),
                  ),
                  child: Text(
                    isOpen ? 'Open' : 'Closed',
                    style: AppTypography.caption.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color:
                          isOpen ? AppColors.success : AppColors.textSecondary,
                    ),
                  ),
                ),
                const Spacer(),
                Flexible(
                  child: Text(
                    nextScanLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: AppColors.primary,
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Slim 24h solar window timeline bar
            SizedBox(
              height: 14,
              width: double.infinity,
              child: CustomPaint(
                painter: _SolarTimelineBarPainter(window: window),
              ),
            ),
            const SizedBox(height: 6),

            // Micro footer: Allowed window + Peak alignment
            Row(
              children: [
                Text(
                  window.hasWindow
                      ? '${window.windowRangeLabel} · ${window.durationLabel}'
                      : 'No valid window today',
                  style: AppTypography.caption.copyWith(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (window.hasWindow)
                  Text(
                    'Peak ${window.peakLabel}',
                    style: AppTypography.caption.copyWith(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SolarTimelineBarPainter extends CustomPainter {
  _SolarTimelineBarPainter({required this.window});

  final DailySolarWindow window;

  @override
  void paint(Canvas canvas, Size size) {
    final trackHeight = 6.0;
    final trackY = (size.height - trackHeight) / 2;
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, trackY, size.width, trackHeight),
      const Radius.circular(3),
    );

    // Blocked / Night background
    canvas.drawRRect(
      trackRect,
      Paint()..color = AppColors.border.withValues(alpha: 0.6),
    );

    // Allowed solar window segment
    if (window.hasWindow) {
      final startFrac = (window.windowStart!.hour +
              window.windowStart!.minute / 60.0) /
          24.0;
      final endFrac =
          (window.windowEnd!.hour + window.windowEnd!.minute / 60.0) / 24.0;
      final left = (startFrac * size.width).clamp(0.0, size.width);
      final right = (endFrac * size.width).clamp(left, size.width);
      final allowedRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, trackY, math.max(2.0, right - left), trackHeight),
        const Radius.circular(3),
      );
      canvas.drawRRect(
        allowedRect,
        Paint()
          ..shader = const LinearGradient(
            colors: [AppColors.secondary, AppColors.success],
          ).createShader(allowedRect.outerRect),
      );
    }

    // Subtle 06h, 12h, 18h tick marks
    final tickPaint = Paint()
      ..color = AppColors.surface.withValues(alpha: 0.85)
      ..strokeWidth = 1;
    for (final h in [6, 12, 18]) {
      final x = (h / 24.0) * size.width;
      canvas.drawLine(
        Offset(x, trackY),
        Offset(x, trackY + trackHeight),
        tickPaint,
      );
    }

    // Current time ("Now") dot
    final nowX = ((window.nowHourFraction / 24.0) * size.width)
        .clamp(4.0, size.width - 4.0);
    final centerY = size.height / 2;
    canvas.drawCircle(
      Offset(nowX, centerY),
      5.5,
      Paint()..color = AppColors.surface,
    );
    canvas.drawCircle(
      Offset(nowX, centerY),
      4.0,
      Paint()
        ..color = window.isOpenNow ? AppColors.success : AppColors.primary,
    );
  }

  @override
  bool shouldRepaint(covariant _SolarTimelineBarPainter oldDelegate) {
    return oldDelegate.window != window;
  }
}

/// Interactive/reactive 24h solar elevation arc chart (CustomPainter).
/// Used both in the Configuration screen (live preview) and the Solar Window sheet.
class SolarWindowCurveChart extends StatelessWidget {
  const SolarWindowCurveChart({
    super.key,
    required this.window,
    this.showNowMarker = true,
    this.height = 148,
  });

  final DailySolarWindow window;
  final bool showNowMarker;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                window.hasWindow
                    ? 'Allowed: ${window.windowRangeLabel}'
                    : 'No valid window',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                window.hasWindow
                    ? '${window.durationLabel} · Min ${window.minSolarAngleDeg.toStringAsFixed(0)}°'
                    : 'Min ${window.minSolarAngleDeg.toStringAsFixed(0)}°',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: height,
            width: double.infinity,
            child: CustomPaint(
              painter: _SolarCurvePainter(
                window: window,
                showNowMarker: showNowMarker,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SolarCurvePainter extends CustomPainter {
  _SolarCurvePainter({
    required this.window,
    required this.showNowMarker,
  });

  final DailySolarWindow window;
  final bool showNowMarker;

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 30.0;
    const rightPad = 8.0;
    const topPad = 10.0;
    const bottomPad = 20.0;

    final rect = Rect.fromLTWH(
      leftPad,
      topPad,
      math.max(1.0, size.width - leftPad - rightPad),
      math.max(1.0, size.height - topPad - bottomPad),
    );

    const maxDeg = 90.0;
    double xForHour(double h) => rect.left + (h / 24.0) * rect.width;
    double yForDeg(double deg) =>
        rect.bottom - (deg.clamp(0.0, maxDeg) / maxDeg) * rect.height;

    // Subtle horizontal grid (0°, 30°, 60°, 90°)
    final gridPaint = Paint()
      ..color = AppColors.border.withValues(alpha: 0.7)
      ..strokeWidth = 0.8;
    for (final deg in [0.0, 30.0, 60.0, 90.0]) {
      final y = yForDeg(deg);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), gridPaint);
      final tp = TextPainter(
        text: TextSpan(
          text: '${deg.toInt()}°',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 9.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftPad - tp.width - 5, y - tp.height / 2));
    }

    // Build curve path (clamped at horizon 0°)
    final fullCurve = Path();
    final allowedFill = Path();
    final blockedFill = Path();

    final threshY = yForDeg(window.minSolarAngleDeg);
    var inAllowed = false;
    double? allowedStartX;
    double? allowedLastX;

    for (var i = 0; i < window.points.length; i++) {
      final p = window.points[i];
      final x = xForHour(p.hourFraction);
      final elev = math.max(0.0, p.elevationDeg);
      final y = yForDeg(elev);

      if (i == 0) {
        fullCurve.moveTo(x, y);
        blockedFill.moveTo(x, rect.bottom);
        blockedFill.lineTo(x, y);
      } else {
        fullCurve.lineTo(x, y);
        blockedFill.lineTo(x, y);
      }

      if (p.isAllowed) {
        if (!inAllowed) {
          inAllowed = true;
          allowedStartX = x;
          allowedFill.moveTo(x, threshY);
          allowedFill.lineTo(x, y);
        } else {
          allowedFill.lineTo(x, y);
        }
        allowedLastX = x;
      } else if (inAllowed && allowedStartX != null && allowedLastX != null) {
        allowedFill.lineTo(allowedLastX, threshY);
        allowedFill.close();
        inAllowed = false;
      }
    }
    if (inAllowed && allowedStartX != null && allowedLastX != null) {
      allowedFill.lineTo(allowedLastX, threshY);
      allowedFill.close();
    }
    if (window.points.isNotEmpty) {
      blockedFill
        ..lineTo(xForHour(window.points.last.hourFraction), rect.bottom)
        ..close();
    }

    // Fill blocked daytime portion lightly
    canvas.drawPath(
      blockedFill,
      Paint()..color = AppColors.border.withValues(alpha: 0.35),
    );

    // Fill allowed portion above threshold
    canvas.drawPath(
      allowedFill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.success.withValues(alpha: 0.28),
            AppColors.secondary.withValues(alpha: 0.14),
          ],
        ).createShader(rect),
    );

    // Draw sun curve
    canvas.drawPath(
      fullCurve,
      Paint()
        ..color = AppColors.secondary
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Dashed threshold line
    final dashPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.7)
      ..strokeWidth = 1.2;
    const dashW = 5.0;
    const dashGap = 4.0;
    var dx = rect.left;
    while (dx < rect.right) {
      canvas.drawLine(
        Offset(dx, threshY),
        Offset(math.min(dx + dashW, rect.right), threshY),
        dashPaint,
      );
      dx += dashW + dashGap;
    }

    // Now marker
    if (showNowMarker) {
      final nowX = xForHour(window.nowHourFraction);
      final nowY = yForDeg(math.max(0.0, window.currentElevationDeg));
      canvas.drawLine(
        Offset(nowX, rect.top),
        Offset(nowX, rect.bottom),
        Paint()
          ..color = (window.isOpenNow ? AppColors.success : AppColors.primary)
              .withValues(alpha: 0.4)
          ..strokeWidth = 1.2,
      );
      canvas.drawCircle(
        Offset(nowX, nowY),
        4.5,
        Paint()..color = AppColors.surface,
      );
      canvas.drawCircle(
        Offset(nowX, nowY),
        3.2,
        Paint()
          ..color = window.isOpenNow ? AppColors.success : AppColors.primary,
      );
    }

    // X-axis hour ticks
    for (final h in [0, 6, 12, 18, 24]) {
      final x = xForHour(h.toDouble());
      final label = '${h.toString().padLeft(2, '0')}h';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 9.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final drawX = (x - tp.width / 2).clamp(rect.left, rect.right - tp.width);
      tp.paint(canvas, Offset(drawX, rect.bottom + 5));
    }
  }

  @override
  bool shouldRepaint(covariant _SolarCurvePainter oldDelegate) {
    return oldDelegate.window != window ||
        oldDelegate.showNowMarker != showNowMarker;
  }
}

/// Opens the clean, minimal-text Solar Scan Window bottom sheet.
Future<void> showSolarWindowSheet({
  required BuildContext context,
  required PvModule module,
  required String nextScanLabel,
  VoidCallback? onOpenScheduleHistory,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _SolarWindowSheetContent(
      module: module,
      nextScanLabel: nextScanLabel,
      onOpenScheduleHistory: onOpenScheduleHistory,
    ),
  );
}

class _SolarWindowSheetContent extends StatefulWidget {
  const _SolarWindowSheetContent({
    required this.module,
    required this.nextScanLabel,
    this.onOpenScheduleHistory,
  });

  final PvModule module;
  final String nextScanLabel;
  final VoidCallback? onOpenScheduleHistory;

  @override
  State<_SolarWindowSheetContent> createState() =>
      _SolarWindowSheetContentState();
}

class _SolarWindowSheetContentState extends State<_SolarWindowSheetContent> {
  SolarSeasonPreset _season = SolarSeasonPreset.today;

  @override
  Widget build(BuildContext context) {
    final lat = widget.module.latitude ?? 0.0;
    final lon = widget.module.longitude ?? 0.0;
    final minAngle = widget.module.minimumSolarAngleDeg ?? 15.0;
    final date = SolarWindowCalculator.dateForSeason(
      season: _season,
      latitude: lat,
    );
    final window = SolarWindowCalculator.computeDailyWindow(
      latitude: lat,
      longitude: lon,
      minSolarAngleDeg: minAngle,
      azimuthDeg: widget.module.azimuthDeg,
      tiltDeg: widget.module.tiltDeg,
      dateLocal: date,
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(
                  Icons.wb_sunny_rounded,
                  size: 20,
                  color: AppColors.secondary,
                ),
                const SizedBox(width: 8),
                Text('Solar Scan Window', style: AppTypography.h2),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: window.isOpenNow
                        ? AppColors.successBackground
                        : AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: window.isOpenNow
                          ? AppColors.successBorder
                          : AppColors.border,
                    ),
                  ),
                  child: Text(
                    window.isOpenNow ? 'Open Now' : 'Closed Now',
                    style: AppTypography.caption.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: window.isOpenNow
                          ? AppColors.success
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Season toggle: Today | Summer | Winter
            Row(
              children: [
                _seasonChip('Today', SolarSeasonPreset.today),
                const SizedBox(width: 6),
                _seasonChip('Summer', SolarSeasonPreset.summer),
                const SizedBox(width: 6),
                _seasonChip('Winter', SolarSeasonPreset.winter),
              ],
            ),
            const SizedBox(height: 12),

            SolarWindowCurveChart(
              window: window,
              showNowMarker: _season == SolarSeasonPreset.today,
              height: 165,
            ),
            const SizedBox(height: 12),

            // 3 compact KPIs
            Row(
              children: [
                _kpiBox('Window', window.windowRangeLabel),
                const SizedBox(width: 8),
                _kpiBox('Duration', window.durationLabel),
                const SizedBox(width: 8),
                _kpiBox('Peak', window.peakLabel),
              ],
            ),
            const SizedBox(height: 12),

            // Compact schedule row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.event_repeat_rounded,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.nextScanLabel,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (widget.onOpenScheduleHistory != null)
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onOpenScheduleHistory!();
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('History'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _seasonChip(String label, SolarSeasonPreset preset) {
    final selected = _season == preset;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _season = preset),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: AppTypography.caption.copyWith(
              color: selected ? Colors.white : AppColors.textSecondary,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _kpiBox(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTypography.caption.copyWith(
                fontSize: 10.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption.copyWith(
                fontSize: 12,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
