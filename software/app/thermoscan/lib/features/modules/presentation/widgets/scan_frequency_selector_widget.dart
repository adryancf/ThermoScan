import 'package:flutter/material.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';

/// Compact semantic frequency selector for routine robotic inspections.
/// Features a single-row compact layout, location/industry recommendation (★),
/// persistent Custom stepper mode (prevents getting stuck on preset values),
/// and human-readable schedule feedback.
class ScanFrequencySelectorWidget extends StatefulWidget {
  const ScanFrequencySelectorWidget({
    super.key,
    required this.selectedDays,
    required this.onChanged,
    this.readOnly = false,
  });

  final int selectedDays;
  final ValueChanged<int> onChanged;
  final bool readOnly;

  @override
  State<ScanFrequencySelectorWidget> createState() =>
      _ScanFrequencySelectorWidgetState();
}

class _ScanFrequencySelectorWidgetState
    extends State<ScanFrequencySelectorWidget> {
  late bool _isCustomMode;

  @override
  void initState() {
    super.initState();
    _isCustomMode = widget.selectedDays != 1 &&
        widget.selectedDays != 7 &&
        widget.selectedDays != 15;
  }

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
        const SizedBox(height: 8),

        // Compact Single Row of 4 Option Chips
        Row(
          children: [
            Expanded(
              child: _buildCompactOption(
                key: const Key('frequency_option_daily'),
                title: 'Daily',
                subtitle: 'Every day',
                days: 1,
                isSelected: !_isCustomMode && widget.selectedDays == 1,
                onTap: () {
                  setState(() => _isCustomMode = false);
                  widget.onChanged(1);
                },
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildCompactOption(
                key: const Key('frequency_option_weekly'),
                title: 'Weekly',
                subtitle: '7 days',
                days: 7,
                isRecommended: true,
                isSelected: !_isCustomMode && widget.selectedDays == 7,
                onTap: () {
                  setState(() => _isCustomMode = false);
                  widget.onChanged(7);
                },
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildCompactOption(
                key: const Key('frequency_option_biweekly'),
                title: 'Bi-Weekly',
                subtitle: '15 days',
                days: 15,
                isSelected: !_isCustomMode && widget.selectedDays == 15,
                onTap: () {
                  setState(() => _isCustomMode = false);
                  widget.onChanged(15);
                },
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildCompactOption(
                key: const Key('frequency_option_custom'),
                title: 'Custom',
                subtitle: _isCustomMode ? '${widget.selectedDays}d' : 'Custom',
                days: widget.selectedDays,
                isSelected: _isCustomMode,
                onTap: () {
                  setState(() => _isCustomMode = true);
                  if (widget.selectedDays == 1 ||
                      widget.selectedDays == 7 ||
                      widget.selectedDays == 15) {
                    widget.onChanged(5);
                  }
                },
              ),
            ),
          ],
        ),

        // Persistent Custom Days Stepper if Custom is active
        if (_isCustomMode) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.tune_rounded,
                  size: 15,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Custom Interval: ${widget.selectedDays} ${widget.selectedDays == 1 ? 'day' : 'days'}',
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                      fontSize: 11,
                    ),
                  ),
                ),
                if (!widget.readOnly) ...[
                  IconButton(
                    key: const Key('custom_frequency_decrement'),
                    icon: const Icon(Icons.remove_circle_outline, size: 18),
                    color: widget.selectedDays > 1 ? AppColors.primary : AppColors.border,
                    splashRadius: 16,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: widget.selectedDays > 1
                        ? () => widget.onChanged(widget.selectedDays - 1)
                        : null,
                  ),
                  Text(
                    '${widget.selectedDays}',
                    style: AppTypography.bodySmall.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  IconButton(
                    key: const Key('custom_frequency_increment'),
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    color: AppColors.primary,
                    splashRadius: 16,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: () => widget.onChanged(widget.selectedDays + 1),
                  ),
                ],
              ],
            ),
          ),
        ],

        // Contextual Schedule Summary
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
                Icons.check_circle_outline_rounded,
                size: 13,
                color: AppColors.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.selectedDays == 1
                      ? 'The robot will inspect panels daily during safe sun hours.'
                      : 'The robot will automatically scan panels every ${widget.selectedDays} days.',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 10.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompactOption({
    required Key key,
    required String title,
    required String subtitle,
    required int days,
    required bool isSelected,
    required VoidCallback onTap,
    bool isRecommended = false,
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
              ? AppColors.primarySoft.withValues(alpha: 0.5)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: AppTypography.caption.copyWith(
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                      color: isSelected ? AppColors.primary : AppColors.textPrimary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: AppTypography.caption.copyWith(
                      fontSize: 9.5,
                      color: isSelected ? AppColors.primary : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (isRecommended)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
                  decoration: BoxDecoration(
                    color: AppColors.secondary,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text(
                    '★',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 7.5,
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
