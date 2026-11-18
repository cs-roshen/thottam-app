import 'dart:math';

import '../ids/uuid_v7.dart';

/// Rows per table, keyed by the table names in the draft schema.
typedef SeedTables = Map<String, List<Map<String, Object?>>>;

/// Three years of realistic data for one farm (implementation plan section
/// 14), for benchmarks and tests only; never shipped to farmers. The same
/// [seed] always gives the same rows. B2 inserts these into Drift.
SeedTables generateBenchmarkSeed({int seed = 42, DateTime? until}) =>
    _Seed(Random(seed), until ?? DateTime.utc(2026, 11, 17)).build();

class _Seed {
  _Seed(this.r, this.until)
    : from = until.subtract(const Duration(days: 3 * 365));

  final Random r;
  final DateTime until;
  final DateTime from;
  final SeedTables t = {};
  final String user = '00000000-0000-7000-8000-000000000001';
  late final String farmId;

  int _clock = 0;

  /// A creation time on [day], unique and increasing so ids stay ordered.
  DateTime _at(DateTime day) =>
      day.add(Duration(hours: 7, milliseconds: _clock++));

  DateTime _day(int i, int count) =>
      from.add(Duration(days: (i * 3 * 365) ~/ count));

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
      'version': 1,
      'deleted_at': null,
    };
    farmId = farm['id']! as String;
    t['farms'] = [farm];

    final plots = [
      for (var i = 0; i < 8; i++)
        _row('plots', from, {
          'name': 'plot_${i + 1}',
          'area': 25 + r.nextInt(400),
          'area_unit': 'cent',
          'tenure': i == 7 ? 'leased' : 'owned',
        }),
    ];
    final cycles = [
      for (var i = 0; i < 20; i++)
        _row('crop_cycles', from, {
          'plot_id': plots[i % 8]['id'],
          'crop_code': _pick([
            'coconut',
            'rubber',
            'pepper',
            'banana',
            'paddy',
            'cardamom',
          ]),
          'area_share': i < 8 ? 60 : 40,
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
          'name': 'group_${i + 1}',
          'is_named': i < 4,
        }),
    ];

    for (var i = 0; i < 15000; i++) {
      final day = _day(i, 15000);
      final cycle = _pick(cycles);
      final byGroup = r.nextInt(5) == 0;
      final heads = byGroup ? 3 + r.nextInt(8) : 1;
      final attendance = byGroup ? 1.0 : _pick([1.0, 1.0, 1.0, 0.5, 0.0]);
      final rate = (700 + r.nextInt(5) * 100) * 100;
      final entry = _row('labour_entries', day, {
        'work_date': _date(day),
        'worker_id': byGroup ? null : _pick(workers)['id'],
        'group_id': byGroup ? _pick(groups)['id'] : null,
        'crop_cycle_id': cycle['id'],
        'plot_id': cycle['plot_id'],
        'head_count': heads,
        'attendance': attendance,
        'rate_paise': rate,
        'amount_paise': (rate * heads * attendance).round(),
      });
      _maybeEdit('labour_entries', entry, 'rate_paise', rate + 5000, day);
    }

    for (var i = 0; i < 6000; i++) {
      final day = _day(i, 6000);
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
    for (var i = 0; i < 1500; i++) {
      final day = _day(i, 1500);
      final cycle = _pick(cycles);
      final qty = (20 + r.nextInt(400)) * 1000; // thousandths of a kg
      final harvest = _row('harvests', day, {
        'harvested_on': _date(day),
        'crop_cycle_id': cycle['id'],
        'plot_id': cycle['plot_id'],
        'quantity': qty,
        'unit': 'kg',
      });
      lots.add(
        _row('lots', day, {
          'harvest_id': harvest['id'],
          'crop_cycle_id': cycle['id'],
          'quantity': qty,
          'remaining': qty,
          'cost_paise': qty ~/ 1000 * (40 + r.nextInt(200)) * 100,
          'unit': 'kg',
        }),
      );
    }

    for (var i = 0; i < 1200; i++) {
      final lotIndex = (i * 1500) ~/ 1200;
      final lot = lots[lotIndex];
      final day = DateTime.parse(
        (t['harvests']![lotIndex]['harvested_on'])! as String,
      ).add(Duration(days: 1 + r.nextInt(20)));
      final qty = (lot['remaining']! as int) ~/ 2;
      final rate = (100 + r.nextInt(700)) * 100;
      final sale = _row('sales', day, {
        'sold_on': _date(day.isAfter(until) ? until : day),
        'crop_cycle_id': lot['crop_cycle_id'],
        'quantity': qty,
        'rate_paise': rate,
        'deductions_paise': r.nextInt(500) * 100,
        'mode': _pick(['cash', 'upi', 'bank', 'credit']),
      });
      _row('sale_lots', day, {
        'sale_id': sale['id'],
        'lot_id': lot['id'],
        'quantity': qty,
      });
      lot['remaining'] = (lot['remaining']! as int) - qty;
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
