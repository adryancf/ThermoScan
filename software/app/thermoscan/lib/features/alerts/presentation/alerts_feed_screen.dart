import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/core/widgets/top_app_bar.dart';
import 'package:thermoscan/features/auth/presentation/auth_controller.dart';
import 'package:thermoscan/features/modules/presentation/modules_controller.dart';

/// SCR-21: Active Field Alerts Feed
class AlertsFeedScreen extends ConsumerStatefulWidget {
  const AlertsFeedScreen({super.key});

  @override
  ConsumerState<AlertsFeedScreen> createState() => _AlertsFeedScreenState();
}

class _AlertsFeedScreenState extends ConsumerState<AlertsFeedScreen> {
  String _filter = 'all'; // 'all', 'critical', 'warning'

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final modulesAsync = ref.watch(modulesListProvider);

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
            ref.invalidate(modulesListProvider);
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

                // Severity Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('all', 'All Alerts (2)'),
                      const SizedBox(width: 8),
                      _buildFilterChip('critical', 'Critical (1)'),
                      const SizedBox(width: 8),
                      _buildFilterChip('warning', 'Warning (1)'),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Alerts List
                modulesAsync.when(
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  error: (error, _) => Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      'Failed to load modules: $error',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ),
                  data: (modules) {
                    final firstModule = modules.isNotEmpty ? modules.first : null;
                    final firstModuleName = firstModule?.name ?? 'PV-001 (Main Array)';
                    final firstModuleId = firstModule?.id;

                    return Column(
                      children: [
                        // Alert 1: Unresolved Hotspot (Critical)
                        if (_filter == 'all' || _filter == 'critical') ...[
                          _buildAlertCard(
                            context: context,
                            title: 'Hotspot Unresolved: $firstModuleName',
                            timeAgo: '12m ago',
                            severity: 'Critical',
                            isCritical: true,
                            icon: Icons.error_outline_rounded,
                            iconColor: AppColors.error,
                            borderColor: AppColors.error,
                            description:
                                'Thermal anomaly confirmed across consecutive acquisitions at coordinate X=12 cm. Temperature delta > +10.0°C over baseline. Cleaning budget limit: 1 of 3 wash attempts registered.',
                            metaText: 'Delta: +15.3°C vs Baseline (Med)',
                            actionLabel: 'View Module Details',
                            onTap: () {
                              if (firstModuleId != null) {
                                context.push('/modules/$firstModuleId');
                              }
                            },
                          ),
                          const SizedBox(height: 14),
                        ],

                        // Alert 2: Low Reservoir Water (Warning)
                        if (_filter == 'all' || _filter == 'warning') ...[
                          _buildAlertCard(
                            context: context,
                            title: 'Reservoir Low: $firstModuleName',
                            timeAgo: '1h ago',
                            severity: 'Warning',
                            isCritical: false,
                            icon: Icons.water_drop_outlined,
                            iconColor: AppColors.warning,
                            borderColor: AppColors.warning,
                            description:
                                'Capacitive binary water sensor tripped (water_available=false). Water level is below safety minimum threshold. Autonomous wash cycles are blocked until manual refill.',
                            metaText: 'Safety Interlock: Wash Cycles Blocked',
                            actionLabel: 'Check Status',
                            onTap: () {
                              if (firstModuleId != null) {
                                context.push('/modules/$firstModuleId');
                              }
                            },
                          ),
                          const SizedBox(height: 14),
                        ],

                        // Informational Advisory banner
                        Container(
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
                        ),
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
