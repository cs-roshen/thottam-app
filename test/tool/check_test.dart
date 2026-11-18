import 'package:flutter_test/flutter_test.dart';

import '../../tool/check.dart';

void main() {
  test('user-facing text is caught; codes, paths and symbols are not', () {
    expect(userFacing('Save'), isTrue);
    expect(userFacing('സേവ്'), isTrue);
    expect(userFacing('Hello, \$name'), isTrue);
    expect(userFacing('cash'), isFalse);
    expect(userFacing('more.gallery'), isFalse);
    expect(userFacing('/more/gallery'), isFalse);
    expect(userFacing('₹ '), isFalse);
    expect(userFacing('\$sign₹\$grouped'), isFalse);
  });

  test('flags text, colours and fonts in a screen file', () {
    final problems = checkFile(
      'lib/features/expenses/ui/expense_screen.dart',
      "Text('Save');\nColor(0xFF000000);\nfontFamily: 'Inter';\n",
    );
    for (final kind in ['user-facing text', 'colour literal', 'font name']) {
      expect(problems.where((p) => p.contains(kind)), isNotEmpty, reason: kind);
    }
  });

  test('allows colours and fonts in the theme', () {
    expect(
      checkFile(
        'lib/app/theme/tokens.dart',
        "Color(0xFF000000);\nfontFamily: 'Inter';\n",
      ),
      isEmpty,
    );
  });

  test('keeps domain pure and Supabase in sync and auth', () {
    expect(
      checkFile(
        'lib/features/labour/domain/wages.dart',
        "import 'package:flutter/foundation.dart';\n",
      ),
      hasLength(1),
    );
    expect(
      checkFile(
        'lib/features/labour/data/repo.dart',
        "import 'package:supabase_flutter/supabase_flutter.dart';\n",
      ),
      hasLength(1),
    );
    expect(
      checkFile(
        'lib/core/sync/engine.dart',
        "import 'package:supabase_flutter/supabase_flutter.dart';\n",
      ),
      isEmpty,
    );
  });

  test('repository writes must go through writeWithHistory', () {
    expect(
      checkFile(
        'lib/features/expenses/data/expense_repository.dart',
        'await db.into(db.expenses).insert(row);\n',
      ),
      hasLength(1),
    );
  });

  test('the marker skips a line on purpose', () {
    expect(
      checkFile(
        'lib/app/date_format.dart',
        "DateFormat('EEEE, d MMMM'); // gate: not user-facing\n",
      ),
      isEmpty,
    );
  });
}
