/// A standard crop the farmer can pick in set-up.
class CropChoice {
  const CropChoice(this.id, this.nameMl, this.nameEn);
  final String id;
  final String nameMl;
  final String nameEn;
}

/// What set-up collects (screens.md 17). Only [name] and [farmName] are
/// needed; everything else has a default and can be added later.
class SetupInput {
  const SetupInput({
    required this.name,
    required this.farmName,
    this.phone,
    this.area,
    required this.areaUnit,
    this.tenure = 'owned',
    this.cropIds = const [],
  });

  final String name;
  final String? phone;
  final String farmName;

  /// Thousandths of [areaUnit], or null when not given.
  final int? area;
  final String areaUnit;

  /// owned or leased.
  final String tenure;
  final List<String> cropIds;

  bool get ready => name.trim().isNotEmpty && farmName.trim().isNotEmpty;
}

/// The farm to open after the first sync: the one used last on this phone
/// while the account still belongs to it, else the first of [farms].
String? farmToOpen(List<String> farms, String? lastUsed) =>
    farms.contains(lastUsed) ? lastUsed : farms.firstOrNull;
