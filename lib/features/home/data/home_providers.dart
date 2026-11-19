import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/session.dart';
import 'home_repository.dart';

final homeRepositoryProvider = Provider<HomeRepository>(
  (ref) => HomeRepository(
    ref.watch(databaseProvider),
    ref.watch(historyProvider),
    ref.watch(farmIdProvider),
  ),
);

/// Today's tasks, for the day the clock says when Home opens.
final todayTasksProvider = StreamProvider<List<TaskView>>((ref) {
  final now = ref.watch(clockProvider)();
  final start = DateTime(now.year, now.month, now.day);
  return ref
      .watch(homeRepositoryProvider)
      .watchTodayTasks(isoDay(start), start.millisecondsSinceEpoch);
});

String isoDay(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
