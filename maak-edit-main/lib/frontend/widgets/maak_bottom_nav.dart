import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class MaakNavItem {
  final IconData icon;
  final String label;
  const MaakNavItem({required this.icon, required this.label});
}

class MaakBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<MaakNavItem> items;
  const MaakBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });
  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: AppColors.divider)),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: List.generate(
            items.length,
            (i) => Expanded(
              child: Semantics(
                selected: currentIndex == i,
                button: true,
                label: items[i].label,
                child: InkWell(
                  onTap: () => onTap(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          items[i].icon,
                          size: 25,
                          color: currentIndex == i
                              ? AppColors.primaryNavy
                              : AppColors.textMuted,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          items[i].label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: currentIndex == i
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: currentIndex == i
                                ? AppColors.primaryNavy
                                : AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
