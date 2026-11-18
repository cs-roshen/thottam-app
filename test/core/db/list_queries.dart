/// The list and total queries the screens will run, with the shapes section 12
/// asks for (keyset pages, totals in SQL, partial indexes on live rows).
/// The query-plan test checks each uses an index; the benchmark test times
/// each with the seed loaded. Repositories add theirs here as they are built.
class ListQuery {
  const ListQuery(
    this.name,
    this.sql, {
    this.ordered = false,
    this.budgetMs = 50,
  });

  final String name;

  /// Uses :farm, :cycle, :worker, :entity, :row, :from, :to, :day, :id.
  final String sql;

  /// A page in index order: must not sort in a temporary b-tree.
  final bool ordered;
  final int budgetMs;
}

const listQueries = [
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
    'SELECT SUM(amount_paise) FROM expense_allocations '
        'WHERE crop_cycle_id = :cycle AND deleted_at IS NULL',
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
    'SELECT crop_cycle_id, SUM(amount_paise) FROM labour_entries '
        'WHERE farm_id = :farm AND deleted_at IS NULL AND work_date BETWEEN :from AND :to '
        'GROUP BY crop_cycle_id',
    budgetMs: 150,
  ),
  ListQuery(
    'profit and loss for a season, sales',
    'SELECT SUM(net_paise) FROM sales WHERE farm_id = :farm AND deleted_at IS NULL '
        'AND sold_on BETWEEN :from AND :to',
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
    'SELECT l.id, l.quantity - COALESCE((SELECT SUM(s.quantity) FROM sale_lots s '
        'WHERE s.lot_id = l.id AND s.deleted_at IS NULL), 0) AS stock_left '
        'FROM lots l WHERE l.farm_id = :farm AND l.deleted_at IS NULL AND stock_left > 0',
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
