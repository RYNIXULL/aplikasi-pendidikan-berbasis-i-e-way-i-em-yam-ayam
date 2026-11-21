import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class NavDestinationItem {
  const NavDestinationItem({
    required this.label,
    required this.icon,
    required this.route,
  });

  final String label;
  final IconData icon;
  final String route;
}

/// Restrained Frosted Glass floating bottom navigation bar.
/// Falls back cleanly to a solid translucent surface when reduced motion is enabled
/// to keep 60fps performance on mid-range Android hardware.
class AppBottomNavigation extends StatelessWidget {
  const AppBottomNavigation({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onSelect,
  });

  final List<NavDestinationItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final disableBlur = MediaQuery.of(context).disableAnimations;
    final scheme = Theme.of(context).colorScheme;

    final containerColor = isDark
        ? AppColors.cardDark.withValues(alpha: disableBlur ? 0.96 : 0.72)
        : Colors.white.withValues(alpha: disableBlur ? 0.96 : 0.72);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.white.withValues(alpha: 0.65);

    final navRow = Container(
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (idx) {
          final item = items[idx];
          final active = idx == currentIndex;
          final activeColor = scheme.primary;
          final inactiveColor =
              isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

          return Expanded(
            child: InkWell(
              onTap: () => onSelect(idx),
              borderRadius: BorderRadius.circular(14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: active ? activeColor.withValues(alpha: 0.14) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      item.icon,
                      size: 20,
                      color: active ? activeColor : inactiveColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active ? activeColor : inactiveColor,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: disableBlur
              ? navRow
              : BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: navRow,
                ),
        ),
      ),
    );
  }
}
