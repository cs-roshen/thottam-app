import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:thottam/app/app.dart';
import 'package:thottam/app/router.dart';
import 'package:thottam/app/session.dart';
import 'package:thottam/core/access/access.dart';
import 'package:thottam/core/db/database.dart';
import 'package:thottam/core/history/write_with_history.dart';
import 'package:thottam/features/expenses/data/expense_repository.dart';
import 'package:thottam/features/harvest/data/harvest_repository.dart';
import 'package:thottam/features/harvest/domain/harvest_math.dart';
import 'package:thottam/features/history/data/history_repository.dart';
import 'package:thottam/features/history/domain/history.dart';
import 'package:thottam/features/labour/data/labour_repository.dart';
import 'package:thottam/features/labour/domain/wages.dart';
import 'package:thottam/features/land/data/land_repository.dart';
import 'package:thottam/features/sales/data/sales_repository.dart';

import '../../helpers/screen_golden.dart';
import '../../helpers/session.dart';

/// A day's work on the farm through every repository: a plot edited, an
/// expense, a labour day, a payment, a harvest with two teams and a sale.
Future<void> aDayOfWork(AppDatabase db, History history, String farm) async {
  final land = LandRepository(db, history, farm);
  final plot = (await land.watchPlots().first).single;
  await land.updatePlot(
    plot.id,
    PlotInput(name: 'Riverside', area: 60000, areaUnit: plot.areaUnit),
  );
  await ExpenseRepository(db, history, farm).save(
    ExpenseInput(
      day: '2026-11-18',
      categoryCode: 'fertiliser',
      amountPaise: 360000,
      plotId: plot.id,
      parts: [(plot.cycles.single.id, 360000)],
      plotName: plot.name,
    ),
  );
  final labour = LabourRepository(db, history, farm);
  final (worker, _) = await labour.createWorker(
    'Biju',
    defaultRatePaise: 90000,
  );
  await labour.saveWorkersDay(
    day: '2026-11-18',
    workers: [WorkerDay(worker, Attendance.full, ratePaise: 90000)],
    target: WageTarget.one(plot.cycles.single.id),
    plotId: plot.id,
    plotName: plot.name,
    names: {worker: 'Biju'},
  );
  await labour.addPayment(
    workerId: worker,
    kind: PaymentKind.part,
    amountPaise: 50000,
    day: '2026-11-19',
    name: 'Biju',
  );
  final (harvest, _) = await HarvestRepository(db, history, farm).save(
    HarvestInput(
      day: '2026-11-19',
      plotId: plot.id,
      cycleId: plot.cycles.single.id,
      unit: 'kg',
      teams: const [
        HarvestTeam(heads: 3, ratePaise: 80000),
        HarvestTeam(heads: 2, ratePaise: 80000),
      ],
      perTeam: false,
      total: 100000,
      plotName: 'Riverside',
      cropMl: 'കുരുമുളക്',
      cropEn: 'Pepper',
    ),
    canWriteMoney: true,
  );
  final lot =
      (await db
              .customSelect("SELECT id FROM lots WHERE harvest_id = '$harvest'")
              .getSingle())
          .read<String>('id');
  await SalesRepository(db, history, farm).save(
    SaleInput(
      day: '2026-11-19',
      quantity: 40000,
      unit: 'kg',
      ratePaise: 70500,
      takes: [(lot, 40000)],
      newBuyer: 'Joseph',
      cropMl: 'കുരുമുളക്',
      cropEn: 'Pepper',
    ),
  );
}

