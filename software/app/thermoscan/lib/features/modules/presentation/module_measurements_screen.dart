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
  });

  final String moduleId;

  @override
  ConsumerState<ModuleMeasurementsScreen> createState() =>
      _ModuleMeasurementsScreenState();
}

class _ModuleMeasurementsScreenState
    extends ConsumerState<ModuleMeasurementsScreen> {
  String _filter = 'all'; // 'all', 'hotspots', 'normal'

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final detailsAsync = ref.watch(moduleDetailsProvider(widget.moduleId));
    final measurementsAsync =
        ref.watch(moduleMeasurementsProvider(widget.moduleId));

    final mod = detailsAsync.valueOrNull?.module;

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
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () async {
                  ref.invalidate(moduleMeasurementsProvider(widget.moduleId));
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

                          return ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              return _buildMeasurementCard(filtered[index]);
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
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

  Widget _buildMeasurementCard(ModuleMeasurement m) {
    final isHotspot = m.hotspotDetected;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isHotspot ? AppColors.errorBorder : AppColors.border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isHotspot
                  ? AppColors.errorBackground
                  : AppColors.primarySoft.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isHotspot ? Icons.warning_rounded : Icons.grid_on_rounded,
              color: isHotspot ? AppColors.error : AppColors.primary,
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
                    Text(
                      _formatDate(m.measuredAt),
                      style: AppTypography.bodySmall.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isHotspot
                            ? AppColors.errorBackground
                            : AppColors.successBackground,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isHotspot
                              ? AppColors.errorBorder
                              : AppColors.successBorder,
                        ),
                      ),
                      child: Text(
                        isHotspot ? 'HOTSPOT' : 'NORMAL',
                        style: AppTypography.caption.copyWith(
                          color: isHotspot
                              ? AppColors.error
                              : AppColors.success,
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Position X=${m.xPositionCm.toStringAsFixed(1)} cm • Baseline: ${m.baselineTemperatureC.toStringAsFixed(1)}°C',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildMetricChip(
                      'T_max',
                      '${m.maxTemperatureC.toStringAsFixed(1)}°C',
                      isHotspot ? AppColors.error : AppColors.textPrimary,
                    ),
                    const SizedBox(width: 8),
                    _buildMetricChip(
                      'Volt',
                      '${m.voltageV.toStringAsFixed(1)} V',
                      AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    _buildMetricChip(
                      'Curr',
                      '${m.currentA.toStringAsFixed(2)} A',
                      AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    _buildMetricChip(
                      'Power',
                      '${m.powerW.toStringAsFixed(1)} W',
                      AppColors.primary,
                    ),
                  ],
                ),
              ],
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
