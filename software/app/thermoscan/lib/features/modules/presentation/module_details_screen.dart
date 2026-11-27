import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:thermoscan/core/network/api_exception.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/core/utils/date_formatter.dart';
import 'package:thermoscan/core/widgets/app_buttons.dart';
import 'package:thermoscan/core/widgets/top_app_bar.dart';
import 'package:thermoscan/features/alerts/presentation/alerts_controller.dart';
import 'package:thermoscan/features/auth/presentation/auth_controller.dart';
import 'package:thermoscan/features/modules/data/module_repository.dart';
import 'package:thermoscan/features/modules/domain/inspection_routine_bundle.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';
import 'package:thermoscan/features/modules/domain/solar_window_calculator.dart';
import 'package:thermoscan/features/modules/presentation/module_cleanings_screen.dart';
import 'package:thermoscan/features/modules/presentation/module_configuration_screen.dart';
import 'package:thermoscan/features/modules/presentation/module_measurements_screen.dart';
import 'package:thermoscan/features/modules/presentation/module_state_logs_screen.dart';
import 'package:thermoscan/features/modules/presentation/modules_controller.dart';
import 'package:thermoscan/features/modules/presentation/modules_home_screen.dart';
import 'package:thermoscan/features/modules/presentation/widgets/clean_thermal_preview_card.dart';
import 'package:thermoscan/features/modules/presentation/widgets/export_pdf_report_sheet.dart';
import 'package:thermoscan/features/modules/presentation/widgets/firmware_state_badge.dart';
import 'package:thermoscan/features/modules/presentation/widgets/routine_progress_stepper.dart';
import 'package:thermoscan/features/modules/presentation/widgets/solar_window_widgets.dart';
import 'package:thermoscan/features/modules/presentation/widgets/thermal_matrix_inspector_modal.dart';
import 'package:thermoscan/features/modules/presentation/widgets/thermal_panorama_painter.dart';

/// SCR-10: Module Details Screen with TabBar / TabBarView navigation
class ModuleDetailsScreen extends ConsumerStatefulWidget {
  const ModuleDetailsScreen({
    super.key,
    required this.moduleId,
    this.initialTabIndex = 0,
  });

  final String moduleId;
  final int initialTabIndex;

  @override
  ConsumerState<ModuleDetailsScreen> createState() =>
      _ModuleDetailsScreenState();
}

class _ModuleDetailsScreenState extends ConsumerState<ModuleDetailsScreen> {
  bool _infoExpanded = false;
  bool _updatingEmailPref = false;
  bool _isTriggeringInspection = false;
  bool _isTriggeringCleaning = false;
  bool _isTriggeringLocalizedReading = false;
  bool _isFetchingLocalizedReading = false;
  bool _awaitingLocalizedReading = false;
  String? _previousLocalizedReadingAt;
  double? _pendingLocalizedTargetXCm;
  Timer? _localizedReadingTimeoutTimer;
  bool _awaitingManualCleaning = false;
  bool _manualCleaningSawActive = false;
  double? _pendingManualCleaningTargetXCm;
  Timer? _manualCleaningTimeoutTimer;
  Timer? _statusRefreshTimer;
  String? _lastObservedFirmwareState;

