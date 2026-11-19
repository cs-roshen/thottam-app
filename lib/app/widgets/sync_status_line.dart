import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../../core/sync/sync_status.dart';
import '../../l10n/app_localizations.dart';

/// The sync line for Settings: last synced time and anything waiting.
/// Information only; sync never blocks a screen.
class SyncStatusLine extends StatelessWidget {
  const SyncStatusLine({super.key, required this.status});

  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final last = status.lastSyncedAt;
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            last == null
                ? l10n.syncNever
                : l10n.syncLastSynced(
                    // gate: not user-facing
                    DateFormat('d MMM, h:mm a', l10n.localeName).format(last),
                  ),
            style: text.bodyLarge,
          ),
          // "Everything is synced" only when it is true
          if (status.waiting > 0 ||
              (last != null && status.conflicts == 0 && status.rejected == 0))
            Text(l10n.syncWaiting(status.waiting), style: text.bodyMedium),
          if (status.conflicts > 0)
            Text(l10n.syncConflicts(status.conflicts), style: text.bodyMedium),
          if (status.rejected > 0)
            Text(l10n.syncRejected(status.rejected), style: text.bodyMedium),
        ],
      ),
    );
  }
}
