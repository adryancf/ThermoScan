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
import 'package:thermoscan/features/modules/presentation/modules_controller.dart';
import 'package:thermoscan/features/modules/presentation/modules_home_screen.dart';
import 'package:thermoscan/features/modules/presentation/widgets/module_sub_nav_bar.dart';
import 'package:thermoscan/features/modules/presentation/widgets/radiometric_scan_card.dart';

/// SCR-10 & SCR-28: Module Overview & Client Email Notification Preferences
class ModuleOverviewScreen extends ConsumerStatefulWidget {
  const ModuleOverviewScreen({
    super.key,
    required this.moduleId,
  });

  final String moduleId;

  @override
  ConsumerState<ModuleOverviewScreen> createState() =>
      _ModuleOverviewScreenState();
}

class _ModuleOverviewScreenState extends ConsumerState<ModuleOverviewScreen> {
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
                'This action is irreversible. All administrative manager, technician, and client assignments for this module will be removed. Modules with operational history cannot be deleted.',
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
      final user = ref.read(authControllerProvider).user;
      context.go((user?.isManager ?? false) ? '/modules' : '/home');
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

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final detailsAsync = ref.watch(moduleDetailsProvider(widget.moduleId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: ThermoScanAppBar(
        title: 'Module Overview',
        role: user?.role ?? 'technician',
        showBack: true,
        onBack: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go((user?.isManager ?? false) ? '/modules' : '/home');
          }
        },
        trailingAction: detailsAsync.valueOrNull?.module.permissions.canDelete == true
            ? PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: AppColors.primary),
                tooltip: 'More actions',
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppColors.border),
                ),
                onSelected: (val) {
                  if (val == 'delete' && detailsAsync.valueOrNull != null) {
                    _confirmAndDeleteModule(detailsAsync.valueOrNull!.module.name);
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
        child: detailsAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
          error: (err, _) => Padding(
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
                    onPressed: () =>
                        ref.invalidate(moduleDetailsProvider(widget.moduleId)),
                  ),
                ],
              ),
            ),
          ),
          data: (details) {
            final mod = details.module;
            final perms = mod.permissions;
            final measurementsAsync = ref.watch(moduleMeasurementsProvider(mod.id));
            final latestMeasurement = measurementsAsync.valueOrNull?.isNotEmpty == true
                ? measurementsAsync.valueOrNull!.first
                : null;

            return Column(
              children: [
                ModuleSubNavBar(
                  moduleId: mod.id,
                  currentTab: 'overview',
                  canManageAccess: perms.canManageAccess,
                  isPendingConfig: mod.isPendingConfiguration,
                ),
                Expanded(
                  child: RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: () async {
                      ref.invalidate(moduleDetailsProvider(widget.moduleId));
                      ref.invalidate(moduleMeasurementsProvider(widget.moduleId));
                      await ref.read(moduleDetailsProvider(widget.moduleId).future);
                    },
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 48),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                    // 1. Pending Configuration Banner (SCR-16 draft resume)
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
                                onPressed: () => context
                                    .push('/modules/${mod.id}/install'),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // 2. Module Header Card
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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'MODULE OVERVIEW',
                                      style: AppTypography.caption.copyWith(
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.7,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      mod.name,
                                      style: AppTypography.h2,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              ModuleMonitoringStatusBadge(
                                status: mod.monitoringStatus,
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          const Divider(height: 1),
                          const SizedBox(height: 14),
                          _MetadataRow(
                            icon: Icons.memory_outlined,
                            label: 'MAC Address',
                            value: mod.macAddress,
                            isMono: true,
                          ),
                          const SizedBox(height: 10),
                          const _MetadataRow(
                            icon: Icons.wifi_off_outlined,
                            label: 'Device Status',
                            value: 'Offline (Awaiting ESP32 connection)',
                          ),
                          const SizedBox(height: 10),
                          _MetadataRow(
                            icon: Icons.engineering_outlined,
                            label: 'Installer',
                            value: '${mod.installerName} (${mod.installerEmail})',
                          ),
                          const SizedBox(height: 10),
                          _MetadataRow(
                            icon: Icons.verified_user_outlined,
                            label: 'Your Access',
                            value: mod.relationshipLabel,
                          ),
                          const SizedBox(height: 10),
                          _MetadataRow(
                            icon: Icons.event_available_outlined,
                            label: 'Configured',
                            value: _formatDate(mod.configuredAt),
                            isMono: mod.configuredAt != null,
                          ),
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.sensors_off_outlined,
                                  size: 18,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Embedded Device Offline — This module will transition to Online once the physical ESP32 connects and syncs.',
                                        style: AppTypography.caption,
                                      ),
                                      const SizedBox(height: 6),
                                      InkWell(
                                        onTap: () => context.push(
                                          '/modules/${mod.id}/handshake',
                                        ),
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
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Radiometric Scan & Thermal Matrix (SCR-10)
                    if (!mod.isPendingConfiguration) ...[
                      RadiometricScanCard(
                        module: mod,
                        latestMeasurement: latestMeasurement,
                      ),
                      const SizedBox(height: 14),

                      // Telemetry & Cleanings Shortcuts
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => context.push(
                                '/modules/${mod.id}/measurements',
                              ),
                              icon: const Icon(
                                Icons.show_chart_rounded,
                                size: 18,
                              ),
                              label: const Text('Measurements'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                side: const BorderSide(color: AppColors.border),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => context.push(
                                '/modules/${mod.id}/cleanings',
                              ),
                              icon: const Icon(
                                Icons.wash_rounded,
                                size: 18,
                              ),
                              label: const Text('Cleanings'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                side: const BorderSide(color: AppColors.border),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],

                    // 3. Quick Action Buttons (SCR-13 & SCR-14)
                    if (!mod.isPendingConfiguration) ...[
                      PrimaryButton(
                        label: perms.canEditAnyField
                            ? 'Module Configuration & Interval Log'
                            : 'View Configuration & Interval Log',
                        icon: Icons.tune_outlined,
                        onPressed: () =>
                            context.push('/modules/${mod.id}/configuration'),
                      ),
                      if (perms.canManageAccess) const SizedBox(height: 10),
                    ],
                    if (perms.canManageAccess) ...[
                      SecondaryButton(
                        label: 'Manage Access & Responsible Managers',
                        icon: Icons.admin_panel_settings_outlined,
                        onPressed: () =>
                            context.push('/modules/${mod.id}/access'),
                      ),
                    ],
                    const SizedBox(height: 20),

                    // 4. Photovoltaic Array & Inspection Schedule
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
                            'Array & Inspection Schedule',
                            style: AppTypography.h3,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Physical string geometry and scheduled scan parameters.',
                            style: AppTypography.bodySmall,
                          ),
                          const SizedBox(height: 14),
                          const Divider(height: 1),
                          const SizedBox(height: 14),
                          _MetadataRow(
                            icon: Icons.straighten_outlined,
                            label: 'Panel Size',
                            value: mod.panelLengthCm != null &&
                                    mod.panelWidthCm != null
                                ? '${mod.panelLengthCm!.toStringAsFixed(1)} × ${mod.panelWidthCm!.toStringAsFixed(1)} cm'
                                : 'Not configured',
                            isMono: mod.panelLengthCm != null,
                          ),
                          const SizedBox(height: 10),
                          _MetadataRow(
                            icon: Icons.grid_view_outlined,
                            label: 'Panels in String',
                            value: mod.panelCount != null
                                ? '${mod.panelCount} panels'
                                : 'Not configured',
                            isMono: mod.panelCount != null,
                          ),
                          const SizedBox(height: 10),
                          _MetadataRow(
                            icon: Icons.space_bar_outlined,
                            label: 'Panel Spacing',
                            value: mod.panelSpacingCm != null
                                ? '${mod.panelSpacingCm!.toStringAsFixed(1)} cm'
                                : 'Not configured',
                            isMono: mod.panelSpacingCm != null,
                          ),
                          const SizedBox(height: 10),
                          _MetadataRow(
                            icon: Icons.wb_sunny_outlined,
                            label: 'Min Solar Angle',
                            value: mod.minimumSolarAngleDeg != null
                                ? '${mod.minimumSolarAngleDeg!.toStringAsFixed(1)}°'
                                : 'Not configured',
                            isMono: mod.minimumSolarAngleDeg != null,
                          ),
                          const SizedBox(height: 10),
                          _MetadataRow(
                            icon: Icons.update_outlined,
                            label: 'Scan Interval',
                            value:
                                'Every ${mod.inspectionIntervalDays} ${mod.inspectionIntervalDays == 1 ? 'day' : 'days'}',
                            isMono: true,
                          ),
                          if (mod.reservoirNominalCapacityMl != null) ...[
                            const SizedBox(height: 10),
                            _MetadataRow(
                              icon: Icons.water_drop_outlined,
                              label: 'Nominal Reservoir',
                              value:
                                  '${mod.reservoirNominalCapacityMl!.toStringAsFixed(0)} mL (descriptive)',
                              isMono: true,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 5. Location & Surface Orientation
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
                            'Site Location & Orientation',
                            style: AppTypography.h3,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Coordinates and panel surface alignment relative to true north.',
                            style: AppTypography.bodySmall,
                          ),
                          const SizedBox(height: 14),
                          const Divider(height: 1),
                          const SizedBox(height: 14),
                          _MetadataRow(
                            icon: Icons.location_on_outlined,
                            label: 'Coordinates',
                            value: mod.latitude != null && mod.longitude != null
                                ? '${mod.latitude!.toStringAsFixed(5)}°, ${mod.longitude!.toStringAsFixed(5)}°'
                                : 'Not configured',
                            isMono: mod.latitude != null,
                          ),
                          const SizedBox(height: 10),
                          _MetadataRow(
                            icon: Icons.terrain_outlined,
                            label: 'Elevation',
                            value: mod.elevationM != null
                                ? '${mod.elevationM!.toStringAsFixed(1)} m'
                                : 'Not configured',
                            isMono: mod.elevationM != null,
                          ),
                          const SizedBox(height: 10),
                          _MetadataRow(
                            icon: Icons.explore_outlined,
                            label: 'Azimuth',
                            value: mod.azimuthDeg != null
                                ? '${mod.azimuthDeg!.toStringAsFixed(1)}° (${(mod.azimuthSource ?? 'manual').toUpperCase()})'
                                : 'Not configured',
                            isMono: mod.azimuthDeg != null,
                          ),
                          const SizedBox(height: 10),
                          _MetadataRow(
                            icon: Icons.architecture_outlined,
                            label: 'Tilt Angle',
                            value: mod.tiltDeg != null
                                ? '${mod.tiltDeg!.toStringAsFixed(1)}° (${(mod.tiltSource ?? 'manual').toUpperCase()})'
                                : 'Not configured',
                            isMono: mod.tiltDeg != null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 6. Responsible Managers Card
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
                            'Responsible Managers',
                            style: AppTypography.h3,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Company Managers responsible for supervising this module.',
                            style: AppTypography.bodySmall,
                          ),
                          const SizedBox(height: 12),
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                        borderRadius:
                                            BorderRadius.circular(999),
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
                      ),
                    ),

                    // 7. SCR-28: Client Operational Email Notification Preferences
                    if (mod.userRelationship == 'assigned_client') ...[
                      const SizedBox(height: 16),
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
                            const Divider(height: 16),
                            Row(
                              children: [
                                const Icon(
                                  Icons.info_outline,
                                  size: 16,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Inspection interval change emails cannot be disabled.',
                                    style: AppTypography.caption,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    },
        ),
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
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        SizedBox(
          width: 118,
          child: Text(
            label,
            style: AppTypography.bodySmall,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: isMono
                ? AppTypography.dataValue.copyWith(fontSize: 13)
                : AppTypography.body.copyWith(fontSize: 14),
          ),
        ),
      ],
    );
  }
}
