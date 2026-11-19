import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/db/database.dart';
import '../../../core/history/write_with_history.dart';

/// A farm this account belongs to, with its role there.
typedef FarmView = ({String id, String name, String role});

/// A member of the open farm.
class MemberView {
  const MemberView({
    required this.id,
    required this.userId,
    required this.name,
    required this.role,
    required this.permissions,
  });

  final String id;
  final String userId;

  /// Empty until the member's profile reaches this phone.
  final String name;
  final String role;

  /// Access class → 'none' | 'read' | 'write', over the role's defaults.
  final Map<String, Object?> permissions;
}

/// An invitation not yet accepted.
typedef InviteView = ({String id, String email, String role});

/// Settings' farms and members (screen 7) and My lists' changes
/// (screen 16). Every write goes through history and the outbox; the server
/// applies members and invites by its own rules once they sync. Farms,
/// members and invites are a handful of rows, read here directly.
class SettingsRepository {
  SettingsRepository(this.db, this.history, this.farmId, this.userId);

  final AppDatabase db;
  final History history;
  final String farmId;
  final String userId;

  Stream<List<FarmView>> watchFarms() => db
      .customSelect(
        'SELECT f.id, f.name, m.role FROM farm_members m '
        'JOIN farms f ON f.id = m.farm_id WHERE m.user_id = ? '
        'AND m.deleted_at IS NULL AND f.deleted_at IS NULL ORDER BY f.name, f.id',
        variables: [Variable.withString(userId)],
        readsFrom: {db.farmMembers, db.farms},
      )
      .watch()
      .map(
        (rows) => [
          for (final r in rows)
            (
              id: r.read<String>('id'),
              name: r.read<String>('name'),
              role: r.read<String>('role'),
            ),
        ],
      );

  Stream<List<MemberView>> watchMembers() => db
      .customSelect(
        'SELECT m.id, m.user_id, m.role, m.permissions, '
        "COALESCE(p.full_name, '') AS name FROM farm_members m "
        'LEFT JOIN profiles p ON p.id = m.user_id '
        'WHERE m.farm_id = ? AND m.deleted_at IS NULL '
        "ORDER BY m.role <> 'owner', name, m.id",
        variables: [Variable.withString(farmId)],
        readsFrom: {db.farmMembers, db.profiles},
      )
      .watch()
      .map(
        (rows) => [
          for (final r in rows)
            MemberView(
              id: r.read<String>('id'),
              userId: r.read<String>('user_id'),
              name: r.read<String>('name'),
              role: r.read<String>('role'),
              permissions: (jsonDecode(r.read<String>('permissions')) as Map)
                  .cast<String, Object?>(),
            ),
        ],
      );

  Stream<List<InviteView>> watchInvites() => db
      .customSelect(
        'SELECT id, email, role FROM farm_invites WHERE farm_id = ? '
        'AND accepted_at IS NULL AND deleted_at IS NULL ORDER BY created_at, id',
        variables: [Variable.withString(farmId)],
        readsFrom: {db.farmInvites},
      )
      .watch()
      .map(
        (rows) => [
          for (final r in rows)
            (
              id: r.read<String>('id'),
              email: r.read<String>('email'),
              role: r.read<String>('role'),
            ),
        ],
      );

  // ---------- members ----------

  Future<List<String>> invite(String email, String role) {
    final e = email.trim().toLowerCase();
    return history.writeWithHistory([
      CreateRow(
        'farm_invites',
        {
          'id': history.newId(),
          'farm_id': farmId,
          'email': e,
          'role': role,
          'permissions': '{}',
        },
        summary: {'text': e},
      ),
    ]);
  }

  Future<List<String>> cancelInvite(InviteView i) => history.writeWithHistory([
    DeleteRow('farm_invites', i.id, summary: {'text': i.email}),
  ]);

  Future<List<String>> setRole(MemberView m, String role, String name) =>
      history.writeWithHistory([
        UpdateRow(
          'farm_members',
          m.id,
          {'role': role},
          summary: {'text': name},
        ),
      ]);

  /// Sets one area to [level], or back to the role's default with null.
  Future<List<String>> setPermission(
    MemberView m,
    String area,
    String? level,
    String name,
  ) {
    final p = {...m.permissions};
    level == null ? p.remove(area) : p[area] = level;
    return history.writeWithHistory([
      UpdateRow(
        'farm_members',
        m.id,
        {'permissions': jsonEncode(p)},
        summary: {'text': name},
      ),
    ]);
  }

  Future<List<String>> remove(MemberView m, String name) =>
      history.writeWithHistory([
        DeleteRow('farm_members', m.id, summary: {'text': name}),
      ]);

  // ---------- My lists ----------

  /// The template item [code] of [listType] stands for in [cropId]'s list:
  /// the crop's own item, else the one for every crop.
  Future<String?> _templateItem(
    String listType,
    String code,
    String? cropId,
  ) async {
    final rows = await db
        .customSelect(
          'SELECT id FROM template_items WHERE list_type = ? AND code = ? '
          'AND (crop_id IS NULL OR crop_id = ?) ORDER BY crop_id IS NULL LIMIT 1',
          variables: [
            Variable.withString(listType),
            Variable.withString(code),
            Variable(cropId),
          ],
        )
        .get();
    return rows.isEmpty ? null : rows.single.read<String>('id');
  }

