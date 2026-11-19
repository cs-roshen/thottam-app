import 'package:drift/drift.dart';

import '../../../core/db/database.dart';
import '../../../core/db/queries.dart';
import '../../../core/history/write_with_history.dart';
import '../domain/prices.dart';

/// A crop's prices and the signed-in person's alert on it.
typedef CropPrices = ({List<PricePoint> points, int? alertPaise});

/// Prices from the local database (screen 14): official prices that sync
/// down and the farm's own shop rates. Works offline; each price keeps its
/// time, so the screen says how old it is.
class PricesRepository {
  PricesRepository(this.db, this.history, this.farmId, this.userId);

  final AppDatabase db;
  final History history;
  final String farmId;
  final String userId;

  Future<CropPrices> _load(String cropId) async {
    final points = [
      for (final r in await select(db, qCropPrices, {
        'row': cropId,
        'farm': farmId,
      }))
        PricePoint(
          paise: r.read<int>('price_paise'),
          unit: r.read<String>('unit'),
          market: r.read<String>('market'),
          source: r.read<String>('source'),
          at: DateTime.fromMillisecondsSinceEpoch(r.read<int>('published_at')),
          local: r.readNullable<String>('farm_id') != null,
        ),
    ];
    final alert = await select(db, qPriceAlert, {
      'row': cropId,
      'farm': farmId,
      'user': userId,
    });
    final on = alert.isNotEmpty && alert.single.read<bool>('is_active');
    return (
      points: points,
      alertPaise: on ? alert.single.read<int>('threshold_paise') : null,
    );
  }

  /// Each of [cropIds]' prices and alert, again whenever a price or alert
  /// changes.
  Stream<Map<String, CropPrices>> watch(List<String> cropIds) async* {
    Future<Map<String, CropPrices>> load() async => {
      for (final c in cropIds) c: await _load(c),
    };
    yield await load();
    await for (final _ in db.tableUpdates(
      TableUpdateQuery.onAllTables([db.marketPrices, db.priceAlerts]),
    )) {
      yield await load();
    }
  }

  /// The unit a crop is usually sold in.
  Future<String> defaultUnit(String cropId) async =>
      (await db
              .customSelect(
                'SELECT default_unit FROM crops WHERE id = ?',
                variables: [Variable.withString(cropId)],
              )
              .getSingle())
          .read<String>('default_unit');

  /// A rate from a shop or market, entered now on this farm.
  Future<List<String>> addPrice({
    required String cropId,
    required int paise,
    required String unit,
    required String market,
    required DateTime at,
    String? cropMl,
    String? cropEn,
  }) => history.writeWithHistory([
    CreateRow(
      'market_prices',
      {
        'id': history.newId(),
        'farm_id': farmId,
        'crop_id': cropId,
        'market': market.trim(),
        'price_paise': paise,
        'unit': unit,
        // the server's word for a rate entered on a farm
        'source': 'local',
        'published_at': at.millisecondsSinceEpoch,
      },
      summary: {'text': market.trim(), 'crop_ml': ?cropMl, 'crop_en': ?cropEn},
    ),
  ]);

  /// Turns the alert on at [thresholdPaise], or off with null.
  Future<List<String>> setAlert(String cropId, int? thresholdPaise) async {
    final rows = await select(db, qPriceAlert, {
      'row': cropId,
      'farm': farmId,
      'user': userId,
    });
    if (rows.isEmpty) {
      if (thresholdPaise == null) return const [];
      return history.writeWithHistory([
        CreateRow('price_alerts', {
          'id': history.newId(),
          'farm_id': farmId,
          'user_id': userId,
          'crop_id': cropId,
          'threshold_paise': thresholdPaise,
          'direction': 'above',
          'is_active': true,
        }),
      ]);
    }
    return history.writeWithHistory([
      UpdateRow('price_alerts', rows.single.read<String>('id'), {
        'is_active': thresholdPaise != null,
        'threshold_paise': ?thresholdPaise,
      }),
    ]);
  }

  Future<List<String>> undo(List<String> events) => history.undo(events);
}
