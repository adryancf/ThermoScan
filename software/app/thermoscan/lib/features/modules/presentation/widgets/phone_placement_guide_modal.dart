import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/core/widgets/app_buttons.dart';

/// Modal bottom sheet demonstrating phone placement on solar panel
/// with a smooth native Flutter vector animation.
class PhonePlacementGuideModal extends StatefulWidget {
  const PhonePlacementGuideModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const PhonePlacementGuideModal(),
    );
  }

  @override
  State<PhonePlacementGuideModal> createState() =>
      _PhonePlacementGuideModalState();
}

class _PhonePlacementGuideModalState extends State<PhonePlacementGuideModal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header Row
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.screen_rotation_outlined,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Placement Guide', style: AppTypography.h3),
                      const SizedBox(height: 2),
                      Text(
                        'How to position your device on the panel',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Animated Visual Diagram
            Container(
              height: 210,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AnimatedBuilder(
                  animation: _animCtrl,
                  builder: (context, child) {
                    return CustomPaint(
                      painter: _PlacementAnimationPainter(
                        progress: _animCtrl.value,
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Step 1
            _InstructionRow(
              number: '1',
              title: 'Lay flat against panel glass',
              description:
                  'Rest the back of your smartphone completely flat on the photovoltaic glass surface.',
              icon: Icons.layers_outlined,
            ),
            const SizedBox(height: 14),

            // Step 2
            _InstructionRow(
              number: '2',
              title: 'Point top edge downhill',
              description:
                  'Orient the top edge of your phone toward the lower edge of the slope (the azimuth direction the panel faces).',
              icon: Icons.south_rounded,
            ),
            const SizedBox(height: 24),

            // Action Button
            PrimaryButton(
              label: 'Got It, Ready to Measure',
              icon: Icons.check_circle_outline,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

class _InstructionRow extends StatelessWidget {
  const _InstructionRow({
    required this.number,
    required this.title,
    required this.description,
    required this.icon,
  });

  final String number;
  final String title;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.body.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                description,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Custom vector painter animating a 3D isometric solar panel and phone landing on it.
class _PlacementAnimationPainter extends CustomPainter {
  _PlacementAnimationPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2 + 15;

    // Ground line / grid baseline
    final groundPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(24, size.height - 24),
      Offset(size.width - 24, size.height - 24),
      groundPaint,
    );

    // Panel orientation: inclined by ~26 degrees
    const panelAngleRad = 26.0 * math.pi / 180.0;
    final panelLength = size.width * 0.65;
    const panelThickness = 8.0;

    // Panel center point
    final pCenter = Offset(cx - 10, cy + 10);

    // Calculate panel endpoints
    final cosA = math.cos(panelAngleRad);
    final sinA = math.sin(panelAngleRad);

    final halfL = panelLength / 2;
    // Top-high end (left-up)
    final topEnd = Offset(pCenter.dx - halfL * cosA, pCenter.dy - halfL * sinA);
    // Lower end (right-down, facing azimuth)
    final bottomEnd =
        Offset(pCenter.dx + halfL * cosA, pCenter.dy + halfL * sinA);

    // Support strut underneath the high end
    final strutPaint = Paint()
      ..color = const Color(0xFF94A3B8)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      topEnd,
      Offset(topEnd.dx + 10, size.height - 24),
      strutPaint,
    );
    canvas.drawLine(
      bottomEnd,
      Offset(bottomEnd.dx - 10, size.height - 24),
      strutPaint,
    );

    // Draw Solar Module Body (aluminum frame + blue cells)
    final panelPath = Path();
    panelPath.moveTo(topEnd.dx, topEnd.dy);
    panelPath.lineTo(bottomEnd.dx, bottomEnd.dy);
    panelPath.lineTo(bottomEnd.dx - panelThickness * sinA,
        bottomEnd.dy + panelThickness * cosA);
    panelPath.lineTo(
        topEnd.dx - panelThickness * sinA, topEnd.dy + panelThickness * cosA);
    panelPath.close();

    // Aluminum frame shadow/fill
    canvas.drawPath(
      panelPath,
      Paint()..color = const Color(0xFF334155),
    );

    // Photovoltaic glass surface (vibrant deep blue)
    final glassPath = Path();
    const borderOffset = 2.0;
    glassPath.moveTo(topEnd.dx + borderOffset * cosA,
        topEnd.dy + borderOffset * sinA - borderOffset * sinA);
    glassPath.lineTo(bottomEnd.dx - borderOffset * cosA,
        bottomEnd.dy - borderOffset * sinA - borderOffset * sinA);
    glassPath.lineTo(bottomEnd.dx - borderOffset * cosA - 4 * sinA,
        bottomEnd.dy - borderOffset * sinA + 4 * cosA);
    glassPath.lineTo(topEnd.dx + borderOffset * cosA - 4 * sinA,
        topEnd.dy + borderOffset * sinA + 4 * cosA);
    glassPath.close();

    final glassPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
      ).createShader(Rect.fromPoints(topEnd, bottomEnd));
    canvas.drawPath(glassPath, glassPaint);

    // Cell divider lines on panel surface
    final cellPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1.0;
    for (int i = 1; i <= 4; i++) {
      final frac = i / 5.0;
      final px = topEnd.dx + (bottomEnd.dx - topEnd.dx) * frac;
      final py = topEnd.dy + (bottomEnd.dy - topEnd.dy) * frac;
      canvas.drawLine(
        Offset(px, py),
        Offset(px - 4 * sinA, py + 4 * cosA),
        cellPaint,
      );
    }

    // "Slope / Azimuth" direction arrow under the lower edge
    final slopeTextPainter = TextPainter(
      text: const TextSpan(
        text: 'Facing / Azimuth ➔',
        style: TextStyle(
          color: Color(0xFF64748B),
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    slopeTextPainter.paint(
      canvas,
      Offset(bottomEnd.dx - 40, bottomEnd.dy + 12),
    );

    // ==========================================
    // Phone Animation Phases (0.0 to 1.0)
    // 0.0 - 0.40: Phone hovers down and tilts to 26°
    // 0.40 - 0.50: Phone lands flat on panel glass
    // 0.50 - 0.85: Phone rests, alignment arrow glows
    // 0.85 - 1.00: Fade transition back to start
    // ==========================================

    double phoneX;
    double phoneY;
    double phoneAngle;
    double phoneAlpha = 1.0;
    double arrowProgress = 0.0;

    if (progress < 0.40) {
      // Phase 1: Descent and tilt
      final t = progress / 0.40;
      final curved = Curves.easeOutCubic.transform(t);
      phoneX = pCenter.dx - (1.0 - curved) * 20;
      phoneY = (pCenter.dy - 65) + curved * 55;
      phoneAngle = curved * panelAngleRad;
    } else if (progress < 0.50) {
      // Phase 2: Touchdown / settling
      final t = (progress - 0.40) / 0.10;
      phoneX = pCenter.dx;
      phoneY = (pCenter.dy - 10) + math.sin(t * math.pi) * 2.0;
      phoneAngle = panelAngleRad;
    } else if (progress < 0.85) {
      // Phase 3: Resting flat on surface + arrow pulsing
      final t = (progress - 0.50) / 0.35;
      phoneX = pCenter.dx;
      phoneY = pCenter.dy - 10;
      phoneAngle = panelAngleRad;
      arrowProgress = Curves.easeInOut.transform((t * 2) % 1.0);
    } else {
      // Phase 4: Fade out
      final t = (progress - 0.85) / 0.15;
      phoneX = pCenter.dx;
      phoneY = pCenter.dy - 10;
      phoneAngle = panelAngleRad;
      phoneAlpha = (1.0 - t).clamp(0.0, 1.0);
    }

    // Draw the smartphone
    canvas.save();
    canvas.translate(phoneX, phoneY);
    canvas.rotate(phoneAngle);

    final phoneW = 44.0;
    final phoneH = 80.0;
    final phoneRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: const Offset(0, 0),
        width: phoneW,
        height: phoneH,
      ),
      const Radius.circular(8),
    );

    // Phone body (dark metallic)
    final phoneBodyPaint = Paint()
      ..color = Color.lerp(
        Colors.transparent,
        const Color(0xFF0F172A),
        phoneAlpha,
      )!
      ..style = PaintingStyle.fill;
    canvas.drawRRect(phoneRect, phoneBodyPaint);

    // Phone screen
    final screenRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: const Offset(0, 0),
        width: phoneW - 4,
        height: phoneH - 6,
      ),
      const Radius.circular(6),
    );
    final phoneScreenPaint = Paint()
      ..color = Color.lerp(
        Colors.transparent,
        const Color(0xFF1E293B),
        phoneAlpha,
      )!;
    canvas.drawRRect(screenRect, phoneScreenPaint);

    // Phone Top Camera / Speaker Notch (identifies the top of the phone)
    final topIndicatorPaint = Paint()
      ..color = Color.lerp(
        Colors.transparent,
        AppColors.primary,
        phoneAlpha,
      )!;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(phoneW / 2 - 8, 0),
          width: 4,
          height: 12,
        ),
        const Radius.circular(2),
      ),
      topIndicatorPaint,
    );

    // Inner Phone compass graphic
    final compassCenterPaint = Paint()
      ..color = Color.lerp(
        Colors.transparent,
        AppColors.primary.withValues(alpha: 0.4),
        phoneAlpha,
      )!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(const Offset(0, 0), 10, compassCenterPaint);

    // Directional indicator from top of phone
    if (progress >= 0.50 && progress < 0.90) {
      final arrowPaint = Paint()
        ..color = AppColors.primary.withValues(
          alpha: (0.3 + arrowProgress * 0.7) * phoneAlpha,
        )
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;

      // Draw arrow extending downhill from top of phone
      final startX = phoneW / 2 + 4;
      final endX = startX + 22 + (arrowProgress * 8);
      canvas.drawLine(Offset(startX, 0), Offset(endX, 0), arrowPaint);

      // Arrow head
      final headPath = Path();
      headPath.moveTo(endX, 0);
      headPath.lineTo(endX - 6, -4);
      headPath.lineTo(endX - 6, 4);
      headPath.close();
      canvas.drawPath(
        headPath,
        Paint()
          ..color = AppColors.primary.withValues(alpha: phoneAlpha)
          ..style = PaintingStyle.fill,
      );
    }

    canvas.restore();

    // Visual label pointing to the top of phone
    if (progress >= 0.40 && progress < 0.85) {
      final labelPaint = TextPainter(
        text: TextSpan(
          text: 'Top edge points down slope',
          style: TextStyle(
            color: AppColors.primary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            backgroundColor: AppColors.surface.withValues(alpha: 0.9),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      labelPaint.paint(canvas, Offset(cx - 30, cy - 65));
    }
  }

  @override
  bool shouldRepaint(covariant _PlacementAnimationPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
