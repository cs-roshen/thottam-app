import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/date_format.dart';
import '../../../app/router.dart';
import '../../../app/session.dart';
import '../../../app/settings.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/widgets/widgets.dart';
import '../../../core/access/access.dart';
import '../../../core/money/money_format.dart';
import '../../../l10n/app_localizations.dart';
import '../../labour/data/labour_providers.dart';
import '../../labour/data/labour_repository.dart';
import '../../land/data/land_providers.dart';
import '../../land/domain/land.dart';
import '../../land/ui/land_labels.dart';
import '../../money/data/money_providers.dart';
import '../../money/domain/profit.dart';
import '../data/home_providers.dart';
import '../data/home_repository.dart';

/// Screen 2: the date in both calendars, a greeting, and the cards the
/// farmer keeps switched on. Each card watches only its own data. Weather
/// waits for a data source (implementation plan, C9).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final hidden = ref.watch(settingsProvider.select((s) => s.hiddenCards));
    final canSeeMoney = ref.watch(canSeeMoneyProvider);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(t.screenPadding),
          children: [
            const _Header(),
            for (final (card, widget) in [
              if (canSeeMoney) ('profit', const _ProfitCard()),
              ('price', const _PriceCard()),
              ('tasks', const _TasksCard()),
              if (canSeeMoney) ('dues', const _DuesCard()),
            ])
              if (!hidden.contains(card)) widget,
          ],
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final name = ref.watch(sessionProvider).account?.name ?? '';
    final settings = ref.watch(settingsProvider.notifier);
    final language = ref.watch(settingsProvider.select((s) => s.language));
    Widget round({
      required Key key,
      required String label,
      required VoidCallback onTap,
      required Widget child,
    }) => Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        shape: CircleBorder(side: BorderSide(color: t.line)),
        color: t.surface,
        child: InkWell(
          key: key,
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(
            dimension: t.minTouch,
            child: Center(child: child),
          ),
        ),
      ),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: t.cardGap),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatHomeDate(ref.watch(clockProvider)(), l10n),
                  key: const Key('home.date'),
                  style: text.bodySmall,
                ),
                Text(
                  name.trim().isEmpty
                      ? l10n.navHome
                      : l10n.homeGreeting(name.trim().split(' ').first),
                  style: text.headlineMedium,
                ),
              ],
            ),
          ),
          round(
            key: const Key('home.language'),
            label: l10n.homeLanguageSwitch,
            onTap: () => settings.setLanguage(
              language == LanguageChoice.english
                  ? LanguageChoice.malayalam
                  : LanguageChoice.english,
            ),
            child: Text(
              l10n.homeLanguageBadge,
              style: text.bodyLarge!.copyWith(color: t.primary),
            ),
          ),
          const SizedBox(width: 8),
          round(
            key: const Key('home.settings'),
            label: l10n.settingsTitle,
            // shortcut: More until Settings has its own screen (C10)
            onTap: () => context.go('/more'),
            child: Icon(Icons.tune, color: t.ink),
          ),
        ],
      ),
    );
  }
}

/// A card with the gap below it, so a hidden card leaves no gap.
class _Gap extends StatelessWidget {
  const _Gap({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: context.tokens.cardGap),
    child: child,
  );
}

