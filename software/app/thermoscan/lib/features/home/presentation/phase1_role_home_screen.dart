import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/core/widgets/app_buttons.dart';
import 'package:thermoscan/core/widgets/status_chips.dart';
import 'package:thermoscan/core/widgets/thermoscan_logo.dart';
import 'package:thermoscan/core/widgets/top_app_bar.dart';
import 'package:thermoscan/features/auth/presentation/auth_controller.dart';

/// SCR-33: Phase 1 Home for Technician and Client
class Phase1RoleHomeScreen extends ConsumerWidget {
  const Phase1RoleHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    if (user == null) {
      return const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: ThermoScanAppBar(
        title: 'ThermoScan',
        role: user.role,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome, ${user.name}',
              style: AppTypography.h2,
            ),
            const SizedBox(height: 4),
            Text(
              'Signed in as ${user.roleDisplayName}',
              style: AppTypography.bodySmall,
            ),
            const SizedBox(height: 20),

            // User Account Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      user.initials,
                      style: AppTypography.h3.copyWith(
                        color: AppColors.surface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.name, style: AppTypography.h3),
                        const SizedBox(height: 2),
                        Text(user.email, style: AppTypography.bodySmall),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            RoleChip(role: user.role),
                            StatusChip(isActive: user.isActive),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Phase 1 Notice Card (per design.md SCR-33)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const ThermoScanLogoIcon(size: 28),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Solar Monitoring & Diagnostics',
                          style: AppTypography.h3,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Panel monitoring and cleaning controls will be available in an upcoming update.',
                    style: AppTypography.body,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Your account is active and verified. You can manage your personal profile and password settings below.',
                    style: AppTypography.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  const RadiometricSpectrumBar(width: double.infinity),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SecondaryButton(
              label: 'Profile & Password',
              icon: Icons.manage_accounts_outlined,
              onPressed: () => context.push('/profile'),
            ),
            const SizedBox(height: 12),
            DangerButton(
              label: 'Log Out',
              icon: Icons.logout,
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).logout(),
            ),
          ],
        ),
      ),
    );
  }
}
