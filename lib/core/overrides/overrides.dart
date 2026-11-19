/// The override model (product spec rule 3): app default → farm → plot →
/// crop cycle → single entry; the most specific level wins. Pure Dart: the
/// templates and overrides are loaded once and resolved from memory.
library;

/// Where a value came from, so a screen can mark it "overridden" and offer
/// a reset.
enum Level { app, farm, plot, cropCycle, entry }

/// A `template_items` row.
class TemplateItem {
  const TemplateItem({
    required this.id,
    required this.listType,
    required this.code,
    required this.nameMl,
    required this.nameEn,
    this.cropId,
    this.data = const {},
    this.sortOrder = 0,
    this.isActive = true,
    this.templateVersion = 1,
  });

  final String id;
  final String? cropId;
  final String listType;
  final String code;
  final String nameMl;
  final String nameEn;
  final Map<String, Object?> data;
  final int sortOrder;
  final bool isActive;
  final int templateVersion;
}

/// A `template_overrides` row: a change to a template item at one level, or
/// the farmer's own item when [templateItemId] is null.
class TemplateOverride {
  const TemplateOverride({
    required this.id,
    required this.scope,
    this.scopeId,
    this.templateItemId,
    this.cropId,
    this.listType,
    this.code,
    this.nameMl,
    this.nameEn,
    this.data = const {},
    this.hidden,
    this.updatedAt = 0,
  });

  final String id;

  /// [Level.farm], [Level.plot] or [Level.cropCycle].
  final Level scope;

  /// The plot or crop cycle id when [scope] is not the farm.
  final String? scopeId;
  final String? templateItemId;
  final String? cropId;
  final String? listType;
  final String? code;
  final String? nameMl;
  final String? nameEn;
  final Map<String, Object?> data;

  /// True hides the item at this level, false shows it again, null leaves it.
  final bool? hidden;

  /// Milliseconds; breaks ties between two rows at one level (two phones
  /// each setting the farm rate offline), so every phone shows the same one.
  final int updatedAt;
}

/// Where a value is being used.
class Scope {
  const Scope({this.cropId, this.plotId, this.cropCycleId});
  final String? cropId;
  final String? plotId;
  final String? cropCycleId;
}

/// A resolved value, its level, and the override row that set it (null for
/// the app default and for an entry's own value); a reset edits that row.
class Resolved<T> {
  const Resolved(this.value, this.level, [this.overrideId]);
  final T value;
  final Level level;
  final String? overrideId;

  @override
  String toString() => '$value $level $overrideId'; // gate: not user-facing
}

/// An item of a list as the farmer sees it in [Scope].
class ListItem {
  const ListItem({
    required this.code,
    required this.nameMl,
    required this.nameEn,
    required this.data,
    required this.sortOrder,
    required this.hidden,
    required this.isOwn,
    required this.updateAvailable,
    this.retired = false,
  });

  final String code;
  final Resolved<String> nameMl;
  final Resolved<String> nameEn;

  /// Every data field, each from its most specific level.
  final Map<String, Resolved<Object?>> data;
  final int sortOrder;
  final bool hidden;

  /// The farmer's own item, not from the templates.
  final bool isOwn;

  /// The farmer changed this item and the templates changed it after the
  /// farm last accepted an update.
  final bool updateAvailable;

  /// The template item is switched off; it is left out of lists.
  final bool retired;
}

class Overrides {
  Overrides({
    required Iterable<TemplateItem> items,
    required Iterable<TemplateOverride> overrides,
    this.acceptedVersion = 0,
  }) : _items = items.toList(),
       _overrides = overrides.toList();

  final List<TemplateItem> _items;
  final List<TemplateOverride> _overrides;

  /// `farms.accepted_template_version`.
  final int acceptedVersion;

  /// The newest template version on the phone; above [acceptedVersion],
  /// My lists says new items are available.
  int get latestVersion =>
      _items.fold(0, (m, i) => i.templateVersion > m ? i.templateVersion : m);

  /// The value of data [field] of item [listType]/[code] in [scope], or null
  /// when no level sets it. A non-null [entryValue] (the value typed on the
  /// entry itself) wins over every other level.
  Resolved<Object?>? value(
    String listType,
    String code,
    String field,
    Scope scope, {
    Object? entryValue,
  }) {
    if (entryValue != null) return Resolved(entryValue, Level.entry);
    final item = _item(listType, code, scope.cropId);
    Resolved<Object?>? best;
    if (item != null && item.data.containsKey(field)) {
      best = Resolved(item.data[field], Level.app);
    }
    for (final o in _layers(item, listType, code, scope)) {
      if (o.data.containsKey(field)) {
        best = Resolved(o.data[field], o.scope, o.id);
      }
    }
    return best;
  }

