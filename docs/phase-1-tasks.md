# Phase 1 backlog

Work in order. Each task ends with `flutter analyze` and `flutter test` passing. Tick a task only when its checks pass.

## A. Foundation

- [ ] A1. Create the Flutter project in this repository (app id to be confirmed with the owner), Android and iOS targets, stable channel. Keep existing `docs/`, `design/`, `supabase/` and `lib/l10n/`.
- [ ] A2. Theme and tokens from `docs/design-tokens.md`; load fonts (Anek Malayalam, Inter, Noto Sans Malayalam) as bundled assets so they work offline.
- [ ] A3. Localisation: wire ARB files, language switch (ml, en, mixed), large-text mode. Clean up ARB keys from the prototype export (rename indexed keys, add descriptions).
- [ ] A4. Shared widgets: primary and outline buttons, choice chip, segmented control, switch row, stepper, tint icon tile, card, toast with undo, bottom sheet, bottom nav with centre add button.
- [ ] A5. Router and shell: four tabs plus add sheet; empty placeholder screens.

## B. Data core

- [ ] B1. Validate `supabase/migrations/0001_init.sql` on a local Supabase instance; fix errors; add seed data for wave 1 crop templates (coconut, rubber, pepper, banana, paddy).
- [ ] B2. Drift schema mirroring the phase 1 tables, with the common columns and an outbox table.
- [ ] B3. Money (integer paise, Indian formatting) and unit conversion helpers, with tests.
- [ ] B4. Event log: every repository write records old and new values; restore function; tests.
- [ ] B5. Override resolver (app → farm → plot or crop → entry) with tests.
- [ ] B6. Auth: phone OTP with Supabase; local session; works offline after first sign-in.
- [ ] B7. Sync: outbox upload, pull since last sync, conflict rules from the spec; tests with two simulated devices.

## C. Features (each: tests from `docs/screens.md` first, then UI)

- [ ] C1. Welcome, language and set-up.
- [ ] C2. Land: plot list, add or edit plot, crop cycles (mixed crops), plot detail.
- [ ] C3. Labour: workers, unnamed and named groups, attendance, group entry, payments and balances.
- [ ] C4. Expenses with split allocation.
- [ ] C5. Harvest with multiple teams and optional per-team quantity; lots.
- [ ] C6. Selling from stock; buyers; receivables.
- [ ] C7. History: timelines per entity, farm diary, filters, change log and restore.
- [ ] C8. Profit and loss with family-labour switch; report export.
- [ ] C9. Home dashboard and tasks; quick add sheet.
- [ ] C10. Settings: pages on/off, home cards, reset; My lists (farmer templates).
- [ ] C11. Prices: table and manual entry first; source integration after data access is confirmed.

## D. Release readiness

- [ ] D1. Offline test: seven days of entries in flight mode, then sync with no loss or duplicates.
- [ ] D2. Malayalam rendering pass on a low-end Android device, including large text.
- [ ] D3. Role checks: supervisor cannot see profit; viewer cannot write.
- [ ] D4. Backup and full export (Excel, PDF).
- [ ] D5. Closed beta build.

## Open decisions for the owner

- App id / package name and store account.
- Supabase project (new or existing) and region.
- Pilot district, crops and partner organisation.
- Which price sources are licensed for use.
