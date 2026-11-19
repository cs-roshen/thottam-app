import 'dart:math';

import '../ids/uuid_v7.dart';
import '../money/money.dart';

/// Rows per table, keyed by table name, with the columns of the schema in
/// `lib/core/db/tables.drift` (timestamps as DateTime, JSON as maps and lists).
typedef SeedTables = Map<String, List<Map<String, Object?>>>;

/// [years] of realistic data for one farm, three by default (implementation
/// plan section 14), for benchmarks and tests only; never shipped to
/// farmers. The same [seed] always gives the same rows. B2 inserts these into
/// Drift. Entry counts grow with [years] at the same pace per year.
SeedTables generateBenchmarkSeed({
  int seed = 42,
  DateTime? until,
  int years = 3,
}) => _Seed(Random(seed), until ?? DateTime.utc(2026, 11, 17), years).build();

class _Seed {
  _Seed(this.r, this.until, this.years)
    : from = until.subtract(Duration(days: years * 365));

  final Random r;
  final DateTime until;
  final int years;
  final DateTime from;
  final SeedTables t = {};
  final String user = '00000000-0000-7000-8000-000000000001';
  late final String farmId;

  int _clock = 0;

  /// A creation time on [day], unique and increasing so ids stay ordered.
  DateTime _at(DateTime day) =>
      day.add(Duration(hours: 7, milliseconds: _clock++));

  DateTime _day(int i, int count) =>
      from.add(Duration(days: (i * years * 365) ~/ count));

  /// [perThreeYears] scaled to [years].
  int _n(int perThreeYears) => perThreeYears * years ~/ 3;

  String _date(DateTime d) => d.toIso8601String().substring(0, 10);

  Map<String, Object?> _row(
    String table,
    DateTime day,
    Map<String, Object?> cols,
  ) {
    final at = _at(day);
    final row = <String, Object?>{
      'id': uuidV7(at, r),
      if (table != 'farms') 'farm_id': farmId,
      'created_at': at,
      'created_by': user,
      'updated_at': at,
      'updated_by': user,
      'version': 1,
      'deleted_at': null,
      ...cols,
    };
    (t[table] ??= []).add(row);
    _event(table, row['id']! as String, 'create', at, null, cols);
    return row;
  }

  void _event(
    String entity,
    String entityId,
    String action,
    DateTime at,
    Map<String, Object?>? oldValues,
    Map<String, Object?>? newValues,
  ) {
    (t['event_log'] ??= []).add({
      'id': uuidV7(at, r),
      'farm_id': farmId,
      'entity': entity,
      'entity_id': entityId,
      'action': action,
      'old_values': oldValues,
      'new_values': newValues,
      'occurred_on': _date(at),
      'created_at': at,
      'created_by': user,
    });
  }

  T _pick<T>(List<T> list) => list[r.nextInt(list.length)];

