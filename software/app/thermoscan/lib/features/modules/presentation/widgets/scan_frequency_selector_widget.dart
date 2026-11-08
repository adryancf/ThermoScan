import 'package:flutter/material.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';

/// Modern semantic frequency selector for routine robotic inspections.
/// Replaces clunky raw integer inputs with friendly presets (Daily, Weekly, Bi-Weekly, Custom)
/// plus an intuitive stepper for custom days and human-readable schedule feedback.
class ScanFrequencySelectorWidget extends StatelessWidget {
  const ScanFrequencySelectorWidget({
    super.key,
    required this.selectedDays,
    required this.onChanged,
    this.readOnly = false,
  });

  final int selectedDays;
  final ValueChanged<int> onChanged;
  final bool readOnly;

  bool get _isCustom =>
      selectedDays != 1 && selectedDays != 7 && selectedDays != 15;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.schedule_rounded,
              size: 16,
              color: AppColors.primary,
            ),
            const SizedBox(width: 6),
            Text(
              'Inspection Schedule Frequency',
              style: AppTypography.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'How often the robot automatically runs a routine thermal scan',
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondary,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 10),

        // 4 Preset Cards in a Grid/Row
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
                _buildFrequencyOption(
                  key: const Key('frequency_option_daily'),
                  title: 'Daily',
                  subtitle: 'Every day',
                  days: 1,
                  isSelected: selectedDays == 1,
                ),
                _buildFrequencyOption(
                  key: const Key('frequency_option_weekly'),
                  title: 'Weekly',
                  subtitle: '7 days',
                  days: 7,
                  isRecommended: true,
                  isSelected: selectedDays == 7,
                ),
                _buildFrequencyOption(
                  key: const Key('frequency_option_biweekly'),
                  title: 'Bi-Weekly',
                  subtitle: '15 days',
                  days: 15,
                  isSelected: selectedDays == 15,
                ),
                _buildFrequencyOption(
                  key: const Key('frequency_option_custom'),
                  title: 'Custom',
                  subtitle: _isCustom ? '$selectedDays days' : 'Custom',
                  days: _isCustom ? selectedDays : (selectedDays == 7 ? 5 : 7),
                  isCustomOption: true,
                  isSelected: _isCustom,
                ),
              ],
            );
          },
        ),

        // Custom Days Stepper if Custom is active
        if (_isCustom) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.tune_rounded,
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Custom Interval: $selectedDays ${selectedDays == 1 ? 'day' : 'days'}',
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                if (!readOnly) ...[
                  IconButton(
                    key: const Key('custom_frequency_decrement'),
                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                    color: selectedDays > 1 ? AppColors.primary : AppColors.border,
                    splashRadius: 18,
                    onPressed: selectedDays > 1
                        ? () => onChanged(selectedDays - 1)
                        : null,
                  ),
                  Text(
                    '$selectedDays',
                    style: AppTypography.bodySmall.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  IconButton(
                    key: const Key('custom_frequency_increment'),
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                    color: AppColors.primary,
                    splashRadius: 18,
                    onPressed: () => onChanged(selectedDays + 1),
                  ),
                ],
              ],
            ),
          ),
        ],

        // Contextual Schedule Summary
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
                Icons.check_circle_outline_rounded,
                size: 14,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  selectedDays == 1
                      ? 'The robot will inspect panels daily during safe sun hours.'
                      : 'The robot will automatically scan panels every $selectedDays days.',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFrequencyOption({
    required Key key,
    required String title,
    required String subtitle,
    required int days,
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
                // Default custom to 5 days if currently on a preset
                if (!_isCustom) {
                  onChanged(5);
                }
              } else {
                onChanged(days);
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
            color: isSelected ? AppColors.primary : AppColors.border,
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
                      color: isSelected ? AppColors.primary : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTypography.caption.copyWith(
                      fontSize: 10,
                      color: isSelected ? AppColors.primary : AppColors.textSecondary,
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
