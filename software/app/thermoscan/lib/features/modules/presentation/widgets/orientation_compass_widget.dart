import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/features/modules/data/device_sensor_service.dart';
import 'package:thermoscan/features/modules/presentation/widgets/phone_placement_guide_modal.dart';

class OrientationCompassWidget extends StatefulWidget {
  const OrientationCompassWidget({
    super.key,
    required this.reading,
    required this.onCapture,
    this.onRecapture,
    this.isCapturing = false,
    this.isLocked = false,
    this.lockedAzimuth,
    this.lockedTilt,
  });

  final SurfaceOrientationReading? reading;
  final VoidCallback onCapture;
  final VoidCallback? onRecapture;
  final bool isCapturing;
  final bool isLocked;
  final double? lockedAzimuth;
  final double? lockedTilt;

  @override
  State<OrientationCompassWidget> createState() =>
      _OrientationCompassWidgetState();
}

class _OrientationCompassWidgetState extends State<OrientationCompassWidget> {
  double _lastAngle = 0.0;

  /// Calculates continuous angle to prevent 360-degree spins when crossing 0° (North)
  double _getContinuousAngle(double currentDeg) {
    final targetRad = -currentDeg * (math.pi / 180.0);
    var diff = (targetRad - _lastAngle) % (2 * math.pi);
    if (diff > math.pi) diff -= 2 * math.pi;
    if (diff < -math.pi) diff += 2 * math.pi;
    _lastAngle += diff;
    return _lastAngle;
  }

  String _cardinalDirection(double deg) {
    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final idx = ((deg + 22.5) % 360 / 45).floor();
    return directions[idx % 8];
  }

