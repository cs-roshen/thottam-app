@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:thottam/app/theme/tokens.dart';
import 'package:thottam/app/widgets/widgets.dart';
import 'package:thottam/l10n/app_localizations.dart';

import '../../helpers/host.dart';

typedef Build = Widget Function(BuildContext c, AppLocalizations l, bool long);

/// Each widget's longest realistic Malayalam label is
/// harvestPerTeamQuantity, the longest string in the app.
String pick(AppLocalizations l, bool long, String normal) =>
    long ? l.harvestPerTeamQuantity : normal;

final Map<String, Build> widgets = {
  'primary_button': (c, l, long) =>
      PrimaryButton(label: pick(l, long, l.actionSave), onPressed: () {}),
  'outline_button': (c, l, long) =>
      OutlineButton(label: pick(l, long, l.actionChange), onPressed: () {}),
  'choice_chip': (c, l, long) => Wrap(
    spacing: 8,
    children: [
      // Chips are one line by design; their longest realistic label is a
      // short choice such as a history filter, not a sentence.
      ChoiceChipX(
        label: long ? l.historyFilterHarvest : l.paymentCash,
        selected: true,
        onSelected: (_) {},
      ),
      ChoiceChipX(label: l.paymentUpi, selected: false, onSelected: (_) {}),
    ],
  ),
  'segmented_control': (c, l, long) => SegmentedControl(
    labels: [pick(l, long, l.labourModeNamed), l.labourModeGroup],
    selected: 0,
    onChanged: (_) {},
  ),
  'switch_row': (c, l, long) => SwitchRow(
    title: pick(l, long, l.settingsLargeText),
    subtitle: l.settingsLargeTextHint,
    value: true,
    onChanged: (_) {},
  ),
  'stepper': (c, l, long) =>
      CountStepper(value: long ? 120 : 5, onChanged: (_) {}),
  'tint_icon_tile': (c, l, long) {
    final t = c.tokens;
    return TintIconTile(
      icon: Icons.payments_outlined,
      background: t.expenseTint,
      foreground: t.onExpenseTint,
      label: l.quickAddExpense,
      onTap: () {},
    );
  },
  'card': (c, l, long) => ThottamCard(
    child: Text(
      pick(l, long, l.homeSeasonProfit),
      style: Theme.of(c).textTheme.titleMedium,
    ),
  ),
  'amount_input': (c, l, long) => AmountInput(
    label: pick(l, long, l.fieldAmount),
    hint: l.amountInputHint,
    autofocus: false,
    onChanged: (_) {},
  ),
  'empty_state': (c, l, long) => EmptyState(
    icon: Icons.landscape_outlined,
    title: pick(l, long, l.landTitle),
    message: l.setupStepFarmHint,
    actionLabel: l.landAddPlot,
    onAction: () {},
  ),
  'last_time_banner': (c, l, long) => LastTimeBanner(
    text: long
        ? l.harvestPerTeamQuantity
        : l.harvestLastTime('110', 6, l.dayYesterday),
  ),
  'stale_data_tag': (c, l, long) => StaleDataTag(
    label: l.staleDataTag(long ? l.harvestPerTeamQuantity : l.dayYesterday),
  ),
  'bottom_nav': (c, l, long) => ThottamBottomNav(
    tabs: [
      NavTab(Icons.home_outlined, l.navHome),
      NavTab(Icons.landscape_outlined, pick(l, long, l.navLand)),
      NavTab(Icons.account_balance_wallet_outlined, l.navMoney),
      NavTab(Icons.more_horiz, l.navMore),
    ],
    current: 0,
    onTab: (_) {},
    onAdd: () {},
    addLabel: l.actionAdd,
  ),
  'toast': (c, l, long) => TextButton(
    onPressed: () => showUndoToast(c, pick(l, long, l.toastSaved), () {}),
    child: Text(l.actionSave),
  ),
  'bottom_sheet': (c, l, long) => TextButton(
    onPressed: () => showThottamSheet<void>(
      c,
      builder: (c) => Text(pick(l, long, l.quickAddTitle)),
    ),
    child: Text(l.actionAdd),
  ),
};

const variants = {
  'ml': (Locale('ml'), 1.0, false),
  'en': (Locale('en'), 1.0, false),
  'ml_large': (Locale('ml'), 1.12, false),
  'ml_long': (Locale('ml'), 1.0, true),
};

void main() {
  setUpAll(loadAppFonts);

  for (final MapEntry(key: name, value: build) in widgets.entries) {
    for (final MapEntry(key: variant, value: (locale, scale, long))
        in variants.entries) {
      testWidgets('$name $variant', (tester) async {
        tester.view
          ..physicalSize = const Size(400, 400)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        // Draw real shadows instead of the test framework's black outlines.
        debugDisableShadows = false;
        addTearDown(() => debugDisableShadows = true);
        await tester.pumpWidget(
          host((c, l) => build(c, l, long), locale: locale, textScale: scale),
        );
        if (name == 'toast' || name == 'bottom_sheet') {
          await tester.tap(find.byType(TextButton));
        }
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/$name.$variant.png'),
        );
      });
    }
  }
}
