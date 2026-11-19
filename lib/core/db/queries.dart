import 'package:drift/drift.dart';

import 'database.dart';

/// The list and total queries the app runs, with the shapes section 12 asks
/// for (keyset pages, totals in SQL, partial indexes on live rows).
/// Repositories run them through [select] and [watch]; the query-plan test
/// checks each uses an index and the benchmark test times each with the seed
/// loaded, so the gates test the queries the app runs. Add each new list or
/// total query here, not inline in a repository.
class ListQuery {
  const ListQuery(
    this.name,
    this.sql, {
    this.ordered = false,
    this.budgetMs = 50,
  });

  final String name;

  /// Named parameters (:farm, :plot, :cycle, :worker, :group, :entity,
  /// :row, :from, :to, :day, :id, :limit), bound by [bindNamed].
  final String sql;

  /// A page in index order: must not sort in a temporary b-tree.
  final bool ordered;
  final int budgetMs;
}

const listQueries = [
  ...landQueries,
  ...labourQueries,
  ...expenseQueries,
  ListQuery(
    'labour day page',
    'SELECT * FROM labour_entries WHERE farm_id = :farm AND deleted_at IS NULL '
        'AND (work_date, id) < (:day, :id) ORDER BY work_date DESC, id DESC LIMIT 50',
    ordered: true,
  ),
  ListQuery(
    'expense day page',
    'SELECT * FROM expenses WHERE farm_id = :farm AND deleted_at IS NULL '
        'AND (spent_on, id) < (:day, :id) ORDER BY spent_on DESC, id DESC LIMIT 50',
    ordered: true,
  ),
  ListQuery(
    'harvest day page',
    'SELECT * FROM harvests WHERE farm_id = :farm AND deleted_at IS NULL '
        'AND (harvested_on, id) < (:day, :id) ORDER BY harvested_on DESC, id DESC LIMIT 50',
    ordered: true,
  ),
  ListQuery(
    'sales day page',
    'SELECT * FROM sales WHERE farm_id = :farm AND deleted_at IS NULL '
        'AND (sold_on, id) < (:day, :id) ORDER BY sold_on DESC, id DESC LIMIT 50',
    ordered: true,
  ),
  ListQuery(
    'history page',
    'SELECT * FROM event_log WHERE farm_id = :farm '
        'AND (occurred_on, created_at, id) < (:day, 9999999999999, :id) '
        'ORDER BY occurred_on DESC, created_at DESC, id DESC LIMIT 50',
    ordered: true,
  ),
  ListQuery(
    'record timeline',
    'SELECT * FROM event_log WHERE entity = :entity AND entity_id = :row '
        'ORDER BY created_at DESC LIMIT 50',
    ordered: true,
  ),
  ListQuery(
    'month expenses by category',
    'SELECT category_code, SUM(amount_paise) FROM expenses WHERE farm_id = :farm '
        'AND deleted_at IS NULL AND spent_on BETWEEN :from AND :to GROUP BY category_code',
  ),
  ListQuery(
    'crop cycle expense total',
    'SELECT SUM(a.amount_paise) FROM expense_allocations a '
        'JOIN expenses e ON e.id = a.expense_id AND e.deleted_at IS NULL '
        'WHERE a.crop_cycle_id = :cycle AND a.deleted_at IS NULL',
  ),
  ListQuery(
    'crop cycle labour total for a period',
    'SELECT SUM(amount_paise) FROM labour_entries WHERE crop_cycle_id = :cycle '
        'AND deleted_at IS NULL AND work_date BETWEEN :from AND :to',
  ),
  ListQuery(
    'profit and loss for a season, expenses by crop cycle',
    'SELECT a.crop_cycle_id, SUM(a.amount_paise) FROM expenses e '
        'JOIN expense_allocations a ON a.expense_id = e.id AND a.deleted_at IS NULL '
        'WHERE e.farm_id = :farm AND e.deleted_at IS NULL AND e.spent_on BETWEEN :from AND :to '
        'GROUP BY a.crop_cycle_id',
    budgetMs: 150,
  ),
  ListQuery(
    'profit and loss for a season, labour by crop cycle',
    // an entry split across a mixed plot has no crop cycle of its own: its
    // labour_allocations carry the parts
    'SELECT cycle, SUM(paise) FROM ('
        'SELECT crop_cycle_id AS cycle, amount_paise AS paise FROM labour_entries '
        'WHERE farm_id = :farm AND deleted_at IS NULL AND crop_cycle_id IS NOT NULL '
        'AND work_date BETWEEN :from AND :to '
        'UNION ALL SELECT a.crop_cycle_id, a.amount_paise FROM labour_entries l '
        'JOIN labour_allocations a ON a.labour_entry_id = l.id AND a.deleted_at IS NULL '
        'WHERE l.farm_id = :farm AND l.deleted_at IS NULL AND l.crop_cycle_id IS NULL '
        'AND l.work_date BETWEEN :from AND :to) GROUP BY cycle',
    budgetMs: 150,
  ),
  ListQuery(
    'profit and loss for a season, sales',
    // income reaches a crop through the lots each sale drew from
    'SELECT l.crop_cycle_id, SUM(s.net_paise * sl.quantity / s.quantity) FROM sales s '
        'JOIN sale_lots sl ON sl.sale_id = s.id AND sl.deleted_at IS NULL '
        'JOIN lots l ON l.id = sl.lot_id '
        'WHERE s.farm_id = :farm AND s.deleted_at IS NULL AND s.sold_on BETWEEN :from AND :to '
        'GROUP BY l.crop_cycle_id',
    budgetMs: 150,
  ),
  ListQuery(
    'profit and loss for a season, other income',
    'SELECT crop_cycle_id, SUM(amount_paise) FROM other_income WHERE farm_id = :farm '
        'AND deleted_at IS NULL AND received_on BETWEEN :from AND :to GROUP BY crop_cycle_id',
    budgetMs: 150,
  ),
  ListQuery(
    'worker balance: wages',
    'SELECT SUM(amount_paise) FROM labour_entries WHERE worker_id = :worker AND deleted_at IS NULL',
  ),
  ListQuery(
    'worker balance: payments',
    'SELECT SUM(amount_paise) FROM labour_payments WHERE worker_id = :worker AND deleted_at IS NULL',
  ),
  ListQuery(
    'last time for a worker',
    'SELECT * FROM labour_entries WHERE worker_id = :worker AND deleted_at IS NULL '
        'ORDER BY work_date DESC LIMIT 1',
    ordered: true,
  ),
  ListQuery(
    'harvest teams',
    'SELECT * FROM labour_entries WHERE harvest_id = :row AND deleted_at IS NULL',
  ),
  ListQuery(
    'lots with stock left',
    // stock is derived, so no index can hold "has stock left"; reading only the
    // lots of active crop cycles keeps this from growing with every season
    'SELECT l.id, l.quantity - COALESCE((SELECT SUM(s.quantity) FROM sale_lots s '
        'WHERE s.lot_id = l.id AND s.deleted_at IS NULL), 0) AS stock_left '
        'FROM crop_cycles c JOIN lots l ON l.crop_cycle_id = c.id AND l.deleted_at IS NULL '
        "WHERE c.farm_id = :farm AND c.status = 'active' AND c.deleted_at IS NULL "
        'AND stock_left > 0',
  ),
  ListQuery(
    'crop cycles on a plot',
    "SELECT * FROM crop_cycles WHERE plot_id = :row AND status = 'active' AND deleted_at IS NULL",
  ),
  ListQuery(
    'upload queue',
    "SELECT * FROM outbox WHERE status = 'pending' ORDER BY created_at LIMIT 200",
    ordered: true,
  ),
];

