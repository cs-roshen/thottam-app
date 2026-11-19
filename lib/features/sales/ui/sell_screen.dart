import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/date_format.dart';
import '../../../app/session.dart';
import '../../../app/settings.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/widgets/widgets.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/money/money_parse.dart';
import '../../../core/overrides/overrides.dart';
import '../../../core/units/quantity_parse.dart';
import '../../../l10n/app_localizations.dart';
import '../data/sales_providers.dart';
import '../data/sales_repository.dart';
import '../domain/sale_math.dart';

/// Screen 13: sell from one or more lots of a crop. Rate prefilled from
/// the latest price; gross, deductions, net; profit per sale unit before
/// saving; paid, part paid or due. Saving lowers the stock.
class SellScreen extends ConsumerStatefulWidget {
  const SellScreen({super.key, this.lotId});

  final String? lotId;

  @override
  ConsumerState<SellScreen> createState() => _SellScreenState();
}

class _Deduction {
  String label = '';
  int paise = 0;
}

class _SellScreenState extends ConsumerState<SellScreen> {
  late String _day;
  String? _cropId;
  final _lots = <String>{};
  String? _unit;
  final _qty = TextEditingController();
  final _rate = TextEditingController();
  bool _rateTouched = false;
  (int, String, int, String)? _price;
  String? _buyerId;
  final _buyerName = TextEditingController();
  String _saleType = 'trader';
  final _deductions = <_Deduction>[];
  PaymentStatus _status = PaymentStatus.paid;
  int? _received;
  String _mode = 'cash';
  bool _showErrors = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _day = _iso(ref.read(clockProvider)());
    ref.read(salesRepositoryProvider).last().then((l) {
      if (!mounted) return;
      setState(() {
        _saleType = l.$1 ?? _saleType;
        if (l.$2 case 'cash' || 'upi' || 'bank') _mode = l.$2!;
      });
    });
  }

  @override
  void dispose() {
    for (final c in [_qty, _rate, _buyerName]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String _plainPaise(int paise) =>
      formatPaise(paise).replaceAll('₹', '').replaceAll(',', '');

  /// Picks the crop and its lots once the stock has loaded.
  void _pickCrop(List<LotInStock> stock, String cropId, {String? lot}) {
    _cropId = cropId;
    _lots
      ..clear()
      ..add(lot ?? stock.firstWhere((l) => l.cropId == cropId).id);
    _unit = null;
    _price = null;
    ref.read(salesRepositoryProvider).latestPrice(cropId).then((p) {
      if (mounted) setState(() => _price = p);
    });
  }

  /// The price in the sale's unit, or null.
  int? _priceIn(String unit) {
    final p = _price;
    final units = ref.read(unitsProvider);
    if (p == null || units == null) return null;
    final oneSaleUnit = units.convert(1000, unit, p.$2);
    return oneSaleUnit == null ? null : mulDivRound(p.$1, oneSaleUnit, 1000);
  }

  Future<void> _save(SaleInput input) async {
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(salesRepositoryProvider);
    final events = await repo.save(input);
    if (!mounted) return;
    showUndoToast(context, l10n.toastSaved, () => repo.undo(events));
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);
    final canSell = ref.watch(canSellProvider);
    final units = ref.watch(unitsProvider);
    final overrides = ref.watch(overridesProvider).value;
    final stock = ref.watch(lotsInStockProvider).value;
    final buyers = ref.watch(buyersProvider).value ?? const <Buyer>[];
    final today = ref.watch(clockProvider)();

    if (stock != null && stock.isNotEmpty && _cropId == null) {
      final start = stock.where((l) => l.id == widget.lotId).firstOrNull;
      _pickCrop(stock, (start ?? stock.first).cropId, lot: start?.id);
    }
    final crops = <String, LotInStock>{
      for (final l in stock ?? const <LotInStock>[]) l.cropId: l,
    };
    final cropLots = [
      for (final l in stock ?? const <LotInStock>[])
        if (l.cropId == _cropId) l,
    ];
    final chosen = [
      for (final l in cropLots)
        if (_lots.contains(l.id)) l,
    ];
    final lotUnit = chosen.firstOrNull?.unit;
    // units of the lot's kind: a lot in kg sells by kg, quintal or tonne
    final saleUnits = [
      for (final u
          in overrides?.list('unit', Scope(cropId: _cropId)) ??
              const <ListItem>[])
        if (!u.hidden &&
            lotUnit != null &&
            units?.convert(1000, u.code, lotUnit) != null)
          u.code,
    ];
    final unit = _unit ?? lotUnit ?? 'kg';
    if (!_rateTouched && _rate.text.isEmpty) {
      final p = _priceIn(unit);
      if (p != null) _rate.text = _plainPaise(p);
    }

    final qty = parseQuantity(_qty.text) ?? 0;
    final rate = parseRupeesToPaise(_rate.text) ?? 0;
    final qtyInLot = lotUnit == null
        ? null
        : units?.convert(qty, unit, lotUnit);
    final takes = qtyInLot == null
        ? null
        : takeFrom([for (final l in chosen) StockLot(l.id, l.stock)], qtyInLot);
    final inStock = chosen.fold<int>(0, (s, l) => s + l.stock);
    final g = gross(qty, rate);
    final n = net(g, [for (final d in _deductions) d.paise]);
    final costKnown = chosen.every((l) => l.costPaise != null);
    final lotTakes = [
      for (final (id, taken) in takes ?? const <(String, int)>[])
        LotTake(
          taken,
          chosen.firstWhere((l) => l.id == id).quantity,
          chosen.firstWhere((l) => l.id == id).costPaise ?? 0,
        ),
    ];
    final cost = costKnown && takes != null
        ? costPerSaleUnit(lotTakes, qty)
        : null;
    final profit = costKnown && takes != null
        ? profitPerSaleUnit(n, lotTakes, qty)
        : null;

    String? error;
    if (_showErrors && qty <= 0) error = l10n.saleNoQuantity;
    if (_showErrors && rate <= 0) error ??= l10n.saleNoRate;
    if (qty > 0 && qtyInLot == null) error = l10n.saleNoUnitWay;
    if (qty > 0 && qtyInLot != null && takes == null) {
      error = l10n.saleTooMuch(
        l10n.quantityWithUnit(formatQuantity(inStock), lotUnit!),
      );
    }

    Widget line(String label, String value, {Key? key, bool big = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          // wraps at large text sizes rather than running off the edge
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(label, style: big ? text.bodyLarge : text.bodyMedium),
              Text(
                value,
                key: key,
                style: big ? text.headlineMedium : text.bodyLarge,
              ),
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.saleTitle),
        actions: [
          IconButton(
            key: const Key('sale.buyers'),
            tooltip: l10n.buyersTitle,
            icon: const Icon(Icons.storefront_outlined),
            onPressed: () => context.push('/sales/buyers'),
          ),
        ],
      ),
      body: stock == null
          ? const SizedBox.shrink()
          : stock.isEmpty
          ? Padding(
              padding: EdgeInsets.all(t.screenPadding),
              child: EmptyState(
                icon: Icons.inventory_2_outlined,
                title: l10n.saleTitle,
                message: l10n.saleNoStock,
              ),
            )
          : ListView(
              padding: EdgeInsets.all(t.screenPadding),
              children: [
                if (!canSell) ...[
                  LastTimeBanner(
                    text: l10n.saleReadOnly,
                    icon: Icons.lock_outline,
                  ),
                  SizedBox(height: t.cardGap),
                ],
                if (_price case final p?) ...[
                  ThottamCard(
                    key: const Key('sale.price'),
                    onTap: () => context.push('/prices'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.saleTodayPrice(formatPaise(p.$1), p.$2),
                          style: text.titleMedium,
                        ),
                        Text(
                          l10n.pricesSource(
                            p.$4,
                            DateFormat(
                              // gate: not user-facing
                              'd MMM, h:mm a',
                              l10n.localeName,
                            ).format(DateTime.fromMillisecondsSinceEpoch(p.$3)),
                          ),
                          style: text.bodySmall,
                        ),
                        if (today.millisecondsSinceEpoch - p.$3 >
                            const Duration(days: 1).inMilliseconds)
                          StaleDataTag(
                            label: l10n.staleDataTag(
                              formatDay(
                                _iso(DateTime.fromMillisecondsSinceEpoch(p.$3)),
                                l10n,
                                today,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(height: t.cardGap),
                ],
                if (crops.length > 1) ...[
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final c in crops.values)
                        ChoiceChipX(
                          key: Key('sale.crop.${c.cropEn}'),
                          label: localName(
                            settings,
                            c.cropMl,
                            c.cropEn,
                            l10n.nameMixed,
                          ),
                          selected: c.cropId == _cropId,
                          onSelected: (_) => setState(() {
                            _pickCrop(stock, c.cropId);
                            _rate.clear();
                            _rateTouched = false;
                          }),
                        ),
                    ],
                  ),
                  SizedBox(height: t.cardGap),
                ],
                Text(l10n.saleFrom, style: text.bodySmall),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final l in cropLots)
                      ChoiceChipX(
                        key: Key('sale.lot.${l.id}'),
                        label: l10n.saleLotChip(
                          l.harvestedOn == null
                              ? ''
                              : formatDay(l.harvestedOn!, l10n, today),
                          l10n.quantityWithUnit(
                            formatQuantity(l.stock),
                            l.unit,
                          ),
                        ),
                        selected: _lots.contains(l.id),
                        onSelected: (on) => setState(() {
                          on ? _lots.add(l.id) : _lots.remove(l.id);
                          if (_lots.isEmpty) _lots.add(l.id);
                        }),
                      ),
                  ],
                ),
                SizedBox(height: t.cardGap),
                TextField(
                  key: const Key('sale.quantity'),
                  controller: _qty,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  style: text.displayLarge,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: l10n.fieldQuantityInUnit(unit),
                    suffixText: unit,
                  ),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final u in saleUnits)
                      ChoiceChipX(
                        key: Key('sale.unit.$u'),
                        label: u,
                        selected: u == unit,
                        onSelected: (_) => setState(() {
                          _unit = u;
                          if (!_rateTouched) _rate.clear();
                        }),
                      ),
                  ],
                ),
                TextField(
                  key: const Key('sale.rate'),
                  controller: _rate,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  onChanged: (_) => setState(() => _rateTouched = true),
                  decoration: InputDecoration(
                    labelText: l10n.saleRatePerUnit(unit),
                    prefixText: '₹ ',
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      error,
                      key: const Key('sale.error'),
                      style: text.bodySmall!.copyWith(color: t.danger),
                    ),
                  ),
                SizedBox(height: t.cardGap),
                Text(l10n.saleBuyer, style: text.bodySmall),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final b in buyers)
                      ChoiceChipX(
                        key: Key('sale.buyer.${b.id}'),
                        label: b.name,
                        selected: _buyerId == b.id,
                        onSelected: (_) => setState(() => _buyerId = b.id),
                      ),
                    ChoiceChipX(
                      key: const Key('sale.buyer.new'),
                      label: l10n.saleNewBuyer,
                      selected: _buyerId == null,
                      onSelected: (_) => setState(() => _buyerId = null),
                    ),
                  ],
                ),
                if (_buyerId == null)
                  TextField(
                    key: const Key('sale.buyerName'),
                    controller: _buyerName,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(labelText: l10n.saleBuyerName),
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final type in const ['trader', 'society', 'direct'])
                      ChoiceChipX(
                        key: Key('sale.type.$type'),
                        label: l10n.saleType(type),
                        selected: _saleType == type,
                        onSelected: (_) => setState(() => _saleType = type),
                      ),
                  ],
                ),
                SizedBox(height: t.cardGap),
                ThottamCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      line(
                        l10n.saleGross,
                        formatPaise(g),
                        key: const Key('sale.gross'),
                      ),
                      Text(l10n.saleDeductions, style: text.bodySmall),
                      for (var i = 0; i < _deductions.length; i++)
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                key: Key('sale.deduction.$i.label'),
                                initialValue: _deductions[i].label,
                                decoration: InputDecoration(
                                  labelText: l10n.saleDeductionLabel,
                                ),
                                onChanged: (v) => _deductions[i].label = v,
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 110,
                              child: TextFormField(
                                key: Key('sale.deduction.$i.amount'),
                                initialValue: _deductions[i].paise == 0
                                    ? ''
                                    : _plainPaise(_deductions[i].paise),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  prefixText: '₹ ',
                                ),
                                onChanged: (v) => setState(
                                  () => _deductions[i].paise =
                                      parseRupeesToPaise(v) ?? 0,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: l10n.actionRemove,
                              icon: const Icon(Icons.close),
                              onPressed: () =>
                                  setState(() => _deductions.removeAt(i)),
                            ),
                          ],
                        ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          key: const Key('sale.addDeduction'),
                          onPressed: () =>
                              setState(() => _deductions.add(_Deduction())),
                          icon: const Icon(Icons.add),
                          label: Text(l10n.saleAddDeduction),
                        ),
                      ),
                      const Divider(),
                      line(
                        l10n.saleNet,
                        formatPaise(n),
                        key: const Key('sale.net'),
                        big: true,
                      ),
                      if (perUnit(n, qty) case final p?)
                        Text(
                          l10n.salePerUnitNet(formatPaise(p), unit),
                          key: const Key('sale.netPerUnit'),
                          style: text.bodySmall,
                        ),
                      if (qty > 0 && takes != null) ...[
                        const Divider(),
                        line(
                          l10n.saleProfitPerUnit(unit),
                          profit == null
                              ? l10n.lotCostPending
                              : formatPaise(profit),
                          key: const Key('sale.profit'),
                        ),
                        if (cost != null)
                          Text(
                            l10n.saleCostLine(formatPaise(cost), unit),
                            key: const Key('sale.cost'),
                            style: text.bodySmall,
                          ),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: t.cardGap),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final (s, label) in [
                      (PaymentStatus.paid, l10n.salePaid),
                      (PaymentStatus.part, l10n.salePartPaid),
                      (PaymentStatus.due, l10n.saleDue),
                    ])
                      ChoiceChipX(
                        key: Key('sale.status.${s.name}'),
                        label: label,
                        selected: _status == s,
                        onSelected: (_) => setState(() => _status = s),
                      ),
                  ],
                ),
                if (_status == PaymentStatus.part)
                  TextField(
                    key: const Key('sale.received'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: l10n.saleReceivedNow,
                      prefixText: '₹ ',
                    ),
                    onChanged: (v) =>
                        setState(() => _received = parseRupeesToPaise(v)),
                  ),
                if (_status != PaymentStatus.due)
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final (code, label) in [
                        ('cash', l10n.paymentCash),
                        ('upi', l10n.paymentUpi),
                        ('bank', l10n.paymentBank),
                      ])
                        ChoiceChipX(
                          key: Key('sale.mode.$code'),
                          label: label,
                          selected: _mode == code,
                          onSelected: (_) => setState(() => _mode = code),
                        ),
                    ],
                  ),
              ],
            ),
      bottomNavigationBar: stock == null || stock.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: EdgeInsets.all(t.screenPadding),
                child: PrimaryButton(
                  key: const Key('sale.save'),
                  label: l10n.saleSave,
                  onPressed: !canSell || _saving
                      ? null
                      : () {
                          if (qty <= 0 || rate <= 0 || takes == null) {
                            setState(() => _showErrors = true);
                            return;
                          }
                          final crop = crops[_cropId]!;
                          _save(
                            SaleInput(
                              day: _day,
                              quantity: qty,
                              unit: unit,
                              ratePaise: rate,
                              takes: takes,
                              deductions: [
                                for (final d in _deductions)
                                  if (d.paise != 0) (d.label.trim(), d.paise),
                              ],
                              buyerId: _buyerId,
                              newBuyer: _buyerId == null
                                  ? _buyerName.text
                                  : null,
                              saleType: _saleType,
                              status: _status,
                              receivedPaise: _received,
                              mode: _mode,
                              cropMl: crop.cropMl,
                              cropEn: crop.cropEn,
                            ),
                          );
                        },
                ),
              ),
            ),
    );
  }
}
