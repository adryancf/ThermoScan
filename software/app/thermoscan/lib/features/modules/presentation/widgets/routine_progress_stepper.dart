import 'dart:async';

import 'package:flutter/material.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';

/// Compact 4-step live routine tracker shown only while a scan/cleaning/verification
/// cycle is active, waiting cooldown, resetting, or halted in ERROR_HALT.
/// Collapses completely (`SizedBox.shrink`) when the robot is in IDLE.
class RoutineProgressStepper extends StatefulWidget {
  const RoutineProgressStepper({
    super.key,
    required this.firmwareState,
    this.firmwareStateDetail,
    this.verificationReadyAt,
    this.resetPending = false,
  });

  final String? firmwareState;
  final String? firmwareStateDetail;
  final String? verificationReadyAt;
  final bool resetPending;

  static bool isVisibleForState(String? state, {bool resetPending = false}) {
    if (resetPending) return true;
    final norm = (state ?? '').trim().toUpperCase();
    return switch (norm) {
      'SCANNING' ||
      'ANALYZING' ||
      'CLEANING' ||
      'WAITING_VERIFICATION' ||
      'VERIFYING' ||
      'VERIFICATION' ||
      'SYNCING' ||
      'ERROR_HALT' =>
        true,
      _ => false,
    };
  }

  @override
  State<RoutineProgressStepper> createState() => _RoutineProgressStepperState();
}