// ---------- land (screens 4, 18) ----------

const qPlots = ListQuery(
  'plots of a farm',
  'SELECT * FROM plots WHERE farm_id = :farm AND deleted_at IS NULL '
      'ORDER BY name',
  ordered: true,
);

const qFarmCycles = ListQuery(
  'crop cycles growing on a farm',
  'SELECT c.*, k.name_ml, k.name_en, k.kind FROM crop_cycles c '
      'JOIN crops k ON k.id = c.crop_id WHERE c.farm_id = :farm '
      "AND c.deleted_at IS NULL AND c.status IN ('active', 'planned') "
      'ORDER BY c.created_at, c.id',
);

const qPlotCycles = ListQuery(
  'crop cycles on a plot, closed seasons last',
  'SELECT c.*, k.name_ml, k.name_en, k.kind FROM crop_cycles c '
      'JOIN crops k ON k.id = c.crop_id WHERE c.plot_id = :plot '
      "AND c.deleted_at IS NULL ORDER BY c.status = 'closed', c.created_at, c.id",
);

const qOpenTasks = ListQuery(
  'open tasks of a farm by due day',
  // later rows win: the earliest due day comes last
  'SELECT COALESCE(t.plot_id, c.plot_id) AS plot, t.title, t.due_on '
      'FROM tasks t LEFT JOIN crop_cycles c ON c.id = t.crop_cycle_id '
      'WHERE t.farm_id = :farm AND t.deleted_at IS NULL AND t.done_at IS NULL '
      'ORDER BY t.due_on DESC, t.id DESC LIMIT 200',
  ordered: true,
);

