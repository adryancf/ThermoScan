import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/core/widgets/app_buttons.dart';

/// Interactive Blueprint widget that renders a visual technical schematic
/// of the solar array and the cleaning robot track in real time.
class ArrayGeometryBlueprintWidget extends StatelessWidget {
  const ArrayGeometryBlueprintWidget({
    super.key,
    required this.panelLengthCm,
    required this.panelWidthCm,
    required this.panelCount,
    required this.panelSpacingCm,
    this.onSwapDimensions,
    this.onOpenMeasureGuide,
  });

  final double panelLengthCm;
  final double panelWidthCm;
  final int panelCount;
  final double panelSpacingCm;
  final VoidCallback? onSwapDimensions;
  final VoidCallback? onOpenMeasureGuide;

  double get totalTrackLengthCm {
    if (panelCount <= 0 || panelLengthCm <= 0) return 0;
    return (panelCount * panelLengthCm) +
        ((panelCount - 1) * math.max(0.0, panelSpacingCm));
  }

  @override
  Widget build(BuildContext context) {
    final validLength = panelLengthCm > 0 ? panelLengthCm : 100.0;
    final validWidth = panelWidthCm > 0 ? panelWidthCm : 100.0;
    final validCount = math.max(1, panelCount);
    final validSpacing = math.max(0.0, panelSpacingCm);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.architecture_rounded,
                    color: AppColors.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Live Array Blueprint',
                        style: AppTypography.h3.copyWith(fontSize: 15),
                      ),
                      Text(
                        'Track layout & dimensions',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onOpenMeasureGuide != null)
                  InkWell(
                    key: const Key('how_to_measure_guide_button'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: onOpenMeasureGuide,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.help_outline_rounded,
                            size: 15,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'How to Measure?',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),

          // Blueprint Drawing Canvas
          Container(
            height: 195,
            width: double.infinity,
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CustomPaint(
                painter: _ArrayBlueprintPainter(
                  panelLengthCm: validLength,
                  panelWidthCm: validWidth,
                  panelCount: validCount,
                  panelSpacingCm: validSpacing,
                ),
              ),
            ),
          ),

