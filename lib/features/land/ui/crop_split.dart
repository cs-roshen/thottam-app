import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/settings.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/widgets/widgets.dart';
import '../../../core/money/money_format.dart';
import '../../../core/money/money_parse.dart';
import '../../../l10n/app_localizations.dart';
import '../data/land_providers.dart';
import '../domain/land.dart';
import 'land_labels.dart';

/// Chips for the farm's plots; the chosen one gets the entry.
class PlotChips extends ConsumerWidget {
  const PlotChips({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plots = ref.watch(plotsProvider).value ?? const <PlotView>[];
    return Wrap(
      spacing: 8,
      children: [
        for (final p in plots)
          ChoiceChipX(
            key: Key('plotChip.${p.id}'),
            label: p.name,
            selected: p.id == selected,
            onSelected: (_) => onSelected(p.id),
          ),
      ],
    );
  }
}

/// How an amount on a mixed plot goes to its crops: the parts by default,
/// editable by hand; or, when the setting says so, all to one crop. The
/// parts always sum to the amount; the screen keeps them.
class CropSplit extends ConsumerWidget {
  const CropSplit({
    super.key,
    required this.cycles,
    required this.parts,
    required this.editing,
    required this.onToggleEdit,
    required this.onPart,
    this.single,
    this.onSingle,
  });

  final List<CycleView> cycles;
  final List<int> parts;
  final bool editing;
  final VoidCallback onToggleEdit;
  final void Function(int index, int paise) onPart;

  /// When the amount goes to one crop: its id, and how to pick another.
  final String? single;
  final ValueChanged<String>? onSingle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);
    if (onSingle != null) {
      return Wrap(
        spacing: 8,
        children: [
          for (final c in cycles)
            ChoiceChipX(
              key: Key('split.one.${c.id}'),
              label: l10n.cropName(settings, c),
              selected: c.id == single,
              onSelected: (_) => onSingle!(c.id),
            ),
        ],
      );
    }
    return ThottamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // wraps at large text sizes rather than squeezing the button
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(l10n.expenseSplit, style: text.bodyLarge),
              TextButton(
                key: const Key('split.edit'),
                onPressed: onToggleEdit,
                child: Text(l10n.expenseSplitEdit),
              ),
            ],
          ),
          for (var i = 0; i < cycles.length && i < parts.length; i++)
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: t.minTouch),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.cropName(settings, cycles[i]),
                      style: text.bodyMedium,
                    ),
                  ),
                  if (editing)
                    SizedBox(
                      width: 140,
                      child: _PartField(
                        key: Key('split.part.$i'),
                        paise: parts[i],
                        onChanged: (p) => onPart(i, p),
                      ),
                    )
                  else
                    Text(formatPaise(parts[i]), style: text.bodyLarge),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A rupee field that shows the current part and reports edits.
class _PartField extends StatefulWidget {
  const _PartField({super.key, required this.paise, required this.onChanged});

  final int paise;
  final ValueChanged<int> onChanged;

  @override
  State<_PartField> createState() => _PartFieldState();
}

class _PartFieldState extends State<_PartField> {
  late final _c = TextEditingController(text: _text(widget.paise));
  final _focus = FocusNode();

  static String _text(int paise) =>
      formatPaise(paise).replaceAll('₹', '').replaceAll(',', '');

  @override
  void didUpdateWidget(_PartField old) {
    super.didUpdateWidget(old);
    // follow the rebalanced value unless the farmer is typing in this one
    if (!_focus.hasFocus && parseRupeesToPaise(_c.text) != widget.paise) {
      _c.text = _text(widget.paise);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _c,
    focusNode: _focus,
    textAlign: TextAlign.end,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
    decoration: const InputDecoration(prefixText: '₹ ', isDense: true),
    onChanged: (v) {
      final p = parseRupeesToPaise(v);
      if (p != null) widget.onChanged(p);
    },
  );
}
