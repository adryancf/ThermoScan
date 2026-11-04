import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/core/widgets/top_app_bar.dart';
import 'package:thermoscan/features/auth/presentation/auth_controller.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';
import 'package:thermoscan/features/modules/presentation/modules_controller.dart';
import 'package:thermoscan/features/modules/presentation/widgets/module_sub_nav_bar.dart';

/// SCR-11: Module Details — Telemetry History / Measurements (Paginated)
class ModuleMeasurementsScreen extends ConsumerStatefulWidget {
  const ModuleMeasurementsScreen({
    super.key,
    required this.moduleId,
    this.showAppBar = true,
  });

  final String moduleId;
  final bool showAppBar;

  @override
  ConsumerState<ModuleMeasurementsScreen> createState() =>
      _ModuleMeasurementsScreenState();
}

class ModuleMeasurementsView extends StatelessWidget {
  const ModuleMeasurementsView({
    super.key,
    required this.moduleId,
  });

  final String moduleId;

  @override
  Widget build(BuildContext context) {
    return ModuleMeasurementsScreen(
      moduleId: moduleId,
      showAppBar: false,
    );
  }
}

class _ModuleMeasurementsScreenState
    extends ConsumerState<ModuleMeasurementsScreen> {
  int _currentPage = 1;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final detailsAsync = ref.watch(moduleDetailsProvider(widget.moduleId));
    final latestInspectionAsync =
        ref.watch(latestInspectionProvider(widget.moduleId));
    final allMeasurementsAsync =
        ref.watch(moduleMeasurementsProvider(widget.moduleId));

    final mod = detailsAsync.valueOrNull?.module;

    final content = RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        ref.invalidate(latestInspectionProvider(widget.moduleId));
        ref.invalidate(moduleMeasurementsProvider(widget.moduleId));
        ref.invalidate(inspectionMeasurementsPagedProvider);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
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
                        'Telemetry History',
                        style: AppTypography.h2,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Historical radiometric acquisitions & electrical yield',
                        style: AppTypography.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            latestInspectionAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                  ),
                ),
              ),
              error: (err, _) => Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  'Failed to load inspection telemetry: $err',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ),
              data: (latestInspection) {
                final allMeasurements =
                    allMeasurementsAsync.valueOrNull ?? const <ModuleMeasurement>[];
                if ((latestInspection == null ||
                        latestInspection.inspection.id.isEmpty) &&
                    allMeasurements.isEmpty) {
                  return _buildEmptyState();
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (latestInspection != null &&
                        latestInspection.inspection.id.isNotEmpty) ...[
                      _buildPaginatedInspectionSection(latestInspection),
                      const SizedBox(height: 20),
                    ],
                    _buildInspectionHistorySection(
                      allMeasurementsAsync: allMeasurementsAsync,
                      latestInspection: latestInspection,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );

    if (!widget.showAppBar) {
      return content;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: ThermoScanAppBar(
        title: mod != null ? '${mod.name} Telemetry' : 'Telemetry History',
        role: user?.role,
        showBack: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Sub-navigation bar
            if (mod != null)
              ModuleSubNavBar(
                moduleId: widget.moduleId,
                currentTab: 'measurements',
                canManageAccess: mod.permissions.canManageAccess,
                isPendingConfig: mod.isPendingConfiguration,
              ),

            // Content body
            Expanded(child: content),
          ],
        ),
      ),
    );
  }

  Widget _buildPaginatedInspectionSection(LatestInspection latestInspection) {
    final insp = latestInspection.inspection;
    final pagedAsync = ref.watch(inspectionMeasurementsPagedProvider((
      moduleId: widget.moduleId,
      inspectionId: insp.id,
      page: _currentPage,
      limit: 10,
    )));

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.layers_outlined,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Active Inspection (Paginated)',
                        style: AppTypography.caption.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Baseline: ${insp.baselineTemperatureC != null ? "${insp.baselineTemperatureC!.toStringAsFixed(1)}°C" : "N/A"}',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  insp.status.toUpperCase(),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          pagedAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            ),
            error: (err, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Failed to load inspection measurements: $err',
                style: AppTypography.caption.copyWith(color: AppColors.error),
              ),
            ),
            data: (paged) {
              final measurements = List<ModuleMeasurement>.from(paged.measurements)
                ..sort((a, b) => a.xPositionCm.compareTo(b.xPositionCm));

              if (measurements.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      'No measurements in this inspection.',
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                );
              }

              return Column(
                children: [
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: measurements.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (ctx, idx) {
                      final m = measurements[idx];
                      final isConfirmed = latestInspection.confirmedAnomalies.any(
                        (a) => (a.xPositionCm - m.xPositionCm).abs() <= 1.0,
                      );
                      return _buildPaginatedStepTile(m, isConfirmed);
                    },
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Page ${paged.page} of ${paged.totalPages} (${paged.totalCount} items)',
                        style: AppTypography.caption
                            .copyWith(color: AppColors.textSecondary),
                      ),
                      Row(
                        children: [
                          OutlinedButton(
                            key: const Key('btn_prev_page'),
                            onPressed: paged.page > 1
                                ? () => setState(() => _currentPage--)
                                : null,
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                            ),
                            child: const Text('Previous'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            key: const Key('btn_next_page'),
                            onPressed: paged.hasNextPage
                                ? () => setState(() => _currentPage++)
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                            ),
                            child: const Text('Next'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPaginatedStepTile(ModuleMeasurement m, bool isConfirmed) {
    final vText = m.voltageV != null ? '${m.voltageV!.toStringAsFixed(1)}V' : 'N/A';
    final iText = m.currentA != null ? '${m.currentA!.toStringAsFixed(2)}A' : 'N/A';
    final pText = m.powerW != null ? '${m.powerW!.toStringAsFixed(1)}W' : 'N/A';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isConfirmed ? AppColors.errorBorder : AppColors.border,
          width: isConfirmed ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'X = ${m.xPositionCm.toStringAsFixed(1)} cm',
                style: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              if (isConfirmed) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.errorBackground,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.errorBorder),
                  ),
                  child: Text(
                    'HOTSPOT',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.error,
                      fontWeight: FontWeight.w800,
                      fontSize: 9,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: [
                  _buildMetricChip(
                    'Peak',
                    '${m.maxTemperatureC.toStringAsFixed(1)}°C',
                    isConfirmed ? AppColors.error : AppColors.textPrimary,
                  ),
                  _buildMetricChip(
                    'Volt',
                    vText,
                    AppColors.textSecondary,
                  ),
                  _buildMetricChip(
                    'Curr',
                    iText,
                    AppColors.textSecondary,
                  ),
                  _buildMetricChip(
                    'Power',
                    pText,
                    AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricChip(String label, String value, Color valueColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: AppTypography.caption.copyWith(
              fontSize: 10,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            value,
            style: AppTypography.dataValue.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInspectionHistorySection({
    required AsyncValue<List<ModuleMeasurement>> allMeasurementsAsync,
    required LatestInspection? latestInspection,
  }) {
    return allMeasurementsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (allMeasurements) {
        if (allMeasurements.isEmpty) {
          return const SizedBox.shrink();
        }

        // Group measurements by inspectionId
        final Map<String, List<ModuleMeasurement>> grouped = {};
        for (final m in allMeasurements) {
          final key = m.inspectionId.isNotEmpty ? m.inspectionId : 'unlinked';
          grouped.putIfAbsent(key, () => []).add(m);
        }

        // Sort groups by most recent measurement timestamp DESC
        final entries = grouped.entries.toList()
          ..sort((a, b) {
            final maxA = _maxMeasuredAt(a.value);
            final maxB = _maxMeasuredAt(b.value);
            if (maxA != null && maxB != null) {
              return maxB.compareTo(maxA);
            }
            return b.key.compareTo(a.key);
          });

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.history_rounded,
                  color: AppColors.primary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Inspection History (Grouped by Inspection)',
                    style: AppTypography.h3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'All recorded inspections and their measurements grouped by inspection_id',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final entry = entries[index];
                final inspectionId = entry.key;
                final groupMeasurements = List<ModuleMeasurement>.from(entry.value)
                  ..sort((a, b) => a.xPositionCm.compareTo(b.xPositionCm));
                final isLatest =
                    latestInspection?.inspection.id == inspectionId;
                return _buildInspectionHistoryGroupCard(
                  inspectionId: inspectionId,
                  measurements: groupMeasurements,
                  isLatest: isLatest,
                  latestInspection: isLatest ? latestInspection : null,
                );
              },
            ),
          ],
        );
      },
    );
  }

  DateTime? _maxMeasuredAt(List<ModuleMeasurement> items) {
    DateTime? maxDt;
    for (final m in items) {
      final dt = DateTime.tryParse(m.measuredAt);
      if (dt != null && (maxDt == null || dt.isAfter(maxDt))) {
        maxDt = dt;
      }
    }
    return maxDt;
  }

  String _formatShortTimestamp(String isoString) {
    final dt = DateTime.tryParse(isoString)?.toLocal();
    if (dt == null) return isoString;
    final y = dt.year.toString().padLeft(4, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$d/$mo/$y $h:$mi:$s';
  }

  Widget _buildInspectionHistoryGroupCard({
    required String inspectionId,
    required List<ModuleMeasurement> measurements,
    required bool isLatest,
    required LatestInspection? latestInspection,
  }) {
    final shortId = inspectionId.length > 8
        ? '${inspectionId.substring(0, 8)}...'
        : inspectionId;
    final peakTemp = measurements.isNotEmpty
        ? measurements
              .map((m) => m.maxTemperatureC)
              .reduce((a, b) => a > b ? a : b)
        : 0.0;
    final latestDt = _maxMeasuredAt(measurements);
    final dateLabel = latestDt != null
        ? _formatShortTimestamp(latestDt.toIso8601String())
        : (measurements.isNotEmpty ? measurements.first.measuredAt : 'N/A');

    return Container(
      key: Key('history_group_$inspectionId'),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isLatest ? AppColors.primary : AppColors.border,
          width: isLatest ? 1.5 : 1.0,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Inspection $shortId',
                            style: AppTypography.caption.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isLatest) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primarySoft,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'LATEST',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w800,
                                fontSize: 9,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$dateLabel • ${measurements.length} frames • Peak ${peakTemp.toStringAsFixed(1)}°C',
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
          const SizedBox(height: 10),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: measurements.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (ctx, idx) {
              final m = measurements[idx];
              final isConfirmed = latestInspection != null &&
                  latestInspection.confirmedAnomalies.any(
                    (a) =>
                        a.originMeasurementId == m.id ||
                        a.confirmingMeasurementIds.contains(m.id) ||
                        (a.originMeasurementId.isEmpty &&
                            a.confirmingMeasurementIds.isEmpty &&
                            (a.xPositionCm - m.xPositionCm).abs() <= 1.0),
                  );
              return _buildPaginatedStepTile(m, isConfirmed);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.sensors_outlined,
            size: 44,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 14),
          Text(
            'No Telemetry Records Yet',
            style: AppTypography.h3,
          ),
          const SizedBox(height: 6),
          Text(
            'Thermal acquisitions and electrical measurements will appear here once the ESP32 performs its scheduled solar window scans.',
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall,
          ),
        ],
      ),
    );
  }
}
