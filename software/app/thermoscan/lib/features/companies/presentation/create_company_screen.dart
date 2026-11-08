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
import 'package:thermoscan/features/companies/data/company_repository.dart';
import 'package:thermoscan/features/companies/presentation/companies_controller.dart';

/// SCR-05: Create Company (System Admin)
class CreateCompanyScreen extends ConsumerStatefulWidget {
  const CreateCompanyScreen({super.key});

  @override
  ConsumerState<CreateCompanyScreen> createState() =>
      _CreateCompanyScreenState();
}

class _CreateCompanyScreenState extends ConsumerState<CreateCompanyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _companyNameController = TextEditingController();
  final _companyAddressController = TextEditingController();
  final _managerNameController = TextEditingController();
  final _managerEmailController = TextEditingController();

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _companyNameController.dispose();
    _companyAddressController.dispose();
    _managerNameController.dispose();
    _managerEmailController.dispose();
    super.dispose();
  }

  Future<void> _handleCreateCompany() async {
    setState(() {
      _errorMessage = null;
    });

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final result =
          await ref.read(companyRepositoryProvider).createCompany(
                name: _companyNameController.text,
                address: _companyAddressController.text,
                managerName: _managerNameController.text,
                managerEmail: _managerEmailController.text,
              );

      // Refresh companies list in background
      ref.invalidate(companiesListProvider);

      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
      });

      // Show one-time temporary password modal (design.md Section 8 & SCR-05)
      await showTemporaryPasswordModal(
        context: context,
        title: 'Temporary Password',
        userName: result.defaultManager.name,
        userEmail: result.defaultManager.email,
        temporaryPassword: result.temporaryPassword,
      );

      if (!mounted) return;
      context.pushReplacement('/admin/companies/${result.company.id}');
    } on ApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _errorMessage = err.message;
        _isSubmitting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to create company. Please try again.';
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: ThermoScanAppBar(
        title: 'Add Company',
        role: user?.role ?? 'system_admin',
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
                  'Add Company',
                  style: AppTypography.h2,
                ),
                const SizedBox(height: 4),
                Text(
                  'Register a new organization and generate temporary credentials for its first Manager.',
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
                // Section 1: Company Details
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
                      Text('Company Information', style: AppTypography.h3),
                      const SizedBox(height: 16),
                      AppTextField(
                        label: 'Company Name',
                        controller: _companyNameController,
                        hintText: 'e.g. SolTech Energy Ltd',
                        textInputAction: TextInputAction.next,
                        prefixIcon: Icons.domain_outlined,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Company name is required.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        label: 'Company Address (Optional)',
                        controller: _companyAddressController,
                        hintText: 'e.g. 1000 Solar Way, Suite 400',
                        textInputAction: TextInputAction.next,
                        prefixIcon: Icons.location_on_outlined,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Section 2: Initial Manager
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
                      Text('Initial Primary Manager', style: AppTypography.h3),
                      const SizedBox(height: 4),
                      Text(
                        'This Manager will administer users and clients for the company.',
                        style: AppTypography.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        label: 'First Manager Name',
                        controller: _managerNameController,
                        hintText: 'Full name',
                        textInputAction: TextInputAction.next,
                        prefixIcon: Icons.person_outline,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'First Manager name is required.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        label: 'First Manager Email',
                        controller: _managerEmailController,
                        hintText: 'manager@company.com',
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.done,
                        prefixIcon: Icons.mail_outline,
                        onFieldSubmitted: (_) => _handleCreateCompany(),
                        validator: (value) {
                          final trimmed = value?.trim() ?? '';
                          if (trimmed.isEmpty || !trimmed.contains('@')) {
                            return 'Enter a valid email address.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.vpn_key_outlined,
                              size: 18,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'A one-time temporary password will be generated upon creation and must be changed on first sign-in.',
                                style: AppTypography.caption,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
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
                        label: 'Add Company',
                        isLoading: _isSubmitting,
                        onPressed: _handleCreateCompany,
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
