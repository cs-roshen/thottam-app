import 'dart:convert';

import 'package:drift/drift.dart';

import 'database.dart';
import '../overrides/overrides.dart';

/// A farm's templates and overrides, loaded into memory and loaded again
/// whenever either table changes, so screens resolve values without a query
/// per field.
Stream<Overrides> watchOverrides(AppDatabase db, String farmId) {
  final query = db.customSelect(
    'SELECT '
    '(SELECT json_group_array(json_object('
    "'id', id, 'crop_id', crop_id, 'list_type', list_type, 'code', code, "
    "'name_ml', name_ml, 'name_en', name_en, 'data', json(data), "
    "'sort_order', sort_order, 'is_active', is_active, "
    "'template_version', template_version)) FROM template_items) AS items, "
    '(SELECT json_group_array(json_object('
    "'id', id, 'scope', scope, 'scope_id', scope_id, "
    "'template_item_id', template_item_id, 'crop_id', crop_id, "
    "'list_type', list_type, 'code', code, 'name_ml', name_ml, "
    "'name_en', name_en, 'data', json(data), 'hidden', hidden)) "
    'FROM template_overrides WHERE farm_id = ?1 AND deleted_at IS NULL) '
    'AS overrides, '
    '(SELECT accepted_template_version FROM farms WHERE id = ?1) AS accepted',
    variables: [Variable.withString(farmId)],
    readsFrom: {db.templateItems, db.templateOverrides, db.farms},
  );
  return query.watchSingle().map((row) {
    List<Map<String, Object?>> list(String col) => [
      for (final e in jsonDecode(row.read<String>(col)) as List)
        (e as Map).cast<String, Object?>(),
    ];
    return Overrides(
      items: [for (final r in list('items')) _item(r)],
      overrides: [for (final r in list('overrides')) _override(r)],
      acceptedVersion: row.readNullable<int>('accepted') ?? 0,
    );
  });
}

TemplateItem _item(Map<String, Object?> r) => TemplateItem(
  id: r['id']! as String,
  cropId: r['crop_id'] as String?,
  listType: r['list_type']! as String,
  code: r['code']! as String,
  nameMl: r['name_ml']! as String,
  nameEn: r['name_en']! as String,
  data: (r['data'] as Map?)?.cast<String, Object?>() ?? const {},
  sortOrder: r['sort_order']! as int,
  isActive: r['is_active'] == 1,
  templateVersion: r['template_version']! as int,
);

TemplateOverride _override(Map<String, Object?> r) => TemplateOverride(
  id: r['id']! as String,
  scope: switch (r['scope']) {
    'plot' => Level.plot,
    'crop_cycle' => Level.cropCycle,
    _ => Level.farm,
  },
  scopeId: r['scope_id'] as String?,
  templateItemId: r['template_item_id'] as String?,
  cropId: r['crop_id'] as String?,
  listType: r['list_type'] as String?,
  code: r['code'] as String?,
  nameMl: r['name_ml'] as String?,
  nameEn: r['name_en'] as String?,
  data: (r['data'] as Map?)?.cast<String, Object?>() ?? const {},
  hidden: r['hidden'] == 1,
);
