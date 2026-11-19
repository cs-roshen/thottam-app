import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/session.dart';
import '../../../core/access/access.dart';
import '../domain/land.dart';
import 'land_repository.dart';

final landRepositoryProvider = Provider<LandRepository>(
  (ref) => LandRepository(
    ref.watch(databaseProvider),
    ref.watch(historyProvider),
    ref.watch(farmIdProvider),
  ),
);

/// Plots and crop cycles are set-up records: the owner and a manager write
/// them, everyone else reads (product spec rule 7).
final canWriteLandProvider = Provider<bool>(
  (ref) =>
      ref.watch(accessProvider).value?.canWrite(AccessClass.setup) ?? false,
);

final plotsProvider = StreamProvider<List<PlotView>>(
  (ref) => ref.watch(landRepositoryProvider).watchPlots(),
);

final plotProvider = StreamProvider.family<PlotView?, String>(
  (ref, id) => ref.watch(landRepositoryProvider).watchPlot(id),
);

final cycleTotalsProvider = StreamProvider.family<List<CycleTotals>, String>(
  (ref, plotId) => ref.watch(landRepositoryProvider).watchCycleTotals(plotId),
);

final plotCostsProvider = StreamProvider.family<List<(String, int)>, String>(
  (ref, plotId) =>
      ref.watch(landRepositoryProvider).watchCostsByCategory(plotId),
);

final plotHistoryProvider = StreamProvider.family<List<PlotEvent>, String>(
  (ref, plotId) => ref.watch(landRepositoryProvider).watchRecentHistory(plotId),
);

/// Latest price by crop id, for the crops of one plot (ids joined by ',').
final cropPricesProvider =
    StreamProvider.family<Map<String, (int, String, int)>, String>(
      (ref, ids) => ref
          .watch(landRepositoryProvider)
          .watchLatestPrices(ids.isEmpty ? const [] : ids.split(',')),
    );

final cropOptionsProvider = FutureProvider<List<CropOption>>((ref) async {
  await ref.watch(templatesReadyProvider.future);
  return ref.watch(landRepositoryProvider).crops();
});
