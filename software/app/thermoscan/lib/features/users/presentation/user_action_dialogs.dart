import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thermoscan/core/network/api_exception.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/core/widgets/app_buttons.dart';
import 'package:thermoscan/core/widgets/temporary_password_modal.dart';
import 'package:thermoscan/features/users/data/user_repository.dart';
import 'package:thermoscan/features/users/domain/user_models.dart';
import 'package:thermoscan/features/users/presentation/users_controller.dart';

/// SCR-27: Reset Technician/Client Password Confirmation + One-time Modal
Future<void> confirmAndResetUserPassword({
  required BuildContext context,
  required WidgetRef ref,
  required CompanyUser targetUser,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.warningBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.warningBorder),
                  ),
                  child: const Icon(
                    Icons.lock_reset,
                    color: AppColors.warning,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Reset Password?',
                    style: AppTypography.h3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Generate a new temporary password for ${targetUser.name} (${targetUser.email})?',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    label: 'Cancel',
                    onPressed: () => Navigator.of(ctx).pop(false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PrimaryButton(
                    label: 'Reset',
                    onPressed: () => Navigator.of(ctx).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  if (confirmed != true || !context.mounted) return;

  try {
    final result = await ref
        .read(userRepositoryProvider)
        .resetUserPassword(userId: targetUser.id);

    ref.invalidate(companyUsersProvider);

    if (!context.mounted) return;
    await showTemporaryPasswordModal(
      context: context,
      title: 'Temporary Password',
      userName: result.user.name,
      userEmail: result.user.email,
      temporaryPassword: result.temporaryPassword,
    );
  } on ApiException catch (err) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(err.message),
        backgroundColor: AppColors.error,
      ),
    );
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Failed to reset password.'),
        backgroundColor: AppColors.error,
      ),
    );
  }
}

/// SCR-32: User Activity Confirmation (Activate / Deactivate Technician or Client)
Future<void> confirmAndToggleUserStatus({
  required BuildContext context,
  required WidgetRef ref,
  required CompanyUser targetUser,
}) async {
  final nextActive = !targetUser.isActive;
  final actionLabel = nextActive ? 'Activate' : 'Deactivate';

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: nextActive
                        ? AppColors.successBackground
                        : AppColors.errorBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: nextActive
                          ? AppColors.successBorder
                          : AppColors.errorBorder,
                    ),
                  ),
                  child: Icon(
                    nextActive
                        ? Icons.check_circle_outline
                        : Icons.person_off_outlined,
                    color: nextActive ? AppColors.success : AppColors.error,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '$actionLabel Account?',
                    style: AppTypography.h3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              nextActive
                  ? 'Restore login access for ${targetUser.name} (${targetUser.email})?'
                  : 'Suspend login access and sign out ${targetUser.name} (${targetUser.email}) on all devices?',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    label: 'Cancel',
                    onPressed: () => Navigator.of(ctx).pop(false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: nextActive
                      ? PrimaryButton(
                          label: 'Activate',
                          onPressed: () => Navigator.of(ctx).pop(true),
                        )
                      : DangerButton(
                          label: 'Deactivate',
                          outlined: false,
                          onPressed: () => Navigator.of(ctx).pop(true),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  if (confirmed != true || !context.mounted) return;

  try {
    await ref.read(userRepositoryProvider).setUserStatus(
          userId: targetUser.id,
          isActive: nextActive,
        );
    ref.invalidate(companyUsersProvider);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          nextActive
              ? '${targetUser.name} activated.'
              : '${targetUser.name} deactivated.',
        ),
      ),
    );
  } on ApiException catch (err) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(err.message),
        backgroundColor: AppColors.error,
      ),
    );
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Failed to update user status.'),
        backgroundColor: AppColors.error,
      ),
    );
  }
}

