import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/db/database.dart';
import '../../../core/db/queries.dart';
import '../../../core/history/write_with_history.dart';
import '../../../core/money/money.dart';
import '../domain/wages.dart';

class WorkerView {
  const WorkerView({
    required this.id,
    required this.name,
    this.phone,
    this.defaultRatePaise = 0,
    this.isFamily = false,
    this.balancePaise = 0,
  });

  final String id;
  final String name;
  final String? phone;
  final int defaultRatePaise;
  final bool isFamily;

  /// Wages earned less money paid and deductions.
  final int balancePaise;
}

class GroupView {
  const GroupView({
    required this.id,
    required this.label,
    required this.isNamed,
    this.leaderWorkerId,
    this.usualSize,
    this.defaultRates = const {},
    this.memberIds = const [],
    this.balancePaise = 0,
  });

  final String id;

  /// Empty for an unnamed group; screens show a generic name.
  final String label;
  final bool isNamed;
  final String? leaderWorkerId;
  final int? usualSize;

  /// Default rate per head by rate class.
  final Map<String, int> defaultRates;
  final List<String> memberIds;
  final int balancePaise;
}

/// One worker's line on a day's attendance.
class WorkerDay {
  const WorkerDay(
    this.workerId,
    this.attendance, {
    required this.ratePaise,
    this.overtimeHours = 0,
    this.overtimeRatePaise = 0,
  });

  final String workerId;
  final Attendance attendance;
  final int ratePaise;

  /// Thousandths of an hour.
  final int overtimeHours;
  final int overtimeRatePaise;

  int get paise => attendanceWage(
    ratePaise,
    attendance,
    overtimeHours: overtimeHours,
    overtimeRatePaise: overtimeRatePaise,
  );
}

/// Where a day's wages go: one crop cycle, or parts across several. The
/// weights are what each crop cycle carries of the day (amounts the farmer
/// may have edited); each entry is split by them so its parts sum to it.
class WageTarget {
  WageTarget.one(String cycleId) : cycles = [cycleId], weights = const [1];
  const WageTarget.split(this.cycles, this.weights);

  /// No crop: the plot has none growing.
  const WageTarget.none() : cycles = const [], weights = const [];

  final List<String> cycles;
  final List<int> weights;
}

/// A line in a worker's or group's history: a day of work or a payment.
class LedgerLine {
  const LedgerLine({
    required this.id,
    required this.day,
    required this.paise,
    this.attendance,
    this.overtimeHours,
    this.heads,
    this.kind,
  });

  final String id;
  final String day;
  final int paise;
  final int? attendance;
  final int? overtimeHours;
  final int? heads;

  /// The payment kind; null for a day of work.
  final PaymentKind? kind;
}

/// Labour: workers, groups, days of work, payments and balances (screens 8,
/// 11; product spec, Labour). Every write goes through the history.
class LabourRepository {
  LabourRepository(this.db, this.history, this.farmId);

  final AppDatabase db;
  final History history;
  final String farmId;

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

  Future<List<QueryRow>> _rows(String sql, List<Object> args) => db
      .customSelect(
        sql,
        variables: [
          for (final a in args)
            a is int ? Variable.withInt(a) : Variable.withString('$a'),
        ],
      )
      .get();

  // ---------- reading ----------

  /// Workers by name, each with their balance.
  Stream<List<WorkerView>> watchWorkers() => _watch(
    {'workers', 'labour_entries', 'labour_payments'},
    () async => [
      for (final r in await select(db, qWorkers, {'farm': farmId}))
        WorkerView(
          id: r.read<String>('id'),
          name: r.read<String>('name'),
          phone: r.readNullable<String>('phone'),
          defaultRatePaise: r.read<int>('default_rate_paise'),
          isFamily: r.read<bool>('is_family'),
          balancePaise: r.read<int>('balance'),
        ),
    ],
  );

  /// Groups, named first, each with its members and balance.
  Stream<List<GroupView>> watchGroups() => _watch(
    {
      'labour_groups',
      'labour_group_members',
      'labour_entries',
      'labour_payments',
    },
    () async {
      final members = <String, List<String>>{};
      for (final r in await select(db, qGroupMembers, {'farm': farmId})) {
        (members[r.read<String>('group_id')] ??= []).add(
          r.read<String>('worker_id'),
        );
      }
      return [
        for (final r in await select(db, qGroups, {'farm': farmId}))
          GroupView(
            id: r.read<String>('id'),
            label: r.read<String>('label'),
            isNamed: r.read<bool>('is_named'),
            leaderWorkerId: r.readNullable<String>('leader_worker_id'),
            usualSize: r.readNullable<int>('usual_size'),
            defaultRates: {
              for (final MapEntry(:key, :value) in (jsonDecode(
                r.read<String>('default_rates'),
              ) as Map).entries)
                key as String: (value as num).toInt(),
            },
            memberIds: members[r.read<String>('id')] ?? const [],
            balancePaise: r.read<int>('balance'),
          ),
      ];
    },
  );

