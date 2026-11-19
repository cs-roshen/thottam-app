# Gates

The checks from `docs/implementation-plan.md` section 16. They run the same way
locally and in CI (`.github/workflows/ci.yml`). Run them all before a pull request:

```
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
dart run tool/check.dart
flutter test
```

| Gate | Where |
| --- | --- |
| `dart format` | CI step |
| `flutter analyze` (strict) | `analysis_options.yaml` |
| `flutter test` | `test/` |
| String check | `tool/check.dart`: text with letters in a string literal in `lib/`, outside `lib/l10n/`, the theme, the debug seed and the data layers (SQL in `core/db`, `core/history`, `core/sync` and each feature's `data/`). Codes (`cash`), keys (`more.gallery`), paths (`/home`) and raw strings pass. Put `// gate: not user-facing` at the end of a line, or alone on the line before, for format patterns and assert messages. |
| ARB check | `test/l10n/arb_test.dart`: same keys, a description on every key, same placeholders, no indexed keys or sample data |
| Token check | `tool/check.dart`: `Color(0x..)`, `Colors.*` (except `transparent`) or a font name outside `lib/app/theme/` |
| Layering check | `tool/check.dart`: `ui/` importing Drift or Supabase; `domain/` importing Flutter, Drift or Supabase; Supabase outside `lib/core/sync/` and `lib/core/auth/` |
| Write-path check | `tool/check.dart`: Drift `into(`, `update(`, `delete(` or `customStatement(` in a `data/` folder; writes go through `writeWithHistory` in `lib/core/history/` (B4) |
| Query-plan tests | `test/core/db/query_plan_test.dart`: every query in `test/core/db/list_queries.dart` searches an index, and pages come out in index order |
| Benchmark test | `test/core/db/benchmark_test.dart`: loads `generateBenchmarkSeed()`, times every list query against twice its budget, checks the file stays under 60 MB |
| Schema check | `test/core/db/schema_check_test.dart`: `supabase/migrations` and `lib/core/db/tables.drift` have the same tables and columns, apart from `server_seq` |

## Golden images

Golden tests (`@Tags(['golden'])`) render with the bundled fonts and are
created on Windows, which is why CI runs on Windows. After an intended visual
change, regenerate and look at every changed image before committing:

```
flutter test --update-goldens --tags golden
```

## Fonts

`tool/build_fonts.py` rebuilds `assets/fonts/` from the Google Fonts variable
fonts; see its header for the source commit.

## Benchmark seed

`generateBenchmarkSeed()` gives one farm with three years of data at the sizes
in section 14: 8 plots, 20 crop cycles, 40 workers, 10 groups, 15,000 labour
entries, 6,000 expenses with allocations, 1,500 harvests and lots, 1,200 sales
and about 48,000 event-log rows. Rows use the draft schema's column names;
`loadSeed()` in `lib/core/dev/load_seed.dart` inserts them.

## Phone database

The schema is `lib/core/db/tables.drift`. After changing it, regenerate and
export the new version (bump `schemaVersion` and add its migration step first):

```
dart run build_runner build
dart run drift_dev make-migrations
dart run drift_dev schema generate --data-classes --companions drift_schemas/app/ test/core/db/generated/
```

SQL in Dart goes in raw strings (`r'...'`), which the string check passes.
