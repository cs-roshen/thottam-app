import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/db/database.dart';
import '../../../core/db/queries.dart';
import '../../../core/history/write_with_history.dart';
import '../domain/land.dart';

/// A plot or crop cycle to save.
class PlotInput {
  const PlotInput({
    required this.name,
    required this.areaUnit,
    this.area,
    this.tenure = 'owned',
  });

  final String name;
  final int? area;
  final String areaUnit;
  final String tenure;
}

class CycleInput {
  const CycleInput({
    required this.cropId,
    this.variety,
    this.plantCount,
    this.areaShare,
    this.season,
    this.plantedOn,
  });

  final String cropId;
  final String? variety;
  final int? plantCount;
  final int? areaShare;
  final String? season;
  final String? plantedOn;
}

/// A crop the farmer can grow.
class CropOption {
  const CropOption(this.id, this.nameMl, this.nameEn, this.kind);
  final String id;
  final String nameMl;
  final String nameEn;
  final String kind;
}

/// One recent history row for a plot.
class PlotEvent {
  const PlotEvent({
    required this.entity,
    required this.action,
    required this.occurredOn,
    required this.summary,
  });

  final String entity;
  final String action;
  final String occurredOn;
  final Map<String, Object?> summary;
}

/// Plots and crop cycles (screens.md 4, 18). Deleting a plot or crop cycle
/// keeps every entry under it: they stay in history and profit and loss,
/// shown under the deleted plot, and undo brings it back (owner decision,
/// 2026-11-19). Totals count entries, never whether their plot is deleted.
class LandRepository {
  LandRepository(this.db, this.history, this.farmId);

  final AppDatabase db;
  final History history;
  final String farmId;

  /// Re-runs [load] whenever one of [tables] changes.
  Stream<T> _watch<T>(Set<String> tables, Future<T> Function() load) async* {
    yield await load();
    final infos = {
      for (final t in db.allTables)
        if (tables.contains(t.actualTableName)) t,
    };
    await for (final _ in db.tableUpdates(
      TableUpdateQuery.onAllTables(infos),
    )) {
      yield await load();
    }
  }

  Future<List<QueryRow>> _rows(String sql, List<Object?> args) =>
      db.customSelect(sql, variables: [for (final a in args) _v(a)]).get();

  static Variable<Object> _v(Object? a) => switch (a) {
    final int i => Variable.withInt(i),
    final String s => Variable.withString(s),
    _ => throw ArgumentError.value(a),
  };

  // ---------- reading ----------

  /// The farm's live plots with the crops growing now and the next task.
  Stream<List<PlotView>> watchPlots() =>
      _watch({'plots', 'crop_cycles', 'crops', 'tasks'}, () async {
        final cycles = [
          for (final r in await select(db, qFarmCycles, {'farm': farmId}))
            _cycle(r),
        ];
        final tasks = {
          for (final r in await select(db, qOpenTasks, {'farm': farmId}))
            r.readNullable<String>('plot'): (
              r.read<String>('title'),
              r.readNullable<String>('due_on'),
            ),
        };
        return [
          for (final r in await select(db, qPlots, {'farm': farmId}))
            _plot(r, [
              for (final c in cycles)
                if (c.plotId == r.read<String>('id')) c,
            ], tasks[r.read<String>('id')]),
        ];
      });

  /// One plot with every crop cycle on it, closed seasons included; null
  /// once deleted.
  Stream<PlotView?> watchPlot(String plotId) =>
      _watch({'plots', 'crop_cycles', 'crops'}, () async {
        final rows = await _rows(
          'SELECT * FROM plots WHERE id = ? AND deleted_at IS NULL',
          [plotId],
        );
        if (rows.isEmpty) return null;
        return _plot(rows.single, [
          for (final r in await select(db, qPlotCycles, {'plot': plotId}))
            _cycle(r),
        ], null);
      });

  PlotView _plot(QueryRow r, List<CycleView> cycles, (String, String?)? task) =>
      PlotView(
        id: r.read<String>('id'),
        name: r.read<String>('name'),
        area: r.readNullable<int>('area'),
        areaUnit: r.read<String>('area_unit'),
        tenure: r.read<String>('tenure'),
        cycles: cycles,
        nextTask: task,
      );

  static CycleView _cycle(QueryRow r) => CycleView(
    id: r.read<String>('id'),
    plotId: r.read<String>('plot_id'),
    cropId: r.read<String>('crop_id'),
    nameMl: r.read<String>('name_ml'),
    nameEn: r.read<String>('name_en'),
    kind: r.read<String>('kind'),
    variety: r.readNullable<String>('variety'),
    plantCount: r.readNullable<int>('plant_count'),
    areaShare: r.readNullable<int>('area_share'),
    season: r.readNullable<String>('season'),
    plantedOn: r.readNullable<String>('planted_on'),
    status: r.read<String>('status'),
  );

