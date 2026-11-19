import 'package:flutter_test/flutter_test.dart';

import '../../tool/check.dart';

void main() {
  test('user-facing text is caught; codes, paths and symbols are not', () {
    expect(userFacing('Save'), isTrue);
    expect(userFacing('സേവ്'), isTrue);
    expect(userFacing('Hello, \$name'), isTrue);
    expect(userFacing('cash'), isFalse);
    expect(userFacing('more.gallery'), isFalse);
    expect(userFacing(r'\n'), isFalse);
    expect(userFacing(r'Line one\nline two'), isTrue);
    expect(userFacing('/more/gallery'), isFalse);
    expect(userFacing('₹ '), isFalse);
    expect(userFacing('\$sign₹\$grouped'), isFalse);
  });

  test('route paths with parameters and query keys are not text', () {
    for (final path in [
      '/land/:plot',
      'crop/new',
      'crop/:cycle',
      '/history?plot=',
      '/land//edit', // '/land/${id}/edit' once the id is taken out
    ]) {
      expect(userFacing(path), isFalse, reason: path);
    }
    expect(userFacing('Plot name'), isTrue);
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

  test('SQL in the data layer and generated code pass the string check', () {
    const sql =
        "db.customStatement('UPDATE plots SET name = ? WHERE id = ?');\n";
    expect(checkFile('lib/core/history/write_with_history.dart', sql), isEmpty);
    expect(
      checkFile('lib/core/db/database.g.dart', "Text('NOT NULL');\n"),
      isEmpty,
    );
    expect(
      checkFile('lib/features/plots/ui/plot_screen.dart', sql),
      isNotEmpty,
    );
    // a feature's repository holds SQL, never text a farmer sees
    const query = "db.customSelect('SELECT name FROM plots WHERE id = ?');\n";
    expect(checkFile('lib/features/land/data/plots.dart', query), isEmpty);
    expect(checkFile('lib/features/land/ui/plots.dart', query), isNotEmpty);
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

  test('every kind of Drift write is caught, in data/ and elsewhere', () {
    for (final (path, line) in const [
      (
        'lib/features/land/data/plot_repository.dart',
        "db.customUpdate('UPDATE plots');",
      ),
      ('lib/features/land/data/plot_repository.dart', 'db.batch((b) {});'),
      ('lib/core/overrides/overrides.dart', 'db.into(db.plots).insert(row);'),
      (
        'lib/features/land/ui/plot_screen.dart',
        "db.customStatement('DELETE');",
      ),
    ]) {
      expect(
        checkFile(path, '$line\n').where((p) => p.contains('write outside')),
        hasLength(1),
        reason: path,
      );
    }
    expect(
      checkFile(
        'lib/core/dev/load_seed.dart',
        "b.customStatement('INSERT');\n",
      ),
      isEmpty,
    );
    expect(
      checkFile(
        'lib/core/money/money_format.dart',
        'groups.insert(0, head);\n',
      ),
      isEmpty,
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
