import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/core/utils/date_formatter.dart';
import 'package:thermoscan/core/widgets/top_app_bar.dart';
import 'package:thermoscan/features/auth/presentation/auth_controller.dart';
import 'package:thermoscan/features/modules/domain/inspection_routine_bundle.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';
import 'package:thermoscan/features/modules/presentation/modules_controller.dart';
import 'package:thermoscan/features/modules/presentation/widgets/module_sub_nav_bar.dart';

/// SCR-12: Module Details — Cleaning History
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

class _CleaningTimelineEntry {
  const _CleaningTimelineEntry.inspection({
    required this.bundle,
    required this.cleanings,
    required this.sortTime,
  }) : standaloneCleaning = null;

  const _CleaningTimelineEntry.standalone({
    required this.standaloneCleaning,
    required this.sortTime,
  })  : bundle = null,
        cleanings = const [];

  final InspectionRoutineBundle? bundle;
  final List<ModuleCleaning> cleanings;
  final ModuleCleaning? standaloneCleaning;
  final DateTime? sortTime;

  bool get isInspectionGroup => bundle != null;
}

class _ModuleCleaningsScreenState extends ConsumerState<ModuleCleaningsScreen> {
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final detailsAsync = ref.watch(moduleDetailsProvider(widget.moduleId));
    final cleaningsAsync = ref.watch(moduleCleaningsProvider(widget.moduleId));
    final inspectionsAsync =
        ref.watch(moduleInspectionsProvider(widget.moduleId));

    final mod = detailsAsync.valueOrNull?.module;
    final inspections =
        inspectionsAsync.valueOrNull ?? const <ModuleInspection>[];

    final content = RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        ref.invalidate(moduleCleaningsProvider(widget.moduleId));
        ref.invalidate(moduleInspectionsProvider(widget.moduleId));
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
                        'Cleaning History',
                        style: AppTypography.h2,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Automatic washing cycles & follow-up check',
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
                          'Automatic Washing Rules',
                          style: AppTypography.h3.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Up to 3 washes per hotspot. Before spraying, the robot checks the water level and makes sure the panel isn’t too hot. A follow-up scan runs 30 minutes after washing.',
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

            // Cleanings list grouped by inspection cycle
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