const _family =
    '(SELECT id FROM workers WHERE farm_id = :farm AND is_family = 1 '
    'AND deleted_at IS NULL)';

const qCycleTotals = ListQuery(
  'cost of each crop cycle on a plot',
  // Deleting an expense or labour entry deletes its allocations in the same
  // save, so live allocations alone give the cost. Labour on one crop cycle
  // carries it on the entry; labour split across a mixed plot has none, and
  // its allocations carry the parts. Family labour stays out.
  'SELECT c.id, '
      '(SELECT COALESCE(SUM(a.amount_paise), 0) FROM expense_allocations a '
      'WHERE a.crop_cycle_id = c.id AND a.deleted_at IS NULL) AS expense, '
      '(SELECT COALESCE(SUM(l.amount_paise), 0) FROM labour_entries l '
      'WHERE l.crop_cycle_id = c.id AND l.deleted_at IS NULL '
      "AND COALESCE(l.worker_id, '') NOT IN $_family) + "
      '(SELECT COALESCE(SUM(a.amount_paise), 0) FROM labour_allocations a '
      'JOIN labour_entries l ON l.id = a.labour_entry_id '
      'WHERE a.crop_cycle_id = c.id AND a.deleted_at IS NULL '
      "AND COALESCE(l.worker_id, '') NOT IN $_family) AS labour "
      'FROM crop_cycles c WHERE c.plot_id = :plot AND c.deleted_at IS NULL '
      'ORDER BY c.created_at, c.id',
);

const qPlotYields = ListQuery(
  'harvested quantity of each crop cycle on a plot',
  'SELECT h.crop_cycle_id AS cycle, h.unit, SUM(h.quantity) AS q '
      'FROM crop_cycles c JOIN harvests h ON h.crop_cycle_id = c.id '
      'AND h.deleted_at IS NULL '
      'WHERE c.plot_id = :plot AND c.deleted_at IS NULL '
      'GROUP BY h.crop_cycle_id, h.unit',
);

const qPlotCosts = ListQuery(
  'costs of a plot this season by category',
  'SELECT code, SUM(paise) AS paise FROM ('
      'SELECT e.category_code AS code, a.amount_paise AS paise '
      'FROM crop_cycles c JOIN expense_allocations a ON a.crop_cycle_id = c.id '
      'AND a.deleted_at IS NULL '
      'JOIN expenses e ON e.id = a.expense_id '
      "WHERE c.plot_id = :plot AND c.deleted_at IS NULL AND c.status <> 'closed' "
      'UNION ALL '
      "SELECT 'wages', l.amount_paise FROM crop_cycles c "
      'JOIN labour_entries l ON l.crop_cycle_id = c.id AND l.deleted_at IS NULL '
      "WHERE c.plot_id = :plot AND c.deleted_at IS NULL AND c.status <> 'closed' "
      "AND COALESCE(l.worker_id, '') NOT IN $_family "
      'UNION ALL '
      "SELECT 'wages', a.amount_paise FROM crop_cycles c "
      'JOIN labour_allocations a ON a.crop_cycle_id = c.id '
      'AND a.deleted_at IS NULL '
      'JOIN labour_entries l ON l.id = a.labour_entry_id '
      "WHERE c.plot_id = :plot AND c.deleted_at IS NULL AND c.status <> 'closed' "
      "AND COALESCE(l.worker_id, '') NOT IN $_family"
      ') GROUP BY code HAVING SUM(paise) <> 0 ORDER BY paise DESC, code',
);

