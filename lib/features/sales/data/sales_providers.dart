import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/session.dart';
import '../../../core/access/access.dart';
import 'sales_repository.dart';

final salesRepositoryProvider = Provider<SalesRepository>(
  (ref) => SalesRepository(
    ref.watch(databaseProvider),
    ref.watch(historyProvider),
    ref.watch(farmIdProvider),
  ),
);

/// Sales, buyers and what they owe are money (product spec rule 7).
final canSellProvider = Provider<bool>(
  (ref) =>
      ref.watch(accessProvider).value?.canWrite(AccessClass.money) ?? false,
);

final lotsInStockProvider = StreamProvider<List<LotInStock>>(
  (ref) => ref.watch(salesRepositoryProvider).watchLotsInStock(),
);

final buyersProvider = StreamProvider<List<Buyer>>(
  (ref) => ref.watch(salesRepositoryProvider).watchBuyers(),
);

final buyerSalesProvider = StreamProvider.family<List<BuyerSale>, String>(
  (ref, id) => ref.watch(salesRepositoryProvider).watchBuyerSales(id),
);
