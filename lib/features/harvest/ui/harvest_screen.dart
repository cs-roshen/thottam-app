import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/date_format.dart';
import '../../../app/session.dart';
import '../../../app/settings.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/widgets/widgets.dart';
import '../../../core/money/money_format.dart';
import '../../../core/money/money_parse.dart';
import '../../../core/overrides/overrides.dart';
import '../../../core/units/quantity_parse.dart';
import '../../../l10n/app_localizations.dart';
import '../../labour/data/labour_providers.dart';
import '../../labour/data/labour_repository.dart';
import '../../land/data/land_providers.dart';
import '../../land/domain/land.dart';
import '../../land/domain/split_targets.dart';
import '../../land/ui/crop_split.dart';
import '../../land/ui/land_labels.dart';
import '../data/harvest_providers.dart';
import '../data/harvest_repository.dart';
import '../domain/harvest_math.dart';

/// One team as the form holds it while the farmer edits.
class _Team {
  _Team({
    required this.ratePaise,
    this.heads = 1,
    this.workerId,
    this.groupId,
    this.label = '',
    this.isFamily = false,
    this.pieceRate = false,
    this.quantity,
  });

  int heads;
  int ratePaise;
  final String? workerId;
  final String? groupId;
  final String label;
  final bool isFamily;
  bool pieceRate;
  int? quantity;

  HarvestTeam team({required bool perTeam}) => HarvestTeam(
    heads: heads,
    ratePaise: ratePaise,
    pieceRate: pieceRate,
    // a piece-rate team always keeps its quantity, for its wage
    quantity: perTeam || pieceRate ? quantity : null,
    isFamily: isFamily,
    workerId: workerId,
    groupId: groupId,
    label: label,
  );
}

/// Screen 12: total quantity with its unit, any number of teams (groups by
/// head count, named workers), quantity per team when the switch is on and
/// always for a piece-rate team; the summary below. Saving creates the
/// harvest, its teams and its lot. With [editId] it edits a saved harvest's
/// teams.
class HarvestScreen extends ConsumerStatefulWidget {
  const HarvestScreen({super.key, this.plotId, this.editId});

  final String? plotId;
  final String? editId;

  @override
  ConsumerState<HarvestScreen> createState() => _HarvestScreenState();
}

