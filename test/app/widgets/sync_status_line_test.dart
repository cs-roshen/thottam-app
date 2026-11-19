import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thottam/app/widgets/widgets.dart';
import 'package:thottam/core/sync/sync_status.dart';

import '../../helpers/host.dart';

void main() {
  testWidgets('before the first sync, in Malayalam', (tester) async {
    await tester.pumpWidget(
      host(
        (_, _) => const SyncStatusLine(
          status: SyncStatus(waiting: 3, rejected: 0, conflicts: 0),
        ),
      ),
    );
    expect(find.text('ഇതുവരെ സിങ്ക് ചെയ്തിട്ടില്ല'), findsOneWidget);
    expect(find.text('3 മാറ്റങ്ങൾ സിങ്ക് ചെയ്യാനുണ്ട്'), findsOneWidget);
  });

  testWidgets('after a sync, with refusals and choices waiting, large text', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        (_, _) => SyncStatusLine(
          status: SyncStatus(
            waiting: 0,
            rejected: 1,
            conflicts: 2,
            lastSyncedAt: DateTime(2026, 11, 18, 9, 5),
          ),
        ),
        locale: const Locale('en'),
        textScale: 1.12,
      ),
    );
    expect(find.text('Last synced 18 Nov, 9:05 AM'), findsOneWidget);
    // never "everything is synced" while choices or refusals wait
    expect(find.text('Everything is synced'), findsNothing);
    expect(find.text('2 changes need your choice'), findsOneWidget);
    expect(find.text('1 change the server refused'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
