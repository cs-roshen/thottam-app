import 'package:drift/drift.dart';

import '../../../core/db/database.dart';
import '../../../core/db/queries.dart';
import '../../../core/history/write_with_history.dart';
import '../domain/harvest_math.dart';

/// A harvest to save (screen 12).
class HarvestInput {
  const HarvestInput({
    required this.day,
    required this.plotId,
    required this.cycleId,
    required this.unit,
    required this.teams,
    required this.perTeam,
    this.total,
    this.gradeCode,
    this.plotName,
    this.cropMl,
    this.cropEn,
  });

  final String day;
  final String plotId;
  final String cycleId;
  final String unit;
  final List<HarvestTeam> teams;
  final bool perTeam;

  /// The total entered when teams do not log their own quantity.
  final int? total;
  final String? gradeCode;
  final String? plotName;
  final String? cropMl;
  final String? cropEn;

  int get quantity => harvestQuantity(teams, perTeam: perTeam, total: total);
}

/// A saved harvest with its lot and the lot's cost.
class HarvestView {
  const HarvestView({
    required this.id,
    required this.day,
    required this.cycleId,
    required this.plotId,
    required this.quantity,
    required this.unit,
    required this.perTeam,
    required this.lotId,
    required this.teams,
    this.costPaise,
    this.costOverridden = false,
  });

  final String id;
  final String day;
  final String cycleId;
  final String plotId;
  final int quantity;
  final String unit;
  final bool perTeam;
  final String lotId;
  final List<HarvestTeam> teams;

  /// Null while not yet worked out, or for a role that cannot see money.
  final int? costPaise;
  final bool costOverridden;
}

/// The last harvest of a crop cycle, for the "last time" banner.
class LastHarvest {
  const LastHarvest(this.day, this.quantity, this.unit, this.people);
  final String day;
  final int quantity;
  final String unit;
  final int people;
}

/// Harvests, their teams, their lots and lot costs (product spec rule 9).
/// A lot's cost lives in `lot_costs`, which is money: a phone that cannot
/// write money saves the lot without it, and the next phone that can works
/// it out ([settlePending]). Each save of the teams gets a new stamp, so a
/// cost worked out for older teams is known to be stale.
class HarvestRepository {
  HarvestRepository(this.db, this.history, this.farmId);

  final AppDatabase db;
  final History history;
  final String farmId;

  /// The labour entries that are [teams] on harvest [harvestId].
  List<RowWrite> _teamRows(
    String harvestId,
    HarvestInput h,
    Map<String, Object?> summary,
  ) => [
    for (final t in h.teams) ...[
      ..._newGroup(t, summary),
      CreateRow(
        'labour_entries',
        {
          'farm_id': farmId,
          'work_date': h.day,
          'harvest_id': harvestId,
          'crop_cycle_id': h.cycleId,
          'plot_id': h.plotId,
          'worker_id': t.workerId,
          'group_id': t.workerId == null ? _groupIds[t] : null,
          'head_count': t.heads,
          'rate_paise': t.ratePaise,
          'wage_type': t.pieceRate ? 'piece' : 'daily',
          'piece_quantity': t.quantity,
          'piece_unit': t.quantity == null ? null : h.unit,
          'amount_paise': t.wagePaise,
          'task_code': 'harvest',
        },
        occurredOn: h.day,
        summary: {...summary, 'amount_paise': t.wagePaise},
      ),
    ],
  ];

  /// The group of each group team being saved.
  final _groupIds = Map<HarvestTeam, String>.identity();

  /// A group team with no group yet gets an unnamed one, in the same save,
  /// as a labour day's group does; it can be named later.
  List<RowWrite> _newGroup(HarvestTeam t, Map<String, Object?> summary) {
    if (t.workerId != null) return const [];
    if (t.groupId case final id?) {
      _groupIds[t] = id;
      return const [];
    }
    final id = _groupIds[t] = history.newId();
    return [
      CreateRow(
        'labour_groups',
        {
          'id': id,
          'farm_id': farmId,
          'label': t.label.trim(),
          'is_named': t.label.trim().isNotEmpty,
        },
        summary: {...summary, 'group_id': id},
      ),
    ];
  }