class _HarvestScreenState extends ConsumerState<HarvestScreen> {
  late String _day;
  String? _plotId;
  String? _cycleId;
  String? _unit;
  bool _perTeam = false;
  final _total = TextEditingController();
  final _teams = <_Team>[];
  LastHarvest? _last;
  bool _loaded = false;
  bool _showErrors = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _day = _iso(ref.read(clockProvider)());
    _plotId = widget.plotId;
  }

  @override
  void dispose() {
    _total.dispose();
    super.dispose();
  }

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Fills the form from the saved harvest being edited.
  void _load(HarvestView h) {
    _loaded = true;
    _day = h.day;
    _plotId = h.plotId;
    _cycleId = h.cycleId;
    _unit = h.unit;
    _perTeam = h.perTeam;
    _total.text = _plain(h.quantity);
    _teams
      ..clear()
      ..addAll([
        for (final t in h.teams)
          _Team(
            heads: t.heads,
            ratePaise: t.ratePaise,
            workerId: t.workerId,
            groupId: t.groupId,
            label: t.label,
            isFamily: t.isFamily,
            pieceRate: t.pieceRate,
            quantity: t.quantity,
          ),
      ]);
  }

  static String _plain(int thousandths) => (thousandths / 1000)
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'\.?0+$'), '');

  int _groupRate(Overrides? o) =>
      (o
                  ?.list('rate_class', const Scope())
                  .firstOrNull
                  ?.data['default_rate_paise']
                  ?.value
              as num?)
          ?.toInt() ??
      0;

  Future<void> _addNamed() async {
    final workers = ref.read(workersProvider).value ?? const <WorkerView>[];
    final l10n = AppLocalizations.of(context);
    final picked = await showThottamSheet<WorkerView>(
      context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.harvestChooseWorker,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (workers.isEmpty) Text(l10n.labourNoWorkers),
          for (final w in workers)
            ListTile(
              key: Key('harvest.pick.${w.id}'),
              title: Text(w.name),
              subtitle: Text(
                l10n.labourRatePerDay(formatPaise(w.defaultRatePaise)),
              ),
              onTap: () => Navigator.pop(context, w),
            ),
        ],
      ),
    );
    if (picked == null) return;
    setState(
      () => _teams.add(
        _Team(
          ratePaise: picked.defaultRatePaise,
          workerId: picked.id,
          label: picked.name,
          isFamily: picked.isFamily,
        ),
      ),
    );
  }

  Future<void> _save(PlotView plot, CycleView cycle) async {
    final teams = [for (final t in _teams) t.team(perTeam: _perTeam)];
    final total = parseQuantity(_total.text);
    final quantity = harvestQuantity(teams, perTeam: _perTeam, total: total);
    if (teams.isEmpty || quantity <= 0) {
      setState(() => _showErrors = true);
      return;
    }
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(harvestRepositoryProvider);
    final input = HarvestInput(
      day: _day,
      plotId: plot.id,
      cycleId: cycle.id,
      unit: _unit ?? 'kg',
      teams: teams,
      perTeam: _perTeam,
      total: total,
      plotName: plot.name,
      cropMl: cycle.nameMl,
      cropEn: cycle.nameEn,
    );
    final money = ref.read(canWriteLotCostProvider);
    final String id;
    final List<String> events;
    if (widget.editId case final edit?) {
      id = edit;
      events = await repo.editTeams(edit, input, canWriteMoney: money);
    } else {
      (id, events) = await repo.save(input, canWriteMoney: money);
    }
    if (!mounted) return;
    showUndoToast(context, l10n.toastSaved, () => repo.undo(events));
    if (widget.editId != null) {
      context.pop();
    } else {
      context.pushReplacement('/harvest/$id');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);
    final overrides = ref.watch(overridesProvider).value;
    final canWrite = ref.watch(canWriteDailyProvider);
    // loaded ahead, so the worker sheet opens with them
    ref.watch(workersProvider);
    if (widget.editId case final id? when !_loaded) {
      final h = ref.watch(harvestProvider(id)).value;
      if (h != null) _load(h);
    }
    final plots = ref.watch(plotsProvider).value ?? const <PlotView>[];
    final plot =
        plots.where((p) => p.id == _plotId).firstOrNull ?? plots.firstOrNull;
    final cycles = openCycles(plot);
    final cycle =
        cycles.where((c) => c.id == _cycleId).firstOrNull ?? cycles.firstOrNull;
    // the crop's own units first, then the rest, never areas
    final units = [
      for (final u
          in overrides?.list('unit', Scope(cropId: cycle?.cropId)) ??
              const <ListItem>[])
        if (!u.hidden && u.data['dimension']?.value != 'area') u.code,
    ];
    final unit = _unit ?? (units.contains('kg') ? 'kg' : units.firstOrNull);
    final teams = [for (final x in _teams) x.team(perTeam: _perTeam)];
    final summary = summarise(
      teams,
      perTeam: _perTeam,
      total: parseQuantity(_total.text),
    );
    if (cycle != null && _last == null && widget.editId == null) {
      ref.read(harvestRepositoryProvider).lastHarvest(cycle.id).then((l) {
        if (mounted && l != null && _last?.day != l.day) {
          setState(() => _last = l);
        }
      });
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.harvestTitle)),
      body: ListView(
        padding: EdgeInsets.all(t.screenPadding),
        children: [
          if (!canWrite) ...[
            LastTimeBanner(
              text: l10n.harvestReadOnly,
              icon: Icons.lock_outline,
            ),
            SizedBox(height: t.cardGap),
          ],
          if (_last case final l?) ...[
            LastTimeBanner(
              text: l10n.harvestLastTime(
                l10n.quantityWithUnit(formatQuantity(l.quantity), l.unit),
                l.people,
                formatDay(l.day, l10n, ref.watch(clockProvider)()),
              ),
            ),
            SizedBox(height: t.cardGap),
          ],
          if (widget.editId == null) ...[
            Text(l10n.labourPlot, style: text.bodySmall),
            PlotChips(
              selected: plot?.id,
              onSelected: (id) => setState(() {
                _plotId = id;
                _cycleId = null;
                _last = null;
              }),
            ),
            if (cycles.length > 1) ...[
              SizedBox(height: t.cardGap),
              Text(l10n.harvestCrop, style: text.bodySmall),
              Wrap(
                spacing: 8,
                children: [
                  for (final c in cycles)
                    ChoiceChipX(
                      key: Key('harvest.crop.${c.nameEn}'),
                      label: l10n.cropName(settings, c),
                      selected: c.id == cycle?.id,
                      onSelected: (_) => setState(() {
                        _cycleId = c.id;
                        _unit = null;
                        _last = null;
                      }),
                    ),
                ],
              ),
            ],
            SizedBox(height: t.cardGap),
          ],
          if (plot != null && cycle == null)
            Text(l10n.harvestNoCrop, style: text.bodyMedium)
          else ...[
            if (!_perTeam)
              TextField(
                key: const Key('harvest.total'),
                controller: _total,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                style: text.displayLarge,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: l10n.harvestTotalQuantity,
                  suffixText: unit,
                ),
              ),
            Wrap(
              spacing: 8,
              children: [
                for (final u in units)
                  ChoiceChipX(
                    key: Key('harvest.unit.$u'),
                    label: u,
                    selected: u == unit,
                    onSelected: (_) => setState(() => _unit = u),
                  ),
              ],
            ),
            SwitchRow(
              key: const Key('harvest.perTeam'),
              title: l10n.harvestPerTeamQuantity,
              subtitle: l10n.harvestPerTeamQuantityHint,
              value: _perTeam,
              onChanged: (v) => setState(() => _perTeam = v),
            ),
            SizedBox(height: t.cardGap),
            Text(l10n.harvestTeams, style: text.titleLarge),
            for (var i = 0; i < _teams.length; i++) ...[
              SizedBox(height: t.cardGap),
              _TeamCard(
                key: Key('harvest.team.$i'),
                team: _teams[i],
                index: i,
                unit: unit ?? '',
                perTeam: _perTeam,
                onChanged: () => setState(() {}),
                onRemove: () => setState(() => _teams.removeAt(i)),
              ),
            ],
            SizedBox(height: t.cardGap),
            Row(
              children: [
                Expanded(
                  child: OutlineButton(
                    key: const Key('harvest.addGroup'),
                    label: l10n.harvestAddGroup,
                    icon: Icons.add,
                    onPressed: () => setState(
                      () => _teams.add(_Team(ratePaise: _groupRate(overrides))),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlineButton(
                    key: const Key('harvest.addNamed'),
                    label: l10n.harvestAddNamedWorker,
                    icon: Icons.add,
                    onPressed: _addNamed,
                  ),
                ),
              ],
            ),
            if (_showErrors)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _teams.isEmpty ? l10n.harvestNoTeams : l10n.harvestNoQuantity,
                  style: text.bodySmall!.copyWith(color: t.danger),
                ),
              ),
            SizedBox(height: t.cardGap),
            _Summary(summary: summary, unit: unit ?? ''),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(t.screenPadding),
          child: PrimaryButton(
            key: const Key('harvest.save'),
            label: l10n.actionSave,
            onPressed: !canWrite || _saving || plot == null || cycle == null
                ? null
                : () => _save(plot, cycle),
          ),
        ),
      ),
    );
  }
}

