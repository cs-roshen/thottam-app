import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thottam/core/access/access.dart';

void main() {
  test('role defaults follow product spec rule 7', () {
    // owner: everything, members included
    const owner = Access('owner');
    for (final c in AccessClass.values) {
      expect(owner.canWrite(c), isTrue, reason: '$c');
    }
    // manager: everything except members and permissions
    const manager = Access('manager');
    expect(manager.canWrite(AccessClass.setup), isTrue);
    expect(manager.canWrite(AccessClass.money), isTrue);
    expect(manager.canRead(AccessClass.members), isFalse);
    // supervisor: daily work, workers and groups; no money at all
    const supervisor = Access('supervisor');
    expect(supervisor.canWrite(AccessClass.daily), isTrue);
    expect(supervisor.canWrite(AccessClass.team), isTrue);
    expect(supervisor.canWrite(AccessClass.setup), isFalse);
    expect(supervisor.canRead(AccessClass.setup), isTrue);
    expect(supervisor.canRead(AccessClass.money), isFalse);
    // accountant: reads everything, writes money, not daily work
    const accountant = Access('accountant');
    expect(accountant.canWrite(AccessClass.money), isTrue);
    expect(accountant.canWrite(AccessClass.daily), isFalse);
    expect(accountant.canRead(AccessClass.daily), isTrue);
    expect(accountant.canWrite(AccessClass.setup), isFalse);
    // viewer: reads everything, writes nothing
    const viewer = Access('viewer');
    for (final c in AccessClass.values.where((c) => c != AccessClass.members)) {
      expect(viewer.canRead(c), isTrue, reason: '$c');
      expect(viewer.canWrite(c), isFalse, reason: '$c');
    }
  });

  test('a per-person permission wins over the role', () {
    expect(
      const Access('supervisor', {'money': 'read'}).canRead(AccessClass.money),
      isTrue,
    );
    expect(
      const Access('manager', {'setup': 'none'}).canRead(AccessClass.setup),
      isFalse,
    );
    expect(
      const Access('owner', {'setup': 'none'}).canWrite(AccessClass.setup),
      isTrue,
    );
  });

  test('no membership reads nothing', () {
    expect(Access.none.canRead(AccessClass.setup), isFalse);
  });

  test('every table has the access class the server gives it', () {
    final server = {
      for (final f in Directory('supabase/migrations').listSync())
        if (f is File && f.path.endsWith('.sql'))
          for (final block in RegExp(
            r'insert into public\.sync_tables[^;]*;',
          ).allMatches(f.readAsStringSync()))
            for (final m in RegExp(
              r"\('(\w+)', '(\w+)', '\w+', \d+\)",
            ).allMatches(block[0]!))
              m[1]!: m[2]!,
    };
    expect(server, hasLength(tableAccess.length));
    for (final MapEntry(:key, :value) in tableAccess.entries) {
      expect(server[key], value.name, reason: key);
    }
  });
}
