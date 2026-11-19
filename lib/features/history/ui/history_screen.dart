import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/date_format.dart';
import '../../../app/session.dart';
import '../../../app/settings.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/widgets/widgets.dart';
import '../../../core/access/access.dart';
import '../../../core/money/money_format.dart';
import '../../../l10n/app_localizations.dart';
import '../data/history_providers.dart';
import '../data/history_repository.dart';
import '../domain/history.dart';

/// Screen 15: the farm diary by day, with filters and "this week last
/// year"; with [entity] and [entityId], one record's timeline. Every row
/// opens its old → new values and can put the record back.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key, this.plotId, this.entity, this.entityId});

  final String? plotId;
  final String? entity;
  final String? entityId;

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  HistoryFilter _filter = HistoryFilter.all;
  int _limit = 50;

  bool get _record => widget.entity != null && widget.entityId != null;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final access = ref.watch(accessProvider).value ?? Access.none;
    final entities = asParam(entitiesFor(_filter, access));
    final events = _record
        ? ref
                  .watch(
                    recordHistoryProvider((widget.entity!, widget.entityId!)),
                  )
                  .value ??
              const <HistoryEvent>[]
        : ref
                  .watch(
                    diaryProvider((
                      entities: entities,
                      actions: asParam(actionsFor(_filter)),
                      plot: widget.plotId ?? '',
                      limit: _limit,
                    )),
                  )
                  .value ??
              const <HistoryEvent>[];
    final today = ref.watch(clockProvider)();
    final more = !_record && events.length >= _limit;

    final header = <Widget>[
      if (!_record && widget.plotId == null)
        _LastYearCard(
          entities: asParam(entitiesFor(HistoryFilter.all, access)),
        ),
      if (!_record) ...[
        SizedBox(height: t.cardGap),
        Wrap(
          spacing: 8,
          children: [
            for (final (f, label) in [
              (HistoryFilter.all, l10n.historyFilterAll),
              (HistoryFilter.labour, l10n.historyFilterLabour),
              if (access.canRead(AccessClass.money)) ...[
                (HistoryFilter.expense, l10n.historyFilterExpense),
              ],
              (HistoryFilter.harvest, l10n.historyFilterHarvest),
              if (access.canRead(AccessClass.money))
                (HistoryFilter.sales, l10n.historyFilterSales),
              (HistoryFilter.edits, l10n.historyFilterEdits),
            ])
              ChoiceChipX(
                key: Key('history.filter.${f.name}'),
                label: label,
                selected: _filter == f,
                onSelected: (_) => setState(() {
                  _filter = f;
                  _limit = 50;
                }),
              ),
          ],
        ),
      ],
      if (events.isEmpty)
        Padding(
          padding: EdgeInsets.only(top: t.cardGap * 2),
          child: Text(l10n.historyEmpty, style: text.bodyMedium),
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_record ? l10n.historyRecordTitle : l10n.historyTitle),
      ),
      body: ListView.builder(
        padding: EdgeInsets.all(t.screenPadding),
        itemCount: header.length + events.length + 1,
        itemBuilder: (context, i) {
          if (i < header.length) return header[i];
          final k = i - header.length;
          if (k == events.length) {
            if (more) {
              // the next page, after the last row shown
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && events.length >= _limit) {
                  setState(() => _limit += 50);
                }
              });
              return const SizedBox(height: 48);
            }
            return events.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: EdgeInsets.all(t.cardGap),
                    child: Text(
                      l10n.historyAllLoaded,
                      textAlign: TextAlign.center,
                      style: text.bodySmall,
                    ),
                  );
          }
          final e = events[k];
          final newDay = k == 0 || events[k - 1].day != e.day;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (newDay)
                Padding(
                  padding: EdgeInsets.only(top: t.cardGap, bottom: 6),
                  child: Text(
                    formatDay(e.day, l10n, today),
                    style: text.titleMedium,
                  ),
                ),
              EventTile(event: e),
            ],
          );
        },
      ),
    );
  }
}

class _LastYearCard extends ConsumerWidget {
  const _LastYearCard({required this.entities});

