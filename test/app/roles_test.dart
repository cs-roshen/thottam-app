import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:thottam/app/app.dart';
import 'package:thottam/app/widgets/widgets.dart';

import '../helpers/screen_golden.dart';
import '../helpers/session.dart';

/// D3: the role defaults of product spec rule 7, and per-person permissions,
/// as the app shows them: the Money tab, and what the add button offers.
/// Screens hide what a role cannot open (docs/screens.md, top).
void main() {
  const all = ['expense', 'labour', 'harvest', 'sale', 'note'];

  for (final (role, permissions, money, tiles) in [
    ('owner', '{}', true, all),
    ('manager', '{}', true, all),
    // records daily work; cannot open money
    ('supervisor', '{}', false, ['labour', 'harvest', 'note']),
    // reads everything; writes money, not daily work
    ('accountant', '{}', true, ['expense', 'sale']),
    // reads everything; writes nothing, so there is nothing to add
    ('viewer', '{}', true, <String>[]),
    // the owner lets a supervisor read money: the tab, still no bills
    ('supervisor', '{"money": "read"}', true, ['labour', 'harvest', 'note']),
    // and lets an accountant record daily work too
    ('accountant', '{"daily": "write"}', true, all),
    // and takes money away from a manager
    ('manager', '{"money": "none"}', false, ['labour', 'harvest', 'note']),
  ]) {
    testWidgets('$role $permissions: money tab $money, adds $tiles', (
      tester,
    ) async {
      final (db, farm) = await farmDatabase(crops: const ['Pepper']);
      await db.customStatement(
        'UPDATE farm_members SET role = ?, permissions = ? WHERE user_id = ?',
        [role, permissions, testUser],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: farmOverrides(db, farm),
          child: const ThottamApp(),
        ),
      );
      await settle(tester);
      final nav = tester.widget<ThottamBottomNav>(
        find.byKey(const Key('shell.nav')),
      );
      expect(nav.tabs, hasLength(money ? 4 : 3));
      final add = find.bySemanticsLabel('Add');
      if (tiles.isEmpty) {
        expect(add, findsNothing);
        return;
      }
      await tester.tap(add);
      await settle(tester);
      for (final t in all) {
        expect(
          find.byKey(Key('quickAdd./add/$t')),
          tiles.contains(t) ? findsOneWidget : findsNothing,
          reason: t,
        );
      }
    });
  }
}
