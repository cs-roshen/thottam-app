import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> load(String lang) =>
    jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync())
        as Map<String, dynamic>;

Iterable<String> messages(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@'));

Set<String> placeholders(Map<String, dynamic> arb, String key) {
  final meta = arb['@$key'] as Map<String, dynamic>?;
  final ph = meta?['placeholders'] as Map<String, dynamic>?;
  return ph?.keys.toSet() ?? <String>{};
}

void main() {
  final ml = load('ml');
  final en = load('en');

  test('Malayalam and English have the same keys', () {
    expect(messages(en).toSet(), messages(ml).toSet());
  });

  test('every key has a description', () {
    for (final key in messages(ml)) {
      final meta = ml['@$key'] as Map<String, dynamic>?;
      expect(meta?['description'], isA<String>(), reason: key);
    }
  });

  test('placeholders match between languages', () {
    for (final key in messages(ml)) {
      expect(placeholders(en, key), placeholders(ml, key), reason: key);
    }
  });

  test('a message without placeholders has no braces', () {
    for (final arb in [ml, en]) {
      for (final key in messages(arb)) {
        if (placeholders(ml, key).isEmpty) {
          expect(arb[key] as String, isNot(contains('{')), reason: key);
        }
      }
    }
  });

  test('no indexed keys left from the prototype export', () {
    final indexed = RegExp(r'\d$|\dx\d');
    expect(messages(ml).where(indexed.hasMatch), isEmpty);
  });

  test('no sample names or amounts in strings', () {
    for (final arb in [ml, en]) {
      for (final key in messages(arb)) {
        final value = arb[key] as String;
        expect(value, isNot(contains('Rajan')), reason: key);
        expect(value, isNot(contains('രാജൻ')), reason: key);
        expect(value, isNot(matches(RegExp(r'₹\d'))), reason: key);
      }
    }
  });
}