class _RoutineProgressStepperState extends State<RoutineProgressStepper> {
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _syncCountdownTimer();
  }

  @override
  void didUpdateWidget(covariant RoutineProgressStepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.firmwareState != widget.firmwareState ||
        oldWidget.firmwareStateDetail != widget.firmwareStateDetail ||
        oldWidget.verificationReadyAt != widget.verificationReadyAt ||
        oldWidget.resetPending != widget.resetPending) {
      _syncCountdownTimer();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    super.dispose();
  }

  DateTime? _parseTargetUtc() {
    if (widget.resetPending) return null;
    final normState = (widget.firmwareState ?? '').trim().toUpperCase();
    final normDetail = (widget.firmwareStateDetail ?? '').trim().toLowerCase();
    if (normState != 'WAITING_VERIFICATION' ||
        normDetail == 'solar_window_closed' ||
        normDetail == 'insufficient_water' ||
        normDetail == 'high_baseline_temp') {
      return null;
    }
    final raw = widget.verificationReadyAt;
    if (raw == null || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw.trim())?.toUtc();
  }

  void _syncCountdownTimer() {
    final target = _parseTargetUtc();
    if (target == null) {
      _countdownTimer?.cancel();
      _countdownTimer = null;
      return;
    }

    if (target.difference(DateTime.now().toUtc()) <= Duration.zero) {
      _countdownTimer?.cancel();
      _countdownTimer = null;
      return;
    }

    _countdownTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final currentTarget = _parseTargetUtc();
      if (currentTarget == null ||
          currentTarget.difference(DateTime.now().toUtc()) <= Duration.zero) {
        _countdownTimer?.cancel();
        _countdownTimer = null;
      }
      setState(() {});
    });
  }

  static String _formatRemaining(Duration remaining) {
    final totalSeconds = remaining.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '${hours}h ${minutes.toString().padLeft(2, '0')}m ${seconds.toString().padLeft(2, '0')}s';
    }
    if (minutes > 0) {
      return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
    }
    return '${seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    if (!RoutineProgressStepper.isVisibleForState(
      widget.firmwareState,
      resetPending: widget.resetPending,
    )) {
      return const SizedBox.shrink();
    }

    final normState = widget.resetPending
        ? 'RESET_REQUESTED'
        : (widget.firmwareState ?? '').trim().toUpperCase();
    final normDetail = (widget.firmwareStateDetail ?? '').trim().toLowerCase();

    final _StepperStateMeta meta = _resolveMeta(normState, normDetail);

    const steps = <_StepDef>[
      _StepDef(label: 'Scan', icon: Icons.radar),
      _StepDef(label: 'Analysis', icon: Icons.analytics_outlined),
      _StepDef(label: 'Cleaning', icon: Icons.cleaning_services_outlined),
      _StepDef(label: 'Final Check', icon: Icons.fact_check_outlined),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: meta.isError ? AppColors.errorBackground : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: meta.isError
              ? AppColors.errorBorder
              : meta.accentColor.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: meta.accentColor.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (int i = 0; i < steps.length; i++) ...[
                Expanded(
                  child: _buildStepNode(
                    step: steps[i],
                    index: i,
                    activeIndex: meta.activeIndex,
                    isError: meta.isError,
                    isWaiting: meta.isWaiting,
                    accentColor: meta.accentColor,
                  ),
                ),
                if (i < steps.length - 1)
                  Expanded(
                    flex: 0,
                    child: Container(
                      width: 18,
                      height: 2,
                      margin: const EdgeInsets.only(bottom: 18),
                      color: i < meta.activeIndex
                          ? AppColors.success
                          : AppColors.border,
                    ),
                  ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (!meta.isError && !meta.isWaiting)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: meta.accentColor,
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(
                    meta.isError
                        ? Icons.error_outline
                        : Icons.hourglass_top_rounded,
                    size: 15,
                    color: meta.accentColor,
                  ),
                ),
              Expanded(
                child: Text(
                  meta.message,
                  style: AppTypography.bodySmall.copyWith(
                    color: meta.isError
                        ? AppColors.error
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepNode({
    required _StepDef step,
    required int index,
    required int activeIndex,
    required bool isError,
    required bool isWaiting,
    required Color accentColor,
  }) {
    final bool isDone = !isError && index < activeIndex;
    final bool isCurrent = index == activeIndex;

    final Color circleBg;
    final Color borderColor;
    final Color iconColor;
    final IconData icon;

    if (isDone) {
      circleBg = AppColors.success.withValues(alpha: 0.14);
      borderColor = AppColors.success;
      iconColor = AppColors.success;
      icon = Icons.check_rounded;
    } else if (isCurrent) {
      circleBg = accentColor.withValues(alpha: 0.14);
      borderColor = accentColor;
      iconColor = accentColor;
      icon = isError
          ? Icons.error_outline
          : (isWaiting ? Icons.hourglass_top_rounded : step.icon);
    } else {
      circleBg = AppColors.background;
      borderColor = AppColors.border;
      iconColor = AppColors.textSecondary;
      icon = step.icon;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: circleBg,
            shape: BoxShape.circle,
            border: Border.all(
              color: borderColor,
              width: isCurrent ? 1.8 : 1.2,
            ),
          ),
          child: Icon(icon, size: 15, color: iconColor),
        ),
        const SizedBox(height: 5),
        Text(
          step.label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.caption.copyWith(
            fontSize: 10.5,
            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
            color: isCurrent
                ? (isError ? AppColors.error : AppColors.textPrimary)
                : (isDone ? AppColors.success : AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  _StepperStateMeta _resolveMeta(String normState, String normDetail) {
    switch (normState) {
      case 'SCANNING':
        return _StepperStateMeta(
          activeIndex: 0,
          accentColor: Colors.blue.shade700,
          message: 'Step 1/4 • Scanning thermal profile across panels...',
        );
      case 'ANALYZING':
        return _StepperStateMeta(
          activeIndex: 1,
          accentColor: Colors.deepPurple.shade600,
          message: 'Step 2/4 • Analyzing hotspots and finalizing results...',
        );
      case 'CLEANING':
        return _StepperStateMeta(
          activeIndex: 2,
          accentColor: Colors.cyan.shade700,
          message: 'Step 3/4 • Actuating water spray cleaning...',
        );
      case 'WAITING_VERIFICATION':
        String waitMsg;
        switch (normDetail) {
          case 'solar_window_closed':
            waitMsg =
                'Step 4/4 • Waiting for valid solar window to verify...';
          case 'insufficient_water':
            waitMsg =
                'Step 4/4 • Waiting water refill before verification...';
          case 'high_baseline_temp':
            waitMsg = 'Step 4/4 • Waiting for panel temperature to drop...';
          default:
            final target = _parseTargetUtc();
            if (target != null) {
              final remaining = target.difference(DateTime.now().toUtc());
              if (remaining > Duration.zero) {
                waitMsg =
                    'Step 4/4 • Cooling down • ${_formatRemaining(remaining)} remaining';
              } else {
                waitMsg = 'Step 4/4 • Cooldown complete, preparing check...';
              }
            } else {
              waitMsg = 'Step 4/4 • Cooling down before final check...';
            }
        }
        return _StepperStateMeta(
          activeIndex: 3,
          isWaiting: true,
          accentColor: Colors.amber.shade800,
          message: waitMsg,
        );
      case 'VERIFYING':
      case 'VERIFICATION':
        return _StepperStateMeta(
          activeIndex: 3,
          accentColor: Colors.blueGrey.shade700,
          message: 'Step 4/4 • Running final post-cleaning verification...',
        );
      case 'SYNCING':
        return _StepperStateMeta(
          activeIndex: 3,
          accentColor: Colors.lightBlue.shade700,
          message: 'Syncing configuration and routine status...',
        );
      case 'RESET_REQUESTED':
        return _StepperStateMeta(
          activeIndex: 0,
          isError: true,
          accentColor: Colors.red.shade700,
          message: 'Reset requested — waiting for robot acknowledgement...',
        );
      case 'ERROR_HALT':
        final reason = normDetail.isEmpty ? 'hardware_fault' : normDetail;
        return _StepperStateMeta(
          activeIndex: 0,
          isError: true,
          accentColor: Colors.red.shade700,
          message:
              'Robot halted ($reason) — use Abort & Reset Routine to recover.',
        );
      default:
        return _StepperStateMeta(
          activeIndex: 0,
          accentColor: AppColors.primary,
          message: 'Routine in progress...',
        );
    }
  }
}

class _StepDef {
  const _StepDef({required this.label, required this.icon});
  final String label;
  final IconData icon;
}

class _StepperStateMeta {
  const _StepperStateMeta({
    required this.activeIndex,
    required this.accentColor,
    required this.message,
    this.isError = false,
    this.isWaiting = false,
  });

  final int activeIndex;
  final Color accentColor;
  final String message;
  final bool isError;
  final bool isWaiting;
}
