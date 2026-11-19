import 'package:drift/drift.dart';

import '../../../core/db/database.dart';
import '../../../core/db/queries.dart';
import '../../../core/history/write_with_history.dart';

/// An expense to save. [parts] are the crop cycles' shares of [amountPaise]
/// (they sum to it); empty when the plot has no crops.
class ExpenseInput {
  const ExpenseInput({
    required this.day,
    required this.categoryCode,
    required this.amountPaise,
    required this.plotId,
    this.parts = const [],
    this.manual = false,
    this.mode = 'cash',
    this.vendor,
    this.plotName,
  });

  final String day;
  final String categoryCode;
  final int amountPaise;
  final String plotId;
  final List<(String cycleId, int paise)> parts;

  /// The farmer edited the split by hand.
  final bool manual;

  /// cash, upi, bank or credit; credit leaves a payable.
  final String mode;

  /// Who it was bought from, when on credit.
  final String? vendor;
  final String? plotName;
}

/// A purchase on credit and what is still owed on it.
class Payable {
  const Payable(this.expenseId, this.day, this.categoryCode, this.owedPaise);
  final String expenseId;
  final String day;
  final String categoryCode;
  final int owedPaise;
}

/// Expenses with their split across crop cycles (screen 9).
class ExpenseRepository {
  ExpenseRepository(this.db, this.history, this.farmId);

  final AppDatabase db;
  final History history;
  final String farmId;

  /// Category codes used most in the 90 days before [today], most used
  /// first.
  Future<List<String>> categoriesByUse(String today) async => [
    for (final r in await select(db, qCategoryUse, {
      'farm': farmId,
      'from': DateTime.parse(today)
          .subtract(const Duration(days: 90))
          .toIso8601String()
          .substring(0, 10),
    }))
      r.read<String>('category_code'),
  ];

  /// The plot, category and payment mode of the latest expense.
  Future<(String?, String?, String?)> last() async {
    final r = await select(db, qLastExpense, {'farm': farmId});
    if (r.isEmpty) return (null, null, null);
    return (
      r.single.readNullable<String>('plot_id'),
      r.single.read<String>('category_code'),
      r.single.read<String>('mode'),
    );
  }

  /// Saves the expense and its split in one transaction; returns the
  /// history ids for undo.
  Future<List<String>> save(ExpenseInput e) async {
    assert(
      e.parts.isEmpty ||
          e.parts.fold<int>(0, (s, p) => s + p.$2) == e.amountPaise,
      // gate: not user-facing
      'parts must sum to the amount',
    );
    final id = history.newId();
    final vendorId = e.mode == 'credit' ? await _vendor(e.vendor) : null;
    final summary = {
      'plot_id': e.plotId,
      'plot': ?e.plotName,
      'amount_paise': e.amountPaise,
      'category': e.categoryCode,
    };
    return history.writeWithHistory([
      if (vendorId case (final vid, true))
        CreateRow(
          'parties',
          {
            'id': vid,
            'farm_id': farmId,
            'kind': 'vendor',
            'name': e.vendor!.trim(),
          },
          summary: {'party': e.vendor!.trim()},
        ),
      CreateRow(
        'expenses',
        {
          'id': id,
          'farm_id': farmId,
          'spent_on': e.day,
          'category_code': e.categoryCode,
          'amount_paise': e.amountPaise,
          'plot_id': e.plotId,
          'mode': e.mode,
          'vendor_party_id': vendorId?.$1,
        },
        occurredOn: e.day,
        summary: summary,
      ),
      for (final (cycle, paise) in e.parts)
        CreateRow('expense_allocations', {
          'farm_id': farmId,
          'expense_id': id,
          'crop_cycle_id': cycle,
          'amount_paise': paise,
          'is_manual': e.manual,
        }, occurredOn: e.day),
    ]);
  }

  /// The vendor's party id, and whether it must be made: a shop named
  /// before is found by name.
  Future<(String, bool)?> _vendor(String? name) async {
    if (name == null || name.trim().isEmpty) return null;
    final found = await db
        .customSelect(
          "SELECT id FROM parties WHERE farm_id = ? AND kind = 'vendor' "
          'AND deleted_at IS NULL AND name = ? LIMIT 1',
          variables: [
            Variable.withString(farmId),
            Variable.withString(name.trim()),
          ],
        )
        .getSingleOrNull();
    return found == null
        ? (history.newId(), true)
        : (found.read<String>('id'), false);
  }

  /// Deletes an expense with its split: totals read live allocations only,
  /// so they go together.
  Future<List<String>> delete(String expenseId) async {
    final parts = await db
        .customSelect(
          'SELECT id FROM expense_allocations WHERE expense_id = ? '
          'AND deleted_at IS NULL',
          variables: [Variable.withString(expenseId)],
        )
        .get();
    return history.writeWithHistory([
      for (final p in parts)
        DeleteRow('expense_allocations', p.read<String>('id')),
      DeleteRow('expenses', expenseId),
    ]);
  }

  /// What is still owed on purchases made on credit, newest first.
  Future<List<Payable>> payables() async => [
    for (final r in await select(db, qPayables, {'farm': farmId}))
      if (r.read<int>('owed') > 0)
        Payable(
          r.read<String>('id'),
          r.read<String>('spent_on'),
          r.read<String>('category_code'),
          r.read<int>('owed'),
        ),
  ];

  Future<void> undo(List<String> events) => history.undo(events);
}
