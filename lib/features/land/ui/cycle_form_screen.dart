import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/session.dart';
import '../../../app/settings.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/widgets/widgets.dart';
import '../../../core/units/quantity_parse.dart';
import '../../../l10n/app_localizations.dart';
import '../data/land_providers.dart';
import '../data/land_repository.dart';
import '../domain/land.dart';

/// Add a crop to [plotId], or edit crop cycle [cycleId]: the crop, and as
/// much as the farmer knows of variety, plants, area share, season and
/// planting year. Mixed and intercropped plots carry several.
class CycleFormScreen extends ConsumerStatefulWidget {
  const CycleFormScreen({super.key, required this.plotId, this.cycleId});

  final String plotId;
  final String? cycleId;

  @override
  ConsumerState<CycleFormScreen> createState() => _CycleFormScreenState();
}

class _CycleFormScreenState extends ConsumerState<CycleFormScreen> {
  String? _crop;
  final _variety = TextEditingController();
  final _plants = TextEditingController();
  final _share = TextEditingController();
  final _season = TextEditingController();
  final _year = TextEditingController();
  bool _loaded = false;
  bool _showErrors = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_variety, _plants, _share, _season, _year]) {
      c.dispose();
    }
    super.dispose();
  }

  void _load(CycleView c) {
    _loaded = true;
    _crop = c.cropId;
    _variety.text = c.variety ?? '';
    _plants.text = c.plantCount?.toString() ?? '';
    _share.text = c.areaShare == null
        ? ''
        : (c.areaShare! / 1000)
              .toStringAsFixed(3)
              .replaceFirst(RegExp(r'\.?0+$'), '');
    _season.text = c.season ?? '';
    _year.text = c.plantedOn?.substring(0, 4) ?? '';
  }

  int get _thisYear => ref.read(clockProvider)().year;
  bool get _plantsOk =>
      _plants.text.trim().isEmpty || int.tryParse(_plants.text.trim()) != null;
  bool get _shareOk =>
      _share.text.trim().isEmpty ||
      parsePercent(parseQuantity(_share.text)) != null;
  bool get _yearOk =>
      _year.text.trim().isEmpty ||
      plantedOnForYear(_year.text, _thisYear) != null;

  Future<void> _save(CropOption crop) async {
    final input = CycleInput(
      cropId: crop.id,
      variety: _variety.text,
      plantCount: int.tryParse(_plants.text.trim()),
      areaShare: parsePercent(parseQuantity(_share.text)),
      season: crop.kind == 'seasonal' ? _season.text : null,
      plantedOn: crop.kind == 'perennial'
          ? plantedOnForYear(_year.text, _thisYear)
          : null,
    );
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(landRepositoryProvider);
    final List<String> events;
    if (widget.cycleId case final id?) {
      events = await repo.updateCycle(widget.plotId, id, input);
    } else {
      (_, events) = await repo.createCycle(widget.plotId, input);
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
    final settings = ref.watch(settingsProvider);
    final crops = ref.watch(cropOptionsProvider).value ?? const [];
    if (widget.cycleId case final id? when !_loaded) {
      final plot = ref.watch(plotProvider(widget.plotId)).value;
      final cycle = plot?.cycles.where((c) => c.id == id).firstOrNull;
      if (cycle != null) _load(cycle);
    }
    final crop = crops.where((c) => c.id == _crop).firstOrNull;
    final ok = _plantsOk && _shareOk && _yearOk;

    Widget field(
      String key,
      TextEditingController c,
      String label, {
      bool number = false,
      String? error,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        key: Key('cycle.$key'),
        controller: c,
        keyboardType: number
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        inputFormatters: number
            ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
            : null,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: l10n.fieldOptional(label),
          errorText: error,
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.cycleId == null
              ? l10n.cycleFormTitleNew
              : l10n.cycleFormTitleEdit,
        ),
      ),
      body: ListView(
        padding: EdgeInsets.all(t.screenPadding),
        children: [
          Text(l10n.cycleCrop, style: text.bodySmall),
          Wrap(
            spacing: 8,
            children: [
              for (final c in crops)
                ChoiceChipX(
                  key: Key('cycle.crop.${c.nameEn}'),
                  label: localName(
                    settings,
                    c.nameMl,
                    c.nameEn,
                    l10n.nameMixed,
                  ),
                  selected: c.id == _crop,
                  onSelected: (_) => setState(() => _crop = c.id),
                ),
            ],
          ),
          if (_showErrors && crop == null)
            Text(
              l10n.cycleCropRequired,
              style: text.bodySmall!.copyWith(color: t.danger),
            ),
          SizedBox(height: t.cardGap),
          ThottamCard(
            child: Column(
              children: [
                field('variety', _variety, l10n.cycleVariety),
                field(
                  'plants',
                  _plants,
                  l10n.cyclePlantCount,
                  number: true,
                  error: _plantsOk ? null : l10n.cyclePlantCountInvalid,
                ),
                field(
                  'share',
                  _share,
                  l10n.cycleAreaShare,
                  number: true,
                  error: _shareOk ? null : l10n.cycleAreaShareInvalid,
                ),
                if (crop?.kind == 'seasonal')
                  field('season', _season, l10n.cycleSeason),
                if (crop?.kind == 'perennial')
                  field(
                    'year',
                    _year,
                    l10n.cyclePlantingYear,
                    number: true,
                    error: _yearOk ? null : l10n.cyclePlantingYearInvalid,
                  ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(t.screenPadding),
          child: PrimaryButton(
            key: const Key('cycle.save'),
            label: l10n.actionSave,
            onPressed: _saving
                ? null
                : () => crop == null || !ok
                      ? setState(() => _showErrors = true)
                      : _save(crop),
          ),
        ),
      ),
    );
  }
}
