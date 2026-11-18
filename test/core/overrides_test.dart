import 'package:drift/drift.dart' show TableUpdate;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thottam/core/db/database.dart';
import 'package:thottam/core/db/override_store.dart';
import 'package:thottam/core/overrides/overrides.dart';

const pepper = 'crop-pepper';
const coconut = 'crop-coconut';
const plot = 'plot-1';
const cycle = 'cycle-1';
const here = Scope(cropId: pepper, plotId: plot, cropCycleId: cycle);

const climber = TemplateItem(
  id: 'item-climber',
  listType: 'rate_class',
  code: 'climber',
  nameMl: 'കയറ്റക്കാർ',
  nameEn: 'Climbers',
  data: {'default_rate_paise': 120000},
);
const splitAll = TemplateItem(
  id: 'item-split',
  listType: 'setting',
  code: 'split_weight',
  nameMl: 'വിഹിതം',
  nameEn: 'Share',
  data: {'value': 50},
);
const splitPepper = TemplateItem(
  id: 'item-split-pepper',
  cropId: pepper,
  listType: 'setting',
  code: 'split_weight',
  nameMl: 'വിഹിതം',
  nameEn: 'Share',
  data: {'value': 30},
);

TemplateOverride rate(String id, Level scope, int paise, [String? scopeId]) =>
    TemplateOverride(
      id: id,
      scope: scope,
      scopeId: scopeId,
      templateItemId: climber.id,
      data: {'default_rate_paise': paise},
    );

