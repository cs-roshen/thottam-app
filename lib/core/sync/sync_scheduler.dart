import 'dart:async';
import 'dart:math';

import 'sync_engine.dart';
import 'sync_server.dart';

/// When sync runs (implementation plan section 13): a few seconds after a
/// local write, when the app comes to the foreground, and every [period]
/// while it is open; after a failure it waits longer each time. One run at a
/// time, always in the background.
// shortcut: no connectivity or battery signal and no background work yet;
// retries with backoff stand in for "connectivity returned". Add the
// planned connectivity and background-work packages before the beta (D5).
class SyncScheduler {
  SyncScheduler(
    this.engine, {
    this.debounce = const Duration(seconds: 3),
    this.period = const Duration(minutes: 15),
    Duration Function(int attempt)? backoff,
    Random? random,
  }) : _backoff = backoff ?? ((n) => retryDelay(n, random ?? Random()));

  final SyncEngine engine;
  final Duration debounce;
  final Duration period;
  final Duration Function(int attempt) _backoff;

  Timer? _debounceTimer;
  Timer? _periodic;
  Timer? _retry;
  StreamSubscription<int>? _writes;
  bool _running = false;
  bool _again = false;
  int _failures = 0;

  void start() {
    final db = engine.db;
    _writes = db
        .customSelect(
          "SELECT COUNT(*) AS n FROM outbox WHERE status = 'pending'",
          readsFrom: {db.outbox},
        )
        .watchSingle()
        .map((r) => r.read<int>('n'))
        .distinct()
        .listen((n) {
          if (n > 0) poke();
        });
    _periodic = Timer.periodic(period, (_) => runNow());
  }

  /// A local write happened: sync once things settle.
  void poke() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, runNow);
  }

  /// The app came to the foreground.
  void onForeground() => runNow();

  Future<void> runNow() async {
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    _retry?.cancel();
    try {
      await engine.sync();
      _failures = 0;
    } on SyncUnavailable {
      _retry = Timer(_backoff(_failures++), runNow);
    } finally {
      _running = false;
      if (_again) {
        _again = false;
        poke();
      }
    }
  }

  Future<void> dispose() async {
    _debounceTimer?.cancel();
    _periodic?.cancel();
    _retry?.cancel();
    await _writes?.cancel();
  }
}
