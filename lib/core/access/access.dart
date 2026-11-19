/// Who may read and write what (product spec rule 7), the same rules the
/// server applies in `public.access_level` (supabase/migrations/0001_init.sql),
/// so screens hide what a role cannot open and refuse what it cannot write
/// before the server would.
library;

enum AccessClass { setup, team, daily, stock, money, prices, members }

/// Each synced table's access class, as `public.sync_tables` lists them.
const tableAccess = {
  'farms': AccessClass.setup,
  'farm_members': AccessClass.members,
  'farm_invites': AccessClass.members,
  'crops': AccessClass.setup,
  'template_overrides': AccessClass.setup,
  'plots': AccessClass.setup,
  'crop_cycles': AccessClass.setup,
  'parties': AccessClass.money,
  'workers': AccessClass.team,
  'labour_groups': AccessClass.team,
  'labour_group_members': AccessClass.team,
  'harvests': AccessClass.daily,
  'labour_entries': AccessClass.daily,
  'expenses': AccessClass.money,
  'notes': AccessClass.daily,
  'tasks': AccessClass.daily,
  'market_prices': AccessClass.prices,
  'price_alerts': AccessClass.prices,
  'lots': AccessClass.stock,
  'lot_costs': AccessClass.money,
  'sales': AccessClass.money,
  'sale_lots': AccessClass.money,
  'labour_allocations': AccessClass.daily,
  'expense_allocations': AccessClass.money,
  'labour_payments': AccessClass.money,
  'expense_payments': AccessClass.money,
  'sale_payments': AccessClass.money,
  'other_income': AccessClass.money,
  'input_items': AccessClass.stock,
  'input_applications': AccessClass.daily,
  'stock_movements': AccessClass.stock,
  'input_application_costs': AccessClass.money,
  'soil_tests': AccessClass.daily,
};

/// 0 none, 1 read, 2 write. The owner writes everything; a per-person
/// permission ("write", "read" or "none") wins over the role default.
int accessLevel(String role, Map<String, Object?> permissions, AccessClass c) {
  if (role == 'owner') return 2;
  switch (permissions[c.name]) {
    case 'write':
      return 2;
    case 'read':
      return 1;
    case 'none':
      return 0;
  }
  return switch (c) {
    AccessClass.setup => role == 'manager' ? 2 : 1,
    AccessClass.team ||
    AccessClass.daily => role == 'manager' || role == 'supervisor' ? 2 : 1,
    AccessClass.stock => role == 'viewer' ? 1 : 2,
    AccessClass.money => switch (role) {
      'manager' || 'accountant' => 2,
      'supervisor' => 0,
      _ => 1,
    },
    AccessClass.prices => role == 'manager' || role == 'accountant' ? 2 : 1,
    AccessClass.members => 0,
  };
}

/// The signed-in person's access on the open farm.
class Access {
  const Access(this.role, [this.permissions = const {}]);

  /// No membership (yet): reads and writes nothing.
  static const none = Access('');

  final String role;
  final Map<String, Object?> permissions;

  int _level(AccessClass c) =>
      role.isEmpty ? 0 : accessLevel(role, permissions, c);

  bool canRead(AccessClass c) => _level(c) >= 1;
  bool canWrite(AccessClass c) => _level(c) >= 2;
}