  Map<String, Object?> _summary(HarvestInput h, int quantity) => {
    'plot_id': h.plotId,
    'plot': ?h.plotName,
    'crop_ml': ?h.cropMl,
    'crop_en': ?h.cropEn,
    'quantity': quantity,
    'unit': h.unit,
  };

  /// The cost rule 9 gives harvest [harvestId] on [day], with [paidWages].
  Future<int> _workOut(
    String cycleId,
    String harvestId,
    String day,
    int paidWages,
  ) async {
    final prev = await select(db, qPreviousHarvest, {
      'cycle': cycleId,
      'day': day,
      'id': harvestId,
    });
    final since = await select(db, qCostsSince, {
      'cycle': cycleId,
      'from': prev.isEmpty ? '' : prev.single.read<String>('harvested_on'),
      'day': day,
      'farm': farmId,
    });
    return lotCost(
      costsSincePaise: since.single.read<int>('costs'),
      paidWagesPaise: paidWages,
    );
  }

  /// Saves the harvest, its teams and its lot in one transaction; with
  /// [canWriteMoney] the lot's cost too, else it is left to be worked out.
  /// Returns the harvest id and the history ids for undo.
  Future<(String, List<String>)> save(
    HarvestInput h, {
    required bool canWriteMoney,
  }) async {
    final id = history.newId();
    final lotId = history.newId();
    final stamp = history.newId();
    final quantity = h.quantity;
    final summary = _summary(h, quantity);
    final paid = summarise(
      h.teams,
      perTeam: h.perTeam,
      total: h.total,
    ).paidWagesPaise;
    final cost = canWriteMoney
        ? await _workOut(h.cycleId, id, h.day, paid)
        : null;
    final events = await history.writeWithHistory([
      CreateRow(
        'harvests',
        {
          'id': id,
          'farm_id': farmId,
          'crop_cycle_id': h.cycleId,
          'plot_id': h.plotId,
          'harvested_on': h.day,
          'quantity': quantity,
          'unit': h.unit,
          'grade_code': h.gradeCode,
          'per_team_quantity': h.perTeam,
        },
        occurredOn: h.day,
        summary: summary,
      ),
      ..._teamRows(id, h, summary),
      CreateRow(
        'lots',
        {
          'id': lotId,
          'farm_id': farmId,
          'crop_cycle_id': h.cycleId,
          'harvest_id': id,
          'quantity': quantity,
          'unit': h.unit,
          'grade_code': h.gradeCode,
          'teams_stamp': stamp,
        },
        occurredOn: h.day,
        summary: summary,
      ),
      if (cost != null)
        CreateRow(
          'lot_costs',
          {
            'id': lotId,
            'farm_id': farmId,
            'cost_paise': cost,
            'teams_stamp': stamp,
          },
          occurredOn: h.day,
          summary: {...summary, 'amount_paise': cost},
        ),
    ]);
    return (id, events);
  }

