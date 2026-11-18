import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

enum LanguageChoice {
  malayalam(Locale('ml')),
  english(Locale('en')),

  /// Malayalam interface; crop, category and unit names also in English.
  mixed(Locale('ml'), showEnglishNames: true);

  const LanguageChoice(this.locale, {this.showEnglishNames = false});

  final Locale locale;
  final bool showEnglishNames;
}

@immutable
class AppSettings {
  const AppSettings({
    this.language = LanguageChoice.malayalam,
    this.largeText = false,
  });

  final LanguageChoice language;
  final bool largeText;
}

// shortcut: kept in memory only; persist in the app_settings table (B2) so the
// choice survives a restart (screens.md 1).
class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => const AppSettings();

  void setLanguage(LanguageChoice language) =>
      state = AppSettings(language: language, largeText: state.largeText);

  void setLargeText(bool largeText) =>
      state = AppSettings(language: state.language, largeText: largeText);
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
