import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/session.dart';
import '../../../app/settings.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/widgets/widgets.dart';
import '../../../core/money/money_format.dart';
import '../../../core/overrides/overrides.dart';
import '../../../l10n/app_localizations.dart';
import '../../land/data/land_providers.dart';
import '../../land/domain/land.dart';
import '../../land/ui/land_labels.dart';
import '../data/prices_providers.dart';
import '../data/prices_repository.dart';
import '../domain/prices.dart';

/// Screen 14: each of the farm's crops with its latest price, change,
/// source and time (marked when older than a day); the chosen crop's 30-day
/// line, markets and alert; and a shop rate entered by hand. Source feeds
/// come after licensing is confirmed (implementation plan, C11).
class PricesScreen extends ConsumerStatefulWidget {
  const PricesScreen({super.key});

  @override
  ConsumerState<PricesScreen> createState() => _PricesScreenState();
}

class _PricesScreenState extends ConsumerState<PricesScreen> {
  String? _crop;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);
    final now = ref.watch(clockProvider)();
    final canWrite = ref.watch(canWritePricesProvider);
    final crops = {
      for (final p in ref.watch(plotsProvider).value ?? const <PlotView>[])
        for (final c in p.cycles) c.cropId: c,
    };
    final data =
        ref.watch(cropPricesListProvider(crops.keys.join(','))).value ??
        const <String, CropPrices>{};
    final selected = _crop ?? crops.keys.firstOrNull;
    final chosen = selected == null ? null : crops[selected];
    final prices = selected == null ? null : data[selected];
    final summary = prices == null ? null : summarize(prices.points, now);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.pricesTitle)),
      body: ListView(
        padding: EdgeInsets.all(t.screenPadding),
        children: [
          Text(l10n.pricesSubtitle, style: text.bodySmall),
          for (final c in crops.values) ...[
            SizedBox(height: t.cardGap),
            _CropRow(
              name: l10n.cropName(settings, c),
              prices: data[c.cropId],
              selected: c.cropId == selected,
              onTap: () => setState(() => _crop = c.cropId),
            ),
          ],
          if (chosen != null) ...[
            SizedBox(height: t.cardGap),
            if (summary == null)
              Text(l10n.pricesEmpty, style: text.bodyMedium)
            else ...[
              ThottamCard(
                key: const Key('prices.chart'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 12,
                      children: [
                        Text(
                          l10n.cropName(settings, chosen),
                          style: text.titleMedium,
                        ),
                        Text(l10n.pricesLast30Days, style: text.bodySmall),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ExcludeSemantics(
                      child: SizedBox(
                        height: 120,
                        child: CustomPaint(
                          painter: _LinePainter(
                            [for (final c in summary.chart) c.paise],
                            t.primary,
                            t.lineSoft,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.pricesRange(
                        formatPaise(summary.low),
                        formatPaise(summary.high),
                      ),
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
              SizedBox(height: t.cardGap),
              ThottamCard(
                key: const Key('prices.markets'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l10n.pricesMarkets, style: text.titleMedium),
                    for (final m in summary.markets)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(m.market, style: text.bodyLarge),
                                  Text(_source(l10n, m), style: text.bodySmall),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              l10n.ratePerUnit(formatPaise(m.paise), m.unit),
                              style: text.bodyLarge,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            SizedBox(height: t.cardGap),
            Material(
              color: t.surface,
              borderRadius: BorderRadius.circular(t.cardRadius),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: t.cardPadding),
                child: SwitchRow(
                  key: const Key('prices.alert'),
                  title: l10n.pricesAlert,
                  subtitle: prices?.alertPaise == null
                      ? l10n.pricesAlertOff
                      : l10n.pricesAlertAbove(formatPaise(prices!.alertPaise!)),
                  value: prices?.alertPaise != null,
                  onChanged: !canWrite
                      ? null
                      : (on) => _setAlert(selected!, on, summary),
                ),
              ),
            ),
          ],
          SizedBox(height: t.cardGap),
          if (canWrite)
            OutlineButton(
              key: const Key('prices.add'),
              label: l10n.pricesAdd,
              icon: Icons.add,
              onPressed: crops.isEmpty
                  ? null
                  : () => showThottamSheet<void>(
                      context,
                      builder: (_) => _AddPriceSheet(
                        crops: crops.values.toList(),
                        cropId: selected!,
                      ),
                    ),
            )
          else
            LastTimeBanner(text: l10n.pricesReadOnly, icon: Icons.lock_outline),
        ],
      ),
    );
  }

  Future<void> _setAlert(String cropId, bool on, PriceSummary? s) async {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(pricesRepositoryProvider);
    int? threshold;
    if (on) {
      threshold = await showAmountDialog(
        context,
        title: l10n.pricesAlertAmount,
        paise: s?.latest.paise,
        fieldKey: const Key('alert.amount'),
        saveKey: const Key('alert.save'),
      );
      if (threshold == null || threshold <= 0) return;
    }
    final events = await repo.setAlert(cropId, threshold);
    if (mounted && events.isNotEmpty) {
      showUndoToast(context, l10n.toastSaved, () => repo.undo(events));
    }
  }
}

String _time(AppLocalizations l10n, DateTime at) =>
    // gate: not user-facing
    DateFormat('d MMM, h:mm a', l10n.localeName).format(at);

String _source(AppLocalizations l10n, PricePoint p) => p.local
    ? l10n.pricesYourEntry(p.market, _time(l10n, p.at))
    : l10n.pricesSource(p.source, _time(l10n, p.at));

class _CropRow extends ConsumerWidget {
  const _CropRow({
    required this.name,
    required this.prices,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final CropPrices? prices;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final now = ref.watch(clockProvider)();
    final s = prices == null ? null : summarize(prices!.points, now);
    final change = s?.changePaise;
    // an arrow and the amount, so colour is never the only sign
    final (changeText, icon, bg, fg) = switch (change) {
      null || 0 => (l10n.pricesNoChange, null, t.lineSoft, t.ink),
      > 0 => (
        formatPaise(change),
        Icons.arrow_upward,
        t.primaryPill,
        t.primaryDark,
      ),
      _ => (
        formatPaise(-change),
        Icons.arrow_downward,
        t.negativeTint,
        t.onNegativeTint,
      ),
    };
    final radius = BorderRadius.circular(t.cardRadius);
    return Semantics(
      selected: selected,
      child: Material(
        color: t.surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: selected ? t.primary : t.surface, width: 2),
        ),
        child: InkWell(
          key: Key('prices.crop.$name'),
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(t.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(name, style: text.titleMedium)),
                    Text(
                      s == null
                          ? '—'
                          : l10n.ratePerUnit(
                              formatPaise(s.latest.paise),
                              s.latest.unit,
                            ),
                      style: text.titleMedium,
                    ),
                  ],
                ),
                if (s != null) ...[
                  Text(_source(l10n, s.latest), style: text.bodySmall),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Semantics(
                        label: change == null || change == 0
                            ? null
                            : l10n.pricesChange(
                                '${change > 0 ? '+' : '−'}'
                                '${formatPaise(change.abs())}',
                              ),
                        child: Container(
                          key: const Key('prices.change'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(t.chipRadius),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (icon != null) Icon(icon, size: 16, color: fg),
                              Text(
                                changeText,
                                style: text.bodySmall!.copyWith(color: fg),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (s.stale)
                        StaleDataTag(
                          label: l10n.staleDataTag(
                            DateFormat(
                              // gate: not user-facing
                              'd MMM',
                              l10n.localeName,
                            ).format(s.latest.at),
                          ),
                        ),
                      if (alertHit(prices!.alertPaise, s.latest.paise))
                        Pill(
                          label: l10n.pricesAlertHit(
                            formatPaise(prices!.alertPaise!),
                          ),
                          background: t.accentTint,
                          foreground: t.onAccentTintStrong,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The last 30 days' prices as a line; the range is said in words below.
class _LinePainter extends CustomPainter {
  _LinePainter(this.values, this.colour, this.grid);

  final List<int> values;
  final Color colour;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = grid
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      line,
    );
    if (values.isEmpty) return;
    final low = values.reduce((a, b) => a < b ? a : b);
    final high = values.reduce((a, b) => a > b ? a : b);
    final span = high == low ? 1 : high - low;
    Offset at(int i) => Offset(
      values.length == 1
          ? size.width / 2
          : size.width * i / (values.length - 1),
      size.height * (1 - (values[i] - low) / span) * 0.9 + size.height * 0.05,
    );
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = colour
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(at(values.length - 1), 5, Paint()..color = colour);
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.values != values || old.colour != colour;
}

/// A rate from a shop or market, entered by hand.
class _AddPriceSheet extends ConsumerStatefulWidget {
  const _AddPriceSheet({required this.crops, required this.cropId});

  final List<CycleView> crops;
  final String cropId;

  @override
  ConsumerState<_AddPriceSheet> createState() => _AddPriceSheetState();
}

class _AddPriceSheetState extends ConsumerState<_AddPriceSheet> {
  late String _crop = widget.cropId;
  String? _unit;
  String? _defaultUnit;
  int? _paise;
  final _market = TextEditingController();
  bool _showErrors = false;

  @override
  void initState() {
    super.initState();
    _loadUnit();
  }

  Future<void> _loadUnit() async {
    final u = await ref.read(pricesRepositoryProvider).defaultUnit(_crop);
    if (mounted) setState(() => _unit = _defaultUnit = u);
  }

  @override
  void dispose() {
    _market.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if ((_paise ?? 0) <= 0 || _market.text.trim().isEmpty || _unit == null) {
      setState(() => _showErrors = true);
      return;
    }
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(pricesRepositoryProvider);
    final crop = widget.crops.firstWhere((c) => c.cropId == _crop);
    final events = await repo.addPrice(
      cropId: _crop,
      paise: _paise!,
      unit: _unit!,
      market: _market.text,
      at: ref.read(clockProvider)(),
      cropMl: crop.nameMl,
      cropEn: crop.nameEn,
    );
    if (!mounted) return;
    // the toast first: the sheet's context goes when it closes
    showUndoToast(context, l10n.toastSaved, () => repo.undo(events));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);
    // the crop's own units first, then the rest, never areas (as harvest)
    final units = {
      ?_defaultUnit,
      for (final u
          in ref
                  .watch(overridesProvider)
                  .value
                  ?.list('unit', Scope(cropId: _crop)) ??
              const <ListItem>[])
        if (!u.hidden && u.data['dimension']?.value != 'area') u.code,
    };
    return ListView(
      shrinkWrap: true,
      children: [
        Text(l10n.pricesAdd, style: text.titleLarge),
        SizedBox(height: t.cardGap),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in widget.crops)
              ChoiceChipX(
                key: Key('price.crop.${c.cropId}'),
                label: l10n.cropName(settings, c),
                selected: c.cropId == _crop,
                onSelected: (_) {
                  setState(() => _crop = c.cropId);
                  _loadUnit();
                },
              ),
          ],
        ),
        SizedBox(height: t.cardGap),
        AmountInput(
          key: const Key('price.amount'),
          label: l10n.pricesPerUnit(_unit ?? ''),
          hint: l10n.amountInputHint,
          onChanged: (p) => setState(() => _paise = p),
        ),
        if (_showErrors && (_paise ?? 0) <= 0)
          Text(
            l10n.pricesPriceRequired,
            style: text.bodySmall!.copyWith(color: t.danger),
          ),
        Wrap(
          spacing: 8,
          children: [
            for (final u in units)
              ChoiceChipX(
                key: Key('price.unit.$u'),
                label: u,
                selected: u == _unit,
                onSelected: (_) => setState(() => _unit = u),
              ),
          ],
        ),
        TextField(
          key: const Key('price.market'),
          controller: _market,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: l10n.pricesMarket,
            errorText: _showErrors && _market.text.trim().isEmpty
                ? l10n.pricesMarketRequired
                : null,
          ),
        ),
        SizedBox(height: t.cardGap),
        PrimaryButton(
          key: const Key('price.save'),
          label: l10n.actionSave,
          onPressed: _save,
        ),
      ],
    );
  }
}