  /// Replaces the teams of harvest [id]. The lot follows the new quantity;
  /// its cost is worked out again unless it was edited by hand, or left
  /// not yet worked out when [canWriteMoney] is false.
  Future<List<String>> editTeams(
    String id,
    HarvestInput h, {
    required bool canWriteMoney,
  }) async {
    final old = await select(db, qHarvestTeams, {'row': id});
    final lot = await _lot(id);
    final stamp = history.newId();
    final quantity = h.quantity;
    final summary = _summary(h, quantity);
    final cost = await _cost(lot.$1);
    final paid = summarise(
      h.teams,
      perTeam: h.perTeam,
      total: h.total,
    ).paidWagesPaise;
    final worked = canWriteMoney
        ? await _workOut(h.cycleId, id, h.day, paid)
        : null;
    return history.writeWithHistory([
      UpdateRow(
        'harvests',
        id,
        {'quantity': quantity, 'unit': h.unit, 'per_team_quantity': h.perTeam},
        occurredOn: h.day,
        summary: summary,
      ),
      for (final r in old) DeleteRow('labour_entries', r.read<String>('id')),
      ..._teamRows(id, h, summary),
      UpdateRow(
        'lots',
        lot.$1,
        {'quantity': quantity, 'unit': h.unit, 'teams_stamp': stamp},
        occurredOn: h.day,
        summary: summary,
      ),
      if (worked != null)
        if (cost == null)
          CreateRow(
            'lot_costs',
            {
              'id': lot.$1,
              'farm_id': farmId,
              'cost_paise': worked,
              'teams_stamp': stamp,
            },
            summary: {...summary, 'amount_paise': worked},
          )
        else
          UpdateRow(
            'lot_costs',
            lot.$1,
            {
              // an edited cost stays; it only learns the teams changed
              if (!cost.$2) 'cost_paise': worked,
              'teams_stamp': stamp,
            },
            summary: {...summary, 'amount_paise': cost.$2 ? cost.$1 : worked},
          ),
    ]);
  }

  Future<(String, String?)> _lot(String harvestId) async {
    final r = await db
        .customSelect(
          'SELECT id, teams_stamp FROM lots WHERE harvest_id = ? '
          'AND deleted_at IS NULL',
          variables: [Variable.withString(harvestId)],
        )
        .getSingle();
    return (r.read<String>('id'), r.readNullable<String>('teams_stamp'));
  }

  /// The lot cost and whether it was edited, or null when there is none.
  Future<(int, bool)?> _cost(String lotId) async {
    final r = await db
        .customSelect(
          'SELECT cost_paise, cost_overridden FROM lot_costs WHERE id = ? '
          'AND deleted_at IS NULL',
          variables: [Variable.withString(lotId)],
        )
        .getSingleOrNull();
    return r == null
        ? null
        : (r.read<int>('cost_paise'), r.read<bool>('cost_overridden'));
  }

  /// The farmer types the lot's cost: it is kept, and marked as edited.
  Future<List<String>> setCost(String lotId, int paise) async {
    final have = await _cost(lotId);
    final stamp =
        (await db
                .customSelect(
                  'SELECT teams_stamp FROM lots WHERE id = ?',
                  variables: [Variable.withString(lotId)],
                )
                .getSingle())
            .readNullable<String>('teams_stamp');
    return history.writeWithHistory([
      if (have == null)
        CreateRow(
          'lot_costs',
          {
            'id': lotId,
            'farm_id': farmId,
            'cost_paise': paise,
            'cost_overridden': true,
            'teams_stamp': stamp,
          },
          summary: {'amount_paise': paise},
        )
      else
        UpdateRow(
          'lot_costs',
          lotId,
          {'cost_paise': paise, 'cost_overridden': true},
          summary: {'amount_paise': paise},
        ),
    ]);
  }

  /// Works the lot's cost out again from today's entries, and clears an
  /// edited cost: "recalculate" and "reset" both.
  Future<List<String>> recalculate(String harvestId) async {
    final h = (await watchHarvest(harvestId, withCost: false).first)!;
    final paid = summarise(
      h.teams,
      perTeam: h.perTeam,
      total: h.quantity,
    ).paidWagesPaise;
    final worked = await _workOut(h.cycleId, h.id, h.day, paid);
    final lot = await _lot(harvestId);
    final have = await _cost(lot.$1);
    return history.writeWithHistory([
      if (have == null)
        CreateRow(
          'lot_costs',
          {
            'id': lot.$1,
            'farm_id': farmId,
            'cost_paise': worked,
            'teams_stamp': lot.$2,
          },
          summary: {'amount_paise': worked},
        )
      else
        UpdateRow(
          'lot_costs',
          lot.$1,
          {
            'cost_paise': worked,
            'cost_overridden': false,
            'teams_stamp': lot.$2,
          },
          summary: {'amount_paise': worked},
        ),
    ]);
  }