  /// A worker's or group's days of work and payments, newest first.
  Stream<List<LedgerLine>> watchLedger({String? workerId, String? groupId}) {
    final (days, payments, key, id) = workerId != null
        ? (qWorkerDays, qWorkerPayments, 'worker', workerId)
        : (qGroupDays, qGroupPayments, 'group', groupId!);
    return _watch({'labour_entries', 'labour_payments'}, () async {
      final lines = [
        for (final r in await select(db, days, {key: id}))
          LedgerLine(
            id: r.read<String>('id'),
            day: r.read<String>('work_date'),
            paise: r.read<int>('amount_paise'),
            attendance: r.read<int>('attendance'),
            overtimeHours: r.readNullable<int>('overtime_hours'),
            heads: r.read<int>('head_count'),
          ),
        for (final r in await select(db, payments, {key: id}))
          LedgerLine(
            id: r.read<String>('id'),
            day: r.read<String>('paid_on'),
            paise: r.read<int>('amount_paise'),
            kind: PaymentKind.values.asNameMap()[r.read<String>('kind')],
          ),
      ]..sort((a, b) => b.day.compareTo(a.day));
      return lines;
    });
  }

  /// The named workers' attendance on the last day before [day] that had
  /// any, for "same as yesterday".
  Future<List<WorkerDay>> lastDay(String day) async => [
    for (final r in await select(db, qLastLabourDay, {
      'farm': farmId,
      'day': day,
    }))
      WorkerDay(
        r.read<String>('worker_id'),
        Attendance.of(
          r.read<int>('attendance'),
          r.readNullable<int>('overtime_hours'),
        ),
        ratePaise: r.read<int>('rate_paise'),
        overtimeHours: r.readNullable<int>('overtime_hours') ?? 0,
        overtimeRatePaise: r.readNullable<int>('overtime_rate_paise') ?? 0,
      ),
  ];

  /// The plot and task of the latest labour entry, for smart defaults.
  Future<(String?, String?)> lastPlotAndTask() async {
    final r = await select(db, qLastLabour, {'farm': farmId});
    if (r.isEmpty) return (null, null);
    return (
      r.single.readNullable<String>('plot_id'),
      r.single.readNullable<String>('task_code'),
    );
  }

  // ---------- writing ----------

  Future<(String, List<String>)> createWorker(
    String name, {
    String? phone,
    int defaultRatePaise = 0,
    bool isFamily = false,
  }) async {
    final id = history.newId();
    final events = await history.writeWithHistory([
      CreateRow(
        'workers',
        {
          'id': id,
          'farm_id': farmId,
          'name': name.trim(),
          'phone': _blank(phone),
          'default_rate_paise': defaultRatePaise,
          'is_family': isFamily,
        },
        summary: {'worker_id': id, 'worker': name.trim()},
      ),
    ]);
    return (id, events);
  }

  Future<List<String>> updateWorker(
    String id,
    String name, {
    String? phone,
    required int defaultRatePaise,
    required bool isFamily,
  }) => history.writeWithHistory([
    UpdateRow(
      'workers',
      id,
      {
        'name': name.trim(),
        'phone': _blank(phone),
        'default_rate_paise': defaultRatePaise,
        'is_family': isFamily,
      },
      summary: {'worker_id': id, 'worker': name.trim()},
    ),
  ]);

  /// Names a group (an unnamed one keeps every entry it has), and sets its
  /// leader, usual size, default rates and members.
  Future<List<String>> updateGroup(
    GroupView g, {
    required String label,
    String? leaderWorkerId,
    int? usualSize,
    Map<String, int> defaultRates = const {},
    List<String> memberIds = const [],
  }) async {
    final current = await _rows(
      'SELECT id, worker_id FROM labour_group_members WHERE group_id = ? '
      'AND deleted_at IS NULL',
      [g.id],
    );
    final have = {
      for (final r in current)
        r.read<String>('worker_id'): r.read<String>('id'),
    };
    final summary = {'group_id': g.id, 'group': label.trim()};
    return history.writeWithHistory([
      UpdateRow('labour_groups', g.id, {
        'label': label.trim(),
        'is_named': label.trim().isNotEmpty,
        'leader_worker_id': leaderWorkerId,
        'usual_size': usualSize,
        'default_rates': defaultRates,
      }, summary: summary),
      for (final w in memberIds)
        if (!have.containsKey(w))
          CreateRow('labour_group_members', {
            'farm_id': farmId,
            'group_id': g.id,
            'worker_id': w,
          }, summary: summary),
      for (final MapEntry(key: w, value: rowId) in have.entries)
        if (!memberIds.contains(w))
          DeleteRow('labour_group_members', rowId, summary: summary),
    ]);
  }