  @override
  Widget build(BuildContext context) {
    final liveAzimuth = widget.reading?.azimuthDeg ?? 0.0;
    final liveTilt = widget.reading?.tiltDeg ?? 0.0;
    final hasMag = widget.reading?.hasMagnetometer ?? false;

    final displayAzimuth = widget.isLocked && widget.lockedAzimuth != null
        ? widget.lockedAzimuth!
        : liveAzimuth;
    final displayTilt = widget.isLocked && widget.lockedTilt != null
        ? widget.lockedTilt!
        : liveTilt;

    final cardinal = _cardinalDirection(displayAzimuth);
    final continuousAngle = _getContinuousAngle(displayAzimuth);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.isLocked ? AppColors.success : AppColors.border,
          width: widget.isLocked ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Header Status Badge & Placement Guide Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: widget.isLocked
                          ? AppColors.success
                          : (widget.reading != null
                              ? AppColors.primary
                              : Colors.grey),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.isLocked
                        ? 'Locked'
                        : 'Live Sensors',
                    style: AppTypography.h3.copyWith(fontSize: 14),
                  ),
                ],
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: widget.isLocked
                          ? AppColors.successBackground
                          : (hasMag
                              ? AppColors.primarySoft
                              : AppColors.warningBackground),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.isLocked
                              ? Icons.check_circle
                              : (hasMag ? Icons.explore : Icons.screen_rotation),
                          size: 13,
                          color: widget.isLocked
                              ? AppColors.success
                              : (hasMag ? AppColors.primary : AppColors.warning),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.isLocked
                              ? 'Captured'
                              : (hasMag ? 'Compass Active' : 'Tilt Sensor'),
                          style: AppTypography.chip.copyWith(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: widget.isLocked
                                ? AppColors.success
                                : (hasMag ? AppColors.primary : AppColors.warning),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => PhonePlacementGuideModal.show(context),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.25),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.help_outline_rounded,
                            size: 13,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Guide',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Interactive Gauges (Compass Dial + Inclinometer Arc)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // 1. Compass Dial (Smooth Rotational Interpolation)
              Column(
                children: [
                  SizedBox(
                    width: 140,
                    height: 140,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Dial Base
                        Container(
                          width: 136,
                          height: 136,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.background,
                            border: Border.all(
                              color: widget.isLocked
                                  ? AppColors.success.withValues(alpha: 0.4)
                                  : AppColors.primary.withValues(alpha: 0.25),
                              width: 2,
                            ),
                          ),
                        ),

                        // Smooth Rotating Dial (Tween animation avoids jitter & 360 wrap)
                        TweenAnimationBuilder<double>(
                          tween: Tween<double>(end: continuousAngle),
                          duration: const Duration(milliseconds: 120),
                          curve: Curves.easeOutCubic,
                          builder: (context, angle, child) {
                            return Transform.rotate(
                              angle: angle,
                              child: CustomPaint(
                                size: const Size(130, 130),
                                painter: _CompassDialPainter(),
                              ),
                            );
                          },
                        ),

                        // Center Digital Readout
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surface.withValues(alpha: 0.94),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.border.withValues(alpha: 0.6),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${displayAzimuth.toStringAsFixed(1)}°',
                                style: AppTypography.h3.copyWith(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: widget.isLocked
                                      ? AppColors.success
                                      : AppColors.primary,
                                ),
                              ),
                              Text(
                                cardinal,
                                style: AppTypography.caption.copyWith(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Azimuth (North Ref)',
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),

              // 2. Surface Inclinometer (Tilt Gauge)
              Column(
                children: [
                  SizedBox(
                    width: 140,
                    height: 140,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Inclinometer Arc Painter
                        TweenAnimationBuilder<double>(
                          tween: Tween<double>(end: displayTilt),
                          duration: const Duration(milliseconds: 120),
                          curve: Curves.easeOutCubic,
                          builder: (context, animatedTilt, child) {
                            return CustomPaint(
                              size: const Size(130, 130),
                              painter: _TiltGaugePainter(
                                tiltDeg: animatedTilt,
                                isLocked: widget.isLocked,
                              ),
                            );
                          },
                        ),

                        // Center Tilt Readout
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.solar_power_outlined,
                              size: 20,
                              color: widget.isLocked
                                  ? AppColors.success
                                  : AppColors.primary,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${displayTilt.toStringAsFixed(1)}°',
                              style: AppTypography.h3.copyWith(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: widget.isLocked
                                    ? AppColors.success
                                    : AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              'Panel Slope',
                              style: AppTypography.caption.copyWith(
                                fontSize: 10,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tilt (0°-90°)',
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Primary Capture / Recapture Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    widget.isLocked ? AppColors.surface : AppColors.primary,
                foregroundColor:
                    widget.isLocked ? AppColors.primary : Colors.white,
                side: widget.isLocked
                    ? const BorderSide(color: AppColors.primary)
                    : null,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: widget.isLocked ? 0 : 1,
              ),
              icon: widget.isCapturing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      widget.isLocked
                          ? Icons.refresh
                          : Icons.check_circle_outline,
                      size: 20,
                    ),
              label: Text(
                widget.isLocked
                    ? 'Recapture (Return to Live)'
                    : 'Capture Orientation (${liveAzimuth.toStringAsFixed(1)}° / ${liveTilt.toStringAsFixed(1)}°)',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              onPressed: widget.isCapturing
                  ? null
                  : (widget.isLocked
                      ? (widget.onRecapture ?? widget.onCapture)
                      : widget.onCapture),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompassDialPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final tickPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1.5;

    final northPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;

    // Draw ticks around the dial
    for (int i = 0; i < 360; i += 30) {
      final rad = i * (math.pi / 180.0);
      final isMajor = (i % 90 == 0);
      final tickLength = isMajor ? 10.0 : 5.0;

      final p1 = Offset(
        center.dx + (radius - tickLength) * math.sin(rad),
        center.dy - (radius - tickLength) * math.cos(rad),
      );
      final p2 = Offset(
        center.dx + radius * math.sin(rad),
        center.dy - radius * math.cos(rad),
      );

      canvas.drawLine(p1, p2, tickPaint);
    }

    // Draw North arrow pointer
    final path = Path()
      ..moveTo(center.dx, center.dy - radius + 3)
      ..lineTo(center.dx - 6, center.dy - radius + 17)
      ..lineTo(center.dx + 6, center.dy - radius + 17)
      ..close();
    canvas.drawPath(path, northPaint);

    // Cardinal letter 'N'
    const textSpan = TextSpan(
      text: 'N',
      style: TextStyle(
        color: Colors.red,
        fontWeight: FontWeight.bold,
        fontSize: 10,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy - radius + 19),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TiltGaugePainter extends CustomPainter {
  _TiltGaugePainter({
    required this.tiltDeg,
    this.isLocked = false,
  });

  final double tiltDeg;
  final bool isLocked;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;

    final bgPaint = Paint()
      ..color = AppColors.border.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    final activePaint = Paint()
      ..color = isLocked ? AppColors.success : AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    // Background arc (0 to 90 degrees)
    const startAngle = math.pi * 0.75;
    const sweepRange = math.pi * 1.5;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepRange,
      false,
      bgPaint,
    );

    // Active sweep based on tilt (clamped 0 to 90)
    final progress = (tiltDeg / 90.0).clamp(0.0, 1.0);
    final activeSweep = sweepRange * progress;

    if (activeSweep > 0.01) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        activeSweep,
        false,
        activePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TiltGaugePainter oldDelegate) {
    return oldDelegate.tiltDeg != tiltDeg || oldDelegate.isLocked != isLocked;
  }
}
