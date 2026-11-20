import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thottam/core/db/database.dart';
import 'package:thottam/core/history/write_with_history.dart';
import 'package:thottam/core/sync/bundled_templates.dart';
import 'package:thottam/core/sync/sync_engine.dart';
import 'package:thottam/core/sync/sync_server.dart';
import 'package:thottam/features/onboarding/data/onboarding_repository.dart';
import 'package:thottam/features/onboarding/domain/setup.dart';

import '../../core/sync/fake_server.dart';

const user = 'user-owner';

/// One phone signed in as [userId], with the bundled templates.
class Phone {
  Phone(FakeServer server, this.userId, {int seed = 1})
    : db = AppDatabase(NativeDatabase.memory()) {
    var now = DateTime.utc(2026, 11, 19, 8);
    DateTime clock() => now = now.add(const Duration(milliseconds: 10));
    history = History(db, userId: userId, clock: clock, random: Random(seed));
    this.server = server.as(userId);
    engine = SyncEngine(
      db,
      this.server,
      userId: userId,
      clock: clock,
      random: Random(seed + 100),
    );
    repo = OnboardingRepository(db, history);
  }

  final String userId;
  final AppDatabase db;
  late final History history;
  late final SyncServer server;
  late final SyncEngine engine;
  late final OnboardingRepository repo;

  Future<void> templates() => installBundledTemplates(
    db,
    File(bundledTemplatesAsset).readAsStringSync(),
  );

  Future<List<Map<String, Object?>>> rows(String sql) async => [
    for (final r in await db.customSelect(sql).get()) r.data,
  ];
}

