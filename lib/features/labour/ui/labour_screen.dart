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
import '../../../core/split/split.dart';
import '../../../core/units/quantity_parse.dart';
import '../../../l10n/app_localizations.dart';
import '../../land/data/land_providers.dart';
import '../../land/domain/land.dart';
import '../../land/domain/split_targets.dart';
import '../../land/ui/crop_split.dart';
import '../data/labour_providers.dart';
import '../data/labour_repository.dart';
import '../domain/wages.dart';
import 'worker_form.dart';

/// Screens 8 and 11: a day's labour, by named workers (attendance) or by a
/// group's head count per rate class, with the wage posted to the plot's
/// crop or split across a mixed plot's crops.
class LabourScreen extends ConsumerStatefulWidget {
  const LabourScreen({super.key, this.plotId});

  final String? plotId;

  @override
  ConsumerState<LabourScreen> createState() => _LabourScreenState();
}

class _Mark {
  _Mark(this.attendance, this.ratePaise, [this.overtimeHours = 0]);
  Attendance attendance;
  int ratePaise;

  /// Whole hours.
  int overtimeHours;
}

class _LabourScreenState extends ConsumerState<LabourScreen> {
  late String _day;
  String? _plotId;
  String? _task;
  int _mode = 0;
  final _marks = <String, _Mark>{};
  int? _overtimeRate;

  // group
  String? _groupId;
  final _label = TextEditingController();
  final _heads = <String, int>{};
  final _rates = <String, int>{};
  bool _lump = false;
  int? _lumpPaise;
  final _hours = TextEditingController();

  // split
  final _fixed = <int, int>{};
  bool _editSplit = false;
  String? _single;

  bool _saving = false;
  bool _showErrors = false;

  @override
  void initState() {
    super.initState();
    final now = ref.read(clockProvider)();
    _day = _iso(now);
    _plotId = widget.plotId;
    ref.read(labourRepositoryProvider).lastPlotAndTask().then((last) {
      if (!mounted) return;
      setState(() {
        _plotId ??= last.$1;
        _task ??= last.$2;
      });
    });
  }

  @override
  void dispose() {
    _label.dispose();
    _hours.dispose();
    super.dispose();
  }

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Overrides? get _overrides => ref.read(overridesProvider).value;

  int get _defaultOvertimeRate =>
      (_overrides
                  ?.value(
                    'setting',
                    'overtime_rate_paise',
                    'value',
                    Scope(plotId: _plotId),
                  )
                  ?.value
              as num?)
          ?.toInt() ??
      0;

  int get _overtime => _overtimeRate ?? _defaultOvertimeRate;

  List<WorkerDay> _workerDays() => [
    for (final MapEntry(:key, :value) in _marks.entries)
      WorkerDay(
        key,
        value.attendance,
        ratePaise: value.ratePaise,
        overtimeHours: value.overtimeHours * 1000,
        overtimeRatePaise: _overtime,
      ),
  ];

  List<GroupLine> _lines(List<ListItem> classes) => [
    for (final c in classes)
      GroupLine(c.code, _heads[c.code] ?? 0, _rates[c.code] ?? _rateOf(c)),
  ];

  int _rateOf(ListItem c) {
    final group = ref
        .read(groupsProvider)
        .value
        ?.where((g) => g.id == _groupId)
        .firstOrNull;
    return group?.defaultRates[c.code] ??
        (c.data['default_rate_paise']?.value as num?)?.toInt() ??
        0;
  }

  int _total(List<ListItem> classes) => _mode == 0
      ? _workerDays().fold(0, (s, w) => s + w.paise)
      : _lump
      ? (_lumpPaise ?? 0)
      : groupWage(_lines(classes));

