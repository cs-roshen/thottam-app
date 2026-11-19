import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:thottam/app/app.dart';
import 'package:thottam/app/session.dart';
import 'package:thottam/core/db/database.dart';
import 'package:thottam/core/history/write_with_history.dart';
import 'package:thottam/core/prefs/device_store.dart';
import 'package:thottam/core/sync/bundled_templates.dart';
import 'package:thottam/core/sync/sync_engine.dart';
import 'package:thottam/core/sync/sync_server.dart';
import 'package:thottam/features/onboarding/data/onboarding_providers.dart';
import 'package:thottam/features/onboarding/data/onboarding_repository.dart';
import 'package:thottam/features/onboarding/domain/setup.dart';

import '../../core/sync/fake_server.dart';
import '../../helpers/session.dart';

const owner = 'user-owner';

/// A phone on its first run: nothing chosen, nobody signed in. The test
/// account it signs in with is [owner].
MemoryDeviceStore freshStore([Map<String, Object?> extra = const {}]) =>
    MemoryDeviceStore({'auth.test_account_id': owner, ...extra});

void main() {
  setUp(
    () => FirstSyncController.retryAfter = (_) => const Duration(seconds: 1),
  );

  late ProviderContainer container;

  Future<void> pumpApp(
    WidgetTester tester,
    DeviceStore store, {
    FakeServer? server,
    AppDatabase Function()? database,
  }) async {
    // a typical phone screen, 412 x 915
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    container = ProviderContainer(
      overrides: appOverrides(
        store: store,
        database: database,
        server: server == null ? null : (user) => server.as(user),
      ),
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ThottamApp(),
      ),
    );
    await settle(tester);
  }

  Future<void> reveal(WidgetTester tester, String key) async {
    if (find.byKey(Key(key)).evaluate().isEmpty) {
      // a lazy list builds what is near the screen only
      await tester.scrollUntilVisible(
        find.byKey(Key(key)),
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(find.byKey(Key(key)));
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await reveal(tester, key);
    await tester.tap(find.byKey(Key(key)));
    await settle(tester);
  }

  Future<void> type(WidgetTester tester, String key, String text) async {
    await reveal(tester, key);
    await tester.enterText(find.byKey(Key(key)), text);
    await settle(tester);
  }

  String? title(WidgetTester tester) => tester
      .widgetList<AppBar>(find.byType(AppBar))
      .map((b) => (b.title as Text?)?.data)
      .lastOrNull;

  testWidgets('first launch opens the welcome screen in Malayalam', (
    tester,
  ) async {
    await pumpApp(tester, freshStore());
    expect(find.text('ഭാഷ തിരഞ്ഞെടുക്കുക'), findsOneWidget);
    expect(find.byKey(const Key('shell.nav')), findsNothing);
  });

  testWidgets('the language choice applies at once and is kept on the phone', (
    tester,
  ) async {
    final store = freshStore();
    await pumpApp(tester, store);
    await tap(tester, 'welcome.english');
    expect(find.text('Choose a language'), findsOneWidget);
    expect(store.get('settings.language'), 'english');

    // the app opened again on the same phone
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, store);
    expect(find.text('Choose a language'), findsOneWidget);
  });

  testWidgets('large text applies at once and is kept', (tester) async {
    final store = freshStore();
    await pumpApp(tester, store);
    await tap(tester, 'welcome.largeText');
    final context = tester.element(find.text('ഭാഷ തിരഞ്ഞെടുക്കുക'));
    expect(MediaQuery.textScalerOf(context).scale(10), closeTo(11.2, 0.001));
    expect(store.get('settings.large_text'), isTrue);
  });

  testWidgets('sign in, then set-up with only a name and a farm name, opens '
      'Home with the farm saved', (tester) async {
    final store = freshStore();
    await pumpApp(tester, store);
    await tap(tester, 'welcome.english');
    await tap(tester, 'welcome.continue');
    expect(title(tester), 'Sign in');
    await tap(tester, 'signIn.test');

    // step 1 needs a name
    expect(find.text('Step 1 / 3'), findsOneWidget);
    await tap(tester, 'setup.next');
    expect(find.text('Enter your name'), findsOneWidget);
    expect(find.text('Step 1 / 3'), findsOneWidget);
    await type(tester, 'setup.name', 'Ravi');
    await tap(tester, 'setup.next');

    // step 2 needs a farm name; the area and the rest have defaults
    expect(find.text('Step 2 / 3'), findsOneWidget);
    expect(find.byKey(const Key('setup.unit.cent')), findsOneWidget);
    expect(find.byKey(const Key('setup.unit.acre')), findsOneWidget);
    await tap(tester, 'setup.next');
    expect(find.text('Enter a name for the farm'), findsOneWidget);
    await type(tester, 'setup.farmName', 'Home farm');
    await tap(tester, 'setup.next');

    // step 3 can be left empty
    expect(find.text('Step 3 / 3'), findsOneWidget);
    expect(find.text('Coconut'), findsOneWidget);
    await tap(tester, 'setup.next');

    expect(find.byKey(const Key('shell.nav')), findsOneWidget);
    expect(find.text('Welcome! Your farm is ready'), findsOneWidget);
    final db = container.read(databaseProvider);
    final farm = (await db.customSelect('SELECT * FROM farms').get()).single;
    expect(farm.data['name'], 'Home farm');
    expect(container.read(sessionProvider).farmId, farm.data['id']);
    expect(container.read(sessionProvider).account!.name, 'Ravi');
    expect(
      (await db.customSelect('SELECT * FROM plots').get()).single.data['name'],
      'Home farm',
    );

    // opened again, the app goes straight to Home
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, store);
    expect(find.byKey(const Key('shell.nav')), findsOneWidget);
  });

  testWidgets('chosen area, tenure and crops are saved', (tester) async {
    await pumpApp(tester, freshStore());
    await tap(tester, 'welcome.english');
    await tap(tester, 'welcome.continue');
    await tap(tester, 'signIn.test');
    await type(tester, 'setup.name', 'Ravi');
    await tap(tester, 'setup.next');
    await type(tester, 'setup.farmName', 'Home farm');
    await type(tester, 'setup.area', '2.5');
    await tap(tester, 'setup.unit.acre');
    await tap(tester, 'setup.tenure.leased');
    await tap(tester, 'setup.next');
    await tap(tester, 'setup.crop.Pepper');
    await tap(tester, 'setup.crop.Coconut');
    await tap(tester, 'setup.next');

    final db = container.read(databaseProvider);
    final plot = (await db.customSelect('SELECT * FROM plots').get()).single;
    expect(plot.data['area'], 2500);
    expect(plot.data['area_unit'], 'acre');
    expect(plot.data['tenure'], 'leased');
    final crops = await db
        .customSelect(
          'SELECT c.name_en FROM crop_cycles y JOIN crops c ON c.id = y.crop_id '
          'ORDER BY c.name_en',
        )
        .get();
    expect(crops.map((r) => r.data['name_en']), ['Coconut', 'Pepper']);
  });

  testWidgets('mixed shows crop names in Malayalam followed by English', (
    tester,
  ) async {
    await pumpApp(tester, freshStore());
    await tap(tester, 'welcome.mixed');
    await tap(tester, 'welcome.continue');
    await tap(tester, 'signIn.test');
    await type(tester, 'setup.name', 'Ravi');
    await tap(tester, 'setup.next');
    await type(tester, 'setup.farmName', 'Home farm');
    await tap(tester, 'setup.next');
    expect(find.text('തെങ്ങ് (Coconut)'), findsOneWidget);
  });

  testWidgets('every step fits a small phone at the largest text, in '
      'Malayalam', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester, freshStore({'settings.large_text': true}));
    // 360 x 740, the narrowest phones in use
    tester.view.physicalSize = const Size(720, 1480);
    tester.view.devicePixelRatio = 2;
    await settle(tester);
    await tap(tester, 'welcome.mixed');
    await tap(tester, 'welcome.continue');
    await tap(tester, 'signIn.test');
    await tap(tester, 'setup.next'); // shows the error line
    await type(tester, 'setup.name', 'രവി');
    await tap(tester, 'setup.next');
    await tap(tester, 'setup.next');
    await type(tester, 'setup.farmName', 'വീട്ടുവളപ്പ്');
    await type(tester, 'setup.area', 'x');
    await type(tester, 'setup.area', '2.5');
    await tap(tester, 'setup.next');
    expect(find.text('തുടങ്ങാം'), findsOneWidget); // the finish button
    // a layout overflow fails the test on its own
  });

  group('with a server', () {
    late FakeServer server;
    setUp(() => server = FakeServer());

    /// The owner already set up a farm on another phone and synced it.
    Future<String> farmOnAnotherPhone(WidgetTester tester) async {
      final other = memoryDatabase();
      addTearDown(other.close);
      await installBundledTemplates(
        other,
        File(bundledTemplatesAsset).readAsStringSync(),
      );
      final farmId =
          await OnboardingRepository(
            other,
            History(other, userId: owner),
          ).createFarm(
            owner,
            const SetupInput(
              name: 'Ravi',
              farmName: 'Hill farm',
              areaUnit: 'cent',
            ),
          );
      await SyncEngine(other, server.as(owner), userId: owner).sync();
      return farmId;
    }

    testWidgets('a new phone restores the account\'s farm and opens Home, '
        'with no set-up and no second farm', (tester) async {
      final farmId = await farmOnAnotherPhone(tester);
      await pumpApp(tester, freshStore(), server: server);
      await tap(tester, 'welcome.continue');
      await tap(tester, 'signIn.test');
      await settle(tester);

      expect(find.byKey(const Key('shell.nav')), findsOneWidget);
      expect(container.read(sessionProvider).farmId, farmId);
      expect(server.tables['farms'], hasLength(1));
    });

    testWidgets('offline at first launch says once that a connection is '
        'needed, and goes on by itself when one returns', (tester) async {
      server.down = true;
      await pumpApp(tester, freshStore(), server: server);
      await tap(tester, 'welcome.english');
      await tap(tester, 'welcome.continue');
      await tap(tester, 'signIn.test');
      expect(find.byKey(const Key('signIn.offline')), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      // still waiting, still one message
      expect(find.byKey(const Key('signIn.offline')), findsOneWidget);

      server.down = false;
      await tester.pump(const Duration(seconds: 2));
      await settle(tester);
      expect(find.text('Step 1 / 3'), findsOneWidget);
    });

    group('invites', () {
      Invite invite(String farmId) => Invite(
        id: 'inv-1',
        farmId: farmId,
        farmName: 'Hill farm',
        role: 'manager',
        invitedBy: 'Mary',
      );

      testWidgets('sign-in shows an open invite; declining goes to set-up '
          'without joining', (tester) async {
        final farmId = await farmOnAnotherPhone(tester);
        server.invites['user-new'] = [invite(farmId)];
        await pumpApp(
          tester,
          MemoryDeviceStore({'auth.test_account_id': 'user-new'}),
          server: server,
        );
        await tap(tester, 'welcome.english');
        await tap(tester, 'welcome.continue');
        await tap(tester, 'signIn.test');
        expect(title(tester), 'You have an invitation');
        expect(find.text('Hill farm'), findsOneWidget);
        expect(find.text('As manager'), findsOneWidget);
        expect(find.text('Invited by Mary'), findsOneWidget);

        await tap(tester, 'invite.inv-1.decline');
        expect(find.text('Step 1 / 3'), findsOneWidget);
        expect(
          server.tables['farm_members']!.values.where(
            (m) => m['user_id'] == 'user-new',
          ),
          isEmpty,
        );
      });

      testWidgets('joining pulls the farm and opens Home', (tester) async {
        final farmId = await farmOnAnotherPhone(tester);
        server.invites['user-new'] = [invite(farmId)];
        await pumpApp(
          tester,
          MemoryDeviceStore({'auth.test_account_id': 'user-new'}),
          server: server,
        );
        await tap(tester, 'welcome.continue');
        await tap(tester, 'signIn.test');
        await tap(tester, 'invite.inv-1.join');
        await settle(tester);

        expect(find.byKey(const Key('shell.nav')), findsOneWidget);
        expect(container.read(sessionProvider).farmId, farmId);
        final db = container.read(databaseProvider);
        expect(
          (await db.customSelect('SELECT name FROM farms').get()).single.data,
          {'name': 'Hill farm'},
        );
      });
    });
  });
}

/// Lets futures, streams and animations run; the sign-in step has a
/// progress bar that never settles, so this pumps frames instead.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