const qLatestPrice = ListQuery(
  'latest price of a crop',
  'SELECT price_paise, unit, published_at FROM market_prices '
      'WHERE crop_id = :row AND deleted_at IS NULL '
      'AND (farm_id IS NULL OR farm_id = :farm) '
      'ORDER BY published_at DESC LIMIT 1',
);

const qPlotHistory = ListQuery(
  'recent history of a plot',
  'SELECT entity, "action", occurred_on, summary FROM event_log '
      // a window of recent days, so a quiet plot never reads the whole
      // farm's history; the full history screen pages through the rest
      'WHERE farm_id = :farm AND occurred_on >= :from AND (entity_id = :plot '
      r"OR json_extract(summary, '$.plot_id') = :plot) "
      "AND entity NOT LIKE '%allocations' "
      'ORDER BY occurred_on DESC, created_at DESC, id DESC LIMIT :limit',
  ordered: true,
);

const landQueries = [
  qPlots,
  qFarmCycles,
  qPlotCycles,
  qOpenTasks,
  qCycleTotals,
  qPlotYields,
  qPlotCosts,
  qLatestPrice,
  qPlotHistory,
];

// ---------- labour (screens 8, 11) ----------

const _paidOrDeducted =
    "SUM(CASE WHEN kind IN ('advance', 'part', 'settlement', 'deduction') "
    'THEN amount_paise ELSE 0 END)';

const qWorkers = ListQuery(
  'workers of a farm with what each is owed',
  'SELECT w.*, '
      '(SELECT COALESCE(SUM(amount_paise), 0) FROM labour_entries l '
      'WHERE l.worker_id = w.id AND l.deleted_at IS NULL) - '
      '(SELECT COALESCE($_paidOrDeducted, 0) FROM labour_payments p '
      'WHERE p.worker_id = w.id AND p.deleted_at IS NULL) AS balance '
      'FROM workers w WHERE w.farm_id = :farm AND w.deleted_at IS NULL '
      'ORDER BY w.name',
  ordered: true,
);

const qGroups = ListQuery(
  'groups of a farm with what each is owed',
  'SELECT g.*, '
      '(SELECT COALESCE(SUM(amount_paise), 0) FROM labour_entries l '
      'WHERE l.group_id = g.id AND l.deleted_at IS NULL) - '
      '(SELECT COALESCE($_paidOrDeducted, 0) FROM labour_payments p '
      'WHERE p.group_id = g.id AND p.deleted_at IS NULL) AS balance '
      'FROM labour_groups g WHERE g.farm_id = :farm AND g.deleted_at IS NULL '
      'ORDER BY g.label',
  ordered: true,
);

const qGroupMembers = ListQuery(
  'members of the groups',
  'SELECT m.group_id, m.worker_id FROM labour_groups g '
      'JOIN labour_group_members m ON m.group_id = g.id '
      'AND m.deleted_at IS NULL '
      'WHERE g.farm_id = :farm AND g.deleted_at IS NULL '
      'ORDER BY g.label',
  ordered: true,
);

const qWorkerDays = ListQuery(
  "a worker's days of work",
  'SELECT id, work_date, amount_paise, attendance, overtime_hours, head_count '
      'FROM labour_entries WHERE worker_id = :worker AND deleted_at IS NULL '
      'ORDER BY work_date DESC LIMIT 100',
  ordered: true,
);

const qGroupDays = ListQuery(
  "a group's days of work",
  'SELECT id, work_date, amount_paise, attendance, overtime_hours, head_count '
      'FROM labour_entries WHERE group_id = :group AND deleted_at IS NULL '
      'ORDER BY work_date DESC LIMIT 100',
  ordered: true,
);

