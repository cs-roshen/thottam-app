import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thottam/features/labour/domain/wages.dart';

/// The values a column may take on the server: its `check (col in (...))`
/// inside `create table public.<table>`.
Set<String> serverValues(String table, String column) {
  final sql = File('supabase/migrations/0001_init.sql').readAsStringSync();
  final start = sql.indexOf('create table public.$table (');
  expect(start, isNot(-1), reason: table);
  final body = sql.substring(start, sql.indexOf(');\n', start));
  final m = RegExp(
    '$column text not null[^\\n]*check \\($column in \\(([^)]*)\\)',
  ).firstMatch(body);
  expect(m, isNotNull, reason: '$table.$column');
  return {for (final v in RegExp(r"'(\w+)'").allMatches(m![1]!)) v[1]!};
}

/// Codes the phone writes must be ones the server accepts, or the upload is
/// refused and the farmer's entry never leaves the phone.
void main() {
  test('labour payment kinds', () {
    expect(
      serverValues('labour_payments', 'kind'),
      containsAll([for (final k in PaymentKind.values) k.code]),
    );
  });

  test('payment modes offered on each screen', () {
    expect(
      serverValues('labour_payments', 'mode'),
      containsAll(['cash', 'upi', 'bank']),
    );
    expect(
      serverValues('expenses', 'mode'),
      containsAll(['cash', 'upi', 'bank', 'credit']),
    );
  });

  test('wage types, tenures and party kinds', () {
    expect(
      serverValues('labour_entries', 'wage_type'),
      containsAll(['daily', 'piece']),
    );
    expect(
      serverValues('plots', 'tenure'),
      containsAll(['owned', 'leased', 'shared']),
    );
    expect(serverValues('parties', 'kind'), containsAll(['vendor', 'buyer']));
    expect(
      serverValues('crop_cycles', 'status'),
      containsAll(['active', 'closed']),
    );
  });
}
