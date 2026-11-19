import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thottam/core/db/database.dart';
import 'package:thottam/core/dev/benchmark_seed.dart';
import 'package:thottam/core/dev/load_seed.dart';

import 'list_queries.dart';
import 'query_plan_test.dart' show bindNamed;

/// Section 14: with the benchmark seed loaded, every list query stays under
/// twice its budget (CI machines differ from phones, so the margin is wide),
/// and the file stays under 60 MB. Release numbers come from the test phone.
void main() {
  late Directory dir;
  late AppDatabase db;
  late SeedTables seed;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('thottam_bench');
    db = AppDatabase(
      NativeDatabase(File('${dir.path}/bench.db'), setup: applyPragmas),
    );
    seed = generateBenchmarkSeed();
    final watch = Stopwatch()..start();
    await loadSeed(db, seed);
    await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    // ignore: avoid_print
    print('seed loaded in ${watch.elapsedMilliseconds} ms');
  });

  tearDownAll(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('database file with the seed loaded is under 60 MB', () async {
    final bytes = await File('${dir.path}/bench.db').length();
    // ignore: avoid_print
    print('database file: ${(bytes / 1024 / 1024).toStringAsFixed(1)} MB');
    expect(bytes, lessThan(60 * 1024 * 1024));
  });

  test('every list query stays within twice its budget', () async {
    final farm = seed['farms']!.first['id']! as String;
    final cycle = seed['crop_cycles']!.first['id']! as String;
    final worker = seed['workers']!.first['id']! as String;
    final harvest = seed['harvests']!.last['id']! as String;
    final plot = seed['plots']!.first['id']! as String;
    final values = <String, Object>{
      'farm': farm,
      'cycle': cycle,
      'worker': worker,
      'entity': 'expenses',
      'row': harvest,
      'from': '2026-04-01',
      'to': '2027-03-31',
      'day': '2026-11-18',
      'id': 'ffffffff',
    };
    final report = <String>[];
    for (final q in listQueries) {
      final v = {
        ...values,
        if (q.name == 'crop cycles on a plot') 'row': plot,
        if (q.name == 'record timeline')
          'row': seed['expenses']!.first['id']! as String,
      };
      final (sql, args) = bindNamed(q.sql, v);
      final times = <int>[];
      for (var i = 0; i < 7; i++) {
        final w = Stopwatch()..start();
        await db.customSelect(sql, variables: args).get();
        times.add(w.elapsedMicroseconds);
      }
      times.sort();
      final median = times[times.length ~/ 2] / 1000;
      report.add(
        '${q.name}: ${median.toStringAsFixed(2)} ms (budget ${q.budgetMs})',
      );
      expect(median, lessThan(q.budgetMs * 2), reason: q.name);
    }
    // ignore: avoid_print
    print(report.join('\n'));
  });
}
