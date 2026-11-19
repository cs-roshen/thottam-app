# Phase 1 backlog

Work in order. Each task ends with `flutter analyze` and `flutter test` passing. Tick a task only when its checks pass.

## A. Foundation

- [x] A1. Create the Flutter project in this repository (app id `app.thottam`), Android and iOS targets, stable channel. Keep existing `docs/`, `design/`, `supabase/` and `lib/l10n/`.
- [x] A2. Theme and tokens from `docs/design-tokens.md`; load fonts (Anek Malayalam, Inter, Noto Sans Malayalam) as bundled assets so they work offline.
- [x] A3. Localisation: wire ARB files, language switch (ml, en, mixed), large-text mode. Clean up ARB keys from the prototype export (rename indexed keys, add descriptions). Add placeholders and plural rules for every string that carries a number, amount, date or name; renaming keys alone is not enough.
- [x] A4. Shared widgets: primary and outline buttons, choice chip, segmented control, switch row, stepper, tint icon tile, card, toast with undo, bottom sheet, bottom nav with centre add button, amount input, empty state, "last time" banner, stale-data tag.
- [x] A5. Router and shell: four tabs (three when the role cannot open Money) plus add sheet; empty placeholder screens.
- [x] A6. Gates and benchmark seed: check scripts in `tool/` and a CI workflow (implementation plan section 16); a debug-only seed generator with three years of data for one farm (section 14). Done before B1.

## B. Data core

- [x] B1. Validate `supabase/migrations/0001_init.sql` against Supabase (`tool/server_tests.py`); fix errors; add seed data for wave 1 crop templates (coconut, rubber, pepper, banana, paddy, cardamom).
- [x] B2. Drift schema mirroring the phase 1 tables, with the common columns and an outbox table.
- [x] B3. Money (integer paise, Indian formatting) and unit conversion helpers, with tests.
- [x] B4. Event log: every repository write records old and new values; restore function; tests.
- [x] B5. Override resolver (app → farm → plot or crop → entry) with tests.
- [ ] B6. Auth: Google sign-in with Supabase; local session; works offline after first sign-in. Phone OTP comes later (D6).
- [x] B7. Sync: outbox upload, pull since last sync, conflict rules from the spec; tests with two simulated devices.

## C. Features (each: tests from `docs/screens.md` first, then UI)

- [x] C1. Welcome, language and set-up.
- [x] C2. Land: plot list, add or edit plot, crop cycles (mixed crops), plot detail.
- [ ] C3. Labour: workers, unnamed and named groups, attendance, group entry, payments and balances; split across crop cycles on mixed plots.
- [ ] C4. Expenses with split allocation.
- [ ] C5. Harvest with multiple teams and optional per-team quantity; lots with lot cost (edit, recalculate, reset).
- [ ] C6. Selling from stock; buyers; receivables.
- [ ] C7. History: timelines per entity, farm diary, filters, change log and restore.
- [ ] C8. Profit and loss with family-labour switch; report export.
- [ ] C9. Home dashboard and tasks; quick add sheet with Note.
- [ ] C10. Settings: pages on/off, home cards, reset; farms (switch and add); members and roles (owner only); account and sign out; sync status; My lists (farmer templates).
- [ ] C11. Prices: table and manual entry first; source integration after data access is confirmed.
- [ ] C12. Admin console (minimal): seed SQL plus one web page behind admin sign-in to edit template items in Malayalam and English and publish a new version (screen 23). Service-role access stays on the server side.

## D. Release readiness

- [ ] D1. Offline test: seven days of entries in flight mode, then sync with no loss or duplicates.
- [ ] D2. Malayalam rendering pass on a low-end Android device, including large text.
- [ ] D3. Role checks: the role defaults in `docs/product-spec.md` rule 7 (supervisor cannot see money or profit; accountant cannot write daily work; viewer cannot write), in the app and on the server.
- [ ] D4. Backup and full export (Excel, PDF).
- [ ] D5. Closed beta build.
- [ ] D6. Phone OTP sign-in as a second method beside Google, once everything above works. Same offline and per-user database rules as B6. Decide with the owner whether one account can have both phone and Google linked, and how a member who signs in by phone only is invited.

