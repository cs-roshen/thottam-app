import 'package:thottam/core/db/database.dart';
import 'package:thottam/core/history/write_with_history.dart';
import 'package:thottam/features/land/data/land_repository.dart';

import '../money/money_test_farm.dart';

/// Home on 19 November 2026: the spec's profit example, four tasks (due
/// today, overdue, done yesterday, due tomorrow) and a pepper price from
/// two days ago.
Future<void> homeFarm(AppDatabase db, History history, String farm) async {
  await specExample(db, history, farm);
  final plot = (await LandRepository(
    db,
    history,
    farm,
  ).watchPlots().first).single;
  final pepper = plot.cycles.firstWhere((c) => c.nameEn == 'Pepper');
  final yesterday = DateTime(2026, 11, 18, 9).millisecondsSinceEpoch;
  await history.writeWithHistory([
    for (final (title, due, done) in [
      ('Spray Bordeaux', '2026-11-19', null),
      ('Tie the vines', '2026-11-12', null),
      ('Weed the basins', '2026-11-18', yesterday),
      ('Apply lime', '2026-11-20', null),
    ])
      CreateRow('tasks', {
        'id': history.newId(),
        'farm_id': farm,
        'crop_cycle_id': pepper.id,
        'title': title,
        'due_on': due,
        'done_at': done,
      }),
    CreateRow('market_prices', {
      'id': history.newId(),
      'farm_id': farm,
      'crop_id': pepper.cropId,
      'market': 'Kochi',
      'price_paise': 70500,
      'unit': 'kg',
      'source': 'manual',
      'published_at': DateTime(2026, 11, 17, 10).millisecondsSinceEpoch,
    }),
  ]);
}
