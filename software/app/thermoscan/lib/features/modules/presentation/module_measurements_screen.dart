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

    final mod = detailsAsync.valueOrNull?.module;

    final content = RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        ref.invalidate(latestInspectionProvider(widget.moduleId));
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
                if (latestInspection == null ||
                    latestInspection.inspection.id.isEmpty) {
                  return _buildEmptyState();
                }

                return _buildPaginatedInspectionSection(latestInspection);
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
