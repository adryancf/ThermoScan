import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/core/widgets/top_app_bar.dart';
import 'package:thermoscan/features/auth/presentation/auth_controller.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';
import 'package:thermoscan/features/modules/presentation/modules_controller.dart';
import 'package:thermoscan/features/modules/presentation/widgets/module_sub_nav_bar.dart';

/// SCR-12: Module Details — Actuator Wash Log / Cleanings
class ModuleCleaningsScreen extends ConsumerStatefulWidget {
  const ModuleCleaningsScreen({
    super.key,
    required this.moduleId,
    this.showAppBar = true,
  });

  final String moduleId;
  final bool showAppBar;

  @override
  ConsumerState<ModuleCleaningsScreen> createState() =>
      _ModuleCleaningsScreenState();
}

class ModuleCleaningsView extends StatelessWidget {
  const ModuleCleaningsView({
    super.key,
    required this.moduleId,
  });

  final String moduleId;

  @override
  Widget build(BuildContext context) {
    return ModuleCleaningsScreen(
      moduleId: moduleId,
      showAppBar: false,
    );
  }
}

class _ModuleCleaningsScreenState extends ConsumerState<ModuleCleaningsScreen> {
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final detailsAsync = ref.watch(moduleDetailsProvider(widget.moduleId));
    final cleaningsAsync = ref.watch(moduleCleaningsProvider(widget.moduleId));

    final mod = detailsAsync.valueOrNull?.module;

    final content = RefreshIndicator(
      color: AppColors.primary,
                onRefresh: () async {
                  ref.invalidate(moduleCleaningsProvider(widget.moduleId));
                  await ref.read(
                    moduleCleaningsProvider(widget.moduleId).future,
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
                                  'Actuator Wash Log',
                                  style: AppTypography.h2,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Autonomous water spray cycles & post-clean verification',
                                  style: AppTypography.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Safety Interlock Advisory Card (matching AGENT_CONTEXT.md Section 13)
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
                              Icons.water_drop_outlined,
                              color: AppColors.primary,
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Safety Interlocks & Budget Limit',
                                    style: AppTypography.h3.copyWith(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Max 3 wash attempts per hotspot event. Each cycle evaluates capacitive water reserve (water_available) and thermal safety. Post-clean verification scans run ≥ 30 min after pump actuation.',
                                    style: AppTypography.caption.copyWith(
                                      color: AppColors.textSecondary,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Cleanings list
                      cleaningsAsync.when(
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
                            'Failed to load wash logs: $err',
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.error,
                            ),
                          ),
                        ),
                        data: (cleanings) {
                          if (cleanings.isEmpty) {
                            return _buildEmptyState();
                          }

                          return ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: cleanings.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              return _buildCleaningCard(cleanings[index]);
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
        title: mod != null ? '${mod.name} Cleanings' : 'Actuator Wash Log',
        role: user?.role,
        showBack: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (mod != null)
              ModuleSubNavBar(
                moduleId: widget.moduleId,
                currentTab: 'cleanings',
                canManageAccess: mod.permissions.canManageAccess,
                isPendingConfig: mod.isPendingConfiguration,
              ),
            Expanded(
              child: content,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCleaningCard(ModuleCleaning c) {
    Color statusBg = AppColors.successBackground;
    Color statusBorder = AppColors.successBorder;
    Color statusText = AppColors.success;
    String statusLabel = 'VERIFIED POST-CLEAN';

    final isTargetInGap = c.failureReason == 'target_in_gap';

    if (isTargetInGap) {
      statusBg = AppColors.warningBackground;
      statusBorder = AppColors.warningBorder;
      statusText = AppColors.warning;
      statusLabel = 'RECUSADA (NO GAP)';
    } else if (c.status == 'refused') {
      statusBg = AppColors.warningBackground;
      statusBorder = AppColors.warningBorder;
      statusText = AppColors.warning;
      statusLabel = 'REFUSED (SAFETY LOCK)';
    } else if (c.status == 'failed') {
      statusBg = AppColors.errorBackground;
      statusBorder = AppColors.errorBorder;
      statusText = AppColors.error;
      statusLabel = 'INTERRUPTED';
    } else if (c.postCleaningResult == 'pending') {
      statusBg = AppColors.primarySoft.withValues(alpha: 0.3);
      statusBorder = AppColors.primary.withValues(alpha: 0.3);
      statusText = AppColors.primary;
      statusLabel = 'VERIFICATION PENDING (≥30m)';
    }

    final duration = c.durationSeconds != null
        ? '${c.durationSeconds!.toStringAsFixed(1)} sec'
        : 'N/A';
    final fluid = c.estimatedWaterVolumeMl != null
        ? '${c.estimatedWaterVolumeMl!.toStringAsFixed(0)} mL'
        : 'N/A';

    final panelPrefix = c.panelIndex != null ? 'Painel ${c.panelIndex} • ' : '';

    return Container(
      padding: const EdgeInsets.all(18),
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
                      c.attemptNumber != null
                          ? '${panelPrefix}Wash Attempt #${c.attemptNumber} • Localized Traverse'
                          : '${panelPrefix}Wash Request • Localized Traverse',
                      style: AppTypography.h3.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      c.startedAt != null
                          ? 'Executed ${_formatDate(c.startedAt!)}'
                          : 'Logged ${_formatDate(c.createdAt)}',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: statusBorder),
                ),
                child: Text(
                  statusLabel,
                  style: AppTypography.caption.copyWith(
                    color: statusText,
                    fontWeight: FontWeight.w800,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Association to Origin Measurement / Hotspot
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.link_rounded,
                  size: 15,
                  color: AppColors.secondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Associated Hotspot: ${panelPrefix}X = ${c.targetXPositionCm.toStringAsFixed(1)} cm${c.localXPositionCm != null ? " (Local: ${c.localXPositionCm!.toStringAsFixed(1)} cm)" : ""} (Anomaly ${c.anomalyEventId.length > 8 ? c.anomalyEventId.substring(0, 8) : c.anomalyEventId})',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 10.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (c.failureReason != null && c.failureReason!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                isTargetInGap
                    ? 'Safety Reason: Target located in inter-panel gap (${c.targetXPositionCm.toStringAsFixed(1)} cm). Spray aborted to preserve water.'
                    : 'Safety Reason: ${c.failureReason}',
                style: AppTypography.caption.copyWith(
                  color: AppColors.warning,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMetricCol(
                  'Position',
                  c.panelIndex != null
                      ? 'Painel ${c.panelIndex} • X: ${c.targetXPositionCm.toStringAsFixed(1)} cm${c.localXPositionCm != null ? " (Local: ${c.localXPositionCm!.toStringAsFixed(1)} cm)" : ""}'
                      : 'X: ${c.targetXPositionCm.toStringAsFixed(1)} cm',
                  AppColors.textPrimary,
                ),
              ),
              Expanded(
                child: _buildMetricCol(
                  'Duration',
                  duration,
                  AppColors.textPrimary,
                ),
              ),
              Expanded(
                child: _buildMetricCol(
                  'Fluid Est.',
                  fluid,
                  AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCol(String label, String value, Color valColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.caption.copyWith(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTypography.dataValue.copyWith(
            fontWeight: FontWeight.w700,
            color: valColor,
          ),
        ),
      ],
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
            Icons.wash_outlined,
            size: 44,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 14),
          Text(
            'No Cleaning Cycles Recorded',
            style: AppTypography.h3,
          ),
          const SizedBox(height: 6),
          Text(
            'Actuator spray routines execute autonomously when a localized thermal hotspot is confirmed across consecutive acquisitions and safety interlocks allow water delivery.',
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
