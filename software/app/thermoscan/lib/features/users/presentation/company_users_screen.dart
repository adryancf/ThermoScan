import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/core/widgets/app_buttons.dart';
import 'package:thermoscan/core/widgets/status_chips.dart';
import 'package:thermoscan/core/widgets/top_app_bar.dart';
import 'package:thermoscan/features/auth/presentation/auth_controller.dart';
import 'package:thermoscan/features/users/domain/user_models.dart';
import 'package:thermoscan/features/users/presentation/user_action_dialogs.dart';
import 'package:thermoscan/features/users/presentation/users_controller.dart';

enum _TeamFilter {
  all,
  managers,
  technicians,
  inactive,
}

/// SCR-30: Company Users List (Managers & Technicians)
class CompanyUsersScreen extends ConsumerStatefulWidget {
  const CompanyUsersScreen({super.key});

  @override
  ConsumerState<CompanyUsersScreen> createState() => _CompanyUsersScreenState();
}

class _CompanyUsersScreenState extends ConsumerState<CompanyUsersScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  _TeamFilter _filter = _TeamFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<CompanyUser> _applyFilter(List<CompanyUser> allUsers) {
    final teamUsers =
        allUsers.where((u) => u.isManager || u.isTechnician).toList();
    final query = _searchQuery.trim().toLowerCase();

    return teamUsers.where((u) {
      if (_filter == _TeamFilter.managers && !u.isManager) return false;
      if (_filter == _TeamFilter.technicians && !u.isTechnician) return false;
      if (_filter == _TeamFilter.inactive && u.isActive) return false;

      if (query.isEmpty) return true;
      return u.name.toLowerCase().contains(query) ||
          u.email.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authControllerProvider).user;
    final usersAsync = ref.watch(companyUsersProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const ThermoScanAppBar(
        title: 'Company Users',
        showBack: true,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/manager/users/new'),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.surface,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        tooltip: 'Create User',
        child: const Icon(Icons.add, size: 26),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () =>
              ref.read(companyUsersProvider.notifier).refresh(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _searchController,
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value;
                          });
                        },
                        style: AppTypography.body.copyWith(fontSize: 15),
                        decoration: InputDecoration(
                          hintText: 'Search by name or email...',
                          prefixIcon: const Icon(
                            Icons.search,
                            color: AppColors.textSecondary,
                            size: 20,
                          ),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {
                                      _searchQuery = '';
                                    });
                                  },
                                  icon: const Icon(
                                    Icons.clear,
                                    size: 18,
                                    color: AppColors.textSecondary,
                                  ),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _FilterChipButton(
                              label: 'All',
                              selected: _filter == _TeamFilter.all,
                              onTap: () =>
                                  setState(() => _filter = _TeamFilter.all),
                            ),
                            const SizedBox(width: 8),
                            _FilterChipButton(
                              label: 'Managers',
                              selected: _filter == _TeamFilter.managers,
                              onTap: () => setState(
                                () => _filter = _TeamFilter.managers,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _FilterChipButton(
                              label: 'Technicians',
                              selected: _filter == _TeamFilter.technicians,
                              onTap: () => setState(
                                () => _filter = _TeamFilter.technicians,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _FilterChipButton(
                              label: 'Inactive',
                              selected: _filter == _TeamFilter.inactive,
                              onTap: () => setState(
                                () => _filter = _TeamFilter.inactive,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              usersAsync.when(
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
                        Text(
                          err.toString(),
                          textAlign: TextAlign.center,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.error,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SecondaryButton(
                          label: 'Retry',
                          icon: Icons.refresh,
                          fullWidth: false,
                          onPressed: () => ref
                              .read(companyUsersProvider.notifier)
                              .refresh(),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (allUsers) {
                  final filtered = _applyFilter(allUsers);
                  final managers =
                      allUsers.where((u) => u.isManager).toList();

                  if (filtered.isEmpty) {
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            'No matching users found.',
                            style: AppTypography.bodySmall,
                          ),
                        ),
                      ),
                    );
                  }

                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 96),
                    sliver: SliverList.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final item = filtered[index];
                        final isCurrentUser =
                            currentUser != null && item.id == currentUser.id;
                        return _TeamUserCard(
                          user: item,
                          isCurrentUser: isCurrentUser,
                          onManageManagers: item.isTechnician
                              ? () => showTechnicianManagersDialog(
                                    context: context,
                                    technician: item,
                                    availableManagers: managers,
                                  )
                              : null,
                          onResetPassword: item.isTechnician
                              ? () => confirmAndResetUserPassword(
                                    context: context,
                                    ref: ref,
                                    targetUser: item,
                                  )
                              : null,
                          onToggleStatus: item.isTechnician
                              ? () => confirmAndToggleUserStatus(
                                    context: context,
                                    ref: ref,
                                    targetUser: item,
                                  )
                              : null,
                          onDelete: (item.isTechnician || item.isClient)
                              ? () => confirmAndDeleteUser(
                                    context: context,
                                    ref: ref,
                                    targetUser: item,
                                  )
                              : null,
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
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.chip.copyWith(
            color: selected ? AppColors.surface : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _TeamUserCard extends StatelessWidget {
  const _TeamUserCard({
    required this.user,
    this.isCurrentUser = false,
    this.onManageManagers,
    this.onResetPassword,
    this.onToggleStatus,
    this.onDelete,
  });

  final CompanyUser user;
  final bool isCurrentUser;
  final VoidCallback? onManageManagers;
  final VoidCallback? onResetPassword;
  final VoidCallback? onToggleStatus;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrentUser ? AppColors.primary : AppColors.border,
          width: isCurrentUser ? 1.5 : 1.0,
        ),
      ),
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user.name,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.body.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (isCurrentUser) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'You',
                              style: AppTypography.caption.copyWith(
                                fontSize: 11,
                                color: AppColors.surface,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user.email,
                      style: AppTypography.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(isActive: user.isActive),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              RoleChip(role: user.role),
              if (user.isDefaultManager)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    'Default',
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (user.mustChangePassword)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warningBackground,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.warningBorder),
                  ),
                  child: Text(
                    'Temp Password',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          if (user.isTechnician) ...[
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _CardActionButton(
                    icon: Icons.supervisor_account_outlined,
                    label: 'Managers',
                    onTap: onManageManagers,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CardActionButton(
                    icon: Icons.lock_reset,
                    label: 'Reset Password',
                    onTap: onResetPassword,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CardActionButton(
                    icon: user.isActive
                        ? Icons.person_off_outlined
                        : Icons.check_circle_outline,
                    label: user.isActive ? 'Deactivate' : 'Activate',
                    isDanger: user.isActive,
                    onTap: onToggleStatus,
                  ),
                ),
                if (onDelete != null) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Delete User',
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: AppColors.error,
                    ),
                    onPressed: onDelete,
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CardActionButton extends StatelessWidget {
  const _CardActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDanger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isDanger;

  @override
  Widget build(BuildContext context) {
    final fgColor = isDanger ? AppColors.error : AppColors.primary;
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: fgColor,
        backgroundColor: AppColors.background,
        side: BorderSide(
          color: isDanger ? AppColors.errorBorder : AppColors.border,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      icon: Icon(icon, size: 15),
      label: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.caption.copyWith(
          fontSize: 11,
          color: fgColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
