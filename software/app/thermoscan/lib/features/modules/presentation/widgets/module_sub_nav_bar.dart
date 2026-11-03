import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';

/// Module Sub-navigation bar conforming to prototype_1 and prototype_2 (SCR-10, SCR-11, SCR-12, SCR-13, SCR-14).
class ModuleSubNavBar extends StatelessWidget {
  const ModuleSubNavBar({
    super.key,
    required this.moduleId,
    required this.currentTab,
    this.canManageAccess = false,
    this.isPendingConfig = false,
  });

  final String moduleId;
  final String currentTab; // 'overview', 'measurements', 'cleanings', 'config', 'access'
  final bool canManageAccess;
  final bool isPendingConfig;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _buildTab(
              context: context,
              label: 'Overview',
              tabId: 'overview',
              route: '/modules/$moduleId',
            ),
            _buildTab(
              context: context,
              label: 'Measurements',
              tabId: 'measurements',
              route: '/modules/$moduleId/measurements',
            ),
            _buildTab(
              context: context,
              label: 'Cleanings',
              tabId: 'cleanings',
              route: '/modules/$moduleId/cleanings',
            ),
            if (!isPendingConfig) ...[
              _buildTab(
                context: context,
                label: 'Config',
                tabId: 'config',
                route: '/modules/$moduleId/configuration',
              ),
            ],
            if (canManageAccess) ...[
              _buildTab(
                context: context,
                label: 'Access',
                tabId: 'access',
                route: '/modules/$moduleId/access',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTab({
    required BuildContext context,
    required String label,
    required String tabId,
    required String route,
  }) {
    final isSelected = currentTab == tabId;

    return InkWell(
      onTap: () {
        if (!isSelected) {
          context.push(route);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? AppColors.primary : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: Text(
          label,
          style: AppTypography.caption.copyWith(
            color: isSelected ? AppColors.primary : AppColors.textSecondary,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
