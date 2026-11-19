import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:thottam/core/db/database.dart';
import 'package:thottam/core/db/override_store.dart';
import 'package:thottam/core/history/write_with_history.dart';
import 'package:thottam/core/overrides/overrides.dart';
import 'package:thottam/features/onboarding/data/onboarding_repository.dart';
import 'package:thottam/features/onboarding/domain/setup.dart';
import 'package:thottam/features/settings/data/settings_repository.dart';

import '../../helpers/session.dart';

void main() {
  late AppDatabase db;
  late String farm;
  late History history;
  late SettingsRepository repo;
  late String pepper;

  setUp(() async {
    final (d, f) = await farmDatabase(crops: const ['Pepper']);
    db = d;
    farm = f;
    var now = DateTime(2026, 11, 19, 12);
    history = History(
      db,
      userId: testUser,
      clock: () => now = now.add(const Duration(milliseconds: 10)),
      random: Random(11),
    );
    repo = SettingsRepository(db, history, farm, testUser);
    pepper =
        (await db
                .customSelect("SELECT id FROM crops WHERE name_en = 'Pepper'")
                .getSingle())
            .read<String>('id');
  });
  tearDown(() => db.close());

  Future<Overrides> overrides() => watchOverrides(db, farm).first;
  Future<List<ListItem>> activities([String? crop]) async =>
      (await overrides()).list('activity', Scope(cropId: crop ?? pepper));
  Future<ListItem> item(String code) async =>
      (await activities()).firstWhere((i) => i.code == code);
  Future<int> rows(String sql) async =>
      (await db.customSelect(sql).getSingle()).read<int>('n');

  group('My lists', () {
    test('switching an activity off hides it for this crop only; on again '
        'removes the change', () async {
      expect((await item('mulching')).hidden, isFalse);
      await repo.setShown(
        'activity',
        'mulching',
        pepper,
        shown: false,
        own: false,
      );
      expect((await item('mulching')).hidden, isTrue);
      expect(
        await rows(
          "SELECT COUNT(*) AS n FROM template_overrides WHERE deleted_at IS NULL "
          "AND hidden = 1 AND crop_id = '$pepper'",
        ),
        1,
      );
      await repo.setShown(
        'activity',
        'mulching',
        pepper,
        shown: true,
        own: false,
      );
      expect((await item('mulching')).hidden, isFalse);
      expect(
        await rows(
          'SELECT COUNT(*) AS n FROM template_overrides WHERE deleted_at IS NULL',
        ),
        0,
      );
    });

    test('switching on again clears only the switch: a renamed item keeps '
        'its name', () async {
      await repo.setShown(
        'activity',
        'mulching',
        pepper,
        shown: false,
        own: false,
      );
      await db.customStatement(
        "UPDATE template_overrides SET name_en = 'Mulch with leaves'",
      );
      await repo.setShown(
        'activity',
        'mulching',
        pepper,
        shown: true,
        own: false,
      );
      final m = await item('mulching');
      expect(m.hidden, isFalse);
      expect(m.nameEn.value, 'Mulch with leaves');
    });

    test('an admin update never changes an item the farmer switched off; '
        'it shows as new items until seen', () async {
      await repo.setShown(
        'activity',
        'mulching',
        pepper,
        shown: false,
        own: false,
      );
      final before = await overrides();
      expect(before.latestVersion, before.acceptedVersion);
      // the admin renames the item and publishes a new version
      await db.customStatement(
        "UPDATE template_items SET name_en = 'Mulching (dry leaves)', "
        "template_version = (SELECT MAX(accepted_template_version) + 1 "
        "FROM farms) WHERE code = 'mulching' "
        "AND list_type = 'activity'",
      );
      final after = await overrides();
      final m = (after.list(
        'activity',
        Scope(cropId: pepper),
      )).firstWhere((i) => i.code == 'mulching');
      expect(m.hidden, isTrue);
      expect(m.updateAvailable, isTrue);
      expect(after.latestVersion, greaterThan(after.acceptedVersion));

      await repo.acceptTemplates(after.latestVersion);
      final seen = await overrides();
      expect(seen.latestVersion, seen.acceptedVersion);
      expect(
        (seen.list(
          'activity',
          Scope(cropId: pepper),
        )).firstWhere((i) => i.code == 'mulching').hidden,
        isTrue,
      );
    });

    test('own items: added, switched, kept by reset, removed', () async {
      await repo.addOwn('activity', pepper, 'കുരുമുളക് കെട്ടൽ', null);
      final own = (await activities()).singleWhere((i) => i.isOwn);
      expect(own.nameEn.value, 'കുരുമുളക് കെട്ടൽ');
      // another crop does not see it
      final banana =
          (await db
                  .customSelect("SELECT id FROM crops WHERE name_en = 'Banana'")
                  .getSingle())
              .read<String>('id');
      expect((await activities(banana)).where((i) => i.isOwn), isEmpty);

      await repo.setShown(
        'activity',
        own.code,
        pepper,
        shown: false,
        own: true,
      );
      await repo.setShown(
        'activity',
        'mulching',
        pepper,
        shown: false,
        own: false,
      );
      await repo.resetShown('activity', pepper);
      expect((await item('mulching')).hidden, isFalse);
      expect((await activities()).singleWhere((i) => i.isOwn).hidden, isTrue);

      await repo.removeOwn('activity', own.code, pepper);
      expect((await activities()).where((i) => i.isOwn), isEmpty);
    });

    test('every change is in history and waits to sync', () async {
      await repo.setShown(
        'activity',
        'mulching',
        pepper,
        shown: false,
        own: false,
      );
      expect(
        await rows(
          "SELECT COUNT(*) AS n FROM event_log WHERE entity = 'template_overrides'",
        ),
        1,
      );
      expect(
        await rows(
          "SELECT COUNT(*) AS n FROM outbox WHERE entity = 'template_overrides'",
        ),
        1,
      );
    });
  });

  group('members', () {
    Future<MemberView> addMember() async {
      await db.customStatement(
        "INSERT INTO profiles (id, full_name, created_at, updated_at) "
        "VALUES ('user-anu', 'Anu', 0, 0)",
      );
      await history.writeWithHistory([
        CreateRow('farm_members', {
          'id': 'member-anu',
          'farm_id': farm,
          'user_id': 'user-anu',
          'role': 'supervisor',
        }),
      ]);
      return (await repo.watchMembers().first).firstWhere(
        (m) => m.userId == 'user-anu',
      );
    }

    test('the owner first, then the others by name', () async {
      await addMember();
      final members = await repo.watchMembers().first;
      expect(members.map((m) => (m.userId, m.role)), [
        (testUser, 'owner'),
        ('user-anu', 'supervisor'),
      ]);
      expect(members.last.name, 'Anu');
    });

    test('an invite by Google email waits to sync; cancelling takes it '
        'back', () async {
      await repo.invite('  Anu.K@Gmail.com ', 'accountant');
      final invites = await repo.watchInvites().first;
      expect(invites.single.email, 'anu.k@gmail.com');
      expect(invites.single.role, 'accountant');
      expect(
        await rows(
          "SELECT COUNT(*) AS n FROM outbox WHERE entity = 'farm_invites'",
        ),
        1,
      );
      await repo.cancelInvite(invites.single);
      expect(await repo.watchInvites().first, isEmpty);
    });

    test(
      'a per-person permission over the role, and back to the role',
      () async {
        final anu = await addMember();
        await repo.setPermission(anu, 'money', 'read', 'Anu');
        final after = (await repo.watchMembers().first).last;
        expect(after.permissions, {'money': 'read'});
        final stored = await db
            .customSelect(
              "SELECT permissions FROM farm_members WHERE id = 'member-anu'",
            )
            .getSingle();
        expect(jsonDecode(stored.read<String>('permissions')), {
          'money': 'read',
        });
        await repo.setPermission(after, 'money', null, 'Anu');
        expect((await repo.watchMembers().first).last.permissions, isEmpty);
      },
    );

    test('changing a role and removing a member are in history', () async {
      final anu = await addMember();
      await repo.setRole(anu, 'manager', 'Anu');
      expect((await repo.watchMembers().first).last.role, 'manager');
      await repo.remove(anu, 'Anu');
      expect((await repo.watchMembers().first).map((m) => m.userId), [
        testUser,
      ]);
      expect(
        await rows(
          "SELECT COUNT(*) AS n FROM event_log WHERE entity = 'farm_members' "
          "AND action IN ('update', 'delete')",
        ),
        2,
      );
    });
  });

  test('farms: each with its role', () async {
    final other = await OnboardingRepository(db, history).createFarm(
      testUser,
      const SetupInput(
        name: 'Ravi',
        farmName: 'Hill garden',
        area: 10000,
        areaUnit: 'cent',
        cropIds: [],
      ),
    );
    final farms = await repo.watchFarms().first;
    expect(farms.map((f) => (f.name, f.role)), [
      ('Hill garden', 'owner'),
      ('Riverside', 'owner'),
    ]);
    expect(farms.first.id, other);
  });
}
