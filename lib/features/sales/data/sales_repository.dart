import 'package:drift/drift.dart';

import '../../../core/db/database.dart';
import '../../../core/db/queries.dart';
import '../../../core/history/write_with_history.dart';
import '../domain/sale_math.dart';

/// A lot with stock left.
class LotInStock {
  const LotInStock({
    required this.id,
    required this.cropId,
    required this.cropMl,
    required this.cropEn,
    required this.quantity,
    required this.stock,
    required this.unit,
    this.harvestedOn,
    this.costPaise,
  });

  final String id;
  final String cropId;
  final String cropMl;
  final String cropEn;

  /// What the lot held, and what is left, in thousandths of [unit].
  final int quantity;
  final int stock;
  final String unit;
  final String? harvestedOn;

  /// Null while the lot's cost is not yet worked out.
  final int? costPaise;
}

class Buyer {
  const Buyer(this.id, this.name, this.duePaise);
  final String id;
  final String name;

  /// What the buyer still owes.
  final int duePaise;
}

class BuyerSale {
  const BuyerSale(
    this.id,
    this.day,
    this.quantity,
    this.unit,
    this.net,
    this.due,
  );
  final String id;
  final String day;
  final int quantity;
  final String unit;
  final int net;
  final int due;
}

/// A sale to save. [takes] are (lot id, quantity in the lot's unit).
class SaleInput {
  const SaleInput({
    required this.day,
    required this.quantity,
    required this.unit,
    required this.ratePaise,
    required this.takes,
    this.deductions = const [],
    this.buyerId,
    this.newBuyer,
    this.saleType = 'trader',
    this.status = PaymentStatus.paid,
    this.receivedPaise,
    this.mode = 'cash',
    this.cropMl,
    this.cropEn,
  });

  final String day;

  /// Thousandths of [unit], the sale's own unit.
  final int quantity;
  final String unit;
  final int ratePaise;
  final List<(String, int)> takes;

  /// (label, paise).
  final List<(String, int)> deductions;
  final String? buyerId;

  /// A buyer named for the first time.
  final String? newBuyer;
  final String saleType;
  final PaymentStatus status;

  /// For a part payment: what was received now.
  final int? receivedPaise;

  /// How it was paid: cash, upi or bank.
  final String mode;
  final String? cropMl;
  final String? cropEn;

  int get grossPaise => gross(quantity, ratePaise);
  int get netPaise => net(grossPaise, [for (final d in deductions) d.$2]);
}

/// Selling from stock, buyers and what they owe (screen 13).
class SalesRepository {
  SalesRepository(this.db, this.history, this.farmId);

  final AppDatabase db;
  final History history;
  final String farmId;

  Stream<T> _watch<T>(Set<String> tables, Future<T> Function() load) async* {
    yield await load();
    final infos = {
      for (final t in db.allTables)
        if (tables.contains(t.actualTableName)) t,
    };
    await for (final _ in db.tableUpdates(
      TableUpdateQuery.onAllTables(infos),
    )) {
      yield await load();
    }
  }

  Stream<List<LotInStock>> watchLotsInStock() => _watch(
    {'lots', 'sale_lots', 'lot_costs', 'crop_cycles'},
    () async => [
      for (final r in await select(db, qLotsInStock, {'farm': farmId}))
        LotInStock(
          id: r.read<String>('id'),
          cropId: r.read<String>('crop_id'),
          cropMl: r.read<String>('name_ml'),
          cropEn: r.read<String>('name_en'),
          quantity: r.read<int>('quantity'),
          stock: r.read<int>('stock'),
          unit: r.read<String>('unit'),
          harvestedOn: r.readNullable<String>('harvested_on'),
          costPaise: r.read<bool>('cost_pending')
              ? null
              : r.readNullable<int>('cost_paise'),
        ),
    ],
  );

  Stream<List<Buyer>> watchBuyers() => _watch(
    {'parties', 'sales', 'sale_payments'},
    () async => [
      for (final r in await select(db, qBuyers, {'farm': farmId}))
        Buyer(r.read<String>('id'), r.read<String>('name'), r.read<int>('due')),
    ],
  );