  /// Works out the cost of every lot saved, or whose teams were edited,
  /// by someone who cannot write money, keeping a cost edited by hand.
  /// Run by a phone that can; each one is a money entry in the history.
  Future<int> settlePending() async {
    final pending = await select(db, qPendingLotCosts, {'farm': farmId});
    for (final p in pending) {
      final harvestId = p.read<String>('harvest_id');
      final lotId = p.read<String>('id');
      final stamp = p.readNullable<String>('teams_stamp');
      if (p.readNullable<String>('cost_id') == null) {
        await recalculate(harvestId);
      } else if (p.read<bool>('cost_overridden')) {
        await history.writeWithHistory([
          UpdateRow('lot_costs', lotId, {'teams_stamp': stamp}),
        ]);
      } else {
        await recalculate(harvestId);
      }
    }
    return pending.length;
  }

  /// A harvest with its teams and lot; [withCost] false for a role that
  /// cannot read money, so the cost is never read.
  Stream<HarvestView?> watchHarvest(String id, {bool withCost = true}) async* {
    Future<HarvestView?> load() async {
      final h = await db
          .customSelect(
            'SELECT h.*, l.id AS lot_id FROM harvests h '
            'JOIN lots l ON l.harvest_id = h.id AND l.deleted_at IS NULL '
            'WHERE h.id = ? AND h.deleted_at IS NULL',
            variables: [Variable.withString(id)],
          )
          .getSingleOrNull();
      if (h == null) return null;
      final lotId = h.read<String>('lot_id');
      final cost = withCost ? await _cost(lotId) : null;
      final stale = withCost && cost != null
          ? (await db
                    .customSelect(
                      'SELECT l.teams_stamp IS NOT c.teams_stamp AS stale '
                      'FROM lots l JOIN lot_costs c ON c.id = l.id '
                      'WHERE l.id = ?',
                      variables: [Variable.withString(lotId)],
                    )
                    .getSingle())
                .read<bool>('stale')
          : false;
      return HarvestView(
        id: id,
        day: h.read<String>('harvested_on'),
        cycleId: h.read<String>('crop_cycle_id'),
        plotId: h.read<String>('plot_id'),
        quantity: h.read<int>('quantity'),
        unit: h.read<String>('unit'),
        perTeam: h.read<bool>('per_team_quantity'),
        lotId: lotId,
        teams: [
          for (final t in await select(db, qHarvestTeams, {'row': id}))
            HarvestTeam(
              heads: t.read<int>('head_count'),
              ratePaise: t.read<int>('rate_paise'),
              pieceRate: t.read<String>('wage_type') == 'piece',
              quantity: t.readNullable<int>('piece_quantity'),
              isFamily: t.readNullable<bool>('is_family') ?? false,
              workerId: t.readNullable<String>('worker_id'),
              groupId: t.readNullable<String>('group_id'),
              label:
                  t.readNullable<String>('worker_name') ??
                  t.readNullable<String>('group_label') ??
                  '',
            ),
        ],
        // a cost worked out for older teams is not yet worked out
        costPaise: stale ? null : cost?.$1,
        costOverridden: cost?.$2 ?? false,
      );
    }

    yield await load();
    await for (final _ in db.tableUpdates(
      TableUpdateQuery.onAllTables([
        db.harvests,
        db.labourEntries,
        db.lots,
        db.lotCosts,
      ]),
    )) {
      yield await load();
    }
  }

  Future<LastHarvest?> lastHarvest(String cycleId) async {
    final r = await select(db, qLastHarvest, {'cycle': cycleId});
    if (r.isEmpty) return null;
    final x = r.single;
    return LastHarvest(
      x.read<String>('harvested_on'),
      x.read<int>('quantity'),
      x.read<String>('unit'),
      x.read<int>('people'),
    );
  }

  Future<void> undo(List<String> events) => history.undo(events);
}