class _TeamCard extends StatelessWidget {
  const _TeamCard({
    super.key,
    required this.team,
    required this.index,
    required this.unit,
    required this.perTeam,
    required this.onChanged,
    required this.onRemove,
  });

  final _Team team;
  final int index;
  final String unit;
  final bool perTeam;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final h = team.team(perTeam: perTeam);
    final (perPerson, costPerUnit) = teamRates(h);
    final named = team.workerId != null;
    return ThottamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  named
                      ? team.label
                      : (team.label.isEmpty
                            ? l10n.harvestAddGroup
                            : team.label),
                  style: text.titleMedium,
                ),
              ),
              Pill(
                label: named ? l10n.teamTagNamed : l10n.teamTagGroup,
                background: named ? t.primaryTint : t.infoTint,
                foreground: named ? t.primaryDark : t.onInfoTintStrong,
              ),
              if (team.isFamily) ...[
                const SizedBox(width: 6),
                Pill(
                  label: l10n.labourFamily,
                  background: t.accentTint,
                  foreground: t.onAccentTintStrong,
                ),
              ],
              IconButton(
                key: Key('harvest.team.$index.remove'),
                tooltip: l10n.actionRemove,
                icon: const Icon(Icons.close),
                onPressed: onRemove,
              ),
            ],
          ),
          if (!named)
            Row(
              children: [
                Expanded(
                  child: Text(l10n.labourHeadCount, style: text.bodyMedium),
                ),
                CountStepper(
                  key: Key('harvest.team.$index.heads'),
                  value: team.heads,
                  min: 1,
                  onChanged: (v) {
                    team.heads = v;
                    onChanged();
                  },
                ),
              ],
            ),
          SwitchRow(
            key: Key('harvest.team.$index.piece'),
            title: l10n.harvestPieceRate,
            value: team.pieceRate,
            onChanged: (v) {
              team.pieceRate = v;
              onChanged();
            },
          ),
          _NumberField(
            key: Key('harvest.team.$index.rate'),
            label: team.pieceRate
                ? l10n.harvestRatePerUnit(unit)
                : named
                ? l10n.harvestWageNamed
                : l10n.fieldWagePerPerson,
            text: formatPaise(team.ratePaise)
                .replaceAll('₹', '')
                .replaceAll(',', ''),
            onChanged: (v) {
              team.ratePaise = parseRupeesToPaise(v) ?? 0;
              onChanged();
            },
          ),
          if (perTeam || team.pieceRate)
            _NumberField(
              key: Key('harvest.team.$index.quantity'),
              label: l10n.fieldQuantityInUnit(unit),
              text: team.quantity == null
                  ? ''
                  : (team.quantity! / 1000)
                        .toStringAsFixed(3)
                        .replaceFirst(RegExp(r'\.?0+$'), ''),
              onChanged: (v) {
                team.quantity = parseQuantity(v);
                onChanged();
              },
            ),
          const SizedBox(height: 6),
          Text(
            l10n.harvestTeamWage(formatPaise(h.wagePaise)),
            style: text.bodyLarge,
          ),
          if (perPerson != null && costPerUnit != null)
            Text(
              l10n.harvestTeamRates(
                l10n.quantityWithUnit(formatQuantity(perPerson), unit),
                formatPaise(costPerUnit),
                unit,
              ),
              style: text.bodySmall,
            ),
        ],
      ),
    );
  }
}

