import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/date_format.dart';
import '../../../app/session.dart';
import '../../../app/settings.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/widgets/widgets.dart';
import '../../../core/access/access.dart';
import '../../../core/overrides/overrides.dart';
import '../../../core/split/split.dart';
import '../../../l10n/app_localizations.dart';
import '../../land/data/land_providers.dart';
import '../../land/domain/land.dart';
import '../../land/domain/split_targets.dart';
import '../../land/ui/crop_split.dart';
import '../data/expense_providers.dart';
import '../data/expense_repository.dart';

/// Screen 9: amount first, what it was for (most used first), the plot
/// (last used), the split across its crops (by default share, editable),
/// how it was paid; save with undo.
class ExpenseScreen extends ConsumerStatefulWidget {
  const ExpenseScreen({super.key, this.plotId});

  final String? plotId;

  @override
  ConsumerState<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends ConsumerState<ExpenseScreen> {
  late String _day;
  int? _amount;
  String? _category;
  String? _plotId;
  String _mode = 'cash';
  final _vendor = TextEditingController();
  List<String> _byUse = const [];

  SplitMode _splitMode = SplitMode.templateShare;
  final _fixed = <int, int>{};
  bool _editSplit = false;
  bool _showErrors = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final now = ref.read(clockProvider)();
    _day = _iso(now);
    _plotId = widget.plotId;
    final repo = ref.read(expenseRepositoryProvider);
    Future.wait([repo.last(), repo.categoriesByUse(_day)]).then((r) {
      if (!mounted) return;
      final (plot, category, mode) = r[0] as (String?, String?, String?);
      setState(() {
        _plotId ??= plot;
        _byUse = r[1] as List<String>;
        _category ??= _byUse.firstOrNull ?? category;
        _mode = mode == 'credit' ? 'cash' : (mode ?? 'cash');
      });
    });
  }

  @override
  void dispose() {
    _vendor.dispose();
    super.dispose();
  }

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  List<int> _parts(int total, List<CycleView> cycles) {
    final targets = splitTargets(cycles, ref.read(overridesProvider).value);
    var parts = splitAmount(total, targets, _splitMode);
    final done = <int>{};
    for (final MapEntry(:key, :value) in _fixed.entries) {
      if (key >= parts.length) continue;
      parts = rebalance(total, parts, key, value, fixed: done);
      done.add(key);
    }
    return parts;
  }

  Future<void> _save(PlotView plot) async {
    final amount = _amount ?? 0;
    if (amount <= 0 || _category == null) {
      setState(() => _showErrors = true);
      return;
    }
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(expenseRepositoryProvider);
    final cycles = openCycles(plot);
    final parts = _parts(amount, cycles);
    final events = await repo.save(
      ExpenseInput(
        day: _day,
        categoryCode: _category!,
        amountPaise: amount,
        plotId: plot.id,
        plotName: plot.name,
        parts: [
          for (var i = 0; i < cycles.length; i++) (cycles[i].id, parts[i]),
        ],
        manual: _fixed.isNotEmpty,
        mode: _mode,
        vendor: _mode == 'credit' ? _vendor.text : null,
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);
    final overrides = ref.watch(overridesProvider).value;
    final canWrite =
        ref.watch(accessProvider).value?.canWrite(AccessClass.money) ?? false;
    final plots = ref.watch(plotsProvider).value ?? const <PlotView>[];
    final plot =
        plots.where((p) => p.id == _plotId).firstOrNull ?? plots.firstOrNull;
    final cycles = openCycles(plot);
    // most used first, then the template order
    final categories =
        [
          for (final i
              in overrides?.list('expense_category', Scope(plotId: plot?.id)) ??
                  const <ListItem>[])
            if (!i.hidden) i,
        ]..sort((a, b) {
          int rank(ListItem i) {
            final r = _byUse.indexOf(i.code);
            return r < 0 ? 1 << 20 : r;
          }

          final c = rank(a).compareTo(rank(b));
          return c != 0 ? c : a.sortOrder.compareTo(b.sortOrder);
        });
    final amount = _amount ?? 0;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.expenseTitle)),
      body: ListView(
        padding: EdgeInsets.all(t.screenPadding),
        children: [
          if (!canWrite) ...[
            LastTimeBanner(
              text: l10n.expenseReadOnly,
              icon: Icons.lock_outline,
            ),
            SizedBox(height: t.cardGap),
          ],
          AmountInput(
            key: const Key('expense.amount'),
            label: l10n.fieldAmount,
            hint: l10n.amountInputHint,
            onChanged: (p) => setState(() => _amount = p),
          ),
          if (_showErrors && amount <= 0)
            Text(
              l10n.expenseAmountRequired,
              style: text.bodySmall!.copyWith(color: t.danger),
            ),
          SizedBox(height: t.cardGap),
          Text(l10n.fieldCategory, style: text.bodySmall),
          Wrap(
            spacing: 8,
            children: [
              for (final c in categories)
                ChoiceChipX(
                  key: Key('expense.category.${c.code}'),
                  label: localName(
                    settings,
                    c.nameMl.value,
                    c.nameEn.value,
                    l10n.nameMixed,
                  ),
                  selected: _category == c.code,
                  onSelected: (_) => setState(() => _category = c.code),
                ),
            ],
          ),
          if (_showErrors && _category == null)
            Text(
              l10n.expenseCategoryRequired,
              style: text.bodySmall!.copyWith(color: t.danger),
            ),
          SizedBox(height: t.cardGap),
          Row(
            children: [
              Expanded(child: Text(l10n.expenseDate, style: text.bodySmall)),
              TextButton.icon(
                key: const Key('expense.day'),
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
            }),
          ),
          SizedBox(height: t.cardGap),
          if (plot != null && cycles.isEmpty)
            Text(l10n.expenseNoCrops, style: text.bodySmall)
          else if (cycles.length > 1)
            CropSplit(
              cycles: cycles,
              parts: _parts(amount, cycles),
              editing: _editSplit,
              onToggleEdit: () => setState(() => _editSplit = !_editSplit),
              onPart: (i, p) => setState(() {
                _fixed.remove(i);
                _fixed[i] = p;
              }),
              mode: _splitMode,
              onMode: (m) => setState(() {
                _splitMode = m;
                _fixed.clear();
              }),
            ),
          SizedBox(height: t.cardGap),
          Text(l10n.fieldPaymentMode, style: text.bodySmall),
          Wrap(
            spacing: 8,
            children: [
              for (final (code, label) in [
                ('cash', l10n.paymentCash),
                ('upi', l10n.paymentUpi),
                ('bank', l10n.paymentBank),
                ('credit', l10n.paymentCredit),
              ])
                ChoiceChipX(
                  key: Key('expense.mode.$code'),
                  label: label,
                  selected: _mode == code,
                  onSelected: (_) => setState(() => _mode = code),
                ),
            ],
          ),
          if (_mode == 'credit') ...[
            Text(l10n.expenseCreditHint, style: text.bodySmall),
            TextField(
              key: const Key('expense.vendor'),
              controller: _vendor,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: l10n.expenseVendor),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(t.screenPadding),
          child: PrimaryButton(
            key: const Key('expense.save'),
            label: l10n.actionSave,
            onPressed: !canWrite || _saving || plot == null
                ? null
                : () => _save(plot),
          ),
        ),
      ),
    );
  }
}
