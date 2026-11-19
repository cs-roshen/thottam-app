import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thottam/core/db/database.dart';
import 'package:thottam/core/dev/benchmark_seed.dart';
import 'package:thottam/core/dev/load_seed.dart';

/// D1 review follow-up: every season stays on the phone (owner decision,
/// 2026-11-18), so measure the file with five years of the benchmark farm.
void main() {
  test('database file with five years of data', () async {
    final dir = await Directory.systemTemp.createTemp('thottam_five');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/five.db');
    final db = AppDatabase(NativeDatabase(file, setup: applyPragmas));
    final seed = generateBenchmarkSeed(years: 5);
    await loadSeed(db, seed);
    await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    final events = seed['event_log']!.length;
    await db.close();
    final bytes = await file.length();
    // ignore: avoid_print
    print(
      'five years: ${(bytes / 1024 / 1024).toStringAsFixed(1)} MB, '
      '$events history rows',
    );
    // shortcut: no budget is set for five years (the plan's 60 MB is for the
    // three-year seed, which measures 67.6 MB); the owner decides. Until
    // then this ceiling only catches a jump.
    expect(bytes, lessThan(120 * 1024 * 1024));
  });
}
