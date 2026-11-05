import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/core/widgets/top_app_bar.dart';
import 'package:thermoscan/features/alerts/presentation/alerts_controller.dart';
import 'package:thermoscan/features/auth/presentation/auth_controller.dart';

/// SCR-21: Active Field Alerts Feed
class AlertsFeedScreen extends ConsumerStatefulWidget {
  const AlertsFeedScreen({super.key});

  @override
  ConsumerState<AlertsFeedScreen> createState() => _AlertsFeedScreenState();
}

class _AlertsFeedScreenState extends ConsumerState<AlertsFeedScreen> {
  String _filter = 'all'; // 'all', 'critical', 'warning'

  String _formatTimeAgo(String dateStr) {
    final parsed = DateTime.tryParse(dateStr);
    if (parsed == null) return 'recently';
    final diff = DateTime.now().toUtc().difference(parsed.toUtc());
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Widget _buildAdvisoryBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: AppColors.primary,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Autonomous ESP32 Telemetry Sync',
                  style: AppTypography.h3.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Field units evaluate safety interlocks and solar geometry locally. Alerts are delivered immediately upon HTTPS REST sync.',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
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
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header section
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Active Field Alerts',
                            style: AppTypography.h2,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Operational events, safety interlocks and anomalies',
                            style: AppTypography.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Severity Filter Chips with real dynamic counts
                alertsAsync.when(
                  loading: () => SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('all', 'All Alerts'),
                        const SizedBox(width: 8),
                        _buildFilterChip('critical', 'Critical'),
                        const SizedBox(width: 8),
                        _buildFilterChip('warning', 'Warning'),
                      ],
                    ),
                  ),
                  error: (_, _) => SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('all', 'All Alerts'),
                        const SizedBox(width: 8),
                        _buildFilterChip('critical', 'Critical'),
                        const SizedBox(width: 8),
                        _buildFilterChip('warning', 'Warning'),
                      ],
                    ),
                  ),
                  data: (summary) => SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('all', 'All Alerts (${summary.total})'),
                        const SizedBox(width: 8),
                        _buildFilterChip('critical', 'Critical (${summary.critical})'),
                        const SizedBox(width: 8),
                        _buildFilterChip('warning', 'Warning (${summary.warning})'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

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
                      return true;
                    }).toList();

                    if (filteredAlerts.isEmpty) {
                      return Column(
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.check_circle_outline_rounded,
                                  size: 48,
                                  color: AppColors.success,
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  'No Active Field Alerts',
                                  style: AppTypography.h3,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _filter == 'all'
                                      ? 'All modules and safety interlocks are operating within normal parameters.'
                                      : 'No active alerts matching the selected "$_filter" filter.',
                                  textAlign: TextAlign.center,
                                  style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          _buildAdvisoryBanner(),
                        ],
                      );
                    }

                    return Column(
                      children: [
                        ...filteredAlerts.map((alert) {
                          String effectiveMeta = alert.metaText;
                          if (alert.panelIndex != null) {
                            final posStr = alert.xPositionCm != null
                                ? ' • X: ${alert.xPositionCm!.toStringAsFixed(1)} cm'
                                : '';
                            final locStr = alert.localXPositionCm != null
                                ? ' (Local: ${alert.localXPositionCm!.toStringAsFixed(1)} cm)'
                                : '';
                            effectiveMeta =
                                '${alert.moduleName} • Painel ${alert.panelIndex}$posStr$locStr';
                          }
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _buildAlertCard(
                              context: context,
                              title: alert.title,
                              timeAgo: _formatTimeAgo(alert.createdAt),
                              severity: alert.isCritical ? 'Critical' : 'Warning',
                              isCritical: alert.isCritical,
                              icon: alert.type == 'reservoir_low'
                                  ? Icons.water_drop_outlined
                                  : Icons.error_outline_rounded,
                              iconColor: alert.isCritical ? AppColors.error : AppColors.warning,
                              borderColor: alert.isCritical ? AppColors.error : AppColors.warning,
                              description: alert.description,
                              metaText: effectiveMeta,
                              actionLabel: alert.type == 'reservoir_low' ? 'Check Status' : 'View Module Details',
                              onTap: () {
                                if (alert.moduleId.isNotEmpty) {
                                  context.push('/modules/${alert.moduleId}');
                                }
                              },
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

  Widget _buildAlertCard({
    required BuildContext context,
    required String title,
    required String timeAgo,
    required String severity,
    required bool isCritical,
    required IconData icon,
    required Color iconColor,
    required Color borderColor,
    required String description,
    required String metaText,
    required String actionLabel,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, color: iconColor, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: AppTypography.body.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              timeAgo,
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: isCritical
                              ? AppColors.errorBackground
                              : AppColors.warningBackground,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: borderColor.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          severity.toUpperCase(),
                          style: AppTypography.caption.copyWith(
                            color: borderColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    description,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: AppColors.border),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          metaText,
                          style: AppTypography.caption.copyWith(
                            color: borderColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            actionLabel,
                            style: AppTypography.caption.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            size: 14,
                            color: AppColors.primary,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