  SeedTables build() {
    final farm = <String, Object?>{
      'id': uuidV7(_at(from), r),
      'name': 'Thottam benchmark farm', // gate: not user-facing
      'created_at': from,
      'created_by': user,
      'updated_at': from,
      'updated_by': user,
      'version': 1,
      'deleted_at': null,
    };
    farmId = farm['id']! as String;
    t['farms'] = [farm];

    // Standard crops, as the first sync brings them from the templates.
    final crops = <String, String>{};
    for (final code in const [
      'coconut',
      'rubber',
      'pepper',
      'banana',
      'paddy',
      'cardamom',
    ]) {
      final at = _at(from);
      crops[code] = uuidV7(at, r);
      (t['crops'] ??= []).add({
        'id': crops[code],
        'code': code,
        'name_ml': code,
        'name_en': code,
        'kind': 'perennial',
        'owner_farm_id': null,
        'created_at': at,
        'updated_at': at,
        'version': 1,
      });
    }

    final plots = [
      for (var i = 0; i < 8; i++)
        _row('plots', from, {
          'name': 'plot_${i + 1}',
          'area': (25 + r.nextInt(400)) * 1000, // thousandths of a cent
          'area_unit': 'cent',
          'tenure': i == 7 ? 'leased' : 'owned',
        }),
    ];
    final cycles = [
      for (var i = 0; i < 20; i++)
        _row('crop_cycles', from, {
          'plot_id': plots[i % 8]['id'],
          'crop_id': _pick(crops.values.toList()),
          'area_share': i < 8 ? 60000 : 40000, // thousandths of a percent
          'status': 'active',
        }),
    ];
    final workers = [
      for (var i = 0; i < 40; i++)
        _row('workers', from, {
          'name': 'worker_${i + 1}',
          'default_rate_paise': (700 + r.nextInt(5) * 100) * 100,
        }),
    ];
    final groups = [
      for (var i = 0; i < 10; i++)
        _row('labour_groups', from, {
          'label': 'group_${i + 1}',
          'is_named': i < 4,
        }),
    ];

    for (var i = 0; i < _n(15000); i++) {
      final day = _day(i, _n(15000));
      final cycle = _pick(cycles);
      final byGroup = r.nextInt(5) == 0;
      final heads = byGroup ? 3 + r.nextInt(8) : 1;
      final attendance = byGroup ? 1000 : _pick([1000, 1000, 1000, 500, 0]);
      final rate = (700 + r.nextInt(5) * 100) * 100;
      final amount = mulDivRound(rate * heads, attendance, 1000);
      final onPlot = cycles
          .where((c) => c['plot_id'] == cycle['plot_id'])
          .toList();
      // about a quarter of the days on a mixed plot split across its crops
      final split = onPlot.length > 1 && r.nextInt(4) == 0;
      final entry = _row('labour_entries', day, {
        'work_date': _date(day),
        'worker_id': byGroup ? null : _pick(workers)['id'],
        'group_id': byGroup ? _pick(groups)['id'] : null,
        'crop_cycle_id': split ? null : cycle['id'],
        'plot_id': cycle['plot_id'],
        'head_count': heads,
        'attendance': attendance,
        'rate_paise': rate,
        'amount_paise': amount,
      });
      if (split) {
        for (final (c, share) in _split(amount, onPlot)) {
          _row('labour_allocations', day, {
            'labour_entry_id': entry['id'],
            'crop_cycle_id': c['id'],
            'amount_paise': share,
          });
        }
      }
      _maybeEdit('labour_entries', entry, 'rate_paise', rate + 5000, day);
    }

    for (var i = 0; i < _n(6000); i++) {
      final day = _day(i, _n(6000));
      final plot = _pick(plots);
      final amount = (50 + r.nextInt(5000)) * 100 + r.nextInt(100);
      final expense = _row('expenses', day, {
        'spent_on': _date(day),
        'plot_id': plot['id'],
        'category_code': _pick([
          'fertiliser',
          'wages',
          'seeds',
          'machinery',
          'transport',
        ]),
        'amount_paise': amount,
        'mode': _pick(['cash', 'upi', 'bank', 'credit']),
      });
      final onPlot = cycles.where((c) => c['plot_id'] == plot['id']).toList();
      for (final (cycle, share) in _split(amount, onPlot)) {
        _row('expense_allocations', day, {
          'expense_id': expense['id'],
          'crop_cycle_id': cycle['id'],
          'amount_paise': share,
        });
      }
      _maybeEdit('expenses', expense, 'category_code', 'transport', day);
    }

    final lots = <Map<String, Object?>>[];
    for (var i = 0; i < _n(1500); i++) {
      final day = _day(i, _n(1500));
      final cycle = _pick(cycles);
      final qty = (20 + r.nextInt(400)) * 1000; // thousandths of a kg
      final harvest = _row('harvests', day, {
        'harvested_on': _date(day),
        'crop_cycle_id': cycle['id'],
        'plot_id': cycle['plot_id'],
        'quantity': qty,
        'unit': 'kg',
      });
      // one or two teams picked it: groups paid by the day
      for (var k = 0; k < 1 + r.nextInt(2); k++) {
        const rate = 80000;
        final heads = 2 + r.nextInt(6);
        _row('labour_entries', day, {
          'work_date': _date(day),
          'group_id': _pick(groups)['id'],
          'harvest_id': harvest['id'],
          'crop_cycle_id': cycle['id'],
          'plot_id': cycle['plot_id'],
          'head_count': heads,
          'rate_paise': rate,
          'amount_paise': rate * heads,
        });
      }
      final lot = _row('lots', day, {
        'harvest_id': harvest['id'],
        'crop_cycle_id': cycle['id'],
        'quantity': qty,
        'unit': 'kg',
      });
      lots.add(lot);
      _row('lot_costs', day, {
        'id': lot['id'],
        'cost_paise': qty ~/ 1000 * (40 + r.nextInt(200)) * 100,
      });
    }

    final stockLeft = <String, int>{};
    for (var i = 0; i < _n(1200); i++) {
      final lotIndex = (i * _n(1500)) ~/ _n(1200);
      final lot = lots[lotIndex];
      final day = DateTime.parse(
        (t['harvests']![lotIndex]['harvested_on'])! as String,
      ).add(Duration(days: 1 + r.nextInt(20)));
      final left = stockLeft[lot['id']] ?? (lot['quantity']! as int);
      final qty = left ~/ 2;
      final rate = (100 + r.nextInt(700)) * 100;
      final deduction = r.nextInt(500) * 100;
      final sale = _row('sales', day, {
        'sold_on': _date(day.isAfter(until) ? until : day),
        'quantity': qty,
        'unit': 'kg',
        'rate_paise': rate,
        'deductions': [
          {'code': 'commission', 'amount_paise': deduction},
        ],
        'net_paise': amountForQuantity(qty, rate) - deduction,
        'mode': _pick(['cash', 'upi', 'bank', 'credit']),
      });
      _row('sale_lots', day, {
        'sale_id': sale['id'],
        'lot_id': lot['id'],
        'quantity': qty,
      });
      stockLeft[lot['id']! as String] = left - qty;
    }
    // what each worker and group was paid, about once a month
    for (var month = 0; month < 12 * years; month++) {
      final day = from.add(Duration(days: month * 30 + 29));
      for (final payee in [...workers, ...groups]) {
        final isWorker = workers.contains(payee);
        _row('labour_payments', day, {
          'paid_on': _date(day),
          'worker_id': isWorker ? payee['id'] : null,
          'group_id': isWorker ? null : payee['id'],
          'kind': _pick(['settlement', 'settlement', 'part', 'advance']),
          'amount_paise': (1000 + r.nextInt(20000)) * 100,
          'mode': _pick(['cash', 'upi']),
        });
      }
    }

    for (var i = 0; i < _n(1000); i++) {
      final day = _day(i, _n(1000));
      final cycle = _pick(cycles);
      _row('notes', day, {
        'noted_on': _date(day),
        'body': 'note_${i + 1}',
        'plot_id': cycle['plot_id'],
        'crop_cycle_id': r.nextBool() ? cycle['id'] : null,
      });
    }

    for (var i = 0; i < _n(1500); i++) {
      final day = _day(i, _n(1500));
      final cycle = _pick(cycles);
      final task = _row('tasks', day, {
        'title': 'task_${i + 1}',
        'due_on': _date(day.add(Duration(days: r.nextInt(10)))),
        'crop_cycle_id': cycle['id'],
        'plot_id': cycle['plot_id'],
        'source': _pick(['manual', 'calendar']),
      });
      // most past tasks were ticked off; the last few weeks' are open
      if (i < _n(1500) - 50) {
        final at = _at(day);
        task['done_at'] = at;
        _event(
          'tasks',
          task['id']! as String,
          'update',
          at,
          {'done_at': null},
          {'done_at': at.millisecondsSinceEpoch},
        );
      }
    }

    for (var i = 0; i < _n(150); i++) {
      final day = _day(i, _n(150));
      _row('other_income', day, {
        'received_on': _date(day),
        'source_code': _pick(['subsidy', 'rent', 'other']),
        'amount_paise': (500 + r.nextInt(20000)) * 100,
        'crop_cycle_id': r.nextBool() ? _pick(cycles)['id'] : null,
      });
    }
    return t;
  }

  /// About a third of entries are corrected once, as farmers do.
  void _maybeEdit(
    String table,
    Map<String, Object?> row,
    String field,
    Object? value,
    DateTime day,
  ) {
    if (r.nextInt(3) != 0) return;
    final at = _at(day.add(const Duration(days: 1)));
    final old = row[field];
    row[field] = value;
    row['version'] = 2;
    row['updated_at'] = at;
    _event(
      table,
      row['id']! as String,
      'update',
      at,
      {field: old},
      {field: value},
    );
  }

  /// Equal split in paise; leftover paise go to the first cycles listed.
  List<(Map<String, Object?>, int)> _split(
    int amount,
    List<Map<String, Object?>> cycles,
  ) {
    final n = cycles.length;
    return [
      for (var i = 0; i < n; i++)
        (cycles[i], amount ~/ n + (i < amount % n ? 1 : 0)),
    ];
  }
}
