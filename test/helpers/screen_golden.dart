import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:thottam/app/app.dart';

import 'host.dart';

/// The three language and text-size variants every screen golden is drawn
/// in (implementation plan section 15); the empty state is its own golden
/// where a screen has one.
const goldenVariants = {
  'ml': {'settings.language': 'malayalam'},
  'en': {'settings.language': 'english'},
  'ml_large': {'settings.language': 'malayalam', 'settings.large_text': true},
};

/// Lets futures, streams and animations run without waiting for endless
/// ones (a progress bar) to finish.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Draws the whole app on a 412 x 915 phone after [go] has brought it to the
/// screen, and compares it with `goldens/<name>.<variant>.png`.
Future<void> expectScreenGolden(
  WidgetTester tester,
  String name,
  String variant,
  List<Override> overrides,
  Future<void> Function(WidgetTester tester) go,
) async {
  await loadAppFonts();
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(overrides: overrides, child: const ThottamApp()),
  );
  await settle(tester);
  await go(tester);
  // hide the blinking cursor and any toast still on its way in
  await tester.pump(const Duration(seconds: 3));
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$name.$variant.png'),
  );
}
