# Thottam (തോട്ടം)

Offline-first, Malayalam-first farm management app for Kerala farmers. It replaces the paper notebook: plots and mixed crops, labour (named workers and unnamed groups), expenses, inputs, harvest, processing, selling, live prices, profit and loss, and a complete history of everything.

## Read these first

- `docs/product-spec.md` — what the app does, module by module, and the rules that cut across modules.
- `docs/phase-1-tasks.md` — the ordered backlog. Work top to bottom; one task per branch/PR.
- `docs/implementation-plan.md` — phases, exit checks, review process, UI and UX bar, and the performance, offline and database rules.
- `docs/screens.md` — every screen, its fields, behaviour and acceptance checks.
- `docs/design-tokens.md` — colours, type, spacing, motion. Do not invent new values.
- `design/prototype/` — the interactive HTML prototype. It is the visual and behavioural reference, not code to port line by line.
- `supabase/migrations/` — the server schema. 0001 to 0005 are applied to `Thottam-App` (2026-11-19). Never edit an applied migration: add a new one, run `tool/server_tests.py`, then apply it with `supabase db push --remote=<project ref>`.

## Stack

- Flutter (stable channel), Android first, iOS from the same code.
- State: Riverpod. Navigation: go_router.
- Local database: Drift (SQLite). The local DB is the source of truth for the UI.
- Backend: Supabase (Postgres with row-level security, auth by Google sign-in, storage for photos). Phone OTP is added as a second sign-in method at the end of phase 1 (task D6), once the app works.
- Localisation: `flutter_localizations` + ARB files in `lib/l10n/` (`app_ml.arb` is the template, `app_en.arb` the second language).

Check current package versions and APIs in their docs before adding a dependency; do not rely on memory for version numbers or setup steps.

## Non-negotiable rules

1. **Offline first.** Every write goes to Drift first and into an outbox table; sync is a background concern. No screen may block on the network. The one exception is the first sign-in on a phone, with the first sync of any farm the account already has, which needs a connection once.
2. **History of everything.** Every create, edit and delete writes a row to `event_log` (entity, action, old and new values, user, time). Nothing is hard-deleted from the app; use `deleted_at`.
3. **Everything overridable.** Resolution order: app default → farm → plot or crop → single entry. Computed values (amount = qty × rate, splits, conversion ratios) always have a manual-edit path. Never hard-code a list, unit, rate or category in Dart; they come from templates.
4. **Malayalam first.** No user-facing string in Dart code. Every string is an ARB key with both `ml` and `en`. Test layouts with Malayalam text and with large-text mode (1.12 scale).
5. **Money is integer paise**, quantities are numeric with a unit code. Format with Indian grouping (₹1,84,500).
6. **Ids are UUIDs generated on the device.** Every farm-owned, synced table has `id, farm_id, created_at, created_by, updated_at, updated_by, version, deleted_at`; `farms` uses its own `id` as the farm id. Exempt: standard master data with no owning farm (`crops` with a null `owner_farm_id`, `template_items`, official `market_prices` with a null `farm_id`) and `event_log`, which is insert-only and keeps only `id, farm_id, created_at, created_by`. A farmer's own crops and locally entered prices carry the full set; `crops` uses `owner_farm_id` as its farm id. The device increments `version` on every local write; the server changes it only when it settles a conflict between two devices (implementation plan section 13). The server keeps its own `server_seq` for pulling changes.
7. **20-second entries.** Smart defaults (today, last plot, last rate). Touch targets at least 48 dp. Undo after every save.
8. **Accessibility.** Contrast 4.5:1, labels on every icon button, colour never the only signal.

## Project layout (create as you go)

```
lib/
  app/            # router, theme, localisation setup
  core/           # db (drift), sync, event log, money, units, overrides
  features/
    onboarding/ land/ labour/ expenses/ harvest/ sales/ prices/
    history/ money/ inputs/ processing/ doctor/ templates/ settings/
  l10n/           # app_ml.arb, app_en.arb
supabase/migrations/
test/             # unit tests for every rule in core/, widget tests per feature
```

Each feature folder: `data/` (drift tables, repositories), `domain/` (models, rules), `ui/` (screens, widgets).

## Working agreements

- Before a feature: read its section in `docs/screens.md`, then write the acceptance checks as tests first.
- Calculations (wages, splits, harvest rate, profit) live in pure Dart functions in `domain/` with unit tests that match hand-worked examples in the docs.
- Run `flutter analyze` and `flutter test` before saying a task is done.
- Keep commits small and described by what changed for the farmer.
- If a doc and the prototype disagree, the doc wins; if the doc is silent, ask rather than guess.
- Do not add analytics, ads or third-party SDKs without asking.

## Out of scope for phase 1

Everything in implementation plan phases 7 to 13: inputs and stock, processing, crop doctor (including the photo diagnosis model), loans and full money, voice entry, bill OCR, organisations and the web dashboard, community feed, schemes, documents, equipment, livestock, custom records. The admin template console is phase 1 but may start as seed SQL plus a minimal web page.
