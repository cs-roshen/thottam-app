import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/session.dart';
import 'history_repository.dart';

final historyRepositoryProvider = Provider<HistoryRepository>(
  (ref) => HistoryRepository(
    ref.watch(databaseProvider),
    ref.watch(historyProvider),
    ref.watch(farmIdProvider),
  ),
);

/// A diary page: entities and actions as `,a,b,` lists, a plot or '', and
/// how many rows are shown so far.
typedef DiaryQuery = ({
  String entities,
  String actions,
  String plot,
  int limit,
});

final diaryProvider = StreamProvider.family<List<HistoryEvent>, DiaryQuery>(
  (ref, q) => ref
      .watch(historyRepositoryProvider)
      .watchDiary(
        entities: q.entities,
        actions: q.actions,
        plotId: q.plot,
        limit: q.limit,
      ),
);

final recordHistoryProvider =
    StreamProvider.family<List<HistoryEvent>, (String, String)>(
      (ref, r) => ref.watch(historyRepositoryProvider).watchRecord(r.$1, r.$2),
    );
