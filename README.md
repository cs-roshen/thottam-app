# Thottam (തോട്ടം)

A complete farm management app for Kerala farmers: land and mixed crops, labour, expenses, inputs, harvest, processing, selling, live prices, profit and loss, and a history of everything. Malayalam first, works offline.

This repository holds the Flutter app (Android and iOS, app id `app.thottam`) together with its specifications, design reference, draft database schema and localisation strings.

## Start in Claude Code

1. Clone this repository and open it in Claude Code.
2. Make sure Flutter (stable) and the Supabase CLI are installed.
3. Paste the prompt from `docs/kickoff-prompt.md`.

## Run the app

Needs Flutter (stable) on your PATH and an Android phone with USB debugging on, or an emulator.

```
flutter pub get
flutter run
```

`flutter test` runs the tests and `flutter analyze` checks the code. Localisation code is generated from `lib/l10n/*.arb` by `flutter pub get`; do not edit the generated `app_localizations*.dart` files.

## Platform choices

- **Minimum Android version: 7.0 (API 24).** This is the lowest version current Flutter stable supports, so the app reaches as many low-end phones in the pilot district as Flutter allows. The value comes from `flutter.minSdkVersion` in `android/app/build.gradle.kts`.

## What is here

| Path | Contents |
| --- | --- |
| `CLAUDE.md` | Project rules Claude Code follows in every session |
| `docs/product-spec.md` | Modules and cross-cutting rules |
| `docs/screens.md` | Screen-by-screen behaviour and acceptance checks |
| `docs/phase-1-tasks.md` | Ordered backlog for the first release |
| `docs/implementation-plan.md` | Detailed phase plan, review process, performance and offline rules |
| `docs/design-tokens.md` | Colours, type, spacing, motion |
| `docs/kickoff-prompt.md` | First prompt to paste into Claude Code |
| `design/prototype/` | Interactive HTML prototype source (reference only) |
| `lib/` | App code; `lib/l10n/` holds the Malayalam and English strings |
| `supabase/migrations/0001_init.sql` | Draft schema with row-level security (not yet run) |

## Status

Phase 0 (doc fixes and owner decisions) is done. Phase 1 foundation tasks are in progress; see `docs/phase-1-tasks.md`. All numbers, names and prices in the prototype are sample data. Malayalam wording needs a native-speaker review before release.
