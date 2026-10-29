import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/features/modules/data/device_sensor_service.dart';

class OrientationCompassWidget extends StatelessWidget {
  const OrientationCompassWidget({
    super.key,
    required this.reading,
    required this.onCapture,
    this.isCapturing = false,
  });

  final SurfaceOrientationReading? reading;
  final VoidCallback onCapture;
  final bool isCapturing;

  @override
  Widget build(BuildContext context) {
    final azimuth = reading?.azimuthDeg ?? 0.0;
    final tilt = reading?.tiltDeg ?? 0.0;
    final hasMag = reading?.hasMagnetometer ?? false;
    final cardinal = reading?.cardinalDirection ?? 'N';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: reading != null ? AppColors.success : Colors.grey,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Real-Time Surface Sensors',
                    style: AppTypography.h3.copyWith(fontSize: 15),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: hasMag
                      ? AppColors.primarySoft
                      : AppColors.warningBackground,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  hasMag ? 'Compass Active' : 'Tilt Only',
                  style: AppTypography.chip.copyWith(
                    fontSize: 11,
                    color: hasMag ? AppColors.primary : AppColors.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Place your phone flat and aligned with the solar panel frame.',
            textAlign: TextAlign.start,
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: 18),

          // Interactive Visual Gauges: Compass Dial + Tilt Indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Compass Dial
              Column(
                children: [
                  SizedBox(
                    width: 140,
                    height: 140,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Outer Ring
                        Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.3),
                              width: 2,
                            ),
                            gradient: RadialGradient(
                              colors: [
                                AppColors.background,
                                AppColors.surface,
                              ],
                            ),
                          ),
                        ),

                        // Rotating Compass Rose
                        Transform.rotate(
                          angle: -azimuth * (math.pi / 180.0),
                          child: CustomPaint(
                            size: const Size(130, 130),
                            painter: _CompassDialPainter(),
                          ),
                        ),

                        // Center Readout
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surface.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${azimuth.toStringAsFixed(1)}°',
                                style: AppTypography.h3.copyWith(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
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
                    'Azimuth (Heading)',
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),

              // Tilt / Inclinometer Gauge
              Column(
                children: [
                  SizedBox(
                    width: 140,
                    height: 140,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Tilt circular arc
                        CustomPaint(
                          size: const Size(130, 130),
                          painter: _TiltGaugePainter(tiltDeg: tilt),
                        ),

                        // Center Tilt Readout
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.screen_rotation_outlined,
                              size: 20,
                              color: AppColors.primary,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${tilt.toStringAsFixed(1)}°',
                              style: AppTypography.h3.copyWith(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              'Slope Angle',
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
                    'Surface Tilt (0°-90°)',
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Capture Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              icon: isCapturing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_circle_outline, size: 20),
              label: Text(
                'Capture Orientation (${azimuth.toStringAsFixed(1)}° / ${tilt.toStringAsFixed(1)}°)',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              onPressed: isCapturing ? null : onCapture,
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
      ..lineTo(center.dx - 6, center.dy - radius + 18)
      ..lineTo(center.dx + 6, center.dy - radius + 18)
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
      Offset(center.dx - textPainter.width / 2, center.dy - radius + 20),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TiltGaugePainter extends CustomPainter {
  _TiltGaugePainter({required this.tiltDeg});

  final double tiltDeg;

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
      ..color = AppColors.primary
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
    return oldDelegate.tiltDeg != tiltDeg;
  }
}
