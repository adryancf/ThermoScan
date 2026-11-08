import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/core/widgets/app_buttons.dart';

/// Modal bottom sheet demonstrating phone placement on solar panel
/// with a 3D isometric vector animation and explicit portrait instructions.
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
      duration: const Duration(milliseconds: 3800),
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
                    Icons.stay_current_portrait_rounded,
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
                        'Keep device in portrait (upright) mode',
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

            // Animated Visual Diagram (3D Isometric Perspective)
            Container(
              height: 230,
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
                      painter: _IsometricPlacementPainter(
                        progress: _animCtrl.value,
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Step 1: Explicit Portrait Requirement
            const _InstructionRow(
              number: '1',
              title: 'Keep in Portrait Mode (Vertical / Upright)',
              description:
                  'Do NOT place the phone sideways in landscape. Hold or rest the phone vertically (portrait), with its back flat against the solar panel glass.',
              icon: Icons.stay_current_portrait_outlined,
            ),
            const SizedBox(height: 14),

            // Step 2: Point Top Downhill
            const _InstructionRow(
              number: '2',
              title: 'Point Top of Phone Downhill',
              description:
                  'Orient the top camera edge toward the lower edge of the slope (the direction the panel faces down toward the horizon for solar azimuth).',
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
            child: Icon(
              icon,
              size: 16,
              color: AppColors.primary,
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

/// 3D Isometric Painter showing the entire inclined PV panel surface
/// and the smartphone landing on it in a sleek, clearly rectangular PORTRAIT mode.
class _IsometricPlacementPainter extends CustomPainter {
  _IsometricPlacementPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2 + 6;

    // Ground line positioned near bottom
    final groundY = size.height - 18.0;
    final groundPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(20, groundY),
      Offset(size.width - 20, groundY),
      groundPaint,
    );

    // ==========================================
    // 3D Isometric Solar Panel Geometry
    // Slope runs from top-back to bottom-front (downhill)
    // Vertical span of panel: y ~= 56 to y ~= 178
    // ==========================================
    const wx = 75.0;
    const wy = -15.0;
    const lx = 28.0;
    const ly = 46.0;

    final pCenter = Offset(cx - 10, cy);

    final pTopLeft = Offset(pCenter.dx - wx - lx, pCenter.dy - wy - ly);
    final pTopRight = Offset(pCenter.dx + wx - lx, pCenter.dy + wy - ly);
    final pBottomRight = Offset(pCenter.dx + wx + lx, pCenter.dy + wy + ly);
    final pBottomLeft = Offset(pCenter.dx - wx + lx, pCenter.dy - wy + ly);

    // Support legs down to ground line
    final legPaint = Paint()
      ..color = const Color(0xFF64748B)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      pTopLeft,
      Offset(pTopLeft.dx + 4, groundY),
      legPaint,
    );
    canvas.drawLine(
      pTopRight,
      Offset(pTopRight.dx + 4, groundY),
      legPaint,
    );
    canvas.drawLine(
      pBottomLeft,
      Offset(pBottomLeft.dx + 2, groundY),
      legPaint,
    );
    canvas.drawLine(
      pBottomRight,
      Offset(pBottomRight.dx + 2, groundY),
      legPaint,
    );

    // 3D Frame Side Thickness (Extrusion downwards)
    const thickness = 7.0;
    final bottomSidePath = Path()
      ..moveTo(pBottomLeft.dx, pBottomLeft.dy)
      ..lineTo(pBottomRight.dx, pBottomRight.dy)
      ..lineTo(pBottomRight.dx, pBottomRight.dy + thickness)
      ..lineTo(pBottomLeft.dx, pBottomLeft.dy + thickness)
      ..close();
    canvas.drawPath(
      bottomSidePath,
      Paint()..color = const Color(0xFF1E293B),
    );

    final leftSidePath = Path()
      ..moveTo(pTopLeft.dx, pTopLeft.dy)
      ..lineTo(pBottomLeft.dx, pBottomLeft.dy)
      ..lineTo(pBottomLeft.dx, pBottomLeft.dy + thickness)
      ..lineTo(pTopLeft.dx, pTopLeft.dy + thickness)
      ..close();
    canvas.drawPath(
      leftSidePath,
      Paint()..color = const Color(0xFF334155),
    );

    // Photovoltaic Glass Surface (Deep Blue gradient)
    final panelFace = Path()
      ..moveTo(pTopLeft.dx, pTopLeft.dy)
      ..lineTo(pTopRight.dx, pTopRight.dy)
      ..lineTo(pBottomRight.dx, pBottomRight.dy)
      ..lineTo(pBottomLeft.dx, pBottomLeft.dy)
      ..close();

    final glassGradient = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF0369A1), Color(0xFF0C4A6E)],
    ).createShader(Rect.fromPoints(pTopLeft, pBottomRight));

    canvas.drawPath(panelFace, Paint()..shader = glassGradient);

    // Solar Cell Grid Lines
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..strokeWidth = 1.0;

    // Cross grid lines (2 horizontal divisions)
    for (int i = 1; i <= 2; i++) {
      final t = i / 3.0;
      final pL = Offset(
        pTopLeft.dx + (pBottomLeft.dx - pTopLeft.dx) * t,
        pTopLeft.dy + (pBottomLeft.dy - pTopLeft.dy) * t,
      );
      final pR = Offset(
        pTopRight.dx + (pBottomRight.dx - pTopRight.dx) * t,
        pTopRight.dy + (pBottomRight.dy - pTopRight.dy) * t,
      );
      canvas.drawLine(pL, pR, gridPaint);
    }
    // Longitudinal grid line (vertical division)
    final pTopMid = Offset(
      (pTopLeft.dx + pTopRight.dx) / 2,
      (pTopLeft.dy + pTopRight.dy) / 2,
    );
    final pBotMid = Offset(
      (pBottomLeft.dx + pBottomRight.dx) / 2,
      (pBottomLeft.dy + pBottomRight.dy) / 2,
    );
    canvas.drawLine(pTopMid, pBotMid, gridPaint);

    // Aluminum Border Outline
    final frameOutline = Paint()
      ..color = const Color(0xFF94A3B8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawPath(panelFace, frameOutline);

    // ==========================================
    // Bottom Label: Completely below the panel, above the ground line
    // ==========================================
    final slopeLabelPainter = TextPainter(
      text: const TextSpan(
        text: '▼ DOWNHILL (DIRECTION PANEL FACES)',
        style: TextStyle(
          color: Color(0xFF64748B),
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    slopeLabelPainter.paint(
      canvas,
      Offset(cx - slopeLabelPainter.width / 2, size.height - 15),
    );

    // ==========================================
    // Smartphone Landing Animation
    // Proportions: Clearly elongated rectangle (aspect ratio ~ 1.9 : 1)
    // Width = 26px, Length = 49px
    // ==========================================
    double phoneElevation = 0.0;
    double phoneAlpha = 1.0;
    double arrowPulse = 0.0;

    if (progress < 0.42) {
      final t = progress / 0.42;
      final curved = Curves.easeOutCubic.transform(t);
      phoneElevation = (1.0 - curved) * 55.0;
    } else if (progress < 0.52) {
      final t = (progress - 0.42) / 0.10;
      phoneElevation = math.sin(t * math.pi) * 3.0;
    } else if (progress < 0.86) {
      final t = (progress - 0.52) / 0.34;
      phoneElevation = 0.0;
      arrowPulse = Curves.easeInOut.transform((t * 2.2) % 1.0);
    } else {
      final t = (progress - 0.86) / 0.14;
      phoneAlpha = (1.0 - t).clamp(0.0, 1.0);
    }

    // Phone isometric coordinates centered on the panel
    final phoneCenter = Offset(pCenter.dx, pCenter.dy - phoneElevation);

    // Proportions: Narrow width (pw = 13.0) and long slope length (plx = 22, ply = 44)
    const pw = 13.0;
    const pwy = -2.6;
    const plx = 22.0;
    const ply = 44.0;

    final phTopL = Offset(
      phoneCenter.dx - pw - plx * 0.5,
      phoneCenter.dy - pwy - ply * 0.5,
    );
    final phTopR = Offset(
      phoneCenter.dx + pw - plx * 0.5,
      phoneCenter.dy + pwy - ply * 0.5,
    );
    final phBotR = Offset(
      phoneCenter.dx + pw + plx * 0.5,
      phoneCenter.dy + pwy + ply * 0.5,
    );
    final phBotL = Offset(
      phoneCenter.dx - pw + plx * 0.5,
      phoneCenter.dy - pwy + ply * 0.5,
    );

    // Phone drop shadow on panel glass
    if (phoneElevation > 0) {
      final shadowPath = Path()
        ..moveTo(pCenter.dx - pw - plx * 0.5, pCenter.dy - pwy - ply * 0.5)
        ..lineTo(pCenter.dx + pw - plx * 0.5, pCenter.dy + pwy - ply * 0.5)
        ..lineTo(pCenter.dx + pw + plx * 0.5, pCenter.dy + pwy + ply * 0.5)
        ..lineTo(pCenter.dx - pw + plx * 0.5, pCenter.dy - pwy + ply * 0.5)
        ..close();
      canvas.drawPath(
        shadowPath,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.25 * phoneAlpha),
      );
    }

    // Phone body quad (Dark titanium casing)
    final phoneQuad = Path()
      ..moveTo(phTopL.dx, phTopL.dy)
      ..lineTo(phTopR.dx, phTopR.dy)
      ..lineTo(phBotR.dx, phBotR.dy)
      ..lineTo(phBotL.dx, phBotL.dy)
      ..close();

    canvas.drawPath(
      phoneQuad,
      Paint()
        ..color = Color.lerp(
          Colors.transparent,
          const Color(0xFF0F172A),
          phoneAlpha,
        )!,
    );

    // Phone Screen Glass (inset)
    const inset = 2.0;
    final phScreen = Path()
      ..moveTo(phTopL.dx + inset, phTopL.dy + inset)
      ..lineTo(phTopR.dx - inset, phTopR.dy + inset)
      ..lineTo(phBotR.dx - inset, phBotR.dy - inset)
      ..lineTo(phBotL.dx + inset, phBotL.dy - inset)
      ..close();

    canvas.drawPath(
      phScreen,
      Paint()
        ..color = Color.lerp(
          Colors.transparent,
          const Color(0xFF1E293B),
          phoneAlpha,
        )!,
    );

    // Screen border stroke
    canvas.drawPath(
      phoneQuad,
      Paint()
        ..color = Color.lerp(
          Colors.transparent,
          AppColors.primary.withValues(alpha: 0.8),
          phoneAlpha,
        )!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3,
    );

    // Top Camera / Dynamic Island pill pointing DOWNHILL
    final topCameraX = (phBotL.dx + phBotR.dx) / 2;
    final topCameraY = (phBotL.dy + phBotR.dy) / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(topCameraX, topCameraY - 4),
          width: 8,
          height: 3,
        ),
        const Radius.circular(1.5),
      ),
      Paint()
        ..color = Color.lerp(
          Colors.transparent,
          AppColors.primary,
          phoneAlpha,
        )!,
    );

    // Home bar indicator at UPHILL bottom end of phone
    final botBaseX = (phTopL.dx + phTopR.dx) / 2;
    final botBaseY = (phTopL.dy + phTopR.dy) / 2;
    canvas.drawLine(
      Offset(botBaseX - 4, botBaseY + 4),
      Offset(botBaseX + 4, botBaseY + 4),
      Paint()
        ..color = Color.lerp(
          Colors.transparent,
          Colors.white.withValues(alpha: 0.5),
          phoneAlpha,
        )!
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round,
    );

    // Compass circle graphic on phone screen
    canvas.drawCircle(
      phoneCenter,
      7.0,
      Paint()
        ..color = Color.lerp(
          Colors.transparent,
          AppColors.primary.withValues(alpha: 0.35),
          phoneAlpha,
        )!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // Pulsing Directional Azimuth Arrow from phone top edge downhill
    if (progress >= 0.50 && progress < 0.88) {
      final arrowStart = Offset(topCameraX, topCameraY);
      final arrowEnd = Offset(
        topCameraX + (plx * 0.5) + (arrowPulse * 10),
        topCameraY + (ply * 0.5) + (arrowPulse * 10),
      );

      final arrowPaint = Paint()
        ..color = AppColors.primary.withValues(
          alpha: (0.3 + arrowPulse * 0.7) * phoneAlpha,
        )
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(arrowStart, arrowEnd, arrowPaint);

      // Arrow head
      final head = Path()
        ..moveTo(arrowEnd.dx, arrowEnd.dy)
        ..lineTo(arrowEnd.dx - 5, arrowEnd.dy - 5)
        ..lineTo(arrowEnd.dx + 3, arrowEnd.dy - 3)
        ..close();
      canvas.drawPath(
        head,
        Paint()
          ..color = AppColors.primary.withValues(alpha: phoneAlpha)
          ..style = PaintingStyle.fill,
      );
    }

    // ==========================================
    // Top Callout Badge: Placed cleanly at the very top (y = 10 to 32)
    // Completely clear of the solar panel which starts at y ~= 56
    // ==========================================
    if (progress >= 0.40 && progress < 0.86) {
      final textSpan = TextSpan(
        text: '✓ PORTRAIT (UPRIGHT)',
        style: TextStyle(
          color: AppColors.success,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      );
      final calloutPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      final badgeW = calloutPainter.width + 20.0;
      const badgeH = 24.0;
      final badgeX = cx - badgeW / 2;
      const badgeY = 12.0;

      // Clean rounded pill background
      final badgeRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(badgeX, badgeY, badgeW, badgeH),
        const Radius.circular(12),
      );

      canvas.drawRRect(
        badgeRect,
        Paint()..color = AppColors.surface,
      );
      canvas.drawRRect(
        badgeRect,
        Paint()
          ..color = AppColors.success.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );

      calloutPainter.paint(
        canvas,
        Offset(badgeX + 10, badgeY + (badgeH - calloutPainter.height) / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _IsometricPlacementPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
