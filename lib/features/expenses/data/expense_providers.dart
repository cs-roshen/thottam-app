import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/session.dart';
import 'expense_repository.dart';

final expenseRepositoryProvider = Provider<ExpenseRepository>(
  (ref) => ExpenseRepository(
    ref.watch(databaseProvider),
    ref.watch(historyProvider),
    ref.watch(farmIdProvider),
  ),
);
