import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:thermoscan/core/network/api_exception.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/core/widgets/app_buttons.dart';
import 'package:thermoscan/core/widgets/top_app_bar.dart';
import 'package:thermoscan/features/alerts/presentation/alerts_controller.dart';
import 'package:thermoscan/features/auth/presentation/auth_controller.dart';
import 'package:thermoscan/features/modules/data/module_repository.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';
import 'package:thermoscan/features/modules/presentation/module_cleanings_screen.dart';
import 'package:thermoscan/features/modules/presentation/module_configuration_screen.dart';
import 'package:thermoscan/features/modules/presentation/module_measurements_screen.dart';
import 'package:thermoscan/features/modules/presentation/modules_controller.dart';
import 'package:thermoscan/features/modules/presentation/modules_home_screen.dart';
import 'package:thermoscan/features/modules/presentation/widgets/clean_thermal_preview_card.dart';
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

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return 'recent';
    final d = dt.toLocal();
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    final year = d.year;
    final hour = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$min';
  }

  String _formatReadableTimestamp(String? iso) {
    if (iso == null || iso.isEmpty) return 'Recent';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;

    final now = DateTime.now();
    final isToday =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;

    final hour12 = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final minuteStr = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '$hour12:$minuteStr $ampm';

    if (isToday) {
      return 'Today at $timeStr';
    }
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
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} at $timeStr';
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final detailsAsync = ref.watch(moduleDetailsProvider(widget.moduleId));
    final deviceStatusAsync =
        ref.watch(moduleDeviceStatusProvider(widget.moduleId));

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
                title: 'Module Overview',
                role: user?.role ?? 'technician',
                showBack: true,
                onBack: () => context.go('/modules'),
                trailingAction: (perms.canDelete || !mod.isPendingConfiguration)
                    ? PopupMenuButton<String>(
                        icon: const Icon(
                          Icons.more_vert,
                          color: AppColors.primary,
                        ),
                        tooltip: 'More actions',
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: AppColors.border),
                        ),
                        onSelected: (val) {
                          if (val == 'trigger_scan') {
                            _triggerManualScan(mod.id);
                          } else if (val == 'delete') {
                            _confirmAndDeleteModule(mod.name);
                          }
                        },
                        itemBuilder: (ctx) => [
                          if (!mod.isPendingConfiguration)
                            PopupMenuItem<String>(
                              value: 'trigger_scan',
                              enabled: !_isTriggeringInspection,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.radar_rounded,
                                    size: 18,
                                    color: _isTriggeringInspection
                                        ? AppColors.textSecondary
                                        : AppColors.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _isTriggeringInspection
                                        ? 'Sending Scan Request...'
                                        : 'Trigger Inspection Scan',
                                    style: TextStyle(
                                      color: _isTriggeringInspection
                                          ? AppColors.textSecondary
                                          : AppColors.textPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (perms.canDelete)
                            const PopupMenuItem<String>(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.delete_forever_outlined,
                                    size: 18,
                                    color: AppColors.error,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Delete Module',
                                    style: TextStyle(
                                      color: AppColors.error,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      )
                    : null,
              ),
              body: SafeArea(
                child: Column(
                  children: [
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

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        ref.invalidate(moduleDetailsProvider(widget.moduleId));
        ref.invalidate(moduleDeviceStatusProvider(widget.moduleId));
        ref.invalidate(moduleMeasurementsProvider(widget.moduleId));
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

            // 2. Executive Health Hero Banner
            _buildExecutiveHealthBanner(
              mod: mod,
              deviceStatus: deviceStatus,
              latestInspection: latestInspection,
              latestMeasurement: latestMeasurement,
              measurements: currentMeasurements,
            ),
            const SizedBox(height: 16),

            // 2.1 Hotspot Cleaning Status Card (when hotspot or cleaning pending/recent)
            _buildCleaningStatusCard(
              mod: mod,
              deviceStatus: deviceStatus,
              latestInspection: latestInspection,
            ),

            // 3. Compact Hardware & Robot Status Summary
            _buildHardwareStatusSummary(mod, deviceStatus),
            const SizedBox(height: 16),

            // 4. Module Info Collapsible Card / Accordion
            _buildModuleInfoCard(mod, details, deviceStatus),
            const SizedBox(height: 16),

            // 5. Device Verification Shortcut
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.verified_outlined,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ESP32 Device Verification',
                          style: AppTypography.bodySmall.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Safety interlocks & connection diagnostics',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        context.push('/modules/${mod.id}/device-verification'),
                    child: Text(
                      'Verify Hardware →',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 6. Clean Thermal Preview Card & Key Telemetry Metrics (SCR-10)
            if (!mod.isPendingConfiguration) ...[
              CleanThermalPreviewCard(
                module: mod,
                latestMeasurement: latestMeasurement,
                latestInspection: latestInspection,
                measurements: measurementsAsync.valueOrNull,
              ),
              const SizedBox(height: 16),
              _buildKeyTelemetryGrid(
                mod: mod,
                latestMeasurement: latestMeasurement,
                latestInspection: latestInspection,
                measurements: currentMeasurements,
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

  /// Executive Health Hero Banner
  /// Communicates array health verdict to clients within 3 seconds.
  /// Strict relative threshold: baseline + 10°C or confirmed inspection anomaly.
  Widget _buildExecutiveHealthBanner({
    required PvModule mod,
    required DeviceStatus? deviceStatus,
    required LatestInspection? latestInspection,
    required ModuleMeasurement? latestMeasurement,
    required List<ModuleMeasurement> measurements,
  }) {
    final confirmedAnomalies = latestInspection?.confirmedAnomalies ?? const [];
    final hasHotspot = confirmedAnomalies.isNotEmpty;
    final hasTelemetry = latestInspection != null ||
        latestMeasurement != null ||
        measurements.isNotEmpty;

    final double? baseline = latestInspection?.inspection.baselineTemperatureC;
    double? peakTemp;
    if (measurements.isNotEmpty) {
      peakTemp = measurements
          .map((m) => m.maxTemperatureC)
          .reduce((a, b) => a > b ? a : b);
    } else if (latestMeasurement != null) {
      peakTemp = latestMeasurement.maxTemperatureC;
    }

    final double? delta = (peakTemp != null && baseline != null)
        ? (peakTemp - baseline)
        : null;

    final String title;
    final String subtitle;
    final String badgeText;
    final Color statusColor;
    final Color badgeBg;
    final Color badgeBorder;
    final IconData heroIcon;

    if (hasHotspot) {
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
            '$sign${delta.toStringAsFixed(1)}°C above baseline (${baseline.toStringAsFixed(1)}°C). Robot cleaning recommended.';
      } else if (baseline != null) {
        subtitle =
            'Anomaly exceeds baseline (${baseline.toStringAsFixed(1)}°C). Robot cleaning recommended.';
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
            'All panels operating within normal baseline temperature (${baseline.toStringAsFixed(1)}°C). No hotspots detected.';
      } else {
        subtitle =
            'All panels operating within normal baseline temperature. No hotspots detected.';
      }

      badgeText = 'HEALTHY';
      statusColor = AppColors.success;
      badgeBg = AppColors.successBackground;
      badgeBorder = AppColors.successBorder;
      heroIcon = Icons.check_circle_outline_rounded;
    } else {
      title = 'Awaiting Initial Scan';
      subtitle =
          'Inspection scan will record baseline and thermal map on next robotic cycle.';
      badgeText = 'AWAITING SCAN';
      statusColor = AppColors.warning;
      badgeBg = AppColors.warningBackground;
      badgeBorder = AppColors.warningBorder;
      heroIcon = Icons.radar_rounded;
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
              latestInspection?.inspection.createdAt != null ||
              (deviceStatus?.nextInspectionAt ?? mod.nextInspectionAt) != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                if (latestMeasurement?.measuredAt != null ||
                    (measurements.isNotEmpty && measurements.first.measuredAt.isNotEmpty) ||
                    latestInspection?.inspection.createdAt != null)
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
                InkWell(
                  onTap: () => _showScanHistoryModal(context, mod, deviceStatus),
                  borderRadius: BorderRadius.circular(4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.event_repeat_rounded,
                        size: 13,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        (deviceStatus?.nextInspectionAt ?? mod.nextInspectionAt) != null
                            ? 'Next scan: ${_formatReadableTimestamp(deviceStatus?.nextInspectionAt ?? mod.nextInspectionAt)}'
                            : 'Scan history',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 9,
                        color: AppColors.primary,
                      ),
                    ],
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
                      label: 'Baseline',
                      value: '${baseline.toStringAsFixed(1)}°C',
                    ),
                  if (peakTemp != null)
                    _HeroMetricItem(
                      label: 'Peak Reading',
                      value: '${peakTemp.toStringAsFixed(1)}°C',
                    ),
                  if (delta != null)
                    _HeroMetricItem(
                      label: 'Relative Delta',
                      value:
                          '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}°C',
                      valueColor:
                          hasHotspot ? AppColors.error : AppColors.success,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Hotspot Cleaning Lifecycle Status Card
  /// Displayed when a hotspot is confirmed or a wash cycle is active/cooling down.
  Widget _buildCleaningStatusCard({
    required PvModule mod,
    required DeviceStatus? deviceStatus,
    required LatestInspection? latestInspection,
  }) {
    final cleaningsAsync = ref.watch(moduleCleaningsProvider(mod.id));
    final confirmedAnomalies = latestInspection?.confirmedAnomalies ?? const [];
    final hasHotspot = confirmedAnomalies.isNotEmpty;

    final cleanings = cleaningsAsync.valueOrNull ?? const <ModuleCleaning>[];
    final mostRecent = cleanings.isNotEmpty ? cleanings.first : null;
    final activeAnomalyIds =
        confirmedAnomalies.map((a) => a.sourceEventId).toSet();

    final isWaterLow = deviceStatus?.waterAvailable == false ||
        deviceStatus?.waterStatus == 'low' ||
        deviceStatus?.waterStatus == 'insufficient' ||
        (hasHotspot && mostRecent?.failureReason == 'insufficient_water');

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

    // Suppress card when array is healthy and no wash cycles are active or pending verification
    if (!hasHotspot && !isCleaningInProgress && !isCoolDownPending) {
      return const SizedBox.shrink();
    }

    final String statusBadge;
    final Color badgeColor;
    final Color badgeBg;
    final Color badgeBorder;
    final String cardTitle;
    final String cardDescription;
    final IconData cardIcon;

    if (isWaterLow) {
      statusBadge = 'LOW WATER';
      badgeColor = AppColors.warning;
      badgeBg = AppColors.warningBackground;
      badgeBorder = AppColors.warningBorder;
      cardTitle = 'Insufficient Water for Cleaning';
      cardDescription =
          'Robot reservoir requires refilling before localized washing of the detected hotspot can commence.';
      cardIcon = Icons.water_drop_outlined;
    } else if (isCleaningInProgress) {
      statusBadge = 'CLEANING IN PROGRESS';
      badgeColor = AppColors.primary;
      badgeBg = AppColors.primarySoft;
      badgeBorder = AppColors.primary.withValues(alpha: 0.3);
      cardTitle = 'Robotic Wash Cycle Active';
      cardDescription =
          'The autonomous robot is actively spraying the targeted panel area to clear surface soiling.';
      cardIcon = Icons.precision_manufacturing_rounded;
    } else if (isCoolDownPending) {
      statusBadge = 'COOL-DOWN (30M)';
      badgeColor = const Color(0xFF19B5D6);
      badgeBg = const Color(0xFFE0F7FA);
      badgeBorder = const Color(0xFFB2EBF2);
      cardTitle = 'Wash Completed — Thermal Cool-Down';
      cardDescription =
          'Localized cleaning completed. Awaiting 30-minute thermal cool-down before automated re-inspection scan.';
      cardIcon = Icons.hourglass_top_rounded;
    } else if (isPersistentHotspot) {
      statusBadge = 'PERSISTENT HOTSPOT';
      badgeColor = AppColors.error;
      badgeBg = AppColors.errorBackground;
      badgeBorder = AppColors.errorBorder;
      cardTitle = 'Persistent Thermal Anomaly';
      cardDescription =
          '3 robotic cleaning attempts have been executed. Hotspot persists; on-site technician inspection recommended.';
      cardIcon = Icons.handyman_outlined;
    } else {
      statusBadge = 'CLEANING SCHEDULED';
      badgeColor = AppColors.primary;
      badgeBg = AppColors.primarySoft;
      badgeBorder = AppColors.primary.withValues(alpha: 0.3);
      cardTitle = 'Automated Cleaning Scheduled';
      cardDescription =
          'Robot is primed with water available. Localized wash will trigger automatically during the next safe thermal window.';
      cardIcon = Icons.calendar_today_rounded;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: badgeBorder,
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
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: badgeBorder),
                      ),
                      child: Icon(cardIcon, color: badgeColor, size: 16),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Hotspot Cleaning Status',
                      style: AppTypography.caption.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: badgeBorder),
                  ),
                  child: Text(
                    statusBadge,
                    style: AppTypography.caption.copyWith(
                      color: badgeColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              cardTitle,
              style: AppTypography.bodySmall.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              cardDescription,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                final tabController = DefaultTabController.maybeOf(context);
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 4 Key Telemetry Metrics Grid (Flat, border-only, zero drop shadows)
  Widget _buildKeyTelemetryGrid({
    required PvModule mod,
    required ModuleMeasurement? latestMeasurement,
    required LatestInspection? latestInspection,
    required List<ModuleMeasurement> measurements,
  }) {
    final confirmedAnomalies = latestInspection?.confirmedAnomalies ?? const [];
    final hasConfirmedHotspots = confirmedAnomalies.isNotEmpty;

    final double? baselineTemp =
        latestInspection?.inspection.baselineTemperatureC;
    double? peakTemp;
    if (measurements.isNotEmpty) {
      peakTemp = measurements
          .map((m) => m.maxTemperatureC)
          .reduce((a, b) => a > b ? a : b);
    } else if (latestMeasurement != null) {
      peakTemp = latestMeasurement.maxTemperatureC;
    }

    final double? delta = (peakTemp != null && baselineTemp != null)
        ? (peakTemp - baselineTemp)
        : null;

    final voltage = latestMeasurement?.voltageV;
    final current = latestMeasurement?.currentA;
    final power = latestMeasurement?.powerW ??
        (voltage != null && current != null ? voltage * current : null);

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
                        ? 'Delta: +${delta.toStringAsFixed(1)}°C (Hotspot)'
                        : 'Hotspot confirmed')
                    : (delta != null
                        ? (delta >= 10.0
                            ? 'Delta: +${delta.toStringAsFixed(1)}°C (Elevated)'
                            : 'Nominal (+${delta.toStringAsFixed(1)}°C ΔT)')
                        : 'Nominal baseline curve'),
                isWarning: hasConfirmedHotspots,
                valueColor: hasConfirmedHotspots
                    ? AppColors.error
                    : AppColors.textPrimary,
                badge: hasConfirmedHotspots
                    ? 'HOTSPOT'
                    : (delta != null && delta >= 10.0 ? 'ELEVATED' : null),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildTelemetryMetricTile(
                label: 'Baseline Temperature',
                value: baselineTemp != null && baselineTemp > 0
                    ? '${baselineTemp.toStringAsFixed(1)}°C'
                    : 'N/A',
                subtext: 'Inspection reference baseline',
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
                    : '${voltage != null ? "${voltage.toStringAsFixed(1)} V" : "N/A"} · ${current != null ? "${current.toStringAsFixed(2)} A" : "N/A"}',
                subtext: 'Array electrical output',
                isWarning: false,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildTelemetryMetricTile(
                label: 'Active Power',
                value: power != null ? '${power.toStringAsFixed(1)} W' : 'N/A',
                subtext: (voltage != null && current != null)
                    ? 'Calculated (V × I)'
                    : 'Yield output',
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

  /// Compact Hardware & Robot Status Summary
  /// Clean, friendly, non-intimidating overview with in-line status badges
  /// and a subtle 'View Diagnostics' button for low-level technical telemetry.
  Widget _buildHardwareStatusSummary(PvModule mod, DeviceStatus? status) {
    final limitsOk = status?.limitsCheckPassed == true;
    final thermalOk = status?.thermalSensorActive == true;
    final waterAvailable = status?.waterAvailable;
    final isOnline = status?.isOnline == true;
    final sensorsReady = limitsOk && thermalOk;
    final lastSyncDate = status?.lastPingAt ??
        status?.lastSeenAt ??
        status?.latestMeasurementAt;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.precision_manufacturing_outlined,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Hardware & Robot Status',
                    style: AppTypography.bodySmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () {
                  ref.invalidate(moduleDeviceStatusProvider(widget.moduleId));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Querying ESP32 device status...'),
                      duration: Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.sync_rounded,
                        size: 14,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Refresh',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildStatusPill(
                label: isOnline ? 'Robot Online' : 'Robot Offline',
                isPositive: isOnline,
                isWarning: !isOnline,
                icon: isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
              ),
              _buildStatusPill(
                label: waterAvailable == true
                    ? 'Water Available'
                    : (waterAvailable == false
                        ? 'Low Reservoir'
                        : 'Water Unknown'),
                isPositive: waterAvailable == true,
                isWarning: waterAvailable == false,
                icon: Icons.water_drop_outlined,
              ),
              _buildStatusPill(
                label: sensorsReady ? 'Sensors Ready' : 'Sensors Pending',
                isPositive: sensorsReady,
                isWarning: !sensorsReady,
                icon: Icons.sensors_outlined,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  isOnline && lastSyncDate != null
                      ? 'Sync: ${_formatDateTime(DateTime.tryParse(lastSyncDate))}'
                      : (isOnline
                          ? 'Connected'
                          : 'Offline / awaiting heartbeat'),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () => _showDiagnosticsModal(context, mod, status),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'View Diagnostics',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 11,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ],
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
                      'Hardware & Sensor Diagnostics',
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
                  'Detailed microswitch limit state, thermal sensor health, and ESP32 connectivity.',
                  style: AppTypography.bodySmall,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _SensorHealthCard(
                        title: 'Limits Check Passed',
                        subtitle: limitsOk
                            ? 'Microswitches homed'
                            : 'Awaiting homing',
                        icon: Icons.check_circle_outline_rounded,
                        isPositive: limitsOk,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SensorHealthCard(
                        title: 'Thermal Sensor Active',
                        subtitle:
                            thermalOk ? 'MLX90640 active' : 'Sensor inactive',
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
                        title: 'Water Reservoir',
                        subtitle: waterAvailable == true
                            ? 'Sufficient level'
                            : (waterAvailable == false
                                ? 'Low reservoir level'
                                : 'Awaiting ping'),
                        icon: Icons.water_drop_outlined,
                        isPositive: waterAvailable == true,
                        isWarning: waterAvailable == false,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SensorHealthCard(
                        title: 'ESP32 Connectivity',
                        subtitle: isOnline
                            ? (lastSyncDate != null
                                ? 'Connected (${_formatDateTime(DateTime.tryParse(lastSyncDate))})'
                                : 'Connected (Online)')
                            : 'Awaiting ping',
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
                          'Carriage motion calibration & hardware interlocks wizard.',
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
                          'Open Wizard →',
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
                  'Automated periodic thermal inspection schedule calculated by the ESP32 robot.',
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
                                  '${_formatReadableTimestamp(scanDate)}${hasBaseline ? " · Baseline: ${insp.baselineTemperatureC!.toStringAsFixed(1)}°C" : ""}',
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
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                          ],
                        ),
                        const SizedBox(height: 4),
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
                      ],
                    ),
                  ),
                  Icon(
                    _infoExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.primary,
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
                        ? '${mod.panelCount} panels'
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
                    value: 'Every ${mod.inspectionIntervalDays} days',
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
                      label: 'Reservoir',
                      value:
                          '${mod.reservoirNominalCapacityMl!.toStringAsFixed(0)} mL (nominal)',
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
