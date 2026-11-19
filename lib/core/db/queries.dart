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
  /// :row, :from, :to, :day, :id, :limit, :user), bound by [bindNamed].
  final String sql;

  /// A page in index order: must not sort in a temporary b-tree.
  final bool ordered;
  final int budgetMs;
}

const listQueries = [
  ...landQueries,
  ...labourQueries,
  ...expenseQueries,
  ...harvestQueries,
  ...saleQueries,
  ...historyQueries,
  ...moneyQueries,
  ...homeQueries,
  ...priceQueries,
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
  'SELECT price_paise, unit, published_at, source FROM market_prices '
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
    "SUM(CASE WHEN kind IN ('advance', 'part_payment', 'settlement', 'deduction') "
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

// ---------- harvest and lots (screen 12) ----------

const qPreviousHarvest = ListQuery(
  "the crop cycle's harvest before this one",
  'SELECT harvested_on FROM harvests WHERE crop_cycle_id = :cycle '
      'AND deleted_at IS NULL AND (harvested_on, id) < (:day, :id) '
      // only the day is used, so a same-day tie may go either way
      'ORDER BY harvested_on DESC LIMIT 1',
  ordered: true,
);

const qCostsSince = ListQuery(
  'costs posted to a crop cycle between two harvests',
  // rule 9: after the previous harvest's day, up to and including this
  // one's; harvest teams are counted with their own harvest, family out
  'SELECT '
      '(SELECT COALESCE(SUM(a.amount_paise), 0) FROM expense_allocations a '
      'JOIN expenses e ON e.id = a.expense_id '
      'WHERE a.crop_cycle_id = :cycle AND a.deleted_at IS NULL '
      'AND e.spent_on > :from AND e.spent_on <= :day) + '
      '(SELECT COALESCE(SUM(l.amount_paise), 0) FROM labour_entries l '
      'WHERE l.crop_cycle_id = :cycle AND l.deleted_at IS NULL '
      'AND l.work_date > :from AND l.work_date <= :day '
      'AND l.harvest_id IS NULL '
      "AND COALESCE(l.worker_id, '') NOT IN $_family) + "
      '(SELECT COALESCE(SUM(a.amount_paise), 0) FROM labour_allocations a '
      'JOIN labour_entries l ON l.id = a.labour_entry_id '
      'WHERE a.crop_cycle_id = :cycle AND a.deleted_at IS NULL '
      'AND l.work_date > :from AND l.work_date <= :day '
      'AND l.harvest_id IS NULL '
      "AND COALESCE(l.worker_id, '') NOT IN $_family) AS costs",
);

const qHarvestTeams = ListQuery(
  "a harvest's teams",
  'SELECT l.*, w.name AS worker_name, w.is_family, g.label AS group_label '
      'FROM labour_entries l LEFT JOIN workers w ON w.id = l.worker_id '
      'LEFT JOIN labour_groups g ON g.id = l.group_id '
      'WHERE l.harvest_id = :row AND l.deleted_at IS NULL '
      'ORDER BY l.created_at, l.id',
);

const qLastHarvest = ListQuery(
  'the last harvest of a crop cycle, for the "last time" banner',
  'SELECT h.id, h.harvested_on, h.quantity, h.unit, '
      '(SELECT COALESCE(SUM(head_count), 0) FROM labour_entries l '
      'WHERE l.harvest_id = h.id AND l.deleted_at IS NULL) AS people '
      'FROM harvests h WHERE h.crop_cycle_id = :cycle AND h.deleted_at IS NULL '
      'ORDER BY h.harvested_on DESC LIMIT 1',
  ordered: true,
);

const qPendingLotCosts = ListQuery(
  'lots whose cost is not yet worked out for their teams',
  // a lot saved, or its teams edited, by someone who cannot write money
  'SELECT l.id, l.harvest_id, l.teams_stamp, c.cost_overridden, '
      'c.cost_paise, c.id AS cost_id FROM crop_cycles y '
      'JOIN lots l ON l.crop_cycle_id = y.id AND l.deleted_at IS NULL '
      'LEFT JOIN lot_costs c ON c.id = l.id '
      "WHERE y.farm_id = :farm AND y.status IN ('active', 'planned') "
      'AND y.deleted_at IS NULL AND l.harvest_id IS NOT NULL '
      'AND (c.id IS NULL OR c.teams_stamp IS NOT l.teams_stamp)',
);

const harvestQueries = [
  qPreviousHarvest,
  qCostsSince,
  qHarvestTeams,
  qLastHarvest,
  qPendingLotCosts,
];

// ---------- selling (screen 13) ----------

const qLotsInStock = ListQuery(
  'lots with stock to sell, oldest first, with their cost',
  // stock is derived, so no index holds "has stock left"; reading only the
  // lots of growing crops keeps this from growing with every season
  'SELECT l.id, l.quantity, l.unit, l.crop_cycle_id, k.id AS crop_id, '
      'k.name_ml, k.name_en, h.harvested_on, c.cost_paise, '
      '(c.id IS NULL OR l.teams_stamp IS NOT c.teams_stamp) AS cost_pending, '
      'l.quantity - COALESCE((SELECT SUM(s.quantity) FROM sale_lots s '
      'WHERE s.lot_id = l.id AND s.deleted_at IS NULL), 0) AS stock '
      'FROM crop_cycles y JOIN lots l ON l.crop_cycle_id = y.id '
      'AND l.deleted_at IS NULL '
      'JOIN crops k ON k.id = y.crop_id '
      'LEFT JOIN harvests h ON h.id = l.harvest_id '
      'LEFT JOIN lot_costs c ON c.id = l.id AND c.deleted_at IS NULL '
      "WHERE y.farm_id = :farm AND y.status IN ('active', 'planned') "
      'AND y.deleted_at IS NULL AND stock > 0 ORDER BY l.created_at, l.id',
);

const qBuyers = ListQuery(
  'buyers with what each still owes',
  'SELECT p.id, p.name, p.phone, '
      '(SELECT COALESCE(SUM(s.net_paise), 0) FROM sales s '
      'WHERE s.buyer_party_id = p.id AND s.deleted_at IS NULL) - '
      '(SELECT COALESCE(SUM(sp.amount_paise), 0) FROM sales s '
      'JOIN sale_payments sp ON sp.sale_id = s.id AND sp.deleted_at IS NULL '
      'WHERE s.buyer_party_id = p.id AND s.deleted_at IS NULL) AS due '
      "FROM parties p WHERE p.farm_id = :farm AND p.kind = 'buyer' "
      'AND p.deleted_at IS NULL ORDER BY p.kind, p.name',
  ordered: true,
);

const qBuyerSales = ListQuery(
  "a buyer's sales with what is still owed on each, newest first",
  'SELECT s.id, s.sold_on, s.quantity, s.unit, s.net_paise, s.net_paise - '
      '(SELECT COALESCE(SUM(sp.amount_paise), 0) FROM sale_payments sp '
      'WHERE sp.sale_id = s.id AND sp.deleted_at IS NULL) AS due '
      'FROM sales s WHERE s.buyer_party_id = :row AND s.deleted_at IS NULL '
      'ORDER BY s.sold_on DESC LIMIT 100',
  ordered: true,
);

const qLastSale = ListQuery(
  'the latest sale, for its buyer type and payment mode',
  'SELECT sale_type, mode FROM sales WHERE farm_id = :farm '
      'AND deleted_at IS NULL ORDER BY sold_on DESC, id DESC LIMIT 1',
  ordered: true,
);

const saleQueries = [qLotsInStock, qBuyers, qBuyerSales, qLastSale];

// ---------- history (screen 15) ----------

const qDiaryPage = ListQuery(
  'farm diary page, by filter',
  // a page after (day, time, id), in index order; the filters only drop
  // rows as the index is walked. Rows saved as part of another record (a
  // harvest's teams, the payment made with a sale) show through it.
  'SELECT id, entity, entity_id, "action", summary, old_values, new_values, '
      'occurred_on, created_at, created_by FROM event_log '
      'WHERE farm_id = :farm '
      'AND (occurred_on, created_at, id) < (:day, :created, :id) '
      "AND instr(:entities, ',' || entity || ',') > 0 "
      "AND instr(:actions, ',' || \"action\" || ',') > 0 "
      "AND (:onplot = '' OR entity_id = :onplot "
      r"OR json_extract(summary, '$.plot_id') = :onplot) "
      r"AND json_extract(summary, '$.part_of') IS NULL "
      'ORDER BY occurred_on DESC, created_at DESC, id DESC LIMIT :limit',
  ordered: true,
);

const qDiaryRange = ListQuery(
  'how many diary entries in a range of days',
  'SELECT COUNT(*) AS n FROM event_log WHERE farm_id = :farm '
      'AND occurred_on BETWEEN :from AND :to '
      "AND instr(:entities, ',' || entity || ',') > 0 "
      r"AND json_extract(summary, '$.part_of') IS NULL",
);

const qRecordEvents = ListQuery(
  "one record's history, newest first",
  'SELECT id, entity, entity_id, "action", summary, old_values, new_values, '
      'occurred_on, created_at, created_by FROM event_log '
      'WHERE entity = :entity AND entity_id = :row '
      'ORDER BY created_at DESC LIMIT 100',
  ordered: true,
);

const qChangedSince = ListQuery(
  'whether a record changed after one of its history rows',
  'SELECT COUNT(*) AS n FROM event_log WHERE entity = :entity '
      'AND entity_id = :row AND created_at > :created',
);

const historyQueries = [qDiaryPage, qDiaryRange, qRecordEvents, qChangedSince];

// ---------- money (screen 5) ----------

const qProfitAndLoss = ListQuery(
  'profit and loss of each crop cycle for a period',
  // Each money row lands on a crop cycle, or on none (cycle null) with the
  // plot it was entered on. :plot '' means every plot. Deleted plots and
  // crop cycles keep their money (C2), so cycles are not filtered on
  // deleted_at. Family labour comes back on its own, for the switch.
  'SELECT cycle, c.crop_id AS crop, r.name_ml, r.name_en, '
      'SUM(income) AS income, SUM(expense) AS expense, '
      'SUM(paid) AS paid, SUM(family) AS family FROM ('
      // a sale's net amount, split across the lots it drew from by quantity,
      // the paise left over going one each to the largest remainders, so
      // the parts add up to the sale; a sale from no lot is on no crop
      'SELECT cycle, NULL AS plot, base + (rk <= spare) AS income, '
      '0 AS expense, 0 AS paid, 0 AS family FROM ('
      'SELECT cycle, base, ROW_NUMBER() OVER '
      '(PARTITION BY sale ORDER BY rem DESC, part) AS rk, '
      'net - SUM(base) OVER (PARTITION BY sale) AS spare FROM ('
      'SELECT s.id AS sale, sl.id AS part, l.crop_cycle_id AS cycle, '
      's.net_paise AS net, s.net_paise * COALESCE(sl.quantity, 1) / '
      'SUM(COALESCE(sl.quantity, 1)) OVER (PARTITION BY s.id) AS base, '
      's.net_paise * COALESCE(sl.quantity, 1) % '
      'SUM(COALESCE(sl.quantity, 1)) OVER (PARTITION BY s.id) AS rem '
      'FROM sales s LEFT JOIN sale_lots sl ON sl.sale_id = s.id '
      'AND sl.deleted_at IS NULL LEFT JOIN lots l ON l.id = sl.lot_id '
      'WHERE s.farm_id = :farm AND s.deleted_at IS NULL '
      'AND s.sold_on BETWEEN :from AND :to)) '
      'UNION ALL '
      'SELECT crop_cycle_id, NULL, amount_paise, 0, 0, 0 FROM other_income '
      'WHERE farm_id = :farm AND deleted_at IS NULL '
      'AND received_on BETWEEN :from AND :to '
      'UNION ALL '
      // an expense's parts on crop cycles, and what is on none
      'SELECT a.crop_cycle_id, NULL, 0, a.amount_paise, 0, 0 FROM expenses e '
      'JOIN expense_allocations a ON a.expense_id = e.id '
      'AND a.deleted_at IS NULL '
      'WHERE e.farm_id = :farm AND e.deleted_at IS NULL '
      'AND e.spent_on BETWEEN :from AND :to '
      'UNION ALL '
      'SELECT NULL, e.plot_id, 0, e.amount_paise - '
      '(SELECT COALESCE(SUM(a.amount_paise), 0) FROM expense_allocations a '
      'WHERE a.expense_id = e.id AND a.deleted_at IS NULL), 0, 0 '
      'FROM expenses e WHERE e.farm_id = :farm AND e.deleted_at IS NULL '
      'AND e.spent_on BETWEEN :from AND :to '
      'UNION ALL '
      // labour on one crop cycle carries it on the entry; labour split
      // across a mixed plot has none and its allocations carry the parts
      'SELECT a.crop_cycle_id, NULL, 0, 0, '
      "CASE WHEN COALESCE(l.worker_id, '') IN $_family THEN 0 "
      'ELSE a.amount_paise END, '
      "CASE WHEN COALESCE(l.worker_id, '') IN $_family THEN a.amount_paise "
      'ELSE 0 END FROM labour_entries l '
      'JOIN labour_allocations a ON a.labour_entry_id = l.id '
      'AND a.deleted_at IS NULL '
      'WHERE l.farm_id = :farm AND l.deleted_at IS NULL '
      'AND l.crop_cycle_id IS NULL AND l.work_date BETWEEN :from AND :to '
      'UNION ALL '
      'SELECT cycle, plot, 0, 0, '
      "CASE WHEN fam THEN 0 ELSE paise END, CASE WHEN fam THEN paise ELSE 0 END "
      'FROM (SELECT l.crop_cycle_id AS cycle, l.plot_id AS plot, '
      "COALESCE(l.worker_id, '') IN $_family AS fam, "
      'l.amount_paise - CASE WHEN l.crop_cycle_id IS NULL THEN '
      '(SELECT COALESCE(SUM(a.amount_paise), 0) FROM labour_allocations a '
      'WHERE a.labour_entry_id = l.id AND a.deleted_at IS NULL) '
      'ELSE 0 END AS paise FROM labour_entries l '
      'WHERE l.farm_id = :farm AND l.deleted_at IS NULL '
      'AND l.work_date BETWEEN :from AND :to)'
      ') LEFT JOIN crop_cycles c ON c.id = cycle '
      'LEFT JOIN crops r ON r.id = c.crop_id '
      "WHERE :plot = '' OR COALESCE(c.plot_id, plot) = :plot "
      'GROUP BY cycle HAVING SUM(income) <> 0 OR SUM(expense) <> 0 '
      'OR SUM(paid) <> 0 OR SUM(family) <> 0',
  budgetMs: 150,
);

const moneyQueries = [qProfitAndLoss];

// ---------- home (screen 2) ----------

const qTodayTasks = ListQuery(
  "today's tasks",
  // open tasks due today or before, and those ticked since :created (the
  // start of today), so a tick can be taken back the same day
  'SELECT t.id, t.title, t.due_on, t.done_at, t.crop_cycle_id, '
      'COALESCE(t.plot_id, c.plot_id) AS plot_id, p.name AS plot, '
      'r.name_ml AS crop_ml, r.name_en AS crop_en '
      'FROM tasks t LEFT JOIN crop_cycles c ON c.id = t.crop_cycle_id '
      'LEFT JOIN plots p ON p.id = COALESCE(t.plot_id, c.plot_id) '
      'LEFT JOIN crops r ON r.id = c.crop_id '
      'WHERE t.farm_id = :farm AND t.deleted_at IS NULL AND t.due_on <= :day '
      'AND (t.done_at IS NULL OR t.done_at >= :created) '
      'ORDER BY t.due_on, t.id LIMIT 50',
  ordered: true,
);

const homeQueries = [qTodayTasks];

// ---------- prices (screen 14) ----------

const qCropPrices = ListQuery(
  "a crop's recent prices",
  // official prices and this farm's own shop rates, newest first; enough
  // for the latest, its change, every market and 30 days of the line
  'SELECT price_paise, unit, market, source, published_at, farm_id '
      'FROM market_prices WHERE crop_id = :row AND deleted_at IS NULL '
      'AND (farm_id IS NULL OR farm_id = :farm) '
      'ORDER BY published_at DESC LIMIT 200',
);

const qPriceAlert = ListQuery(
  "a person's price alert on a crop",
  'SELECT id, threshold_paise, is_active FROM price_alerts '
      'WHERE crop_id = :row AND farm_id = :farm AND user_id = :user '
      'AND deleted_at IS NULL ORDER BY updated_at DESC LIMIT 1',
);

const priceQueries = [qCropPrices, qPriceAlert];

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
