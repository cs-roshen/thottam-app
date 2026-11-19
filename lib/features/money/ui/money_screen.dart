import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/session.dart';
import '../../../app/settings.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/widgets/widgets.dart';
import '../../../core/money/money_format.dart';
import '../../../l10n/app_localizations.dart';
import '../../land/data/land_providers.dart';
import '../data/money_providers.dart';
import '../domain/profit.dart';

/// Screen 5: profit, income and expense for a financial year, by crop, with
/// family labour left out unless switched in, and a report to share.
class MoneyScreen extends ConsumerStatefulWidget {
  const MoneyScreen({super.key});

  @override
  ConsumerState<MoneyScreen> createState() => _MoneyScreenState();
}

class _MoneyScreenState extends ConsumerState<MoneyScreen> {
  bool _lastYear = false;
  String _plot = '';
  bool _family = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);
    final today = ref.watch(clockProvider)();
    final (from, to) = financialYear(
      _lastYear ? DateTime(today.year - 1, today.month, today.day) : today,
    );
    final plots = ref.watch(plotsProvider).value ?? const [];
    final plotName = [
      for (final p in plots)
        if (p.id == _plot) p.name,
    ].firstOrNull;
    final rows = ref
        .watch(cycleMoneyProvider((from: from, to: to, plot: _plot)))
        .value;

    final names = {
      for (final r in rows ?? const <Never>[])
        if (r.crop != null)
          r.crop: localName(settings, r.nameMl!, r.nameEn!, l10n.nameMixed),
    };
    final cropOf = {
      for (final r in rows ?? const <Never>[]) r.money.cycleId: r.crop,
    };
    final p = profitByCrop(
      [for (final r in rows ?? const <Never>[]) r.money],
      (c) => cropOf[c],
      includeFamily: _family,
    );
    final most = [
      1,
      for (final r in p.rows) ...[r.incomePaise, r.expensePaise],
    ].reduce(max);
    String name(String? crop) => crop == null ? l10n.moneyNoCrop : names[crop]!;
    final scope = [
      l10n.moneyYearRange(from.substring(0, 4), to.substring(0, 4)),
      plotName ?? l10n.moneyAllPlots,
    ].join(' · ');

    return Scaffold(
      appBar: AppBar(title: Text(l10n.moneyTitle)),
      body: ListView(
        padding: EdgeInsets.all(t.screenPadding),
        children: [
          Text(scope, key: const Key('money.scope'), style: text.bodySmall),
          SizedBox(height: t.cardGap),
          SegmentedControl(
            key: const Key('money.period'),
            labels: [l10n.moneyThisYear, l10n.moneyLastYear],
            selected: _lastYear ? 1 : 0,
            onChanged: (i) => setState(() => _lastYear = i == 1),
          ),
          if (plots.length > 1) ...[
            SizedBox(height: t.cardGap),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (id, label) in [
                  ('', l10n.moneyAllPlots),
                  for (final p in plots) (p.id, p.name),
                ])
                  ChoiceChipX(
                    key: Key('money.plot.$id'),
                    label: label,
                    selected: _plot == id,
                    onSelected: (_) => setState(() => _plot = id),
                  ),
              ],
            ),
          ],
          SizedBox(height: t.cardGap),
          _Totals(p),
          SizedBox(height: t.cardGap),
          ThottamCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.moneyByCrop, style: text.titleMedium),
                if (rows != null && p.rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(l10n.moneyEmpty, style: text.bodySmall),
                  ),
                for (final r in p.rows) ...[
                  const SizedBox(height: 16),
                  _CropRow(row: r, name: name(r.key), most: most),
                ],
              ],
            ),
          ),
          SizedBox(height: t.cardGap),
          Material(
            color: t.surface,
            borderRadius: BorderRadius.circular(t.cardRadius),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: t.cardPadding),
              child: SwitchRow(
                key: const Key('money.family'),
                title: l10n.moneyIncludeFamilyLabour,
                subtitle: l10n.moneyFamilyLabourValue(
                  formatPaise(p.familyPaise),
                ),
                value: _family,
                onChanged: (v) => setState(() => _family = v),
              ),
            ),
          ),
          SizedBox(height: t.cardGap),
          PrimaryButton(
            key: const Key('money.share'),
            label: l10n.moneyShareReport,
            icon: Icons.ios_share,
            onPressed: rows == null
                ? null
                : () async {
                    // shortcut: copies the report as text for any chat app;
                    // a share sheet and PDF wait on the owner's choice of
                    // export packages (D4)
                    await Clipboard.setData(
                      ClipboardData(
                        text: profitReport(l10n, p, scope, name, _family),
                      ),
                    );
                    if (context.mounted) {
                      showToast(context, l10n.moneyReportCopied);
                    }
                  },
          ),
        ],
      ),
    );
  }
}

