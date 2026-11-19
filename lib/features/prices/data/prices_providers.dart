import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/session.dart';
import '../../../core/access/access.dart';
import 'prices_repository.dart';

final pricesRepositoryProvider = Provider<PricesRepository>(
  (ref) => PricesRepository(
    ref.watch(databaseProvider),
    ref.watch(historyProvider),
    ref.watch(farmIdProvider),
    ref.watch(userIdProvider),
  ),
);

/// Prices and alerts of the crops in [cropIds] (comma-separated).
final cropPricesListProvider =
    StreamProvider.family<Map<String, CropPrices>, String>(
      (ref, ids) => ref
          .watch(pricesRepositoryProvider)
          .watch(ids.isEmpty ? const [] : ids.split(',')),
    );

/// Shop rates and alerts follow the server's prices rule: owner, manager
/// and accountant write them; everyone else reads.
final canWritePricesProvider = Provider<bool>(
  (ref) =>
      ref.watch(accessProvider).value?.canWrite(AccessClass.prices) ?? false,
);
