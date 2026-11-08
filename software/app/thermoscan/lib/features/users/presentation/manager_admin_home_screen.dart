import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/core/widgets/top_app_bar.dart';
import 'package:thermoscan/features/auth/presentation/auth_controller.dart';
import 'package:thermoscan/features/modules/presentation/modules_controller.dart';
import 'package:thermoscan/features/users/presentation/users_controller.dart';

/// SCR-24: Administration Home (Manager)
class ManagerAdminHomeScreen extends ConsumerWidget {
  const ManagerAdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final usersAsync = ref.watch(companyUsersProvider);
    final modulesAsync = ref.watch(modulesListProvider);

    final users = usersAsync.valueOrNull ?? const [];
    final modules = modulesAsync.valueOrNull ?? const [];
    final managersCount = users.where((u) => u.isManager).length;
    final techsCount = users.where((u) => u.isTechnician).length;
    final clientsCount = users.where((u) => u.isClient).length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: ThermoScanAppBar(
        role: user?.role ?? 'manager',
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            await Future.wait([
              ref.read(companyUsersProvider.notifier).refresh(),
              ref.read(modulesListProvider.notifier).refresh(),
            ]);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Administration',
                  style: AppTypography.h2,
                ),
                const SizedBox(height: 4),
                Text(
                  'Manage company solar panels, personnel, and client accounts',
                  style: AppTypography.bodySmall,
                ),
                const SizedBox(height: 20),

                // Summary Metrics 2x2 Grid (prevents label wrapping on narrow screens)
                Row(
                  children: [
                    Expanded(
                      child: _MetricCard(
                        label: 'Solar Panels',
                        value:
                            modulesAsync.isLoading ? '—' : '${modules.length}',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MetricCard(
                        label: 'Managers',
                        value: usersAsync.isLoading ? '—' : '$managersCount',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _MetricCard(
                        label: 'Technicians',
                        value: usersAsync.isLoading ? '—' : '$techsCount',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MetricCard(
                        label: 'Clients',
                        value: usersAsync.isLoading ? '—' : '$clientsCount',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Hub Card 0: Solar Panels (SCR-09)
                _AdminHubCard(
                  icon: Icons.solar_power_outlined,
                  title: 'Solar Panels',
                  subtitle: 'Solar panel systems, settings, and access',
                  badgeText:
                      modulesAsync.isLoading ? null : '${modules.length}',
                  onTap: () => context.push('/modules'),
                ),
                const SizedBox(height: 12),

                // Hub Card 1: Company Users (SCR-30)
                _AdminHubCard(
                  icon: Icons.badge_outlined,
                  title: 'Company Users',
                  subtitle: 'Managers & Field Technicians',
                  badgeText:
                      usersAsync.isLoading ? null : '${managersCount + techsCount}',
                  onTap: () => context.push('/manager/users'),
                ),
                const SizedBox(height: 12),

                // Hub Card 2: Clients (SCR-31)
                _AdminHubCard(
                  icon: Icons.groups_outlined,
                  title: 'Clients',
                  subtitle: 'Client accounts & credentials',
                  badgeText: usersAsync.isLoading ? null : '$clientsCount',
                  onTap: () => context.push('/manager/clients'),
                ),
                const SizedBox(height: 12),

                // Hub Card 3: Own Profile & Password (SCR-23)
                _AdminHubCard(
                  icon: Icons.manage_accounts_outlined,
                  title: 'Account Profile',
                  subtitle: 'Edit your name, email, or password',
                  onTap: () => context.push('/profile'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Text(
            label.toUpperCase(),
            style: AppTypography.caption.copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTypography.h3.copyWith(color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}

class _AdminHubCard extends StatelessWidget {
  const _AdminHubCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badgeText,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? badgeText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Icon(icon, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.h3,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTypography.bodySmall,
                    ),
                  ],
                ),
              ),
              if (badgeText != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    badgeText!,
                    style: AppTypography.dataValue.copyWith(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              const Icon(
                Icons.chevron_right,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
