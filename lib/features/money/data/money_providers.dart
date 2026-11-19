import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/session.dart';
import 'money_repository.dart';

final moneyRepositoryProvider = Provider<MoneyRepository>(
  (ref) =>
      MoneyRepository(ref.watch(databaseProvider), ref.watch(farmIdProvider)),
);

/// A period ('YYYY-MM-DD', both days included) and a plot, '' for all.
typedef MoneyQuery = ({String from, String to, String plot});

final cycleMoneyProvider =
    StreamProvider.family<List<CycleMoneyRow>, MoneyQuery>(
      (ref, q) => ref
          .watch(moneyRepositoryProvider)
          .watchCycles(from: q.from, to: q.to, plotId: q.plot),
    );