  /// The items of [listType] in [scope], template items and the farmer's
  /// own, in sort order. Hidden items are included and marked, so My lists
  /// can switch them back on; entry screens skip them.
  List<ListItem> list(String listType, Scope scope) {
    final codes = <String>{
      for (final i in _items)
        if (i.isActive &&
            i.listType == listType &&
            (i.cropId == null || i.cropId == scope.cropId))
          i.code,
      for (final o in _overrides)
        if (o.templateItemId == null &&
            o.listType == listType &&
            (o.cropId == null || o.cropId == scope.cropId) &&
            _applies(o, scope))
          ?o.code,
    };
    final out = [
      for (final c in codes)
        if (_listItem(listType, c, scope) case final item?
            when !(item.retired && !item.isOwn))
          item,
    ];
    out.sort((a, b) {
      final s = a.sortOrder.compareTo(b.sortOrder);
      return s != 0 ? s : a.code.compareTo(b.code);
    });
    return out;
  }

  ListItem? _listItem(String listType, String code, Scope scope) {
    final item = _item(listType, code, scope.cropId);
    final layers = _layers(item, listType, code, scope).toList();
    if (item == null && layers.isEmpty) return null;

    Resolved<String>? nameMl = item == null
        ? null
        : Resolved(item.nameMl, Level.app);
    Resolved<String>? nameEn = item == null
        ? null
        : Resolved(item.nameEn, Level.app);
    final data = <String, Resolved<Object?>>{
      for (final MapEntry(:key, :value) in (item?.data ?? const {}).entries)
        key: Resolved(value, Level.app),
    };
    var hidden = false;
    for (final o in layers) {
      if (o.nameMl case final ml?) nameMl = Resolved(ml, o.scope, o.id);
      if (o.nameEn case final en?) nameEn = Resolved(en, o.scope, o.id);
      for (final MapEntry(:key, :value) in o.data.entries) {
        data[key] = Resolved(value, o.scope, o.id);
      }
      if (o.hidden case final h?) hidden = h;
    }
    // a farmer's own item may have a name in one language only
    nameMl ??= nameEn;
    nameEn ??= nameMl;
    if (nameMl == null || nameEn == null) return null;
    return ListItem(
      code: code,
      nameMl: nameMl,
      nameEn: nameEn,
      data: data,
      sortOrder: item?.sortOrder ?? 1 << 30,
      hidden: hidden,
      isOwn: item == null,
      retired: item != null && !item.isActive,
      // only an item the farmer changed needs a choice; untouched items
      // follow the templates by themselves. Set-up (C1) stores the template
      // version a new farm starts from in farms.accepted_template_version.
      updateAvailable:
          item != null &&
          layers.isNotEmpty &&
          item.templateVersion > acceptedVersion,
    );
  }

  /// The crop's own item if there is one, else the item for all crops.
  TemplateItem? _item(String listType, String code, String? cropId) {
    TemplateItem? general;
    for (final i in _items) {
      if (i.listType != listType || i.code != code) continue;
      if (cropId != null && i.cropId == cropId) return i;
      if (i.cropId == null) general = i;
    }
    return general;
  }

  /// The overrides that apply to an item in [scope], least specific first.
  /// A row tied to the all-crops item still applies after the admin adds a
  /// crop's own item with the same code, so the farmer's change survives.
  Iterable<TemplateOverride> _layers(
    TemplateItem? item,
    String listType,
    String code,
    Scope scope,
  ) {
    final sameItem = {
      for (final i in _items)
        if (i.listType == listType &&
            i.code == code &&
            (i.cropId == null || i.cropId == scope.cropId))
          i.id: i.cropId == null ? 0 : 1,
    };
    int specific(TemplateOverride o) =>
        o.templateItemId == null ? 2 : sameItem[o.templateItemId]!;
    final matching = _overrides.where((o) {
      if (!_applies(o, scope)) return false;
      if (o.cropId != null && o.cropId != scope.cropId) return false;
      if (o.templateItemId != null) {
        return sameItem.containsKey(o.templateItemId);
      }
      return o.listType == listType && o.code == code;
    }).toList();
    matching.sort((a, b) {
      final level = a.scope.index.compareTo(b.scope.index);
      if (level != 0) return level;
      final s = specific(a).compareTo(specific(b));
      if (s != 0) return s;
      final t = a.updatedAt.compareTo(b.updatedAt);
      return t != 0 ? t : a.id.compareTo(b.id);
    });
    return matching;
  }

  bool _applies(TemplateOverride o, Scope scope) => switch (o.scope) {
    Level.farm => true,
    Level.plot => o.scopeId != null && o.scopeId == scope.plotId,
    Level.cropCycle => o.scopeId != null && o.scopeId == scope.cropCycleId,
    Level.app || Level.entry => false,
  };
}
