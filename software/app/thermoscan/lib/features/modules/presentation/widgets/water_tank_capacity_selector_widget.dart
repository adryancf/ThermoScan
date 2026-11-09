import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/core/widgets/app_buttons.dart';
import 'package:thermoscan/core/widgets/app_text_field.dart';

/// Compact and semantic Water Tank Capacity selector widget.
/// Features a single-row 4-chip layout (1.0 L, 1.5 L, 2.0 L ★, Custom),
/// persistent Custom stepper mode, and a hybrid Cupertino Wheel + Direct Typing modal.
class WaterTankCapacitySelectorWidget extends StatefulWidget {
  const WaterTankCapacitySelectorWidget({
    super.key,
    required this.selectedCapacityMl,
    required this.onChanged,
    this.readOnly = false,
  });

  final int selectedCapacityMl;
  final ValueChanged<int> onChanged;
  final bool readOnly;

  @override
  State<WaterTankCapacitySelectorWidget> createState() =>
      _WaterTankCapacitySelectorWidgetState();
}

class _WaterTankCapacitySelectorWidgetState
    extends State<WaterTankCapacitySelectorWidget> {
  late bool _isCustomMode;

  @override
  void initState() {
    super.initState();
    _isCustomMode = widget.selectedCapacityMl != 1000 &&
        widget.selectedCapacityMl != 1500 &&
        widget.selectedCapacityMl != 2000;
  }

  void _openCustomWheelModal({int? overrideCapacityMl}) {
    if (widget.readOnly) return;
    showCustomWaterTankPickerModal(
      context: context,
      initialCapacityMl: overrideCapacityMl ?? widget.selectedCapacityMl,
      onApplied: (newMl) {
        setState(() => _isCustomMode = true);
        widget.onChanged(newMl);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final liters = (widget.selectedCapacityMl / 1000.0).toStringAsFixed(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.water_drop_outlined,
              size: 16,
              color: AppColors.primary,
            ),
            const SizedBox(width: 6),
            Text(
              'Water Tank Capacity',
              style: AppTypography.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'Robot onboard reservoir volume for automated panel washing',
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
                key: const Key('water_tank_option_1000'),
                title: '1.0 L',
                subtitle: '1,000 mL',
                isSelected: !_isCustomMode && widget.selectedCapacityMl == 1000,
                onTap: () {
                  setState(() => _isCustomMode = false);
                  widget.onChanged(1000);
                },
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildCompactOption(
                key: const Key('water_tank_option_1500'),
                title: '1.5 L',
                subtitle: '1,500 mL',
                isSelected: !_isCustomMode && widget.selectedCapacityMl == 1500,
                onTap: () {
                  setState(() => _isCustomMode = false);
                  widget.onChanged(1500);
                },
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildCompactOption(
                key: const Key('water_tank_option_2000'),
                title: '2.0 L',
                subtitle: 'Standard',
                isRecommended: true,
                isSelected: !_isCustomMode && widget.selectedCapacityMl == 2000,
                onTap: () {
                  setState(() => _isCustomMode = false);
                  widget.onChanged(2000);
                },
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildCompactOption(
                key: const Key('water_tank_option_custom'),
                title: 'Custom',
                subtitle: _isCustomMode ? '${liters}L ✎' : 'Custom',
                isSelected: _isCustomMode,
                onTap: () {
                  int targetMl = widget.selectedCapacityMl;
                  if (!_isCustomMode) {
                    setState(() => _isCustomMode = true);
                    if (widget.selectedCapacityMl == 1000 ||
                        widget.selectedCapacityMl == 1500 ||
                        widget.selectedCapacityMl == 2000) {
                      targetMl = 2500;
                      widget.onChanged(2500);
                    }
                  }
                  _openCustomWheelModal(overrideCapacityMl: targetMl);
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
                      'Volume: ${widget.selectedCapacityMl} mL ($liters L)',
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
                    key: const Key('custom_water_tank_decrement'),
                    icon: const Icon(Icons.remove_circle_outline, size: 18),
                    color: widget.selectedCapacityMl > 500
                        ? AppColors.primary
                        : AppColors.border,
                    splashRadius: 16,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: widget.selectedCapacityMl > 500
                        ? () => widget.onChanged(widget.selectedCapacityMl - 100)
                        : null,
                  ),
                  Text(
                    '${widget.selectedCapacityMl}',
                    style: AppTypography.bodySmall.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  IconButton(
                    key: const Key('custom_water_tank_increment'),
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    color: widget.selectedCapacityMl < 5000
                        ? AppColors.primary
                        : AppColors.border,
                    splashRadius: 16,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: widget.selectedCapacityMl < 5000
                        ? () => widget.onChanged(widget.selectedCapacityMl + 100)
                        : null,
                  ),
                  IconButton(
                    key: const Key('custom_water_tank_wheel_picker_button'),
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

        // Contextual Tank Summary
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
                Icons.water_drop_rounded,
                size: 13,
                color: AppColors.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Holds $liters Liters (${widget.selectedCapacityMl} mL) of demineralized water for automated nozzle washing.',
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

/// Modal Bottom Sheet featuring a hybrid Cupertino Picker Wheel and Direct Numeric Keyboard Input.
void showCustomWaterTankPickerModal({
  required BuildContext context,
  required int initialCapacityMl,
  required ValueChanged<int> onApplied,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (modalContext) => _CustomWaterTankPickerModal(
      initialCapacityMl: initialCapacityMl,
      onApplied: onApplied,
    ),
  );
}

class _CustomWaterTankPickerModal extends StatefulWidget {
  const _CustomWaterTankPickerModal({
    required this.initialCapacityMl,
    required this.onApplied,
  });

  final int initialCapacityMl;
  final ValueChanged<int> onApplied;

  @override
  State<_CustomWaterTankPickerModal> createState() =>
      _CustomWaterTankPickerModalState();
}

class _CustomWaterTankPickerModalState
    extends State<_CustomWaterTankPickerModal> {
  // Steps of 100 mL from 500 mL to 5,000 mL (46 items)
  static const int minMl = 500;
  static const int maxMl = 5000;
  static const int stepMl = 100;
  static final int itemCount = ((maxMl - minMl) / stepMl).round() + 1;

  late int _currentMl;
  late TextEditingController _textCtrl;
  late FixedExtentScrollController _wheelCtrl;
  bool _isProgrammaticScroll = false;

  int _mlToIndex(int ml) {
    final clamped = ml.clamp(minMl, maxMl);
    return ((clamped - minMl) / stepMl).round();
  }

  int _indexToMl(int index) {
    return minMl + (index * stepMl);
  }

  @override
  void initState() {
    super.initState();
    _currentMl = widget.initialCapacityMl.clamp(minMl, maxMl);
    _textCtrl = TextEditingController(text: '$_currentMl');
    final initialIndex = _mlToIndex(_currentMl);
    _wheelCtrl = FixedExtentScrollController(initialItem: initialIndex);
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _wheelCtrl.dispose();
    super.dispose();
  }

  void _onWheelChanged(int index) {
    if (_isProgrammaticScroll) return;
    final ml = _indexToMl(index);
    setState(() {
      _currentMl = ml;
      _textCtrl.text = '$ml';
    });
  }

  void _onTextTyped(String text) {
    final parsed = int.tryParse(text.trim());
    if (parsed == null) return;
    final clamped = parsed.clamp(minMl, maxMl);
    setState(() {
      _currentMl = clamped;
    });

    final targetIndex = _mlToIndex(clamped);
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
    final liters = (_currentMl / 1000.0).toStringAsFixed(1);
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
            // Drag handle
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
                      Icons.water_drop_outlined,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Custom Water Tank Volume',
                      style: AppTypography.h3.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                TextButton(
                  key: const Key('custom_water_tank_done_header_button'),
                  onPressed: () {
                    widget.onApplied(_currentMl);
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

            // Direct Typing Input with live Liters badge
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    key: const Key('custom_water_tank_text_field'),
                    label: 'Type Volume (mL)',
                    hintText: 'e.g. 2400',
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
                      '= $liters Liters',
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
                childCount: itemCount,
                itemBuilder: (context, index) {
                  final ml = _indexToMl(index);
                  final l = (ml / 1000.0).toStringAsFixed(1);
                  final isSelected = ml == _currentMl;
                  return Center(
                    child: Text(
                      '$ml mL  ·  $l L',
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
              key: const Key('custom_water_tank_apply_button'),
              label: 'Apply Volume ($liters L)',
              onPressed: () {
                widget.onApplied(_currentMl);
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}
