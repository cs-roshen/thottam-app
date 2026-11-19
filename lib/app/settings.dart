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
    this.hiddenCards = const {},
  });

  final LanguageChoice language;
  final bool largeText;

  /// Home cards switched off (screen 2): 'profit', 'price', 'tasks', 'dues'.
  final Set<String> hiddenCards;

  AppSettings copyWith({
    LanguageChoice? language,
    bool? largeText,
    Set<String>? hiddenCards,
  }) => AppSettings(
    language: language ?? this.language,
    largeText: largeText ?? this.largeText,
    hiddenCards: hiddenCards ?? this.hiddenCards,
  );
}

/// The phone's preferences file; `main` opens the real one before the first
/// frame.
final deviceStoreProvider = Provider<DeviceStore>((ref) => MemoryDeviceStore());

/// Language and text size belong to the phone: they are chosen before
/// sign-in and stay for whoever signs in next.
class SettingsNotifier extends Notifier<AppSettings> {
  static const _language = 'settings.language';
  static const _largeText = 'settings.large_text';
  static const _hiddenCards = 'settings.home_hidden';

  DeviceStore get _store => ref.read(deviceStoreProvider);

  @override
  AppSettings build() {
    final store = ref.watch(deviceStoreProvider);
    return AppSettings(
      language:
          LanguageChoice.values.asNameMap()[store.get(_language)] ??
          LanguageChoice.malayalam,
      largeText: store.get(_largeText) == true,
      hiddenCards: {...?(store.get(_hiddenCards) as List?)?.cast<String>()},
    );
  }

  void setLanguage(LanguageChoice language) {
    state = state.copyWith(language: language);
    _store.set(_language, language.name);
  }

  void setLargeText(bool largeText) {
    state = state.copyWith(largeText: largeText);
    _store.set(_largeText, largeText);
  }

  void setCardShown(String card, bool shown) {
    final hidden = {...state.hiddenCards};
    shown ? hidden.remove(card) : hidden.add(card);
    state = state.copyWith(hiddenCards: hidden);
    _store.set(_hiddenCards, hidden.toList()..sort());
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
