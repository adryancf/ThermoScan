import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/core/widgets/app_buttons.dart';
import 'package:thermoscan/core/widgets/status_chips.dart';
import 'package:thermoscan/core/widgets/top_app_bar.dart';
import 'package:thermoscan/features/users/domain/user_models.dart';
import 'package:thermoscan/features/users/presentation/user_action_dialogs.dart';
import 'package:thermoscan/features/users/presentation/users_controller.dart';

enum _ClientFilter {
  all,
  active,
  inactive,
}

/// SCR-31: Clients List
class ClientsListScreen extends ConsumerStatefulWidget {
  const ClientsListScreen({super.key});

  @override
  ConsumerState<ClientsListScreen> createState() => _ClientsListScreenState();
}

class _ClientsListScreenState extends ConsumerState<ClientsListScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  _ClientFilter _filter = _ClientFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<CompanyUser> _applyFilter(List<CompanyUser> allUsers) {
    final clients = allUsers.where((u) => u.isClient).toList();
    final query = _searchQuery.trim().toLowerCase();

    return clients.where((c) {
      if (_filter == _ClientFilter.active && !c.isActive) return false;
      if (_filter == _ClientFilter.inactive && c.isActive) return false;

      if (query.isEmpty) return true;
      return c.name.toLowerCase().contains(query) ||
          c.email.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(companyUsersProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const ThermoScanAppBar(
        title: 'Clients',
        showBack: true,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/manager/clients/new'),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.surface,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        tooltip: 'Create Client',
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
                          hintText: 'Search clients by name or email...',
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
                            _FilterChip(
                              label: 'All',
                              selected: _filter == _ClientFilter.all,
                              onTap: () =>
                                  setState(() => _filter = _ClientFilter.all),
                            ),
                            const SizedBox(width: 8),
                            _FilterChip(
                              label: 'Active',
                              selected: _filter == _ClientFilter.active,
                              onTap: () => setState(
                                () => _filter = _ClientFilter.active,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _FilterChip(
                              label: 'Inactive',
                              selected: _filter == _ClientFilter.inactive,
                              onTap: () => setState(
                                () => _filter = _ClientFilter.inactive,
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
                  final totalClients =
                      allUsers.where((u) => u.isClient).toList();
                  final filtered = _applyFilter(allUsers);

                  if (totalClients.isEmpty) {
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 88),
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
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: AppColors.background,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  child: const Icon(
                                    Icons.person_add_outlined,
                                    color: AppColors.primary,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  'No Clients registered yet',
                                  style: AppTypography.h3,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Create a Client account to grant portal access and issue temporary credentials.',
                                  textAlign: TextAlign.center,
                                  style: AppTypography.bodySmall,
                                ),
                                const SizedBox(height: 18),
                                PrimaryButton(
                                  label: 'Create First Client',
                                  icon: Icons.add,
                                  onPressed: () =>
                                      context.push('/manager/clients/new'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  if (filtered.isEmpty) {
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            'No matching clients found.',
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
                        final client = filtered[index];
                        return _ClientCard(
                          client: client,
                          onResetPassword: () => confirmAndResetUserPassword(
                            context: context,
                            ref: ref,
                            targetUser: client,
                          ),
                          onToggleStatus: () => confirmAndToggleUserStatus(
                            context: context,
                            ref: ref,
                            targetUser: client,
                          ),
                          onDelete: () => confirmAndDeleteUser(
                            context: context,
                            ref: ref,
                            targetUser: client,
                          ),
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

class _FilterChip extends StatelessWidget {
  const _FilterChip({
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

class _ClientCard extends StatelessWidget {
  const _ClientCard({
    required this.client,
    required this.onResetPassword,
    required this.onToggleStatus,
    required this.onDelete,
  });

  final CompanyUser client;
  final VoidCallback onResetPassword;
  final VoidCallback onToggleStatus;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final statusActionColor =
        client.isActive ? AppColors.error : AppColors.primary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
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
                    Text(
                      client.name,
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      client.email,
                      style: AppTypography.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(isActive: client.isActive),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              RoleChip(role: client.role),
              if (client.mustChangePassword)
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
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onResetPassword,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    backgroundColor: AppColors.background,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.lock_reset, size: 16),
                  label: Text(
                    'Reset Password',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onToggleStatus,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: statusActionColor,
                    backgroundColor: AppColors.background,
                    side: BorderSide(
                      color: client.isActive
                          ? AppColors.errorBorder
                          : AppColors.border,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: Icon(
                    client.isActive
                        ? Icons.person_off_outlined
                        : Icons.check_circle_outline,
                    size: 16,
                  ),
                  label: Text(
                    client.isActive ? 'Deactivate' : 'Activate',
                    style: AppTypography.caption.copyWith(
                      color: statusActionColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Delete Client',
                icon: const Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: AppColors.error,
                ),
                onPressed: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
