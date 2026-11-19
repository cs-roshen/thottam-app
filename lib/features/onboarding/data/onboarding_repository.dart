import 'package:drift/drift.dart';

import '../../../core/db/database.dart';
import '../../../core/history/write_with_history.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_server.dart';
import '../domain/setup.dart';

/// Reads what set-up offers and creates the first farm (screens.md 1, 17).
class OnboardingRepository {
  OnboardingRepository(this.db, this.history);

  final AppDatabase db;
  final History history;

  /// The standard crops from the templates.
  Future<List<CropChoice>> standardCrops() async => [
    for (final r
        in await db
            .customSelect(
              'SELECT id, name_ml, name_en FROM crops '
              'WHERE owner_farm_id IS NULL AND deleted_at IS NULL '
              'ORDER BY name_en',
            )
            .get())
      CropChoice(
        r.read<String>('id'),
        r.read<String>('name_ml'),
        r.read<String>('name_en'),
      ),
  ];

  /// Area unit codes from the templates, in template order. Screens show a
  /// unit by its code, which is its English name.
  Future<List<String>> areaUnits() async => [
    for (final r
        in await db
            .customSelect(
              "SELECT code FROM template_items WHERE list_type = 'unit' "
              'AND crop_id IS NULL AND is_active = 1 '
              "AND json_extract(data, '\$.dimension') = 'area' "
              'ORDER BY sort_order, code',
            )
            .get())
      r.read<String>('code'),
  ];

  /// Creates the farm, the owner's membership, one plot carrying the farm's
  /// area and tenure, and a crop cycle per chosen crop, in one transaction.
  /// The farm starts from the templates on the phone, so "update available"
  /// starts clear. Returns the farm id.
  Future<String> createFarm(String userId, SetupInput input) async {
    final version = await db
        .customSelect(
          'SELECT COALESCE(MAX(template_version), 0) AS v FROM template_items',
        )
        .getSingle();
    final crops = {for (final c in await standardCrops()) c.id: c};
    final farmId = history.newId();
    final plotId = history.newId();
    final farmName = input.farmName.trim();
    final today = history.today();
    await history.writeWithHistory([
      CreateRow(
        'farms',
        {
          'id': farmId,
          'name': farmName,
          'accepted_template_version': version.read<int>('v'),
        },
        summary: {'farm': farmName},
      ),
      CreateRow(
        'farm_members',
        {'farm_id': farmId, 'user_id': userId, 'role': 'owner'},
        summary: {'role': 'owner'},
      ),
      CreateRow(
        'plots',
        {
          'id': plotId,
          'farm_id': farmId,
          'name': farmName,
          'area': input.area,
          'area_unit': input.areaUnit,
          'tenure': input.tenure,
        },
        summary: {'plot_id': plotId, 'plot': farmName},
      ),
      for (final id in input.cropIds)
        CreateRow(
          'crop_cycles',
          {
            'farm_id': farmId,
            'plot_id': plotId,
            'crop_id': id,
            'started_on': today,
            'status': 'active',
          },
          summary: {
            'plot_id': plotId,
            'plot': farmName,
            'crop_ml': crops[id]?.nameMl,
            'crop_en': crops[id]?.nameEn,
          },
        ),
    ]);
    return farmId;
  }

  /// The farms [userId] belongs to on this phone, by name.
  Future<List<String>> memberFarms(String userId) async => [
    for (final r
        in await db
            .customSelect(
              'SELECT f.id FROM farm_members m JOIN farms f ON f.id = m.farm_id '
              'WHERE m.user_id = ? AND m.deleted_at IS NULL '
              'AND f.deleted_at IS NULL ORDER BY f.name, f.id',
              variables: [Variable.withString(userId)],
            )
            .get())
      r.read<String>('id'),
  ];

  /// The first sync after sign-in: the account's open invites, then
  /// everything it already has. Throws [SyncUnavailable] when offline.
  Future<(List<Invite>, List<String>)> firstSync(
    SyncServer server,
    SyncEngine engine,
  ) async {
    final invites = await server.invites();
    await engine.sync();
    return (invites, await memberFarms(engine.userId));
  }

  /// Joins [invite]'s farm and pulls it. Returns the farm id, or null when
  /// the invite is no longer open.
  Future<String?> join(
    SyncServer server,
    SyncEngine engine,
    Invite invite,
  ) async {
    final farm = await server.acceptInvite(invite.id);
    if (farm != null) await engine.sync();
    return farm;
  }
}