  @override
  void initState() {
    super.initState();
    _statusRefreshTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (!mounted) return;
        final curStatus =
            ref.read(moduleDeviceStatusProvider(widget.moduleId)).valueOrNull;
        final curState = curStatus?.firmwareState;
        final isActive = RoutineProgressStepper.isVisibleForState(
          curState,
          resetPending: curStatus?.resetPending == true,
        );
        final justFinished = !isActive &&
            RoutineProgressStepper.isVisibleForState(_lastObservedFirmwareState);
        ref.invalidate(moduleDeviceStatusProvider(widget.moduleId));
        if (isActive || justFinished) {
          ref.invalidate(latestInspectionProvider(widget.moduleId));
        }
        if (justFinished) {
          ref.invalidate(moduleMeasurementsProvider(widget.moduleId));
          ref.invalidate(moduleInspectionsProvider(widget.moduleId));
          ref.invalidate(moduleCleaningsProvider(widget.moduleId));
          ref.invalidate(alertsSummaryProvider);
        }
        _lastObservedFirmwareState = curState;
      },
    );
  }

  @override
  void dispose() {
    _statusRefreshTimer?.cancel();
    _localizedReadingTimeoutTimer?.cancel();
    _manualCleaningTimeoutTimer?.cancel();
    super.dispose();
  }

  void _handleDeviceStatusUpdate(DeviceStatus newStatus) {
    if (_awaitingLocalizedReading) {
      final newAt = newStatus.localizedReadingAt;
      if (newAt != null &&
          newAt.isNotEmpty &&
          newAt != _previousLocalizedReadingAt) {
        _localizedReadingTimeoutTimer?.cancel();
        _localizedReadingTimeoutTimer = null;
        setState(() {
          _awaitingLocalizedReading = false;
          _pendingLocalizedTargetXCm = null;
        });
        unawaited(_openStoredLocalizedReading(widget.moduleId));
      }
    }

    if (_awaitingManualCleaning) {
      final normState = (newStatus.firmwareState ?? '').trim().toUpperCase();
      final normDetail =
          (newStatus.firmwareStateDetail ?? '').trim().toLowerCase();
      final isActive = newStatus.manualCleaningPending ||
          (normState == 'CLEANING' && normDetail == 'manual_cleaning') ||
          normState == 'CLEANING';
      if (isActive) {
        _manualCleaningSawActive = true;
      } else if (_manualCleaningSawActive && normState == 'IDLE') {
        _manualCleaningTimeoutTimer?.cancel();
        _manualCleaningTimeoutTimer = null;
        setState(() {
          _awaitingManualCleaning = false;
          _manualCleaningSawActive = false;
          _pendingManualCleaningTargetXCm = null;
        });
        ref.invalidate(moduleCleaningsProvider(widget.moduleId));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Manual cleaning completed.'),
              backgroundColor: AppColors.success,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  Future<void> _openStoredLocalizedReading(String moduleId) async {
    if (_isFetchingLocalizedReading) return;
    setState(() => _isFetchingLocalizedReading = true);
    try {
      final reading = await ref
          .read(moduleRepositoryProvider)
          .getLocalizedReading(moduleId);
      if (!mounted) return;
      await showLocalizedReadingDialog(context, reading);
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load localized reading: $err'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isFetchingLocalizedReading = false);
      }
    }
  }

  Future<double?> _promptTargetXPositionCm({
    required String title,
    String? description,
    required String confirmLabel,
    required PvModule mod,
    double? initialXCm,
  }) {
    return showDialog<double>(
      context: context,
      builder: (_) => _TargetXPositionDialog(
        title: title,
        description: description,
        confirmLabel: confirmLabel,
        mod: mod,
        initialXCm: initialXCm,
      ),
    );
  }

  Future<void> _triggerManualScan(String moduleId) async {
    setState(() => _isTriggeringInspection = true);
    try {
      await ref
          .read(moduleRepositoryProvider)
          .triggerManualInspection(moduleId: moduleId);
      ref.invalidate(moduleDeviceStatusProvider(moduleId));
      ref.invalidate(latestInspectionProvider(moduleId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Inspection requested! The robot will start scanning on next communication.',
          ),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 4),
        ),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to request inspection: $err'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isTriggeringInspection = false);
      }
    }
  }

  Future<void> _promptAndTriggerLocalizedReading(
    PvModule mod,
    DeviceStatus? deviceStatus,
  ) async {
    final targetX = await _promptTargetXPositionCm(
      title: 'Localized Reading',
      description:
          'Move the sensor carriage to X (cm) and capture a single 32×24 thermal frame.',
      confirmLabel: 'Capture',
      mod: mod,
      initialXCm: deviceStatus?.localizedReadingXCm ?? mod.localizedReadingXCm,
    );
    if (targetX == null || !mounted) return;

    final currentStatus =
        ref.read(moduleDeviceStatusProvider(mod.id)).valueOrNull ??
            deviceStatus;
    final prevReadingAt =
        currentStatus?.localizedReadingAt ?? mod.localizedReadingAt;

    setState(() => _isTriggeringLocalizedReading = true);
    try {
      await ref.read(moduleRepositoryProvider).triggerManualReading(
            moduleId: mod.id,
            targetXPositionCm: targetX,
          );
      if (!mounted) return;
      _localizedReadingTimeoutTimer?.cancel();
      _localizedReadingTimeoutTimer = Timer(const Duration(seconds: 60), () {
        if (!mounted || !_awaitingLocalizedReading) return;
        setState(() {
          _awaitingLocalizedReading = false;
          _pendingLocalizedTargetXCm = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Localized reading capture timed out after 60s. Check More actions later.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
      });
      setState(() {
        _awaitingLocalizedReading = true;
        _previousLocalizedReadingAt = prevReadingAt;
        _pendingLocalizedTargetXCm = targetX;
      });
      ref.invalidate(moduleDeviceStatusProvider(mod.id));
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to request localized reading: $err'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isTriggeringLocalizedReading = false);
      }
    }
  }

  Future<void> _promptAndTriggerManualCleaning(PvModule mod) async {
    final targetX = await _promptTargetXPositionCm(
      title: 'Manual Cleaning',
      confirmLabel: 'Trigger',
      mod: mod,
    );
    if (targetX == null || !mounted) return;

    setState(() => _isTriggeringCleaning = true);
    try {
      await ref.read(moduleRepositoryProvider).triggerManualCleaning(
            moduleId: mod.id,
            targetXPositionCm: targetX,
          );
      if (!mounted) return;
      _manualCleaningTimeoutTimer?.cancel();
      _manualCleaningTimeoutTimer = Timer(const Duration(seconds: 60), () {
        if (!mounted || !_awaitingManualCleaning) return;
        setState(() {
          _awaitingManualCleaning = false;
          _manualCleaningSawActive = false;
          _pendingManualCleaningTargetXCm = null;
        });
      });
      setState(() {
        _awaitingManualCleaning = true;
        _manualCleaningSawActive = false;
        _pendingManualCleaningTargetXCm = targetX;
      });
      ref.invalidate(moduleDeviceStatusProvider(mod.id));
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to request manual cleaning: $err'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isTriggeringCleaning = false);
      }
    }
  }

  Future<void> _toggleEmailPreference(bool enabled) async {
    setState(() => _updatingEmailPref = true);
    try {
      await ref.read(moduleRepositoryProvider).updateClientEmailPreference(
            moduleId: widget.moduleId,
            operationalEmailEnabled: enabled,
          );
      ref.invalidate(moduleDetailsProvider(widget.moduleId));
      ref.invalidate(modulesListProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Operational email alerts enabled for this module.'
                : 'Operational email alerts disabled for this module.',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err.toString()),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _updatingEmailPref = false);
      }
    }
  }

  Future<void> _confirmAndResetRoutine() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Abort & Reset Routine'),
        content: const Text(
          'This will stop any active scan or cleaning, clear the command queue, '
          'and return the module to IDLE. Are you sure you want to continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Abort & Reset'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await ref.read(moduleRepositoryProvider).resetRoutine(widget.moduleId);
      ref.invalidate(moduleDeviceStatusProvider(widget.moduleId));
      ref.invalidate(moduleDetailsProvider(widget.moduleId));
      ref.invalidate(latestInspectionProvider(widget.moduleId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reset routine requested. Module will return to IDLE.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to reset routine: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _confirmAndDeleteModule(String moduleName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.errorBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.errorBorder),
                    ),
                    child: const Icon(
                      Icons.delete_forever_outlined,
                      color: AppColors.error,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Delete Module?',
                      style: AppTypography.h3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Are you sure you want to permanently delete "$moduleName"?',
                style: AppTypography.body.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Delete this module permanently? Its measurements, thermal maps, cleaning history, alerts, and access assignments will also be deleted. This action cannot be undone.',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: SecondaryButton(
                      label: 'Cancel',
                      onPressed: () => Navigator.of(ctx).pop(false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DangerButton(
                      label: 'Delete',
                      onPressed: () => Navigator.of(ctx).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await ref
          .read(moduleRepositoryProvider)
          .deleteModule(moduleId: widget.moduleId);
      ref.invalidate(modulesListProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Module deleted successfully.'),
          backgroundColor: AppColors.success,
        ),
      );
      context.go('/modules');
    } on ApiException catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err.message),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete module: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return 'Not configured yet';
    final idx = iso.indexOf('T');
    return idx > 0 ? iso.substring(0, idx) : iso;
  }

  String _formatDateTime(DateTime? dt) =>
      AppDateFormatter.formatDateTime(dt, includeYear: true, fallback: 'recent');

  String _formatReadableTimestamp(String? iso) =>
      AppDateFormatter.formatDateTimeShort(iso);

  String _formatNextInspectionLabel(String? iso, {bool isPendingManual = false}) {
    if (isPendingManual) {
      return 'Scan Requested (Queued)';
    }
    if (iso != null && iso.isNotEmpty) {
      final dt = DateTime.tryParse(iso)?.toLocal();
      if (dt != null) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final targetDay = DateTime(dt.year, dt.month, dt.day);
        final diffDays = targetDay.difference(today).inDays;

        if (diffDays == 0) {
          final hour12 =
              dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
          final minuteStr = dt.minute.toString().padLeft(2, '0');
          final ampm = dt.hour >= 12 ? 'PM' : 'AM';
          return 'Next: Today ($hour12:$minuteStr $ampm)';
        } else if (diffDays == 1) {
          return 'Next: Tomorrow';
        } else if (diffDays > 1 && diffDays < 7) {
          return 'Next: in ${diffDays}d';
        } else {
          const months = [
            'Jan',
            'Feb',
            'Mar',
            'Apr',
            'May',
            'Jun',
            'Jul',
            'Aug',
            'Sep',
            'Oct',
            'Nov',
            'Dec'
          ];
          return 'Next: ${dt.day} ${months[dt.month - 1]}';
        }
      }
    }
    return 'Next: Awaiting sync';
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final detailsAsync = ref.watch(moduleDetailsProvider(widget.moduleId));
    final deviceStatusAsync =
        ref.watch(moduleDeviceStatusProvider(widget.moduleId));

    ref.listen<AsyncValue<DeviceStatus>>(
      moduleDeviceStatusProvider(widget.moduleId),
      (previous, next) {
        if (next.isLoading || !next.hasValue) return;
        final newStatus = next.valueOrNull;
        if (newStatus != null) {
          _handleDeviceStatusUpdate(newStatus);
        }
      },
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        context.go('/modules');
      },
      child: detailsAsync.when(
        loading: () => Scaffold(
          backgroundColor: AppColors.background,
          appBar: ThermoScanAppBar(
            title: 'Module Details',
            role: user?.role ?? 'technician',
            showBack: true,
            onBack: () => context.go('/modules'),
          ),
          body: const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        ),
        error: (err, _) => Scaffold(
          backgroundColor: AppColors.background,
          appBar: ThermoScanAppBar(
            title: 'Module Details',
            role: user?.role ?? 'technician',
            showBack: true,
            onBack: () => context.go('/modules'),
          ),
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: AppColors.error,
                    size: 40,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    err.toString(),
                    textAlign: TextAlign.center,
                    style: AppTypography.body,
                  ),
                  const SizedBox(height: 16),
                  SecondaryButton(
                    label: 'Retry',
                    fullWidth: false,
                    onPressed: () {
                      ref.invalidate(moduleDetailsProvider(widget.moduleId));
                      ref.invalidate(
                          moduleDeviceStatusProvider(widget.moduleId));
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        data: (details) {
          final mod = details.module;
          final perms = mod.permissions;
          final isPendingConfig = mod.isPendingConfiguration;
          final tabCount = isPendingConfig ? 3 : 4;
          final safeInitialIndex = (widget.initialTabIndex < tabCount)
              ? widget.initialTabIndex
              : 0;

          final deviceStatus = deviceStatusAsync.valueOrNull;

          return DefaultTabController(
            key: ValueKey('module_tabs_${isPendingConfig}_$safeInitialIndex'),
            length: tabCount,
            initialIndex: safeInitialIndex,
            child: Scaffold(
              backgroundColor: AppColors.background,
              appBar: ThermoScanAppBar(
                title: mod.name,
                role: user?.role ?? 'technician',
                showBack: true,
                onBack: () => context.go('/modules'),
                trailingAction: IconButton(
                  key: const Key('module_more_actions_button'),
                  icon: const Icon(
                    Icons.more_vert,
                    color: AppColors.primary,
                  ),
                  tooltip: 'More actions',
                  onPressed: () => _showModuleActionsSheet(
                    context,
                    mod,
                    perms,
                    deviceStatus,
                  ),
                ),
              ),
              body: SafeArea(
                child: Column(
                  children: [
                    if (_awaitingLocalizedReading)
                      _buildLocalizedReadingPendingBanner(),
                    if (_isManualCleaningActive(deviceStatus, mod))
                      _buildManualCleaningPendingBanner(deviceStatus),
                    Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        color: AppColors.surface,
                        border: Border(
                          bottom: BorderSide(
                            color: AppColors.border,
                            width: 1,
                          ),
                        ),
                      ),
                      child: TabBar(
                        isScrollable: false,
                        labelColor: AppColors.primary,
                        unselectedLabelColor: AppColors.textSecondary,
                        indicatorColor: AppColors.primary,
                        indicatorWeight: 3,
                        indicatorSize: TabBarIndicatorSize.tab,
                        labelStyle: AppTypography.caption.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                        unselectedLabelStyle: AppTypography.caption.copyWith(
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                        tabs: [
                          const Tab(text: 'Overview'),
                          const Tab(text: 'Measurements'),
                          const Tab(text: 'Cleanings'),
                          if (!isPendingConfig)
                            const Tab(text: 'Configuration'),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          // Tab 1: Overview
                          _buildOverviewTab(context, mod, details, deviceStatus),
                          // Tab 2: Measurements
                          ModuleMeasurementsView(moduleId: mod.id),
                          // Tab 3: Cleanings
                          ModuleCleaningsView(moduleId: mod.id),
                          // Tab 4: Configuration (if not pending)
                          if (!isPendingConfig)
                            ModuleConfigurationView(moduleId: mod.id),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLocalizedReadingPendingBanner() {
    final targetX = _pendingLocalizedTargetXCm;
    final message = targetX != null
        ? 'Capturing localized thermal frame at ${targetX.toStringAsFixed(1)} cm...'
        : 'Capturing localized thermal frame...';
    return Container(
      key: const Key('localized_reading_capturing_banner'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primarySoft.withValues(alpha: 0.75),
        border: Border(
          bottom: BorderSide(
            color: AppColors.primary.withValues(alpha: 0.25),
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.radar_rounded,
            size: 16,
            color: AppColors.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppTypography.caption.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          InkWell(
            key: const Key('dismiss_localized_reading_banner'),
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              _localizedReadingTimeoutTimer?.cancel();
              _localizedReadingTimeoutTimer = null;
              setState(() {
                _awaitingLocalizedReading = false;
                _pendingLocalizedTargetXCm = null;
              });
            },
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(
                Icons.close_rounded,
                size: 16,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isManualCleaningActive(DeviceStatus? deviceStatus, PvModule mod) {
    final normState =
        (deviceStatus?.firmwareState ?? mod.firmwareState ?? '')
            .trim()
            .toUpperCase();
    final normDetail =
        (deviceStatus?.firmwareStateDetail ?? mod.firmwareStateDetail ?? '')
            .trim()
            .toLowerCase();
    return _awaitingManualCleaning ||
        deviceStatus?.manualCleaningPending == true ||
        (normState == 'CLEANING' && normDetail == 'manual_cleaning');
  }

  Widget _buildManualCleaningPendingBanner(DeviceStatus? deviceStatus) {
    final targetX =
        _pendingManualCleaningTargetXCm ?? deviceStatus?.manualCleaningTargetXCm;
    final message = targetX != null
        ? 'Running manual cleaning at ${targetX.toStringAsFixed(1)} cm...'
        : 'Running manual cleaning...';
    return Container(
      key: const Key('manual_cleaning_active_banner'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primarySoft.withValues(alpha: 0.75),
        border: Border(
          bottom: BorderSide(
            color: AppColors.primary.withValues(alpha: 0.25),
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cleaning_services_outlined,
            size: 16,
            color: AppColors.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppTypography.caption.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          if (_awaitingManualCleaning)
            InkWell(
              key: const Key('dismiss_manual_cleaning_banner'),
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                _manualCleaningTimeoutTimer?.cancel();
                _manualCleaningTimeoutTimer = null;
                setState(() {
                  _awaitingManualCleaning = false;
                  _manualCleaningSawActive = false;
                  _pendingManualCleaningTargetXCm = null;
                });
              },
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: AppColors.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showModuleActionsSheet(
    BuildContext context,
    PvModule mod,
    ModulePermissions perms,
    DeviceStatus? deviceStatus,
  ) {
    final lastLocalizedAt =
        deviceStatus?.localizedReadingAt ?? mod.localizedReadingAt;
    final lastLocalizedX =
        deviceStatus?.localizedReadingXCm ?? mod.localizedReadingXCm;
    final hasLastLocalized =
        lastLocalizedAt != null && lastLocalizedAt.isNotEmpty;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetCtx).size.height * 0.85,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
              child: Column(
                key: const Key('module_actions_bottom_sheet'),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
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
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Module Actions',
                              style: AppTypography.h3.copyWith(fontSize: 16),
                            ),
                            Text(
                              mod.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        color: AppColors.textSecondary,
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(sheetCtx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  if (!mod.isPendingConfiguration) ...[
                    _buildActionSheetSectionHeader('ROBOT CONTROLS'),
                    const SizedBox(height: 6),
                    _buildActionSheetItem(
                      key: const Key('action_sheet_run_scan'),
                      icon: Icons.radar_rounded,
                      label: _isTriggeringInspection
                          ? 'Sending Scan Request...'
                          : 'Run Scan Now',
                      subtitle: 'Start a full panel thermal inspection',
                      enabled: !_isTriggeringInspection,
                      onTap: () {
                        Navigator.of(sheetCtx).pop();
                        _triggerManualScan(mod.id);
                      },
                    ),
                    const SizedBox(height: 6),
                    _buildLocalizedReadingActionRow(
                      sheetCtx: sheetCtx,
                      mod: mod,
                      deviceStatus: deviceStatus,
                      hasLastLocalized: hasLastLocalized,
                      lastLocalizedX: lastLocalizedX,
                    ),
                    const SizedBox(height: 6),
                    _buildActionSheetItem(
                      key: const Key('action_sheet_manual_cleaning'),
                      icon: Icons.cleaning_services_outlined,
                      label: _isTriggeringCleaning
                          ? 'Sending Cleaning Request...'
                          : 'Manual Cleaning',
                      subtitle: 'Spot-wash a specific rail coordinate',
                      enabled: !_isTriggeringCleaning,
                      onTap: () {
                        Navigator.of(sheetCtx).pop();
                        _promptAndTriggerManualCleaning(mod);
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildActionSheetSectionHeader('REPORTS'),
                    const SizedBox(height: 6),
                    _buildActionSheetItem(
                      key: const Key('action_sheet_export_pdf'),
                      icon: Icons.picture_as_pdf_rounded,
                      label: 'Export PDF Report',
                      subtitle: 'Select one or multiple inspections to export',
                      onTap: () {
                        Navigator.of(sheetCtx).pop();
                        showExportPdfReportSheet(
                          context: context,
                          module: mod,
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                  ],

                  _buildActionSheetSectionHeader('DIAGNOSTICS'),
                  const SizedBox(height: 6),
                  _buildActionSheetItem(
                    key: const Key('action_sheet_state_logs'),
                    icon: Icons.history_rounded,
                    label: 'State Logs',
                    subtitle: 'Inspect firmware state history',
                    onTap: () {
                      Navigator.of(sheetCtx).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ModuleStateLogsScreen(
                            moduleId: mod.id,
                            moduleName: mod.name,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 6),
                  _buildActionSheetItem(
                    key: const Key('action_sheet_connection_check'),
                    icon: Icons.verified_outlined,
                    label: 'Robot Connection Check',
                    subtitle: 'Verify setup, Wi-Fi, sensors & camera',
                    onTap: () {
                      Navigator.of(sheetCtx).pop();
                      context.push('/modules/${mod.id}/device-verification');
                    },
                  ),

                  const SizedBox(height: 12),
                  const Divider(height: 1, color: AppColors.border),
                  const SizedBox(height: 10),

                  _buildActionSheetSectionHeader('DANGER ZONE', isDanger: true),
                  const SizedBox(height: 6),
                  _buildActionSheetItem(
                    key: const Key('action_sheet_reset_routine'),
                    icon: Icons.restart_alt_rounded,
                    label: 'Abort & Reset Routine',
                    subtitle: 'Stop active task and return robot to IDLE',
                    isDanger: true,
                    onTap: () {
                      Navigator.of(sheetCtx).pop();
                      _confirmAndResetRoutine();
                    },
                  ),
                  if (perms.canDelete) ...[
                    const SizedBox(height: 6),
                    _buildActionSheetItem(
                      key: const Key('action_sheet_delete_module'),
                      icon: Icons.delete_forever_outlined,
                      label: 'Delete Module',
                      subtitle: 'Permanently delete module and telemetry',
                      isDanger: true,
                      onTap: () {
                        Navigator.of(sheetCtx).pop();
                        _confirmAndDeleteModule(mod.name);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionSheetSectionHeader(String title, {bool isDanger = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        title,
        style: AppTypography.caption.copyWith(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
          color: isDanger ? AppColors.error : AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildActionSheetItem({
    Key? key,
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
    bool enabled = true,
    bool isDanger = false,
  }) {
    final fgColor = !enabled
        ? AppColors.textSecondary
        : (isDanger ? AppColors.error : AppColors.textPrimary);
    final iconColor = !enabled
        ? AppColors.textSecondary
        : (isDanger ? AppColors.error : AppColors.primary);
    final iconBg = isDanger
        ? AppColors.errorBackground
        : AppColors.primarySoft.withValues(alpha: 0.65);

    return Material(
      color: isDanger
          ? AppColors.errorBackground.withValues(alpha: 0.35)
          : AppColors.background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDanger ? AppColors.errorBorder : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppTypography.bodySmall.copyWith(
                        fontWeight: FontWeight.w700,
                        color: fgColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle,
                      style: AppTypography.caption.copyWith(
                        fontSize: 11,
                        color: isDanger
                            ? AppColors.error.withValues(alpha: 0.85)
                            : AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: isDanger
                    ? AppColors.error.withValues(alpha: 0.7)
                    : AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocalizedReadingActionRow({
    required BuildContext sheetCtx,
    required PvModule mod,
    required DeviceStatus? deviceStatus,
    required bool hasLastLocalized,
    required double? lastLocalizedX,
  }) {
    final enabled = !_isTriggeringLocalizedReading;
    final xLabel = lastLocalizedX != null
        ? 'Last: ${lastLocalizedX == lastLocalizedX.roundToDouble() ? lastLocalizedX.toStringAsFixed(0) : lastLocalizedX.toStringAsFixed(1)} cm'
        : 'View Last';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              key: const Key('action_sheet_localized_reading'),
              borderRadius: BorderRadius.horizontal(
                left: const Radius.circular(12),
                right:
                    hasLastLocalized ? Radius.zero : const Radius.circular(12),
              ),
              onTap: enabled
                  ? () {
                      Navigator.of(sheetCtx).pop();
                      _promptAndTriggerLocalizedReading(mod, deviceStatus);
                    }
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(
                        Icons.center_focus_strong_outlined,
                        size: 18,
                        color: enabled
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isTriggeringLocalizedReading
                                ? 'Requesting Reading...'
                                : 'Localized Reading',
                            style: AppTypography.bodySmall.copyWith(
                              fontWeight: FontWeight.w700,
                              color: enabled
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Capture a single 32×24 frame at X (cm)',
                            style: AppTypography.caption.copyWith(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (hasLastLocalized)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: InkWell(
                key: const Key('action_sheet_view_last_localized_reading'),
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _openStoredLocalizedReading(mod.id);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.grid_on_rounded,
                        size: 13,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        xLabel,
                        style: AppTypography.caption.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsBar(PvModule mod, DeviceStatus? deviceStatus) {
    final isOnline = deviceStatus?.isOnline ?? mod.isOnline;

    Widget buildAction({
      required IconData icon,
      required String label,
      required bool loading,
      required VoidCallback? onTap,
    }) {
      return Expanded(
        child: Material(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.border),
          ),
          child: InkWell(
            onTap: loading ? null : onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (loading)
                    const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    )
                  else
                    Icon(
                      icon,
                      size: 16,
                      color: isOnline
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: isOnline
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        buildAction(
          icon: Icons.play_arrow_rounded,
          label: 'Scan',
          loading: _isTriggeringInspection,
          onTap: () => _triggerManualScan(mod.id),
        ),
        const SizedBox(width: 8),
        buildAction(
          icon: Icons.radar_rounded,
          label: 'Read Point',
          loading: _isTriggeringLocalizedReading,
          onTap: () => _promptAndTriggerLocalizedReading(mod, deviceStatus),
        ),
        const SizedBox(width: 8),
        buildAction(
          icon: Icons.cleaning_services_outlined,
          label: 'Wash',
          loading: _isTriggeringCleaning,
          onTap: () => _promptAndTriggerManualCleaning(mod),
        ),
      ],
    );
  }

  Widget _buildOverviewTab(
    BuildContext context,
    PvModule mod,
    ModuleDetails details,
    DeviceStatus? deviceStatus,
  ) {
    final perms = mod.permissions;
    final measurementsAsync = ref.watch(moduleMeasurementsProvider(mod.id));
    final measurements =
        measurementsAsync.valueOrNull ?? const <ModuleMeasurement>[];
    final latestInspectionAsync = ref.watch(latestInspectionProvider(mod.id));
    final latestInspection = latestInspectionAsync.valueOrNull;
    final inspectionsAsync = ref.watch(moduleInspectionsProvider(mod.id));
    final cleaningsAsync = ref.watch(moduleCleaningsProvider(mod.id));
    final inspectionsList =
        inspectionsAsync.valueOrNull ?? const <ModuleInspection>[];
    final cleaningsList =
        cleaningsAsync.valueOrNull ?? const <ModuleCleaning>[];

    final bundles = InspectionRoutineBundle.buildBundles(
      allInspections: inspectionsList,
      allCleanings: cleaningsList,
      allMeasurements: measurements,
      latestInspection: latestInspection,
    );

    final latestBundle = InspectionRoutineBundle.getLatestActiveBundle(bundles) ??
        (bundles.isNotEmpty ? bundles.first : null);
    final verifMeasurements =
        latestBundle?.verificationMeasurements ?? const <ModuleMeasurement>[];
    final postCleaningResult = latestBundle?.verificationResult;

    final rawLatestMeasurement =
        measurements.isNotEmpty ? measurements.first : null;
    final currentMeasurements = filterMeasurementsForCurrentInspection(
      measurements: measurements,
      latestInspection: latestInspection,
      latestMeasurement: rawLatestMeasurement,
    );
    final latestMeasurement = currentMeasurements.isNotEmpty
        ? currentMeasurements.first
        : rawLatestMeasurement;

    final effectiveLatestInspection =
        latestBundle?.toEffectiveLatestInspection(latestInspection) ??
            latestInspection;
    final effectiveRoutineMeasurements = (latestBundle != null &&
            latestBundle.routineMeasurements.isNotEmpty)
        ? latestBundle.routineMeasurements
        : currentMeasurements;
    final effectiveLatestMeasurement =
        _latestMeasurementByTime(effectiveRoutineMeasurements) ??
            latestMeasurement;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        ref.invalidate(moduleDetailsProvider(widget.moduleId));
        ref.invalidate(moduleDeviceStatusProvider(widget.moduleId));
        ref.invalidate(moduleMeasurementsProvider(widget.moduleId));
        ref.invalidate(moduleInspectionsProvider(widget.moduleId));
        ref.invalidate(latestInspectionProvider(widget.moduleId));
        ref.invalidate(moduleCleaningsProvider(widget.moduleId));
        ref.invalidate(alertsSummaryProvider);
        await ref.read(moduleDetailsProvider(widget.moduleId).future);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Quick Robot Actions Bar (for Technicians & Managers on configured modules)
            if (!mod.isPendingConfiguration &&
                !(ref.watch(authControllerProvider).user?.isClient ??
                    false)) ...[
              _buildQuickActionsBar(mod, deviceStatus),
              const SizedBox(height: 16),
            ],
            // 1. Pending Configuration Banner
            if (mod.isPendingConfiguration) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.warningBackground,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.warningBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: AppColors.warning,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Pending Installation Configuration',
                            style: AppTypography.h3.copyWith(
                              fontSize: 15,
                              color: AppColors.warning,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Monitoring remains blocked until panel geometry, site coordinates, orientation, and minimum solar angle are configured.',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.warning,
                      ),
                    ),
                    if (perms.canEditGeometryAndLocation) ...[
                      const SizedBox(height: 12),
                      PrimaryButton(
                        label: 'Continue Installation Wizard',
                        icon: Icons.play_arrow_rounded,
                        onPressed: () =>
                            context.push('/modules/${mod.id}/install'),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 2. Module Info Collapsible Card / Accordion (TOPO)
            _buildModuleInfoCard(mod, details, deviceStatus),
            const SizedBox(height: 16),

            // 2b. Live 4-step routine tracker (only shown while active/halted/resetting, hidden during manual cleaning)
            if (RoutineProgressStepper.isVisibleForState(
                  deviceStatus?.firmwareState ?? mod.firmwareState,
                  firmwareStateDetail: deviceStatus?.firmwareStateDetail ??
                      mod.firmwareStateDetail,
                  resetPending: deviceStatus?.resetPending == true,
                ) &&
                !(_isManualCleaningActive(deviceStatus, mod) &&
                    (deviceStatus?.firmwareState ?? mod.firmwareState ?? '')
                            .trim()
                            .toUpperCase() ==
                        'CLEANING')) ...[
              RoutineProgressStepper(
                firmwareState: deviceStatus?.firmwareState ?? mod.firmwareState,
                firmwareStateDetail:
                    deviceStatus?.firmwareStateDetail ?? mod.firmwareStateDetail,
                verificationReadyAt:
                    deviceStatus?.verificationReadyAt ?? mod.verificationReadyAt,
                resetPending: deviceStatus?.resetPending == true,
              ),
              const SizedBox(height: 16),
            ],

            // 2c. Unified slim Solar Window & Next Scan card
            if (!mod.isPendingConfiguration &&
                mod.latitude != null &&
                mod.longitude != null) ...[
              Builder(
                builder: (context) {
                  final solarWindow = SolarWindowCalculator.computeDailyWindow(
                    latitude: mod.latitude!,
                    longitude: mod.longitude!,
                    minSolarAngleDeg: mod.minimumSolarAngleDeg ?? 15.0,
                    azimuthDeg: mod.azimuthDeg,
                    tiltDeg: mod.tiltDeg,
                  );
                  final nextScanLabel = _formatNextInspectionLabel(
                    deviceStatus?.nextInspectionAt ?? mod.nextInspectionAt,
                    isPendingManual:
                        deviceStatus?.manualInspectionPending == true,
                  );
                  return SolarWindowCompactCard(
                    window: solarWindow,
                    nextScanLabel: nextScanLabel,
                    onTap: () => showSolarWindowSheet(
                      context: context,
                      module: mod,
                      nextScanLabel: nextScanLabel,
                      onOpenScheduleHistory: () => _showScanHistoryModal(
                        context,
                        mod,
                        deviceStatus,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],

            // 3. Executive Health Hero Banner (com status de limpeza integrado)
            _buildExecutiveHealthBanner(
              mod: mod,
              deviceStatus: deviceStatus,
              latestInspection: effectiveLatestInspection,
              latestMeasurement: effectiveLatestMeasurement,
              measurements: effectiveRoutineMeasurements,
              hasPostCleaning: latestBundle?.hasPostCleaning ?? false,
              isHotspotResolved: latestBundle?.isHotspotResolved ?? false,
              fallbackBaselineTempC: latestBundle?.baselineTemperatureC,
              fallbackConfirmedAnomalies: latestBundle?.confirmedAnomalies,
            ),
            const SizedBox(height: 16),

            // 6. Clean Thermal Preview Card & Key Telemetry Metrics (SCR-10)
            if (!mod.isPendingConfiguration) ...[
              CleanThermalPreviewCard(
                module: mod,
                latestMeasurement: effectiveLatestMeasurement,
                latestInspection: effectiveLatestInspection,
                measurements: effectiveRoutineMeasurements,
                verificationMeasurements: verifMeasurements,
                postCleaningResult: postCleaningResult,
                fallbackBaselineTempC: latestBundle?.baselineTemperatureC,
                fallbackConfirmedAnomalies: latestBundle?.confirmedAnomalies,
              ),
              const SizedBox(height: 16),
              _buildKeyTelemetryGrid(
                mod: mod,
                latestMeasurement: effectiveLatestMeasurement,
                latestInspection: effectiveLatestInspection,
                measurements: effectiveRoutineMeasurements,
                isResolved: (latestBundle?.hasPostCleaning ?? false) &&
                    (latestBundle?.isHotspotResolved ?? false),
              ),
              const SizedBox(height: 16),
            ],

            // 7. Client Operational Email Preferences
            if (mod.userRelationship == 'assigned_client') ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Email Notification Preferences',
                      style: AppTypography.h3,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Control operational email alerts for this assigned module.',
                      style: AppTypography.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeThumbColor: AppColors.primary,
                      title: Text(
                        'Operational Email Alerts',
                        style: AppTypography.body.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        'Receive emails for unresolved anomalies, failed inspections, and insufficient water.',
                        style: AppTypography.caption,
                      ),
                      value: mod.operationalEmailEnabled ?? true,
                      onChanged: _updatingEmailPref
                          ? null
                          : _toggleEmailPreference,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  ModuleMeasurement? _latestMeasurementByTime(
    List<ModuleMeasurement> items,
  ) {
    if (items.isEmpty) return null;
    ModuleMeasurement best = items.first;
    DateTime? bestDt = DateTime.tryParse(best.measuredAt);
    for (var i = 1; i < items.length; i++) {
      final candidate = items[i];
      final candidateDt = DateTime.tryParse(candidate.measuredAt);
      if (candidateDt != null &&
          (bestDt == null || candidateDt.isAfter(bestDt))) {
        best = candidate;
        bestDt = candidateDt;
      }
    }
    return best;
  }

  /// Executive Health Hero Banner
  /// Communicates array health verdict to clients within 3 seconds.
  /// Strict relative threshold: baseline + 10°C or confirmed inspection anomaly.
  Widget _buildExecutiveHealthBanner({
    required PvModule mod,
    required DeviceStatus? deviceStatus,
    required LatestInspection? latestInspection,
    required ModuleMeasurement? latestMeasurement,
    required List<ModuleMeasurement> measurements,
    bool hasPostCleaning = false,
    bool isHotspotResolved = false,
    double? fallbackBaselineTempC,
    List<ConfirmedAnomaly>? fallbackConfirmedAnomalies,
  }) {
    final isInspScheduled = latestInspection?.inspection.status == 'scheduled';
    final rawConfirmedAnomalies = (!isInspScheduled && latestInspection != null)
        ? latestInspection.confirmedAnomalies
        : (fallbackConfirmedAnomalies ??
            latestInspection?.confirmedAnomalies ??
            const <ConfirmedAnomaly>[]);
    final confirmedAnomalies =
        rawConfirmedAnomalies.where((a) => !a.isCleared).toList();
    final hasHotspot = confirmedAnomalies.isNotEmpty;
    final hasTelemetry = latestInspection != null ||
        latestMeasurement != null ||
        measurements.isNotEmpty;

    final double? baseline = (!isInspScheduled &&
            latestInspection?.inspection.baselineTemperatureC != null)
        ? latestInspection!.inspection.baselineTemperatureC
        : (fallbackBaselineTempC ??
            latestInspection?.inspection.baselineTemperatureC);
    final panelBaselines = !isInspScheduled
        ? buildPanelBaselineMap(latestInspection?.panelResults)
        : const <int, double>{};
    double? peakTemp;
    if (measurements.isNotEmpty) {
      peakTemp = measurements
          .map((m) => m.maxTemperatureC)
          .reduce((a, b) => a > b ? a : b);
    } else if (latestMeasurement != null) {
      peakTemp = latestMeasurement.maxTemperatureC;
    }

    final double? delta = computeMaxPerPanelDelta(
      measurements: measurements,
      panelBaselines: panelBaselines,
      fallbackBaseline: baseline,
      module: mod,
      fallbackMeasurement: latestMeasurement,
    );

    final String title;
    final String subtitle;
    final String badgeText;
    final Color statusColor;
    final Color badgeBg;
    final Color badgeBorder;
    final IconData heroIcon;

    if (hasPostCleaning && isHotspotResolved) {
      title = 'Hotspot Resolved via Cleaning';
      if (baseline != null) {
        subtitle =
            'Thermal anomaly was successfully cleaned and verified normal (${baseline.toStringAsFixed(1)}°C). Array operating normally.';
      } else {
        subtitle =
            'Thermal anomaly was successfully cleaned and verified. Array operating normally.';
      }
      badgeText = 'CLEANED & RESOLVED';
      statusColor = AppColors.success;
      badgeBg = AppColors.successBackground;
      badgeBorder = AppColors.successBorder;
      heroIcon = Icons.task_alt_rounded;
    } else if (hasHotspot) {
      if (confirmedAnomalies.length == 1) {
        final anom = confirmedAnomalies.first;
        final pIdx = anom.panelIndex ??
            (mod.panelCount != null && mod.panelCount! > 0
                ? mod.resolvePanelPosition(anom.xPositionCm).panelIndex
                : null);
        title = (pIdx != null && pIdx > 0)
            ? 'Hotspot on Panel $pIdx'
            : 'Hotspot Detected';
      } else {
        final pIndices = confirmedAnomalies.map((a) {
          return a.panelIndex ??
              (mod.panelCount != null && mod.panelCount! > 0
                  ? mod.resolvePanelPosition(a.xPositionCm).panelIndex
                  : null);
        }).whereType<int>().toSet();

        if (pIndices.length == 1 && pIndices.first > 0) {
          title = 'Hotspots on Panel ${pIndices.first}';
        } else {
          title = '${confirmedAnomalies.length} Hotspots Detected';
        }
      }

      if (delta != null && baseline != null) {
        final sign = delta >= 0 ? '+' : '';
        subtitle =
            '$sign${delta.toStringAsFixed(1)}°C above normal (${baseline.toStringAsFixed(1)}°C). Robot cleaning recommended.';
      } else if (baseline != null) {
        subtitle =
            'Anomaly exceeds normal temp (${baseline.toStringAsFixed(1)}°C). Robot cleaning recommended.';
      } else {
        subtitle =
            'Thermal anomaly confirmed by inspection. Robot cleaning recommended.';
      }

      badgeText = 'HOTSPOT DETECTED';
      statusColor = AppColors.error;
      badgeBg = AppColors.errorBackground;
      badgeBorder = AppColors.errorBorder;
      heroIcon = Icons.warning_amber_rounded;
    } else if (hasTelemetry) {
      title = 'Solar Array Healthy';
      if (baseline != null) {
        subtitle =
            'All panels operating within normal temperature (${baseline.toStringAsFixed(1)}°C). No hotspots detected.';
      } else {
        subtitle =
            'All panels operating within normal temperature. No hotspots detected.';
      }

      badgeText = 'HEALTHY';
      statusColor = AppColors.success;
      badgeBg = AppColors.successBackground;
      badgeBorder = AppColors.successBorder;
      heroIcon = Icons.check_circle_outline_rounded;
    } else {
      title = 'Awaiting Initial Scan';
      subtitle =
          'Inspection scan will record normal temperature and heat map on next robotic cycle.';
      badgeText = 'AWAITING SCAN';
      statusColor = AppColors.warning;
      badgeBg = AppColors.warningBackground;
      badgeBorder = AppColors.warningBorder;
      heroIcon = Icons.radar_rounded;
    }

    // Integrated Hotspot Cleaning Lifecycle Status
    final cleaningsAsync = ref.watch(moduleCleaningsProvider(mod.id));
    final cleanings = cleaningsAsync.valueOrNull ?? const <ModuleCleaning>[];
    final mostRecent = cleanings.isNotEmpty ? cleanings.first : null;
    final activeAnomalyIds =
        confirmedAnomalies.map((a) => a.id).toSet();

    final isWaterLow = deviceStatus?.waterAvailable == false ||
        deviceStatus?.waterStatus == 'low' ||
        deviceStatus?.waterStatus == 'insufficient' ||
        (hasHotspot &&
            (mostRecent?.failureReason == 'insufficient_water' ||
                mostRecent?.failureReason == 'water_depleted_during_cleaning'));

    final isCleaningInProgress =
        cleanings.any((c) => c.status == 'in_progress');

    final isMostRecentAlreadyResolved = mostRecent != null &&
        (mostRecent.status == 'verified' ||
            mostRecent.status == 'refused' ||
            mostRecent.status == 'failed' ||
            mostRecent.postCleaningResult == 'resolved' ||
            mostRecent.postCleaningResult == 'verified_resolved' ||
            mostRecent.postCleaningResult == 'skipped');

    final isCoolDownPending = mostRecent != null &&
        !isMostRecentAlreadyResolved &&
        (mostRecent.postCleaningResult == 'pending' ||
            (mostRecent.status == 'completed' &&
                mostRecent.postCleaningResult.isEmpty));

    final washEndTimeStr = mostRecent?.endedAt ?? mostRecent?.startedAt;
    final washEndTime = washEndTimeStr != null
        ? DateTime.tryParse(washEndTimeStr)?.toUtc()
        : null;
    final coolDownElapsedMinutes = washEndTime != null
        ? DateTime.now().toUtc().difference(washEndTime).inMinutes
        : null;
    final isCoolDownElapsed =
        coolDownElapsedMinutes != null && coolDownElapsedMinutes >= 30;

    final relevantCleaning = mostRecent != null &&
            (activeAnomalyIds.isEmpty ||
                activeAnomalyIds.contains(mostRecent.anomalyEventId))
        ? mostRecent
        : null;

    final isPersistentHotspot = hasHotspot &&
        relevantCleaning != null &&
        ((relevantCleaning.attemptNumber != null &&
                relevantCleaning.attemptNumber! >= 3) ||
            relevantCleaning.postCleaningResult == 'verified_unresolved' ||
            relevantCleaning.postCleaningResult == 'unresolved');

    final showCleaningSection =
        hasHotspot || isCleaningInProgress || isCoolDownPending;

    final String cleaningStatusBadge;
    final Color cleaningBadgeColor;
    final Color cleaningBadgeBg;
    final Color cleaningBadgeBorder;
    final String cleaningCardTitle;
    final String cleaningCardDescription;
    final IconData cleaningCardIcon;

    if (isWaterLow) {
      cleaningStatusBadge = 'LOW WATER';
      cleaningBadgeColor = AppColors.warning;
      cleaningBadgeBg = AppColors.warningBackground;
      cleaningBadgeBorder = AppColors.warningBorder;
      cleaningCardTitle = 'Insufficient Water for Cleaning';
      cleaningCardDescription =
          'Water tank is empty. Refill the tank before the robot can wash the hotspot.';
      cleaningCardIcon = Icons.water_drop_outlined;
    } else if (isCleaningInProgress) {
      cleaningStatusBadge = 'CLEANING IN PROGRESS';
      cleaningBadgeColor = AppColors.primary;
      cleaningBadgeBg = AppColors.primarySoft;
      cleaningBadgeBorder = AppColors.primary.withValues(alpha: 0.3);
      cleaningCardTitle = 'Cleaning in Progress';
      cleaningCardDescription =
          'The robot is actively washing the panel area to remove dirt.';
      cleaningCardIcon = Icons.precision_manufacturing_rounded;
    } else if (isCoolDownPending) {
      if (isCoolDownElapsed) {
        cleaningStatusBadge = 'AWAITING VERIFICATION';
        cleaningBadgeColor = AppColors.primary;
        cleaningBadgeBg = AppColors.primarySoft;
        cleaningBadgeBorder = AppColors.primary.withValues(alpha: 0.3);
        cleaningCardTitle = 'Awaiting Post-Clean Verification';
        cleaningCardDescription =
            'Cool-down period completed. Ready for a thermal re-scan to verify if the hotspot was resolved.';
        cleaningCardIcon = Icons.fact_check_outlined;
      } else {
        cleaningStatusBadge = 'COOL-DOWN (30M)';
        cleaningBadgeColor = const Color(0xFF19B5D6);
        cleaningBadgeBg = const Color(0xFFE0F7FA);
        cleaningBadgeBorder = const Color(0xFFB2EBF2);
        cleaningCardTitle = 'Wash Completed — Cooling Down';
        cleaningCardDescription =
            'Spot wash completed. Waiting 30 minutes for the panel to cool before re-scanning.';
        cleaningCardIcon = Icons.hourglass_top_rounded;
      }
    } else if (isPersistentHotspot) {
      cleaningStatusBadge = 'PERSISTENT HOTSPOT';
      cleaningBadgeColor = AppColors.error;
      cleaningBadgeBg = AppColors.errorBackground;
      cleaningBadgeBorder = AppColors.errorBorder;
      cleaningCardTitle = 'Still Overheating After 3 Washes';
      cleaningCardDescription =
          'The robot washed this spot 3 times, but it is still hot. On-site technician inspection recommended.';
      cleaningCardIcon = Icons.handyman_outlined;
    } else {
      cleaningStatusBadge = 'CLEANING SCHEDULED';
      cleaningBadgeColor = AppColors.primary;
      cleaningBadgeBg = AppColors.primarySoft;
      cleaningBadgeBorder = AppColors.primary.withValues(alpha: 0.3);
      cleaningCardTitle = 'Automated Cleaning Scheduled';
      cleaningCardDescription =
          'Water tank is ready. The robot will wash the hotspot automatically during the next safe window.';
      cleaningCardIcon = Icons.calendar_today_rounded;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasHotspot ? AppColors.errorBorder : AppColors.border,
          width: hasHotspot ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: badgeBorder),
                ),
                child: Icon(heroIcon, color: statusColor, size: 24),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: badgeBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      badgeText,
                      style: AppTypography.chip.copyWith(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: AppTypography.h2.copyWith(fontSize: 20),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          if (latestMeasurement?.measuredAt != null ||
              (measurements.isNotEmpty && measurements.first.measuredAt.isNotEmpty) ||
              latestInspection?.inspection.createdAt != null) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  size: 13,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 5),
                Text(
                  'Last inspected: ${_formatReadableTimestamp(latestMeasurement?.measuredAt ?? (measurements.isNotEmpty ? measurements.first.measuredAt : null) ?? latestInspection?.inspection.createdAt)}',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
          if (baseline != null || peakTemp != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  if (baseline != null)
                    _HeroMetricItem(
                      label: 'Normal Temp',
                      value: '${baseline.toStringAsFixed(1)}°C',
                    ),
                  if (peakTemp != null)
                    _HeroMetricItem(
                      label: 'Peak Reading',
                      value: '${peakTemp.toStringAsFixed(1)}°C',
                    ),
                  if (delta != null)
                    _HeroMetricItem(
                      label: 'Above Normal',
                      value:
                          '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}°C',
                      valueColor:
                          hasHotspot ? AppColors.error : AppColors.success,
                    ),
                ],
              ),
            ),
          ],
          if (showCleaningSection) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cleaningBadgeBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: cleaningBadgeBorder,
                  width: isPersistentHotspot || isWaterLow ? 1.5 : 1.0,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            cleaningCardIcon,
                            size: 16,
                            color: cleaningBadgeColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Hotspot Cleaning Status',
                            style: AppTypography.caption.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: cleaningBadgeBorder),
                        ),
                        child: Text(
                          cleaningStatusBadge,
                          style: AppTypography.caption.copyWith(
                            color: cleaningBadgeColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    cleaningCardTitle,
                    style: AppTypography.bodySmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    cleaningCardDescription,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () {
                        final tabController =
                            DefaultTabController.maybeOf(context);
                        if (tabController != null) {
                          tabController.animateTo(2);
                        } else {
                          context.push('/modules/${mod.id}/cleanings');
                        }
                      },
                      icon: const Icon(
                        Icons.history_rounded,
                        size: 14,
                        color: AppColors.primary,
                      ),
                      label: Text(
                        'View Wash Logs →',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 4 Key Telemetry Metrics Grid (Flat, border-only, zero drop shadows)
  Widget _buildKeyTelemetryGrid({
    required PvModule mod,
    required ModuleMeasurement? latestMeasurement,
    required LatestInspection? latestInspection,
    required List<ModuleMeasurement> measurements,
    bool isResolved = false,
  }) {
    final confirmedAnomalies = (latestInspection?.confirmedAnomalies ?? const [])
        .where((a) => !a.isCleared)
        .toList();
    final hasConfirmedHotspots = !isResolved && confirmedAnomalies.isNotEmpty;

    final isInspScheduled = latestInspection?.inspection.status == 'scheduled';
    final double? baselineTemp =
        latestInspection?.inspection.baselineTemperatureC;
    final panelBaselines = !isInspScheduled
        ? buildPanelBaselineMap(latestInspection?.panelResults)
        : const <int, double>{};
    double? peakTemp;
    if (measurements.isNotEmpty) {
      peakTemp = measurements
          .map((m) => m.maxTemperatureC)
          .reduce((a, b) => a > b ? a : b);
    } else if (latestMeasurement != null) {
      peakTemp = latestMeasurement.maxTemperatureC;
    }

    final double? delta = computeMaxPerPanelDelta(
      measurements: measurements,
      panelBaselines: panelBaselines,
      fallbackBaseline: baselineTemp,
      module: mod,
      fallbackMeasurement: latestMeasurement,
    );

    final elecSummary = computeElectricalSummary(
      measurements: measurements,
      module: mod,
      fallbackMeasurement: latestMeasurement,
    );
    final voltage = elecSummary.voltageV;
    final current = elecSummary.currentA;
    final power = elecSummary.powerW;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildTelemetryMetricTile(
                label: 'Peak Temperature',
                value: peakTemp != null
                    ? '${peakTemp.toStringAsFixed(1)}°C'
                    : 'N/A',
                subtext: hasConfirmedHotspots
                    ? (delta != null
                        ? '+${delta.toStringAsFixed(1)}°C above normal (Hotspot)'
                        : 'Hotspot confirmed')
                    : (delta != null
                        ? '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}°C (Normal)'
                        : 'Within normal range'),
                isWarning: hasConfirmedHotspots,
                valueColor: hasConfirmedHotspots
                    ? AppColors.error
                    : AppColors.textPrimary,
                badge: hasConfirmedHotspots ? 'HOTSPOT' : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildTelemetryMetricTile(
                label: 'Normal Temperature',
                value: baselineTemp != null && baselineTemp > 0
                    ? '${baselineTemp.toStringAsFixed(1)}°C'
                    : 'N/A',
                subtext: 'Average panel temperature',
                isWarning: false,
                valueColor: AppColors.secondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildTelemetryMetricTile(
                label: 'DC Output',
                value: (voltage == null && current == null)
                    ? 'N/A'
                    : '${voltage != null ? "${voltage.toStringAsFixed(3)} V" : "N/A"} · ${current != null ? "${(current * 1000).toStringAsFixed(1)} mA" : "N/A"}',
                subtext: elecSummary.isMultiPanelAverage
                    ? 'Avg of ${elecSummary.panelCount} panel peaks'
                    : 'Array electrical output',
                isWarning: false,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildTelemetryMetricTile(
                label: 'Active Power',
                value: power != null ? '${power.toStringAsFixed(3)} W' : 'N/A',
                subtext: elecSummary.isMultiPanelAverage
                    ? 'Avg of panel peaks (V × I)'
                    : ((voltage != null && current != null)
                        ? 'Calculated (V × I)'
                        : 'Yield output'),
                isWarning: false,
                valueColor: AppColors.primary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTelemetryMetricTile({
    required String label,
    required String value,
    required String subtext,
    bool isWarning = false,
    Color? valueColor,
    String? badge,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isWarning ? AppColors.errorBorder : AppColors.border,
          width: isWarning ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (badge != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: isWarning
                        ? AppColors.errorBackground
                        : AppColors.warningBackground,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      color: isWarning ? AppColors.error : AppColors.warning,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppTypography.h3.copyWith(
              color: valueColor ?? AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtext,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
              fontSize: 10.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// Compact status chip pill conforming to 8px radius design token
  Widget _buildStatusPill({
    required String label,
    required bool isPositive,
    required bool isWarning,
    required IconData icon,
  }) {
    final Color bg;
    final Color border;
    final Color fg;
    if (isPositive) {
      bg = AppColors.successBackground;
      border = AppColors.successBorder;
      fg = AppColors.success;
    } else if (isWarning) {
      bg = AppColors.warningBackground;
      border = AppColors.warningBorder;
      fg = AppColors.warning;
    } else {
      bg = AppColors.background;
      border = AppColors.border;
      fg = AppColors.textSecondary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fg,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTypography.chip.copyWith(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  /// Compact next inspection chip pill opening scan schedule modal on tap
  Widget _buildNextInspectionPill({
    required String label,
    required bool isScheduled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isScheduled
              ? AppColors.primarySoft.withValues(alpha: 0.35)
              : AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isScheduled
                ? AppColors.primary.withValues(alpha: 0.25)
                : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isScheduled
                  ? Icons.calendar_month_outlined
                  : Icons.schedule_rounded,
              size: 14,
              color: isScheduled ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTypography.chip.copyWith(
                fontSize: 11.5,
                fontWeight: isScheduled ? FontWeight.w600 : FontWeight.w500,
                color: isScheduled
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Detailed Technical Diagnostics Modal Bottom Sheet
  void _showDiagnosticsModal(
    BuildContext context,
    PvModule mod,
    DeviceStatus? status,
  ) {
    final limitsOk = status?.limitsCheckPassed == true;
    final thermalOk = status?.thermalSensorActive == true;
    final waterAvailable = status?.waterAvailable;
    final isOnline = status?.isOnline == true;
    final lastSyncDate = status?.lastPingAt ??
        status?.lastSeenAt ??
        status?.latestMeasurementAt;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
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
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Robot & Sensor Status',
                      style: AppTypography.h3,
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.of(modalCtx).pop(),
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Check the robot’s track sensors, thermal camera, water tank, and Wi-Fi.',
                  style: AppTypography.bodySmall,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _SensorHealthCard(
                        title: 'Track Sensors Ready',
                        subtitle: limitsOk
                            ? 'Position verified'
                            : 'Waiting for check',
                        icon: Icons.check_circle_outline_rounded,
                        isPositive: limitsOk,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SensorHealthCard(
                        title: 'Thermal Camera',
                        subtitle:
                            thermalOk ? 'Camera ready' : 'Waiting for robot',
                        icon: Icons.camera_alt_outlined,
                        isPositive: thermalOk,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _SensorHealthCard(
                        title: 'Water Tank',
                        subtitle: waterAvailable == true
                            ? 'Water ready'
                            : (waterAvailable == false
                                ? 'Tank empty / refill'
                                : 'Waiting for check'),
                        icon: Icons.water_drop_outlined,
                        isPositive: waterAvailable == true,
                        isWarning: waterAvailable == false,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SensorHealthCard(
                        title: 'Wi-Fi Connection',
                        subtitle: isOnline
                            ? (lastSyncDate != null
                                ? 'Connected (${_formatDateTime(DateTime.tryParse(lastSyncDate))})'
                                : 'Connected (Online)')
                            : 'Waiting for robot',
                        icon: isOnline
                            ? Icons.wifi_rounded
                            : Icons.wifi_off_rounded,
                        isPositive: isOnline,
                        isWarning: !isOnline,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.build_circle_outlined,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Run the full robot connection and safety checklist.',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.of(modalCtx).pop();
                          context.push(
                            '/modules/${mod.id}/device-verification',
                          );
                        },
                        child: Text(
                          'Run Check →',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Inspection Schedule & Previous Scans Modal Bottom Sheet
  void _showScanHistoryModal(
    BuildContext context,
    PvModule mod,
    DeviceStatus? status,
  ) {
    final nextScanStr = status?.nextInspectionAt ?? mod.nextInspectionAt;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalCtx) {
        return SafeArea(
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(modalCtx).size.height * 0.75,
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
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
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_month_rounded,
                          size: 20,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Inspection Schedule & History',
                          style: AppTypography.h3,
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.of(modalCtx).pop(),
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Automated periodic thermal inspection schedule calculated by the cleaning robot.',
                  style: AppTypography.bodySmall,
                ),
                const SizedBox(height: 16),

                // 1. Next Scheduled Scan Hero Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'NEXT SCHEDULED SCAN',
                            style: AppTypography.caption.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: nextScanStr != null ? AppColors.primarySoft : AppColors.warningBackground,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              nextScanStr != null ? 'PROGRAMMED' : 'AWAITING SYNC',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: nextScanStr != null ? AppColors.primary : AppColors.warning,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        nextScanStr != null
                            ? _formatReadableTimestamp(nextScanStr)
                            : 'Device has not reported scheduled scan yet',
                        style: AppTypography.h3.copyWith(
                          fontSize: 16,
                          color: nextScanStr != null ? AppColors.textPrimary : AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Periodic inspection interval: every ${mod.inspectionIntervalDays} day${mod.inspectionIntervalDays > 1 ? "s" : ""}.',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                Text(
                  'Previous Scans',
                  style: AppTypography.bodySmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),

                // 2. Previous Inspections List
                Expanded(
                  child: Consumer(
                    builder: (context, ref, _) {
                      final inspAsync = ref.watch(moduleInspectionsProvider(mod.id));
                      return inspAsync.when(
                        loading: () => const Center(
                          child: CircularProgressIndicator(),
                        ),
                        error: (err, _) => Center(
                          child: Text(
                            'Failed to load inspection history: $err',
                            style: AppTypography.caption.copyWith(color: AppColors.error),
                          ),
                        ),
                        data: (inspections) {
                          if (inspections.isEmpty) {
                            return Center(
                              child: Text(
                                'No previous inspection scans recorded.',
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            );
                          }

                          return ListView.separated(
                            itemCount: inspections.length,
                            separatorBuilder: (context, index) => const Divider(height: 1),
                            itemBuilder: (ctx, index) {
                              final insp = inspections[index];
                              final isCompleted = insp.status == 'completed';
                              final hasBaseline = insp.baselineTemperatureC != null && insp.baselineTemperatureC! > 0;
                              final scanDate = insp.finishedAt ?? insp.startedAt ?? insp.scheduledFor;

                              return ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                leading: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: isCompleted ? AppColors.successBackground : AppColors.warningBackground,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    isCompleted ? Icons.check_circle_outline_rounded : Icons.pending_outlined,
                                    size: 18,
                                    color: isCompleted ? AppColors.success : AppColors.warning,
                                  ),
                                ),
                                title: Text(
                                  insp.type == 'verification'
                                      ? 'Post-Cleaning Verification'
                                      : 'Periodic Routine Scan',
                                  style: AppTypography.bodySmall.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  '${_formatReadableTimestamp(scanDate)}${hasBaseline ? " · Normal: ${insp.baselineTemperatureC!.toStringAsFixed(1)}°C" : ""}',
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.textSecondary,
                                    fontSize: 11,
                                  ),
                                ),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isCompleted ? AppColors.successBackground : AppColors.surface,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: isCompleted ? AppColors.successBorder : AppColors.border,
                                    ),
                                  ),
                                  child: Text(
                                    insp.status.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: isCompleted ? AppColors.success : AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Module Info Collapsible Card / Accordion
  Widget _buildModuleInfoCard(PvModule mod, ModuleDetails details, DeviceStatus? deviceStatus) {
    final perms = mod.permissions;

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
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _infoExpanded = !_infoExpanded),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Header Row: MODULE OVERVIEW + Status Badge + [Spacer] + Sensor Button + Chevron
                  Row(
                    children: [
                      Text(
                        'MODULE OVERVIEW',
                        style: AppTypography.caption.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.7,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ModuleMonitoringStatusBadge(
                        status: mod.monitoringStatus,
                      ),
                      const Spacer(),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _showDiagnosticsModal(
                          context,
                          mod,
                          deviceStatus,
                        ),
                        child: Tooltip(
                          message: 'Robot & Sensor Status',
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.primarySoft.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppColors.primary.withValues(alpha: 0.25),
                              ),
                            ),
                            child: const Icon(
                              Icons.sensors_rounded,
                              size: 16,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        _infoExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    mod.name,
                    style: AppTypography.h3,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'MAC: ${mod.macAddress} · Serial: ${mod.id.length > 8 ? mod.id.substring(0, 8) : mod.id}',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _buildStatusPill(
                        label: (deviceStatus?.isOnline == true)
                            ? 'Robot Online'
                            : 'Robot Offline',
                        isPositive: deviceStatus?.isOnline == true,
                        isWarning: deviceStatus?.isOnline != true,
                        icon: (deviceStatus?.isOnline == true)
                            ? Icons.wifi_rounded
                            : Icons.wifi_off_rounded,
                      ),
                      if (deviceStatus?.resetPending == true ||
                          ((deviceStatus?.firmwareState ?? mod.firmwareState) !=
                                  null &&
                              (deviceStatus?.firmwareState ??
                                      mod.firmwareState)!
                                  .trim()
                                  .isNotEmpty))
                        FirmwareStateBadge(
                          firmwareState: deviceStatus?.resetPending == true
                              ? 'RESET_REQUESTED'
                              : (deviceStatus?.firmwareState ??
                                  mod.firmwareState),
                          firmwareStateDetail: deviceStatus?.resetPending == true
                              ? null
                              : (deviceStatus?.firmwareStateDetail ??
                                  mod.firmwareStateDetail),
                        ),
                      _buildStatusPill(
                        label: deviceStatus?.waterAvailable == true
                            ? 'Water OK'
                            : (deviceStatus?.waterAvailable == false
                                ? 'Low Water'
                                : 'Water Unknown'),
                        isPositive: deviceStatus?.waterAvailable == true,
                        isWarning: deviceStatus?.waterAvailable == false,
                        icon: Icons.water_drop_outlined,
                      ),
                      if (mod.isPendingConfiguration ||
                          mod.latitude == null ||
                          mod.longitude == null)
                        _buildNextInspectionPill(
                          label: _formatNextInspectionLabel(
                            deviceStatus?.nextInspectionAt ??
                                mod.nextInspectionAt,
                            isPendingManual:
                                deviceStatus?.manualInspectionPending == true,
                          ),
                          isScheduled: deviceStatus?.manualInspectionPending ==
                                  true ||
                              (deviceStatus?.nextInspectionAt ??
                                      mod.nextInspectionAt) !=
                                  null,
                          onTap: () => _showScanHistoryModal(
                            context,
                            mod,
                            deviceStatus,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_infoExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Identity / Installation Details
                  Text(
                    'Identity & Location',
                    style: AppTypography.bodySmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _MetadataRow(
                    icon: Icons.tag_outlined,
                    label: 'Serial ID',
                    value: mod.id,
                    isMono: true,
                  ),
                  const SizedBox(height: 8),
                  _MetadataRow(
                    icon: Icons.memory_outlined,
                    label: 'MAC Address',
                    value: mod.macAddress,
                    isMono: true,
                  ),
                  const SizedBox(height: 8),
                  _MetadataRow(
                    icon: Icons.location_on_outlined,
                    label: 'Coordinates',
                    value: mod.latitude != null && mod.longitude != null
                        ? '${mod.latitude!.toStringAsFixed(5)}°, ${mod.longitude!.toStringAsFixed(5)}°'
                        : 'Not configured',
                    isMono: mod.latitude != null,
                  ),
                  const SizedBox(height: 8),
                  _MetadataRow(
                    icon: Icons.terrain_outlined,
                    label: 'Elevation',
                    value: mod.elevationM != null
                        ? '${mod.elevationM!.toStringAsFixed(1)} m'
                        : 'Not configured',
                    isMono: mod.elevationM != null,
                  ),
                  const SizedBox(height: 8),
                  _MetadataRow(
                    icon: Icons.engineering_outlined,
                    label: 'Installer',
                    value: '${mod.installerName} (${mod.installerEmail})',
                  ),
                  const SizedBox(height: 8),
                  _MetadataRow(
                    icon: Icons.verified_user_outlined,
                    label: 'Your Access',
                    value: mod.relationshipLabel,
                  ),
                  const SizedBox(height: 8),
                  _MetadataRow(
                    icon: Icons.event_available_outlined,
                    label: 'Configured',
                    value: _formatDate(mod.configuredAt),
                    isMono: mod.configuredAt != null,
                  ),

                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 16),

                  // Geometry Summary
                  Text(
                    'PV Panel Geometry',
                    style: AppTypography.bodySmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _MetadataRow(
                    icon: Icons.straighten_outlined,
                    label: 'Dimensions',
                    value: mod.panelLengthCm != null &&
                            mod.panelWidthCm != null
                        ? '${mod.panelLengthCm!.toStringAsFixed(1)} × ${mod.panelWidthCm!.toStringAsFixed(1)} cm'
                        : 'Not configured',
                    isMono: mod.panelLengthCm != null,
                  ),
                  const SizedBox(height: 8),
                  _MetadataRow(
                    icon: Icons.grid_view_outlined,
                    label: 'Panel Count',
                    value: mod.panelCount != null
                        ? '${mod.panelCount} ${mod.panelCount == 1 ? "panel" : "panels"}'
                        : 'Not configured',
                    isMono: mod.panelCount != null,
                  ),
                  const SizedBox(height: 8),
                  _MetadataRow(
                    icon: Icons.space_bar_outlined,
                    label: 'Spacing',
                    value: mod.panelSpacingCm != null
                        ? '${mod.panelSpacingCm!.toStringAsFixed(1)} cm'
                        : 'Not configured',
                    isMono: mod.panelSpacingCm != null,
                  ),
                  const SizedBox(height: 8),
                  _MetadataRow(
                    icon: Icons.architecture_outlined,
                    label: 'Tilt Angle',
                    value: mod.tiltDeg != null
                        ? '${mod.tiltDeg!.toStringAsFixed(1)}° (${(mod.tiltSource ?? "manual").toUpperCase()})'
                        : 'Not configured',
                    isMono: mod.tiltDeg != null,
                  ),
                  const SizedBox(height: 8),
                  _MetadataRow(
                    icon: Icons.explore_outlined,
                    label: 'Azimuth',
                    value: mod.azimuthDeg != null
                        ? '${mod.azimuthDeg!.toStringAsFixed(1)}° (${(mod.azimuthSource ?? "manual").toUpperCase()})'
                        : 'Not configured',
                    isMono: mod.azimuthDeg != null,
                  ),
                  const SizedBox(height: 8),
                  _MetadataRow(
                    icon: Icons.wb_sunny_outlined,
                    label: 'Min Solar Angle',
                    value: mod.minimumSolarAngleDeg != null
                        ? '${mod.minimumSolarAngleDeg!.toStringAsFixed(1)}°'
                        : 'Not configured',
                    isMono: mod.minimumSolarAngleDeg != null,
                  ),
                  const SizedBox(height: 8),
                  _MetadataRow(
                    icon: Icons.update_outlined,
                    label: 'Scan Interval',
                    value:
                        'Every ${mod.inspectionIntervalDays} ${mod.inspectionIntervalDays == 1 ? "day" : "days"}',
                    isMono: true,
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => _showScanHistoryModal(context, mod, deviceStatus),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.calendar_month_outlined,
                            size: 16,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Next Scan',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            (deviceStatus?.nextInspectionAt ?? mod.nextInspectionAt) != null
                                ? _formatReadableTimestamp(deviceStatus?.nextInspectionAt ?? mod.nextInspectionAt)
                                : 'Awaiting sync',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                              fontFamily: (deviceStatus?.nextInspectionAt ?? mod.nextInspectionAt) != null ? 'monospace' : null,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 10,
                            color: AppColors.primary,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (mod.reservoirNominalCapacityMl != null) ...[
                    const SizedBox(height: 8),
                    _MetadataRow(
                      icon: Icons.water_drop_outlined,
                      label: 'Water Tank',
                      value:
                          '${mod.reservoirNominalCapacityMl!.toStringAsFixed(0)} mL',
                      isMono: true,
                    ),
                  ],

                  // Responsible Managers & Manage Access Section inside Accordion
                  if (details.responsibleManagers.isNotEmpty ||
                      perms.canManageAccess) ...[
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Responsible Managers',
                          style: AppTypography.bodySmall.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (perms.canManageAccess)
                          InkWell(
                            onTap: () =>
                                context.push('/modules/${mod.id}/access'),
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              child: Text(
                                'Manage Access →',
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ...details.responsibleManagers.map(
                      (mgr) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.supervisor_account_outlined,
                              size: 18,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    mgr.name,
                                    style: AppTypography.body.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    mgr.email,
                                    style: AppTypography.caption,
                                  ),
                                ],
                              ),
                            ),
                            if (mgr.isDefaultManager)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primarySoft,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  'Default',
                                  style: AppTypography.chip.copyWith(
                                    fontSize: 10,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SensorHealthCard extends StatelessWidget {
  const _SensorHealthCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isPositive,
    this.isWarning = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool isPositive;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color border;
    Color accent;
    String badgeText;

    if (isPositive) {
      bg = AppColors.successBackground;
      border = AppColors.successBorder;
      accent = AppColors.success;
      badgeText = 'OK';
    } else if (isWarning) {
      bg = AppColors.warningBackground;
      border = AppColors.warningBorder;
      accent = AppColors.warning;
      badgeText = 'WARN';
    } else {
      bg = AppColors.errorBackground;
      border = AppColors.errorBorder;
      accent = AppColors.error;
      badgeText = 'FAIL';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: border),
                ),
                child: Icon(icon, size: 18, color: accent),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    color: accent,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption.copyWith(
              fontSize: 10.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isMono = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isMono;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: isMono
                ? AppTypography.dataValue.copyWith(fontSize: 12.5)
                : AppTypography.bodySmall.copyWith(fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _HeroMetricItem extends StatelessWidget {
  const _HeroMetricItem({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTypography.dataValue.copyWith(
            color: valueColor ?? AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _TargetXPositionDialog extends StatefulWidget {
  const _TargetXPositionDialog({
    required this.title,
    this.description,
    required this.confirmLabel,
    required this.mod,
    this.initialXCm,
  });

  final String title;
  final String? description;
  final String confirmLabel;
  final PvModule mod;
  final double? initialXCm;

  @override
  State<_TargetXPositionDialog> createState() => _TargetXPositionDialogState();
}

class _TargetXPositionDialogState extends State<_TargetXPositionDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialXCm != null
          ? widget.initialXCm!.toStringAsFixed(1)
          : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final mod = widget.mod;
    final hasConfiguredLength =
        mod.panelLengthCm != null && mod.panelLengthCm! > 0;
    final maxRailCm = hasConfiguredLength ? mod.calculatedTotalLengthCm : null;

    final parsed = double.tryParse(
      _controller.text.trim().replaceAll(',', '.'),
    );
    if (parsed == null || !parsed.isFinite || parsed < 0) {
      setState(() {
        _errorText = 'Enter a valid non-negative number';
      });
      return;
    }
    if (maxRailCm != null && parsed > maxRailCm) {
      setState(() {
        _errorText = 'Must be between 0 and ${maxRailCm.toStringAsFixed(1)} cm';
      });
      return;
    }
    if (hasConfiguredLength &&
        mod.panelCount != null &&
        mod.panelCount! > 1 &&
        mod.resolvePanelPosition(parsed).inGap) {
      setState(() {
        _errorText = 'Target falls inside an inter-panel gap';
      });
      return;
    }
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final mod = widget.mod;
    final hasConfiguredLength =
        mod.panelLengthCm != null && mod.panelLengthCm! > 0;
    final maxRailCm = hasConfiguredLength ? mod.calculatedTotalLengthCm : null;

    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.description != null) ...[
                Text(
                  widget.description!,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                key: const Key('target_x_position_field'),
                controller: _controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Target X Position (cm)',
                  hintText: maxRailCm != null
                      ? '0.0 – ${maxRailCm.toStringAsFixed(1)}'
                      : 'e.g. 120.5',
                  helperText: maxRailCm != null
                      ? 'Valid rail range: 0.0 to ${maxRailCm.toStringAsFixed(1)} cm'
                      : null,
                  errorText: _errorText,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('confirm_target_x_button'),
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
