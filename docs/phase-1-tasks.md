# Phase 1 backlog

Work in order. Each task ends with `flutter analyze` and `flutter test` passing. Tick a task only when its checks pass.

## A. Foundation

- [ ] A1. Create the Flutter project in this repository (app id to be confirmed with the owner), Android and iOS targets, stable channel. Keep existing `docs/`, `design/`, `supabase/` and `lib/l10n/`.
- [ ] A2. Theme and tokens from `docs/design-tokens.md`; load fonts (Anek Malayalam, Inter, Noto Sans Malayalam) as bundled assets so they work offline.
- [ ] A3. Localisation: wire ARB files, language switch (ml, en, mixed), large-text mode. Clean up ARB keys from the prototype export (rename indexed keys, add descriptions). Add placeholders and plural rules for every string that carries a number, amount, date or name; renaming keys alone is not enough.
- [ ] A4. Shared widgets: primary and outline buttons, choice chip, segmented control, switch row, stepper, tint icon tile, card, toast with undo, bottom sheet, bottom nav with centre add button, amount input, empty state, "last time" banner, stale-data tag.
- [ ] A5. Router and shell: four tabs plus add sheet; empty placeholder screens.
- [ ] A6. Gates and benchmark seed: check scripts in `tool/` and a CI workflow (implementation plan section 16); a debug-only seed generator with three years of data for one farm (section 14). Done before B1.

## B. Data core

- [ ] B1. Validate `supabase/migrations/0001_init.sql` on a local Supabase instance; fix errors; add seed data for wave 1 crop templates (coconut, rubber, pepper, banana, paddy).
- [ ] B2. Drift schema mirroring the phase 1 tables, with the common columns and an outbox table.
- [ ] B3. Money (integer paise, Indian formatting) and unit conversion helpers, with tests.
- [ ] B4. Event log: every repository write records old and new values; restore function; tests.
- [ ] B5. Override resolver (app → farm → plot or crop → entry) with tests.
- [ ] B6. Auth: Google sign-in with Supabase; local session; works offline after first sign-in. Phone OTP comes later (D6).
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
- [ ] C12. Admin console (minimal): seed SQL plus one web page behind admin sign-in to edit template items in Malayalam and English and publish a new version (screen 23). Service-role access stays on the server side.

## D. Release readiness

- [ ] D1. Offline test: seven days of entries in flight mode, then sync with no loss or duplicates.
- [ ] D2. Malayalam rendering pass on a low-end Android device, including large text.
- [ ] D3. Role checks: the role defaults in `docs/product-spec.md` rule 7 (supervisor cannot see money or profit; accountant cannot write daily work; viewer cannot write), in the app and on the server.
- [ ] D4. Backup and full export (Excel, PDF).
- [ ] D5. Closed beta build.
- [ ] D6. Phone OTP sign-in as a second method beside Google, once everything above works. Same offline and per-user database rules as B6. Decide with the owner whether one account can have both phone and Google linked.

## Open decisions for the owner

- App id / package name and store account.
- Supabase project (new or existing) and region.
- Google Cloud project and OAuth client ids for Google sign-in (needed by B6).
- SMS provider for phone OTP, and sender and template registration (needed by D6).
- Whether one account can have both Google and phone sign-in linked (needed by D6).
- Pilot district, crops and partner organisation.
- Which price sources are licensed for use.
- Test phone: one low-end Android phone typical of the pilot district, for all performance budgets (needed by A6).
