import 'package:flutter/material.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/core/widgets/app_buttons.dart';

/// Interactive Sun Height Elevation Selector Widget.
/// Replaces raw numeric text inputs with contextual presets (10° Wide Window, 15° Standard, 20° High Sun, Custom)
/// plus a contextual explanation banner and a modal guide explaining why sun height matters.
class SolarAngleSelectorWidget extends StatelessWidget {
  const SolarAngleSelectorWidget({
    super.key,
    required this.selectedAngle,
    required this.onChanged,
    this.sourceDescription,
    this.readOnly = false,
  });

  final double selectedAngle;
  final ValueChanged<double> onChanged;
  final String? sourceDescription;
  final bool readOnly;

  bool get _isCustom =>
      selectedAngle != 10.0 && selectedAngle != 15.0 && selectedAngle != 20.0;

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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                      size: 13,
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
        const SizedBox(height: 10),

        // 4 Option Cards in a responsive layout
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 360;
            return GridView.count(
              crossAxisCount: isNarrow ? 2 : 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: isNarrow ? 2.1 : 1.25,
              children: [
                _buildOptionCard(
                  key: const Key('sun_angle_option_10'),
                  title: '10°',
                  subtitle: 'Wide Window',
                  angle: 10.0,
                  isSelected: selectedAngle == 10.0,
                ),
                _buildOptionCard(
                  key: const Key('sun_angle_option_15'),
                  title: '15°',
                  subtitle: 'Standard',
                  angle: 15.0,
                  isRecommended: true,
                  isSelected: selectedAngle == 15.0,
                ),
                _buildOptionCard(
                  key: const Key('sun_angle_option_20'),
                  title: '20°',
                  subtitle: 'High Sun',
                  angle: 20.0,
                  isSelected: selectedAngle == 20.0,
                ),
                _buildOptionCard(
                  key: const Key('sun_angle_option_custom'),
                  title: 'Custom',
                  subtitle: _isCustom ? '${selectedAngle.toStringAsFixed(1)}°' : 'Manual',
                  angle: _isCustom ? selectedAngle : 12.0,
                  isCustomOption: true,
                  isSelected: _isCustom,
                ),
              ],
            );
          },
        ),

        // Custom Stepper if Custom is active
        if (_isCustom) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.secondary.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.tune_rounded,
                  size: 16,
                  color: AppColors.secondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Custom Sun Angle: ${selectedAngle.toStringAsFixed(1)}°',
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (!readOnly) ...[
                  IconButton(
                    key: const Key('custom_sun_angle_decrement'),
                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                    color: selectedAngle > 5.0 ? AppColors.secondary : AppColors.border,
                    splashRadius: 18,
                    onPressed: selectedAngle > 5.0
                        ? () => onChanged(selectedAngle - 1.0)
                        : null,
                  ),
                  Text(
                    '${selectedAngle.toStringAsFixed(0)}°',
                    style: AppTypography.bodySmall.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  IconButton(
                    key: const Key('custom_sun_angle_increment'),
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                    color: selectedAngle < 85.0 ? AppColors.secondary : AppColors.border,
                    splashRadius: 18,
                    onPressed: selectedAngle < 85.0
                        ? () => onChanged(selectedAngle + 1.0)
                        : null,
                  ),
                ],
              ],
            ),
          ),
        ],

        // Contextual Explanation Banner
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.primarySoft.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.wb_sunny_outlined,
                size: 14,
                color: AppColors.secondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _getContextualExplanation(selectedAngle),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),

        if (sourceDescription != null && sourceDescription!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Source: $sourceDescription',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
              fontSize: 10.5,
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
      return 'Scans only run when the sun is at least ${angle.toStringAsFixed(1)}° above the horizon.';
    }
  }

  Widget _buildOptionCard({
    required Key key,
    required String title,
    required String subtitle,
    required double angle,
    required bool isSelected,
    bool isRecommended = false,
    bool isCustomOption = false,
  }) {
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(10),
      onTap: readOnly
          ? null
          : () {
              if (isCustomOption) {
                if (!_isCustom) {
                  onChanged(12.0);
                }
              } else {
                onChanged(angle);
              }
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primarySoft.withValues(alpha: 0.5)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppColors.secondary : AppColors.border,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Stack(
          children: [
            Align(
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: AppTypography.caption.copyWith(
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                      color: isSelected ? AppColors.textPrimary : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTypography.caption.copyWith(
                      fontSize: 10,
                      color: isSelected ? AppColors.secondary : AppColors.textSecondary,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            if (isRecommended)
              Align(
                alignment: Alignment.topRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.secondary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '★',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
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
                  title: '15° Is the Recommended Standard',
                  description:
                      '15° corresponds to about 1 to 1.5 hours after sunrise until 1.5 hours before sunset. This ensures irradiance above 600 W/m² (the standard requirement for PV thermography under IEC 62446-3).',
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
