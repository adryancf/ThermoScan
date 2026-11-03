import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:thermoscan/core/network/api_exception.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/core/widgets/app_buttons.dart';
import 'package:thermoscan/core/widgets/top_app_bar.dart';
import 'package:thermoscan/features/auth/presentation/auth_controller.dart';
import 'package:thermoscan/features/modules/data/module_repository.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';
import 'package:thermoscan/features/modules/presentation/module_cleanings_screen.dart';
import 'package:thermoscan/features/modules/presentation/module_configuration_screen.dart';
import 'package:thermoscan/features/modules/presentation/module_measurements_screen.dart';
import 'package:thermoscan/features/modules/presentation/modules_controller.dart';
import 'package:thermoscan/features/modules/presentation/modules_home_screen.dart';
import 'package:thermoscan/features/modules/presentation/widgets/radiometric_scan_card.dart';

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
                trailingAction: perms.canDelete
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
                          if (val == 'delete') {
                            _confirmAndDeleteModule(mod.name);
                          }
                        },
                        itemBuilder: (ctx) => [
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
                          // Tab 1: Visão Geral
                          _buildOverviewTab(context, mod, details, deviceStatus),
                          // Tab 2: Medições
                          ModuleMeasurementsView(moduleId: mod.id),
                          // Tab 3: Limpezas
                          ModuleCleaningsView(moduleId: mod.id),
                          // Tab 4: Configuração (if not pending)
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
    final latestMeasurement =
        measurementsAsync.valueOrNull?.isNotEmpty == true
            ? measurementsAsync.valueOrNull!.first
            : null;
    final thermalMapAsync = ref.watch(moduleThermalMapProvider(mod.id));
    final thermalMap = thermalMapAsync.valueOrNull;

    // Resolve configuration sync info
    final syncInfo = deviceStatus?.effectiveConfigurationSync ??
        details.effectiveConfigurationSync ??
        mod.configurationSync ??
        (mod.isPendingConfiguration
            ? const ConfigurationSyncInfo(
                state: 'pending',
                configVersion: 1,
                configAppliedVersion: 0,
              )
            : ConfigurationSyncInfo(
                state: 'synced',
                configVersion: 1,
                configAppliedVersion: 1,
                configAppliedAt: mod.configuredAt != null
                    ? DateTime.tryParse(mod.configuredAt!)
                    : null,
              ));

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        ref.invalidate(moduleDetailsProvider(widget.moduleId));
        ref.invalidate(moduleDeviceStatusProvider(widget.moduleId));
        ref.invalidate(moduleMeasurementsProvider(widget.moduleId));
        ref.invalidate(moduleThermalMapProvider(widget.moduleId));
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

            // 2. Configuration Sync Status Chip/Card
            _buildConfigurationSyncCard(syncInfo),
            const SizedBox(height: 16),

            // 3. 2x2 Sensor Health Grid
            _buildSensorHealthGrid(deviceStatus),
            const SizedBox(height: 16),

            // 4. Module Info Collapsible Card / Accordion
            _buildModuleInfoCard(mod, details),
            const SizedBox(height: 16),

            // 5. Hardware Handshake Shortcut
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
                      Icons.handshake_outlined,
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
                          'ESP32 Hardware Handshake',
                          style: AppTypography.bodySmall.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Safety interlocks & Wi-Fi checklist',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        context.push('/modules/${mod.id}/handshake'),
                    child: Text(
                      'Verify Hardware Handshake →',
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

            // 6. Radiometric Scan & Thermal Matrix (SCR-10)
            if (!mod.isPendingConfiguration) ...[
              RadiometricScanCard(
                module: mod,
                latestMeasurement: latestMeasurement,
                thermalMap: thermalMap,
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

  /// Configuration Sync Status Chip/Card
  Widget _buildConfigurationSyncCard(ConfigurationSyncInfo syncInfo) {
    final state = syncInfo.state;
    final v = syncInfo.configVersion;

    Color bg;
    Color border;
    Color iconColor;
    IconData icon;
    String message;

    if (state == 'synced') {
      bg = AppColors.successBackground;
      border = AppColors.successBorder;
      iconColor = AppColors.success;
      icon = Icons.check_circle_outline_rounded;
      final dateStr = _formatDateTime(syncInfo.configAppliedAt);
      message = 'Configuration v$v synced to ESP32 on $dateStr';
    } else if (state == 'failed') {
      bg = AppColors.errorBackground;
      border = AppColors.errorBorder;
      iconColor = AppColors.error;
      icon = Icons.error_outline_rounded;
      final err = syncInfo.configApplyError ?? 'unknown error';
      message = 'Failed to apply configuration v$v: $err';
    } else {
      bg = AppColors.warningBackground;
      border = AppColors.warningBorder;
      iconColor = AppColors.warning;
      icon = Icons.access_time_rounded;
      message = 'Configuration v$v pending sync on device';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodySmall.copyWith(
                color: iconColor,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 2x2 Sensor Health Grid
  Widget _buildSensorHealthGrid(DeviceStatus? status) {
    final limitsOk = status?.limitsCheckPassed == true;
    final thermalOk = status?.thermalSensorActive == true;
    final waterAvailable = status?.waterAvailable;
    final isOnline = status?.isOnline == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Sensor Health & Diagnostics',
              style: AppTypography.h3.copyWith(fontSize: 15),
            ),
            Text(
              'Live 2×2 Telemetry',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _SensorHealthCard(
                title: 'Limits Check Passed',
                subtitle: limitsOk ? 'Microswitches homed' : 'Awaiting homing',
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
                        ? 'Insufficient level'
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
                    ? 'Connected (Online)'
                    : 'Awaiting ping',
                icon: isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                isPositive: isOnline,
                isWarning: !isOnline,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Module Info Collapsible Card / Accordion
  Widget _buildModuleInfoCard(PvModule mod, ModuleDetails details) {
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
