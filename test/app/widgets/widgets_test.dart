import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:thottam/app/widgets/widgets.dart';
import 'package:thottam/core/money/money_parse.dart';

import '../../helpers/host.dart';

void main() {
  group('buttons', () {
    testWidgets('primary button runs its action and can be disabled', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        host(
          (c, l) => PrimaryButton(label: l.actionSave, onPressed: () => taps++),
        ),
      );
      await tester.tap(find.byType(PrimaryButton));
      expect(taps, 1);

      await tester.pumpWidget(
        host((c, l) => PrimaryButton(label: l.actionSave, onPressed: null)),
      );
      await tester.tap(find.byType(PrimaryButton), warnIfMissed: false);
      expect(taps, 1);
    });

    testWidgets('primary button is at least 58 high and 48 wide', (
      tester,
    ) async {
      await tester.pumpWidget(
        host((c, l) => PrimaryButton(label: l.actionSave, onPressed: () {})),
      );
      final size = tester.getSize(find.byType(PrimaryButton));
      expect(size.height, greaterThanOrEqualTo(58));
      expect(size.width, greaterThanOrEqualTo(48));
    });
  });

  testWidgets('choice chip reports selection', (tester) async {
    bool? picked;
    await tester.pumpWidget(
      host(
        (c, l) => ChoiceChipX(
          label: l.paymentCash,
          selected: false,
          onSelected: (v) => picked = v,
        ),
      ),
    );
    await tester.tap(find.byType(ChoiceChipX));
    expect(picked, isTrue);
  });

  testWidgets('segmented control picks a segment', (tester) async {
    var index = 0;
    await tester.pumpWidget(
      host(
        (c, l) => SegmentedControl(
          labels: [l.labourModeNamed, l.labourModeGroup],
          selected: 0,
          onChanged: (i) => index = i,
        ),
      ),
    );
    await tester.tap(find.byType(SegmentedControlOption).last);
    expect(index, 1);
  });

  testWidgets('switch row toggles when the whole row is tapped', (
    tester,
  ) async {
    bool? value;
    await tester.pumpWidget(
      host(
        (c, l) => SwitchRow(
          title: l.settingsLargeText,
          subtitle: l.settingsLargeTextHint,
          value: false,
          onChanged: (v) => value = v,
        ),
      ),
    );
    await tester.tap(find.text('എളുപ്പ മോഡ്'));
    expect(value, isTrue);
    expect(
      tester.getSize(find.byType(SwitchRow)).height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('stepper adds and removes, never below its minimum', (
    tester,
  ) async {
    var value = 1;
    await tester.pumpWidget(
      host(
        (c, l) => StatefulBuilder(
          builder: (c, set) => CountStepper(
            value: value,
            min: 0,
            onChanged: (v) => set(() => value = v),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('കൂട്ടുക'));
    await tester.pump();
    expect(value, 2);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byTooltip('കുറയ്ക്കുക'), warnIfMissed: false);
      await tester.pump();
    }
    expect(value, 0);
  });

  testWidgets('toast shows the message and undo works', (tester) async {
    var undone = false;
    await tester.pumpWidget(
      host(
        (c, l) => TextButton(
          onPressed: () => showUndoToast(c, l.toastSaved, () => undone = true),
          child: Text(l.actionSave),
        ),
      ),
    );
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect(find.text('സേവ് ചെയ്തു'), findsOneWidget);
    await tester.tap(find.text('തിരിച്ചെടുക്കുക'));
    expect(undone, isTrue);
  });

  testWidgets('the undo toast goes by itself after about two seconds', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        (c, l) => TextButton(
          onPressed: () => showUndoToast(c, l.toastSaved, () {}),
          child: Text(l.actionSave),
        ),
      ),
    );
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect(find.text('സേവ് ചെയ്തു'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('സേവ് ചെയ്തു'), findsNothing);
  });

  testWidgets('bottom sheet opens with its content', (tester) async {
    await tester.pumpWidget(
      host(
        (c, l) => TextButton(
          onPressed: () =>
              showThottamSheet<void>(c, builder: (c) => Text(l.quickAddTitle)),
          child: Text(l.actionAdd),
        ),
      ),
    );
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect(find.text('എന്ത് ചേർക്കണം?'), findsOneWidget);
  });

  testWidgets('bottom nav reports tabs and the centre add button', (
    tester,
  ) async {
    var tab = -1;
    var added = false;
    await tester.pumpWidget(
      host(
        (c, l) => ThottamBottomNav(
          current: 0,
          onTab: (i) => tab = i,
          onAdd: () => added = true,
          tabs: [
            NavTab(Icons.home_outlined, l.navHome),
            NavTab(Icons.landscape_outlined, l.navLand),
            NavTab(Icons.payments_outlined, l.navMoney),
            NavTab(Icons.more_horiz, l.navMore),
          ],
          addLabel: l.actionAdd,
        ),
      ),
    );
    await tester.tap(find.text('കണക്ക്'));
    expect(tab, 2);
    await tester.tap(find.bySemanticsLabel('ചേർക്കുക'));
    expect(added, isTrue);
  });

  testWidgets('amount input opens the number keyboard and gives paise', (
    tester,
  ) async {
    int? paise;
    await tester.pumpWidget(
      host(
        (c, l) => AmountInput(
          label: l.fieldAmount,
          hint: l.amountInputHint,
          onChanged: (v) => paise = v,
        ),
      ),
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(
      field.keyboardType,
      const TextInputType.numberWithOptions(decimal: true),
    );
    expect(field.autofocus, isTrue);
    await tester.enterText(find.byType(TextField), '1234.5');
    expect(paise, 123450);
  });

  testWidgets('empty state offers its action', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      host(
        (c, l) => EmptyState(
          icon: Icons.landscape_outlined,
          title: l.landTitle,
          message: l.setupStepFarmHint,
          actionLabel: l.landAddPlot,
          onAction: () => tapped = true,
        ),
      ),
    );
    await tester.tap(find.text('പുതിയ പ്ലോട്ട് ചേർക്കുക'));
    expect(tapped, isTrue);
  });

  testWidgets('every tappable widget meets 48 dp and has a label', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      host((c, l) => const SingleChildScrollView(child: WidgetGallery())),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  group('rupee parsing', () {
    test('whole and decimal rupees', () {
      expect(parseRupeesToPaise('100'), 10000);
      expect(parseRupeesToPaise('1,234.5'), 123450);
      expect(parseRupeesToPaise('0.05'), 5);
    });
    test('empty or invalid gives null', () {
      expect(parseRupeesToPaise(''), isNull);
      expect(parseRupeesToPaise('1.234'), isNull);
      expect(parseRupeesToPaise('abc'), isNull);
    });
  });
}
