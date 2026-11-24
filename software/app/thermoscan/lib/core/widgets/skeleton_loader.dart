import 'package:flutter/material.dart';
import 'package:thermoscan/core/theme/app_colors.dart';

/// Lightweight pulsing skeleton placeholder to replace bare spinners in lists.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  final double width;
  final double height;
  final double borderRadius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Color?> _colorAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _colorAnimation = ColorTween(
      begin: const Color(0xFFE6EDF4),
      end: const Color(0xFFF3F7FA),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _colorAnimation,
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: _colorAnimation.value,
            borderRadius: BorderRadius.circular(widget.borderRadius),
          ),
        );
      },
    );
  }
}

/// Skeleton list matching the Module card layout on ModulesHomeScreen.
class ModuleCardSkeletonList extends StatelessWidget {
  const ModuleCardSkeletonList({super.key, this.itemCount = 3});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(itemCount, (index) {
        return Padding(
          padding: EdgeInsets.only(bottom: index == itemCount - 1 ? 0 : 12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    SkeletonBox(width: 150, height: 18, borderRadius: 6),
                    SkeletonBox(width: 76, height: 22, borderRadius: 8),
                  ],
                ),
                SizedBox(height: 8),
                SkeletonBox(width: 110, height: 12, borderRadius: 4),
                SizedBox(height: 14),
                Divider(height: 1),
                SizedBox(height: 12),
                Row(
                  children: [
                    SkeletonBox(width: 72, height: 22, borderRadius: 10),
                    SizedBox(width: 8),
                    SkeletonBox(width: 96, height: 22, borderRadius: 10),
                    SizedBox(width: 8),
                    SkeletonBox(width: 68, height: 22, borderRadius: 10),
                  ],
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

/// Skeleton list matching the Alert card layout on AlertsFeedScreen.
class AlertCardSkeletonList extends StatelessWidget {
  const AlertCardSkeletonList({super.key, this.itemCount = 3});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(itemCount, (index) {
        return Padding(
          padding: EdgeInsets.only(bottom: index == itemCount - 1 ? 0 : 14),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    SkeletonBox(width: 68, height: 20, borderRadius: 6),
                    SkeletonBox(width: 54, height: 12, borderRadius: 4),
                  ],
                ),
                SizedBox(height: 12),
                SkeletonBox(width: 210, height: 16, borderRadius: 6),
                SizedBox(height: 8),
                SkeletonBox(width: double.infinity, height: 48, borderRadius: 10),
                SizedBox(height: 12),
                SkeletonBox(width: double.infinity, height: 34, borderRadius: 8),
              ],
            ),
          ),
        );
      }),
    );
  }
}
