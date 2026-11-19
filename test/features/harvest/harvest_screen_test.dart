import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:thottam/app/app.dart';
import 'package:thottam/app/router.dart';
import 'package:thottam/core/db/database.dart';
import 'package:thottam/core/history/write_with_history.dart';

import '../../helpers/screen_golden.dart';
import '../../helpers/session.dart';

/// Biju, ₹1,000 a day.
Future<void> biju(AppDatabase db, History history, String farm) =>
    history.writeWithHistory([
      CreateRow('workers', {
        'id': 'w-biju',
        'farm_id': farm,
        'name': 'Biju',
        'default_rate_paise': 100000,
      }),
    ]);

void main() {
  late ProviderContainer container;

  Future<AppDatabase> pumpHarvest(
    WidgetTester tester, {
    String role = 'owner',
    String path = '/add/harvest',
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final (db, farm) = await farmDatabase(
      crops: const ['Pepper'],
      role: role,
      seed: biju,
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
    container.read(routerProvider).push(path);
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    return db;
  }

  Finder key(String k) => find.byKey(Key(k));

  Future<void> reveal(WidgetTester tester, Finder f) async {
    if (f.evaluate().isEmpty) {
      final list = find.byType(Scrollable).first;
      try {
        await tester.scrollUntilVisible(
          f,
          200,
          scrollable: list,
          maxScrolls: 30,
        );
      } on StateError {
        await tester.scrollUntilVisible(f, -200, scrollable: list);
      }
    }
    await tester.ensureVisible(f);
    await tester.pump();
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await reveal(tester, f);
    await tester.tap(f);
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> type(WidgetTester tester, String k, String text) async {
    await reveal(tester, key(k));
    await tester.enterText(key(k), text);
    await settle(tester);
  }

  Future<void> heads(WidgetTester tester, int team, int count) async {
    for (var i = 1; i < count; i++) {
      await tap(
        tester,
        find.descendant(
          of: key('harvest.team.$team.heads'),
          matching: find.byIcon(Icons.add),
        ),
      );
    }
  }

  String sum(WidgetTester tester, String k) =>
      tester.widget<Text>(key('harvest.sum.$k')).data!;

  /// The spec's three teams.
  Future<void> specTeams(WidgetTester tester, {required bool perTeam}) async {
    if (perTeam) await tap(tester, key('harvest.perTeam'));
    await tap(tester, key('harvest.addGroup'));
    await heads(tester, 0, 6);
    if (perTeam) await type(tester, 'harvest.team.0.quantity', '75');
    await tap(tester, key('harvest.addGroup'));
    await heads(tester, 1, 3);
    await type(tester, 'harvest.team.1.rate', '900');
    if (perTeam) await type(tester, 'harvest.team.1.quantity', '30');
    await tap(tester, key('harvest.addNamed'));
    await tap(tester, key('harvest.pick.w-biju'));
    if (perTeam) await type(tester, 'harvest.team.2.quantity', '15');
  }

  testWidgets('per-team quantity on: 120 kg, 12 kg per person, ₹70.83 per '
      'kg, wages ₹8,500; save opens the lot with its cost', (tester) async {
    await pumpHarvest(tester);
    await specTeams(tester, perTeam: true);
    await reveal(tester, key('harvest.sum.wages'));
    expect(sum(tester, 'quantity'), '120 kg');
    expect(sum(tester, 'perPerson'), '12 kg');
    expect(sum(tester, 'costPerUnit'), '₹70.83 / kg');
    expect(sum(tester, 'wages'), '₹8,500');
    await reveal(tester, find.text('12.5 kg per person · ₹64 per kg'));
    expect(find.text('12.5 kg per person · ₹64 per kg'), findsOneWidget);
    await tap(tester, key('harvest.save'));
    expect(find.text('120 kg'), findsOneWidget);
    expect(tester.widget<Text>(key('lot.cost')).data, '₹8,500');
    expect(tester.widget<Text>(key('lot.costPerUnit')).data, '₹70.83 per kg');
  });

  testWidgets('per-team quantity off: the total entered, same summary', (
    tester,
  ) async {
    await pumpHarvest(tester);
    await type(tester, 'harvest.total', '120');
    await specTeams(tester, perTeam: false);
    await reveal(tester, key('harvest.sum.wages'));
    expect(sum(tester, 'quantity'), '120 kg');
    expect(sum(tester, 'perPerson'), '12 kg');
    expect(sum(tester, 'costPerUnit'), '₹70.83 / kg');
    expect(key('harvest.team.0.quantity'), findsNothing);
  });

  testWidgets('removing a team recalculates', (tester) async {
    await pumpHarvest(tester);
    await specTeams(tester, perTeam: true);
    await tap(tester, key('harvest.team.1.remove'));
    await reveal(tester, key('harvest.sum.wages'));
    expect(sum(tester, 'quantity'), '90 kg');
    expect(sum(tester, 'wages'), '₹5,800');
  });

  testWidgets('with the switch off a piece-rate team still enters its '
      'quantity', (tester) async {
    await pumpHarvest(tester);
    await type(tester, 'harvest.total', '100');
    await tap(tester, key('harvest.addGroup'));
    expect(key('harvest.team.0.quantity'), findsNothing);
    await tap(tester, key('harvest.team.0.piece'));
    await type(tester, 'harvest.team.0.rate', '6');
    await type(tester, 'harvest.team.0.quantity', '40');
    await reveal(tester, key('harvest.sum.wages'));
    expect(sum(tester, 'wages'), '₹240');
    expect(sum(tester, 'quantity'), '100 kg');
  });

  testWidgets('the lot cost can be changed by hand, is marked, and resets', (
    tester,
  ) async {
    await pumpHarvest(tester);
    await specTeams(tester, perTeam: true);
    await tap(tester, key('harvest.save'));
    await tap(tester, key('lot.edit'));
    await tester.enterText(key('lot.costField'), '9000');
    await tap(tester, key('lot.costSave'));
    expect(tester.widget<Text>(key('lot.cost')).data, '₹9,000');
    expect(find.text('Changed by hand'), findsOneWidget);
    await tap(tester, key('lot.recalculate'));
    expect(tester.widget<Text>(key('lot.cost')).data, '₹8,500');
    expect(find.text('Changed by hand'), findsNothing);
  });

  testWidgets("a supervisor's harvest saves without a cost; the screen "
      'shows none', (tester) async {
    final db = await pumpHarvest(tester, role: 'supervisor');
    await specTeams(tester, perTeam: true);
    await tap(tester, key('harvest.save'));
    expect(find.text('120 kg'), findsOneWidget);
    expect(key('lot.cost'), findsNothing);
    final costs = await db
        .customSelect('SELECT COUNT(*) AS n FROM lot_costs')
        .getSingle();
    expect(costs.data['n'], 0);
  });

  testWidgets('the harvest screen fits a small phone at the largest text', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpHarvest(tester);
    tester.view.physicalSize = const Size(720, 1480);
    tester.view.devicePixelRatio = 2;
    await settle(tester);
    await tap(tester, key('harvest.perTeam'));
    await tap(tester, key('harvest.addGroup'));
    await tap(tester, key('harvest.addNamed'));
    await tap(tester, key('harvest.pick.w-biju'));
    await reveal(tester, key('harvest.sum.wages'));
    expect(key('harvest.sum.wages'), findsOneWidget);
  });
}