void main() {
  group('repository', () {
    late AppDatabase db;
    late String farm;
    late HistoryRepository repo;

    setUp(() async {
      final (d, f) = await farmDatabase(
        crops: const ['Pepper'],
        seed: aDayOfWork,
      );
      db = d;
      farm = f;
      var now = DateTime(2026, 11, 19, 12);
      repo = HistoryRepository(
        db,
        History(
          db,
          userId: testUser,
          clock: () => now = now.add(const Duration(milliseconds: 10)),
          random: Random(5),
        ),
        farm,
      );
    });
    tearDown(() => db.close());

    Future<List<HistoryEvent>> diary(
      HistoryFilter f, {
      Access access = const Access('owner'),
      String plot = '',
    }) => repo
        .watchDiary(
          entities: asParam(entitiesFor(f, access)),
          actions: asParam(actionsFor(f)),
          plotId: plot,
        )
        .first;

    test('every create and edit from every screen is in the diary, newest '
        'day first; parts of a save show through their record', () async {
      final events = await diary(HistoryFilter.all);
      final seen = {for (final e in events) '${e.entity} ${e.action}'};
      expect(
        seen,
        containsAll([
          'farms create',
          'plots create',
          'plots update',
          'crop_cycles create',
          'expenses create',
          'workers create',
          'labour_entries create',
          'labour_payments create',
          'harvests create',
          'lot_costs create',
          'sales create',
          'parties create',
        ]),
      );
      // the payment made with the sale shows through the sale
      expect(seen, isNot(contains('sale_payments create')));
      // no splits, sale lots or harvest teams of their own
      expect(
        events.where(
          (e) =>
              e.entity.endsWith('allocations') ||
              e.entity == 'sale_lots' ||
              e.entity == 'lots',
        ),
        isEmpty,
      );
      expect(events.where((e) => e.entity == 'labour_entries'), hasLength(1));
      expect(events.first.day, '2026-11-19');
      expect(events.last.day.compareTo(events.first.day) <= 0, isTrue);
    });

    test('a supervisor sees no money in the history', () async {
      final events = await diary(
        HistoryFilter.all,
        access: const Access('supervisor'),
      );
      expect(
        events.map((e) => e.entity).toSet().intersection({
          'expenses',
          'sales',
          'sale_payments',
          'labour_payments',
          'lot_costs',
          'parties',
        }),
        isEmpty,
      );
      expect(events.any((e) => e.entity == 'harvests'), isTrue);
    });

    test('filters: expense, labour, edits; and one plot', () async {
      expect(
        (await diary(HistoryFilter.expense)).map((e) => e.entity).toSet(),
        {'expenses'},
      );
      expect((await diary(HistoryFilter.labour)).map((e) => e.entity).toSet(), {
        'workers',
        'labour_entries',
        'labour_payments',
      });
      expect(
        (await diary(HistoryFilter.edits))
            .map((e) => '${e.entity} ${e.action}'),
        ['plots update'],
      );
      final plot = (await db.customSelect('SELECT id FROM plots').getSingle())
          .read<String>('id');
      final onPlot = await diary(HistoryFilter.all, plot: plot);
      expect(onPlot.any((e) => e.entity == 'expenses'), isTrue);
      expect(onPlot.any((e) => e.entity == 'farms'), isFalse);
    });

    test('an edit carries old and new values; restore puts them back, and '
        'warns only when the record changed again', () async {
      final edit = (await diary(HistoryFilter.edits)).single;
      expect(changes(edit.oldValues, edit.newValues), [('area', 50000, 60000)]);
      expect(await repo.changedSince(edit), isFalse);
      final created = (await diary(HistoryFilter.all))
          .firstWhere((e) => e.entity == 'plots' && e.action == 'create');
      expect(await repo.changedSince(created), isTrue);

      final undo = await repo.restore(edit);
      final area = (await db.customSelect('SELECT area FROM plots').getSingle())
          .read<int>('area');
      expect(area, 50000);
      final timeline = await repo.watchRecord('plots', edit.entityId).first;
      expect(timeline.map((e) => e.action), ['restore', 'update', 'create']);
      await repo.undo(undo);
      expect(
        (await db.customSelect('SELECT area FROM plots').getSingle()).read<int>(
          'area',
        ),
        60000,
      );
    });

    test('this week last year counts that week only', () async {
      expect(await repo.countBetween('2025-11-16', '2025-11-22', ',plots,'), 0);
      expect(await repo.countBetween('2026-11-16', '2026-11-22', ',plots,'), 2);
    });
  });

  group('screen', () {
    late ProviderContainer container;

    Future<void> pumpHistory(
      WidgetTester tester, {
      String role = 'owner',
      bool small = false,
    }) async {
      // 412 dp wide, or 360 dp, the narrowest phones in use
      tester.view.physicalSize = small
          ? const Size(720, 1480)
          : const Size(1080, 2400);
      tester.view.devicePixelRatio = small ? 2 : 2.625;
      addTearDown(tester.view.reset);
      final (db, farm) = await farmDatabase(
        crops: const ['Pepper'],
        role: role,
        seed: aDayOfWork,
      );
      container = ProviderContainer(overrides: farmOverrides(db, farm));
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const ThottamApp(),
        ),
      );
      await settle(tester);
      container.read(routerProvider).push('/history');
      await settle(tester);
      await tester.pump(const Duration(seconds: 1));
    }

    Future<void> tap(WidgetTester tester, Finder f) async {
      if (f.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          f,
          200,
          scrollable: find.byType(Scrollable).first,
        );
      }
      await tester.ensureVisible(f);
      await tester.pump();
      await tester.tap(f);
      await settle(tester);
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('the diary groups by day, signs money, and an edit opens '
        'old → new and puts it back', (tester) async {
      await pumpHistory(tester);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Sale added'), findsOneWidget);
      expect(find.text('+ ₹28,200'), findsWidgets);
      await tester.scrollUntilVisible(
        find.text('Yesterday'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Yesterday'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('history.filter.expense')),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await tap(tester, find.byKey(const Key('history.filter.expense')));
      expect(find.text('− ₹3,600'), findsOneWidget);
      await tap(tester, find.byKey(const Key('history.filter.edits')));
      await tap(tester, find.text('Plot changed'));
      expect(find.text('Area corrected: 50 → 60'), findsOneWidget);
      await tap(tester, find.byKey(const Key('event.restore')));
      expect(find.text('Put back'), findsOneWidget);
      expect(find.text('Plot brought back'), findsOneWidget);
    });

    testWidgets('restoring an older change asks first', (tester) async {
      await pumpHistory(tester);
      // the plot is changed once more, after the change being restored
      final db = container.read(databaseProvider);
      final land = LandRepository(
        db,
        History(db, userId: testUser),
        container.read(farmIdProvider),
      );
      final plot = (await land.watchPlots().first).single;
      await land.updatePlot(
        plot.id,
        PlotInput(name: 'Riverside farm', area: 60000, areaUnit: plot.areaUnit),
      );
      await settle(tester);
      await tap(tester, find.byKey(const Key('history.filter.edits')));
      expect(find.text('Plot changed'), findsNWidgets(2));
      await tap(tester, find.text('Plot changed').last);
      await tap(tester, find.byKey(const Key('event.restore')));
      expect(find.text('It changed again after this'), findsOneWidget);
      await tap(tester, find.byKey(const Key('restore.cancel')));
      expect(find.text('Plot brought back'), findsNothing);
    });

    testWidgets('a supervisor sees no money events', (tester) async {
      await pumpHistory(tester, role: 'supervisor');
      expect(find.text('Harvest added'), findsOneWidget);
      expect(find.text('Sale added'), findsNothing);
      expect(find.text('Expense added'), findsNothing);
      expect(find.byKey(const Key('history.filter.sales')), findsNothing);
    });

    testWidgets('history fits a small phone at the largest text', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpHistory(tester, small: true);
      await tap(tester, find.byKey(const Key('history.filter.edits')));
      await tap(tester, find.text('Plot changed'));
      expect(find.byKey(const Key('event.restore')), findsOneWidget);
    });
  });
}
