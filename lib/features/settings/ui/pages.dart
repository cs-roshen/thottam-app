import 'package:material_ui/material_ui.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/access/access.dart';
import '../../../l10n/app_localizations.dart';

/// A page the farmer can switch off in Settings (screen 7): it then leaves
/// More and quick add. Phase 1 pages only; later phases add theirs here.
class AppPage {
  const AppPage(
    this.code,
    this.icon,
    this.path,
    this.label,
    this.colours, {
    this.needs = AccessClass.setup,
  });

  final String code;
  final IconData icon;
  final String path;
  final String Function(AppLocalizations) label;
  final (Color, Color) Function(ThottamTokens) colours;

  /// What the role must be able to read for the page to show.
  final AccessClass needs;
}

final appPages = <AppPage>[
  AppPage(
    'labour',
    Icons.groups_outlined,
    '/labour/team',
    (l) => l.pageLabour,
    (t) => (t.infoTint, t.onInfoTint),
  ),
  AppPage(
    'harvest',
    Icons.agriculture_outlined,
    '/add/harvest',
    (l) => l.harvestTitle,
    (t) => (t.primaryTint, t.primaryDark),
    needs: AccessClass.daily,
  ),
  AppPage(
    'sell',
    Icons.sell_outlined,
    '/sales/buyers',
    (l) => l.pageSelling,
    (t) => (t.accentTint, t.onAccentTint),
    needs: AccessClass.money,
  ),
  AppPage(
    'prices',
    Icons.show_chart,
    '/prices',
    (l) => l.pricesTitle,
    (t) => (t.accentTint, t.onAccentTint),
    needs: AccessClass.prices,
  ),
  AppPage(
    'history',
    Icons.history,
    '/history',
    (l) => l.historyTitle,
    (t) => (t.lineSoft, t.ink),
  ),
  AppPage(
    'lists',
    Icons.checklist,
    '/more/lists',
    (l) => l.myListsTitle,
    (t) => (t.infoTint, t.onInfoTint),
  ),
];
