import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/core/widgets/top_app_bar.dart';
import 'package:thermoscan/features/alerts/domain/alert_models.dart';
import 'package:thermoscan/features/alerts/presentation/alerts_controller.dart';
import 'package:thermoscan/features/auth/presentation/auth_controller.dart';

/// SCR-21: Active Field Alerts Feed
class AlertsFeedScreen extends ConsumerStatefulWidget {
  const AlertsFeedScreen({super.key});

  @override
  ConsumerState<AlertsFeedScreen> createState() => _AlertsFeedScreenState();
}

class _AlertsFeedScreenState extends ConsumerState<AlertsFeedScreen> {
  // Filters: 'all', 'critical', 'warning', 'hotspot', 'water'
  String _filter = 'all';

  String _formatTimeAgo(String dateStr) {
    final parsed = DateTime.tryParse(dateStr);
    if (parsed == null) return 'recently';
    final diff = DateTime.now().toUtc().difference(parsed.toUtc());
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _formatInspectionDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return 'Recent';
    final parsed = DateTime.tryParse(dateStr);
    if (parsed == null) return dateStr;
    final local = parsed.toLocal();
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
    final month = months[local.month - 1];
    final hour = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$month ${local.day}, $hour:$min';
  }

  void _toggleFilter(String target) {
    setState(() {
      if (_filter == target) {
        _filter = 'all';
      } else {
        _filter = target;
      }
    });
  }

