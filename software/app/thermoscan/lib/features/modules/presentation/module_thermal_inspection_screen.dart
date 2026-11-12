import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/core/widgets/app_buttons.dart';
import 'package:thermoscan/core/widgets/status_chips.dart';
import 'package:thermoscan/core/widgets/top_app_bar.dart';
import 'package:thermoscan/features/auth/presentation/auth_controller.dart';
import 'package:thermoscan/features/modules/domain/inspection_routine_bundle.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';
import 'package:thermoscan/features/modules/presentation/modules_controller.dart';
import 'package:thermoscan/features/modules/presentation/widgets/radiometric_scan_card.dart';
import 'package:thermoscan/features/modules/presentation/widgets/thermal_panorama_painter.dart';

/// SCR-10 Dedicated Screen: Thermal Inspection Studio
///
/// Provides a dedicated workspace for high-resolution radiometric MLX90640 analysis,
/// thermal gradient exploration, multi-frame traversal (F1..Fn), and dual-frame anomaly confirmation.
class ModuleThermalInspectionScreen extends ConsumerStatefulWidget {
  const ModuleThermalInspectionScreen({
    super.key,
    required this.moduleId,
  });

  final String moduleId;

  @override
  ConsumerState<ModuleThermalInspectionScreen> createState() =>
      _ModuleThermalInspectionScreenState();
}

