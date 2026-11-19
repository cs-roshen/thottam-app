import 'package:material_ui/material_ui.dart';

import '../theme/tokens.dart';

@immutable
class NavTab {
  const NavTab(this.icon, this.label);

  final IconData icon;
  final String label;
}

/// Bottom bar: tabs either side of a raised centre add button. Works with
/// three tabs (no Money) or four; with no [onAdd] (a role that writes nothing)
/// there is no add button.
class ThottamBottomNav extends StatelessWidget {
  const ThottamBottomNav({
    super.key,
    required this.tabs,
    required this.current,
    required this.onTab,
    required this.onAdd,
    required this.addLabel,
  });

  final List<NavTab> tabs;
  final int current;
  final ValueChanged<int> onTab;
  final VoidCallback? onAdd;
  final String addLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final half = (tabs.length + 1) ~/ 2;
    Widget tab(int i) => Expanded(
      child: _Tab(tab: tabs[i], active: i == current, onTap: () => onTab(i)),
    );
    // The add button rises above the bar; the box is tall enough to keep
    // its whole area tappable.
    return SizedBox(
      height:
          t.navHeight + t.addButtonRaise + MediaQuery.paddingOf(context).bottom,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Material(
              color: t.surface,
              child: SafeArea(
                top: false,
                child: SizedBox(
                  height: t.navHeight,
                  child: Row(
                    children: [
                      for (var i = 0; i < half; i++) tab(i),
                      if (onAdd != null)
                        SizedBox(width: t.addButtonSize + t.cardGap),
                      for (var i = half; i < tabs.length; i++) tab(i),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (onAdd case final add?)
            Positioned(
              top: 0,
              child: _AddButton(label: addLabel, onTap: add),
            ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.tab, required this.active, required this.onTap});

  final NavTab tab;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final style = Theme.of(context).textTheme.labelSmall!.copyWith(
      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
      color: active ? t.primaryDark : t.muted,
    );
    return Semantics(
      selected: active,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: t.navLabelMaxScale,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: active ? t.primaryPill : Colors.transparent,
                  borderRadius: BorderRadius.circular(t.chipRadius),
                ),
                child: Icon(
                  tab.icon,
                  size: t.iconSize,
                  color: active ? t.primaryDark : t.muted,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                tab.label,
                style: style.copyWith(height: 1.2),
                textAlign: TextAlign.center,
                // Two lines so long Malayalam labels wrap instead of clipping.
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      label: label,
      button: true,
      excludeSemantics: true,
      child: Material(
        color: t.primary,
        shape: const CircleBorder(),
        elevation: 3,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(
            dimension: t.addButtonSize,
            child: Icon(Icons.add, color: t.onPrimary, size: t.iconSize + 8),
          ),
        ),
      ),
    );
  }
}
