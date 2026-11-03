import 'package:flutter/material.dart';

import '../widgets/maak_bottom_nav.dart' show MaakNavItem;
import 'tokens.dart';

// Light navigation from the approved design, used by AppShell (Help Seeker
// and Volunteer) and AdminShell. Takes the same MaakNavItem items and
// callbacks as the older MaakBottomNav, which is no longer used.

class _NavIcon extends StatelessWidget {
  final MaakNavItem item;
  final bool selected;
  final double size;
  const _NavIcon({
    required this.item,
    required this.selected,
    required this.size,
  });
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: selected ? MaakColors.selected : Colors.transparent,
      shape: BoxShape.circle,
    ),
    child: Badge(
      isLabelVisible: item.unreadCount > 0,
      backgroundColor: MaakColors.coral,
      textColor: MaakColors.ink,
      label: Text(item.unreadCount > 99 ? '99+' : '${item.unreadCount}'),
      offset: const Offset(10, -10),
      child: Icon(item.icon, size: 23, color: MaakColors.icon),
    ),
  );
}

String _label(MaakNavItem item) => item.unreadCount > 0
    ? '${item.label}, ${item.unreadCount} unread'
    : item.label;

class MaakNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<MaakNavItem> items;
  const MaakNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: MaakColors.warmWhite,
      border: Border(top: BorderSide(color: MaakColors.border)),
      boxShadow: [
        BoxShadow(
          color: Color(0x0DAA6464),
          blurRadius: 12,
          offset: Offset(0, -2),
        ),
      ],
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: Semantics(
                  selected: currentIndex == i,
                  button: true,
                  label: _label(items[i]),
                  excludeSemantics: true,
                  child: InkResponse(
                    onTap: () => onTap(i),
                    containedInkWell: true,
                    highlightShape: BoxShape.rectangle,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 60),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _NavIcon(
                            item: items[i],
                            selected: currentIndex == i,
                            size: 40,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            items[i].label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MaakText.caption.copyWith(
                              color: currentIndex == i
                                  ? MaakColors.ink
                                  : MaakColors.muted,
                              fontWeight: currentIndex == i
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Tablet counterpart of [MaakNavBar], with the logo above the destinations.
class MaakNavRail extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<MaakNavItem> items;
  final Widget? leading;
  const MaakNavRail({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
    this.leading,
  });
  @override
  Widget build(BuildContext context) => Container(
    width: 96,
    decoration: const BoxDecoration(
      color: MaakColors.warmWhite,
      border: BorderDirectional(end: BorderSide(color: MaakColors.border)),
    ),
    child: SafeArea(
      right: false,
      child: Column(
        children: [
          const SizedBox(height: MaakSpace.xl),
          if (leading != null) ...[
            leading!,
            const SizedBox(height: MaakSpace.xxl),
          ],
          for (var i = 0; i < items.length; i++)
            Semantics(
              selected: currentIndex == i,
              button: true,
              label: _label(items[i]),
              excludeSemantics: true,
              child: InkResponse(
                onTap: () => onTap(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: MaakSpace.sm),
                  child: Column(
                    children: [
                      _NavIcon(
                        item: items[i],
                        selected: currentIndex == i,
                        size: 48,
                      ),
                      const SizedBox(height: MaakSpace.xs),
                      Text(
                        items[i].label,
                        style: MaakText.caption.copyWith(
                          color: currentIndex == i
                              ? MaakColors.ink
                              : MaakColors.muted,
                          fontWeight: currentIndex == i
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
