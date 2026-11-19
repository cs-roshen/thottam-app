import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/session.dart';
import '../../../core/access/access.dart';
import 'labour_repository.dart';

final labourRepositoryProvider = Provider<LabourRepository>(
  (ref) => LabourRepository(
    ref.watch(databaseProvider),
    ref.watch(historyProvider),
    ref.watch(farmIdProvider),
  ),
);

final workersProvider = StreamProvider<List<WorkerView>>(
  (ref) => ref.watch(labourRepositoryProvider).watchWorkers(),
);

final groupsProvider = StreamProvider<List<GroupView>>(
  (ref) => ref.watch(labourRepositoryProvider).watchGroups(),
);

final workerLedgerProvider = StreamProvider.family<List<LedgerLine>, String>(
  (ref, id) => ref.watch(labourRepositoryProvider).watchLedger(workerId: id),
);

final groupLedgerProvider = StreamProvider.family<List<LedgerLine>, String>(
  (ref, id) => ref.watch(labourRepositoryProvider).watchLedger(groupId: id),
);

Access _access(Ref ref) => ref.watch(accessProvider).value ?? Access.none;

/// Days of work: owner, manager and supervisor (product spec rule 7).
final canWriteDailyProvider = Provider<bool>(
  (ref) => _access(ref).canWrite(AccessClass.daily),
);

/// Workers and groups: a supervisor may add and edit them too.
final canWriteTeamProvider = Provider<bool>(
  (ref) => _access(ref).canWrite(AccessClass.team),
);

/// Payments and balances are money.
final canSeeLabourMoneyProvider = Provider<bool>(
  (ref) => _access(ref).canRead(AccessClass.money),
);

final canPayProvider = Provider<bool>(
  (ref) => _access(ref).canWrite(AccessClass.money),
);