  /// The day's parts across [cycles]: by default shares, then each part the
  /// farmer typed, in the order typed.
  List<int> _parts(int total, List<CycleView> cycles) {
    final targets = splitTargets(cycles, _overrides);
    var parts = splitAmount(total, targets, SplitMode.templateShare);
    final done = <int>{};
    for (final MapEntry(:key, :value) in _fixed.entries) {
      if (key >= parts.length) continue;
      parts = rebalance(total, parts, key, value, fixed: done);
      done.add(key);
    }
    return parts;
  }

  WageTarget _target(int total, List<CycleView> cycles, bool splits) {
    if (cycles.isEmpty) return const WageTarget.none();
    if (cycles.length == 1) return WageTarget.one(cycles.single.id);
    if (!splits) {
      return WageTarget.one(
        cycles.any((c) => c.id == _single) ? _single! : cycles.first.id,
      );
    }
    final parts = _parts(total, cycles);
    // an all-zero day still needs weights to split by
    return WageTarget.split(
      [for (final c in cycles) c.id],
      parts.every((p) => p == 0)
          ? splitWeights(
              splitTargets(cycles, _overrides),
              SplitMode.templateShare,
            )
          : parts,
    );
  }

  Future<void> _sameAsYesterday() async {
    final l10n = AppLocalizations.of(context);
    final last = await ref.read(labourRepositoryProvider).lastDay(_day);
    if (!mounted) return;
    if (last.isEmpty) {
      showToast(context, l10n.labourNothingToCopy);
      return;
    }
    setState(() {
      _marks.clear();
      for (final w in last) {
        _marks[w.workerId] = _Mark(
          w.attendance,
          w.ratePaise,
          w.overtimeHours ~/ 1000,
        );
      }
    });
  }

  Future<void> _save(
    List<ListItem> classes,
    PlotView? plot,
    bool splits,
  ) async {
    final total = _total(classes);
    final ok = _mode == 0
        ? _marks.isNotEmpty
        : (_lump
              ? (_lumpPaise ?? 0) > 0
              : _lines(classes).any((l) => l.heads > 0));
    if (!ok) {
      setState(() => _showErrors = true);
      return;
    }
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(labourRepositoryProvider);
    final cycles = openCycles(plot);
    final target = _target(total, cycles, splits);
    final manual = _fixed.isNotEmpty;
    final List<String> events;
    if (_mode == 0) {
      final names = {
        for (final w in ref.read(workersProvider).value ?? const <WorkerView>[])
          w.id: w.name,
      };
      events = await repo.saveWorkersDay(
        day: _day,
        workers: _workerDays(),
        target: target,
        plotId: plot?.id,
        plotName: plot?.name,
        taskCode: _task,
        manualSplit: manual,
        names: names,
      );
    } else {
      events = await repo.saveGroupDay(
        day: _day,
        groupId: _groupId,
        label: _label.text,
        lines: _lines(classes),
        lumpSumPaise: _lump ? _lumpPaise : null,
        hours: parseQuantity(_hours.text),
        target: target,
        plotId: plot?.id,
        plotName: plot?.name,
        taskCode: _task,
        manualSplit: manual,
      );
    }
    if (!mounted) return;
    showUndoToast(context, l10n.toastSaved, () => repo.undo(events));
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  Future<void> _pickDay() async {
    final now = ref.read(clockProvider)();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(_day),
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null) setState(() => _day = _iso(picked));
  }

