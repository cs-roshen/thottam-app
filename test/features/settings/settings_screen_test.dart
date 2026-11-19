import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:thottam/app/app.dart';
import 'package:thottam/app/router.dart';
import 'package:thottam/app/session.dart';
import 'package:thottam/app/settings.dart';
import 'package:thottam/core/db/database.dart';
import 'package:thottam/core/history/write_with_history.dart';
import 'package:thottam/features/land/data/land_repository.dart';
import 'package:thottam/features/onboarding/data/onboarding_repository.dart';
import 'package:thottam/features/onboarding/domain/setup.dart';

import '../../helpers/screen_golden.dart';
import '../../helpers/session.dart';

/// Riverside with pepper, a second farm "Hill garden" with one plot "Top",
/// and a supervisor "Anu" on Riverside.
Future<void> twoFarms(AppDatabase db, History history, String farm) async {
  final hill = await OnboardingRepository(db, history).createFarm(
    testUser,
    const SetupInput(
      name: 'Ravi',
      farmName: 'Hill garden',
      area: 10000,
      areaUnit: 'cent',
      cropIds: [],
    ),
  );
  await LandRepository(db, history, hill).updatePlot(
    (await LandRepository(db, history, hill).watchPlots().first).single.id,
    const PlotInput(name: 'Top', areaUnit: 'cent', area: 10000),
  );
  await db.customStatement(
    'INSERT INTO profiles (id, full_name, created_at, updated_at) '
    "VALUES ('user-anu', 'Anu', 0, 0)",
  );
  await history.writeWithHistory([
    CreateRow('farm_members', {
      'id': 'member-anu',
      'farm_id': farm,
      'user_id': 'user-anu',
      'role': 'supervisor',
    }),
  ]);
}