## Review follow-ups

From the independent reviews of B1 to B7 (2026-11-19). Each belongs to the task named; do
it there, with its test.

- C1 and C10: show open invites with Join and Decline (`SyncServer.invites`, `acceptInvite`, `declineInvite`), at sign-in and under Settings → Farms; nobody joins a farm until they tap Join.
- C1: set-up stores the template version the farm starts from in `farms.accepted_template_version`, so "update available" starts clear.
- C2: deleting a plot or crop cycle asks first and keeps its entries, in profit and loss and history under the deleted plot or crop cycle. That also covers a delete that crosses a new entry another phone already uploaded under it: nothing is lost, so it needs no conflict.
- C4: repositories use shared query definitions, so the query-plan and benchmark gates test the queries the app runs; the benchmark seed fills the tables it leaves empty (labour payments and allocations, harvest teams, notes, tasks, other income) and the benchmark reports the slowest run as well as the median.
- C5: a harvest save writes each row as separate statements (about 140 for 30 rows); measure against the 150 ms save budget and batch them if it is missed.
- C7: restoring an older event warns when the row has changed since.
- C8: the profit and loss queries replace the stand-ins in `test/core/db/list_queries.dart`, with the family-labour switch.
- C10: reset removes only the field being reset from an override row; screens can show the value a reset would go back to.
- C12: the admin console retires template items (`is_active`) instead of deleting them.
- D1: measure the database file with five years of data (all seasons stay on the phone).
- D3: a member whose access narrows drops the rows they can no longer read from the phone (removal already drops the farm).
- Before schema version 2: copy the database file before a migration and run an integrity check (implementation plan section 12).
- Before the beta (D5): sync on connectivity and in the background, and skip on low battery (`lib/core/sync/sync_scheduler.dart`).
- Search: a phone-only search table with normalised Malayalam, English and Manglish text, when the first searchable list is built.

## Owner decisions

Decided (2026-11-17):

- App id: `app.thottam`. Store account: the owner's existing Google Play developer account.
- Supabase: project `Thottam-App` (`mtkxbzwkxupcdjrbmxnf`), region ap-southeast-1 (Singapore). Chosen 2026-11-18 in place of the paused `thottam` project. Migrations 0001 to 0005 applied on 2026-11-19.
- Pilot district: Idukki. Crops: wave 1 (coconut, rubber, pepper, banana, paddy, cardamom).

Decided (2026-11-18):

- History on the phone: every season stays on the phone; nothing is cut off or fetched on demand.
- B1 and B7 server tests run against the owner's Supabase cloud project, `Thottam-App`, in a transaction that always ends in an error so nothing is kept (`tool/server_tests.py`), instead of a local Supabase instance.
- B6 waits for the Google Cloud project and OAuth client ids; B7 is built against a fake server and the server tests until then.

Decided (2026-11-19):

- Invites: the invited person sees each open invite (farm name, role, who sent it) and taps Join or Decline. Nobody is added to a farm until they accept.
- Units and numbers are always shown in English with Latin digits (50 kg, 2.5 acre, 3 quintal, ₹1,84,500), in every language setting; only crop and category names follow the language. Screens show a unit's English name (`name_en`); the Malayalam unit names in the templates are not used for display.
- Standard units only: kg, g, quintal, tonne, litre, cent, acre, hectare, are, and the counts piece, nut, bunch and sheet. The traditional measure para is retired from the templates (migration 0005); no local unit chains are needed.
- Deleting a plot or crop cycle asks first and keeps its entries; undo brings it back.

Open:

- Google Cloud project and OAuth client ids for Google sign-in (needed by B6).
- SMS provider for phone OTP, and sender and template registration (needed by D6).
- Whether one account can have both Google and phone sign-in linked, and how a phone-only member is invited (needed by D6).
- Partner organisation for the pilot (needed by the field test).
- Which price sources are licensed for use (needed by C11).
- Test phone: one low-end Android phone typical of the pilot district, for all performance budgets (needed by A6).
