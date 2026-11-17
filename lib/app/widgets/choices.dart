import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../theme/tokens.dart';

/// Pill chip: selected is primary with white text, unselected is white with
/// a grey border.
class ChoiceChipX extends StatelessWidget {
  const ChoiceChipX({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool>? onSelected;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      showCheckmark: false,
      selectedColor: t.primary,
      backgroundColor: t.surface,
      labelStyle: Theme.of(context).textTheme.bodyLarge!
          .copyWith(color: selected ? t.onPrimary : t.ink),
      side: BorderSide(color: selected ? t.primary : t.chipBorder),
      shape: const StadiumBorder(),
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }
}

/// Grey track with the chosen segment raised in white.
class SegmentedControl extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: t.segmentTrack,
        borderRadius: BorderRadius.circular(t.buttonRadius),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: SegmentedControlOption(
                label: labels[i],
                selected: i == selected,
                onTap: onChanged == null ? null : () => onChanged!(i),
              ),
            ),
        ],
      ),
    );
  }
}

class SegmentedControlOption extends StatelessWidget {
  const SegmentedControlOption({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final radius = BorderRadius.circular(t.tileRadius);
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: selected ? t.surface : Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: t.minTouch),
            child: Center(
              heightFactor: 1,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge!
                    .copyWith(color: selected ? t.primaryDark : t.muted),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A setting row whose whole area toggles the switch.
class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: t.listRowMin),
      child: SwitchListTile(
        title: Text(title, style: Theme.of(context).textTheme.bodyLarge),
        subtitle: subtitle == null
            ? null
            : Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
        value: value,
        onChanged: onChanged,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }
}

/// Two round 48 dp buttons around a large number.
class CountStepper extends StatelessWidget {
  const CountStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max,
  });

  final int value;
  final int min;
  final int? max;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final l10n = AppLocalizations.of(context);
    Widget button(IconData icon, String label, int? next) => SizedBox.square(
      dimension: t.stepperButton,
      child: IconButton.outlined(
        onPressed: next == null || onChanged == null
            ? null
            : () => onChanged!(next),
        tooltip: label,
        icon: Icon(icon),
        color: t.primaryDark,
        style: IconButton.styleFrom(
          side: BorderSide(color: t.primary, width: t.outlineWidth),
        ),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(
          Icons.remove,
          l10n.stepperDecrease,
          value > min ? value - 1 : null,
        ),
        ConstrainedBox(
          constraints: BoxConstraints(minWidth: t.stepperButton),
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium!
                .copyWith(fontSize: t.stepperNumberSize),
          ),
        ),
        button(
          Icons.add,
          l10n.stepperIncrease,
          max == null || value < max! ? value + 1 : null,
        ),
      ],
    );
  }
}