          // Footer calculation & swap controls
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.straighten_rounded,
                        size: 16,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Total Track Travel: ',
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              Text(
                                '${totalTrackLengthCm.toStringAsFixed(1)} cm',
                                style: AppTypography.bodySmall.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '$validCount panel(s) × ${validLength.toStringAsFixed(1)} cm + ${(validCount > 1 ? '${validCount - 1} × ${validSpacing.toStringAsFixed(1)} cm gap' : 'no gaps')}',
                            style: AppTypography.caption.copyWith(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onSwapDimensions != null)
                      OutlinedButton.icon(
                        key: const Key('swap_dimensions_button'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(
                          Icons.swap_horiz_rounded,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        label: Text(
                          'Swap L ⇋ W',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: onSwapDimensions,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Visual modal bottom sheet guide explaining the 3 measurements to users.
void showHowToMeasureModal(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (modalContext) {
      return Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
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
                      Icons.straighten_rounded,
                      size: 22,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'How to Measure Your Solar Array',
                        style: AppTypography.h3.copyWith(fontSize: 17),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppColors.textSecondary,
                      ),
                      onPressed: () => Navigator.of(modalContext).pop(),
                    ),
                  ],
                ),
                const Divider(height: 20, color: AppColors.border),
                _buildGuideStepCard(
                  number: '1',
                  title: 'Panel Length along Track (Travel Direction)',
                  description:
                      'Find the direction the robot moves along its track. Measure the side of the solar panel parallel to this rail. Whether mounted portrait or landscape, Length is ALWAYS the dimension along the robot track.',
                  icon: Icons.east_rounded,
                ),
                const SizedBox(height: 12),
                _buildGuideStepCard(
                  number: '2',
                  title: 'Panel Width across (Perpendicular)',
                  description:
                      'Measure the perpendicular side across the face of the solar panel, from edge to edge.',
                  icon: Icons.north_rounded,
                ),
                const SizedBox(height: 12),
                _buildGuideStepCard(
                  number: '3',
                  title: 'Gap Between Panels (Inter-Panel Spacing)',
                  description:
                      'Measure the empty gap between the aluminum frame of one panel and the next along the rail. The robot uses this to skip spraying water over gaps to prevent waste.',
                  icon: Icons.space_bar_rounded,
                ),
                const SizedBox(height: 20),
                PrimaryButton(
                  label: 'Got it, Thanks!',
                  onPressed: () => Navigator.of(modalContext).pop(),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Widget _buildGuideStepCard({
  required String number,
  required String title,
  required String description,
  required IconData icon,
}) {
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(8),
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: AppTypography.bodySmall.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Icon(icon, size: 16, color: AppColors.primary),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Custom technical blueprint painter rendering the schematic.
class _ArrayBlueprintPainter extends CustomPainter {
  const _ArrayBlueprintPainter({
    required this.panelLengthCm,
    required this.panelWidthCm,
    required this.panelCount,
    required this.panelSpacingCm,
  });

  final double panelLengthCm;
  final double panelWidthCm;
  final int panelCount;
  final double panelSpacingCm;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // Background subtle grid
    final gridPaint = Paint()
      ..color = AppColors.border.withValues(alpha: 0.35)
      ..strokeWidth = 0.8;
    for (double x = 0; x < size.width; x += 16) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += 16) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Drawing area margins with generous breathing room
    const leftMargin = 50.0;
    const rightMargin = 48.0;
    const topMargin = 52.0; // Anchors panels safely below the fixed top rail
    const bottomMargin = 32.0;

    final availableWidth = size.width - leftMargin - rightMargin;
    final availableHeight = size.height - topMargin - bottomMargin;

    // We render up to 2 panels to show the length, width, and gap clearly
    final panelsToDraw = math.min(panelCount, 2);
    final isPlural = panelCount > 2;

    // Aspect ratio representation (constrained for clear view)
    final ratio = (panelLengthCm / math.max(1.0, panelWidthCm)).clamp(0.5, 2.5);
    final targetPanelWidthPx = (availableWidth / (panelsToDraw + (isPlural ? 0.45 : 0.15))).clamp(30.0, 105.0);
    final targetPanelHeightPx = (targetPanelWidthPx / ratio).clamp(45.0, availableHeight);

    // Only give visual gap if there is actual spacing configured
    final hasGap = panelsToDraw > 1 && panelSpacingCm > 0;
    final panelGapPx = hasGap ? 20.0 : (panelsToDraw > 1 ? 2.0 : 0.0);
    final totalPanelsWidthPx = (panelsToDraw * targetPanelWidthPx) +
        ((panelsToDraw - 1) * panelGapPx);

    final startX = leftMargin + (availableWidth - totalPanelsWidthPx - (isPlural ? 36.0 : 0.0)) / 2;
    final startY = topMargin + (availableHeight - targetPanelHeightPx) / 2;

    // 1. Draw Top Rail & Robot Carriage - LOCKED AT THE TOP OF THE CARD
    const railY = 24.0;
    final railPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.45)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final railStartX = leftMargin - 16.0;
    final railEndX = size.width - rightMargin + 16.0;
    canvas.drawLine(Offset(railStartX, railY), Offset(railEndX, railY), railPaint);

    // Robot Icon representation
    final robotX = railStartX + 18.0;
    final robotPaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.fill;
    final robotRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(robotX, railY), width: 18, height: 12),
      const Radius.circular(3),
    );
    canvas.drawRRect(robotRect, robotPaint);

    // Direction arrow & label: positioned cleanly ABOVE the rail line (no strikethrough/collision)
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = const TextSpan(
      text: 'Robot Travel Direction ──▶',
      style: TextStyle(
        color: AppColors.primary,
        fontSize: 9.0,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
    );
    textPainter.layout();

    final labelX = robotX + 16.0;
    const labelY = 6.0;
    final labelBgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(labelX - 4, labelY - 1, textPainter.width + 8, textPainter.height + 2),
      const Radius.circular(3),
    );
    canvas.drawRRect(
      labelBgRect,
      Paint()..color = AppColors.surface.withValues(alpha: 0.92),
    );
    textPainter.paint(canvas, Offset(labelX, labelY));

    // 2. Draw Panels with solar cell texture
    final panelStroke = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final panelFill = Paint()
      ..color = AppColors.primarySoft.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    final cellLinePaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.15)
      ..strokeWidth = 0.8;

    for (int i = 0; i < panelsToDraw; i++) {
      final pX = startX + i * (targetPanelWidthPx + panelGapPx);
      final pRect = Rect.fromLTWH(pX, startY, targetPanelWidthPx, targetPanelHeightPx);

      // Fill and border
      canvas.drawRect(pRect, panelFill);
      canvas.drawRect(pRect, panelStroke);

      // Cell grid lines
      const cols = 3;
      const rows = 4;
      for (int c = 1; c < cols; c++) {
        final cx = pX + (pRect.width / cols) * c;
        canvas.drawLine(Offset(cx, pRect.top), Offset(cx, pRect.bottom), cellLinePaint);
      }
      for (int r = 1; r < rows; r++) {
        final ry = pRect.top + (pRect.height / rows) * r;
        canvas.drawLine(Offset(pRect.left, ry), Offset(pRect.right, ry), cellLinePaint);
      }

      // Panel label: "P1", "P2"
      final pLabel = TextSpan(
        text: 'P${i + 1}',
        style: TextStyle(
          color: AppColors.primary.withValues(alpha: 0.75),
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      );
      textPainter.text = pLabel;
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          pRect.center.dx - (textPainter.width / 2),
          pRect.center.dy - (textPainter.height / 2),
        ),
      );
    }

