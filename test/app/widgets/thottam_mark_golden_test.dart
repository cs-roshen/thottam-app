@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:thottam/app/theme/tokens.dart';
import 'package:thottam/app/widgets/widgets.dart';

import '../../helpers/host.dart';

void main() {
  // Compare with design/logo/thottam-logo.svg: the same palm and sun on the
  // primary background, at the welcome screen's size and at 48.
  testWidgets('mark matches the master logo', (tester) async {
    await tester.pumpWidget(
      host(
        (context, l10n) => RepaintBoundary(
          child: ColoredBox(
            color: context.tokens.primary,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ThottamMark(),
                  SizedBox(width: 16),
                  ThottamMark(size: 48),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(RepaintBoundary).last,
      matchesGoldenFile('goldens/thottam_mark.png'),
    );
  });
}
