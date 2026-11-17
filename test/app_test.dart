import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:thottam/app/app.dart';

void main() {
  testWidgets('opens in Malayalam by default', (tester) async {
    await tester.pumpWidget(const ThottamApp());
    await tester.pumpAndSettle();

    expect(find.text('തോട്ടം'), findsOneWidget);
  });

  testWidgets('supports Malayalam and English', (tester) async {
    await tester.pumpWidget(const ThottamApp());

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(
      app.supportedLocales.map((l) => l.languageCode),
      containsAll(<String>['ml', 'en']),
    );
  });

  testWidgets('switches to English when asked', (tester) async {
    await tester.pumpWidget(const ThottamApp(locale: Locale('en')));
    await tester.pumpAndSettle();

    expect(find.text('Thottam'), findsOneWidget);
  });
}