  Stream<List<BuyerSale>> watchBuyerSales(String buyerId) => _watch(
    {'sales', 'sale_payments'},
    () async => [
      for (final r in await select(db, qBuyerSales, {'row': buyerId}))
        BuyerSale(
          r.read<String>('id'),
          r.read<String>('sold_on'),
          r.read<int>('quantity'),
          r.read<String>('unit'),
          r.read<int>('net_paise'),
          r.read<int>('due'),
        ),
    ],
  );

  /// The buyer type and payment mode of the latest sale.
  Future<(String?, String?)> last() async {
    final r = await select(db, qLastSale, {'farm': farmId});
    if (r.isEmpty) return (null, null);
    return (r.single.read<String>('sale_type'), r.single.read<String>('mode'));
  }

  /// The latest price of [cropId]: paise, unit, publish time, source.
  Future<(int, String, int, String)?> latestPrice(String cropId) async {
    final r = await select(db, qLatestPrice, {'row': cropId, 'farm': farmId});
    if (r.isEmpty) return null;
    return (
      r.single.read<int>('price_paise'),
      r.single.read<String>('unit'),
      r.single.read<int>('published_at'),
      r.single.read<String>('source'),
    );
  }

  /// Saves the sale, the stock it takes and any payment in one transaction.
  /// Refuses, before writing anything, to take more than a lot holds.
  Future<List<String>> save(SaleInput s) async {
    for (final (lot, taken) in s.takes) {
      final r = await db
          .customSelect(
            'SELECT l.quantity - COALESCE((SELECT SUM(quantity) FROM sale_lots '
            'WHERE lot_id = l.id AND deleted_at IS NULL), 0) AS stock '
            'FROM lots l WHERE l.id = ?',
            variables: [Variable.withString(lot)],
          )
          .getSingle();
      if (taken > r.read<int>('stock')) {
        throw StateError('lot $lot holds less than $taken');
      }
    }
    final id = history.newId();
    final buyerId =
        s.buyerId ??
        (s.newBuyer == null || s.newBuyer!.trim().isEmpty
            ? null
            : history.newId());
    final received = switch (s.status) {
      PaymentStatus.paid => s.netPaise,
      PaymentStatus.part => s.receivedPaise ?? 0,
      PaymentStatus.due => 0,
    };
    final summary = {
      'crop_ml': ?s.cropMl,
      'crop_en': ?s.cropEn,
      'amount_paise': s.netPaise,
      'quantity': s.quantity,
      'unit': s.unit,
      'party': ?s.newBuyer?.trim(),
    };
    return history.writeWithHistory([
      if (s.buyerId == null && buyerId != null)
        CreateRow(
          'parties',
          {
            'id': buyerId,
            'farm_id': farmId,
            'kind': 'buyer',
            'name': s.newBuyer!.trim(),
          },
          summary: {'party': s.newBuyer!.trim()},
        ),
      CreateRow(
        'sales',
        {
          'id': id,
          'farm_id': farmId,
          'sold_on': s.day,
          'buyer_party_id': buyerId,
          'sale_type': s.saleType,
          'quantity': s.quantity,
          'unit': s.unit,
          'rate_paise': s.ratePaise,
          'deductions': [
            for (final (label, paise) in s.deductions)
              {'code': 'other', 'label': label, 'amount_paise': paise},
          ],
          'net_paise': s.netPaise,
          'mode': s.status == PaymentStatus.due ? 'credit' : s.mode,
        },
        occurredOn: s.day,
        summary: summary,
      ),
      for (final (lot, taken) in s.takes)
        CreateRow('sale_lots', {
          'farm_id': farmId,
          'sale_id': id,
          'lot_id': lot,
          'quantity': taken,
        }, occurredOn: s.day),
      if (received > 0)
        CreateRow(
          'sale_payments',
          {
            'farm_id': farmId,
            'sale_id': id,
            'received_on': s.day,
            'amount_paise': received,
            'mode': s.mode,
          },
          occurredOn: s.day,
          summary: {'amount_paise': received},
        ),
    ]);
  }

  /// Money received later on sale [saleId].
  Future<List<String>> receive(
    String saleId,
    int paise,
    String day, {
    String mode = 'cash',
  }) => history.writeWithHistory([
    CreateRow(
      'sale_payments',
      {
        'farm_id': farmId,
        'sale_id': saleId,
        'received_on': day,
        'amount_paise': paise,
        'mode': mode,
      },
      occurredOn: day,
      summary: {'amount_paise': paise},
    ),
  ]);

  Future<void> undo(List<String> events) => history.undo(events);
}
