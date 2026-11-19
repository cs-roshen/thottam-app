import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:thottam/app/app.dart';
import 'package:thottam/app/router.dart';
import 'package:thottam/core/db/database.dart';
import 'package:thottam/core/history/write_with_history.dart';

import '../../helpers/screen_golden.dart';
import '../../helpers/session.dart';

/// Four workers: Biju ₹900, Sali ₹900, Raju ₹700, Anu ₹900.
Future<void> fourWorkers(AppDatabase db, History history, String farm) =>
    history.writeWithHistory([
      for (final (id, name, rate) in [
        ('w1', 'Biju', 90000),
        ('w2', 'Sali', 90000),
        ('w3', 'Raju', 70000),
        ('w4', 'Anu', 90000),
      ])
        CreateRow('workers', {
          'id': id,
          'farm_id': farm,
          'name': name,
          'default_rate_paise': rate,
        }),
    ]);

void main() {
  late ProviderContainer container;

  Future<AppDatabase> pumpLabour(
    WidgetTester tester, {
    List<String> crops = const ['Coconut'],
    String role = 'owner',
    String path = '/add/labour',
    Future<void> Function(AppDatabase, History, String)? seed = fourWorkers,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final (db, farm) = await farmDatabase(crops: crops, role: role, seed: seed);
    container = ProviderContainer(overrides: farmOverrides(db, farm));
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ThottamApp(),
      ),
    );
    await settle(tester);
    container.read(routerProvider).push(path);
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    return db;
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    if (f.evaluate().isEmpty) {
      // a lazy list builds what is near the screen only: look down, then up
      final list = find.byType(Scrollable).first;
      try {
        await tester.scrollUntilVisible(
          f,
          200,
          scrollable: list,
          maxScrolls: 20,
        );
      } on StateError {
        await tester.scrollUntilVisible(f, -200, scrollable: list);
      }
    }
    await tester.ensureVisible(f);
    await tester.pump(); // the scroll lands on the next frame
    await tester.tap(f);
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
  }

  Finder key(String k) => find.byKey(Key(k));
  String total(WidgetTester tester) =>
      tester.widget<Text>(key('labour.total')).data!;

  Future<int> count(AppDatabase db, String sql) async =>
      (await db.customSelect(sql).getSingle()).data.values.first! as int;

  testWidgets('full, full, half, absent → ₹2,150, live as the farmer marks; '
      'save records four days', (tester) async {
    final db = await pumpLabour(tester);
    expect(total(tester), '₹0');
    await tap(tester, key('worker.w1.full'));
    await tap(tester, key('worker.w2.full'));
    await tap(tester, key('worker.w3.half'));
    await tap(tester, key('worker.w4.absent'));
    expect(total(tester), '₹2,150');
    await tap(tester, key('labour.save'));
    expect(find.text('Saved'), findsOneWidget);
    expect(await count(db, 'SELECT COUNT(*) FROM labour_entries'), 4);
    expect(
      await count(db, 'SELECT SUM(amount_paise) FROM labour_entries'),
      215000,
    );
  });

  testWidgets('overtime: a full day plus 2 hours at the template rate of '
      '₹150 → ₹1,200', (tester) async {
    await pumpLabour(tester);
    await tap(tester, key('worker.w1.overtime'));
    expect(total(tester), '₹1,050'); // one extra hour to start
    await tap(
      tester,
      find.descendant(
        of: key('worker.w1.hours'),
        matching: find.byIcon(Icons.add),
      ),
    );
    expect(total(tester), '₹1,200');
  });

  testWidgets('a group of 5 general and 1 climber → ₹5,200 with no names', (
    tester,
  ) async {
    final db = await pumpLabour(tester, seed: null);
    await tap(tester, find.text('Group (head count)'));
    for (var i = 0; i < 5; i++) {
      await tap(
        tester,
        find.descendant(
          of: key('labour.class.general'),
          matching: find.byIcon(Icons.add),
        ),
      );
    }
    await tap(
      tester,
      find.descendant(
        of: key('labour.class.climber'),
        matching: find.byIcon(Icons.add),
      ),
    );
    expect(total(tester), '₹5,200');
    await tap(tester, key('labour.save'));
    expect(await count(db, 'SELECT COUNT(*) FROM labour_groups'), 1);
    expect(
      await count(db, 'SELECT SUM(amount_paise) FROM labour_entries'),
      520000,
    );
  });

  testWidgets('a mixed plot shows the split by template share, editable by '
      'hand, always summing to the wage', (tester) async {
    final db = await pumpLabour(tester, crops: const ['Coconut', 'Pepper']);
    await tap(tester, key('worker.w1.full'));
    // ₹900 at 60 / 30
    expect(find.text('₹600'), findsOneWidget);
    expect(find.text('₹300'), findsOneWidget);
    await tap(tester, key('split.edit'));
    await tester.enterText(key('split.part.0'), '500');
    await settle(tester);
    await tap(tester, key('labour.save'));
    final parts = await db
        .customSelect(
          'SELECT amount_paise, is_manual FROM labour_allocations '
          'ORDER BY created_at',
        )
        .get();
    expect(parts.map((p) => p.data['amount_paise']), [50000, 40000]);
    expect(parts.every((p) => p.data['is_manual'] == 1), isTrue);
  });

  testWidgets('"same as yesterday" marks the workers as on the last day', (
    tester,
  ) async {
    await pumpLabour(
      tester,
      seed: (db, history, farm) async {
        await fourWorkers(db, history, farm);
        await history.writeWithHistory([
          CreateRow('labour_entries', {
            'farm_id': farm,
            'work_date': '2026-11-18',
            'worker_id': 'w3',
            'attendance': 500,
            'rate_paise': 70000,
            'amount_paise': 35000,
          }),
        ]);
      },
    );
    await tap(tester, key('labour.same'));
    expect(total(tester), '₹350');
  });

  testWidgets('a viewer cannot save a day', (tester) async {
    await pumpLabour(tester, role: 'viewer');
    expect(
      find.text('Only the owner, a manager or a supervisor can record work.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.descendant(
              of: key('labour.save'),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('pay a worker from their ledger; the balance follows', (
    tester,
  ) async {
    await pumpLabour(
      tester,
      path: '/labour/worker/w1',
      seed: (db, history, farm) async {
        await fourWorkers(db, history, farm);
        await history.writeWithHistory([
          CreateRow('labour_entries', {
            'farm_id': farm,
            'work_date': '2026-11-18',
            'worker_id': 'w1',
            'rate_paise': 90000,
            'amount_paise': 90000,
          }),
        ]);
      },
    );
    expect(find.text('Due ₹900'), findsOneWidget);
    await tap(tester, key('ledger.pay'));
    await tester.enterText(key('pay.amount'), '400');
    await tap(tester, key('pay.kind.part'));
    await tap(tester, key('pay.save'));
    expect(find.text('Due ₹500'), findsOneWidget);
    expect(find.text('Part payment'), findsOneWidget);
  });

  testWidgets('a supervisor sees workers but no balances or payments', (
    tester,
  ) async {
    await pumpLabour(tester, role: 'supervisor', path: '/labour/team');
    expect(find.text('Biju'), findsOneWidget);
    expect(find.textContaining('Due'), findsNothing);
    expect(find.text('Settled'), findsNothing);
    await tap(tester, find.text('Biju'));
    expect(key('ledger.pay'), findsNothing);
  });

  testWidgets('add a worker from the attendance screen', (tester) async {
    await pumpLabour(tester, seed: null);
    expect(
      find.text(
        'No workers yet. Add the people who work here, or use Group for a '
        'head count.',
      ),
      findsOneWidget,
    );
    await tap(tester, key('labour.addWorker'));
    await tester.enterText(key('workerForm.name'), 'Biju');
    await tester.enterText(key('workerForm.rate'), '900');
    await tap(tester, key('workerForm.save'));
    expect(find.text('Biju'), findsOneWidget);
    expect(find.text('₹900 / day'), findsOneWidget);
  });

  testWidgets('labour fits a small phone at the largest text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpLabour(tester, crops: const ['Coconut', 'Pepper']);
    tester.view.physicalSize = const Size(720, 1480);
    tester.view.devicePixelRatio = 2;
    await settle(tester);
    await tap(tester, key('worker.w1.overtime'));
    await tap(tester, find.text('Group (head count)'));
    await tap(tester, key('labour.lump'));
    expect(key('labour.lumpAmount'), findsOneWidget);
  });
}
