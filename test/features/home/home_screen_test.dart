import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:thottam/app/app.dart';
import 'package:thottam/app/router.dart';
import 'package:thottam/app/session.dart';
import 'package:thottam/app/settings.dart';
import 'package:thottam/features/money/ui/money_screen.dart';

import '../../helpers/screen_golden.dart';
import '../../helpers/session.dart';
import 'home_test_farm.dart';

void main() {
  late ProviderContainer container;

  Future<void> pumpHome(
    WidgetTester tester, {
    String role = 'owner',
    bool small = false,
    Map<String, Object?> prefs = const {'settings.language': 'english'},
  }) async {
    // 412 dp wide, or 360 dp, the narrowest phones in use
    tester.view.physicalSize = small
        ? const Size(720, 1480)
        : const Size(1080, 2400);
    tester.view.devicePixelRatio = small ? 2 : 2.625;
    addTearDown(tester.view.reset);
    final (db, farm) = await farmDatabase(
      crops: const ['Coconut', 'Pepper', 'Banana'],
      role: role,
      seed: homeFarm,
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
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(
      f,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(f);
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
  }

  Future<int> taskEvents() async =>
      (await container
              .read(databaseProvider)
              .customSelect(
                "SELECT COUNT(*) AS n FROM event_log WHERE entity = 'tasks' "
                "AND action = 'update'",
              )
              .getSingle())
          .read<int>('n');

  testWidgets('the date in both calendars, a greeting, and every card', (
    tester,
  ) async {
    await pumpHome(tester);
    expect(
      tester.widget<Text>(find.byKey(const Key('home.date'))).data,
      'Thursday, 19 November · Vrischikam\u00a04',
    );
    expect(find.text('Hello, Ravi'), findsOneWidget);
    expect(find.text('This year · Profit'), findsOneWidget);
    expect(find.text('₹88,300'), findsOneWidget);
    expect(find.text('₹1,84,500'), findsOneWidget);
    expect(find.text('₹96,200'), findsOneWidget);
    expect(find.text('Today’s price · Pepper'), findsOneWidget);
    expect(find.text('₹705 / kg'), findsOneWidget);
    // two days old
    expect(find.textContaining('Old price'), findsOneWidget);
    expect(find.text('Tie the vines'), findsOneWidget);
    expect(find.text('Spray Bordeaux'), findsOneWidget);
    expect(find.text('Apply lime'), findsNothing);
    expect(find.text('Weed the basins'), findsNothing);
    expect(find.text('Due 12 Nov · Pepper · Riverside'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('home.dues')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Wages due ₹22,000 · 1 to pay'), findsOneWidget);
  });

  testWidgets('ticking a task writes to history; undo takes it back', (
    tester,
  ) async {
    await pumpHome(tester);
    expect(await taskEvents(), 0);
    await tap(tester, find.text('Spray Bordeaux'));
    expect(await taskEvents(), 1);
    expect(find.text('1 done'), findsOneWidget);
    final box = tester.widget<CheckboxListTile>(
      find.ancestor(
        of: find.text('Spray Bordeaux'),
        matching: find.byType(CheckboxListTile),
      ),
    );
    expect(box.value, isTrue);
    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(find.text('1 done'), findsNothing);
  });

  testWidgets('hiding a card in settings removes it', (tester) async {
    await pumpHome(tester);
    final settings = container.read(settingsProvider.notifier);
    settings.setCardShown('profit', false);
    settings.setCardShown('tasks', false);
    await settle(tester);
    expect(find.byKey(const Key('home.profit')), findsNothing);
    expect(find.byKey(const Key('home.tasks')), findsNothing);
    expect(find.byKey(const Key('home.price')), findsOneWidget);
    settings.setCardShown('profit', true);
    await settle(tester);
    expect(find.byKey(const Key('home.profit')), findsOneWidget);
    // kept on the phone
    expect(container.read(deviceStoreProvider).get('settings.home_hidden'), [
      'tasks',
    ]);
  });

  testWidgets('a supervisor sees tasks and price, not money', (tester) async {
    await pumpHome(tester, role: 'supervisor');
    expect(find.byKey(const Key('home.profit')), findsNothing);
    expect(find.byKey(const Key('home.dues')), findsNothing);
    expect(find.byKey(const Key('home.tasks')), findsOneWidget);
    expect(find.byKey(const Key('home.price')), findsOneWidget);
  });

  testWidgets('a viewer cannot tick a task', (tester) async {
    await pumpHome(tester, role: 'viewer');
    final box = tester.widget<CheckboxListTile>(
      find.ancestor(
        of: find.text('Spray Bordeaux'),
        matching: find.byType(CheckboxListTile),
      ),
    );
    expect(box.onChanged, isNull);
  });

  testWidgets('Details opens profit and loss; the language button switches', (
    tester,
  ) async {
    await pumpHome(tester);
    await tap(tester, find.byKey(const Key('home.language')));
    expect(find.text('നമസ്കാരം, Ravi'), findsOneWidget);
    await tap(tester, find.byKey(const Key('home.language')));
    expect(find.text('Hello, Ravi'), findsOneWidget);
    await tap(tester, find.byKey(const Key('home.profit.details')));
    expect(find.byType(MoneyScreen), findsOneWidget);
  });

  testWidgets('a note from quick add shows in History under its day', (
    tester,
  ) async {
    await pumpHome(tester);
    await tester.tap(find.bySemanticsLabel('Add'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('quickAdd./add/note')));
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    // nothing written yet: saving asks for the words first
    await tester.tap(find.byKey(const Key('note.save')));
    await settle(tester);
    expect(find.text('Write the note first.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('note.text')),
      'Leaves yellowing on the east side',
    );
    await tester.tap(find.text('Riverside'));
    await settle(tester);
    await tester.tap(find.text('Pepper'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('note.save')));
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Saved'), findsOneWidget);
    container.read(routerProvider).push('/history');
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    // the test clock stands still, so the note sits below the seed's rows
    await tester.scrollUntilVisible(
      find.text('Note added'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Note added'), findsOneWidget);
    expect(
      find.text('Leaves yellowing on the east side · Pepper · Riverside'),
      findsOneWidget,
    );
  });

  testWidgets('Malayalam, large text, on a 360 dp phone: nothing overflows', (
    tester,
  ) async {
    await pumpHome(
      tester,
      small: true,
      prefs: const {
        'settings.language': 'malayalam',
        'settings.large_text': true,
      },
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('home.dues')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });
}
