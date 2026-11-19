// Source gates from implementation plan section 16 that the analyzer and
// tests do not cover. Run: dart run tool/check.dart
//
// A line ending in `// gate: not user-facing`, or the line right after that
// comment on its own, is skipped by the string check.
import 'dart:io';

// Raw strings (r'...') are regular expressions or paths, never UI text.
final _literal = RegExp(
  r"(?<![r\w])'((?:[^'\\]|\\.)*)'"
  '|'
  r'(?<![r\w])"((?:[^"\\]|\\.)*)"',
);
const _marker = '// gate: not user-facing';
final _interpolation = RegExp(r'\$\{[^}]*\}|\$\w+');
final _identifier = RegExp(r'^[a-z][a-zA-Z0-9_.]*$');
final _path = RegExp(r'^/[a-z0-9_/]*$');
final _letter = RegExp(r'\p{L}', unicode: true);
final _colour = RegExp(r'\bColor\(0x|\bColors\.(?!transparent\b)\w+');
final _fontName = RegExp(
  r"""['"](AnekMalayalam|Inter|NotoSansMalayalam)['"]""",
);
final _driftWrite = RegExp(
  r'\.(into|update|delete|insert|insertAll|insertOnConflictUpdate|'
  r'insertReturning|replace|deleteWhere|batch)\(|custom(Statement|Insert|Update)\(',
);
// Calls only Drift has, so they are looked for in every file, not only data/.
final _driftOnlyWrite = RegExp(
  r'\.(into|batch|deleteWhere|insertOnConflictUpdate|insertReturning)\(|'
  r'custom(Statement|Insert|Update)\(',
);

/// Strips comments, keeping line numbers.
String _code(String line) {
  final i = line.indexOf('//');
  if (i < 0) return line;
  // A '//' inside a string literal is rare in this codebase; keep it simple.
  return line.substring(0, i);
}

/// True when a literal reads like text a farmer would see.
bool userFacing(String literal) {
  final text = literal.replaceAll(_interpolation, '');
  if (!_letter.hasMatch(text)) return false;
  return !_identifier.hasMatch(text) && !_path.hasMatch(text);
}

List<String> checkFile(String path, String source) {
  final problems = <String>[];
  final p = path.replaceAll(r'\', '/');
  final inTheme = p.startsWith('lib/app/theme/');
  final generated = p.startsWith('lib/l10n/') || p.endsWith('.g.dart');
  final devSeed = p.startsWith('lib/core/dev/');
  // SQL and developer errors only; these layers never show text to a farmer.
  final dataLayer = const [
    'lib/core/db/',
    'lib/core/history/',
    'lib/core/sync/',
  ].any(p.startsWith);
  final lines = source.split('\n');
  for (var n = 0; n < lines.length; n++) {
    final raw = lines[n];
    final line = _code(raw);
    final where = '$p:${n + 1}';
    final trimmed = line.trimLeft();
    final isDirective =
        trimmed.startsWith('import ') ||
        trimmed.startsWith('export ') ||
        trimmed.startsWith('part ');

    if (!generated &&
        !devSeed &&
        !dataLayer &&
        !inTheme &&
        !isDirective &&
        !raw.trimRight().endsWith(_marker) &&
        !(n > 0 && lines[n - 1].trim() == _marker)) {
      for (final m in _literal.allMatches(
        line.replaceAll(_interpolation, ''),
      )) {
        final text = m.group(1) ?? m.group(2)!;
        if (userFacing(text)) {
          problems.add('$where: user-facing text in code: "$text"');
        }
      }
    }
    if (!inTheme && !generated && _colour.hasMatch(line)) {
      problems.add('$where: colour literal outside the theme');
    }
    if (!inTheme && !generated && _fontName.hasMatch(line)) {
      problems.add('$where: font name outside the theme');
    }
    if (isDirective) {
      final drift = line.contains('package:drift');
      final supabase = line.contains('package:supabase');
      final flutter =
          line.contains('package:flutter/') ||
          line.contains('package:material_ui') ||
          line.contains('package:cupertino_ui');
      if (p.contains('/ui/') && (drift || supabase)) {
        problems.add('$where: ui/ must not import Drift or Supabase');
      }
      if (p.contains('/domain/') && (drift || supabase || flutter)) {
        problems.add('$where: domain/ must stay pure Dart');
      }
      final mayUseSupabase =
          p.startsWith('lib/core/sync/') || p.startsWith('lib/core/auth/');
      if (supabase && !mayUseSupabase) {
        problems.add(
          '$where: only core/sync and core/auth may import Supabase',
        );
      }
    }
    final mayWrite =
        const [
          'lib/core/history/',
          'lib/core/sync/',
          'lib/core/dev/',
        ].any(p.startsWith) ||
        generated;
    final write = p.contains('/data/') ? _driftWrite : _driftOnlyWrite;
    if (!mayWrite && write.hasMatch(line)) {
      problems.add('$where: write outside writeWithHistory');
    }
  }
  return problems;
}

void main() {
  final problems = <String>[];
  for (final file in Directory('lib').listSync(recursive: true)) {
    if (file is File && file.path.endsWith('.dart')) {
      problems.addAll(checkFile(file.path, file.readAsStringSync()));
    }
  }
  if (problems.isEmpty) {
    stdout.writeln('Gates passed.');
    return;
  }
  problems.forEach(stderr.writeln);
  stderr.writeln('${problems.length} problem(s).');
  exitCode = 1;
}
