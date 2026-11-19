@Tags(['golden'])
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:thottam/app/router.dart';

import '../../helpers/screen_golden.dart';
import '../../helpers/session.dart';
import 'settings_screen_test.dart' show twoFarms;

void main() {
  Future<void> Function(WidgetTester) go(String path) => (tester) async {
    ProviderScope.containerOf(tester.element(find.byType(Scaffold).first))
        .read(routerProvider)
        .go(path);
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
  };

  Future<void> golden(
    WidgetTester tester,
    String name,
    String variant,
    String path,
  ) async {
    final (db, farm) = await farmDatabase(
      crops: const ['Pepper'],
      seed: twoFarms,
    );
    await expectScreenGolden(
      tester,
      name,
      variant,
      farmOverrides(db, farm, goldenVariants[variant]!),
      go(path),
    );
  }

  for (final variant in goldenVariants.keys) {
    testWidgets('settings $variant', (tester) async {
      await golden(tester, 'settings', variant, '/more/settings');
    });
  }

  testWidgets('more ml', (tester) async {
    await golden(tester, 'more', 'ml', '/more');
  });

  testWidgets('farms ml', (tester) async {
    await golden(tester, 'farms', 'ml', '/more/settings/farms');
  });

  testWidgets('members ml', (tester) async {
    await golden(tester, 'members', 'ml', '/more/settings/members');
  });

  testWidgets('my lists ml', (tester) async {
    await golden(tester, 'lists', 'ml', '/more/lists');
  });
}
