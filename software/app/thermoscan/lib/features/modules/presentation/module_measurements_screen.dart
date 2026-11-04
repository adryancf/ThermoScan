import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/core/widgets/top_app_bar.dart';
import 'package:thermoscan/features/auth/presentation/auth_controller.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';
import 'package:thermoscan/features/modules/presentation/modules_controller.dart';
import 'package:thermoscan/features/modules/presentation/widgets/module_sub_nav_bar.dart';

/// SCR-11: Module Details — Telemetry History / Measurements
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
  String _filter = 'all'; // 'all', 'hotspots', 'normal'
  int _currentPage = 1;
  final Set<String> _expandedSessions = {};

  List<_InspectionSession> _groupIntoSessions(List<ModuleMeasurement> list) {
    final Map<String, List<ModuleMeasurement>> groups = {};
    for (final m in list) {
      final parsed = DateTime.tryParse(m.measuredAt);
      final key = m.inspectionId.isNotEmpty
          ? m.inspectionId
          : (parsed != null
              ? '${parsed.year}-${parsed.month}-${parsed.day} ${parsed.hour}:${parsed.minute ~/ 10}'
              : m.measuredAt);
      groups.putIfAbsent(key, () => []).add(m);
    }

    return groups.entries.map((entry) {
      final items = entry.value;
      items.sort((a, b) => a.xPositionCm.compareTo(b.xPositionCm));
      return _InspectionSession(
        id: entry.key,
        measuredAt: items.first.measuredAt,
        measurements: items,
      );
    }).toList()
      ..sort((a, b) {
        final da = DateTime.tryParse(a.measuredAt) ?? DateTime(1970);
        final db = DateTime.tryParse(b.measuredAt) ?? DateTime(1970);
        return db.compareTo(da);
      });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final detailsAsync = ref.watch(moduleDetailsProvider(widget.moduleId));
    final measurementsAsync =
        ref.watch(moduleMeasurementsProvider(widget.moduleId));
    final latestInspectionAsync =
        ref.watch(latestInspectionProvider(widget.moduleId));
    final latestInspection = latestInspectionAsync.valueOrNull;

    final mod = detailsAsync.valueOrNull?.module;

    final content = RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        ref.invalidate(moduleMeasurementsProvider(widget.moduleId));
        ref.invalidate(latestInspectionProvider(widget.moduleId));
        await ref.read(
          moduleMeasurementsProvider(widget.moduleId).future,
        );
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

            if (latestInspection != null && latestInspection.inspection.id.isNotEmpty) ...[
              _buildPaginatedInspectionSection(latestInspection),
              const SizedBox(height: 24),
              const Divider(color: AppColors.border),
              const SizedBox(height: 16),
              Text(
                'Aggregated Sessions Log',
                style: AppTypography.h3,
              ),
              const SizedBox(height: 12),
            ],

            // Filter Pills
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('all', 'All Measurements'),
                  const SizedBox(width: 8),
                  _buildFilterChip('hotspots', 'Hotspots Only'),
                  const SizedBox(width: 8),
                  _buildFilterChip('normal', 'Normal'),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Measurements list
            measurementsAsync.when(
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
                  'Failed to load measurements: $err',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ),
              data: (measurements) {
                final filtered = measurements.where((m) {
                  if (_filter == 'hotspots') {
                    return m.hotspotDetected;
                  }
                  if (_filter == 'normal') {
                    return !m.hotspotDetected;
                  }
                  return true;
                }).toList();

                if (filtered.isEmpty) {
                  return _buildEmptyState();
                }

                final sessions = _groupIntoSessions(filtered);

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: sessions.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    return _buildInspectionSessionCard(
                      sessions[index],
                      latestInspection,
                    );
                  },
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

  Widget _buildFilterChip(String value, String label) {
    final isSelected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.caption.copyWith(
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? AppColors.surface : AppColors.textSecondary,
          ),
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
                        'Baseline: ${insp.baselineTemperatureC != null ? "${insp.baselineTemperatureC!.toStringAsFixed(1)}°C" : "Awaiting scan"}',
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
              final measurements = paged.measurements;
              if (measurements.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      'No measurements in this inspection.',
                      style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
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
                        style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
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
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isConfirmed
              ? AppColors.errorBorder
              : (m.hotspotDetected ? AppColors.warningBorder : AppColors.border),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                'X = ${m.xPositionCm.toStringAsFixed(1)} cm',
                style: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              if (isConfirmed)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                )
              else if (m.hotspotDetected)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.warningBackground,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.warningBorder),
                  ),
                  child: Text(
                    'CANDIDATE',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.warning,
                      fontWeight: FontWeight.w800,
                      fontSize: 9,
                    ),
                  ),
                ),
            ],
          ),
          Wrap(
            spacing: 6,
            children: [
              _buildMetricChip(
                'Peak',
                '${m.maxTemperatureC.toStringAsFixed(1)}°C',
                isConfirmed ? AppColors.error : AppColors.textPrimary,
              ),
              _buildMetricChip(
                'Volt',
                '${m.voltageV.toStringAsFixed(1)}V',
                AppColors.textSecondary,
              ),
              _buildMetricChip(
                'Power',
                '${m.powerW.toStringAsFixed(1)}W',
                AppColors.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInspectionSessionCard(
    _InspectionSession session,
    LatestInspection? latestInspection,
  ) {
    final hasConfirmed = latestInspection != null &&
        (session.id == latestInspection.inspection.id ||
            session.id == latestInspection.inspection.sourceEventId ||
            session.measurements.any((m) => latestInspection.confirmedAnomalies
                .any((a) => (a.xPositionCm - m.xPositionCm).abs() < 1.0))) &&
        latestInspection.confirmedAnomalies.isNotEmpty;
    final hasCandidate = session.hasCandidate;
    final baselineTemp = latestInspection?.inspection.baselineTemperatureC;
    final isExpanded = _expandedSessions.contains(session.id);
    final count = session.measurements.length;

    final Color statusColor;
    final Color statusBg;
    final Color statusBorder;
    final String statusText;
    final IconData statusIcon;

    if (hasConfirmed) {
      statusColor = AppColors.error;
      statusBg = AppColors.errorBackground;
      statusBorder = AppColors.errorBorder;
      statusText = 'HOTSPOT';
      statusIcon = Icons.warning_rounded;
    } else if (hasCandidate) {
      statusColor = AppColors.warning;
      statusBg = AppColors.warningBackground;
      statusBorder = AppColors.warningBorder;
      statusText = 'CANDIDATE';
      statusIcon = Icons.info_outline_rounded;
    } else {
      statusColor = AppColors.success;
      statusBg = AppColors.successBackground;
      statusBorder = AppColors.successBorder;
      statusText = 'NORMAL';
      statusIcon = Icons.grid_on_rounded;
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasConfirmed
              ? AppColors.errorBorder
              : (hasCandidate ? AppColors.warningBorder : AppColors.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    statusIcon,
                    color: statusColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              _formatDate(session.measuredAt),
                              style: AppTypography.bodySmall.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: statusBg,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: statusBorder,
                              ),
                            ),
                            child: Text(
                              statusText,
                              style: AppTypography.caption.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.w800,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Inspection Session • $count scan ${count == 1 ? "step" : "steps"}',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Responsive Wrap so Power chip never overflows card
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _buildMetricChip(
                            'Peak',
                            '${session.maxTemp.toStringAsFixed(1)}°C',
                            hasConfirmed
                                ? AppColors.error
                                : (hasCandidate ? AppColors.warning : AppColors.textPrimary),
                          ),
                          _buildMetricChip(
                            'Base',
                            baselineTemp != null && baselineTemp > 0
                                ? '${baselineTemp.toStringAsFixed(1)}°C'
                                : 'N/A',
                            AppColors.textSecondary,
                          ),
                          _buildMetricChip(
                            'Volt',
                            '${session.avgVoltage.toStringAsFixed(1)} V',
                            AppColors.textSecondary,
                          ),
                          _buildMetricChip(
                            'Curr',
                            '${session.avgCurrent.toStringAsFixed(2)} A',
                            AppColors.textSecondary,
                          ),
                          _buildMetricChip(
                            'Power',
                            '${session.avgPower.toStringAsFixed(1)} W',
                            AppColors.primary,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (count > 1) ...[
            const Divider(height: 1),
            InkWell(
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expandedSessions.remove(session.id);
                  } else {
                    _expandedSessions.add(session.id);
                  }
                });
              },
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isExpanded
                          ? 'Hide step breakdown'
                          : 'View $count steps breakdown',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ),
            if (isExpanded)
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                ),
                padding: const EdgeInsets.all(12),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: session.measurements.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (ctx, idx) =>
                      _buildStepTile(session.measurements[idx]),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepTile(ModuleMeasurement m) {
    final isCandidate = m.hotspotDetected;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isCandidate ? AppColors.warningBorder : AppColors.border,
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
              if (isCandidate) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: AppColors.warningBackground,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.warningBorder),
                  ),
                  child: const Text(
                    'Candidate',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AppColors.warning,
                    ),
                  ),
                ),
              ],
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              Text(
                'T_max: ${m.maxTemperatureC.toStringAsFixed(1)}°C',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isCandidate ? AppColors.warning : AppColors.textSecondary,
                ),
              ),
              Text(
                '• ${m.voltageV.toStringAsFixed(1)}V',
                style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
              ),
              Text(
                '• ${m.currentA.toStringAsFixed(2)}A',
                style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
              ),
              Text(
                '• ${m.powerW.toStringAsFixed(1)}W',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ],
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

  String _formatDate(String isoString) {
    final parsed = DateTime.tryParse(isoString);
    if (parsed == null) return isoString;
    final local = parsed.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final ss = local.second.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm:$ss';
  }
}

class _InspectionSession {
  final String id;
  final String measuredAt;
  final List<ModuleMeasurement> measurements;

  _InspectionSession({
    required this.id,
    required this.measuredAt,
    required this.measurements,
  });

  bool get hasCandidate => measurements.any((m) => m.hotspotDetected);

  double get maxTemp => measurements.fold(
        0.0,
        (prev, m) => m.maxTemperatureC > prev ? m.maxTemperatureC : prev,
      );

  double get avgVoltage => measurements.isEmpty
      ? 0.0
      : measurements.map((m) => m.voltageV).reduce((a, b) => a + b) /
          measurements.length;

  double get avgCurrent => measurements.isEmpty
      ? 0.0
      : measurements.map((m) => m.currentA).reduce((a, b) => a + b) /
          measurements.length;

  double get avgPower => measurements.isEmpty
      ? 0.0
      : measurements.map((m) => m.powerW).reduce((a, b) => a + b) /
          measurements.length;
}
