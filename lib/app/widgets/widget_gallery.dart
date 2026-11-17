import 'package:material_ui/material_ui.dart';

import '../../core/money/money_format.dart';
import '../../l10n/app_localizations.dart';
import '../theme/tokens.dart';
import 'bottom_nav.dart';
import 'buttons.dart';
import 'choices.dart';
import 'surfaces.dart';

/// Debug-only page that shows every shared widget for the owner to review.
class WidgetGalleryScreen extends StatelessWidget {
  const WidgetGalleryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.appName)),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: WidgetGallery(),
      ),
    );
  }
}

class WidgetGallery extends StatefulWidget {
  const WidgetGallery({super.key});

  @override
  State<WidgetGallery> createState() => _WidgetGalleryState();
}

class _WidgetGalleryState extends State<WidgetGallery> {
  int _segment = 0;
  int _count = 5;
  bool _switch = true;
  String _pay = 'cash';
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final gap = SizedBox(height: t.cardGap);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PrimaryButton(label: l10n.actionSave, onPressed: () {}),
        gap,
        PrimaryButton(label: l10n.actionSave, onPressed: null),
        gap,
        OutlineButton(label: l10n.actionChange, onPressed: () {}),
        gap,
        Wrap(
          spacing: 8,
          children: [
            for (final (key, label) in [
              ('cash', l10n.paymentCash),
              ('upi', l10n.paymentUpi),
              ('credit', l10n.paymentCredit),
            ])
              ChoiceChipX(
                label: label,
                selected: _pay == key,
                onSelected: (_) => setState(() => _pay = key),
              ),
          ],
        ),
        gap,
        SegmentedControl(
          labels: [l10n.labourModeNamed, l10n.labourModeGroup],
          selected: _segment,
          onChanged: (i) => setState(() => _segment = i),
        ),
        gap,
        SwitchRow(
          title: l10n.settingsLargeText,
          subtitle: l10n.settingsLargeTextHint,
          value: _switch,
          onChanged: (v) => setState(() => _switch = v),
        ),
        gap,
        Center(
          child: CountStepper(
            value: _count,
            min: 0,
            onChanged: (v) => setState(() => _count = v),
          ),
        ),
        gap,
        Row(
          children: [
            TintIconTile(
              icon: Icons.payments_outlined,
              background: t.expenseTint,
              foreground: t.onExpenseTint,
              label: l10n.quickAddExpense,
              onTap: () {},
            ),
            SizedBox(width: t.cardGap),
            TintIconTile(
              icon: Icons.agriculture_outlined,
              background: t.primaryTint,
              foreground: t.primaryDark,
              label: l10n.quickAddHarvest,
              onTap: () {},
            ),
          ],
        ),
        gap,
        ThottamCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.homeSeasonProfit,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                formatPaise(8830000),
                style: Theme.of(context).textTheme.displayLarge,
              ),
            ],
          ),
        ),
        gap,
        AmountInput(
          label: l10n.fieldAmount,
          hint: l10n.amountInputHint,
          autofocus: false,
          onChanged: (_) {},
        ),
        gap,
        LastTimeBanner(text: l10n.harvestLastTime('110', 6, l10n.dayYesterday)),
        gap,
        Align(
          alignment: Alignment.centerLeft,
          child: StaleDataTag(label: l10n.staleDataTag(l10n.dayYesterday)),
        ),
        gap,
        EmptyState(
          icon: Icons.landscape_outlined,
          title: l10n.landTitle,
          message: l10n.setupStepFarmHint,
          actionLabel: l10n.landAddPlot,
          onAction: () {},
        ),
        gap,
        OutlineButton(
          label: l10n.actionSave,
          onPressed: () => showUndoToast(context, l10n.toastSaved, () {}),
        ),
        gap,
        OutlineButton(
          label: l10n.quickAddTitle,
          onPressed: () => showThottamSheet<void>(
            context,
            builder: (c) => Text(l10n.quickAddTitle),
          ),
        ),
        gap,
        ThottamBottomNav(
          tabs: [
            NavTab(Icons.home_outlined, l10n.navHome),
            NavTab(Icons.landscape_outlined, l10n.navLand),
            NavTab(Icons.account_balance_wallet_outlined, l10n.navMoney),
            NavTab(Icons.more_horiz, l10n.navMore),
          ],
          current: _tab,
          onTab: (i) => setState(() => _tab = i),
          onAdd: () {},
          addLabel: l10n.actionAdd,
        ),
      ],
    );
  }
}
