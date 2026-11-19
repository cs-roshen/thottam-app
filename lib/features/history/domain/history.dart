/// The farm diary (screen 15): which records it shows, its filters, and an
/// edit's old → new lines. Pure Dart.
library;

import '../../../core/access/access.dart';

enum HistoryFilter { all, labour, expense, harvest, sales, edits }

/// Records the diary shows. Parts of a save (splits, the lots a sale took,
/// group members) show through the record they belong to.
const diaryEntities = {
  'farms',
  'plots',
  'crop_cycles',
  'workers',
  'labour_groups',
  'labour_entries',
  'labour_payments',
  'expenses',
  'expense_payments',
  'harvests',
  'lot_costs',
  'sales',
  'sale_payments',
  'parties',
  'notes',
  'tasks',
  'template_overrides',
  'other_income',
};

const _byFilter = {
  HistoryFilter.labour: {
    'labour_entries',
    'labour_payments',
    'workers',
    'labour_groups',
  },
  HistoryFilter.expense: {'expenses', 'expense_payments'},
  HistoryFilter.harvest: {'harvests', 'lot_costs'},
  HistoryFilter.sales: {'sales', 'sale_payments', 'parties'},
};

/// The entities [filter] shows to someone with [access]: money records are
/// left out for a role that cannot read money (a supervisor), as the
/// server leaves their history out.
Set<String> entitiesFor(HistoryFilter filter, Access access) => {
  for (final e in _byFilter[filter] ?? diaryEntities)
    if (access.canRead(tableAccess[e] ?? AccessClass.setup)) e,
};

/// The actions [filter] shows: edits are changes after the first save.
Set<String> actionsFor(HistoryFilter filter) => filter == HistoryFilter.edits
    ? const {'update', 'delete', 'restore'}
    : const {'create', 'update', 'delete', 'restore'};

/// A set as the `,a,b,` list the history queries match against.
String asParam(Set<String> values) => ',${values.join(',')},';

/// Fields an edit shows; times, versions and ids say nothing to a farmer.
bool shownField(String field) =>
    !const {
      'id',
      'farm_id',
      'created_at',
      'created_by',
      'updated_at',
      'updated_by',
      'version',
    }.contains(field) &&
    !field.endsWith('_id');

/// The old → new pairs of an edit, in a steady order.
List<(String, Object?, Object?)> changes(
  Map<String, Object?>? oldValues,
  Map<String, Object?>? newValues,
) {
  final keys = {...?oldValues?.keys, ...?newValues?.keys}.where(shownField)
    ..toList();
  return [
    for (final k in keys.toList()..sort())
      if (oldValues?[k] != newValues?[k]) (k, oldValues?[k], newValues?[k]),
  ];
}

/// The money a history row is about, signed as the farmer sees it: money
/// out negative (expenses, wages paid), money in positive (sales and money
/// received); null when the row is not money.
int? signedAmount(String entity, Map<String, Object?> summary) {
  final paise = summary['amount_paise'];
  if (paise is! int) return null;
  return switch (entity) {
    'sales' || 'sale_payments' || 'other_income' => paise,
    'expenses' ||
    'expense_payments' ||
    'labour_entries' ||
    'labour_payments' => -paise,
    _ => null,
  };
}

/// The week around the same day last year: three days either side.
(String, String) weekLastYear(DateTime today) {
  final mid = DateTime(today.year - 1, today.month, today.day);
  String iso(DateTime d) => d.toIso8601String().substring(0, 10);
  return (
    iso(mid.subtract(const Duration(days: 3))),
    iso(mid.add(const Duration(days: 3))),
  );
}
