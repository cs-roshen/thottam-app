import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import 'settings.dart';
import 'theme/theme.dart';
import 'theme/tokens.dart';
import 'router.dart';

class ThottamApp extends ConsumerWidget {
  const ThottamApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    const tokens = ThottamTokens.standard;
    return MaterialApp.router(
      routerConfig: ref.watch(routerProvider),
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      theme: buildTheme(tokens),
      locale: settings.language.locale,
      // Material lives in material_ui since Flutter 3.50, so its delegates
      // replace the framework ones the generated list would add.
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) {
        if (!settings.largeText) return child!;
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: _ExtraScale(media.textScaler, tokens.largeTextScale),
          ),
          child: child!,
        );
      },
    );
  }
}

/// Large-text mode: the system text size, then 1.12 on top of it.
class _ExtraScale extends TextScaler {
  const _ExtraScale(this.base, this.factor);

  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => base.textScaleFactor * factor;

  @override
  bool operator ==(Object other) =>
      other is _ExtraScale && other.base == base && other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}
