import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:thottam/app/app.dart';
import 'package:thottam/app/router.dart';
import 'package:thottam/app/widgets/widgets.dart';

Future<void> pumpApp(WidgetTester tester, {bool canSeeMoney = true}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [canSeeMoneyProvider.overrideWithValue(canSeeMoney)],
      child: const ThottamApp(),
    ),
  );
  await tester.pumpAndSettle();
}

String? title(WidgetTester tester) => tester
    .widgetList<AppBar>(find.byType(AppBar))
    .map((b) => (b.title as Text?)?.data)
    .lastOrNull;

Finder galleryScroll() => find
    .ancestor(of: find.byType(WidgetGallery), matching: find.byType(Scrollable))
    .first;

Future<void> tapTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(const Key('shell.nav')),
      matching: find.text(label),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('four tabs; each opens its screen', (tester) async {
    await pumpApp(tester);
    expect(title(tester), 'ഹോം');
    for (final (tab, screen) in [
      ('എന്റെ ഭൂമി', 'എന്റെ ഭൂമി'),
      ('കണക്ക്', 'ലാഭ നഷ്ടം'),
      ('കൂടുതൽ', 'കൂടുതൽ'),
      ('ഹോം', 'ഹോം'),
    ]) {
      await tapTab(tester, tab);
      expect(title(tester), screen, reason: tab);
    }
  });

  testWidgets('three tabs when the role cannot open Money', (tester) async {
    await pumpApp(tester, canSeeMoney: false);
    final nav = tester.widget<ThottamBottomNav>(
      find.byKey(const Key('shell.nav')),
    );
    expect(nav.tabs, hasLength(3));
    expect(find.text('കണക്ക്'), findsNothing);
  });

  testWidgets('add button opens the quick add sheet; back closes it', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.bySemanticsLabel('ചേർക്കുക'));
    await tester.pumpAndSettle();
    expect(find.text('എന്ത് ചേർക്കണം?'), findsOneWidget);

    await back(tester);
    expect(find.text('എന്ത് ചേർക്കണം?'), findsNothing);
    expect(title(tester), 'ഹോം');
  });

  testWidgets('a tab keeps its stack and scroll position', (tester) async {
    await pumpApp(tester);
    await tapTab(tester, 'കൂടുതൽ');
    await tester.tap(find.byKey(const Key('more.gallery')));
    await tester.pumpAndSettle();
    expect(find.byType(WidgetGallery), findsOneWidget);

    await tester.drag(galleryScroll(), const Offset(0, -300));
    await tester.pumpAndSettle();
    final offset = tester
        .state<ScrollableState>(galleryScroll())
        .position
        .pixels;
    expect(offset, greaterThan(0));

    await tapTab(tester, 'ഹോം');
    await tapTab(tester, 'കൂടുതൽ');
    expect(find.byType(WidgetGallery), findsOneWidget);
    expect(
      tester.state<ScrollableState>(galleryScroll()).position.pixels,
      offset,
    );
  });

  testWidgets('back goes back, then to Home, then leaves the app', (
    tester,
  ) async {
    final exits = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.pop') exits.add(call.method);
        return null;
      },
    );
    await pumpApp(tester);
    await tapTab(tester, 'കൂടുതൽ');
    await tester.tap(find.byKey(const Key('more.gallery')));
    await tester.pumpAndSettle();

    await back(tester);
    expect(find.byType(WidgetGallery), findsNothing);
    expect(title(tester), 'കൂടുതൽ');

    await back(tester);
    expect(title(tester), 'ഹോം');
    expect(exits, isEmpty);

    await back(tester);
    expect(exits, ['SystemNavigator.pop']);
  });
}
