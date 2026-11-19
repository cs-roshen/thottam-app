@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:thottam/core/prefs/device_store.dart';
import 'package:thottam/core/sync/sync_server.dart';

import '../../core/sync/fake_server.dart';
import '../../helpers/screen_golden.dart';
import '../../helpers/session.dart';

void main() {
  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await settle(tester);
  }

  Future<void> toSetup(WidgetTester tester) async {
    await tap(tester, 'welcome.continue');
    await tap(tester, 'signIn.test');
  }

  final screens = <String, Future<void> Function(WidgetTester)>{
    'welcome': (tester) async {},
    'sign_in': (tester) => tap(tester, 'welcome.continue'),
    'setup_name': (tester) async {
      await toSetup(tester);
      await tap(tester, 'setup.next'); // the missing-name error
    },
    'setup_farm': (tester) async {
      await toSetup(tester);
      await tester.enterText(find.byKey(const Key('setup.name')), 'Ravi');
      await tap(tester, 'setup.next');
    },
    'setup_crops': (tester) async {
      await toSetup(tester);
      await tester.enterText(find.byKey(const Key('setup.name')), 'Ravi');
      await tap(tester, 'setup.next');
      await tester.enterText(find.byKey(const Key('setup.farmName')), 'Farm');
      await tap(tester, 'setup.next');
      await tap(tester, 'setup.crop.Pepper');
    },
  };

  for (final MapEntry(key: variant, value: prefs) in goldenVariants.entries) {
    for (final MapEntry(key: name, value: go) in screens.entries) {
      testWidgets('$name $variant', (tester) async {
        await expectScreenGolden(
          tester,
          name,
          variant,
          appOverrides(store: MemoryDeviceStore({...prefs})),
          go,
        );
      });
    }

    testWidgets('invites $variant', (tester) async {
      final server = FakeServer();
      server.invites['user-new'] = [
        const Invite(
          id: 'inv-1',
          farmId: 'farm-hill',
          farmName: 'Hill farm',
          role: 'manager',
          invitedBy: 'Mary',
        ),
      ];
      await expectScreenGolden(
        tester,
        'invites',
        variant,
        appOverrides(
          store: MemoryDeviceStore({
            ...prefs,
            'auth.test_account_id': 'user-new',
          }),
          server: (user) => server.as(user),
        ),
        toSetup,
      );
    });
  }
}
