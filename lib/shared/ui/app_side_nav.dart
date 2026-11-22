import 'package:flutter/material.dart';
import 'package:tawrid_app/app/theme/app_spacing.dart';
import 'package:tawrid_app/app/theme/app_tokens_ext.dart';
import 'package:tawrid_app/app/theme/tokens.dart';

import 'app_icon.dart';

class AppSideNavItem {
  const AppSideNavItem({
    required this.icon,
    required this.label,
    this.showBadge = false,
  });

  final AppIcons icon;
  final String label;
  final bool showBadge;
}

class AppSideNav extends StatelessWidget {
  const AppSideNav({
    required this.items,
    required this.currentIndex,
    required this.onTap,
    super.key,
  });

  final List<AppSideNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;

    return Container(
      width: AppBreakpoints.desktopSideNavWidth,
      height: double.infinity,
      color: cs.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SideNavHeader(cs: cs),
          const SizedBox(height: AppSpacing.sm),
          for (var i = 0; i < items.length; i++)
            _SideNavItem(
              item: items[i],
              active: i == currentIndex,
              onTap: () => onTap(i),
            ),
        ],
      ),
    );
  }
}

class _SideNavHeader extends StatelessWidget {
  const _SideNavHeader({required this.cs});

  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.x2l + 4,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Image.asset(
              'assets/images/logo.jpg',
              width: 36,
              height: 36,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'توريد',
            style: TextStyle(
              color: cs.onPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              fontFamily: 'Tajawal',
            ),
          ),
        ],
      ),
    );
  }
}

class _SideNavItem extends StatefulWidget {
  const _SideNavItem({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final AppSideNavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_SideNavItem> createState() => _SideNavItemState();
}

class _SideNavItemState extends State<_SideNavItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _t;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      value: widget.active ? 1.0 : 0.0,
    );
    _t = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }

  @override
  void didUpdateWidget(_SideNavItem old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) {
      widget.active ? _ctrl.forward() : _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final iconColor = Color.lerp(
              cs.onPrimary.withValues(alpha: 0.6),
              cs.onPrimary,
              _t.value,
            )!;
            final bgAlpha = widget.active
                ? 0.15
                : _hovered
                ? 0.08
                : 0.0;

            return Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 1.5,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: cs.onPrimary.withValues(alpha: bgAlpha),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 11,
                ),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AppIcon(widget.item.icon, size: 20, color: iconColor),
                        if (widget.item.showBadge)
                          Positioned(
                            top: -3,
                            right: -3,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE57373),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: AppSpacing.sm + 2),
                    Expanded(
                      child: Text(
                        widget.item.label,
                        style: TextStyle(
                          color: iconColor,
                          fontSize: 14,
                          fontWeight: widget.active
                              ? FontWeight.w600
                              : FontWeight.w400,
                          fontFamily: 'Tajawal',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