  static String? _blank(String? s) =>
      s == null || s.trim().isEmpty ? null : s.trim();

  /// The rows that post one entry's wage: the crop cycle on the entry, or
  /// allocations by [target]'s weights when it splits.
  List<RowWrite> _posted(
    Map<String, Object?> entry,
    int paise,
    WageTarget target,
    bool manual,
    Map<String, Object?> summary,
  ) {
    final id = history.newId();
    final split = target.cycles.length > 1;
    final parts = split ? splitPaise(paise, target.weights) : const <int>[];
    return [
      CreateRow(
        'labour_entries',
        {
          ...entry,
          'id': id,
          'farm_id': farmId,
          'amount_paise': paise,
          'crop_cycle_id': target.cycles.length == 1
              ? target.cycles.single
              : null,
        },
        occurredOn: entry['work_date']! as String,
        summary: {...summary, 'amount_paise': paise},
      ),
      for (var i = 0; i < parts.length; i++)
        CreateRow('labour_allocations', {
          'farm_id': farmId,
          'labour_entry_id': id,
          'crop_cycle_id': target.cycles[i],
          'amount_paise': parts[i],
          'is_manual': manual,
        }, occurredOn: entry['work_date']! as String),
    ];
  }

  /// Saves a day of named workers in one transaction. Absent workers are
  /// recorded too, at no wage, so their attendance has a history.
  Future<List<String>> saveWorkersDay({
    required String day,
    required List<WorkerDay> workers,
    required WageTarget target,
    String? plotId,
    String? taskCode,
    bool manualSplit = false,
    Map<String, String> names = const {},
    String? plotName,
  }) => history.writeWithHistory([
    for (final w in workers)
      ..._posted(
        {
          'work_date': day,
          'worker_id': w.workerId,
          'plot_id': plotId,
          'task_code': taskCode,
          'attendance': w.attendance.thousandths,
          'wage_type': 'daily',
          'rate_paise': w.ratePaise,
          if (w.attendance == Attendance.overtime) ...{
            'overtime_hours': w.overtimeHours,
            'overtime_rate_paise': w.overtimeRatePaise,
          },
        },
        w.paise,
        target,
        manualSplit,
        {
          'plot_id': ?plotId,
          'plot': ?plotName,
          'worker_id': w.workerId,
          'worker': ?names[w.workerId],
          'task': ?taskCode,
        },
      ),
  ]);

  /// Saves a group's day: one entry per rate class with people, or one
  /// lump sum. With no [groupId] the group is made here, in the same save,
  /// unnamed unless [label] is given.
  Future<List<String>> saveGroupDay({
    required String day,
    String? groupId,
    String label = '',
    required List<GroupLine> lines,
    int? lumpSumPaise,
    int? hours,
    required WageTarget target,
    String? plotId,
    String? taskCode,
    bool manualSplit = false,
    String? plotName,
  }) {
    final id = groupId ?? history.newId();
    final summary = {
      'plot_id': ?plotId,
      'plot': ?plotName,
      'group_id': id,
      'group': label.trim(),
      'task': ?taskCode,
    };
    final base = {
      'work_date': day,
      'group_id': id,
      'plot_id': plotId,
      'task_code': taskCode,
      'hours': hours,
      'wage_type': 'daily',
    };
    final people = [
      for (final l in lines)
        if (l.heads > 0) l,
    ];
    return history.writeWithHistory([
      if (groupId == null)
        CreateRow('labour_groups', {
          'id': id,
          'farm_id': farmId,
          'label': label.trim(),
          'is_named': label.trim().isNotEmpty,
        }, summary: summary),
      if (lumpSumPaise != null)
        ..._posted(
          {
            ...base,
            'head_count': people.fold<int>(0, (s, l) => s + l.heads),
            'amount_overridden': true,
          },
          lumpSumPaise,
          target,
          manualSplit,
          summary,
        )
      else
        for (final l in people)
          ..._posted(
            {
              ...base,
              'rate_class': l.rateClass,
              'head_count': l.heads,
              'rate_paise': l.ratePaise,
            },
            l.paise,
            target,
            manualSplit,
            summary,
          ),
    ]);
  }

  Future<List<String>> addPayment({
    String? workerId,
    String? groupId,
    required PaymentKind kind,
    required int amountPaise,
    required String day,
    String mode = 'cash',
    String? name,
  }) => history.writeWithHistory([
    CreateRow(
      'labour_payments',
      {
        'farm_id': farmId,
        'paid_on': day,
        'worker_id': workerId,
        'group_id': groupId,
        'kind': kind.name,
        'amount_paise': amountPaise,
        'mode': mode,
      },
      occurredOn: day,
      summary: {
        'worker_id': ?workerId,
        'group_id': ?groupId,
        'worker': ?name,
        'amount_paise': amountPaise,
        'kind': kind.name,
      },
    ),
  ]);

  Future<void> undo(List<String> events) => history.undo(events);
}
