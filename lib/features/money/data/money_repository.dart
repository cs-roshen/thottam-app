import 'package:drift/drift.dart';

import '../../../core/db/database.dart';
import '../../../core/db/queries.dart';
import '../domain/profit.dart';

/// One crop cycle's money for a period, with its crop's names; crop and
/// names are null for money on no crop.
typedef CycleMoneyRow = ({
  CycleMoney money,
  String? crop,
  String? nameMl,
  String? nameEn,
});

/// Profit and loss, read from the local database (screen 5).
class MoneyRepository {
  MoneyRepository(this.db, this.farmId);

  final AppDatabase db;
  final String farmId;

  static const _tables = {
    'sales',
    'sale_lots',
    'lots',
    'other_income',
    'expenses',
    'expense_allocations',
    'labour_entries',
    'labour_allocations',
    'workers',
    'crop_cycles',
    'crops',
  };

  /// Each crop cycle's money from [from] to [to] (inclusive days), on one
  /// plot or, with [plotId] '', on every plot.
  Stream<List<CycleMoneyRow>> watchCycles({
    required String from,
    required String to,
    String plotId = '',
  }) async* {
    Future<List<CycleMoneyRow>> load() async => [
      for (final r in await select(db, qProfitAndLoss, {
        'farm': farmId,
        'from': from,
        'to': to,
        'plot': plotId,
      }))
        (
          money: CycleMoney(
            r.readNullable<String>('cycle'),
            incomePaise: r.read<int>('income'),
            expensePaise: r.read<int>('expense'),
            paidLabourPaise: r.read<int>('paid'),
            familyLabourPaise: r.read<int>('family'),
          ),
          crop: r.readNullable<String>('crop'),
          nameMl: r.readNullable<String>('name_ml'),
          nameEn: r.readNullable<String>('name_en'),
        ),
    ];
    yield await load();
    final infos = {
      for (final t in db.allTables)
        if (_tables.contains(t.actualTableName)) t,
    };
    await for (final _ in db.tableUpdates(
      TableUpdateQuery.onAllTables(infos),
    )) {
      yield await load();
    }
  }
}