                final timelineEntries = _buildCleaningTimeline(
                  cleanings: cleanings,
                  inspections: inspections,
                );

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: timelineEntries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final entry = timelineEntries[index];
                    if (entry.isInspectionGroup) {
                      return _buildInspectionCleaningGroupCard(
                        bundle: entry.bundle!,
                        cleanings: entry.cleanings,
                        isLatest: index == 0,
                      );
                    }
                    final c = entry.standaloneCleaning!;
                    final isManualWash =
                        inspections.isNotEmpty || c.anomalyEventId.isEmpty;
                    return _buildCleaningCard(
                      c,
                      showManualBadge: isManualWash,
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
        title: mod != null ? '${mod.name} Cleanings' : 'Cleaning History',
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

  List<_CleaningTimelineEntry> _buildCleaningTimeline({
    required List<ModuleCleaning> cleanings,
    required List<ModuleInspection> inspections,
  }) {
    final entries = <_CleaningTimelineEntry>[];
    final claimedIds = <String>{};

    if (inspections.isNotEmpty) {
      final bundles = InspectionRoutineBundle.buildBundles(
        allInspections: inspections,
        allCleanings: cleanings,
        allMeasurements: const [],
      );

      for (final bundle in bundles) {
        if (bundle.cleanings.isEmpty) continue;
        final groupCleanings = <ModuleCleaning>[];
        for (final c in bundle.cleanings) {
          if (claimedIds.add(c.id)) {
            groupCleanings.add(c);
          }
        }
        if (groupCleanings.isEmpty) continue;

        final sortTime = _latestCleaningTime(groupCleanings) ??
            DateTime.tryParse(bundle.routineInspection.finishedAt ?? '') ??
            DateTime.tryParse(bundle.routineInspection.startedAt ?? '') ??
            DateTime.tryParse(bundle.routineInspection.scheduledFor) ??
            DateTime.tryParse(bundle.routineInspection.createdAt);

        entries.add(
          _CleaningTimelineEntry.inspection(
            bundle: bundle,
            cleanings: groupCleanings,
            sortTime: sortTime,
          ),
        );
      }
    }

    for (final c in cleanings) {
      if (claimedIds.contains(c.id)) continue;
      entries.add(
        _CleaningTimelineEntry.standalone(
          standaloneCleaning: c,
          sortTime: _cleaningTimestamp(c),
        ),
      );
    }

    entries.sort((a, b) {
      final dtA = a.sortTime;
      final dtB = b.sortTime;
      if (dtA != null && dtB != null) {
        return dtB.compareTo(dtA);
      }
      if (dtA != null || dtB != null) {
        return dtB != null ? 1 : -1;
      }
      return 0;
    });

    return entries;
  }

  DateTime? _cleaningTimestamp(ModuleCleaning c) {
    return DateTime.tryParse(c.startedAt ?? '') ??
        DateTime.tryParse(c.endedAt ?? '') ??
        DateTime.tryParse(c.createdAt);
  }

  DateTime? _latestCleaningTime(List<ModuleCleaning> list) {
    DateTime? latest;
    for (final c in list) {
      final dt = _cleaningTimestamp(c);
      if (dt != null && (latest == null || dt.isAfter(latest))) {
        latest = dt;
      }
    }
    return latest;
  }

  ({
    String label,
    Color bg,
    Color border,
    Color fg,
    IconData icon,
  }) _resolveCleaningGroupBadge({
    required InspectionRoutineBundle bundle,
    required List<ModuleCleaning> cleanings,
  }) {
    final summaries = bundle.hotspotSummaries;
    if (summaries.isNotEmpty) {
      final total = summaries.length;
      final resolved = bundle.resolvedCount;
      final resolvedLater = bundle.resolvedLaterCount;
      final unresolved = bundle.unresolvedCount;
      final pending = bundle.pendingCount;
      final cleared = resolved + resolvedLater;

      if (resolvedLater > 0 &&
          unresolved == 0 &&
          resolved == 0 &&
          pending == 0) {
        return (
          label: 'Cleared in Later Scan',
          bg: AppColors.primarySoft,
          border: AppColors.primary.withValues(alpha: 0.3),
          fg: AppColors.primary,
          icon: Icons.verified_outlined,
        );
      }
      if (cleared == total && total > 0) {
        return (
          label: total == 1 ? 'Resolved' : '$total/$total Resolved',
          bg: AppColors.successBackground,
          border: AppColors.successBorder,
          fg: AppColors.success,
          icon: Icons.check_circle_outline_rounded,
        );
      }
      if (cleared > 0 && (unresolved > 0 || pending > 0)) {
        return (
          label: '$cleared/$total Resolved',
          bg: AppColors.warningBackground,
          border: AppColors.warningBorder,
          fg: AppColors.warning,
          icon: Icons.rule_rounded,
        );
      }
      if (unresolved > 0) {
        return (
          label: unresolved == 1 ? 'Unresolved' : '$unresolved Unresolved',
          bg: AppColors.errorBackground,
          border: AppColors.errorBorder,
          fg: AppColors.error,
          icon: Icons.warning_amber_rounded,
        );
      }
      if (pending > 0) {
        return (
          label: 'Verification Pending',
          bg: AppColors.primarySoft,
          border: AppColors.primary.withValues(alpha: 0.3),
          fg: AppColors.primary,
          icon: Icons.hourglass_top_rounded,
        );
      }
    }

    // Fallback based on individual cleaning statuses
    final total = cleanings.length;
    final resolvedCount = cleanings
        .where(
          (c) =>
              c.postCleaningResult == 'resolved' ||
              c.postCleaningResult == 'verified_resolved',
        )
        .length;
    final pendingCount =
        cleanings.where((c) => c.postCleaningResult == 'pending').length;
    final failedCount = cleanings.where((c) => c.status == 'failed').length;
    final refusedCount = cleanings.where((c) => c.status == 'refused').length;

    if (resolvedCount == total && total > 0) {
      return (
        label: total == 1 ? 'Resolved' : '$total/$total Resolved',
        bg: AppColors.successBackground,
        border: AppColors.successBorder,
        fg: AppColors.success,
        icon: Icons.check_circle_outline_rounded,
      );
    }
    if (pendingCount > 0) {
      return (
        label: 'Verification Pending',
        bg: AppColors.primarySoft,
        border: AppColors.primary.withValues(alpha: 0.3),
        fg: AppColors.primary,
        icon: Icons.hourglass_top_rounded,
      );
    }
    if (failedCount > 0) {
      return (
        label: 'Interrupted',
        bg: AppColors.errorBackground,
        border: AppColors.errorBorder,
        fg: AppColors.error,
        icon: Icons.error_outline_rounded,
      );
    }
    if (refusedCount == total && total > 0) {
      return (
        label: 'Safety Hold',
        bg: AppColors.warningBackground,
        border: AppColors.warningBorder,
        fg: AppColors.warning,
        icon: Icons.pause_circle_outline_rounded,
      );
    }
    return (
      label: '$total ${total == 1 ? 'Wash' : 'Washes'}',
      bg: AppColors.primarySoft,
      border: AppColors.primary.withValues(alpha: 0.3),
      fg: AppColors.primary,
      icon: Icons.water_drop_outlined,
    );
  }

  Widget _buildInspectionCleaningGroupCard({
    required InspectionRoutineBundle bundle,
    required List<ModuleCleaning> cleanings,
    required bool isLatest,
  }) {
    final insp = bundle.routineInspection;
    final dateIso = insp.finishedAt ??
        insp.startedAt ??
        (insp.scheduledFor.isNotEmpty ? insp.scheduledFor : insp.createdAt);
    final dateLabel = _formatReadableTimestamp(dateIso);

    final badge = _resolveCleaningGroupBadge(
      bundle: bundle,
      cleanings: cleanings,
    );

    double totalDurationSec = 0;
    bool hasDuration = false;

    for (final c in cleanings) {
      if (c.durationSeconds != null) {
        totalDurationSec += c.durationSeconds!;
        hasDuration = true;
      }
    }

    final washCountLabel =
        '${cleanings.length} ${cleanings.length == 1 ? 'wash' : 'washes'}';
    final totalDurationLabel =
        hasDuration ? _formatDurationAggregate(totalDurationSec) : 'N/A';

    return Container(
      key: Key('cleaning_group_card_${insp.id}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLatest
              ? AppColors.primary.withValues(alpha: 0.45)
              : AppColors.border,
          width: isLatest ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Date + LATEST chip + Outcome Pill
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      dateLabel,
                      style: AppTypography.bodySmall.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (isLatest)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'LATEST',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800,
                            fontSize: 9,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: badge.bg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: badge.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badge.icon, size: 13, color: badge.fg),
                    const SizedBox(width: 4),
                    Text(
                      badge.label,
                      style: AppTypography.caption.copyWith(
                        color: badge.fg,
                        fontWeight: FontWeight.w700,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Aggregate Metrics Strip (matching Inspection History card style)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildCompactMetricCell(
                    label: 'Washes',
                    value: washCountLabel,
                  ),
                ),
                Container(width: 1, height: 24, color: AppColors.border),
                Expanded(
                  child: _buildCompactMetricCell(
                    label: 'Total Duration',
                    value: totalDurationLabel,
                    valueColor: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),

          // Individual washes: inline if <= 2, collapsible ExpansionTile if > 2
          if (cleanings.length <= 2) ...[
            const SizedBox(height: 12),
            for (var i = 0; i < cleanings.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _buildCleaningCard(cleanings[i], compact: true),
            ],
          ] else ...[
            const SizedBox(height: 4),
            Material(
              color: Colors.transparent,
              child: Theme(
                data: Theme.of(context).copyWith(
                  dividerColor: Colors.transparent,
                ),
                child: ExpansionTile(
                  key: Key('show_washes_tile_${insp.id}'),
                  initiallyExpanded: false,
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(top: 6),
                  dense: true,
                  title: Text(
                    'Show ${cleanings.length} ${cleanings.length == 1 ? "wash" : "washes"}',
                    style: AppTypography.bodySmall.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  children: [
                    for (var i = 0; i < cleanings.length; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      _buildCleaningCard(cleanings[i], compact: true),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactMetricCell({
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTypography.caption.copyWith(
            fontSize: 10,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTypography.bodySmall.copyWith(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: valueColor ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  String _formatDurationAggregate(double seconds) {
    if (seconds >= 60) {
      final mins = (seconds / 60).floor();
      final rem = (seconds % 60).round();
      return '${mins}m ${rem}s';
    }
    return '${seconds.toStringAsFixed(1)} s';
  }

  String _formatReadableTimestamp(String? isoString) {
    if (isoString == null || isoString.isEmpty) return 'N/A';
    final dt = DateTime.tryParse(isoString);
    if (dt == null) return isoString;
    return AppDateFormatter.formatDateTime(
      dt,
      includeYear: true,
      fallback: 'N/A',
    );
  }

  Widget _buildCleaningCard(
    ModuleCleaning c, {
    bool compact = false,
    bool showManualBadge = false,
  }) {
    Color statusBg = AppColors.successBackground;
    Color statusBorder = AppColors.successBorder;
    Color statusText = AppColors.success;
    String statusLabel = 'VERIFIED POST-CLEAN';

    final isTargetInGap = c.failureReason == 'target_in_gap';

    if (isTargetInGap) {
      statusBg = AppColors.warningBackground;
      statusBorder = AppColors.warningBorder;
      statusText = AppColors.warning;
      statusLabel = 'SKIPPED (GAP BETWEEN PANELS)';
    } else if (c.status == 'refused') {
      statusBg = AppColors.warningBackground;
      statusBorder = AppColors.warningBorder;
      statusText = AppColors.warning;
      statusLabel = 'PAUSED (SAFETY CHECK)';
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

    final panelPrefix = c.panelIndex != null ? 'Panel ${c.panelIndex} • ' : '';

    return Container(
      padding: EdgeInsets.all(compact ? 14 : 18),
      decoration: BoxDecoration(
        color: compact ? AppColors.background : AppColors.surface,
        borderRadius: BorderRadius.circular(compact ? 12 : 16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showManualBadge) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.touch_app_outlined,
                    size: 12,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Manual Wash',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.status == 'refused'
                          ? '${panelPrefix}Cleaning Request (Refused)'
                          : (!c.pumpActuated
                              ? '${panelPrefix}Safety Hold (Pump Inactive)'
                              : (c.attemptNumber != null
                                  ? '${panelPrefix}Wash Attempt #${c.attemptNumber} • Spot Wash'
                                  : '${panelPrefix}Wash Request • Spot Wash')),
                      style: AppTypography.h3.copyWith(
                        fontSize: compact ? 13.5 : 15,
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
                flex: 2,
                child: _buildMetricCol(
                  'Position',
                  c.panelIndex != null
                      ? 'Panel ${c.panelIndex} • X: ${c.targetXPositionCm.toStringAsFixed(1)} cm${c.localXPositionCm != null ? " (Local: ${c.localXPositionCm!.toStringAsFixed(1)} cm)" : ""}'
                      : 'X: ${c.targetXPositionCm.toStringAsFixed(1)} cm',
                  AppColors.textPrimary,
                ),
              ),
              Expanded(
                child: _buildMetricCol(
                  'Duration',
                  duration,
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
            'The robot washes panels automatically when a hotspot is confirmed across scans and water is available.',
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
    return AppDateFormatter.formatDateTime(
      parsed,
      includeYear: true,
      fallback: isoString,
    );
  }
}
