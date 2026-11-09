import 'package:flutter/material.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/core/widgets/app_buttons.dart';

/// Compact and interactive Sun Height Elevation Selector Widget.
/// Features a single-row compact layout, location-based recommendation (★),
/// persistent Custom stepper mode (prevents getting stuck on preset values),
/// and a contextual guide modal.
class SolarAngleSelectorWidget extends StatefulWidget {
  const SolarAngleSelectorWidget({
    super.key,
    required this.selectedAngle,
    required this.onChanged,
    this.recommendedAngle = 15.0,
    this.sourceDescription,
    this.readOnly = false,
  });

  final double selectedAngle;
  final ValueChanged<double> onChanged;
  final double recommendedAngle;
  final String? sourceDescription;
  final bool readOnly;

  @override
  State<SolarAngleSelectorWidget> createState() =>
      _SolarAngleSelectorWidgetState();
}

class _SolarAngleSelectorWidgetState extends State<SolarAngleSelectorWidget> {
  late bool _isCustomMode;

  @override
  void initState() {
    super.initState();
    _isCustomMode = widget.selectedAngle != 10.0 &&
        widget.selectedAngle != 15.0 &&
        widget.selectedAngle != 20.0;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with Info Button
        Row(
          children: [
            const Icon(
              Icons.wb_sunny_rounded,
              size: 16,
              color: AppColors.secondary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Minimum Sun Height',
                style: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            InkWell(
              key: const Key('sun_height_guide_button'),
              borderRadius: BorderRadius.circular(6),
              onTap: () => showSunHeightGuideModal(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.help_outline_rounded,
                      size: 12,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Why Sun Height?',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'Lowest sun elevation required for the robot to run an inspection scan',
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondary,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 8),

        // Compact Single Row of 4 Option Chips
        Row(
          children: [
            Expanded(
              child: _buildCompactOption(
                key: const Key('sun_angle_option_10'),
                title: '10°',
                subtitle: 'Wide',
                angle: 10.0,
                isRecommended: (widget.recommendedAngle - 10.0).abs() < 1.0,
                isSelected: !_isCustomMode && (widget.selectedAngle - 10.0).abs() < 0.1,
                onTap: () {
                  setState(() => _isCustomMode = false);
                  widget.onChanged(10.0);
                },
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildCompactOption(
                key: const Key('sun_angle_option_15'),
                title: '15°',
                subtitle: 'Standard',
                angle: 15.0,
                isRecommended: (widget.recommendedAngle - 15.0).abs() < 1.0,
                isSelected: !_isCustomMode && (widget.selectedAngle - 15.0).abs() < 0.1,
                onTap: () {
                  setState(() => _isCustomMode = false);
                  widget.onChanged(15.0);
                },
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildCompactOption(
                key: const Key('sun_angle_option_20'),
                title: '20°',
                subtitle: 'High Sun',
                angle: 20.0,
                isRecommended: (widget.recommendedAngle - 20.0).abs() < 1.0,
                isSelected: !_isCustomMode && (widget.selectedAngle - 20.0).abs() < 0.1,
                onTap: () {
                  setState(() => _isCustomMode = false);
                  widget.onChanged(20.0);
                },
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildCompactOption(
                key: const Key('sun_angle_option_custom'),
                title: 'Custom',
                subtitle: _isCustomMode ? '${widget.selectedAngle.toStringAsFixed(0)}°' : 'Manual',
                angle: widget.selectedAngle,
                isRecommended: false,
                isSelected: _isCustomMode,
                onTap: () {
                  setState(() => _isCustomMode = true);
                  if ((widget.selectedAngle - 10.0).abs() < 0.1 ||
                      (widget.selectedAngle - 15.0).abs() < 0.1 ||
                      (widget.selectedAngle - 20.0).abs() < 0.1) {
                    widget.onChanged(12.0);
                  }
                },
              ),
            ),
          ],
        ),

        // Persistent Custom Stepper when Custom is active
        if (_isCustomMode) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.secondary.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.tune_rounded,
                  size: 15,
                  color: AppColors.secondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Custom Sun Angle: ${widget.selectedAngle.toStringAsFixed(1)}°',
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      fontSize: 11,
                    ),
                  ),
                ),
                if (!widget.readOnly) ...[
                  IconButton(
                    key: const Key('custom_sun_angle_decrement'),
                    icon: const Icon(Icons.remove_circle_outline, size: 18),
                    color: widget.selectedAngle > 5.0 ? AppColors.secondary : AppColors.border,
                    splashRadius: 16,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: widget.selectedAngle > 5.0
                        ? () => widget.onChanged(widget.selectedAngle - 1.0)
                        : null,
                  ),
                  Text(
                    '${widget.selectedAngle.toStringAsFixed(0)}°',
                    style: AppTypography.bodySmall.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  IconButton(
                    key: const Key('custom_sun_angle_increment'),
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    color: widget.selectedAngle < 85.0 ? AppColors.secondary : AppColors.border,
                    splashRadius: 16,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: widget.selectedAngle < 85.0
                        ? () => widget.onChanged(widget.selectedAngle + 1.0)
                        : null,
                  ),
                ],
              ],
            ),
          ),
        ],

        // Contextual Explanation Banner
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.primarySoft.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.wb_sunny_outlined,
                size: 13,
                color: AppColors.secondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _getContextualExplanation(widget.selectedAngle),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                    fontSize: 10.5,
                  ),
                ),
              ),
            ],
          ),
        ),

        if (widget.sourceDescription != null && widget.sourceDescription!.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            'Source: ${widget.sourceDescription}',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
              fontSize: 10,
            ),
          ),
        ],
      ],
    );
  }

  String _getContextualExplanation(double angle) {
    if (angle <= 10.0) {
      return 'Scans run from early morning to late afternoon. Ideal for flat roofs with zero tree shadows.';
    } else if (angle <= 15.0) {
      return 'Balanced daylight window (~8:30 AM – 4:30 PM). Ensures strong solar power for reliable hotspot detection.';
    } else if (angle <= 20.0) {
      return 'Scans run only when the sun is higher in the sky. Avoids morning shadows from nearby trees or walls.';
    } else {
      return 'Scans run when the sun is at least ${angle.toStringAsFixed(1)}° above the horizon.';
    }
  }

  Widget _buildCompactOption({
    required Key key,
    required String title,
    required String subtitle,
    required double angle,
    required bool isSelected,
    required bool isRecommended,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(8),
      onTap: widget.readOnly ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primarySoft.withValues(alpha: 0.6)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.secondary : AppColors.border,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTypography.caption.copyWith(
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    color: AppColors.textPrimary,
                    fontSize: 11.5,
                  ),
                ),
                if (isRecommended) ...[
                  const SizedBox(width: 2),
                  const Text(
                    '★',
                    style: TextStyle(
                      color: AppColors.secondary,
                      fontSize: 8.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 1),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption.copyWith(
                fontSize: 9.5,
                color: isSelected ? AppColors.secondary : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Modal Bottom Sheet Guide explaining why Sun Height is critical for PV thermography.
void showSunHeightGuideModal(BuildContext context) {
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
                      Icons.wb_sunny_rounded,
                      size: 22,
                      color: AppColors.secondary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Why Sun Height Matters',
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
                _buildGuideCard(
                  number: '1',
                  title: 'Panels Must Be Generating Power',
                  description:
                      'A defective solar cell only heats up (+10°C above baseline) when the panel is actively producing electricity under strong, direct sunlight. If scans ran at dawn, anomalies would stay cold and invisible.',
                  icon: Icons.electric_bolt_rounded,
                ),
                const SizedBox(height: 12),
                _buildGuideCard(
                  number: '2',
                  title: 'Eliminating Low-Angle Shadows & Glare',
                  description:
                      'When the sun is low on the horizon (< 10°), trees and neighboring buildings cast long shadows, and specular sun reflections on the glass panel face can cause false thermal alarms.',
                  icon: Icons.wb_twilight_rounded,
                ),
                const SizedBox(height: 12),
                _buildGuideCard(
                  number: '3',
                  title: 'Location-Based Recommendation',
                  description:
                      'The system automatically estimates the best minimum sun angle for your latitude. Higher latitudes experience lower winter sun, so 15°–20° is recommended to avoid shadows.',
                  icon: Icons.verified_outlined,
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

Widget _buildGuideCard({
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
                  Icon(icon, size: 16, color: AppColors.secondary),
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
