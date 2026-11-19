import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/session.dart';
import '../../../core/access/access.dart';
import 'harvest_repository.dart';

final harvestRepositoryProvider = Provider<HarvestRepository>(
  (ref) => HarvestRepository(
    ref.watch(databaseProvider),
    ref.watch(historyProvider),
    ref.watch(farmIdProvider),
  ),
);

Access _access(Ref ref) => ref.watch(accessProvider).value ?? Access.none;

/// Lot costs are money: only roles that read money ever read them.
final canSeeLotCostProvider = Provider<bool>(
  (ref) => _access(ref).canRead(AccessClass.money),
);

final canWriteLotCostProvider = Provider<bool>(
  (ref) => _access(ref).canWrite(AccessClass.money),
);

final harvestProvider = StreamProvider.family<HarvestView?, String>(
  (ref, id) => ref
      .watch(harvestRepositoryProvider)
      .watchHarvest(id, withCost: ref.watch(canSeeLotCostProvider)),
);

/// On a phone that can write money, works out every lot cost left for it
/// (a supervisor's harvest, or teams edited since), now and whenever lots
/// change, as rule 9 asks. Watched by the shell; does nothing elsewhere.
final lotCostSettlerProvider = StreamProvider<int>((ref) async* {
  if (!ref.watch(canWriteLotCostProvider)) return;
  final db = ref.watch(databaseProvider);
  final repo = ref.watch(harvestRepositoryProvider);
  yield await repo.settlePending();
  await for (final _ in db.tableUpdates(TableUpdateQuery.onTable(db.lots))) {
    yield await repo.settlePending();
  }
});