  /// The farm-level change of a template item for [cropId] (null: every
  /// crop), or of the farmer's own item [code].
  Future<QueryRow?> _farmRow(
    String listType,
    String code,
    String? cropId,
    String? templateItemId,
  ) async {
    final rows = await db
        .customSelect(
          'SELECT id, name_ml, name_en, data FROM template_overrides '
          "WHERE farm_id = ? AND scope = 'farm' AND deleted_at IS NULL "
          "AND COALESCE(crop_id, '') = ? AND (template_item_id = ? "
          'OR (template_item_id IS NULL AND list_type = ? AND code = ?)) '
          'ORDER BY updated_at DESC LIMIT 1',
          variables: [
            Variable.withString(farmId),
            Variable.withString(cropId ?? ''),
            Variable(templateItemId),
            Variable.withString(listType),
            Variable.withString(code),
          ],
        )
        .get();
    return rows.firstOrNull;
  }

  /// Switches an item off, or on again. On again clears only the switch:
  /// the row goes when nothing else was changed on it (C10 follow-up).
  Future<List<String>> setShown(
    String listType,
    String code,
    String? cropId, {
    required bool shown,
    required bool own,
  }) async {
    final item = own ? null : await _templateItem(listType, code, cropId);
    final row = await _farmRow(listType, code, cropId, item);
    final summary = {'text': code};
    if (row == null) {
      if (shown) return const [];
      return history.writeWithHistory([
        CreateRow('template_overrides', {
          'id': history.newId(),
          'farm_id': farmId,
          'scope': 'farm',
          'template_item_id': item,
          'crop_id': cropId,
          'list_type': listType,
          'code': code,
          'hidden': true,
        }, summary: summary),
      ]);
    }
    final id = row.read<String>('id');
    final onlySwitch =
        !own &&
        row.readNullable<String>('name_ml') == null &&
        row.readNullable<String>('name_en') == null &&
        (jsonDecode(row.read<String>('data')) as Map).isEmpty;
    return history.writeWithHistory([
      if (shown && onlySwitch)
        DeleteRow('template_overrides', id, summary: summary)
      else
        UpdateRow('template_overrides', id, {
          'hidden': shown ? (own ? false : null) : true,
        }, summary: summary),
    ]);
  }

  /// The farmer's own item, for [cropId] or (null) every crop.
  Future<List<String>> addOwn(
    String listType,
    String? cropId,
    String? nameMl,
    String? nameEn,
  ) {
    final id = history.newId();
    return history.writeWithHistory([
      CreateRow(
        'template_overrides',
        {
          'id': id,
          'farm_id': farmId,
          'scope': 'farm',
          'crop_id': cropId,
          'list_type': listType,
          // own codes never meet a template code
          'code': 'own_$id',
          'name_ml': nameMl,
          'name_en': nameEn,
        },
        summary: {'text': nameMl ?? nameEn},
      ),
    ]);
  }

  Future<List<String>> removeOwn(
    String listType,
    String code,
    String? cropId,
  ) async {
    final row = await _farmRow(listType, code, cropId, null);
    if (row == null) return const [];
    return history.writeWithHistory([
      DeleteRow(
        'template_overrides',
        row.read<String>('id'),
        summary: {'text': code},
      ),
    ]);
  }

  /// Every template item of [listType] switched off for [cropId] comes back
  /// on; own items and other changes stay.
  Future<List<String>> resetShown(String listType, String? cropId) async {
    final rows = await db
        .customSelect(
          'SELECT o.id, o.name_ml, o.name_en, o.data FROM template_overrides o '
          'JOIN template_items i ON i.id = o.template_item_id '
          "WHERE o.farm_id = ? AND o.scope = 'farm' AND o.deleted_at IS NULL "
          "AND o.hidden = 1 AND i.list_type = ? AND COALESCE(o.crop_id, '') = ?",
          variables: [
            Variable.withString(farmId),
            Variable.withString(listType),
            Variable.withString(cropId ?? ''),
          ],
        )
        .get();
    return history.writeWithHistory([
      for (final r in rows)
        if (r.readNullable<String>('name_ml') == null &&
            r.readNullable<String>('name_en') == null &&
            (jsonDecode(r.read<String>('data')) as Map).isEmpty)
          DeleteRow('template_overrides', r.read<String>('id'))
        else
          UpdateRow('template_overrides', r.read<String>('id'), {
            'hidden': null,
          }),
    ]);
  }

  /// Marks the templates' latest version as seen: "new items" goes away.
  Future<List<String>> acceptTemplates(int version) =>
      history.writeWithHistory([
        UpdateRow('farms', farmId, {'accepted_template_version': version}),
      ]);

  Future<List<String>> undo(List<String> events) => history.undo(events);
}
