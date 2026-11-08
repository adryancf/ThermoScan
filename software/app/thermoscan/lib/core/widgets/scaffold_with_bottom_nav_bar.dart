import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/features/alerts/presentation/alerts_controller.dart';
import 'package:thermoscan/features/auth/domain/auth_user.dart';
import 'package:thermoscan/features/auth/presentation/auth_controller.dart';

/// Bottom Navigation Bar Shell conforming to prototype_1 and prototype_2.
/// Strictly 3 tabs: Modules (SCR-09), Alerts (SCR-21), Settings / Administration (SCR-23/24).
/// Suppressed for System Admin role and Linear Onboarding / Wizards / Modals.
class ScaffoldWithBottomNavBar extends ConsumerWidget {
  const ScaffoldWithBottomNavBar({
    super.key,
    required this.child,
    required this.currentLocation,
  });

  final Widget child;
  final String currentLocation;

  int _calculateSelectedIndex(String location) {
    if (location == '/home' || location.startsWith('/modules')) {
      return 0; // Modules
    }
    if (location.startsWith('/alerts')) {
      return 1; // Alerts
    }
    if (location.startsWith('/manager') ||
        location.startsWith('/profile') ||
        location.startsWith('/settings')) {
      return 2; // Settings / Administration
    }
    return 0;
  }

  void _onTabSelected(int index, BuildContext context, AuthUser? user) {
    switch (index) {
      case 0:
        context.go('/modules');
        break;
      case 1:
        context.go('/alerts');
        break;
      case 2:
        if (user?.isManager ?? false) {
          // If manager is currently on profile, tapping settings toggles to admin,
          // otherwise opens manager administration home
          if (currentLocation == '/manager') {
            context.go('/profile');
          } else {
            context.go('/manager');
          }
        } else {
          context.go('/profile');
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final selectedIndex = _calculateSelectedIndex(currentLocation);
    final alertsSummary = ref.watch(alertsSummaryProvider).valueOrNull;
    final hasActiveAlerts = (alertsSummary?.total ?? 0) > 0;

    // Suppress Bottom Navigation Bar for System Admin (companies only)
    final isSystemAdmin = user?.isSystemAdmin ?? false;
    if (isSystemAdmin) {
      return child;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: child,
      bottomNavigationBar: Container(
        height: 64,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(
            top: BorderSide(color: AppColors.border, width: 1),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              // Tab 0: Modules
              _buildNavItem(
                index: 0,
                selectedIndex: selectedIndex,
                icon: Icons.solar_power_outlined,
                activeIcon: Icons.solar_power,
                label: 'Modules',
                onTap: () => _onTabSelected(0, context, user),
              ),

              // Tab 1: Alerts
              _buildNavItem(
                index: 1,
                selectedIndex: selectedIndex,
                icon: Icons.warning_amber_rounded,
                activeIcon: Icons.warning_rounded,
                label: 'Alerts',
                hasNotificationBadge: hasActiveAlerts,
                onTap: () => _onTabSelected(1, context, user),
              ),

              // Tab 2: Settings
              _buildNavItem(
                index: 2,
                selectedIndex: selectedIndex,
                icon: Icons.settings_outlined,
                activeIcon: Icons.settings,
                label: 'Settings',
                onTap: () => _onTabSelected(2, context, user),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required int selectedIndex,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required VoidCallback onTap,
    bool hasNotificationBadge = false,
  }) {
    final isSelected = index == selectedIndex;
    final color = isSelected ? AppColors.primary : AppColors.textSecondary;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          splashFactory: InkRipple.splashFactory,
          highlightColor: AppColors.primarySoft.withValues(alpha: 0.3),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      isSelected ? activeIcon : icon,
                      size: 24,
                      color: color,
                    ),
                    if (hasNotificationBadge)
                      Positioned(
                        top: -1,
                        right: -3,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.error,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: AppTypography.caption.copyWith(
                    color: color,
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