void main() {
  late ProviderContainer container;

  Future<void> pumpApp(
    WidgetTester tester, {
    String role = 'owner',
    String path = '/more/settings',
    bool small = false,
    Map<String, Object?> prefs = const {'settings.language': 'english'},
  }) async {
    tester.view.physicalSize = small
        ? const Size(720, 1480)
        : const Size(1080, 2400);
    tester.view.devicePixelRatio = small ? 2 : 2.625;
    addTearDown(tester.view.reset);
    final (db, farm) = await farmDatabase(
      crops: const ['Pepper'],
      role: role,
      seed: twoFarms,
    );
    container = ProviderContainer(overrides: farmOverrides(db, farm, prefs));
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ThottamApp(),
      ),
    );
    await settle(tester);
    container.read(routerProvider).go(path);
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

  Future<void> openQuickAdd(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('Add'));
    await settle(tester);
  }

  Future<int> scalar(String sql) async =>
      (await container.read(databaseProvider).customSelect(sql).getSingle())
          .read<int>('n');

  testWidgets('hiding a page removes it from More and quick add', (
    tester,
  ) async {
    await pumpApp(tester, path: '/more');
    expect(find.byKey(const Key('more.page.harvest')), findsOneWidget);
    await openQuickAdd(tester);
    expect(find.byKey(const Key('quickAdd./add/harvest')), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await settle(tester);

    await tap(tester, find.byKey(const Key('more.settings')));
    await tap(tester, find.byKey(const Key('settings.page.harvest')));
    await tap(tester, find.byKey(const Key('settings.page.sell')));
    container.read(routerProvider).go('/more');
    await settle(tester);
    expect(find.byKey(const Key('more.page.harvest')), findsNothing);
    expect(find.byKey(const Key('more.page.sell')), findsNothing);
    expect(find.byKey(const Key('more.page.history')), findsOneWidget);
    await openQuickAdd(tester);
    expect(find.byKey(const Key('quickAdd./add/harvest')), findsNothing);
    expect(find.byKey(const Key('quickAdd./add/sale')), findsNothing);
    expect(find.byKey(const Key('quickAdd./add/expense')), findsOneWidget);
  });

  testWidgets('a Home card switched off leaves Home; reset brings every '
      'page and card back', (tester) async {
    await pumpApp(tester);
    await tap(tester, find.byKey(const Key('settings.page.history')));
    await tap(tester, find.byKey(const Key('settings.card.tasks')));
    container.read(routerProvider).go('/home');
    await settle(tester);
    expect(find.byKey(const Key('home.tasks')), findsNothing);
    container.read(routerProvider).go('/more/settings');
    await settle(tester);
    await tap(tester, find.byKey(const Key('settings.reset')));
    expect(find.text('Reset done'), findsOneWidget);
    container.read(routerProvider).go('/home');
    await settle(tester);
    expect(find.byKey(const Key('home.tasks')), findsOneWidget);
  });

  testWidgets('language and large text apply at once', (tester) async {
    await pumpApp(tester);
    await tap(tester, find.byKey(const Key('settings.language.malayalam')));
    expect(find.text('ക്രമീകരണം'), findsWidgets);
    await tap(tester, find.byKey(const Key('settings.largeText')));
    final scaler = MediaQuery.textScalerOf(
      tester.element(find.byType(ListView).first),
    );
    expect(scaler.scale(10), closeTo(11.2, 0.01));
  });

  testWidgets('a supervisor sees no Members and no Selling', (tester) async {
    await pumpApp(tester, role: 'supervisor');
    expect(find.byKey(const Key('settings.members')), findsNothing);
    container.read(routerProvider).go('/more');
    await settle(tester);
    expect(find.byKey(const Key('more.page.sell')), findsNothing);
    expect(find.byKey(const Key('more.page.history')), findsOneWidget);
    await openQuickAdd(tester);
    expect(find.byKey(const Key('quickAdd./add/expense')), findsNothing);
    expect(find.byKey(const Key('quickAdd./add/labour')), findsOneWidget);
  });

  testWidgets('switching farm shows only that farm\'s data', (tester) async {
    await pumpApp(tester);
    await tap(tester, find.byKey(const Key('settings.farms')));
    expect(find.text('Hill garden'), findsOneWidget);
    expect(find.text('Open now'), findsOneWidget);
    await tap(tester, find.text('Hill garden'));
    expect(find.text('Hill garden is open'), findsOneWidget);
    container.read(routerProvider).go('/land');
    await settle(tester);
    expect(find.text('Top'), findsOneWidget);
    expect(find.text('Riverside'), findsNothing);
  });

  testWidgets('adding a farm takes the farm and crop steps, then opens it', (
    tester,
  ) async {
    await pumpApp(tester, path: '/more/settings/farms');
    await tap(tester, find.byKey(const Key('farms.add')));
    expect(find.text('Step 1 / 2'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'East field');
    await tap(tester, find.byKey(const Key('setup.next')));
    expect(find.text('Step 2 / 2'), findsOneWidget);
    await tap(tester, find.byKey(const Key('setup.next')));
    expect(find.text('East field is open'), findsOneWidget);
    expect(container.read(farmIdProvider), isNot(anyOf('farm-test', isEmpty)));
    final farms = await scalar(
      "SELECT COUNT(*) AS n FROM farm_members WHERE user_id = '$testUser'",
    );
    expect(farms, 3);
  });

  testWidgets('members: invite by email, change a permission, remove', (
    tester,
  ) async {
    await pumpApp(tester, path: '/more/settings/members');
    expect(find.text('Ravi (you)'), findsOneWidget);
    expect(find.text('Anu'), findsOneWidget);

    await tap(tester, find.byKey(const Key('members.add')));
    await tap(tester, find.byKey(const Key('invite.save')));
    expect(find.text('Enter an email address'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('invite.email')),
      'biju@gmail.com',
    );
    await tap(tester, find.byKey(const Key('invite.role.accountant')));
    await tap(tester, find.byKey(const Key('invite.save')));
    expect(find.text('biju@gmail.com'), findsOneWidget);
    expect(find.text('Invited · Accountant'), findsOneWidget);

    await tap(tester, find.text('Anu'));
    await tap(
      tester,
      find.descendant(
        of: find.byKey(const Key('member.area.money')),
        matching: find.text('See'),
      ),
    );
    expect(
      await scalar(
        "SELECT COUNT(*) AS n FROM farm_members WHERE id = 'member-anu' "
        "AND permissions = '{\"money\":\"read\"}'",
      ),
      1,
    );
    await tap(tester, find.byKey(const Key('member.remove')));
    expect(
      find.text('Anu will no longer see or write this farm.'),
      findsOneWidget,
    );
    await tap(tester, find.byKey(const Key('member.remove.confirm')));
    expect(find.text('Anu'), findsNothing);
    expect(
      await scalar(
        "SELECT COUNT(*) AS n FROM outbox WHERE entity = 'farm_members'",
      ),
      greaterThanOrEqualTo(2),
    );
  });

  testWidgets('signing out with changes waiting warns first and loses '
      'nothing', (tester) async {
    await pumpApp(tester);
    final waiting = await scalar(
      "SELECT COUNT(*) AS n FROM outbox WHERE status = 'pending' "
      "AND entity <> 'event_log'",
    );
    expect(waiting, greaterThan(0));
    await tap(tester, find.byKey(const Key('settings.signOut')));
    expect(find.text('Changes still waiting to sync'), findsOneWidget);
    await tap(tester, find.byKey(const Key('signOut.cancel')));
    expect(container.read(sessionProvider).account, isNotNull);

    await tap(tester, find.byKey(const Key('settings.signOut')));
    await tap(tester, find.byKey(const Key('signOut.confirm')));
    expect(container.read(sessionProvider).account, isNull);
    // nothing is deleted: the user's own database file stays, and the
    // phone still knows their farm for the next sign-in
    expect(container.read(deviceStoreProvider).get('session.user.$testUser'), {
      'first_synced': true,
      'farm': isNotNull,
    });
  });

  testWidgets('My lists: switch an activity off and reset it', (tester) async {
    await pumpApp(tester, path: '/more/lists');
    await tap(tester, find.text('Pepper'));
    await tap(tester, find.byKey(const Key('lists.switch.mulching')));
    expect(find.text('Changed · usually on'), findsOneWidget);
    await tap(tester, find.byKey(const Key('lists.add')));
    await tester.enterText(find.byKey(const Key('own.en')), 'Tie pepper vines');
    await tap(tester, find.byKey(const Key('own.save')));
    expect(find.text('Tie pepper vines'), findsOneWidget);
    expect(find.text('Your own'), findsOneWidget);
    // the "Saved" toast has gone and no longer covers the button: its
    // timer starts once it is shown, so time moves on in steps
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tap(tester, find.byKey(const Key('lists.reset')));
    expect(find.text('Changed · usually on'), findsNothing);
    expect(find.text('Tie pepper vines'), findsOneWidget);
  });

  testWidgets('Malayalam, large text, on a 360 dp phone: nothing overflows', (
    tester,
  ) async {
    await pumpApp(
      tester,
      small: true,
      prefs: const {
        'settings.language': 'malayalam',
        'settings.large_text': true,
      },
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings.signOut')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    container.read(routerProvider).go('/more/settings/members');
    await settle(tester);
    await tap(tester, find.text('Anu'));
    container.read(routerProvider).go('/more');
    await settle(tester);
    expect(tester.takeException(), isNull);
  });
}
