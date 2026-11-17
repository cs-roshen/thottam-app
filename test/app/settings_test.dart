import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:thottam/app/app.dart';
import 'package:thottam/app/settings.dart';

void main() {
  test('language choices map to a locale and the English-names flag', () {
    expect(LanguageChoice.malayalam.locale, const Locale('ml'));
    expect(LanguageChoice.english.locale, const Locale('en'));
    expect(LanguageChoice.mixed.locale, const Locale('ml'));
    expect(LanguageChoice.mixed.showEnglishNames, isTrue);
    expect(LanguageChoice.malayalam.showEnglishNames, isFalse);
  });

  testWidgets('switching language applies at once', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ThottamApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('തോട്ടം'), findsOneWidget);

    container
        .read(settingsProvider.notifier)
        .setLanguage(LanguageChoice.english);
    await tester.pumpAndSettle();
    expect(find.text('Thottam'), findsOneWidget);
  });

  testWidgets('large text scales by 1.12 on top of the system size', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    double scaleOf10() {
      // The app bar clamps its title, so read the body's scale.
      final context = tester.element(find.byType(Scaffold).first);
      return MediaQuery.textScalerOf(context).scale(10);
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ThottamApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(scaleOf10(), closeTo(20, 0.001));

    container.read(settingsProvider.notifier).setLargeText(true);
    await tester.pumpAndSettle();
    expect(scaleOf10(), closeTo(22.4, 0.001));
  });
}