  /// Cost and yield of each live crop cycle on [plotId]. Entries count
  /// whatever happened to their plot; deleted entries do not.
  Stream<List<CycleTotals>> watchCycleTotals(String plotId) => _watch(
    {
      'crop_cycles',
      'expenses',
      'expense_allocations',
      'labour_entries',
      'labour_allocations',
      'workers',
      'harvests',
    },
    () async {
      final yields = <String, Map<String, int>>{};
      for (final r in await select(db, qPlotYields, {'plot': plotId})) {
        (yields[r.read<String>('cycle')] ??= {})[r.read<String>('unit')] = r
            .read<int>('q');
      }
      return [
        for (final r in await select(db, qCycleTotals, {
          'plot': plotId,
          'farm': farmId,
        }))
          CycleTotals(
            r.read<String>('id'),
            expensePaise: r.read<int>('expense'),
            labourPaise: r.read<int>('labour'),
            yields: yields[r.read<String>('id')] ?? const {},
          ),
      ];
    },
  );

  /// This season's costs on [plotId] by expense category, paid wages under
  /// `wages`, largest first. Closed seasons are left out.
  Stream<List<(String, int)>> watchCostsByCategory(String plotId) => _watch(
    {
      'crop_cycles',
      'expenses',
      'expense_allocations',
      'labour_entries',
      'labour_allocations',
      'workers',
    },
    () async => [
      for (final r in await select(db, qPlotCosts, {
        'plot': plotId,
        'farm': farmId,
      }))
        (r.read<String>('code'), r.read<int>('paise')),
    ],
  );

  /// The latest price of each crop: official, or entered on this farm.
  Stream<Map<String, (int, String, int)>> watchLatestPrices(
    Iterable<String> cropIds,
  ) => _watch({'market_prices'}, () async {
    final out = <String, (int, String, int)>{};
    for (final crop in cropIds) {
      final r = await select(db, qLatestPrice, {'row': crop, 'farm': farmId});
      if (r.isNotEmpty) {
        out[crop] = (
          r.single.read<int>('price_paise'),
          r.single.read<String>('unit'),
          r.single.read<int>('published_at'),
        );
      }
    }
    return out;
  });

  /// The latest history of [plotId]: the plot, its crops and its entries.
  Stream<List<PlotEvent>> watchRecentHistory(String plotId, {int limit = 5}) =>
      _watch(
        {'event_log'},
        () async => [
          for (final r in await select(db, qPlotHistory, {
            'farm': farmId,
            'plot': plotId,
            'limit': limit,
            'from': _daysBefore(history.today(), 90),
          }))
            PlotEvent(
              entity: r.read<String>('entity'),
              action: r.read<String>('action'),
              occurredOn: r.read<String>('occurred_on'),
              summary: (jsonDecode(r.read<String>('summary')) as Map)
                  .cast<String, Object?>(),
            ),
        ],
      );

  static String _daysBefore(String day, int days) =>
      DateTime.parse(day)
          .subtract(Duration(days: days))
          .toIso8601String()
          .substring(0, 10);

  /// The crops this farm can grow: the standard ones and its own.
  Future<List<CropOption>> crops() async => [
    for (final r in await _rows(
      'SELECT id, name_ml, name_en, kind FROM crops WHERE deleted_at IS NULL '
      'AND (owner_farm_id IS NULL OR owner_farm_id = ?) ORDER BY name_en, id',
      [farmId],
    ))
      CropOption(
        r.read<String>('id'),
        r.read<String>('name_ml'),
        r.read<String>('name_en'),
        r.read<String>('kind'),
      ),
  ];

  /// How many live entries sit under [plotId] or its crop cycles (or under
  /// one crop cycle with [cycleId]), to say so before a delete.
  Future<int> entryCount({String? plotId, String? cycleId}) async {
    final cycles = cycleId != null
        ? 'SELECT ?2 AS id'
        : 'SELECT id FROM crop_cycles WHERE plot_id = ?1';
    final plot = plotId ?? '';
    final r = await _rows(
      'SELECT '
      '(SELECT COUNT(*) FROM expenses e WHERE e.deleted_at IS NULL AND '
      '(e.plot_id = ?1 OR e.id IN (SELECT a.expense_id FROM expense_allocations a '
      'WHERE a.deleted_at IS NULL AND a.crop_cycle_id IN ($cycles)))) + '
      '(SELECT COUNT(*) FROM labour_entries l WHERE l.deleted_at IS NULL AND '
      '(l.plot_id = ?1 OR l.crop_cycle_id IN ($cycles) OR l.id IN '
      '(SELECT a.labour_entry_id FROM labour_allocations a '
      'WHERE a.deleted_at IS NULL AND a.crop_cycle_id IN ($cycles)))) + '
      '(SELECT COUNT(*) FROM harvests h WHERE h.deleted_at IS NULL AND '
      '(h.plot_id = ?1 OR h.crop_cycle_id IN ($cycles))) + '
      '(SELECT COUNT(*) FROM notes n WHERE n.deleted_at IS NULL AND '
      '(n.plot_id = ?1 OR n.crop_cycle_id IN ($cycles))) + '
      '(SELECT COUNT(*) FROM tasks t WHERE t.deleted_at IS NULL AND '
      '(t.plot_id = ?1 OR t.crop_cycle_id IN ($cycles))) + '
      '(SELECT COUNT(*) FROM other_income o WHERE o.deleted_at IS NULL AND '
      'o.crop_cycle_id IN ($cycles)) AS n',
      [plot, ?cycleId],
    );
    return r.single.read<int>('n');
  }

