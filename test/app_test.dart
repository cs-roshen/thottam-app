import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:thottam/app/app.dart';

void main() {
  testWidgets('opens in Malayalam by default', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ThottamApp()));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'ഹോം'), findsOneWidget);
  });

  testWidgets('supports Malayalam and English', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ThottamApp()));

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(
      app.supportedLocales.map((l) => l.languageCode),
      containsAll(<String>['ml', 'en']),
    );
  });
}
