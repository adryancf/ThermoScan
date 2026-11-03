import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/core/widgets/app_buttons.dart';
import 'package:thermoscan/core/widgets/app_text_field.dart';
import 'package:thermoscan/core/widgets/top_app_bar.dart';
import 'package:thermoscan/features/alerts/presentation/alerts_controller.dart';
import 'package:thermoscan/features/auth/presentation/auth_controller.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';
import 'package:thermoscan/features/modules/presentation/modules_controller.dart';

/// SCR-09: Modules Home (Manager, Technician, Client)
class ModulesHomeScreen extends ConsumerStatefulWidget {
  const ModulesHomeScreen({
    super.key,
    this.showBackButton = false,
  });

  final bool showBackButton;

  @override
  ConsumerState<ModulesHomeScreen> createState() => _ModulesHomeScreenState();
}

class _ModulesHomeScreenState extends ConsumerState<ModulesHomeScreen> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _statusFilter = 'all'; // 'all', 'active', 'pending_configuration'

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final modulesAsync = ref.watch(modulesListProvider);
    final isTechnician = user?.isTechnician ?? false;

    String subtitle = 'Accessible photovoltaic modules';
    if (user?.isManager ?? false) {
      subtitle = 'All photovoltaic modules registered in your company';
    } else if (isTechnician) {
      subtitle = 'Modules you installed or were granted access to view';
    } else if (user?.isClient ?? false) {
      subtitle = 'Photovoltaic modules assigned to your account';
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: ThermoScanAppBar(
        title: widget.showBackButton ? 'Company Modules' : 'ThermoScan',
        role: user?.role ?? 'technician',
        showBack: widget.showBackButton,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () => ref.read(modulesListProvider.notifier).refresh(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
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
                                Text(
                                  'PV Modules',
                                  style: AppTypography.h2,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  subtitle,
                                  style: AppTypography.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          if (isTechnician) ...[
                            const SizedBox(width: 12),
                            FilledButton.icon(
                              onPressed: () => context.push('/modules/install'),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Install'),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        label: 'Search Modules',
                        hintText: 'Filter by module name or MAC address...',
                        controller: _searchCtrl,
                        prefixIcon: Icons.search,
                        onChanged: (val) => setState(() {
                          _searchQuery = val.trim().toLowerCase();
                        }),
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _FilterChipButton(
                              label: 'All',
                              selected: _statusFilter == 'all',
                              onTap: () =>
                                  setState(() => _statusFilter = 'all'),
                            ),
                            const SizedBox(width: 8),
                            _FilterChipButton(
                              label: 'Configured',
                              selected: _statusFilter == 'active',
                              onTap: () =>
                                  setState(() => _statusFilter = 'active'),
                            ),
                            const SizedBox(width: 8),
                            _FilterChipButton(
                              label: 'Pending Config',
                              selected:
                                  _statusFilter == 'pending_configuration',
                              onTap: () => setState(() =>
                                  _statusFilter = 'pending_configuration'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              modulesAsync.when(
                loading: () => const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                ),
                error: (err, _) => SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: AppColors.error,
                          size: 40,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          err.toString(),
                          textAlign: TextAlign.center,
                          style: AppTypography.body,
                        ),
                        const SizedBox(height: 16),
                        SecondaryButton(
                          label: 'Retry',
                          fullWidth: false,
                          onPressed: () =>
                              ref.read(modulesListProvider.notifier).refresh(),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (modules) {
                  final filtered = modules.where((m) {
                    if (_statusFilter != 'all' &&
                        m.monitoringStatus != _statusFilter) {
                      return false;
                    }
                    if (_searchQuery.isEmpty) return true;
                    return m.name.toLowerCase().contains(_searchQuery) ||
                        m.macAddress.toLowerCase().contains(_searchQuery) ||
                        m.installerName.toLowerCase().contains(_searchQuery);
                  }).toList();

                  if (filtered.isEmpty) {
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Container(
                            width: double.infinity,
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
                                  Icons.solar_power_outlined,
                                  size: 40,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  modules.isEmpty
                                      ? 'No modules available'
                                      : 'No matching modules',
                                  style: AppTypography.h3,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  modules.isEmpty
                                      ? (isTechnician
                                          ? 'Start a new module installation to register a photovoltaic array and its embedded device.'
                                          : 'No photovoltaic modules are currently accessible for your account.')
                                      : 'Try adjusting your search query or status filter.',
                                  textAlign: TextAlign.center,
                                  style: AppTypography.bodySmall,
                                ),
                                if (modules.isEmpty && isTechnician) ...[
                                  const SizedBox(height: 18),
                                  PrimaryButton(
                                    label: 'Start Installation',
                                    icon: Icons.add_circle_outline,
                                    onPressed: () =>
                                        context.push('/modules/install'),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                    sliver: SliverList.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final mod = filtered[index];
                        return _ModuleListCard(
                          module: mod,
                          onTap: () => context.push('/modules/${mod.id}'),
                        );
                      },
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModuleListCard extends ConsumerWidget {
  const _ModuleListCard({
    required this.module,
    required this.onTap,
  });

  final PvModule module;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPending = module.isPendingConfiguration;
    final alertsSummary = ref.watch(alertsSummaryProvider).valueOrNull;
    final hasAlert =
        alertsSummary?.alerts.any((a) => a.moduleId == module.id) ?? false;

    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isPending ? AppColors.warningBorder : AppColors.border,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          module.name,
                          style: AppTypography.h3,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.memory_outlined,
                              size: 14,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              module.macAddress,
                              style:
                                  AppTypography.dataValue.copyWith(fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (hasAlert) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.errorBackground,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.errorBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            size: 13,
                            color: AppColors.error,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Alert',
                            style: AppTypography.chip.copyWith(
                              color: AppColors.error,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  ModuleMonitoringStatusBadge(status: module.monitoringStatus),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _ConnectionStatusPill(module: module),
                  _RelationshipBadge(label: module.relationshipLabel),
                  if (module.panelCount != null &&
                      module.panelLengthCm != null &&
                      module.panelWidthCm != null)
                    _InfoPill(
                      icon: Icons.grid_view_outlined,
                      label:
                          '${module.panelCount} panels (${module.panelLengthCm!.toStringAsFixed(0)}×${module.panelWidthCm!.toStringAsFixed(0)} cm)',
                    ),
                  _InfoPill(
                    icon: Icons.schedule_outlined,
                    label: 'Every ${module.inspectionIntervalDays}d',
                  ),
                ],
              ),
              if (isPending && module.permissions.canEditGeometryAndLocation) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warningBackground,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.warningBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.pending_actions_outlined,
                        size: 16,
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Draft installation — tap to continue configuration',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.warning,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios,
                        size: 12,
                        color: AppColors.warning,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ModuleMonitoringStatusBadge extends StatelessWidget {
  const ModuleMonitoringStatusBadge({
    super.key,
    required this.status,
  });

  final String status;

  @override
  Widget build(BuildContext context) {
    Color bg = AppColors.background;
    Color border = AppColors.border;
    Color text = AppColors.textSecondary;
    String label = status;

    switch (status) {
      case 'active':
        bg = AppColors.primarySoft.withValues(alpha: 0.45);
        border = AppColors.border;
        text = AppColors.primary;
        label = 'Configured';
        break;
      case 'pending_configuration':
        bg = AppColors.warningBackground;
        border = AppColors.warningBorder;
        text = AppColors.warning;
        label = 'Pending Config';
        break;
      case 'maintenance':
        bg = AppColors.warningBackground;
        border = AppColors.warningBorder;
        text = AppColors.warning;
        label = 'Maintenance';
        break;
      case 'inactive':
        bg = AppColors.errorBackground;
        border = AppColors.errorBorder;
        text = AppColors.error;
        label = 'Inactive';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: text,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTypography.chip.copyWith(color: text),
          ),
        ],
      ),
    );
  }
}

class _ConnectionStatusPill extends StatelessWidget {
  const _ConnectionStatusPill({required this.module});

  final PvModule module;

  String _formatLastSeen(String? lastPingAt) {
    if (lastPingAt == null || lastPingAt.isEmpty) return 'Never Connected';
    final dt = DateTime.tryParse(lastPingAt)?.toLocal();
    if (dt == null) return 'Never Connected';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Seen just now';
    if (diff.inMinutes < 60) return 'Seen ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Seen ${diff.inHours}h ago';
    return 'Seen ${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = module.isOnline;
    final lastPing = module.lastPingAt;
    final hasPing = lastPing != null && lastPing.isNotEmpty;

    Color bg;
    Color border;
    Color text;
    IconData icon;
    String label;

    if (isOnline) {
      bg = AppColors.successBackground;
      border = AppColors.successBorder;
      text = AppColors.success;
      icon = Icons.wifi_rounded;
      label = 'Online';
    } else if (hasPing) {
      bg = AppColors.warningBackground;
      border = AppColors.warningBorder;
      text = AppColors.warning;
      icon = Icons.wifi_off_rounded;
      label = _formatLastSeen(lastPing);
    } else {
      bg = AppColors.background;
      border = AppColors.border;
      text = AppColors.textSecondary;
      icon = Icons.wifi_off_rounded;
      label = 'Never Connected';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: text,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppTypography.caption.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: text,
            ),
          ),
        ],
      ),
    );
  }
}

class _RelationshipBadge extends StatelessWidget {
  const _RelationshipBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primarySoft.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTypography.caption.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.chip.copyWith(
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