/// The report as text, one line each: title, scope, totals, crops, family.
String profitReport(
  AppLocalizations l10n,
  ProfitAndLoss p,
  String scope,
  String Function(String? crop) name,
  bool family,
) => [
  l10n.moneyTitle,
  scope,
  '${l10n.moneyIncome} ${formatPaise(p.incomePaise)}',
  '${l10n.moneyExpense} ${formatPaise(p.expensePaise)}',
  '${_profitWord(l10n, p.profitPaise)} ${formatPaise(p.profitPaise.abs())}',
  '',
  for (final r in p.rows)
    l10n.moneyReportCrop(
      name(r.key),
      formatPaise(r.incomePaise),
      formatPaise(r.expensePaise),
      formatPaise(r.profitPaise),
    ),
  '',
  (family ? l10n.moneyFamilyIncluded : l10n.moneyFamilyLeftOut)(
    formatPaise(p.familyPaise),
  ),
].join('\n');

String _profitWord(AppLocalizations l10n, int paise) =>
    paise < 0 ? l10n.moneyLoss : l10n.moneyProfit;

class _Totals extends StatelessWidget {
  const _Totals(this.p);

  final ProfitAndLoss p;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final on = text.bodyLarge!.copyWith(color: t.onPrimary);
    return Container(
      key: const Key('money.totals'),
      padding: EdgeInsets.all(t.cardPadding),
      decoration: BoxDecoration(
        color: t.primaryDark,
        borderRadius: BorderRadius.circular(t.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _profitWord(l10n, p.profitPaise),
            style: text.bodySmall!.copyWith(color: t.primaryPill),
          ),
          const SizedBox(height: 4),
          Text(
            formatPaise(p.profitPaise.abs()),
            key: const Key('money.profit'),
            style: text.displayLarge!.copyWith(color: t.accent),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 20,
            runSpacing: 4,
            children: [
              Text(
                '${l10n.moneyIncome} ${formatPaise(p.incomePaise)}',
                key: const Key('money.income'),
                style: on,
              ),
              Text(
                '${l10n.moneyExpense} ${formatPaise(p.expensePaise)}',
                key: const Key('money.expense'),
                style: on,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CropRow extends StatelessWidget {
  const _CropRow({required this.row, required this.name, required this.most});

  final ProfitRow row;
  final String name;

  /// The largest income or expense of any row, the bars' full width.
  final int most;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final loss = row.profitPaise < 0;
    Widget bar(int paise, Color colour) => ExcludeSemantics(
      child: Container(
        height: 10,
        decoration: BoxDecoration(
          color: t.lineSoft,
          borderRadius: BorderRadius.circular(5),
        ),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: (paise / most).clamp(0, 1),
          child: Container(
            decoration: BoxDecoration(
              color: colour,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ),
      ),
    );
    return Column(
      key: Key('money.crop.${row.key}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          children: [
            Text(name, style: text.titleSmall),
            Text(
              loss
                  ? '${l10n.moneyLoss} ${formatPaise(-row.profitPaise)}'
                  : formatPaise(row.profitPaise),
              style: text.titleSmall!.copyWith(
                color: loss ? t.danger : t.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        bar(row.incomePaise, t.primary),
        const SizedBox(height: 4),
        bar(row.expensePaise, t.expense),
        const SizedBox(height: 6),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          children: [
            Text(
              '${l10n.moneyIncome} ${formatPaise(row.incomePaise)}',
              style: text.bodySmall,
            ),
            Text(
              '${l10n.moneyExpense} ${formatPaise(row.expensePaise)}',
              style: text.bodySmall,
            ),
          ],
        ),
      ],
    );
  }
}
