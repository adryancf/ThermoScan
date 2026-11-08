import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:thermoscan/core/network/api_exception.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/core/widgets/app_buttons.dart';
import 'package:thermoscan/core/widgets/app_text_field.dart';
import 'package:thermoscan/core/widgets/temporary_password_modal.dart';
import 'package:thermoscan/core/widgets/top_app_bar.dart';
import 'package:thermoscan/features/auth/presentation/auth_controller.dart';
import 'package:thermoscan/features/users/data/user_repository.dart';
import 'package:thermoscan/features/users/presentation/users_controller.dart';

/// SCR-07 & SCR-25: Create User (Manager or Technician)
class CreateUserScreen extends ConsumerStatefulWidget {
  const CreateUserScreen({super.key});

  @override
  ConsumerState<CreateUserScreen> createState() => _CreateUserScreenState();
}

class _CreateUserScreenState extends ConsumerState<CreateUserScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();

  String _selectedRole = 'technician'; // 'technician' | 'manager'
  final Set<String> _selectedManagerIds = {};
  bool _preselectedCurrentUser = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    setState(() {
      _errorMessage = null;
    });

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    if (_selectedRole == 'technician' && _selectedManagerIds.isEmpty) {
      setState(() {
        _errorMessage =
            'Select at least 1 responsible Manager for this Technician.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final result = await ref.read(userRepositoryProvider).createUser(
            name: _nameController.text,
            email: _emailController.text,
            role: _selectedRole,
            managerIds: _selectedRole == 'technician'
                ? _selectedManagerIds.toList()
                : const [],
          );

      ref.invalidate(companyUsersProvider);

      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
      });

      await showTemporaryPasswordModal(
        context: context,
        title: 'Temporary Password',
        userName: result.user.name,
        userEmail: result.user.email,
        temporaryPassword: result.temporaryPassword,
      );

      if (!mounted) return;
      context.pop();
    } on ApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _errorMessage = err.message;
        _isSubmitting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to create user. Please try again.';
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authControllerProvider).user;
    final usersAsync = ref.watch(companyUsersProvider);
    final activeManagers = (usersAsync.valueOrNull ?? const [])
        .where((u) => u.isManager && u.isActive)
        .toList();

    if (!_preselectedCurrentUser && currentUser != null) {
      _selectedManagerIds.add(currentUser.id);
      _preselectedCurrentUser = true;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const ThermoScanAppBar(
        title: 'Create User',
        showBack: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add Team Member',
                  style: AppTypography.h2,
                ),
                const SizedBox(height: 4),
                Text(
                  'Provision a Field Technician or an additional Company Manager.',
                  style: AppTypography.bodySmall,
                ),
                const SizedBox(height: 20),

                if (_errorMessage != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.errorBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.errorBorder),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: AppColors.error,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Role Segmented Selector
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _RoleSegmentOption(
                          label: 'Technician',
                          icon: Icons.engineering_outlined,
                          selected: _selectedRole == 'technician',
                          onTap: () =>
                              setState(() => _selectedRole = 'technician'),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _RoleSegmentOption(
                          label: 'Manager',
                          icon: Icons.supervisor_account_outlined,
                          selected: _selectedRole == 'manager',
                          onTap: () =>
                              setState(() => _selectedRole = 'manager'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // User Details Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Account Information', style: AppTypography.h3),
                      const SizedBox(height: 16),
                      AppTextField(
                        label: 'Full Name',
                        controller: _nameController,
                        hintText: 'e.g. Carlos Silva',
                        textInputAction: TextInputAction.next,
                        prefixIcon: Icons.person_outline,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Name is required.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        label: 'Email Address',
                        controller: _emailController,
                        hintText: 'user@company.com',
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.done,
                        prefixIcon: Icons.mail_outline,
                        validator: (value) {
                          final trimmed = value?.trim() ?? '';
                          if (trimmed.isEmpty || !trimmed.contains('@')) {
                            return 'Enter a valid email address.';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),

                // Responsible Managers Selection (Only when Technician is selected)
                if (_selectedRole == 'technician') ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Responsible Managers', style: AppTypography.h3),
                        const SizedBox(height: 4),
                        Text(
                          'Select at least 1 active Manager responsible for this Technician.',
                          style: AppTypography.bodySmall,
                        ),
                        const SizedBox(height: 14),
                        if (usersAsync.isLoading)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(
                                color: AppColors.primary,
                              ),
                            ),
                          )
                        else if (activeManagers.isEmpty)
                          Text(
                            'No active Managers available.',
                            style: AppTypography.bodySmall,
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: activeManagers.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final mgr = activeManagers[index];
                              final isChecked =
                                  _selectedManagerIds.contains(mgr.id);

                              return InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () {
                                  setState(() {
                                    if (isChecked) {
                                      _selectedManagerIds.remove(mgr.id);
                                    } else {
                                      _selectedManagerIds.add(mgr.id);
                                    }
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isChecked
                                        ? AppColors.primarySoft
                                            .withValues(alpha: 0.35)
                                        : AppColors.background,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isChecked
                                          ? AppColors.primary
                                          : AppColors.border,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isChecked
                                            ? Icons.check_box
                                            : Icons.check_box_outline_blank,
                                        color: isChecked
                                            ? AppColors.primary
                                            : AppColors.textSecondary,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              mgr.name +
                                                  (mgr.id == currentUser?.id
                                                      ? ' (You)'
                                                      : ''),
                                              style: AppTypography.bodySmall
                                                  .copyWith(
                                                color: AppColors.textPrimary,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            Text(
                                              mgr.email,
                                              style: AppTypography.caption,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: SecondaryButton(
                        label: 'Cancel',
                        onPressed:
                            _isSubmitting ? null : () => context.pop(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PrimaryButton(
                        label: _selectedRole == 'technician'
                            ? 'Create Technician'
                            : 'Create Manager',
                        isLoading: _isSubmitting,
                        onPressed: _handleSubmit,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleSegmentOption extends StatelessWidget {
  const _RoleSegmentOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? AppColors.surface : AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                color: selected ? AppColors.surface : AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
