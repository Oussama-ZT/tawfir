import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import '../l10n/l10n.dart';

class EcoNavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// Lets the guided tour point at this tab.
  final Key? anchor;
  const EcoNavItem(this.icon, this.selectedIcon, this.label, {this.anchor});
}

/// Floating glass bar: two tabs on each side of a glowing yellow add button.
/// Use with `Scaffold(extendBody: true)` so content scrolls under the glass.
class EcoNavBar extends StatelessWidget {
  const EcoNavBar({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
    required this.onAdd,
    this.addAnchor,
  }) : assert(items.length == 4);

  /// Lets the guided tour point at the add button.
  final Key? addAnchor;

  final List<EcoNavItem> items;
  final int selected;
  final ValueChanged<int> onSelected;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    Widget tab(int i) {
      final item = items[i];
      final isSelected = i == selected;
      final color = isSelected ? eco.blueInk : eco.muted;
      return Expanded(
        child: Semantics(
          key: item.anchor,
          selected: isSelected,
          button: true,
          label: item.label,
          excludeSemantics: true,
          child: InkResponse(
            onTap: () => onSelected(i),
            radius: 34,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(isSelected ? item.selectedIcon : item.icon, color: color, size: 24),
                const SizedBox(height: 3),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      item.label,
                      maxLines: 1,
                      style: context.type.labelSmall?.copyWith(
                        color: isSelected ? eco.ink : eco.muted,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                // Neon dot under the current tab.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: isSelected ? 14 : 0,
                  height: 3,
                  decoration: BoxDecoration(
                    color: eco.blueInk,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: isSelected ? eco.neon(eco.blueInk, strength: 0.8) : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final radius = BorderRadius.circular(30);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 14, 4),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [BoxShadow(color: eco.glassShadow, blurRadius: 30, offset: const Offset(0, 12))],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Container(
                height: 72,
                decoration: BoxDecoration(
                  color: eco.navFill,
                  borderRadius: radius,
                  border: Border.all(color: eco.glassBorder),
                ),
                child: Row(
                  children: [
                    tab(0),
                    tab(1),
                    SizedBox(
                      width: 78,
                      child: Center(child: _AddOrb(key: addAnchor, onTap: onAdd)),
                    ),
                    tab(2),
                    tab(3),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddOrb extends StatelessWidget {
  const _AddOrb({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    return Semantics(
      button: true,
      label: tr('Ajouter une dépense'),
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: eco.neon(eco.yellow)),
        child: Material(
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: Ink(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color.lerp(eco.yellow, Colors.white, 0.35)!, eco.yellow],
              ),
            ),
            child: InkWell(
              onTap: onTap,
              child: SizedBox.square(
                dimension: 54,
                child: Icon(Icons.add_rounded, size: 30, color: eco.onYellow),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