void main() {
  late FakeServer server;
  late Phone phone;

  setUp(() async {
    server = FakeServer();
    phone = Phone(server, user);
    await phone.templates();
  });
  tearDown(() => phone.db.close());

  test('set-up offers the standard crops and area units', () async {
    final crops = await phone.repo.standardCrops();
    expect(crops.map((c) => c.nameEn), [
      'Banana',
      'Cardamom',
      'Coconut',
      'Paddy',
      'Pepper',
      'Rubber',
    ]);
    expect(await phone.repo.areaUnits(), ['cent', 'acre', 'hectare', 'are']);
  });

  test('finishing with only a name and a farm name creates the farm, its '
      'owner and one plot, with history and uploads', () async {
    final farmId = await phone.repo.createFarm(
      user,
      const SetupInput(name: 'Ravi', farmName: 'Home farm', areaUnit: 'cent'),
    );

    final farm = (await phone.rows('SELECT * FROM farms')).single;
    expect(farm['id'], farmId);
    expect(farm['name'], 'Home farm');
    // the templates on the phone are release 3 (migration 0007)
    expect(farm['accepted_template_version'], 3);

    final member = (await phone.rows('SELECT * FROM farm_members')).single;
    expect(member['farm_id'], farmId);
    expect(member['user_id'], user);
    expect(member['role'], 'owner');

    final plot = (await phone.rows('SELECT * FROM plots')).single;
    expect(plot['farm_id'], farmId);
    expect(plot['name'], 'Home farm');
    expect(plot['area'], isNull);
    expect(plot['area_unit'], 'cent');
    expect(plot['tenure'], 'owned');
    expect(await phone.rows('SELECT * FROM crop_cycles'), isEmpty);

    final events = await phone.rows(
      'SELECT entity, "action" FROM event_log ORDER BY created_at',
    );
    expect(events.map((e) => e['entity']), ['farms', 'farm_members', 'plots']);
    expect(events.every((e) => e['action'] == 'create'), isTrue);
    expect(
      (await phone.rows(
        "SELECT entity FROM outbox WHERE entity <> 'event_log' ORDER BY id",
      )).map((r) => r['entity']),
      ['farms', 'farm_members', 'plots'],
    );
  });

  test('chosen crops become crop cycles on the plot', () async {
    final crops = await phone.repo.standardCrops();
    final pepper = crops.firstWhere((c) => c.nameEn == 'Pepper');
    final coconut = crops.firstWhere((c) => c.nameEn == 'Coconut');
    await phone.repo.createFarm(
      user,
      SetupInput(
        name: 'Ravi',
        farmName: 'Home farm',
        area: 2500,
        areaUnit: 'acre',
        tenure: 'leased',
        cropIds: [coconut.id, pepper.id],
      ),
    );
    final plot = (await phone.rows('SELECT * FROM plots')).single;
    expect(plot['area'], 2500);
    expect(plot['area_unit'], 'acre');
    expect(plot['tenure'], 'leased');
    final cycles = await phone.rows('SELECT * FROM crop_cycles');
    expect(cycles.map((c) => c['crop_id']), [coconut.id, pepper.id]);
    expect(cycles.every((c) => c['plot_id'] == plot['id']), isTrue);
    expect(cycles.every((c) => c['status'] == 'active'), isTrue);
    expect(cycles.every((c) => c['started_on'] == '2026-11-19'), isTrue);
    final summary = jsonDecode(
      (await phone.rows(
            "SELECT summary FROM event_log WHERE entity = 'crop_cycles' "
            'ORDER BY created_at',
          )).first['summary']!
          as String,
    ) as Map;
    expect(summary['crop_en'], 'Coconut');
    expect(summary['plot'], 'Home farm');
  });

  test('a new phone signed in with an account that has a farm restores it, '
      'with no second farm', () async {
    final farmId = await phone.repo.createFarm(
      user,
      const SetupInput(name: 'Ravi', farmName: 'Home farm', areaUnit: 'cent'),
    );
    await phone.engine.sync();

    final second = Phone(server, user, seed: 2);
    addTearDown(second.db.close);
    final (invites, farms) = await second.repo.firstSync(
      second.server,
      second.engine,
    );
    expect(invites, isEmpty);
    expect(farms, [farmId]);
    expect(await second.rows('SELECT * FROM plots'), hasLength(1));
    expect(server.tables['farms'], hasLength(1));
  });

  test('a new account has nothing to restore', () async {
    final (invites, farms) = await phone.repo.firstSync(
      phone.server,
      phone.engine,
    );
    expect(invites, isEmpty);
    expect(farms, isEmpty);
  });

  test(
    'first sync offline fails as worth retrying, and works once online',
    () async {
      server.down = true;
      await expectLater(
        phone.repo.firstSync(phone.server, phone.engine),
        throwsA(isA<SyncUnavailable>()),
      );
      server.down = false;
      final (_, farms) = await phone.repo.firstSync(phone.server, phone.engine);
      expect(farms, isEmpty);
    },
  );

  group('invites', () {
    late Phone owner;
    late String farmId;

    setUp(() async {
      owner = Phone(server, 'user-other', seed: 3);
      await owner.templates();
      farmId = await owner.repo.createFarm(
        'user-other',
        const SetupInput(name: 'Mary', farmName: 'Hill farm', areaUnit: 'cent'),
      );
      await owner.engine.sync();
      server.invites[user] = [
        Invite(
          id: 'inv-1',
          farmId: farmId,
          farmName: 'Hill farm',
          role: 'manager',
          invitedBy: 'Mary',
        ),
      ];
    });
    tearDown(() => owner.db.close());

    test('sign-in sees an open invite but does not join the farm', () async {
      final (invites, farms) = await phone.repo.firstSync(
        phone.server,
        phone.engine,
      );
      expect(invites.single.farmName, 'Hill farm');
      expect(invites.single.invitedBy, 'Mary');
      expect(farms, isEmpty);
      expect(await phone.rows('SELECT * FROM farms'), isEmpty);
    });

    test('join adds the membership and pulls the farm', () async {
      final (invites, _) = await phone.repo.firstSync(
        phone.server,
        phone.engine,
      );
      expect(
        await phone.repo.join(phone.server, phone.engine, invites.single),
        farmId,
      );
      expect(await phone.repo.memberFarms(user), [farmId]);
      expect(
        (await phone.rows('SELECT name FROM plots')).single['name'],
        'Hill farm',
      );
    });

    test('decline leaves the account without the farm', () async {
      expect(await phone.server.declineInvite('inv-1'), farmId);
      final (invites, farms) = await phone.repo.firstSync(
        phone.server,
        phone.engine,
      );
      expect(invites, isEmpty);
      expect(farms, isEmpty);
    });
  });

  test('the farm to open is the last used one, else the first', () {
    expect(farmToOpen(['a', 'b'], 'b'), 'b');
    expect(farmToOpen(['a', 'b'], 'gone'), 'a');
    expect(farmToOpen(['a'], null), 'a');
    expect(farmToOpen([], 'a'), isNull);
  });
}
