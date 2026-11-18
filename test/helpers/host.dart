import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:thottam/app/theme/theme.dart';
import 'package:thottam/app/theme/tokens.dart';
import 'package:thottam/l10n/app_localizations.dart';

/// Wraps [child] in the app theme and strings, inside a Scaffold.
Widget host(
  Widget Function(BuildContext context, AppLocalizations l10n) child, {
  Locale locale = const Locale('ml'),
  double textScale = 1,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildTheme(ThottamTokens.standard),
    locale: locale,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Builder(
                  builder: (context) =>
                      child(context, AppLocalizations.of(context)),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Loads the bundled fonts so goldens show real Malayalam and Latin text.
Future<void> loadAppFonts() async {
  const families = {
    'AnekMalayalam': ['AnekMalayalam-600', 'AnekMalayalam-700'],
    'Inter': ['Inter-400', 'Inter-500', 'Inter-600', 'Inter-700'],
    'NotoSansMalayalam': [
      'NotoSansMalayalam-400',
      'NotoSansMalayalam-500',
      'NotoSansMalayalam-600',
      'NotoSansMalayalam-700',
    ],
  };
  for (final MapEntry(key: family, value: files) in families.entries) {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(rootBundle.load('assets/fonts/$f.ttf'));
    }
    await loader.load();
  }
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
}
