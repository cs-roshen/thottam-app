/// The synced tables in dependency order (parents first), with the column
/// that holds each row's farm. Mirrors `public.sync_tables` in
/// `supabase/migrations/0001_init.sql` and later migrations; the schema check
/// test keeps them equal.
const syncedTables = <(String, String?)>[
  ('template_items', null),
  ('farms', 'id'),
  ('farm_members', 'farm_id'),
  ('farm_invites', 'farm_id'),
  ('crops', 'owner_farm_id'),
  ('template_overrides', 'farm_id'),
  ('plots', 'farm_id'),
  ('crop_cycles', 'farm_id'),
  ('parties', 'farm_id'),
  ('workers', 'farm_id'),
  ('labour_groups', 'farm_id'),
  ('labour_group_members', 'farm_id'),
  ('harvests', 'farm_id'),
  ('labour_entries', 'farm_id'),
  ('expenses', 'farm_id'),
  ('notes', 'farm_id'),
  ('tasks', 'farm_id'),
  ('market_prices', 'farm_id'),
  ('price_alerts', 'farm_id'),
  ('lots', 'farm_id'),
  ('lot_costs', 'farm_id'),
  ('sales', 'farm_id'),
  ('sale_lots', 'farm_id'),
  ('labour_allocations', 'farm_id'),
  ('expense_allocations', 'farm_id'),
  ('labour_payments', 'farm_id'),
  ('expense_payments', 'farm_id'),
  ('sale_payments', 'farm_id'),
  ('other_income', 'farm_id'),
  ('input_items', 'farm_id'),
  ('input_applications', 'farm_id'),
  ('stock_movements', 'farm_id'),
  ('soil_tests', 'farm_id'),
  ('event_log', 'farm_id'),
];

/// Columns every farm-owned synced row carries; the history path sets them.
const commonColumns = {
  'id',
  'farm_id',
  'created_at',
  'created_by',
  'updated_at',
  'updated_by',
  'version',
  'deleted_at',
};