  // ---------- writing ----------

  static Map<String, Object?> _plotValues(PlotInput p) => {
    'name': p.name.trim(),
    'area': p.area,
    'area_unit': p.areaUnit,
    'tenure': p.tenure,
  };

  /// Returns the history ids of the save, for undo.
  Future<(String, List<String>)> createPlot(PlotInput p) async {
    final id = history.newId();
    final events = await history.writeWithHistory([
      CreateRow(
        'plots',
        {'id': id, 'farm_id': farmId, ..._plotValues(p)},
        summary: {'plot_id': id, 'plot': p.name.trim()},
      ),
    ]);
    return (id, events);
  }

  Future<List<String>> updatePlot(String id, PlotInput p) =>
      history.writeWithHistory([
        UpdateRow(
          'plots',
          id,
          _plotValues(p),
          summary: {'plot_id': id, 'plot': p.name.trim()},
        ),
      ]);

  /// Deletes the plot and its crop cycles; every entry under them stays.
  Future<List<String>> deletePlot(String plotId) async {
    final plot = await _rows('SELECT name FROM plots WHERE id = ?', [plotId]);
    final name = plot.single.read<String>('name');
    final cycles = await _rows(
      'SELECT id FROM crop_cycles WHERE plot_id = ? AND deleted_at IS NULL',
      [plotId],
    );
    return history.writeWithHistory([
      for (final c in cycles)
        DeleteRow(
          'crop_cycles',
          c.read<String>('id'),
          summary: {'plot_id': plotId, 'plot': name},
        ),
      DeleteRow('plots', plotId, summary: {'plot_id': plotId, 'plot': name}),
    ]);
  }

  Future<Map<String, Object?>> _cycleSummary(
    String plotId,
    String cropId,
  ) async {
    final r = await _rows(
      'SELECT p.name AS plot, k.name_ml, k.name_en FROM plots p, crops k '
      'WHERE p.id = ? AND k.id = ?',
      [plotId, cropId],
    );
    return {
      'plot_id': plotId,
      'plot': r.firstOrNull?.read<String>('plot'),
      'crop_ml': r.firstOrNull?.read<String>('name_ml'),
      'crop_en': r.firstOrNull?.read<String>('name_en'),
    };
  }

  Map<String, Object?> _cycleValues(CycleInput c) => {
    'crop_id': c.cropId,
    'variety': _blank(c.variety),
    'plant_count': c.plantCount,
    'area_share': c.areaShare,
    'season': _blank(c.season),
    'planted_on': c.plantedOn,
  };

  static String? _blank(String? s) =>
      s == null || s.trim().isEmpty ? null : s.trim();

  Future<(String, List<String>)> createCycle(
    String plotId,
    CycleInput c,
  ) async {
    final id = history.newId();
    final events = await history.writeWithHistory([
      CreateRow('crop_cycles', {
        'id': id,
        'farm_id': farmId,
        'plot_id': plotId,
        ..._cycleValues(c),
        'started_on': history.today(),
        'status': 'active',
      }, summary: await _cycleSummary(plotId, c.cropId)),
    ]);
    return (id, events);
  }

  Future<List<String>> updateCycle(
    String plotId,
    String id,
    CycleInput c,
  ) async => history.writeWithHistory([
    UpdateRow(
      'crop_cycles',
      id,
      _cycleValues(c),
      summary: await _cycleSummary(plotId, c.cropId),
    ),
  ]);

  /// Closes the season: its entries become read-only, and it leaves the
  /// plot's current crops. Reopening takes it back.
  Future<List<String>> setCycleClosed(
    CycleView c, {
    required bool closed,
  }) async => history.writeWithHistory([
    UpdateRow('crop_cycles', c.id, {
      'status': closed ? 'closed' : 'active',
      'ended_on': closed ? history.today() : null,
    }, summary: await _cycleSummary(c.plotId, c.cropId)),
  ]);

  Future<List<String>> deleteCycle(CycleView c) async =>
      history.writeWithHistory([
        DeleteRow(
          'crop_cycles',
          c.id,
          summary: await _cycleSummary(c.plotId, c.cropId),
        ),
      ]);

  /// Puts back what a save changed.
  Future<void> undo(List<String> events) => history.undo(events);
}