void main() {
  Object? rateIn(List<TemplateOverride> o, {Scope scope = here, int? entry}) =>
      Overrides(items: const [climber], overrides: o)
          .value(
            'rate_class',
            'climber',
            'default_rate_paise',
            scope,
            entryValue: entry,
          )
          ?.value;

  test('each level wins over the ones above it', () {
    expect(rateIn([]), 120000);
    final farm = rate('o-farm', Level.farm, 110000);
    final plotO = rate('o-plot', Level.plot, 105000, plot);
    final cycleO = rate('o-cycle', Level.cropCycle, 100000, cycle);
    expect(rateIn([farm]), 110000);
    expect(rateIn([farm, plotO]), 105000);
    expect(rateIn([cycleO, farm, plotO]), 100000);
    expect(rateIn([cycleO, farm, plotO], entry: 95000), 95000);
  });

  test('the level and the override row that set the value are reported', () {
    final o = Overrides(
      items: const [climber],
      overrides: [rate('o-plot', Level.plot, 105000, plot)],
    );
    final r = o.value('rate_class', 'climber', 'default_rate_paise', here)!;
    expect(r.level, Level.plot);
    expect(r.overrideId, 'o-plot');
    final app = o.value(
      'rate_class',
      'climber',
      'default_rate_paise',
      const Scope(cropId: pepper, plotId: 'another plot'),
    )!;
    expect(app.level, Level.app);
    expect(app.overrideId, isNull);
  });

  test('reset falls back one level', () {
    final farm = rate('o-farm', Level.farm, 110000);
    final plotO = rate('o-plot', Level.plot, 105000, plot);
    final cycleO = rate('o-cycle', Level.cropCycle, 100000, cycle);
    // resetting the crop cycle value leaves the plot value, and so on up
    expect(rateIn([farm, plotO]), 105000);
    expect(rateIn([farm, cycleO]), 100000);
    expect(rateIn([farm]), 110000);
    expect(rateIn([]), 120000);
  });

  test('plot and crop cycle overrides apply only where they belong', () {
    final plotO = rate('o-plot', Level.plot, 105000, plot);
    expect(rateIn([plotO], scope: const Scope(plotId: 'other')), 120000);
    final cycleO = rate('o-cycle', Level.cropCycle, 100000, cycle);
    expect(rateIn([cycleO], scope: const Scope(cropCycleId: 'other')), 120000);
  });

  test('a crop\'s own template item wins over the one for all crops', () {
    final o = Overrides(
      items: const [splitAll, splitPepper],
      overrides: const [],
    );
    expect(o.value('setting', 'split_weight', 'value', here)!.value, 30);
    expect(
      o
          .value(
            'setting',
            'split_weight',
            'value',
            const Scope(cropId: coconut),
          )!
          .value,
      50,
    );
  });

  test('an admin update never changes a value the farmer edited or hid', () {
    final edited = rate('o-farm', Level.farm, 110000);
    const hide = TemplateOverride(
      id: 'o-hide',
      scope: Level.farm,
      templateItemId: 'item-split',
      hidden: true,
    );
    final before = Overrides(
      items: const [climber, splitAll],
      overrides: [edited, hide],
    );
    // the admin publishes new rates and names (template version 2)
    const climber2 = TemplateItem(
      id: 'item-climber',
      listType: 'rate_class',
      code: 'climber',
      nameMl: 'കയറ്റം',
      nameEn: 'Climbing',
      data: {'default_rate_paise': 150000, 'note': 'new'},
      templateVersion: 2,
    );
    const split2 = TemplateItem(
      id: 'item-split',
      listType: 'setting',
      code: 'split_weight',
      nameMl: 'വിഹിതം',
      nameEn: 'Share',
      data: {'value': 70},
      templateVersion: 2,
    );
    final after = Overrides(
      items: const [climber2, split2],
      overrides: [edited, hide],
      acceptedVersion: 1,
    );
    for (final o in [before, after]) {
      expect(
        o.value('rate_class', 'climber', 'default_rate_paise', here)!.value,
        110000,
      );
      expect(o.list('setting', const Scope()).single.hidden, isTrue);
    }
    final item = after.list('rate_class', here).single;
    expect(item.updateAvailable, isTrue);
    expect(item.data['default_rate_paise']!.value, 110000);
    expect(
      item.data['note']!.level,
      Level.app,
    ); // fields the farmer left alone follow the admin
  });

  test(
    'lists merge names, keep hidden items marked and add the farmer\'s own',
    () {
      final o = Overrides(
        items: const [climber],
        overrides: const [
          TemplateOverride(
            id: 'o-name',
            scope: Level.farm,
            templateItemId: 'item-climber',
            nameEn: 'Tree climbers',
          ),
          TemplateOverride(
            id: 'o-own',
            scope: Level.farm,
            listType: 'rate_class',
            code: 'women',
            nameMl: 'സ്ത്രീകൾ',
            nameEn: 'Women',
            data: {'default_rate_paise': 70000},
          ),
          TemplateOverride(
            id: 'o-own-plot',
            scope: Level.plot,
            scopeId: 'other plot',
            listType: 'rate_class',
            code: 'elsewhere',
            nameMl: 'മറ്റിടം',
            nameEn: 'Elsewhere',
          ),
        ],
      );
      final items = o.list('rate_class', here);
      expect(items.map((i) => i.code), ['climber', 'women']);
      expect(items.first.nameEn.value, 'Tree climbers');
      expect(items.first.nameEn.level, Level.farm);
      expect(items.first.nameMl.level, Level.app);
      expect(items.last.isOwn, isTrue);
      expect(
        o.value('rate_class', 'women', 'default_rate_paise', here)!.value,
        70000,
      );
    },
  );

  test('inactive template items are not offered', () {
    const old = TemplateItem(
      id: 'x',
      listType: 'unit',
      code: 'old',
      nameMl: 'പഴയ',
      nameEn: 'Old',
      isActive: false,
    );
    expect(
      Overrides(items: const [old], overrides: const []).list('unit', here),
      isEmpty,
    );
  });

  test(
    'the store loads from the database and loads again on every change',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customStatement(
        "INSERT INTO farms (id, name, created_at, updated_at) VALUES ('f1', 'F', 0, 0)",
      );
      await db.customStatement(
        'INSERT INTO template_items (id, list_type, code, name_ml, name_en, data, created_at, updated_at) '
        "VALUES ('item-climber', 'rate_class', 'climber', 'കയറ്റക്കാർ', 'Climbers', "
        "'{\"default_rate_paise\": 120000}', 0, 0)",
      );
      final stream = watchOverrides(db, 'f1');
      final values = stream
          .map(
            (o) => o
                .value('rate_class', 'climber', 'default_rate_paise', here)
                ?.value,
          )
          .take(2)
          .toList();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await db.customStatement(
        'INSERT INTO template_overrides (id, farm_id, scope, template_item_id, data, created_at, updated_at) '
        "VALUES ('o1', 'f1', 'farm', 'item-climber', '{\"default_rate_paise\": 110000}', 0, 0)",
      );
      db.notifyUpdates({TableUpdate.onTable(db.templateOverrides)});
      expect(await values, [120000, 110000]);
      // a soft-deleted override (a reset) no longer applies
      await db.customStatement(
        'UPDATE template_overrides SET deleted_at = 1 WHERE id = ?',
        ['o1'],
      );
      db.notifyUpdates({TableUpdate.onTable(db.templateOverrides)});
      final last = await stream.first;
      expect(
        last.value('rate_class', 'climber', 'default_rate_paise', here)!.level,
        Level.app,
      );
    },
  );
}
