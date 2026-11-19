import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:thottam/app/date_format.dart';
import 'package:thottam/l10n/app_localizations.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ml');
    await initializeDateFormatting('en');
  });

  test('Malayalam: Gregorian date then Malayalam month, Latin digits', () {
    final l10n = lookupAppLocalizations(const Locale('ml'));
    final text = formatHomeDate(DateTime(2026, 11, 16), l10n);
    expect(text, contains('16'));
    expect(text, contains('നവംബർ'));
    expect(text, endsWith('വൃശ്ചികം 1'));
    expect(text, isNot(matches(RegExp('[൦-൯]'))));
  });

  test('English', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(
      formatHomeDate(DateTime(2026, 11, 16), l10n),
      'Monday, 16 November · Vrischikam 1',
    );
  });

  test('days of work: today, yesterday, then a short date', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final today = DateTime(2026, 11, 19, 15);
    expect(formatDay('2026-11-19', en, today), 'Today');
    expect(formatDay('2026-11-18', en, today), 'Yesterday');
    expect(formatDay('2026-11-02', en, today), '2 Nov');
    expect(formatDay('2025-12-30', en, today), '30 Dec 2025');
    final ml = lookupAppLocalizations(const Locale('ml'));
    expect(formatDay('2026-11-02', ml, today), isNot(matches(RegExp('[൦-൯]'))));
  });
}
