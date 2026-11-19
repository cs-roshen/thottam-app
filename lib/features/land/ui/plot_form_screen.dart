import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/tokens.dart';
import '../../../app/widgets/widgets.dart';
import '../../../core/units/quantity_parse.dart';
import '../../../l10n/app_localizations.dart';
import '../../onboarding/data/onboarding_providers.dart';
import '../data/land_providers.dart';
import '../data/land_repository.dart';
import '../domain/land.dart';
import 'land_labels.dart';

/// Add a plot, or edit one with [plotId]: name, area with its unit, and
/// tenure.
class PlotFormScreen extends ConsumerStatefulWidget {
  const PlotFormScreen({super.key, this.plotId});

  final String? plotId;

  @override
  ConsumerState<PlotFormScreen> createState() => _PlotFormScreenState();
}

class _PlotFormScreenState extends ConsumerState<PlotFormScreen> {
  final _name = TextEditingController();
  final _area = TextEditingController();
  String? _unit;
  String _tenure = 'owned';
  bool _loaded = false;
  bool _showErrors = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _area.dispose();
    super.dispose();
  }

  void _load(PlotView p) {
    _loaded = true;
    _name.text = p.name;
    _area.text = p.area == null ? '' : _plain(p.area!);
    _unit = p.areaUnit;
    _tenure = p.tenure;
  }

  /// Thousandths as the farmer would type them: 2500 → "2.5".
  static String _plain(int thousandths) {
    final s = (thousandths / 1000).toStringAsFixed(3);
    return s.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  bool get _areaOk =>
      _area.text.trim().isEmpty || parseQuantity(_area.text) != null;

  Future<void> _save(String unit) async {
    if (_name.text.trim().isEmpty || !_areaOk) {
      setState(() => _showErrors = true);
      return;
    }
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(landRepositoryProvider);
    final input = PlotInput(
      name: _name.text,
      area: parseQuantity(_area.text),
      areaUnit: unit,
      tenure: _tenure,
    );
    final List<String> events;
    if (widget.plotId case final id?) {
      events = await repo.updatePlot(id, input);
    } else {
      (_, events) = await repo.createPlot(input);
    }
    if (!mounted) return;
    showUndoToast(context, l10n.toastSaved, () => repo.undo(events));
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final units = ref.watch(setupChoicesProvider).value?.$2;
    if (widget.plotId case final id? when !_loaded) {
      final plot = ref.watch(plotProvider(id)).value;
      if (plot != null) _load(plot);
    }
    final unit = _unit ?? units?.firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.plotId == null
              ? l10n.plotFormTitleNew
              : l10n.plotFormTitleEdit,
        ),
      ),
      body: ListView(
        padding: EdgeInsets.all(t.screenPadding),
        children: [
          ThottamCard(
            child: Column(
              children: [
                TextField(
                  key: const Key('plot.name'),
                  controller: _name,
                  autofocus: widget.plotId == null,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: l10n.plotName,
                    errorText: _showErrors && _name.text.trim().isEmpty
                        ? l10n.plotNameRequired
                        : null,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('plot.area'),
                  controller: _area,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: l10n.fieldOptional(l10n.fieldArea),
                    suffixText: unit,
                    errorText: _areaOk ? null : l10n.setupAreaInvalid,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: t.cardGap),
          Text(l10n.setupAreaUnit, style: text.bodySmall),
          Wrap(
            spacing: 8,
            children: [
              for (final u in units ?? const <String>[])
                ChoiceChipX(
                  key: Key('plot.unit.$u'),
                  label: u,
                  selected: u == unit,
                  onSelected: (_) => setState(() => _unit = u),
                ),
            ],
          ),
          SizedBox(height: t.cardGap),
          Text(l10n.setupTenure, style: text.bodySmall),
          Wrap(
            spacing: 8,
            children: [
              for (final code in const ['owned', 'leased', 'shared'])
                ChoiceChipX(
                  key: Key('plot.tenure.$code'),
                  label: l10n.tenure(code),
                  selected: _tenure == code,
                  onSelected: (_) => setState(() => _tenure = code),
                ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(t.screenPadding),
          child: PrimaryButton(
            key: const Key('plot.save'),
            label: l10n.actionSave,
            onPressed: unit == null || _saving ? null : () => _save(unit),
          ),
        ),
      ),
    );
  }
}