class _ModuleThermalInspectionScreenState
    extends ConsumerState<ModuleThermalInspectionScreen> {
  ModuleInspection? _selectedHistoricalInspection;

  String _formatIsoDate(String? iso) {
    if (iso == null || iso.isEmpty) return 'No timestamp';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final d = dt.toLocal();
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    final year = d.year;
    final hour = d.hour.toString().padLeft(2, '0');
    final minute = d.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  void _refreshAll() {
    ref.invalidate(moduleDetailsProvider(widget.moduleId));
    ref.invalidate(moduleMeasurementsProvider(widget.moduleId));
    ref.invalidate(latestInspectionProvider(widget.moduleId));
    ref.invalidate(moduleInspectionsProvider(widget.moduleId));
    ref.invalidate(moduleCleaningsProvider(widget.moduleId));
    if (_selectedHistoricalInspection != null) {
      ref.invalidate(
        inspectionMeasurementsPagedProvider((
          moduleId: widget.moduleId,
          inspectionId: _selectedHistoricalInspection!.id,
          page: 1,
          limit: 200,
          panelIndex: null,
        )),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final detailsAsync = ref.watch(moduleDetailsProvider(widget.moduleId));
    final measurementsAsync =
        ref.watch(moduleMeasurementsProvider(widget.moduleId));
    final latestInspectionAsync =
        ref.watch(latestInspectionProvider(widget.moduleId));
    final inspectionsAsync =
        ref.watch(moduleInspectionsProvider(widget.moduleId));
    final cleaningsAsync =
        ref.watch(moduleCleaningsProvider(widget.moduleId));

    final latestInspection = latestInspectionAsync.valueOrNull;
    final isViewingLatest = _selectedHistoricalInspection == null ||
        _selectedHistoricalInspection!.id == latestInspection?.inspection.id;

    final historicalPagedAsync = !isViewingLatest
        ? ref.watch(
            inspectionMeasurementsPagedProvider((
              moduleId: widget.moduleId,
              inspectionId: _selectedHistoricalInspection!.id,
              page: 1,
              limit: 200,
              panelIndex: null,
            )),
          )
        : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: ThermoScanAppBar(
        title: 'Thermal Inspection Studio',
        role: user?.role,
        showBack: true,
        onBack: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/modules/${widget.moduleId}');
          }
        },
        trailingAction: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: const Key('studio_help_button'),
              tooltip: 'How to Read This Thermal Map',
              icon: const Icon(
                Icons.help_outline_rounded,
                color: AppColors.primary,
              ),
              onPressed: () => _showTechnicalGuideModal(context),
            ),
            IconButton(
              tooltip: 'Refresh Studio Data',
              icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
              onPressed: _refreshAll,
            ),
          ],
        ),
      ),
      body: detailsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: AppColors.error,
                    size: 44,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Could Not Load Scan Data',
                    style: AppTypography.h3,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    err.toString(),
                    style: AppTypography.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  PrimaryButton(
                    label: 'Retry',
                    fullWidth: false,
                    onPressed: _refreshAll,
                  ),
                ],
              ),
            ),
          ),
        ),
        data: (details) {
          final mod = details.module;
          final rawInspections =
              inspectionsAsync.valueOrNull ?? const <ModuleInspection>[];
          final allCleanings =
              cleaningsAsync.valueOrNull ?? const <ModuleCleaning>[];
          final allMeasurements =
              measurementsAsync.valueOrNull ?? const <ModuleMeasurement>[];

          final bundles = InspectionRoutineBundle.buildBundles(
            allInspections: rawInspections,
            allCleanings: allCleanings,
            allMeasurements: allMeasurements,
            latestInspection: latestInspection,
          );

          final inspections = rawInspections.isNotEmpty
              ? rawInspections
              : (latestInspection != null
                  ? <ModuleInspection>[latestInspection.inspection]
                  : const <ModuleInspection>[]);

          final List<ModuleMeasurement> activeMeasurements;
          final LatestInspection? activeInspection;
          final ModuleMeasurement? activeLatestMeasurement;
          final List<ModuleMeasurement> activeVerificationMeasurements;
          final String? activePostCleaningResult;
          final InspectionRoutineBundle? activeBundle;

          if (isViewingLatest) {
            final measurements = allMeasurements;
            final rawLatestMeasurement =
                measurements.isNotEmpty ? measurements.first : null;
            final currentMeasurements = filterMeasurementsForCurrentInspection(
              measurements: measurements,
              latestInspection: latestInspection,
              latestMeasurement: rawLatestMeasurement,
            );
            activeMeasurements = currentMeasurements;
            activeInspection = latestInspection;
            activeLatestMeasurement = currentMeasurements.isNotEmpty
                ? currentMeasurements.first
                : rawLatestMeasurement;

            final latestActiveBundle =
                InspectionRoutineBundle.getLatestActiveBundle(bundles);
            final latestRoutineId = (latestInspection != null &&
                    latestInspection.inspection.status != 'scheduled')
                ? latestInspection.inspection.id
                : (latestActiveBundle?.routineInspection.id ??
                    (bundles.isNotEmpty
                        ? bundles.first.routineInspection.id
                        : ''));
            final currentBundle = bundles.firstWhere(
              (b) => b.routineInspection.id == latestRoutineId,
              orElse: () =>
                  latestActiveBundle ??
                  (bundles.isNotEmpty
                      ? bundles.first
                      : InspectionRoutineBundle(
                          routineInspection: latestInspection?.inspection ??
                              const ModuleInspection(
                                id: '',
                                moduleId: '',
                                sourceEventId: '',
                                type: 'scheduled',
                                scheduledFor: '',
                                status: 'completed',
                                createdAt: '',
                                updatedAt: '',
                              ),
                          verificationInspections: const [],
                          routineMeasurements: currentMeasurements,
                          verificationMeasurements: const [],
                          restoredMeasurements: currentMeasurements,
                        )),
            );
            activeVerificationMeasurements =
                currentBundle.verificationMeasurements;
            activePostCleaningResult = currentBundle.verificationResult;
            activeBundle = currentBundle;
          } else {
            final pagedMeas =
                historicalPagedAsync?.valueOrNull?.measurements ??
                    const <ModuleMeasurement>[];

            final histBundle = bundles.firstWhere(
              (b) =>
                  b.routineInspection.id == _selectedHistoricalInspection!.id,
              orElse: () => InspectionRoutineBundle(
                routineInspection: _selectedHistoricalInspection!,
                verificationInspections: const [],
                routineMeasurements: pagedMeas,
                verificationMeasurements: const [],
                restoredMeasurements: pagedMeas,
              ),
            );

            final histMeasurements = histBundle.routineMeasurements.isNotEmpty
                ? histBundle.routineMeasurements
                : pagedMeas;

            activeMeasurements = histMeasurements;
            activeInspection = LatestInspection(
              inspection: _selectedHistoricalInspection!,
              totalMeasurements: histMeasurements.length,
              confirmedAnomalies:
                  _selectedHistoricalInspection!.confirmedAnomalies,
            );
            activeLatestMeasurement =
                histMeasurements.isNotEmpty ? histMeasurements.first : null;

            activeVerificationMeasurements =
                histBundle.verificationMeasurements;
            activePostCleaningResult = histBundle.verificationResult;
            activeBundle = histBundle;
          }

          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async {
              _refreshAll();
              await ref.read(moduleDetailsProvider(widget.moduleId).future);
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Studio Header Card
                  _buildStudioHeader(
                    context,
                    mod: mod,
                    latestMeasurement: activeLatestMeasurement,
                    latestInspection: activeInspection,
                    totalMeasurements: activeMeasurements.length,
                    isViewingLatest: isViewingLatest,
                    inspections: inspections,
                    latestInspectionId: latestInspection?.inspection.id ??
                        (inspections.isNotEmpty ? inspections.first.id : null),
                  ),
                  const SizedBox(height: 16),

                  // 2. High-Precision Radiometric Scan Card (SCR-10 Studio)
                  RadiometricScanCard(
                    module: mod,
                    latestMeasurement: activeLatestMeasurement,
                    latestInspection: activeInspection,
                    measurements: isViewingLatest
                        ? measurementsAsync.valueOrNull
                        : activeMeasurements,
                    verificationMeasurements: activeVerificationMeasurements,
                    postCleaningResult: activePostCleaningResult,
                    fallbackBaselineTempC: activeBundle?.baselineTemperatureC,
                    fallbackConfirmedAnomalies:
                        activeBundle?.confirmedAnomalies,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStudioHeader(
    BuildContext context, {
    required PvModule mod,
    required ModuleMeasurement? latestMeasurement,
    required LatestInspection? latestInspection,
    required int totalMeasurements,
    required bool isViewingLatest,
    required List<ModuleInspection> inspections,
    required String? latestInspectionId,
  }) {
    final confirmedCount = latestInspection?.confirmedAnomalies.length ?? 0;
    final lastSyncTimestamp = latestInspection?.inspection.finishedAt ??
        latestInspection?.inspection.startedAt ??
        latestMeasurement?.measuredAt;

    return Container(
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.thermostat_auto_rounded,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mod.name,
                      style: AppTypography.h3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'MAC: ${mod.macAddress} • ${mod.panelCount ?? 1} panel(s)',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(
                isActive: mod.isActive,
                activeLabel: 'Operational',
                inactiveLabel: 'Disabled',
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Status Badge + Historical Scan Switcher Row
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (isViewingLatest)
                Container(
                  key: const Key('latest_scan_badge'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.successBackground,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.successBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.verified_rounded,
                        size: 14,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'LATEST SCAN',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.success,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  key: const Key('historical_scan_badge'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warningBackground,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.warningBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.history_toggle_off_rounded,
                        size: 14,
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'HISTORICAL SCAN',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.warning,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
              InkWell(
                key: const Key('switch_scan_button'),
                borderRadius: BorderRadius.circular(8),
                onTap: () => _showScanSelectorModal(
                  context,
                  inspections: inspections,
                  latestInspectionId: latestInspectionId,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.history_rounded,
                        size: 14,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Switch Scan',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.expand_more_rounded,
                        size: 15,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (!isViewingLatest && _selectedHistoricalInspection != null) ...[
            const SizedBox(height: 12),
            Container(
              key: const Key('historical_scan_banner'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.warningBackground,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.warningBorder),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Viewing Historical Scan (${_formatIsoDate(_selectedHistoricalInspection!.finishedAt ?? _selectedHistoricalInspection!.startedAt ?? _selectedHistoricalInspection!.scheduledFor)})',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.warning,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  InkWell(
                    key: const Key('back_to_latest_scan_button'),
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      setState(() {
                        _selectedHistoricalInspection = null;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.warningBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.restore_rounded,
                            size: 14,
                            color: AppColors.warning,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Back to Latest Scan',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.warning,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              _buildMetricBadge(
                icon: Icons.filter_frames_rounded,
                label: 'Scan Sections',
                value: '$totalMeasurements sections',
              ),
              _buildMetricBadge(
                icon: Icons.warning_amber_rounded,
                label: 'Confirmed Hotspots',
                value: '$confirmedCount hotspot(s)',
                valueColor:
                    confirmedCount > 0 ? AppColors.error : AppColors.success,
              ),
              _buildMetricBadge(
                icon: Icons.schedule_rounded,
                label: isViewingLatest ? 'Last Inspection' : 'Scan Timestamp',
                value: _formatIsoDate(lastSyncTimestamp),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricBadge({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style:
                AppTypography.caption.copyWith(color: AppColors.textSecondary),
          ),
          Text(
            value,
            style: AppTypography.caption.copyWith(
              color: valueColor ?? AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _showScanSelectorModal(
    BuildContext context, {
    required List<ModuleInspection> inspections,
    required String? latestInspectionId,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(modalContext).size.height * 0.75,
          ),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.history_rounded,
                      color: AppColors.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Select Inspection Scan',
                            style: AppTypography.h3.copyWith(fontSize: 17),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Compare historical thermal sweeps or return to the latest scan',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppColors.textSecondary,
                      ),
                      onPressed: () => Navigator.of(modalContext).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              if (inspections.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      'No inspection scans recorded for this module yet.',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                    itemCount: inspections.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (itemContext, index) {
                      final insp = inspections[index];
                      final isLatest = index == 0 ||
                          (latestInspectionId != null &&
                              insp.id == latestInspectionId);
                      final isSelected = (_selectedHistoricalInspection ==
                                  null &&
                              isLatest) ||
                          (_selectedHistoricalInspection?.id == insp.id);

                      final isPostCleaning =
                          insp.type == 'post_cleaning_verification' ||
                              insp.type == 'post_cleaning' ||
                              insp.cleaningOperationId != null;
                      final scanTypeLabel = isPostCleaning
                          ? 'Post-Cleaning Verification'
                          : 'Routine Thermal Scan';
                      final timestamp = _formatIsoDate(
                        insp.finishedAt ?? insp.startedAt ?? insp.scheduledFor,
                      );

                      return InkWell(
                        key: Key('scan_selector_item_${insp.id}'),
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          setState(() {
                            _selectedHistoricalInspection =
                                isLatest ? null : insp;
                          });
                          Navigator.of(modalContext).pop();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primarySoft.withValues(alpha: 0.35)
                                : AppColors.background,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.border,
                              width: isSelected ? 1.5 : 1.0,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: isLatest
                                      ? AppColors.successBackground
                                      : AppColors.surface,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isLatest
                                        ? AppColors.successBorder
                                        : AppColors.border,
                                  ),
                                ),
                                child: Icon(
                                  isPostCleaning
                                      ? Icons.water_drop_outlined
                                      : Icons.thermostat_rounded,
                                  size: 18,
                                  color: isLatest
                                      ? AppColors.success
                                      : AppColors.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          scanTypeLabel,
                                          style:
                                              AppTypography.bodySmall.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                        if (isLatest)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color:
                                                  AppColors.successBackground,
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                              border: Border.all(
                                                color: AppColors.successBorder,
                                              ),
                                            ),
                                            child: Text(
                                              'LATEST',
                                              style: AppTypography.caption
                                                  .copyWith(
                                                color: AppColors.success,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      timestamp,
                                      style: AppTypography.caption.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 10,
                                      runSpacing: 4,
                                      children: [
                                        Text(
                                          'Status: ${insp.status.toUpperCase()}',
                                          style: AppTypography.caption.copyWith(
                                            color: AppColors.textSecondary,
                                            fontSize: 11,
                                          ),
                                        ),
                                        if (insp.baselineTemperatureC != null)
                                          Text(
                                            'Normal: ${insp.baselineTemperatureC!.toStringAsFixed(1)} °C',
                                            style:
                                                AppTypography.caption.copyWith(
                                              color: AppColors.primary,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 11,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                const Padding(
                                  padding: EdgeInsets.only(left: 8, top: 6),
                                  child: Icon(
                                    Icons.check_circle_rounded,
                                    color: AppColors.primary,
                                    size: 20,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showTechnicalGuideModal(BuildContext context) {
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
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
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
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Icon(
                        Icons.science_outlined,
                        size: 22,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'How to Read This Thermal Map',
                          style: AppTypography.h3.copyWith(fontSize: 17),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: AppColors.textSecondary,
                        ),
                        onPressed: () => Navigator.of(modalContext).pop(),
                      ),
                    ],
                  ),
                  const Divider(height: 20, color: AppColors.border),
                  _buildGuideItem(
                    title: 'High-Detail Thermal Camera (32×24 Grid)',
                    description:
                        'Every pixel represents a real temperature reading from the thermal camera. Blue areas are cool, while orange and red show hotter parts of the panel.',
                  ),
                  const SizedBox(height: 12),
                  _buildGuideItem(
                    title: 'Temperature Along the Track',
                    description:
                        'Shows where each scan was taken along the panels and charts the temperatures so you can see spikes and hot areas immediately.',
                  ),
                  const SizedBox(height: 12),
                  _buildGuideItem(
                    title: 'Double-Checked Hotspot Detection',
                    description:
                        'To avoid false alarms from passing clouds or sun glare, the robot checks if the hot spot appears in two overlapping scans.',
                  ),
                  const SizedBox(height: 12),
                  _buildGuideItem(
                    title: 'Interactive Heat Map',
                    description:
                        'Zoom in on specific panels or the entire row. Tap any section or cell to inspect the temperature reading at that exact spot.',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGuideItem({
    required String title,
    required String description,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.bodySmall.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          description,
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