  final String entities;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final (from, to) = weekLastYear(ref.watch(clockProvider)());
    return FutureBuilder<int>(
      future: ref
          .watch(historyRepositoryProvider)
          .countBetween(from, to, entities),
      builder: (context, snap) => Container(
        key: const Key('history.lastYear'),
        padding: EdgeInsets.all(t.cardPadding),
        decoration: BoxDecoration(
          color: t.primaryDark,
          borderRadius: BorderRadius.circular(t.cardRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.historyLastYear,
              style: text.bodySmall!.copyWith(color: t.accent),
            ),
            Text(
              l10n.historyLastYearCount(snap.data ?? 0),
              style: text.titleMedium!.copyWith(color: t.onPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Words for a history row, shared by the diary and the plot screen.
extension HistoryLabels on AppLocalizations {
  /// The names a row is about: crop, plot, worker, group or party.
  String eventContext(AppSettings settings, Map<String, Object?> s) {
    final crop = s['crop_ml'] is String && s['crop_en'] is String
        ? localName(
            settings,
            s['crop_ml']! as String,
            s['crop_en']! as String,
            nameMixed,
          )
        : null;
    return [
      // a note's or task's own words
      if (s['text'] case final String t) t,
      ?crop,
      if (s['plot'] case final String p) p,
      if (s['worker'] case final String w) w,
      if (s['group'] case final String g when g.isNotEmpty) g,
      if (s['party'] case final String p) p,
      if (s['farm'] case final String f) f,
    ].join(' · ');
  }

  String fieldValue(String field, Object? v) {
    if (v == null) return '—';
    if (field.endsWith('_paise') && v is int) return formatPaise(v);
    if (const {'quantity', 'area', 'area_share'}.contains(field) && v is int) {
      return formatQuantity(v);
    }
    return '$v';
  }
}

class EventTile extends ConsumerWidget {
  const EventTile({super.key, required this.event});

  final HistoryEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);
    final e = event;
    final amount = signedAmount(e.entity, e.summary);
    final edit = e.action != 'create';
    final (icon, bg, fg) = switch (e.entity) {
      'expenses' || 'expense_payments' => (
        Icons.payments_outlined,
        t.expenseTint,
        t.onExpenseTint,
      ),
      'labour_entries' ||
      'labour_payments' ||
      'workers' ||
      'labour_groups' => (Icons.groups_outlined, t.infoTint, t.onInfoTint),
      'harvests' ||
      'lot_costs' => (Icons.agriculture_outlined, t.primaryTint, t.primaryDark),
      'sales' ||
      'sale_payments' ||
      'parties' => (Icons.sell_outlined, t.accentTint, t.onAccentTint),
      _ => (Icons.edit_note_outlined, t.lineSoft, t.ink),
    };
    final context0 = l10n.eventContext(settings, e.summary);
    final amountText = amount == null
        ? null
        : Text(
            amount < 0
                ? '− ${formatPaise(-amount)}'
                : '+ ${formatPaise(amount)}',
            style: text.bodyLarge!.copyWith(
              color: amount < 0 ? t.onExpenseTint : t.primary,
            ),
          );
    // at large text the amount goes under the title, so neither squeezes
    final stacked = MediaQuery.textScalerOf(context).scale(10) > 13;
    return InkWell(
      key: Key('event.${e.id}'),
      borderRadius: BorderRadius.circular(t.tileRadius),
      onTap: () => showThottamSheet<void>(
        context,
        builder: (_) => _EventDetail(event: e),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: t.listRowMin),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              TintIconTile(
                icon: icon,
                background: bg,
                foreground: fg,
                size: t.tintTileSmall,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.historyEvent(e.entity, e.action),
                      style: text.bodyLarge,
                    ),
                    if (context0.isNotEmpty)
                      Text(context0, style: text.bodySmall),
                    if (edit)
                      Text(
                        l10n.historyEditedBy(
                          e.createdBy == ref.watch(userIdProvider)
                              ? l10n.historyByYou
                              : l10n.historyByMember,
                        ),
                        style: text.bodySmall,
                      ),
                    if (stacked) ?amountText,
                  ],
                ),
              ),
              if (!stacked) ?amountText,
            ],
          ),
        ),
      ),
    );
  }
}

class _EventDetail extends ConsumerWidget {
  const _EventDetail({required this.event});

  final HistoryEvent event;

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(historyRepositoryProvider);
    if (await repo.changedSince(event)) {
      if (!context.mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.historyRestoreWarnTitle),
          content: Text(l10n.historyRestoreWarnBody),
          actions: [
            TextButton(
              key: const Key('restore.cancel'),
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.actionCancel),
            ),
            TextButton(
              key: const Key('restore.confirm'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.historyRestore),
            ),
          ],
        ),
      );
      if (go != true) return;
    }
    final events = await repo.restore(event);
    if (!context.mounted) return;
    Navigator.pop(context);
    showUndoToast(context, l10n.historyRestored, () => repo.undo(events));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);
    final e = event;
    final access = ref.watch(accessProvider).value ?? Access.none;
    final canRestore =
        e.action != 'create' &&
        access.canWrite(tableAccess[e.entity] ?? AccessClass.setup);
    final lines = e.action == 'update' || e.action == 'restore'
        ? changes(e.oldValues, e.newValues)
        : const <(String, Object?, Object?)>[];
    final when = DateFormat(
      // gate: not user-facing
      'd MMM y, h:mm a',
      l10n.localeName,
    ).format(DateTime.fromMillisecondsSinceEpoch(e.createdAt));
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.historyEvent(e.entity, e.action), style: text.titleLarge),
          Text(
            [
              l10n.eventContext(settings, e.summary),
              when,
            ].where((x) => x.isNotEmpty).join(' · '),
            style: text.bodySmall,
          ),
          for (final (field, from, to) in lines)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.historyEditChange(
                  l10n.historyField(field),
                  l10n.fieldValue(field, from),
                  l10n.fieldValue(field, to),
                ),
                style: text.bodyMedium,
              ),
            ),
          SizedBox(height: t.cardGap),
          if (canRestore)
            PrimaryButton(
              key: const Key('event.restore'),
              label: l10n.historyRestore,
              icon: Icons.restore,
              onPressed: () => _restore(context, ref),
            ),
          const SizedBox(height: 10),
          OutlineButton(
            key: const Key('event.timeline'),
            label: l10n.historyTimeline,
            onPressed: () {
              Navigator.pop(context);
              context.push('/history/${e.entity}/${e.entityId}');
            },
          ),
        ],
      ),
    );
  }
}
