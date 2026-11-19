import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thottam/core/db/database.dart';
import 'package:thottam/core/sync/bundled_templates.dart';

void main() {
  final asset = File(bundledTemplatesAsset).readAsStringSync();
  final seed = (jsonDecode(asset) as Map).cast<String, Object?>();
  List<Map<String, Object?>> rows(String table) => [
    for (final r in seed[table]! as List) (r as Map).cast<String, Object?>(),
  ];

  group('install', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<int> count(String sql) async =>
        (await db.customSelect(sql).getSingle()).data.values.first! as int;

    test('an empty phone gets every standard crop and template item', () async {
      await installBundledTemplates(db, asset);
      expect(
        await count('SELECT COUNT(*) FROM crops WHERE owner_farm_id IS NULL'),
        rows('crops').length,
      );
      expect(
        await count('SELECT COUNT(*) FROM template_items'),
        rows('template_items').length,
      );
      // retired para stays retired, as on the server
      expect(
        await count(
          "SELECT COUNT(*) FROM template_items WHERE code = 'para' "
          'AND is_active = 0 AND template_version = 2',
        ),
        1,
      );
    });

    test('a phone that already has templates keeps them', () async {
      await installBundledTemplates(db, asset);
      final item = rows('template_items').first;
      await db.customStatement(
        "UPDATE template_items SET name_en = 'pulled', template_version = 9 "
        'WHERE id = ?',
        [item['id']],
      );
      await db.customStatement('DELETE FROM template_items WHERE id <> ?', [
        item['id'],
      ]);
      await installBundledTemplates(db, asset);
      expect(await count('SELECT COUNT(*) FROM template_items'), 1);
      expect(
        await count(
          "SELECT COUNT(*) FROM template_items WHERE name_en = 'pulled'",
        ),
        1,
      );
    });
  });

  group('matches the server migrations', () {
    final wave1 = File('supabase/migrations/0002_wave1_templates.sql')
        .readAsStringSync();
    String q(Object? v) => v == null ? 'null' : "'$v'";

    test('every crop is in 0002 with the same names', () {
      for (final c in rows('crops')) {
        expect(
          wave1,
          contains(
            "'${c['code']}', ${q(c['name_ml'])}, ${q(c['name_en'])}, "
            "'${c['kind']}', '${c['default_unit']}')",
          ),
          reason: '${c['code']}',
        );
      }
    });

    // Later migrations that add items, as tool/build_templates.py ADDITIONS.
    final itemSql = [
      wave1,
      File('supabase/migrations/0007_inputs_stock.sql').readAsStringSync(),
    ].map((s) => s.split('insert into public.template_items')[1]).join('\n');

    test('every template item is in 0002 or a later addition, and no more', () {
      final crops = {for (final c in rows('crops')) c['id']: c['code']};
      final items = rows('template_items');
      for (final i in items) {
        expect(
          itemSql,
          contains(
            '(${q(crops[i['crop_id']])}, ${q(i['list_type'])}, '
            "${q(i['code'])}, ${q(i['name_ml'])}, ${q(i['name_en'])}, "
            '${i['sort_order']}, ',
          ),
          reason: '${i['list_type']} ${i['code']}',
        );
      }
      final tuples = RegExp(
        r"^\s*\((null|'\w+'), '\w+', '",
        multiLine: true,
      ).allMatches(itemSql);
      expect(items, hasLength(tuples.length));
    });

    test('every later migration that changes templates is in the tool', () {
      final tool = File('tool/build_templates.py').readAsStringSync();
      for (final f in Directory('supabase/migrations').listSync()) {
        final name = f.uri.pathSegments.last;
        if (f is! File || name.startsWith('0001') || name.startsWith('0002')) {
          continue;
        }
        // a function body (the admin console's publish) writes templates
        // when it runs, not when the migration does
        final sql = f.readAsStringSync().replaceAll(
          RegExp(r'\$\$.*?\$\$', dotAll: true),
          '',
        );
        if (RegExp(r'(insert into|update)\s+public\.(template_items|crops)\b')
            .hasMatch(sql)) {
          expect(tool, contains('("${name.substring(0, 4)}"'), reason: name);
        }
      }
    });
  });
}
