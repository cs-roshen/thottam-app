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
}
