import '../../../app/settings.dart';
import '../../../core/money/money_format.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/land.dart';

/// Words for land values, shared by the land screens.
extension LandLabels on AppLocalizations {
  String tenure(String code) => switch (code) {
    'leased' => tenureLeased,
    'shared' => tenureShared,
    _ => tenureOwned,
  };

  String area(int thousandths, String unit) =>
      quantityWithUnit(formatQuantity(thousandths), unit);

  /// "2.5 acre · Owned", or the tenure alone when no area was given.
  String plotLine(PlotView p) => p.area == null
      ? tenure(p.tenure)
      : nameWithDetail(area(p.area!, p.areaUnit), tenure(p.tenure));

  String cropName(AppSettings s, CycleView c) =>
      localName(s, c.nameMl, c.nameEn, nameMixed);

  /// The crop with its plants or season, as on the land list chips.
  String cycleChip(AppSettings s, CycleView c) {
    final name = cropName(s, c);
    if (c.plantCount != null) {
      return nameWithDetail(name, cyclePlants(c.plantCount!));
    }
    if (c.season != null) return nameWithDetail(name, c.season!);
    return name;
  }

  /// Everything known about a crop cycle besides its name.
  String cycleDetails(CycleView c) => [
    ?c.variety,
    if (c.plantCount != null) cyclePlants(c.plantCount!),
    if (c.areaShare != null) cycleShare(formatQuantity(c.areaShare!)),
    ?c.season,
    if (c.plantedOn != null) cyclePlanted(c.plantedOn!.substring(0, 4)),
  ].join(' · ');

  /// "120 kg + 30 bunch".
  String yields(Map<String, int> byUnit) => [
    for (final MapEntry(:key, :value) in byUnit.entries)
      quantityWithUnit(formatQuantity(value), key),
  ].join(' + ');
}
