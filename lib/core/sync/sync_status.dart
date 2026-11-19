/// What the small sync line in Settings shows. Never a blocking dialog.
class SyncStatus {
  const SyncStatus({
    required this.waiting,
    required this.rejected,
    required this.conflicts,
    this.lastSyncedAt,
  });

  /// Changes saved on the phone, not yet uploaded.
  final int waiting;

  /// Changes the server will never accept (permission, validation).
  final int rejected;

  /// Changes from two phones that the farmer must choose between.
  final int conflicts;
  final DateTime? lastSyncedAt;
}
