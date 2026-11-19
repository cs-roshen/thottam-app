import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/session.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_server.dart';
import 'settings_repository.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(
    ref.watch(databaseProvider),
    ref.watch(historyProvider),
    ref.watch(farmIdProvider),
    ref.watch(userIdProvider),
  ),
);

final farmsProvider = StreamProvider<List<FarmView>>(
  (ref) => ref.watch(settingsRepositoryProvider).watchFarms(),
);

final membersProvider = StreamProvider<List<MemberView>>(
  (ref) => ref.watch(settingsRepositoryProvider).watchMembers(),
);

final farmInvitesProvider = StreamProvider<List<InviteView>>(
  (ref) => ref.watch(settingsRepositoryProvider).watchInvites(),
);

final syncStatusProvider = StreamProvider<SyncStatus>(
  (ref) => watchSyncStatus(ref.watch(databaseProvider)),
);

/// This account's open invites to other farms, asked of the server when
/// Farms opens; none when offline or before there is a server.
final openInvitesProvider = FutureProvider<List<Invite>>((ref) async {
  final server = ref.watch(syncServerProvider);
  if (server == null) return const [];
  try {
    return await server.invites();
  } on SyncUnavailable {
    return const [];
  }
});
