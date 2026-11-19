import 'package:thottam/core/db/database.dart';
import 'package:thottam/core/history/write_with_history.dart';

/// Official pepper prices at Kochi (synced down, no farm): ₹690 on
/// 17 November, ₹700 on the 18th, ₹705 on the 19th at 10:00; one at
/// Kattappana; coconut's only price is from 15 November, so it is stale.
Future<void> priceFarm(AppDatabase db, History history, String farm) async {
  Future<String> crop(String en) async =>
      (await db
              .customSelect("SELECT id FROM crops WHERE name_en = '$en'")
              .getSingle())
          .read<String>('id');
  final pepper = await crop('Pepper');
  final coconut = await crop('Coconut');
  var n = 0;
  for (final (c, market, rupees, at) in [
    (pepper, 'Kochi', 690, DateTime(2026, 11, 17, 10)),
    (pepper, 'Kochi', 700, DateTime(2026, 11, 18, 10)),
    (pepper, 'Kattappana', 698, DateTime(2026, 11, 18, 9)),
    (pepper, 'Kochi', 705, DateTime(2026, 11, 19, 10)),
    (coconut, 'Kochi', 32, DateTime(2026, 11, 15, 10)),
  ]) {
    n++;
    await db.customStatement(
      'INSERT INTO market_prices (id, crop_id, market, price_paise, unit, '
      'source, published_at, created_at, updated_at) VALUES '
      "('official-$n', '$c', '$market', ${rupees * 100}, 'kg', "
      "'Spices Board', ${at.millisecondsSinceEpoch}, 0, 0)",
    );
  }
}