class _ProfitCard extends ConsumerWidget {
  const _ProfitCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final (from, to) = financialYear(ref.watch(clockProvider)());
    final rows = ref
        .watch(cycleMoneyProvider((from: from, to: to, plot: '')))
        .value;
    final p = profitByCrop(
      [for (final r in rows ?? const <Never>[]) r.money],
      (_) => null,
      includeFamily: false,
    );
    final loss = p.profitPaise < 0;
    Widget tile(String label, int paise, Color bg, Color fg, Key key) =>
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(t.tileRadius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: text.bodySmall!.copyWith(color: fg)),
                Text(formatPaise(paise), key: key, style: text.titleMedium),
              ],
            ),
          ),
        );
    return _Gap(
      child: ThottamCard(
        key: const Key('home.profit'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    loss ? l10n.homeYearLoss : l10n.homeSeasonProfit,
                    style: text.bodyLarge!.copyWith(color: t.muted),
                  ),
                ),
                TextButton(
                  key: const Key('home.profit.details'),
                  onPressed: () => context.go('/money'),
                  child: Text(l10n.actionDetails),
                ),
              ],
            ),
            Text(
              formatPaise(p.profitPaise.abs()),
              key: const Key('home.profit.amount'),
              style: text.displayLarge!.copyWith(
                color: loss ? t.danger : t.primary,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                tile(
                  l10n.moneyIncome,
                  p.incomePaise,
                  t.primaryTint,
                  t.primaryDark,
                  const Key('home.profit.income'),
                ),
                const SizedBox(width: 10),
                tile(
                  l10n.moneyExpense,
                  p.expensePaise,
                  t.expenseTint,
                  t.onExpenseTintStrong,
                  const Key('home.profit.expense'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The latest price of the first of the farm's crops that has one; shown
/// only when a price exists.
class _PriceCard extends ConsumerWidget {
  const _PriceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);
    final crops = {
      for (final p in ref.watch(plotsProvider).value ?? const <PlotView>[])
        for (final c in p.cycles) c.cropId: c,
    };
    final prices =
        ref.watch(cropPricesProvider(crops.keys.join(','))).value ?? const {};
    final crop = crops.values.where((c) => prices.containsKey(c.cropId));
    if (crop.isEmpty) return const SizedBox.shrink();
    final (paise, unit, at) = prices[crop.first.cropId]!;
    final now = ref.watch(clockProvider)();
    final published = DateTime.fromMillisecondsSinceEpoch(at);
    final stale = now.difference(published) > const Duration(days: 1);
    return _Gap(
      child: ThottamCard(
        key: const Key('home.price'),
        onTap: () => context.push('/prices'),
        child: Row(
          children: [
            TintIconTile(
              icon: Icons.show_chart,
              background: t.accentTint,
              foreground: t.onAccentTint,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${l10n.homeCardPrice} · ${l10n.cropName(settings, crop.first)}',
                    style: text.bodySmall,
                  ),
                  Text(
                    l10n.ratePerUnit(formatPaise(paise), unit),
                    style: text.titleMedium,
                  ),
                  if (stale)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: StaleDataTag(
                        label: l10n.staleDataTag(
                          formatDay(isoDay(published), l10n, now),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: t.muted),
          ],
        ),
      ),
    );
  }
}

class _TasksCard extends ConsumerWidget {
  const _TasksCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);
    final tasks = ref.watch(todayTasksProvider).value ?? const <TaskView>[];
    final canWrite =
        ref.watch(accessProvider).value?.canWrite(AccessClass.daily) ?? false;
    final now = ref.watch(clockProvider)();
    final today = isoDay(now);
    final done = tasks.where((x) => x.done).length;
    Future<void> tick(TaskView task, bool on) async {
      final repo = ref.read(homeRepositoryProvider);
      final events = await repo.setDone(
        task,
        on,
        ref.read(clockProvider)().millisecondsSinceEpoch,
      );
      if (context.mounted) {
        showUndoToast(context, l10n.toastSaved, () => repo.undo(events));
      }
    }

    return _Gap(
      child: ThottamCard(
        key: const Key('home.tasks'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              children: [
                Text(l10n.homeCardTasks, style: text.titleMedium),
                if (done > 0)
                  Text(l10n.homeTasksDone(done), style: text.bodySmall),
              ],
            ),
            if (tasks.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(l10n.homeNoTasks, style: text.bodySmall),
              ),
            for (final task in tasks)
              CheckboxListTile(
                key: Key('task.${task.id}'),
                value: task.done,
                onChanged: canWrite ? (v) => tick(task, v ?? false) : null,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  task.title,
                  style: text.bodyLarge!.copyWith(
                    color: task.done ? t.muted : t.ink,
                    decoration: task.done ? TextDecoration.lineThrough : null,
                  ),
                ),
                subtitle: switch ([
                  if (task.dueOn != today)
                    l10n.homeTaskDue(formatDay(task.dueOn, l10n, now)),
                  if (task.cropMl != null && task.cropEn != null)
                    localName(
                      settings,
                      task.cropMl!,
                      task.cropEn!,
                      l10n.nameMixed,
                    ),
                  ?task.plot,
                ]) {
                  final parts when parts.isNotEmpty => Text(
                    parts.join(' · '),
                    style: text.bodySmall,
                  ),
                  _ => null,
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Wages owed to workers and groups, with a way to pay; shown only when
/// something is owed.
class _DuesCard extends ConsumerWidget {
  const _DuesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final owed = [
      for (final w in ref.watch(workersProvider).value ?? const <WorkerView>[])
        if (!w.isFamily && w.balancePaise > 0) w.balancePaise,
      for (final g in ref.watch(groupsProvider).value ?? const <GroupView>[])
        if (g.balancePaise > 0) g.balancePaise,
    ];
    if (owed.isEmpty) return const SizedBox.shrink();
    return _Gap(
      child: Container(
        key: const Key('home.dues'),
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        decoration: BoxDecoration(
          color: t.noticeBg,
          border: Border.all(color: t.noticeLine),
          borderRadius: BorderRadius.circular(t.tileRadius),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                l10n.homeDuesSummary(
                  formatPaise(owed.fold(0, (s, p) => s + p)),
                  owed.length,
                ),
                style: text.bodyMedium,
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              key: const Key('home.dues.pay'),
              // the theme's buttons are full width; this one sits in a row
              style: FilledButton.styleFrom(
                minimumSize: Size(t.minTouch, t.minTouch),
              ),
              onPressed: () => context.push('/labour/team'),
              child: Text(l10n.actionPay),
            ),
          ],
        ),
      ),
    );
  }
}
