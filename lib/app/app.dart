import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';

class ThottamApp extends StatelessWidget {
  const ThottamApp({super.key, this.locale = const Locale('ml')});

  final Locale locale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      locale: locale,
      // Material lives in material_ui since Flutter 3.50, so its delegates
      // replace the framework ones the generated list would add.
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const _Placeholder(),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: Text(AppLocalizations.of(context).appName)),
    );
  }
}
