import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/prefs/device_store.dart';

enum LanguageChoice {
  malayalam(Locale('ml')),
  english(Locale('en')),

  /// Malayalam interface; crop and category names also in English.
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

/// The phone's preferences file; `main` opens the real one before the first
/// frame.
final deviceStoreProvider = Provider<DeviceStore>((ref) => MemoryDeviceStore());

/// Language and text size belong to the phone: they are chosen before
/// sign-in and stay for whoever signs in next.
class SettingsNotifier extends Notifier<AppSettings> {
  static const _language = 'settings.language';
  static const _largeText = 'settings.large_text';

  DeviceStore get _store => ref.read(deviceStoreProvider);

  @override
  AppSettings build() {
    final store = ref.watch(deviceStoreProvider);
    return AppSettings(
      language:
          LanguageChoice.values.asNameMap()[store.get(_language)] ??
          LanguageChoice.malayalam,
      largeText: store.get(_largeText) == true,
    );
  }

  void setLanguage(LanguageChoice language) {
    state = AppSettings(language: language, largeText: state.largeText);
    _store.set(_language, language.name);
  }

  void setLargeText(bool largeText) {
    state = AppSettings(language: state.language, largeText: largeText);
    _store.set(_largeText, largeText);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

/// A crop or category name as the language setting shows it: Malayalam,
/// English, or in mixed Malayalam followed by English.
String localName(
  AppSettings settings,
  String nameMl,
  String nameEn,
  String Function(String ml, String en) pair,
) => switch (settings.language) {
  LanguageChoice.english => nameEn,
  LanguageChoice.malayalam => nameMl,
  LanguageChoice.mixed => nameMl == nameEn ? nameMl : pair(nameMl, nameEn),
};