  Future<void> _changeRate(String workerId, _Mark mark) async {
    final paise = await showAmountDialog(
      context,
      title: AppLocalizations.of(context).labourChangeRate,
      paise: mark.ratePaise,
      fieldKey: const Key('labour.rateField'),
      saveKey: const Key('labour.rateSave'),
    );
    if (paise != null) setState(() => mark.ratePaise = paise);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);
    final overrides = ref.watch(overridesProvider).value;
    final canWrite = ref.watch(canWriteDailyProvider);
    final plots = ref.watch(plotsProvider).value ?? const <PlotView>[];
    final plot =
        plots.where((p) => p.id == _plotId).firstOrNull ?? plots.firstOrNull;
    final cycles = openCycles(plot);
    final splits = labourSplits(overrides, plot?.id);
    // the general tasks and each growing crop's own, once each
    final tasks = <String, ListItem>{
      for (final scope in [
        Scope(plotId: plot?.id),
        for (final c in cycles)
          Scope(cropId: c.cropId, plotId: c.plotId, cropCycleId: c.id),
      ])
        for (final i
            in overrides?.list('labour_task', scope) ?? const <ListItem>[])
          if (!i.hidden) i.code: i,
    }.values.toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final classes = [
      for (final i
          in overrides?.list('rate_class', const Scope()) ?? const <ListItem>[])
        if (!i.hidden) i,
    ];
    final total = _total(classes);
    String name(ListItem i) =>
        localName(settings, i.nameMl.value, i.nameEn.value, l10n.nameMixed);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.labourTitle),
        actions: [
          IconButton(
            key: const Key('labour.team'),
            tooltip: l10n.labourTeam,
            icon: const Icon(Icons.groups_outlined),
            onPressed: () => context.push('/labour/team'),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.all(t.screenPadding),
        children: [
          if (!canWrite) ...[
            LastTimeBanner(text: l10n.labourReadOnly, icon: Icons.lock_outline),
            SizedBox(height: t.cardGap),
          ],
          Row(
            children: [
              Expanded(child: Text(l10n.labourDate, style: text.bodySmall)),
              TextButton.icon(
                key: const Key('labour.day'),
                onPressed: _pickDay,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(formatDay(_day, l10n, ref.watch(clockProvider)())),
              ),
            ],
          ),
          Text(l10n.labourPlot, style: text.bodySmall),
          PlotChips(
            selected: plot?.id,
            onSelected: (id) => setState(() {
              _plotId = id;
              _fixed.clear();
              _single = null;
            }),
          ),
          SizedBox(height: t.cardGap),
          Text(l10n.labourTask, style: text.bodySmall),
          Wrap(
            spacing: 8,
            children: [
              for (final task in tasks)
                ChoiceChipX(
                  key: Key('labour.task.${task.code}'),
                  label: name(task),
                  selected: task.code == _task,
                  onSelected: (_) => setState(
                    () => _task = _task == task.code ? null : task.code,
                  ),
                ),
            ],
          ),
          SizedBox(height: t.cardGap),
          SegmentedControl(
            key: const Key('labour.mode'),
            labels: [l10n.labourModeNamed, l10n.labourModeGroup],
            selected: _mode,
            onChanged: (i) => setState(() {
              _mode = i;
              _showErrors = false;
            }),
          ),
          SizedBox(height: t.cardGap),
          if (_mode == 0) ..._named(l10n) else ..._group(l10n, classes, name),
          if (_showErrors)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _mode == 0 ? l10n.labourNothingMarked : l10n.labourNoHeads,
                style: text.bodySmall!.copyWith(color: t.danger),
              ),
            ),
          if (cycles.length > 1) ...[
            SizedBox(height: t.cardGap),
            if (!splits) Text(l10n.labourOneCrop, style: text.bodySmall),
            CropSplit(
              cycles: cycles,
              parts: _parts(total, cycles),
              editing: _editSplit,
              onToggleEdit: () => setState(() => _editSplit = !_editSplit),
              onPart: (i, p) => setState(() {
                _fixed.remove(i);
                _fixed[i] = p;
              }),
              single: splits
                  ? null
                  : (cycles.any((c) => c.id == _single)
                        ? _single
                        : cycles.first.id),
              onSingle: splits ? null : (id) => setState(() => _single = id),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            t.screenPadding,
            10,
            t.screenPadding,
            t.screenPadding,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(l10n.fieldTotalWages, style: text.bodyLarge),
                  ),
                  Text(
                    formatPaise(total),
                    key: const Key('labour.total'),
                    style: text.headlineMedium,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              PrimaryButton(
                key: const Key('labour.save'),
                label: l10n.actionSave,
                onPressed: !canWrite || _saving
                    ? null
                    : () => _save(classes, plot, splits),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _named(AppLocalizations l10n) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final workers = ref.watch(workersProvider).value ?? const <WorkerView>[];
    final teamWriter = ref.watch(canWriteTeamProvider);
    return [
      if (workers.isNotEmpty)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlineButton(
            key: const Key('labour.same'),
            label: l10n.labourSameAsYesterday,
            icon: Icons.replay,
            onPressed: _sameAsYesterday,
          ),
        ),
      if (workers.isEmpty) Text(l10n.labourNoWorkers, style: text.bodyMedium),
      for (final w in workers) ...[
        SizedBox(height: t.cardGap),
        _WorkerRow(
          worker: w,
          mark: _marks[w.id],
          onMark: (a) => setState(() {
            final m = _marks[w.id];
            if (m == null) {
              _marks[w.id] = _Mark(
                a,
                w.defaultRatePaise,
                a == Attendance.overtime ? 1 : 0,
              );
            } else if (m.attendance == a) {
              _marks.remove(w.id); // tapping the chosen one again clears it
            } else {
              m.attendance = a;
              if (a == Attendance.overtime && m.overtimeHours == 0) {
                m.overtimeHours = 1;
              }
            }
          }),
          onHours: (h) => setState(() => _marks[w.id]!.overtimeHours = h),
          onRate: () => _changeRate(w.id, _marks[w.id]!),
        ),
      ],
      if (_marks.values.any((m) => m.attendance == Attendance.overtime)) ...[
        SizedBox(height: t.cardGap),
        _AmountField(
          key: const Key('labour.overtimeRate'),
          label: l10n.labourOvertimeRate,
          paise: _overtime,
          onChanged: (p) => setState(() => _overtimeRate = p),
        ),
      ],
      if (teamWriter) ...[
        SizedBox(height: t.cardGap),
        OutlineButton(
          key: const Key('labour.addWorker'),
          label: l10n.labourAddWorker,
          icon: Icons.person_add_alt,
          onPressed: () => showWorkerForm(context, ref),
        ),
      ],
    ];
  }

  List<Widget> _group(
    AppLocalizations l10n,
    List<ListItem> classes,
    String Function(ListItem) name,
  ) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final groups = [
      for (final g in ref.watch(groupsProvider).value ?? const <GroupView>[])
        if (g.isNamed) g,
    ];
    return [
      if (groups.isNotEmpty) ...[
        Wrap(
          spacing: 8,
          children: [
            ChoiceChipX(
              key: const Key('labour.group.new'),
              label: l10n.labourNewGroup,
              selected: _groupId == null,
              onSelected: (_) => setState(() => _groupId = null),
            ),
            for (final g in groups)
              ChoiceChipX(
                key: Key('labour.group.${g.id}'),
                label: g.label,
                selected: _groupId == g.id,
                onSelected: (_) => setState(() {
                  _groupId = g.id;
                  _rates.clear();
                  if (g.usualSize != null &&
                      _heads.values.every((h) => h == 0)) {
                    _heads[classes.first.code] = g.usualSize!;
                  }
                }),
              ),
          ],
        ),
        SizedBox(height: t.cardGap),
      ],
      if (_groupId == null)
        TextField(
          key: const Key('labour.groupName'),
          controller: _label,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: l10n.labourGroupName),
        ),
      SizedBox(height: t.cardGap),
      ThottamCard(
        child: Column(
          children: [
            for (final c in classes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name(c), style: text.bodyLarge),
                          if (!_lump)
                            InkWell(
                              key: Key('labour.class.${c.code}.rate'),
                              onTap: () async {
                                final p = await _askAmount(
                                  l10n.labourDailyRate,
                                  _rates[c.code] ?? _rateOf(c),
                                );
                                if (p != null) {
                                  setState(() => _rates[c.code] = p);
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Text(
                                  l10n.labourRatePerDay(
                                    formatPaise(_rates[c.code] ?? _rateOf(c)),
                                  ),
                                  style: text.bodySmall!.copyWith(
                                    color: t.primary,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    CountStepper(
                      key: Key('labour.class.${c.code}'),
                      value: _heads[c.code] ?? 0,
                      onChanged: (v) => setState(() => _heads[c.code] = v),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      SwitchRow(
        key: const Key('labour.lump'),
        title: l10n.labourLumpSum,
        value: _lump,
        onChanged: (v) => setState(() => _lump = v),
      ),
      if (_lump)
        _AmountField(
          key: const Key('labour.lumpAmount'),
          label: l10n.labourLumpSumAmount,
          paise: _lumpPaise,
          onChanged: (p) => setState(() => _lumpPaise = p),
        ),
      TextField(
        key: const Key('labour.hours'),
        controller: _hours,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        decoration: InputDecoration(
          labelText: l10n.fieldOptional(l10n.labourHours),
        ),
      ),
      SizedBox(height: t.cardGap),
      Text(l10n.labourGroupHint, style: text.bodySmall),
    ];
  }

  Future<int?> _askAmount(String title, int paise) => showAmountDialog(
    context,
    title: title,
    paise: paise,
    fieldKey: const Key('labour.amountField'),
    saveKey: const Key('labour.amountSave'),
  );
}

class _WorkerRow extends StatelessWidget {
  const _WorkerRow({
    required this.worker,
    required this.mark,
    required this.onMark,
    required this.onHours,
    required this.onRate,
  });

  final WorkerView worker;
  final _Mark? mark;
  final ValueChanged<Attendance> onMark;
  final ValueChanged<int> onHours;
  final VoidCallback onRate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final m = mark;
    return ThottamCard(
      key: Key('worker.${worker.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(worker.name, style: text.titleMedium)),
              if (worker.isFamily) ...[
                Pill(
                  label: l10n.labourFamily,
                  background: t.infoTint,
                  foreground: t.onInfoTintStrong,
                ),
                const SizedBox(width: 8),
              ],
              InkWell(
                key: Key('worker.${worker.id}.rate'),
                onTap: m == null ? null : onRate,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    l10n.labourRatePerDay(
                      formatPaise(m?.ratePaise ?? worker.defaultRatePaise),
                    ),
                    style: text.bodySmall!.copyWith(
                      decoration: m == null ? null : TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Semantics(
            label: worker.name,
            child: Wrap(
              spacing: 8,
              children: [
                for (final (a, label) in [
                  (Attendance.full, l10n.attendanceFull),
                  (Attendance.half, l10n.attendanceHalf),
                  (Attendance.absent, l10n.attendanceAbsent),
                  (Attendance.overtime, l10n.attendanceOvertime),
                ])
                  ChoiceChipX(
                    key: Key('worker.${worker.id}.${a.name}'),
                    label: label,
                    selected: m?.attendance == a,
                    onSelected: (_) => onMark(a),
                  ),
              ],
            ),
          ),
          if (m?.attendance == Attendance.overtime)
            Row(
              children: [
                Expanded(
                  child: Text(l10n.labourOvertimeHours, style: text.bodyMedium),
                ),
                CountStepper(
                  key: Key('worker.${worker.id}.hours'),
                  value: m!.overtimeHours,
                  min: 1,
                  max: 12,
                  onChanged: onHours,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// A rupee field holding [paise], reporting each valid change.
class _AmountField extends StatefulWidget {
  const _AmountField({
    super.key,
    required this.label,
    required this.paise,
    required this.onChanged,
  });

  final String label;
  final int? paise;
  final ValueChanged<int?> onChanged;

  @override
  State<_AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<_AmountField> {
  late final _c = TextEditingController(
    text: widget.paise == null
        ? ''
        : formatPaise(widget.paise!).replaceAll('₹', '').replaceAll(',', ''),
  );

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
    decoration: InputDecoration(labelText: widget.label, prefixText: '₹ '),
    onChanged: (v) => widget.onChanged(parseRupeesToPaise(v)),
  );
}