/// Aditivo — Exclusão de contas (Technician e Client)
Future<void> confirmAndDeleteUser({
  required BuildContext context,
  required WidgetRef ref,
  required CompanyUser targetUser,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.errorBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.errorBorder),
                  ),
                  child: const Icon(
                    Icons.person_remove_outlined,
                    color: AppColors.error,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Delete Account?',
                    style: AppTypography.h3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Permanently delete ${targetUser.name} (${targetUser.email})?',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This action is permanent and will sign the user out on all devices. Users with installed panels or activity history cannot be deleted and must be deactivated instead.',
              style: AppTypography.caption,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    label: 'Cancel',
                    onPressed: () => Navigator.of(ctx).pop(false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DangerButton(
                    label: 'Delete',
                    outlined: false,
                    onPressed: () => Navigator.of(ctx).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  if (confirmed != true || !context.mounted) return;

  try {
    await ref.read(userRepositoryProvider).deleteUser(userId: targetUser.id);
    ref.invalidate(companyUsersProvider);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${targetUser.name} deleted successfully.'),
        backgroundColor: AppColors.success,
      ),
    );
  } on ApiException catch (err) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(err.message),
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 5),
      ),
    );
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Failed to delete user.'),
        backgroundColor: AppColors.error,
      ),
    );
  }
}

/// Dialog to view and update a Technician's responsible Managers (>= 1 required)
Future<void> showTechnicianManagersDialog({
  required BuildContext context,
  required CompanyUser technician,
  required List<CompanyUser> availableManagers,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _TechnicianManagersEditorDialog(
      technician: technician,
      availableManagers: availableManagers,
    ),
  );
}

class _TechnicianManagersEditorDialog extends ConsumerStatefulWidget {
  const _TechnicianManagersEditorDialog({
    required this.technician,
    required this.availableManagers,
  });

  final CompanyUser technician;
  final List<CompanyUser> availableManagers;

  @override
  ConsumerState<_TechnicianManagersEditorDialog> createState() =>
      _TechnicianManagersEditorDialogState();
}

class _TechnicianManagersEditorDialogState
    extends ConsumerState<_TechnicianManagersEditorDialog> {
  final Set<String> _selectedIds = {};
  bool _initialized = false;
  bool _isSaving = false;
  String? _errorMessage;

  Future<void> _handleSave() async {
    if (_selectedIds.isEmpty) {
      setState(() {
        _errorMessage = 'Select at least 1 responsible Manager.';
      });
      return;
    }

    setState(() {
      _errorMessage = null;
      _isSaving = true;
    });

    try {
      await ref.read(userRepositoryProvider).setTechnicianManagers(
            technicianId: widget.technician.id,
            managerIds: _selectedIds.toList(),
          );
      ref.invalidate(userDetailsProvider(widget.technician.id));
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Responsible Managers updated for ${widget.technician.name}.',
          ),
        ),
      );
    } on ApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _errorMessage = err.message;
        _isSaving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to update responsible Managers.';
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailsAsync = ref.watch(userDetailsProvider(widget.technician.id));
    final activeManagers =
        widget.availableManagers.where((m) => m.isActive).toList();

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: detailsAsync.when(
          loading: () => const SizedBox(
            height: 160,
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          ),
          error: (err, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                err.toString(),
                style: AppTypography.bodySmall.copyWith(color: AppColors.error),
              ),
              const SizedBox(height: 16),
              SecondaryButton(
                label: 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          data: (details) {
            if (!_initialized) {
              _selectedIds.addAll(details.managers.map((m) => m.id));
              _initialized = true;
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Responsible Managers', style: AppTypography.h3),
                const SizedBox(height: 4),
                Text(
                  '${widget.technician.name} • Select at least 1 Manager',
                  style: AppTypography.caption,
                ),
                const SizedBox(height: 14),
                if (_errorMessage != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AppColors.errorBackground,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.errorBorder),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: activeManagers.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final mgr = activeManagers[index];
                      final isChecked = _selectedIds.contains(mgr.id);

                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          setState(() {
                            if (isChecked) {
                              _selectedIds.remove(mgr.id);
                            } else {
                              _selectedIds.add(mgr.id);
                            }
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isChecked
                                ? AppColors.primarySoft.withValues(alpha: 0.35)
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
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      mgr.name,
                                      style: AppTypography.bodySmall.copyWith(
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
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: SecondaryButton(
                        label: 'Cancel',
                        onPressed: _isSaving
                            ? null
                            : () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PrimaryButton(
                        label: 'Save',
                        isLoading: _isSaving,
                        onPressed: _handleSave,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
