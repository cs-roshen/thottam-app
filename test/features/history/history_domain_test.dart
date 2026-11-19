import 'package:flutter_test/flutter_test.dart';
import 'package:thottam/core/access/access.dart';
import 'package:thottam/features/history/domain/history.dart';

void main() {
  test('a supervisor sees no money records in the diary', () {
    final mine = entitiesFor(HistoryFilter.all, const Access('supervisor'));
    expect(mine, containsAll(['labour_entries', 'harvests', 'notes']));
    for (final money in [
      'expenses',
      'sales',
      'sale_payments',
      'labour_payments',
      'lot_costs',
      'parties',
    ]) {
      expect(mine, isNot(contains(money)), reason: money);
    }
    expect(
      entitiesFor(HistoryFilter.sales, const Access('supervisor')),
      isEmpty,
    );
    expect(
      entitiesFor(HistoryFilter.all, const Access('owner')),
      containsAll(['expenses', 'sales']),
    );
  });

  test('filters pick their records; edits pick changes', () {
    expect(entitiesFor(HistoryFilter.expense, const Access('owner')), {
      'expenses',
      'expense_payments',
    });
    expect(actionsFor(HistoryFilter.edits), isNot(contains('create')));
    expect(asParam({'a', 'b'}), ',a,b,');
  });

  test('an edit shows what changed, old → new, and nothing internal', () {
    expect(
      changes(
        {'amount_paise': 360000, 'version': 1, 'plot_id': 'p'},
        {'amount_paise': 380000, 'version': 2, 'plot_id': 'q'},
      ),
      [('amount_paise', 360000, 380000)],
    );
    expect(changes(null, {'name': 'Hill'}), [('name', null, 'Hill')]);
  });

  test('money out is negative, money in positive, the rest none', () {
    expect(signedAmount('expenses', {'amount_paise': 360000}), -360000);
    expect(signedAmount('sales', {'amount_paise': 3508000}), 3508000);
    expect(signedAmount('plots', {'amount_paise': 1}), isNull);
    expect(signedAmount('sales', const {}), isNull);
  });

  test('this week last year is three days either side', () {
    expect(weekLastYear(DateTime(2026, 11, 19)), ('2025-11-16', '2025-11-22'));
  });
}