/// A number field that keeps its own text while the farmer types.
class _NumberField extends StatefulWidget {
  const _NumberField({
    super.key,
    required this.label,
    required this.text,
    required this.onChanged,
  });

  final String label;
  final String text;
  final ValueChanged<String> onChanged;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final _c = TextEditingController(text: widget.text);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _c,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
    decoration: InputDecoration(labelText: widget.label),
    onChanged: widget.onChanged,
  );
}

class _Summary extends StatelessWidget {
  const _Summary({required this.summary, required this.unit});

  final HarvestSummary summary;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    Widget line(String label, String value, {Key? key}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: text.bodyMedium)),
          Text(value, key: key, style: text.bodyLarge),
        ],
      ),
    );
    return ThottamCard(
      child: Column(
        children: [
          line(
            l10n.harvestTotalQuantity,
            l10n.quantityWithUnit(formatQuantity(summary.quantity), unit),
            key: const Key('harvest.sum.quantity'),
          ),
          line(
            l10n.harvestPerPersonPerDay,
            summary.perPerson == null
                ? '—'
                : l10n.quantityWithUnit(
                    formatQuantity(summary.perPerson!),
                    unit,
                  ),
            key: const Key('harvest.sum.perPerson'),
          ),
          line(
            l10n.harvestLabourCostPerUnit,
            summary.labourCostPerUnit == null
                ? '—'
                : l10n.ratePerUnit(
                    formatPaise(summary.labourCostPerUnit!),
                    unit,
                  ),
            key: const Key('harvest.sum.costPerUnit'),
          ),
          line(
            l10n.harvestPaidWages,
            formatPaise(summary.paidWagesPaise),
            key: const Key('harvest.sum.wages'),
          ),
          if (summary.familyWagesPaise > 0)
            line(
              l10n.harvestFamilyLine,
              formatPaise(summary.familyWagesPaise),
              key: const Key('harvest.sum.family'),
            ),
        ],
      ),
    );
  }
}
