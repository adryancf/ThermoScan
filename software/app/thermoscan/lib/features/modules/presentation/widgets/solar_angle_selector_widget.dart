import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/core/widgets/app_buttons.dart';
import 'package:thermoscan/core/widgets/app_text_field.dart';

/// Compact and interactive Sun Height Elevation Selector Widget.
/// Features a single-row compact layout, location-based recommendation (★),
/// persistent Custom stepper mode, contextual guide modal, and a hybrid Cupertino Wheel + Direct Typing modal.
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
    _isCustomMode = (widget.selectedAngle - 10.0).abs() >= 0.1 &&
        (widget.selectedAngle - 15.0).abs() >= 0.1 &&
        (widget.selectedAngle - 20.0).abs() >= 0.1;
  }

  void _openCustomWheelModal({double? overrideAngle}) {
    if (widget.readOnly) return;
    showCustomSolarAnglePickerModal(
      context: context,
      initialAngle: overrideAngle ?? widget.selectedAngle,
      onApplied: (newAngle) {
        setState(() => _isCustomMode = true);
        widget.onChanged(newAngle);
      },
    );
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
                subtitle: _isCustomMode
                    ? '${widget.selectedAngle.toStringAsFixed(0)}° ✎'
                    : 'Manual',
                isSelected: _isCustomMode,
                onTap: () {
                  double targetAngle = widget.selectedAngle;
                  if (!_isCustomMode) {
                    setState(() => _isCustomMode = true);
                    if ((widget.selectedAngle - 10.0).abs() < 0.1 ||
                        (widget.selectedAngle - 15.0).abs() < 0.1 ||
                        (widget.selectedAngle - 20.0).abs() < 0.1) {
                      targetAngle = 12.0;
                      widget.onChanged(12.0);
                    }
                  }
                  _openCustomWheelModal(overrideAngle: targetAngle);
                },
              ),
            ),
          ],
        ),

        // Persistent Custom Stepper with Edit Button if Custom is active
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
                  child: GestureDetector(
                    onTap: _openCustomWheelModal,
                    child: Text(
                      'Custom Sun Angle: ${widget.selectedAngle.toStringAsFixed(1)}°',
                      style: AppTypography.caption.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        fontSize: 11,
                      ),
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
                  IconButton(
                    key: const Key('custom_sun_angle_wheel_picker_button'),
                    icon: const Icon(Icons.tune_outlined, size: 17),
                    color: AppColors.secondary,
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
                  _getContextualHelp(widget.selectedAngle),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 10.5,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Optional source indicator
        if (widget.sourceDescription != null &&
            widget.sourceDescription!.isNotEmpty) ...[
          const SizedBox(height: 3),
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text(
              'Source: ${widget.sourceDescription}',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _getContextualHelp(double angle) {
    if ((angle - 10.0).abs() < 0.1) {
      return 'Scans run from early morning to late afternoon. Ideal for flat roofs with zero tree shadows.';
    } else if ((angle - 15.0).abs() < 0.1) {
      return 'Balanced daylight window (~8:30 AM – 4:30 PM). Ensures strong solar power for reliable hotspot detection.';
    } else if ((angle - 20.0).abs() < 0.1) {
      return 'Avoids morning shadows and low irradiation. Restricts robot scanning to peak high-sun midday hours.';
    } else {
      return 'Custom threshold: robot will only trigger inspection runs when sun elevation exceeds ${angle.toStringAsFixed(1)}°.';
    }
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
              ? AppColors.primarySoft.withValues(alpha: 0.6)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.secondary : AppColors.border,
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
                      color: isSelected ? AppColors.secondary : AppColors.textPrimary,
                      fontSize: 12,
                    ),
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

/// Modal Bottom Sheet featuring a hybrid Cupertino Picker Wheel and Direct Numeric Keyboard Input for angles.
void showCustomSolarAnglePickerModal({
  required BuildContext context,
  required double initialAngle,
  required ValueChanged<double> onApplied,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (modalContext) => _CustomSolarAnglePickerModal(
      initialAngle: initialAngle,
      onApplied: onApplied,
    ),
  );
}

class _CustomSolarAnglePickerModal extends StatefulWidget {
  const _CustomSolarAnglePickerModal({
    required this.initialAngle,
    required this.onApplied,
  });

  final double initialAngle;
  final ValueChanged<double> onApplied;

  @override
  State<_CustomSolarAnglePickerModal> createState() =>
      _CustomSolarAnglePickerModalState();
}

class _CustomSolarAnglePickerModalState
    extends State<_CustomSolarAnglePickerModal> {
  static const int minAngle = 5;
  static const int maxAngle = 85;

  late double _currentAngle;
  late TextEditingController _textCtrl;
  late FixedExtentScrollController _wheelCtrl;
  bool _isProgrammaticScroll = false;

  @override
  void initState() {
    super.initState();
    _currentAngle = widget.initialAngle.clamp(minAngle.toDouble(), maxAngle.toDouble());
    _textCtrl = TextEditingController(text: _currentAngle.toStringAsFixed(1));
    _wheelCtrl = FixedExtentScrollController(
      initialItem: (_currentAngle.round() - minAngle).clamp(0, maxAngle - minAngle),
    );
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _wheelCtrl.dispose();
    super.dispose();
  }

  void _onWheelChanged(int index) {
    if (_isProgrammaticScroll) return;
    final angle = (minAngle + index).toDouble();
    setState(() {
      _currentAngle = angle;
      _textCtrl.text = angle.toStringAsFixed(1);
    });
  }

  void _onTextTyped(String text) {
    final parsed = double.tryParse(text.trim());
    if (parsed == null) return;
    final clamped = parsed.clamp(minAngle.toDouble(), maxAngle.toDouble());
    setState(() {
      _currentAngle = clamped;
    });

    final targetIndex = (clamped.round() - minAngle).clamp(0, maxAngle - minAngle);
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
                      Icons.wb_sunny_rounded,
                      size: 18,
                      color: AppColors.secondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Custom Minimum Sun Height',
                      style: AppTypography.h3.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                TextButton(
                  key: const Key('custom_sun_angle_done_header_button'),
                  onPressed: () {
                    widget.onApplied(_currentAngle);
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

            // Direct Typing Input with live Degrees label
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    key: const Key('custom_sun_angle_text_field'),
                    label: 'Elevation (Degrees, 5°–85°)',
                    hintText: 'e.g. 17.5',
                    controller: _textCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                      '${_currentAngle.toStringAsFixed(1)}°',
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
                childCount: maxAngle - minAngle + 1,
                itemBuilder: (context, index) {
                  final angle = minAngle + index;
                  final isSelected = angle == _currentAngle.round();
                  return Center(
                    child: Text(
                      '$angle° Sun Elevation',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? AppColors.secondary : AppColors.textSecondary,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // Primary Action Button
            PrimaryButton(
              key: const Key('custom_sun_angle_apply_button'),
              label: 'Apply Sun Height (${_currentAngle.toStringAsFixed(1)}°)',
              onPressed: () {
                widget.onApplied(_currentAngle);
                Navigator.of(context).pop();
              },
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
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.wb_sunny_rounded,
                      color: AppColors.secondary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Why Sun Height Matters',
                          style: AppTypography.h3.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'IEC 62446-3 Thermographic Standards',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
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
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