const qWorkerPayments = ListQuery(
  "a worker's payments",
  'SELECT id, paid_on, kind, amount_paise FROM labour_payments '
      'WHERE worker_id = :worker AND deleted_at IS NULL '
      'ORDER BY paid_on DESC LIMIT 100',
  ordered: true,
);

const qGroupPayments = ListQuery(
  "a group's payments",
  'SELECT id, paid_on, kind, amount_paise FROM labour_payments '
      'WHERE group_id = :group AND deleted_at IS NULL '
      'ORDER BY paid_on DESC LIMIT 100',
  ordered: true,
);

const qLastLabourDay = ListQuery(
  "the named workers' last day of work before a day",
  'SELECT worker_id, attendance, overtime_hours, overtime_rate_paise, '
      'rate_paise FROM labour_entries WHERE farm_id = :farm '
      'AND worker_id IS NOT NULL AND deleted_at IS NULL AND work_date = '
      '(SELECT MAX(work_date) FROM labour_entries WHERE farm_id = :farm '
      'AND worker_id IS NOT NULL AND deleted_at IS NULL AND work_date < :day)',
);

const qLastLabour = ListQuery(
  'the latest labour entry, for its plot and task',
  'SELECT plot_id, task_code FROM labour_entries WHERE farm_id = :farm '
      'AND deleted_at IS NULL ORDER BY work_date DESC, id DESC LIMIT 1',
  ordered: true,
);

const labourQueries = [
  qWorkers,
  qGroups,
  qGroupMembers,
  qWorkerDays,
  qGroupDays,
  qWorkerPayments,
  qGroupPayments,
  qLastLabourDay,
  qLastLabour,
];

// ---------- expenses (screen 9) ----------

const qCategoryUse = ListQuery(
  'expense categories by use since a day',
  'SELECT category_code, COUNT(*) AS n FROM expenses WHERE farm_id = :farm '
      'AND deleted_at IS NULL AND spent_on >= :from '
      'GROUP BY category_code ORDER BY n DESC',
);

const qLastExpense = ListQuery(
  'the latest expense, for its plot',
  'SELECT plot_id, category_code, mode FROM expenses WHERE farm_id = :farm '
      'AND deleted_at IS NULL ORDER BY spent_on DESC, id DESC LIMIT 1',
  ordered: true,
);

const qPayables = ListQuery(
  'expenses bought on credit with what is still owed, newest first',
  'SELECT e.id, e.spent_on, e.category_code, e.amount_paise, '
      'e.vendor_party_id, e.due_on, e.amount_paise - '
      '(SELECT COALESCE(SUM(p.amount_paise), 0) FROM expense_payments p '
      'WHERE p.expense_id = e.id AND p.deleted_at IS NULL) AS owed '
      'FROM expenses e WHERE e.farm_id = :farm AND e.deleted_at IS NULL '
      "AND e.mode = 'credit' ORDER BY e.spent_on DESC, e.id DESC LIMIT 50",
  ordered: true,
);

const qExpenseParts = ListQuery(
  'the crop parts of an expense',
  'SELECT crop_cycle_id, amount_paise, is_manual FROM expense_allocations '
      'WHERE expense_id = :row AND deleted_at IS NULL ORDER BY created_at, id',
);

const expenseQueries = [qCategoryUse, qLastExpense, qPayables, qExpenseParts];

// ---------- running them ----------

/// Turns `:name` parameters into `?` with values from [values]; a name with
/// no value (when only planning) gets a placeholder.
(String, List<Variable>) bindNamed(String sql, Map<String, Object?> values) {
  final args = <Variable>[];
  final out = sql.replaceAllMapped(RegExp(r':(\w+)'), (m) {
    final v = values.containsKey(m.group(1)) ? values[m.group(1)] : 'x';
    args.add(switch (v) {
      null => const Variable(null),
      final int i => Variable.withInt(i),
      _ => Variable.withString('$v'),
    });
    return '?';
  });
  return (out, args);
}

/// The rows of [q] with [values].
Future<List<QueryRow>> select(
  AppDatabase db,
  ListQuery q,
  Map<String, Object?> values,
) {
  final (sql, args) = bindNamed(q.sql, values);
  return db.customSelect(sql, variables: args).get();
}
