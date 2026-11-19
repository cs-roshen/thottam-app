import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/date_format.dart';
import '../../../app/session.dart';
import '../../../app/settings.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/widgets/widgets.dart';
import '../../../core/access/access.dart';
import '../../../core/money/money_format.dart';
import '../../../core/overrides/overrides.dart';
import '../../../l10n/app_localizations.dart';
import '../data/land_providers.dart';
import '../data/land_repository.dart';
import '../domain/land.dart';
import 'land_labels.dart';

enum _Tab { crops, costs, history }

/// Screen 18: a plot's stats, its crops, costs by category and recent
/// history, with quick buttons to add an expense or a harvest here.
class PlotDetailScreen extends ConsumerStatefulWidget {
  const PlotDetailScreen({super.key, required this.plotId});

  final String plotId;

  @override
  ConsumerState<PlotDetailScreen> createState() => _PlotDetailScreenState();
}

class _PlotDetailScreenState extends ConsumerState<PlotDetailScreen> {
  _Tab _tab = _Tab.crops;

  /// Asks first, saying how many entries sit under it; they all stay.
  Future<bool> _confirmDelete(String title, int entries) async {
    final l10n = AppLocalizations.of(context);
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(l10n.deleteKeepsEntries(entries)),
            actions: [
              TextButton(
                key: const Key('delete.cancel'),
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.actionCancel),
              ),
              TextButton(
                key: const Key('delete.confirm'),
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.actionDelete),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _deletePlot(PlotView plot) async {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(landRepositoryProvider);
    final entries = await repo.entryCount(plotId: plot.id);
    if (!mounted ||
        !await _confirmDelete(l10n.plotDeleteTitle(plot.name), entries)) {
      return;
    }
    final events = await repo.deletePlot(plot.id);
    if (!mounted) return;
    showUndoToast(context, l10n.plotDeleted, () => repo.undo(events));
    context.go('/land');
  }

  Future<void> _cycleAction(CycleView c, String action) async {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(landRepositoryProvider);
    switch (action) {
      case 'edit':
        context.go('/land/${widget.plotId}/crop/${c.id}');
      case 'close' || 'reopen':
        final events = await repo.setCycleClosed(c, closed: action == 'close');
        if (mounted && action == 'close') {
          showUndoToast(
            context,
            l10n.cycleSeasonClosed,
            () => repo.undo(events),
          );
        }
      case 'delete':
        final entries = await repo.entryCount(cycleId: c.id);
        final settings = ref.read(settingsProvider);
        if (!mounted ||
            !await _confirmDelete(
              l10n.cycleDeleteTitle(l10n.cropName(settings, c)),
              entries,
            )) {
          return;
        }
        final events = await repo.deleteCycle(c);
        if (mounted) {
          showUndoToast(context, l10n.cycleDeleted, () => repo.undo(events));
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final plot = ref.watch(plotProvider(widget.plotId)).value;
    final canWrite = ref.watch(canWriteLandProvider);
    final access = ref.watch(accessProvider).value ?? Access.none;
    if (plot == null) {
      return Scaffold(appBar: AppBar());
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(plot.name),
        actions: [
          if (canWrite)
            PopupMenuButton<String>(
              key: const Key('plot.menu'),
              tooltip: l10n.actionMore,
              onSelected: (v) => v == 'edit'
                  ? context.go('/land/${plot.id}/edit')
                  : _deletePlot(plot),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'edit', child: Text(l10n.actionEdit)),
                PopupMenuItem(
                  key: const Key('plot.delete'),
                  value: 'delete',
                  child: Text(l10n.plotDelete),
                ),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.all(t.screenPadding),
        children: [
          Text(
            plot.mixed
                ? l10n.nameWithDetail(
                    l10n.plotLine(plot),
                    l10n.landMixedCropTag,
                  )
                : l10n.plotLine(plot),
            style: text.bodySmall,
          ),
          SizedBox(height: t.cardGap),
          _Stats(plot: plot, showMoney: access.canRead(AccessClass.money)),
          SizedBox(height: t.cardGap),
          SegmentedControl(
            key: const Key('plot.tabs'),
            labels: [l10n.plotTabCrops, l10n.plotTabCosts, l10n.plotTabHistory],
            selected: _tab.index,
            onChanged: (i) => setState(() => _tab = _Tab.values[i]),
          ),
          SizedBox(height: t.cardGap),
          switch (_tab) {
            _Tab.crops => _CropsTab(
              plot: plot,
              canWrite: canWrite,
              showMoney: access.canRead(AccessClass.money),
              onAction: _cycleAction,
            ),
            _Tab.costs => _CostsTab(plotId: plot.id),
            _Tab.history => _HistoryTab(plotId: plot.id),
          },
          if (!canWrite) ...[
            SizedBox(height: t.cardGap),
            LastTimeBanner(text: l10n.landReadOnly, icon: Icons.lock_outline),
          ],
          SizedBox(height: t.cardGap),
          Row(
            children: [
              if (access.canWrite(AccessClass.money))
                Expanded(
                  child: OutlineButton(
                    key: const Key('plot.addExpense'),
                    label: l10n.quickAddExpense,
                    icon: Icons.add,
                    onPressed: () =>
                        context.push('/add/expense?plot=${plot.id}'),
                  ),
                ),
              if (access.canWrite(AccessClass.money) &&
                  access.canWrite(AccessClass.daily))
                const SizedBox(width: 10),
              if (access.canWrite(AccessClass.daily))
                Expanded(
                  child: OutlineButton(
                    key: const Key('plot.addHarvest'),
                    label: l10n.quickAddHarvest,
                    icon: Icons.add,
                    onPressed: () =>
                        context.push('/add/harvest?plot=${plot.id}'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stats extends ConsumerWidget {
  const _Stats({required this.plot, required this.showMoney});

  final PlotView plot;
  final bool showMoney;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final current = [
      for (final c in plot.cycles)
        if (!c.closed) c,
    ];
    final totals = ref.watch(cycleTotalsProvider(plot.id)).value ?? const [];
    final season = plotTotals(plot.id, [
      for (final c in totals)
        if (current.any((x) => x.id == c.cycleId)) c,
    ]);
    final prices =
        ref
            .watch(cropPricesProvider(current.map((c) => c.cropId).join(',')))
            .value ??
        const {};
    // the first crop with a price stands for the plot
    final priced = current.where((c) => prices.containsKey(c.cropId));
    final price = priced.isEmpty ? null : prices[priced.first.cropId];
    final tiles = [
      (l10n.plotCrops, '${current.length}', null),
      if (showMoney) (l10n.plotSeasonCost, formatPaise(season.costPaise), null),
      (
        l10n.plotYield,
        season.yields.isEmpty
            ? '—'
            : season.yields.length == 1
            ? l10n.yields(season.yields)
            : l10n.plotPerCrop,
        null,
      ),
      (
        l10n.homeCardPrice,
        price == null ? '—' : l10n.ratePerUnit(formatPaise(price.$1), price.$2),
        priced.isEmpty ? null : l10n.cropName(settings, priced.first),
      ),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 10.0;
        final width = (box.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final (label, value, note) in tiles)
              SizedBox(
                width: width,
                child: _StatTile(label: label, value: value, note: note),
              ),
          ],
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, this.note});

  final String label;
  final String value;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(t.buttonRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.bodySmall),
          Text(value, style: text.titleLarge),
          if (note != null) Text(note!, style: text.bodySmall),
        ],
      ),
    );
  }
}

class _CropsTab extends ConsumerWidget {
  const _CropsTab({
    required this.plot,
    required this.canWrite,
    required this.showMoney,
    required this.onAction,
  });

  final PlotView plot;
  final bool canWrite;
  final bool showMoney;
  final void Function(CycleView c, String action) onAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final totals = <String, CycleTotals>{
      for (final c
          in ref.watch(cycleTotalsProvider(plot.id)).value ??
              const <CycleTotals>[])
        c.cycleId: c,
    };
    final current = plot.cycles.where((c) => !c.closed).toList();
    final past = plot.cycles.where((c) => c.closed).toList();
    Widget row(CycleView c) => _CycleRow(
      cycle: c,
      totals: totals[c.id],
      canWrite: canWrite,
      showMoney: showMoney,
      onAction: (a) => onAction(c, a),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (current.isEmpty)
          Text(l10n.plotNoCrops, style: text.bodyMedium)
        else
          ThottamCard(
            child: Column(children: [for (final c in current) row(c)]),
          ),
        if (canWrite) ...[
          SizedBox(height: t.cardGap),
          OutlineButton(
            key: const Key('plot.addCrop'),
            label: l10n.plotAddCrop,
            icon: Icons.add,
            onPressed: () => context.go('/land/${plot.id}/crop/new'),
          ),
        ],
        if (past.isNotEmpty) ...[
          SizedBox(height: t.cardGap),
          Text(l10n.plotPastSeasons, style: text.titleMedium),
          const SizedBox(height: 8),
          ThottamCard(child: Column(children: [for (final c in past) row(c)])),
        ],
      ],
    );
  }
}

class _CycleRow extends ConsumerWidget {
  const _CycleRow({
    required this.cycle,
    required this.totals,
    required this.canWrite,
    required this.showMoney,
    required this.onAction,
  });

  final CycleView cycle;
  final CycleTotals? totals;
  final bool canWrite;
  final bool showMoney;
  final void Function(String action) onAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);
    final details = l10n.cycleDetails(cycle);
    final figures = [
      if (showMoney && totals != null)
        l10n.cycleSpent(formatPaise(totals!.costPaise)),
      if (totals != null && totals!.yields.isNotEmpty)
        l10n.cycleHarvested(l10n.yields(totals!.yields)),
    ];
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: t.listRowMin),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            TintIconTile(
              icon: Icons.eco_outlined,
              background: t.primaryTint,
              foreground: t.primary,
              size: t.tintTileSmall,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.cropName(settings, cycle), style: text.bodyLarge),
                  if (details.isNotEmpty) Text(details, style: text.bodySmall),
                  if (figures.isNotEmpty)
                    Text(figures.join(' · '), style: text.bodySmall),
                  if (cycle.closed)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Pill(
                        label: l10n.cycleSeasonClosed,
                        background: t.lineSoft,
                        foreground: t.muted,
                      ),
                    ),
                ],
              ),
            ),
            if (canWrite)
              PopupMenuButton<String>(
                key: Key('cycle.${cycle.id}.menu'),
                tooltip: l10n.actionMore,
                onSelected: onAction,
                itemBuilder: (_) => [
                  if (!cycle.closed)
                    PopupMenuItem(value: 'edit', child: Text(l10n.actionEdit)),
                  PopupMenuItem(
                    key: Key('cycle.${cycle.id}.close'),
                    value: cycle.closed ? 'reopen' : 'close',
                    child: Text(
                      cycle.closed ? l10n.cycleReopen : l10n.cycleCloseSeason,
                    ),
                  ),
                  PopupMenuItem(
                    key: Key('cycle.${cycle.id}.delete'),
                    value: 'delete',
                    child: Text(l10n.actionDelete),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _CostsTab extends ConsumerWidget {
  const _CostsTab({required this.plotId});

  final String plotId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);
    final costs = ref.watch(plotCostsProvider(plotId)).value ?? const [];
    final names = {
      for (final c
          in ref
                  .watch(overridesProvider)
                  .value
                  ?.list('expense_category', const Scope()) ??
              const <ListItem>[])
        c.code: localName(
          settings,
          c.nameMl.value,
          c.nameEn.value,
          l10n.nameMixed,
        ),
    };
    if (costs.isEmpty) return Text(l10n.plotNoCosts, style: text.bodyMedium);
    final total = costs.fold<int>(0, (s, c) => s + c.$2);
    final reduce = MediaQuery.disableAnimationsOf(context);
    return ThottamCard(
      child: Column(
        children: [
          for (final (code, paise) in costs)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          names[code] ?? code,
                          style: text.bodyMedium,
                        ),
                      ),
                      Text(formatPaise(paise), style: text.bodyLarge),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ExcludeSemantics(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: total == 0 ? 0 : paise / total),
                        duration: reduce ? Duration.zero : t.barGrow,
                        curve: t.entryCurve,
                        builder: (context, v, _) => LinearProgressIndicator(
                          value: v,
                          minHeight: 10,
                          color: t.expense,
                          backgroundColor: t.lineSoft,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab({required this.plotId});

  final String plotId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);
    final today = ref.watch(clockProvider)();
    final events = ref.watch(plotHistoryProvider(plotId)).value ?? const [];
    String detail(PlotEvent e) {
      final s = e.summary;
      final crop = s['crop_ml'] is String && s['crop_en'] is String
          ? localName(
              settings,
              s['crop_ml']! as String,
              s['crop_en']! as String,
              l10n.nameMixed,
            )
          : null;
      return [
        formatDay(e.occurredOn, l10n, today),
        crop ?? s['plot'] as String? ?? '',
        if (s['amount_paise'] case final int paise) formatPaise(paise),
      ].where((x) => x.isNotEmpty).join(' · ');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (events.isEmpty)
          Text(l10n.plotNoHistory, style: text.bodyMedium)
        else
          ThottamCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final e in events)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.historyEvent(e.entity, e.action),
                          style: text.bodyLarge,
                        ),
                        Text(detail(e), style: text.bodySmall),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        SizedBox(height: t.cardGap),
        OutlineButton(
          key: const Key('plot.fullHistory'),
          label: l10n.plotFullHistory,
          onPressed: () => context.push('/history?plot=$plotId'),
        ),
      ],
    );
  }
}