  Widget _buildAdvisoryBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: AppColors.primary,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Automatic Alert Updates',
                  style: AppTypography.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Thermal anomalies and robot water levels are automatically monitored and refreshed continuously.',
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
    );
  }

  Widget _buildKpiCard({
    required String label,
    required int count,
    required IconData icon,
    required Color color,
    required Color activeBgColor,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            color: isSelected ? activeBgColor : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color : AppColors.border,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, color: color, size: 18),
                  Text(
                    '$count',
                    style: AppTypography.h3.copyWith(
                      fontWeight: FontWeight.w800,
                      color: color,
                      fontSize: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isSelected ? color : AppColors.textSecondary,
                  fontSize: 11,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final isSelected = _filter == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _filter = value;
        });
      },
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

  Widget _buildEmptyState() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(
                  color: AppColors.successBackground,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_outline_rounded,
                  size: 40,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'No Active Field Alerts',
                style: AppTypography.h3,
              ),
              const SizedBox(height: 6),
              Text(
                _filter == 'all'
                    ? 'All solar arrays and cleaning robots are operating normally without anomalies.'
                    : 'No active field alerts matching the selected filter.',
                textAlign: TextAlign.center,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildAdvisoryBanner(),
      ],
    );
  }

  Widget _buildAlertCard({
    required BuildContext context,
    required FieldAlert alert,
  }) {
    final isCritical = alert.isCritical;
    final borderColor = isCritical ? AppColors.error : AppColors.warning;
    final badgeBg =
        isCritical ? AppColors.errorBackground : AppColors.warningBackground;

    final String originText;
    final IconData originIcon;
    final Color originIconColor;
    if (alert.isHotspot) {
      originIcon = Icons.search_rounded;
      originIconColor = AppColors.primary;
      originText = alert.inspectionDate != null
          ? 'Origin: Inspection (${_formatInspectionDate(alert.inspectionDate)})'
          : 'Origin: Inspection';
    } else if (alert.isReservoirLow) {
      originIcon = Icons.smart_toy_outlined;
      originIconColor = AppColors.accent;
      originText = 'Origin: Robot Hardware Telemetry';
    } else {
      originIcon = Icons.sensors_outlined;
      originIconColor = AppColors.textSecondary;
      originText = 'Origin: System Telemetry';
    }

    final String actionLabel = alert.isHotspot
        ? 'View in Thermal Studio ➔'
        : (alert.isReservoirLow ? 'Check Robot Status ➔' : 'View Module ➔');

    void handleAction() {
      if (alert.moduleId.isEmpty) return;
      if (alert.isHotspot) {
        context.push('/modules/${alert.moduleId}/thermal-inspection');
      } else {
        context.push('/modules/${alert.moduleId}');
      }
    }

    return InkWell(
      onTap: handleAction,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Stack(
          children: [
            // Left colored stripe
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: 4.5,
                decoration: BoxDecoration(
                  color: borderColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Row: Severity badge + Time ago
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: badgeBg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: borderColor.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          isCritical ? 'CRITICAL' : 'WARNING',
                          style: AppTypography.caption.copyWith(
                            color: borderColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      Text(
                        _formatTimeAgo(alert.createdAt),
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Alert Title
                  if (alert.title.isNotEmpty) ...[
                    Text(
                      alert.title,
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                  ],

                  // Location & Entity Row
                  Row(
                    children: [
                      Icon(
                        alert.isReservoirLow
                            ? Icons.water_drop_outlined
                            : Icons.solar_power_outlined,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                alert.moduleName,
                                style: AppTypography.caption.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (alert.panelIndex != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                key: Key('alert_panel_badge_${alert.id}'),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primarySoft,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color:
                                        AppColors.primary.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Text(
                                  'Panel ${alert.panelIndex}',
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ] else if (alert.isReservoirLow) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primarySoft,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color:
                                        AppColors.primary.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Text(
                                  'Robot Tank',
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Origin Badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          originIcon,
                          size: 12,
                          color: originIconColor,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          originText,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Structured Data Box
                  if (alert.isHotspot) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: badgeBg,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '🔥 +${(alert.deltaC ?? 0.0).toStringAsFixed(1)}°C Delta',
                                  style: AppTypography.caption.copyWith(
                                    color: borderColor,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  alert.maxTemperatureC != null &&
                                          alert.baselineTemperatureC != null
                                      ? '${alert.maxTemperatureC!.toStringAsFixed(1)}°C Peak vs ${alert.baselineTemperatureC!.toStringAsFixed(1)}°C Base'
                                      : (alert.metaText.isNotEmpty
                                          ? alert.metaText
                                          : 'Thermal Anomaly'),
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.place_outlined,
                                    size: 13,
                                    color: AppColors.textSecondary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${(alert.localXPositionCm ?? alert.xPositionCm ?? 0.0).toStringAsFixed(1)} cm on panel',
                                    style: AppTypography.caption.copyWith(
                                      color: AppColors.textSecondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                              const Text('·',
                                  style: TextStyle(
                                      color: AppColors.border, fontSize: 12)),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.cleaning_services_outlined,
                                    size: 13,
                                    color: AppColors.textSecondary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${alert.washAttemptsCount ?? 0} of 3 washes attempted',
                                    style: AppTypography.caption.copyWith(
                                      color: AppColors.textSecondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ] else if (alert.isReservoirLow) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.water_drop_outlined,
                                size: 16,
                                color: AppColors.accent,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Reservoir water level low (< 10%)',
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Autonomous spray washing is paused until reservoir is manually refilled.',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        alert.description,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),

                  // Direct Action button
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.15),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          actionLabel,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final alertsAsync = ref.watch(alertsSummaryProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: ThermoScanAppBar(
        title: 'Active Field Alerts',
        role: user?.role,
        showBack: false,
        showProfileAction: true,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(alertsSummaryProvider);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Screen Title
                Text(
                  'Active Field Alerts',
                  style: AppTypography.h2,
                ),
                const SizedBox(height: 16),

                // Section Title for Summary
                Text(
                  'FIELD STATUS SUMMARY',
                  style: AppTypography.caption.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),

                // Interactive KPI Summary Bar
                alertsAsync.when(
                  loading: () => Row(
                    children: [
                      _buildKpiCard(
                        label: 'Critical',
                        count: 0,
                        icon: Icons.error_outline_rounded,
                        color: AppColors.error,
                        activeBgColor: AppColors.errorBackground
                            .withValues(alpha: 0.3),
                        isSelected: _filter == 'critical',
                        onTap: () {},
                      ),
                      const SizedBox(width: 8),
                      _buildKpiCard(
                        label: 'Warnings',
                        count: 0,
                        icon: Icons.warning_amber_rounded,
                        color: AppColors.warning,
                        activeBgColor: AppColors.warningBackground
                            .withValues(alpha: 0.3),
                        isSelected: _filter == 'warning',
                        onTap: () {},
                      ),
                      const SizedBox(width: 8),
                      _buildKpiCard(
                        label: 'Low Water',
                        count: 0,
                        icon: Icons.water_drop_outlined,
                        color: AppColors.accent,
                        activeBgColor:
                            AppColors.primarySoft.withValues(alpha: 0.3),
                        isSelected: _filter == 'water',
                        onTap: () {},
                      ),
                    ],
                  ),
                  error: (_, _) => Row(
                    children: [
                      _buildKpiCard(
                        label: 'Critical',
                        count: 0,
                        icon: Icons.error_outline_rounded,
                        color: AppColors.error,
                        activeBgColor: AppColors.errorBackground
                            .withValues(alpha: 0.3),
                        isSelected: _filter == 'critical',
                        onTap: () {},
                      ),
                      const SizedBox(width: 8),
                      _buildKpiCard(
                        label: 'Warnings',
                        count: 0,
                        icon: Icons.warning_amber_rounded,
                        color: AppColors.warning,
                        activeBgColor: AppColors.warningBackground
                            .withValues(alpha: 0.3),
                        isSelected: _filter == 'warning',
                        onTap: () {},
                      ),
                      const SizedBox(width: 8),
                      _buildKpiCard(
                        label: 'Low Water',
                        count: 0,
                        icon: Icons.water_drop_outlined,
                        color: AppColors.accent,
                        activeBgColor:
                            AppColors.primarySoft.withValues(alpha: 0.3),
                        isSelected: _filter == 'water',
                        onTap: () {},
                      ),
                    ],
                  ),
                  data: (summary) {
                    final criticalCount = summary.critical > 0
                        ? summary.critical
                        : summary.alerts.where((a) => a.isCritical).length;
                    final warningCount = summary.warning > 0
                        ? summary.warning
                        : summary.alerts.where((a) => !a.isCritical).length;
                    final waterCount =
                        summary.alerts.where((a) => a.isReservoirLow).length;

                    return Row(
                      children: [
                        _buildKpiCard(
                          label: 'Critical',
                          count: criticalCount,
                          icon: Icons.error_outline_rounded,
                          color: AppColors.error,
                          activeBgColor: AppColors.errorBackground
                              .withValues(alpha: 0.3),
                          isSelected: _filter == 'critical',
                          onTap: () => _toggleFilter('critical'),
                        ),
                        const SizedBox(width: 8),
                        _buildKpiCard(
                          label: 'Warnings',
                          count: warningCount,
                          icon: Icons.warning_amber_rounded,
                          color: AppColors.warning,
                          activeBgColor: AppColors.warningBackground
                              .withValues(alpha: 0.3),
                          isSelected: _filter == 'warning',
                          onTap: () => _toggleFilter('warning'),
                        ),
                        const SizedBox(width: 8),
                        _buildKpiCard(
                          label: 'Low Water',
                          count: waterCount,
                          icon: Icons.water_drop_outlined,
                          color: AppColors.accent,
                          activeBgColor:
                              AppColors.primarySoft.withValues(alpha: 0.3),
                          isSelected: _filter == 'water',
                          onTap: () => _toggleFilter('water'),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Category Filter Chips
                alertsAsync.when(
                  loading: () => SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('all', 'All Alerts'),
                        const SizedBox(width: 8),
                        _buildFilterChip('hotspot', '🔥 Hotspots'),
                        const SizedBox(width: 8),
                        _buildFilterChip('water', '💧 Low Water'),
                      ],
                    ),
                  ),
                  error: (_, _) => SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('all', 'All Alerts'),
                        const SizedBox(width: 8),
                        _buildFilterChip('hotspot', '🔥 Hotspots'),
                        const SizedBox(width: 8),
                        _buildFilterChip('water', '💧 Low Water'),
                      ],
                    ),
                  ),
                  data: (summary) {
                    final hotspotCount =
                        summary.alerts.where((a) => a.isHotspot).length;
                    final waterCount =
                        summary.alerts.where((a) => a.isReservoirLow).length;

                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip(
                              'all', 'All Alerts (${summary.total})'),
                          const SizedBox(width: 8),
                          _buildFilterChip(
                              'hotspot', '🔥 Hotspots ($hotspotCount)'),
                          const SizedBox(width: 8),
                          _buildFilterChip(
                              'water', '💧 Low Water ($waterCount)'),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 18),

                // Alerts List
                alertsAsync.when(
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  error: (error, _) => Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      'Failed to load field alerts: $error',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ),
                  data: (summary) {
                    final allAlerts = summary.alerts;
                    final filteredAlerts = allAlerts.where((a) {
                      if (_filter == 'critical') return a.isCritical;
                      if (_filter == 'warning') return !a.isCritical;
                      if (_filter == 'hotspot') return a.isHotspot;
                      if (_filter == 'water') return a.isReservoirLow;
                      return true;
                    }).toList();

                    if (filteredAlerts.isEmpty) {
                      return _buildEmptyState();
                    }

                    return Column(
                      children: [
                        ...filteredAlerts.map((alert) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _buildAlertCard(
                              context: context,
                              alert: alert,
                            ),
                          );
                        }),
                        const SizedBox(height: 6),
                        _buildAdvisoryBanner(),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