    // Stylish "+ (N - 2) more" badge if array has more panels
    if (isPlural) {
      final badgeX = startX + totalPanelsWidthPx + 6.0;
      final badgeY = startY + (targetPanelHeightPx / 2) - 10.0;
      final badgeRRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(badgeX, badgeY, 36, 20),
        const Radius.circular(6),
      );
      final badgeFill = Paint()
        ..color = AppColors.primarySoft.withValues(alpha: 0.85)
        ..style = PaintingStyle.fill;
      final badgeBorder = Paint()
        ..color = AppColors.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      canvas.drawRRect(badgeRRect, badgeFill);
      canvas.drawRRect(badgeRRect, badgeBorder);

      final moreText = TextSpan(
        text: '+${panelCount - 2}',
        style: TextStyle(
          color: AppColors.primary,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      );
      textPainter.text = moreText;
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          badgeX + (36 - textPainter.width) / 2,
          badgeY + (20 - textPainter.height) / 2,
        ),
      );
    }

    // 3. Dimension Cotas
    final dimPaint = Paint()
      ..color = AppColors.secondary
      ..strokeWidth = 1.2;

    // Dimension A: Length along Track (Horizontal below Panel 1)
    final p1X = startX;
    final cotaY = startY + targetPanelHeightPx + 10.0;

    canvas.drawLine(Offset(p1X, cotaY), Offset(p1X + targetPanelWidthPx, cotaY), dimPaint);
    canvas.drawLine(Offset(p1X, cotaY - 4), Offset(p1X, cotaY + 4), dimPaint);
    canvas.drawLine(
      Offset(p1X + targetPanelWidthPx, cotaY - 4),
      Offset(p1X + targetPanelWidthPx, cotaY + 4),
      dimPaint,
    );

    // Length text
    textPainter.text = TextSpan(
      text: 'Length: ${panelLengthCm.toStringAsFixed(1)} cm',
      style: const TextStyle(
        color: AppColors.secondary,
        fontSize: 9.5,
        fontWeight: FontWeight.w700,
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        p1X + (targetPanelWidthPx - textPainter.width) / 2,
        cotaY + 4,
      ),
    );

    // Dimension B: Width across Panel (Vertical to the left of Panel 1)
    final cotaX = startX - 16.0;
    canvas.drawLine(Offset(cotaX, startY), Offset(cotaX, startY + targetPanelHeightPx), dimPaint);
    canvas.drawLine(Offset(cotaX - 4, startY), Offset(cotaX + 4, startY), dimPaint);
    canvas.drawLine(
      Offset(cotaX - 4, startY + targetPanelHeightPx),
      Offset(cotaX + 4, startY + targetPanelHeightPx),
      dimPaint,
    );

    // Vertical text painted strictly to the LEFT of the line with no overlap
    textPainter.text = TextSpan(
      text: '${panelWidthCm.toStringAsFixed(1)} cm',
      style: const TextStyle(
        color: AppColors.secondary,
        fontSize: 9.5,
        fontWeight: FontWeight.w700,
      ),
    );
    textPainter.layout();
    canvas.save();
    // Rotate and position so the text does not touch cotaX
    canvas.translate(cotaX - textPainter.height - 4, startY + (targetPanelHeightPx + textPainter.width) / 2);
    canvas.rotate(-math.pi / 2);
    textPainter.paint(canvas, Offset.zero);
    canvas.restore();

    // Dimension C: Gap between Panels (rendered cleanly between panels only when gap > 0)
    if (hasGap) {
      final gapX1 = startX + targetPanelWidthPx;
      final gapX2 = gapX1 + panelGapPx;
      final gapY = startY - 8.0;

      final gapPaint = Paint()
        ..color = AppColors.warning
        ..strokeWidth = 1.0;

      canvas.drawLine(Offset(gapX1, gapY), Offset(gapX2, gapY), gapPaint);
      canvas.drawLine(Offset(gapX1, gapY - 3), Offset(gapX1, gapY + 3), gapPaint);
      canvas.drawLine(Offset(gapX2, gapY - 3), Offset(gapX2, gapY + 3), gapPaint);

      textPainter.text = TextSpan(
        text: '${panelSpacingCm.toStringAsFixed(1)} cm',
        style: const TextStyle(
          color: AppColors.warning,
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          gapX1 + (panelGapPx - textPainter.width) / 2,
          gapY - textPainter.height - 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ArrayBlueprintPainter oldDelegate) {
    return oldDelegate.panelLengthCm != panelLengthCm ||
        oldDelegate.panelWidthCm != panelWidthCm ||
        oldDelegate.panelCount != panelCount ||
        oldDelegate.panelSpacingCm != panelSpacingCm;
  }
}
