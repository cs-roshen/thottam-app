import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/session.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_server.dart';
import '../domain/setup.dart';
import 'onboarding_repository.dart';

final onboardingRepositoryProvider = Provider<OnboardingRepository>(
  (ref) => OnboardingRepository(
    ref.watch(databaseProvider),
    ref.watch(historyProvider),
  ),
);

/// What set-up offers: the standard crops and the area units, from the
/// templates bundled with the app.
final setupChoicesProvider = FutureProvider<(List<CropChoice>, List<String>)>((
  ref,
) async {
  await ref.watch(templatesReadyProvider.future);
  final repo = ref.watch(onboardingRepositoryProvider);
  return (await repo.standardCrops(), await repo.areaUnits());
});

/// The first sync after sign-in, retried by itself until it gets through.
/// The state is true while it waits for a connection.
class FirstSyncController extends Notifier<bool> {
  /// How long to wait before trying again; tests make it short.
  static Duration Function(int attempt) retryAfter = (n) => Duration(
    milliseconds: min(retryDelay(n, Random()).inMilliseconds, 15000),
  );

  bool _running = false;

  @override
  bool build() => false;

  /// Pulls what the account already has and its open invites, then lets the
  /// app move on. With no server yet (no real sign-in) there is nothing to
  /// pull.
  Future<void> run() async {
    if (_running) return;
    _running = true;
    try {
      final session = ref.read(sessionProvider.notifier);
      final server = ref.read(syncServerProvider);
      final engine = ref.read(syncEngineProvider);
      if (server == null || engine == null) {
        await session.firstSyncDone(null);
        return;
      }
      final repo = ref.read(onboardingRepositoryProvider);
      for (var attempt = 0; ref.mounted; attempt++) {
        try {
          final (invites, farms) = await repo.firstSync(server, engine);
          if (!ref.mounted) return;
          ref.read(pendingInvitesProvider.notifier).set(invites);
          state = false;
          await session.firstSyncDone(
            farmToOpen(farms, ref.read(sessionProvider).farmId),
          );
          return;
        } on SyncUnavailable {
          if (!ref.mounted) return;
          state = true;
          await Future<void>.delayed(retryAfter(attempt));
        }
      }
    } finally {
      _running = false;
    }
  }
}

final firstSyncProvider = NotifierProvider<FirstSyncController, bool>(
  FirstSyncController.new,
);
