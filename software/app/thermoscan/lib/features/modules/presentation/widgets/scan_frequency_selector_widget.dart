import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/core/widgets/app_buttons.dart';
import 'package:thermoscan/core/widgets/app_text_field.dart';

/// Compact semantic frequency selector for routine robotic inspections.
/// Features a single-row compact layout, location/industry recommendation (★),
/// persistent Custom stepper mode, and a hybrid Cupertino Wheel + Direct Typing modal.
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

  void _openCustomWheelModal({int? overrideDays}) {
    if (widget.readOnly) return;
    showCustomFrequencyPickerModal(
      context: context,
      initialDays: overrideDays ?? widget.selectedDays,
      onApplied: (days) {
        setState(() => _isCustomMode = true);
        widget.onChanged(days);
      },
    );
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
                subtitle: _isCustomMode ? '${widget.selectedDays}d ✎' : 'Custom',
                isSelected: _isCustomMode,
                onTap: () {
                  int targetDays = widget.selectedDays;
                  if (!_isCustomMode) {
                    setState(() => _isCustomMode = true);
                    if (widget.selectedDays == 1 ||
                        widget.selectedDays == 7 ||
                        widget.selectedDays == 15) {
                      targetDays = 5;
                      widget.onChanged(5);
                    }
                  }
                  _openCustomWheelModal(overrideDays: targetDays);
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
                  child: GestureDetector(
                    onTap: _openCustomWheelModal,
                    child: Text(
                      'Custom Interval: ${widget.selectedDays} ${widget.selectedDays == 1 ? 'day' : 'days'}',
                      style: AppTypography.caption.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                        fontSize: 11,
                      ),
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
                  IconButton(
                    key: const Key('custom_frequency_wheel_picker_button'),
                    icon: const Icon(Icons.tune_outlined, size: 17),
                    color: AppColors.primary,
                    splashRadius: 16,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    tooltip: 'Open Wheel Picker',
                    onPressed: _openCustomWheelModal,
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

/// Modal Bottom Sheet featuring a hybrid Cupertino Picker Wheel and Direct Numeric Keyboard Input for days.
void showCustomFrequencyPickerModal({
  required BuildContext context,
  required int initialDays,
  required ValueChanged<int> onApplied,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (modalContext) => _CustomFrequencyPickerModal(
      initialDays: initialDays,
      onApplied: onApplied,
    ),
  );
}

class _CustomFrequencyPickerModal extends StatefulWidget {
  const _CustomFrequencyPickerModal({
    required this.initialDays,
    required this.onApplied,
  });

  final int initialDays;
  final ValueChanged<int> onApplied;

  @override
  State<_CustomFrequencyPickerModal> createState() =>
      _CustomFrequencyPickerModalState();
}

class _CustomFrequencyPickerModalState
    extends State<_CustomFrequencyPickerModal> {
  static const int minDays = 1;
  static const int maxDays = 90;

  late int _currentDays;
  late TextEditingController _textCtrl;
  late FixedExtentScrollController _wheelCtrl;
  bool _isProgrammaticScroll = false;

  @override
  void initState() {
    super.initState();
    _currentDays = widget.initialDays.clamp(minDays, maxDays);
    _textCtrl = TextEditingController(text: '$_currentDays');
    _wheelCtrl = FixedExtentScrollController(initialItem: _currentDays - minDays);
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _wheelCtrl.dispose();
    super.dispose();
  }

  void _onWheelChanged(int index) {
    if (_isProgrammaticScroll) return;
    final days = minDays + index;
    setState(() {
      _currentDays = days;
      _textCtrl.text = '$days';
    });
  }

  void _onTextTyped(String text) {
    final parsed = int.tryParse(text.trim());
    if (parsed == null) return;
    final clamped = parsed.clamp(minDays, maxDays);
    setState(() {
      _currentDays = clamped;
    });

    final targetIndex = clamped - minDays;
    if (_wheelCtrl.hasClients && _wheelCtrl.selectedItem != targetIndex) {
      _isProgrammaticScroll = true;
      _wheelCtrl.animateToItem(
        targetIndex,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      ).then((_) {
        _isProgrammaticScroll = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.schedule_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Custom Inspection Interval',
                      style: AppTypography.h3.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                TextButton(
                  key: const Key('custom_frequency_done_header_button'),
                  onPressed: () {
                    widget.onApplied(_currentDays);
                    Navigator.of(context).pop();
                  },
                  child: Text(
                    'Done',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Direct Typing Input with live Days label
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    key: const Key('custom_frequency_text_field'),
                    label: 'Interval (Days, 1–90)',
                    hintText: 'e.g. 14',
                    controller: _textCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: _onTextTyped,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  margin: const EdgeInsets.only(top: 22),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '$_currentDays ${_currentDays == 1 ? 'day' : 'days'}',
                      style: AppTypography.bodySmall.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Cupertino Picker Wheel
            Container(
              height: 150,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: CupertinoPicker.builder(
                scrollController: _wheelCtrl,
                itemExtent: 38,
                onSelectedItemChanged: _onWheelChanged,
                childCount: maxDays - minDays + 1,
                itemBuilder: (context, index) {
                  final days = minDays + index;
                  final isSelected = days == _currentDays;
                  return Center(
                    child: Text(
                      '$days ${days == 1 ? 'day' : 'days'}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? AppColors.primary : AppColors.textSecondary,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // Primary Action Button
            PrimaryButton(
              key: const Key('custom_frequency_apply_button'),
              label: 'Apply Interval ($_currentDays ${_currentDays == 1 ? 'day' : 'days'})',
              onPressed: () {
                widget.onApplied(_currentDays);
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}
