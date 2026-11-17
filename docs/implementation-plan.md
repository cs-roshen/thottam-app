# Thottam implementation plan

This plan turns `docs/phase-1-tasks.md` into phases with exit checks, and adds the rules for
review, UI and UX quality, app performance, and offline and database performance. It is written
so that any Claude Code session, on any model, can pick up the next task without earlier context.

Where this plan and `docs/product-spec.md` or `docs/screens.md` disagree, those docs win and this
plan should be corrected. Package names here are the planned choices; check each package's
current docs for versions and setup before adding it. No version numbers are fixed in this plan.

"Phase 1" in `CLAUDE.md`, `docs/phase-1-tasks.md` and `docs/screens.md` means the whole first
release (tasks A1 to D6). This plan splits that release into its phases 1 to 6; its own
"Phase 1" (section 5) is the foundation only. "Phase 2 and later" in `docs/screens.md` means
this plan's phases 7 to 13.

Contents

1. How to work through the plan
2. Where to spend the strongest model
3. Architecture in one page
4. Phase 0: settle the starter
5. Phase 1: foundation (A1 to A6)
6. Phase 2: data core (B1 to B7)
7. Phase 3: daily entries (C1 to C4, quick add)
8. Phase 4: harvest to profit (C5 to C8)
9. Phase 5: home, lists and prices (C9 to C11, admin console)
10. Phase 6: release readiness (D1 to D6)
11. Phases 7 to 13: later modules
12. Local database and offline performance
13. Sync and server performance
14. App performance budgets and how to measure them
15. UI and UX quality bar
16. Code review process
17. Risks and open questions

---

## 1. How to work through the plan

**One task, one branch, one pull request.** Branch names: `a1-flutter-project`, `b4-event-log`,
`c3-labour`. Never mix two backlog tasks in one branch.

**Every task follows the same loop.**

1. Read the task here, its section in `docs/screens.md`, and the worked examples in
   `docs/product-spec.md`.
2. Write the acceptance checks as failing tests. Commit them alone ("tests for C4").
3. Build the pure calculation functions in `domain/` until the unit tests pass.
4. Build the repository (`data/`), then the screen (`ui/`).
5. Run the gates in section 16. Fix everything they report.
6. Run the self-review checklist in section 16 and write the result in the pull request.
7. Tick the task in `docs/phase-1-tasks.md` in the same pull request.

**Definition of done for any task.**

- `flutter analyze` has no issues; `flutter test` passes.
- All gates in section 16 pass.
- Every new string is in both ARB files; no user-facing text in Dart.
- Every write goes through a repository that records the event log and the outbox.
- The screen works in flight mode, in Malayalam, and in large-text mode.
- The budgets in section 14 that apply to the task are measured and met, with the numbers in
  the pull request.

**Owner checkpoints.** Stop and wait for the owner at the end of every phase, and wherever a
task says "owner check". At a checkpoint, give the owner: what was built, how to run it, what to
look at on the phone, and any decision that is waiting.

**When something is unclear.** If the docs are silent or contradict each other, ask. Do not
guess a business rule (rounding, who may see what, what counts as profit).

**Session start prompt** (paste for any task):

```
Read CLAUDE.md and docs/implementation-plan.md sections 1, 3 and 12 to 16.
Then do task <ID> following the task loop in section 1. Show me the failing
tests before you write the implementation. Stop when the definition of done
is met and give me the pull request summary with measured numbers.
```

---

## 2. Where to spend the strongest model

The owner has the strongest model for a limited number of days. Spend it on work where a design
mistake is expensive to undo, and leave repetitive screens for later. In priority order:

1. **Phase 0 decisions and doc fixes.** Small, but everything else rests on them.
2. **B1 schema rework** (section 6). Security rules, uniqueness, sync columns, indexes.
3. **B7 sync design and its two-device test harness**, and the server-side batch function.
   This is the hardest part of the app.
4. **B4 event log and B5 override resolver.** Every feature depends on both.
5. **All `domain/` calculation functions with their unit tests**, for every phase 1 feature
   (wages, splits, harvest rates, sale profit, lot cost, profit and loss). These are pure Dart
   and can be written before any screen exists.
6. **A4 shared widgets** and **one complete reference feature: C4 Expenses**, built end to end
   as the pattern (tests, domain, repository, screen, golden tests, performance numbers).
7. **The benchmark seed generator and the gates** in sections 14 and 16.

After that, the remaining features (C1 to C3, C5 to C11) are mostly "follow the Expenses
pattern" and are safer to hand to any model, provided the gates and review process are in place.
C12 is a small web page outside that pattern.

A possible order for the days available: phase 0 and A1 to A3; then A4 to A6 and B1; then B2 to
B5; then B6, B7 and the domain functions; then C4 as the reference feature. Adjust to what is
actually finished each day; do not skip the gates to keep to the order.

---

## 3. Architecture in one page

```
Screen (ui/)  --watches-->  Riverpod provider  --watches-->  Drift query stream
     |                                                             ^
     | user action                                                 |
     v                                                             |
Repository (data/)  --one local transaction-->  1. write the row
                                                 2. write event_log (old and new values)
                                                 3. write outbox (what to upload)
                                                                    |
Sync engine (core/sync), background only  <-------------------------+
     |  upload outbox in batches  -->  Supabase function (one transaction per batch)
     |  pull changes since cursor <--  Supabase tables (row-level security)
     v
Applies pulled rows to Drift; the screens update by themselves through the streams.
```

Rules that follow from this picture:

- **Screens never call Supabase.** Only the sync engine and auth do.
- **Screens never wait for the network.** No spinner on any data screen. The one exception is
  the first sign-in and first sync (`CLAUDE.md` rule 1).
- **Screens never write to Drift directly.** Only repositories write, so the event log and the
  outbox cannot be skipped.
- **Calculations are pure functions** in `domain/`, taking plain values and returning plain
  values. No database, no clock, no locale inside them; pass those in.
- **One source of time and ids.** A `Clock` and an `IdGenerator` are injected, so tests are
  repeatable.

Planned packages: Riverpod (state), go_router (navigation), Drift (local SQLite),
supabase_flutter (auth, sync, storage), flutter_localizations and intl (strings, numbers,
dates), a connectivity package (to trigger sync, never to block screens), and a background-work
package for periodic sync. Ask before adding anything else.

---

## 4. Phase 0: settle the starter

No app code. The output is corrected docs and answered decisions.

### Owner decisions

| Decision | Needed by | Answer (2026-11-17) |
| --- | --- | --- |
| App id (package name) and store account | A1 | `app.thottam`; the owner's existing Google Play developer account |
| Supabase project (new or existing) and region | B1 | The owner's existing project, in its current region |
| Google Cloud project and OAuth client ids for Google sign-in | B6 | Open |
| SMS provider for phone OTP and its registration (see section 17) | D6 | Open |
| Whether one account can have both Google and phone sign-in linked, and how a phone-only member is invited | D6 | Open |
| How many seasons of history stay on the phone (section 12) | B7 | Open |
| Test phone: one low-end Android phone typical of the pilot district | A6 | Open |
| Pilot district and crops | B1 seed data | Idukki; wave 1 crops (coconut, rubber, pepper, banana, paddy, cardamom) |
| Partner organisation for the pilot | Field test (phase 6) | Open |
| Which price sources are licensed for use | C11 | Open |

### Doc contradictions to settle

Each has a recommended answer. The owner confirms or changes it, then the doc is edited.

**Settled 2026-11-17:** the owner accepted every recommended answer below, plus one more found
during phase 0: half-day is an attendance value (0.5), not a wage type. The docs are edited.
A review of those edits then found more gaps; the owner accepted the recommended fixes on the
same day: a role table (`product-spec.md` rule 7), stored-amount rounding (rule 8), lot cost
(rule 9), overtime, conflicts settled in server order, a merge being the one case where the
server sets `version`, profit per sale unit, and a Google sign-in step in `screens.md`.
A second review found 13 more gaps; the owner accepted those fixes on the same day too: split
parts always follow the split rule, a lot stores its total cost when the harvest is saved and
leaves out family labour, members and account in Settings, the first sign-in as the one step
that needs the network, the base version on uploads, a delete against an edit going to the
user, overtime columns, the switch hit area, and the column and naming notes in `CLAUDE.md`.
A third review found 21 more; the owner settled four rules on the same day (a supervisor also
writes workers and groups; on a mixed plot labour either splits or posts to one crop cycle, as
set under the override model; one account can belong to several farms, with a switcher; family
labour is a separate line on the harvest) and the rest were fixed as recommended. A fourth
review found 9 more, fixed as recommended: lot cost moves to its own money table, a
supervisor's team edit marks the cost pending again, equal values are not a conflict, group
leaders are workers, invites apply at the next sync, labour splits default to the expense
split, and the upload order, indexes and network exception were corrected.

| Question | Recommended answer | Doc to edit |
| --- | --- | --- |
| Minimum touch target: 48 or 44? | 48, as in `CLAUDE.md` | `design-tokens.md` |
| Does sale profit per kg subtract deductions? | Yes: net amount per kg minus lot cost per kg. The spec example becomes 35,080 / 50 − 238 = ₹463.60. Show the deductions line so the farmer sees why. | `product-spec.md` |
| Where do leftover paise go in a split? | Largest-remainder method: give each crop its rounded-down share, then hand out the remaining paise one at a time to the largest fractional parts; ties go to the crop cycle listed first. | `product-spec.md`, `screens.md` |
| How are per-kg and per-person figures rounded? | Keep full precision in calculation; round only for display, to one decimal for quantities and to whole paise for money. | `product-spec.md` |
| What does "mixed" language show? | Malayalam interface, with crop, category and unit names shown in Malayalam followed by English. Digits are always Latin. | `product-spec.md`, `screens.md` |
| Who owns the record `version`? | The device increments `version` on every local write. The server changes it only when it settles a conflict between two devices. The server keeps its own `server_seq` for pulling changes (section 13). | `CLAUDE.md` |
| Which tables carry the common columns? | Every farm-owned, synced table, including a farmer's own crops and locally entered prices. Standard master data with no owning farm (`crops`, `template_items`, official `market_prices`) and `event_log` are exempt, and say so. | `CLAUDE.md` |

### Backlog fixes

- Add task **C12. Admin console (minimal)**: seed SQL plus one web page to edit and publish
  template items. It is in phase 1 scope but has no task.
- Add task **A6. Gates and benchmark seed** (sections 14 and 16), done before B1.
- Note in A3 that ARB placeholders must be added, not only keys renamed.

**Exit check:** the owner has answered the decisions needed for A1 and B1, and a reviewer
session finds no remaining contradiction between the six docs (`CLAUDE.md` included).

---

## 5. Phase 1: foundation (A1 to A6)

Goal: an empty app that already looks and reads right on a real low-end Android phone.

### A1. Flutter project

- Create the project in the repository root, Android and iOS, keeping `docs/`, `design/`,
  `supabase/` and `lib/l10n/`.
- Set the minimum Android version to whatever current Flutter stable supports that still covers
  low-end phones in the pilot district; record the choice in `README.md`.
- Add strict analysis options (strict casts, strict inference, no implicit dynamic) from day one.
- Add `l10n.yaml` with `app_ml.arb` as the template.

### A2. Theme and tokens

- One `ThottamTokens` class holding every value in `docs/design-tokens.md`; one `ThemeData`
  built from it. Widgets read tokens from the theme, never literal colours or sizes.
- Bundle fonts as assets. Include only the weights the tokens list. Measure what the fonts add
  to the app size and report it; Malayalam fonts are large.
- Tabular figures on every amount.
- Unit test: every text and background pair in the tokens meets 4.5:1 contrast.

### A3. Localisation

- Wire both ARB files. Language choice: Malayalam, English, mixed. Large-text switch scales
  content by 1.12 on top of the system text size, not instead of it.
- Rename the 166 indexed keys from the prototype export (`tplActs2x3`, `evT4`) to meaningful
  names with descriptions.
- Remove sample data from the ARB files (worker names, post authors, sample plot names, later
  phase screens). Sample data belongs in seed data, not strings.
- Reword set-up copy written for phone sign-in (`obSubs0`, "Just a name and phone number") to
  match the Google sign-in flow in `screens.md`.
- Add placeholders and plural rules for every string that carries a number, amount, date or
  name. No string concatenation in Dart.
- Money formatter: integer paise in, Indian grouping out (₹1,84,500). Date formatter with the
  Malayalam month beside the Gregorian date.

### A4. Shared widgets

Build each widget once, with all its states, before any feature uses it: primary and outline
button, choice chip, segmented control, switch row, stepper, tint icon tile, card, toast with
undo, bottom sheet, bottom navigation with the centre add button, amount input, empty state,
"last time" banner, stale-data tag.

- Each widget has a semantic label, a 48 dp touch target, and a pressed, disabled and focused
  state.
- Golden tests for each widget in four variants: Malayalam, English, Malayalam with large text,
  Malayalam with the longest realistic label.
- A widget gallery screen in debug builds, so the owner can review them all in one place.

### A5. Router and shell

- Four tabs (three when the role cannot open Money) plus the add sheet, with placeholder screens. Each tab keeps its own navigation
  stack and scroll position when the user switches tabs.
- Android back button behaves predictably: closes a sheet, then goes back, then goes to Home,
  then leaves the app.

### A6. Gates and benchmark seed

- The check scripts and CI workflow in section 16.
- A seed generator (debug builds and tests only) that fills the local database with three years
  of realistic data for one farm: see section 14 for sizes.

**Owner check:** install on a phone. Check the theme against the prototype, read every
Malayalam label for clipping, switch language and large text, and try the navigation.

**Exit check:** cold start within budget on the test phone with an empty database; all golden
tests pass; the owner has approved the look.

---

## 6. Phase 2: data core (B1 to B7)

Goal: data that is correct, private, fast and impossible to lose, before any feature exists.

### B1. Server schema rework

Start a local Supabase instance, run the migration, and fix it. Write changes as new migration
files after `0001`, or rewrite `0001` since it has never been run; say which in the pull request.

Fixes to make:

| Area | Change |
| --- | --- |
| History | `event_log` is insert-only for clients: no update or delete policy. |
| Deletes | Split every `for all` policy into select, insert and update. No client delete policy on any table; deleting means setting `deleted_at`. |
| Farm creation | One security-definer function `create_farm(...)` that inserts the farm and the owner's `farm_members` row in one transaction and returns the farm. Clients do not insert into `farms` directly. |
| Profiles | Create the `profiles` row automatically when an auth user is created. |
| Members | Add `farm_invites` (Google email, role, permissions, with the common columns). A security-definer function turns a matching invite into a `farm_members` row when that account next signs in or syncs. `is_farm_member` and `farm_role` ignore rows with `deleted_at` set, and a withdrawn invite is never accepted; test that a removed member can no longer read or write. One account can belong to several farms. |
| Template uniqueness | Stop duplicate items where `crop_id` is null (unique index that treats nulls as equal, or two partial unique indexes). |
| Crop codes | Unique per owner: standard crops unique by `code`, a farmer's own crops unique by `(owner_farm_id, code)`. |
| Sales | A sale can draw from several lots: add `sale_lots (sale_id, lot_id, quantity)` and drop `sales.lot_id`. Add `sale_payments` for part payments. Both new tables carry the common columns. Keep `sales.received_paise` only if it is derived. |
| Lots | Supervisors read `lots` (stock), and row-level security cannot hide one column, so move the cost out: add `lot_costs (lot_id, cost_paise, cost_overridden)` with the common columns, as a money table, and drop `lots.cost_paise`. Add `lots.cost_pending`, set when a role that cannot write money saves the harvest or edits its teams; the next money phone works out the cost and clears it. |
| Payables | Add a payments table, with the common columns, for expenses bought on credit, so a payable can be part-paid. |
| Notes | Add `notes` (text, date, optional plot and crop cycle) with the common columns. |
| Labour | Payment kinds and wage types match the spec exactly (half-day is an attendance value, not a wage type; settled in phase 0). Add check constraints to `labour_entries.wage_type` and `sales.mode`. Add `overtime_hours` and `overtime_rate_paise` to `labour_entries` (the overtime rate defaults from templates); `hours` stays for the hourly wage type. Add `labour_allocations` (like `expense_allocations`, with the common columns) so wage cost can split across a mixed plot's crop cycles. Replace `labour_groups.leader_party_id` with `leader_worker_id`, so a supervisor can name a group leader without touching parties. |
| Units | Remove hard-coded unit lists from check constraints; units come from templates. |
| Common columns | Add the missing ones to `expense_allocations`, `price_alerts`, farmer-owned `crops` rows and locally entered `market_prices` rows. Give `farm_members` and `labour_group_members` the full common columns so membership changes sync and can be undone. |
| Versions | Remove the version increment from the `set_updated` trigger (see section 13). |
| Sync columns and indexes | Section 13. |
| Roles | Section 13, "Row-level security". Tighten now so D3 is a check, not a rewrite. |
| Template updates | Record which template version each farm has accepted, so "update available" can be computed. |

Seed data: wave 1 crop templates (coconut, rubber, pepper, banana, paddy, cardamom) with activities,
expense categories, units, grades, labour tasks, rate classes and default splits, in Malayalam
and English. Malayalam wording is marked for native-speaker review.

Tests (run against the local instance): for each role, a table of "can read / can insert / can
update" per table; a user from farm A can never read farm B; history cannot be changed; nothing
can be hard-deleted by a client.

### B2. Local schema (Drift)

- Mirror the phase 1 tables with the common columns, plus local-only tables: `outbox`,
  `sync_state` (one cursor per table), `conflicts`, `photo_uploads`, `app_settings`.
- Open the database with the settings in section 12. Create every index in section 12.
- Export the schema for each version and add migration tests from the start, so a later schema
  change cannot lose a farmer's data.

### B3. Money and units

- `Money` as integer paise: add, subtract, multiply by a quantity or ratio with the rounding
  rule in `product-spec.md` rule 8 (once, when saved, half away from zero), split by weights
  using the largest-remainder rule from phase 0, format and parse with Indian grouping.
- Units with conversions from templates, including local units and custom ratios.
- Property-style tests: a split always sums to the original for random amounts and weights;
  formatting then parsing returns the same value.

### B4. Event log

- A single `writeWithHistory` path used by every repository: inside one local transaction it
  writes the row, an `event_log` row, and an `outbox` row.
- Store **only the changed fields** in old and new values for updates (full row for create and
  delete). This keeps the log small and makes "old → new" display direct.
- `summary` holds the few display fields the timeline needs (plot, crop, amount, quantity), so
  the History screen never has to join to render a row.
- Restore: applies the old values as a new write, which is itself logged.
- Tests: create, edit, delete and restore each leave the expected log rows; a failed
  transaction leaves nothing behind in any of the three tables.

### B5. Override resolver

- One function: given a key and a context (farm, plot, crop cycle, entry), return the value and
  which level it came from. The level is needed to show the "overridden" mark and the reset
  action.
- Load a farm's templates and overrides into memory once and refresh when they change; resolve
  from memory. Do not query the database per field.
- Tests: each level wins over the ones above it; reset falls back one level; an admin update
  never changes a value the farmer edited or hid.

### B6. Auth

- Google sign-in through Supabase (owner decision, phase 0). Phone OTP is added later as a
  second method in D6, once the app works. After the first sign-in the app opens and works with
  no network, for as long as the farmer likes; a refresh that fails offline must never sign the
  farmer out or hide their data.
- Session stored in secure storage. The local database is tied to the signed-in user; signing
  in as someone else on the same phone must not show the first user's data.
- Owner check: sign-in works on the test phone with a real Google account, and the app still
  opens with its data after a week in flight mode.
- D6 (phone OTP) reuses the same session and per-user database rules. Its owner check: OTP
  arrives on a real Indian number on at least two mobile networks.

### B7. Sync

Build to the design in section 13. Deliverables:

- Outbox upload with coalescing, batching and retry.
- Pull by cursor per table, applied in dependency order inside local transactions.
- Conflict rules from the spec: different fields merge; on the same field the upload that
  reaches the server later wins; money and quantity conflicts, a delete against an edit, and a
  new row under a parent deleted elsewhere are put in `conflicts` and shown to the user to
  choose.
- A test harness with two simulated devices and a fake or local server, covering: both offline
  then both sync; the same row edited on both; delete on one and edit on the other; upload
  interrupted halfway; the same batch sent twice; clock on one device wrong by a day; a new
  row on one device under a parent deleted on the other.
- A small sync status element (last synced time, items waiting) for Settings. Never a blocking
  dialog.

**Exit check:** the two-device tests pass; the role tests pass; the benchmark seed loads and
every query budget in section 14 is met on the test phone.

---

## 7. Phase 3: daily entries (C1 to C4, quick add)

Goal: a farmer can set up and record a normal working day, offline, in about 20 seconds per
entry. Build **C4 Expenses first** as the reference feature, then the others to the same shape.

### C4. Expenses (reference feature)

- Domain: split by template share, by area, by plant count, equal, or custom; manual edit of
  any share re-balances the rest; the total always equals the amount.
- Screen: large amount input opens with the numeric keypad already up; category chips ordered
  by most used; plot and date default to the last used and today; split shown collapsed with
  "edit manually"; payment mode; save with undo toast.
- Tests: the ₹3,600 example; awkward amounts (₹100 across three equal crops, and the ₹3,333
  percentage example); manual edit then
  amount change; credit creates a payable.
- Record in the pull request: taps to save a typical expense, time from opening to saved, and
  the query timings. Later features copy this structure and this report.

### C1. Welcome, language and set-up

- Three steps, each skippable except name and farm name. Finishing creates the farm, one plot
  and the crop cycles from templates in a single local transaction.
- An account that already has a farm (its own, or by invite) skips set-up: sign-in runs the
  first sync (section 13) and opens Home.
- Works fully offline after the sign-in step; templates needed for set-up ship inside the app as a
  bundled seed so the first run does not depend on a download.

### C2. Land

- Plot list, add and edit plot, crop cycles with area share or plant count, plot detail with
  stats, tabs and recent history.
- Check: plot totals equal the sum of the plot's crop cycles; closing a season makes its
  entries read-only.

### C3. Labour

- Named workers with "same as yesterday", and groups by head count per rate class. Payments,
  advances and balances.
- Domain functions: attendance wage, group wage, balance per worker and per group.
- Check: the ₹2,150, ₹1,200 overtime and ₹5,200 examples; an unnamed group can be named
  later without losing its entries; wage cost posts to the chosen crop cycle, or splits across
  a mixed plot's crop cycles by the split rule, whichever the override model sets.

### Quick add sheet (part of C9, brought forward)

- The centre button opens the sheet from any tab. Tiles follow the enabled pages and the
  user's role. Voice, bill scan and Inputs are hidden in phase 1 (Inputs arrives in plan phase
  7). Note is a small sheet (`screens.md` section 3).

**Owner check:** record a real day from the paper notebook into the app, in flight mode, and
note anything that took more than 20 seconds or needed explaining.

**Exit check:** all worked examples for these features pass; each entry screen meets the tap
and time budgets; everything entered appears in the event log.

---

## 8. Phase 4: harvest to profit (C5 to C8)

Goal: the full chain from harvest to stock to sale to profit, with history visible.

### C5. Harvest

- Any number of teams (unnamed group, named group, named worker), each with its own rate;
  per-team quantity on or off; piece-rate teams beside daily-rate teams.
- Saving creates the harvest, the team labour entries and the lot in one transaction.
- Lot cost: `product-spec.md` rule 9; test with its two lot-cost examples, a family worker on
  a team (left out of the total), and a cost entered later with an earlier date (a saved lot
  does not change until the farmer recalculates). Also: an edited cost is marked and can be
  reset; editing a team recalculates the lot unless the cost was edited by hand; a supervisor's
  harvest saves with the cost not yet worked out, and the next owner, manager or accountant
  phone works it out; a supervisor's team edit marks it pending again; two money phones that
  save the same cost make no conflict.
- Piece-rate teams enter their own quantity even with per-team quantity off.
- Check: the harvest example with the switch on and off; removing a team recalculates.

### C6. Selling

- Sell from one or more lots; rate prefilled from the latest price; deductions; net; profit per
  sale unit shown before saving; part payments and receivables; buyer book.
- Check: cannot sell more than stock, including when two devices sell from the same lot while
  offline (this becomes a quantity conflict for the user to settle); a sale in a different unit
  from the lot (paddy harvested in kg, sold per quintal) converts the lot cost before profit.

### C7. History

- Farm diary grouped by day with filters, per-entity timelines, old → new on edits, restore,
  "this week last year", export.
- Reads only from `event_log` using its `summary` column; keyset pagination (section 12).
- Check: every create, edit and delete from every screen appears; scrolling stays smooth with
  the benchmark seed loaded.

### C8. Profit and loss

- By farm, plot, crop, season or period; family-labour switch; share report.
- Totals come from SQL aggregates over indexed columns, not from loading rows into Dart.
- Check: the profit example in both switch positions; totals match the sum of the parts at
  every level.

**Exit check:** one scripted season (set-up, labour, expenses, harvest, sale) produces the
expected profit to the paisa; History shows every step; budgets met with the seed loaded.

---

## 9. Phase 5: home, lists and prices (C9 to C11, admin console)

- **C9. Home dashboard and tasks.** Each card has its own provider and query, so one card
  changing does not rebuild the others. Ticking a task writes to history. Weather needs a data
  source decision; show the card only when data exists.
- **C10. Settings and My lists.** Pages and home cards on or off; reset to default; farms
  (switch and add); members and roles (owner only, added by Google email); account and sign
  out, with a warning when items are waiting to sync; sync status; farmer templates with "new
  items available" for admin updates. Check: an admin update never changes an item the farmer
  edited or switched off; a member added as supervisor cannot open money or profit; a removed
  member loses access; switching farm shows only that farm's data.
- **C11. Prices.** Table and manual entry first. Prices older than one day are marked stale.
  Source integration only after licensing is confirmed. Cache the latest prices locally so the
  screen works offline and says how old the data is.
- **C12. Admin console (minimal).** One web page behind admin sign-in to edit template items
  in both languages and publish a new version. Service-role access stays on the server side.
- **Report export** (from C8): PDF and Excel generated on the device, off the main thread.

**Exit check:** hiding a page removes it from More and quick add; a published template update
arrives as "update available" and leaves farmer changes untouched.

---

## 10. Phase 6: release readiness (D1 to D6)

- **D1. Offline soak.** Seven days of scripted entries in flight mode on two devices, then
  sync. Compare row counts and totals on both devices and the server: no loss, no duplicates.
- **D2. Malayalam pass.** A native speaker reviews every string in context on a low-end phone,
  in normal and large text. Fix clipping, awkward wording and wrong farming terms.
- **D3. Role checks.** The role defaults in `product-spec.md` rule 7 and per-person permission
  overrides. Checked in the app and against the server directly.
- **D4. Backup and full export.** Excel and PDF of everything, and restore onto a new phone by
  signing in (first sync, section 13).
- **D5. Closed beta.** Release build with obfuscation and split per CPU type; crash reporting
  only with the owner's approval (CLAUDE.md forbids adding SDKs without asking).
- **D6. Phone OTP.** A second sign-in method beside Google, after the closed beta build. Same
  session and per-user database rules as B6. Settle with the owner first whether one account
  can have both linked. Owner check: OTP arrives on a real Indian number on at least two mobile
  networks.
- **Field test.** Five to ten farmers in the pilot district use it for two weeks. Watch at
  least three of them do a first entry without help. Record where they hesitate.
- **Store requirements.** Privacy policy, data deletion request path, permissions explained in
  Malayalam.

**Exit check:** soak test clean; all budgets met on the test phone with the seed loaded; no
open correctness bugs; native-speaker review signed off.

---

## 11. Phases 7 to 13: later modules

These start after the closed beta. The order below is by farmer value and by what each module
depends on; re-order after beta feedback, but keep the dependencies. Each module is its own
phase with its own exit check and owner checkpoint.

| Phase | Module | Depends on |
| --- | --- | --- |
| 7 | Inputs and stock | Expenses, parties, templates |
| 8 | Processing | Harvest lots, selling |
| 9 | Crop doctor | Photos queue, tasks, inputs (for treatments) |
| 10 | Full money: loans, budgets, recurring and capital costs, cash flow | Expenses, sales, profit and loss |
| 11 | Faster entry: voice and bill scan | All entry screens stable |
| 12 | Organisations and web dashboard | Templates, roles, sync |
| 13 | Community, schemes, documents, equipment, livestock, custom records | Organisations (for moderation and content) |

### Rules for every later module

- **Docs first.** Before any code: add the module's rules and hand-worked examples to
  `product-spec.md`, its screens and acceptance checks to `screens.md`, its tables to a new
  migration and the Drift schema, and its strings to both ARB files. One pull request for the
  docs, reviewed by the owner, then the build tasks.
- **Same loop, same gates.** The task loop in section 1, the gates and reviews in section 16,
  the screen checklist in section 15 and the budgets in section 14 all apply unchanged.
- **Switchable.** Each module is a page the farmer can turn off in Settings. A module that is
  off adds no tiles, no home cards and no background work.
- **Offline first still holds.** Anything that truly needs the network (expert replies, voice
  recognition on a server, scheme lists) must let the farmer finish the entry offline and
  complete the network part later from a queue, with a visible "waiting to send" state.
- **Additive schema only.** New tables and new nullable columns. Never change the meaning of a
  phase 1 column. Every change ships with a local migration test from every earlier version.
- **Re-measure.** Extend the benchmark seed with the module's data and re-run all budgets; a
  new module must not slow down an old screen.
- **Backlog ids.** Tasks are numbered by phase: E for phase 7, F for 8, G for 9, H for 10,
  J for 11, K for 12, L for 13. Add them to a new `docs/later-phases-tasks.md` when the phase
  starts, not before, so the list reflects what beta taught.

### Phase 7: inputs and stock (screen 19)

**Goal:** the farmer knows what fertiliser, pesticide and seed is on hand, what was applied
where, what it cost each crop, and when it is safe to harvest after a spray.

**Schema additions**

- `input_items` (farm's own list, linked to a template item where one exists; unit, pack size,
  reorder level, waiting period in days).
- `input_purchases` (item, quantity, unit, price, vendor, batch, expiry date, link to the
  expense row it creates).
- `input_applications` (item, quantity, method, plot, crop cycle, worker or group, date,
  computed cost, link to a disease record when it is a treatment).
- `stock_movements` (one row per purchase, application, adjustment or loss; the stock level is
  the sum of movements, never a stored number that can drift).
- `soil_tests` (plot, date, values, lab, photo of the report).

**Rules and tests**

- A purchase creates one expense, so money is never entered twice. Decide and document when
  the cost reaches a crop: recommended is at application, not at purchase, with unapplied
  stock shown as an asset.
- Cost of an application: weighted average cost of the item at that date. Hand-worked example
  in the spec: two purchases at different prices, then an application.
- Stock cannot go negative without the farmer confirming an adjustment.
- Safe-to-harvest date = application date plus the item's waiting period, per crop cycle,
  taking the latest of all recent applications. Logging a harvest inside the period shows a
  warning that can be overridden with a reason, and the override is recorded in history.
- Low-stock and expiry alerts are computed locally and work offline.

**Screens:** stock list with used and bought and a low-stock tag; add purchase; log application
(reachable from quick add and from plot detail); item history; soil test record; the
safe-to-harvest countdown on plot detail and on the harvest screen.

**Performance notes:** index `stock_movements (item_id, moved_on)`. Stock level per item is an
aggregate; cache it in a summary table only if the stock list misses its budget.

**Tasks:** E1 docs and schema; E2 domain (average cost, stock, waiting period) with tests;
E3 purchases and stock list; E4 applications and cost posting; E5 safe-to-harvest and alerts;
E6 soil tests.

**Owner decisions:** source and review of waiting periods and label doses (these are safety
information; they must come from product labels or an agricultural authority, with the source
shown, and never be invented).

**Exit check:** a scripted season with purchases and applications gives the expected stock,
crop costs and safe dates; profit and loss matches the phase 1 result plus input costs.

### Phase 8: processing (screen 20)

**Goal:** follow produce from harvest lot through drying, curing or milling to a sellable lot,
with the true cost per kg and full traceability.

**Schema additions**

- `process_batches` (crop, started and finished dates, status, storage location).
- `batch_inputs` (batch, source lot, quantity taken).
- `batch_steps` (batch, step from template, started and finished, weight in, weight out, cost,
  labour entries linked to the step).
- `batch_outputs` (batch, new lot, quantity, grade).
- `storage_locations`, and a `location_id` on `lots`.
- `lots.parent_batch_id` so a lot knows where it came from.

**Rules and tests**

- Conversion ratio and loss per step and overall; the spec example (100 kg in, 33 kg out, 33%,
  loss 67 kg) is the first test. Expected ratio comes from the template and is overridable.
- Output lot cost = cost of the input lots used + processing costs + step labour, divided
  across outputs by weight (or by value when grades differ; decide and document).
- Taking from a lot reduces its stock exactly as a sale does, with the same oversell conflict
  handling in sync.
- Traceability query: from any sold lot back to batches, harvests, plot and dates, and forward
  from a harvest to where it was sold.
- A batch can be left open for days; partial progress is saved at every step.

**Screens:** batch list with progress; new batch (pick lots); step entry with weights; move to
stock; lot detail showing its origin; stock ageing view.

**Performance notes:** traceability is a recursive query; keep the chain shallow by storing
`root_harvest_ids` on each lot at creation, and index `batch_inputs (lot_id)` and
`batch_outputs (lot_id)`.

**Tasks:** F1 docs and schema; F2 domain (ratio, loss, cost roll-up) with tests; F3 batch
creation and steps; F4 outputs, storage and ageing; F5 traceability and selling from processed
lots.

**Exit check:** a harvest processed in two steps and sold in two part sales gives the expected
cost per kg and profit, and the sale traces back to the plot.

### Phase 9: crop doctor (screen 10)

**Goal:** the farmer records a problem with photos in under a minute, sees vetted remedies, can
ask an expert in one tap, and keeps the outcome as history for next season.

Build in three steps. Do not start with the diagnosis model.

**9a. Disease records and remedy library**

- Schema: `disease_records` (crop cycle, plot, affected part, severity, area affected, note,
  status: open, awaiting expert, treated, resolved; suggested and corrected diagnosis),
  `disease_photos` (several per record, with follow-up photos dated), `remedies` as template
  content (crop, disease, organic and chemical options, label dose, waiting period, source).
- Photos use the phase 1 upload queue and the resize rules in section 12.
- A remedy can become a task, and a treatment logs an input application (phase 7) so cost and
  safe-to-harvest follow automatically.
- Content rules: label doses only, source shown on every remedy, reviewed by a qualified
  person before publishing, and a plain statement that it is guidance, not a prescription.
  The owner must name who reviews this content.

**9b. Send to expert**

- Schema: `expert_requests` and `expert_replies`, visible only to the farm and the assigned
  expert. A new `expert` role with access limited to records shared with them.
- Works offline: the request is queued and sent on the next sync; the record shows "awaiting
  expert" and a notification arrives with the reply.
- Needs: a partner organisation that supplies experts, a response-time promise shown to the
  farmer, and a simple expert view (part of the web dashboard, phase 12, or a minimal page
  first).

**9c. Photo diagnosis (suggestion only)**

- Start only when there are enough expert-confirmed records for the pilot crops to evaluate a
  model honestly. Until then, the farmer picks from a short illustrated symptom list.
- Decide on-device or server by measurement on the test phone (size, speed, accuracy offline).
- Always shown as a suggestion with a confidence level; the farmer can correct it; corrections
  and expert confirmations are stored for evaluation.
- Never suggest a chemical treatment from the model alone; link to the vetted remedy library.
- Exit only on a measured accuracy the owner and the expert partner accept, per crop.

**Tasks:** G1 docs, schema and content review process; G2 record with photos; G3 remedy
library and remedy-to-task; G4 treatment, follow-up and outcome; G5 expert requests; G6 symptom
picker; G7 diagnosis model evaluation and integration (separate decision).

**Privacy:** photos and locations are the farmer's data. Use for model training only with
explicit, separate consent, recorded per farm.

**Exit check (9a and 9b):** a record created offline with three photos syncs, reaches an
expert, the reply appears on the record, the treatment posts its cost, and the plot shows the
safe-to-harvest date.

### Phase 10: full money

**Goal:** the complete financial picture: loans, what is owed both ways, budgets, repeating and
long-life costs, and cash flow by month.

**Schema additions**

- `loans` (lender party, principal, rate, type, start date, terms), `loan_schedule`,
  `loan_payments` (split into principal and interest).
- A single `ledger_entries` view or table that unifies receivables (sales), payables (credit
  expenses, wages due) and loans per party, so the buyer book, vendor book and worker balances
  read the same way.
- `budgets` (crop cycle, category, amount).
- `recurring_rules` (what to create, how often, until when).
- `assets` (capital expense, purchase value, useful life, method) for depreciation.

**Rules and tests**

- Interest methods used locally (simple, reducing balance, flat, gold loan and Kisan Credit
  Card style terms): get the exact rules from the owner or a banker, write hand-worked
  schedules into the spec, and test to the paisa. Every schedule line is editable, because
  real lenders differ.
- Recurring entries are created as drafts for the farmer to confirm, never silently.
- Depreciation and loan interest appear in profit and loss only when their switches are on,
  matching the family-labour switch pattern from phase 1.
- Cash flow is by payment date; profit is by entry date. Show both and say which is which.
- Break-even price and cost per acre and per kg, with hand-worked examples.

**Screens:** loans list and detail with schedule; party ledgers; budget against actual per crop
cycle; recurring items; assets; cash flow by month; extended profit and loss switches;
extended exports.

**Tasks:** H1 docs and schema; H2 loan domain with tests; H3 loans screens; H4 unified ledgers;
H5 budgets; H6 recurring; H7 assets and depreciation; H8 cash flow and report updates.

**Owner decisions:** which loan types to support first. The accountant can edit loans, as money
entries (`product-spec.md` rule 7).

**Exit check:** a season with a loan, a credit purchase, a part-paid sale and a recurring lease
payment produces the expected ledgers, cash flow and profit in every switch position.

### Phase 11: faster entry (voice and bill scan)

**Goal:** cut entry time further for farmers who find typing slow, without ever saving
something the farmer did not confirm.

**Voice entry**

- The farmer speaks ("five workers at eight hundred for pepper weeding today"); the app fills
  the normal entry form for review. Voice never saves directly.
- Parsing from text to fields is a pure, tested function with a large table of real Malayalam,
  English and mixed phrases collected during the beta. Numbers, units, crops, tasks and names
  resolve against the farm's own lists.
- Speech recognition for Malayalam: evaluate on-device and server options on the test phone
  with recordings from real farmers in the pilot district, measuring word accuracy on numbers
  and crop names specifically. Dialects vary; test more than one.
- If recognition needs the network, the feature is simply unavailable offline, and says so
  briefly. Do not queue audio without the farmer knowing.
- Ask for microphone permission only at first use, with the reason in Malayalam. Do not keep
  audio after parsing unless the farmer has opted in to help improve it.

**Bill scan**

- Photograph a shop bill; the app proposes vendor, date, items and total as a draft expense or
  input purchase for review. The photo is kept with the entry.
- Printed and handwritten bills in Malayalam and English behave very differently; measure both
  and promise only what works. Total and date are the minimum useful result.
- Matching scanned items to the farm's input list uses the search text from section 12.

**Tasks:** J1 phrase collection and parser with tests; J2 recognition evaluation and choice;
J3 voice in quick add; J4 bill capture and extraction evaluation; J5 bill draft review screen.

**Exit check:** on a held-back set of real recordings and bills, the measured accuracy meets a
target the owner sets after J2 and J4; in every failure the farmer lands on a normal form with
whatever was understood, never an error wall.

### Phase 12: organisations and web dashboard

**Goal:** farmer producer organisations, estates with several farms, and extension officers can
manage templates and see what members choose to share.

**Schema additions**

- `organisations`, `organisation_members` (with roles), `organisation_farms` (membership of a
  farm in an organisation, with the farm owner's consent and the list of what is shared).
- Organisation-level templates, completing the three levels in the spec (app admin,
  organisation admin, farmer).
- Aggregated, read-only views for organisation reports.

**Rules**

- **Consent is explicit and granular.** A farm owner chooses what an organisation can see
  (for example crops and harvest quantities, but not money), can change it at any time, and
  every change is in history. The default is nothing shared.
- Organisation staff never get write access to a farm's entries through the organisation.
- Organisation template updates arrive as "update available", exactly like admin updates.
- Row-level security for organisation access is written and tested with the same per-role
  table as B1, and reviewed twice.

**Web dashboard**

- A separate web app that talks to Supabase directly. Read-mostly: multi-farm overview for an
  owner or manager, organisation reports (area by crop, expected and actual harvest, input
  demand), the full admin template console replacing the minimal page from C12, the expert
  view for crop doctor, and exports.
- Not offline. Choose the web framework at the start of the phase from current options and
  record the decision; share types with the schema, not code with the phone app.
- Large tables are paged on the server; reports use database views or scheduled summaries, not
  client-side adding up.

**Tasks:** K1 docs, consent model and schema; K2 security rules and tests; K3 organisation
templates; K4 sharing settings in the app; K5 dashboard shell and sign-in; K6 multi-farm
overview; K7 organisation reports; K8 full admin console; K9 expert view.

**Owner decisions:** the first partner organisation and what it needs to see; pricing or
licensing for organisations; who administers app-level templates.

**Exit check:** an organisation sees only what each farm shared, loses access the moment
sharing is withdrawn, and can publish a template update that leaves farmer changes intact.

### Phase 13: community, schemes and other records

Smaller modules, each independent. Build only those the beta and partners ask for.

| Module | What it does | Main additions | Watch out for |
| --- | --- | --- | --- |
| Schemes and insurance (screen 22) | Lists government schemes and insurance relevant to the farmer's crops and district, with deadlines as tasks and a record of applications | Scheme content as templates with source and "last checked" date; `scheme_applications` | Content goes stale fast and wrong information costs farmers money: show the source and date, link to the official page, and name who keeps it current |
| Documents | Stores land records, lease papers, soil reports, bills and certificates against a farm, plot or loan | `documents` with the photo queue from section 12 | Sensitive papers: private by default, never shared with organisations unless chosen, excluded from any model training |
| Equipment | Machines and tools, service due dates, fuel and repair costs, hire in and hire out | `equipment`, `equipment_logs`; costs post as expenses, hire income as other income | Depreciation reuses phase 10 assets; do not build it twice |
| Livestock | Animals or groups, feed, health, milk or egg output, sales | `livestock_units`, `livestock_events`, output as lots so selling and profit reuse phase 1 | A large area on its own; scope tightly to what pilot farmers keep |
| Custom records | The farmer or organisation defines their own form (fields from a fixed set of types) for anything not covered | `custom_forms`, `custom_entries` with values in a JSON column | Keep field types few; custom data appears in history and export but not in profit and loss |
| Community and case studies (screen 21) | Posts, questions, local case studies, shop rates shared by farmers | `posts`, `comments`, `reports`; online only, cached for reading offline | Needs moderation, a reporting path and clear rules before launch; unvetted farming advice can cause real harm, so label farmer posts as opinion and keep expert content separate. Launch only with a named moderator |

**Tasks:** one docs task and two to four build tasks per module, numbered L1 onward when the
module is chosen.

**Exit check per module:** its acceptance checks pass, it can be switched off cleanly, and all
section 14 budgets still hold with its data added to the benchmark seed.

### What stays out until there is evidence

- Payments inside the app, marketplace or buyer matching, and credit scoring. Each brings
  regulatory duties and changes what the app is; decide only with legal advice and partner
  demand.
- More languages. The localisation setup supports them, but each needs its own templates and
  native review, not only translated strings.

---

## 12. Local database and offline performance

The local database is what every screen reads, so its speed is the app's speed.

### Opening the database

- Run the database on a background isolate so queries never block the interface thread. Use
  the setup Drift's current docs recommend for Flutter.
- At open: write-ahead logging on, synchronous set to normal, foreign keys on, a busy timeout,
  and a moderate cache size. Verify each setting took effect in a test.
- One database connection for writes. Add read isolates only if measurements show reads
  waiting behind writes.

### Column types

- Money: integer paise. Never floating point.
- Quantities: fixed-point integers (thousandths of the unit) so sums are exact.
- Dates of work (`work_date`, `spent_on`): stored as a sortable day value, separate from
  timestamps, so day and month ranges use an index.
- Ids: UUID text. Generate time-ordered UUIDs (version 7) on the device so new rows land at the
  end of indexes instead of at random places.

### Indexes (create with the tables, check with the query plan)

| Table | Index | Serves |
| --- | --- | --- |
| every entry table | `(farm_id, <date column>, id)` | Day and period lists |
| every entry table | `(crop_cycle_id, <date column>)` | Plot and crop totals, profit and loss |
| `labour_entries` | `(worker_id, work_date)`, `(group_id, work_date)`, `(harvest_id)` | Balances, "same as yesterday", harvest teams |
| `labour_payments` | `(worker_id, paid_on)`, `(group_id, paid_on)` | Balances |
| `expense_allocations` | `(expense_id)`, `(crop_cycle_id)` | Splits and crop costs |
| `labour_allocations` | `(labour_entry_id)`, `(crop_cycle_id)` | Splits and crop costs |
| `lot_costs` | unique `(lot_id)` | Lot cost and sale profit |
| `lots` | `(crop_cycle_id)`, and a partial index on lots with stock left | Selling from stock |
| `sale_lots` | `(sale_id)`, `(lot_id)` | Sales and lot history |
| `event_log` | `(farm_id, occurred_on, created_at, id)`, `(entity, entity_id, created_at)` | Diary and timelines |
| `outbox` | `(status, created_at)` | Upload queue |
| `crop_cycles` | `(plot_id, status)` | Plot screens |

Most lists show only rows that are not deleted; where the database supports it, make these
partial indexes on `deleted_at is null`.

For every list and total query, add a test that asserts the query plan uses an index and does
not scan the whole table.

### Query rules

- **Totals in SQL.** Sums and groupings run in the database. Never load rows into Dart to add
  them up.
- **Keyset pagination.** Long lists (History, entries) page by "rows after this date and id",
  about 50 at a time. Never use a growing offset.
- **No query inside a loop.** One query per screen section, with joins or a batched `in` list.
- **Narrow streams.** A watched query should cover only what its widget shows, so a write to
  one table does not re-run every stream on screen. Debounce streams that feed charts.
- **Totals are derived first, cached only if needed.** Start with aggregate queries on good
  indexes. Add a summary table (for example per crop cycle per month) only if a budget in
  section 14 is missed with the seed loaded, and then update it inside the same transaction as
  the entry.
- **Batch writes.** Any multi-row write (set-up, harvest with teams, applying pulled rows) is
  one transaction using batch inserts.

### Search

- Store a normalised search text per searchable row: Malayalam name, English name and a
  Manglish transliteration, lower-cased. Phase 1 lists are small enough for a prefix match on
  an indexed column. Add full-text search only if a list grows past what that handles.

### Event log growth

- Changed fields only for updates (B4). Paginate. Keep everything locally for the current and
  previous two seasons; older events stay on the server and are fetched on demand when the
  farmer scrolls that far back. Decide this cut-off with the owner before B7.

### Photos

- Resize on the device (longest side about 1600 px) and compress before saving. Keep a small
  thumbnail for lists.
- Photos upload from their own queue, separate from data sync, so a large photo never delays
  the entries. Offer "upload photos on Wi-Fi only".

### Migrations and safety

- Every schema change has a migration and a migration test from each earlier version.
- Before a migration runs on a farmer's phone, copy the database file; delete the copy only
  after the app has opened successfully on the new version.
- Run an integrity check after a crash during a write, and periodically; if it fails, keep the
  file, tell the user plainly, and restore from the server.

### Storage budget

- With the benchmark seed loaded, the database file should stay under 60 MB. Report the size
  in the B2 pull request and again at D1.

---

## 13. Sync and server performance

### Upload (outbox)

- **Coalesce before sending.** If a row was edited five times offline, send one upsert with the
  final state. The event log still carries all five changes.
- **Order by dependency.** Farms, then members and invites, a farmer's own crops, template
  overrides, plots, crop cycles, parties, workers and groups, then entries (harvests, labour,
  expenses, notes, tasks, local prices, price alerts), then lots and lot costs, then sales and
  sale lots, then
  allocations and payments, then event log.
- **Batches.** About 200 rows or 256 KB per request, whichever comes first. Tune with
  measurements on a slow connection.
- **One server function per batch**, running in one transaction: it checks permissions, applies
  the conflict rules, and returns the accepted rows and any conflicts. This replaces many small
  requests and keeps a batch all-or-nothing.
- **Idempotent.** Rows are keyed by their device-generated id, and each batch carries its own
  id. Sending the same batch twice changes nothing.
- **Retry.** Exponential backoff with random jitter, capped. A permanent rejection (permission,
  validation) is moved out of the queue and surfaced to the user; it must not block later rows.

### Download (pull)

- **Cursor per table on a server-assigned sequence.** Add a `server_seq` column filled from a
  sequence by a trigger on every insert and update. The device pulls "rows with `server_seq`
  greater than my cursor, ordered by `server_seq`, limit N" and stores the last value. This
  avoids missed rows from clock differences, which a timestamp cursor is prone to.
- Take care with rows committed out of order at the moment of the pull; the usual remedy is to
  pull only up to a safe point slightly behind the newest value. Design and test this
  explicitly in B7.
- Deleted rows travel as normal rows with `deleted_at` set.
- Apply each page inside one local transaction, in dependency order.
- Send only the columns the app uses.

### When sync runs

- A few seconds after a local write (debounced), when the app comes to the foreground, when
  connectivity returns, and periodically in the background. Skip or defer on very low battery.
- No realtime subscriptions in phase 1. Pull on the triggers above is enough and far cheaper
  on battery and data.

### Conflicts

- Detect with the device-owned `version`: the upload carries the base version N (the last
  version this device received from the server) with the new row, so "I changed version N"
  holds however many local edits were coalesced. If the server row is still at N, accept. If
  not, compare changed fields: different fields merge; on the same field the upload that reaches the
  server later wins (server order, never the device clock); money and quantity fields, and a
  delete against an edit, go to the user. A new row whose parent was deleted on another device
  also goes to the user. Two changes that set a field to the same value are not a conflict.
- Settling a conflict is the one case where the server sets `version`: any row it writes after
  a conflict (a merge, or a same-field change accepted over another device's) is stored at the
  highest version seen plus one and returned, so no two different row states share a version.
- Stock is a special case: two devices selling from the same lot offline can oversell. The
  server function detects it and returns a conflict for the user to settle.

### First sync and restore on a new phone

- Pull master data and the current season first, so the app is usable within seconds; then
  older seasons in the background with a quiet progress line in Settings.

### Server schema for speed

- Index `(farm_id, server_seq)` on every synced table (`owner_farm_id` on `crops`), and
  `server_seq` alone on master data with no farm.
- Index `farm_members (user_id)` and every column a policy filters on.
- Keep the indexes that serve reports small in number; this server mostly stores and relays,
  the phone does the reporting.

### Row-level security

Supabase's guidance for fast policies, to follow in B1:

- Call auth functions as `(select auth.uid())` inside policies so the value is computed once
  per statement, not once per row.
- Index the columns that policies compare against.
- Name the role on every policy (`to authenticated`).
- Keep membership lookups in security-definer functions and call those wrapped in `select` too.
- Add the farm filter in the query as well as relying on the policy.

Role rules to encode (D3 then only verifies them), as listed in `product-spec.md` rule 7:
supervisor cannot read money tables (including parties and lot cost) or profit, and its read of
`event_log` leaves out rows whose entity is a money table; supervisor writes daily work
(labour allocations included), workers and groups; lot costs are money; set-up records are written by owner and manager; accountant can read everything and
write money entries but not daily work entries; viewer cannot write; per-person `permissions`
override the role defaults. Roles are per farm.

Check policies with `explain analyze` on a seeded local instance, as a signed-in user, before
B1 is called done.

---

## 14. App performance budgets and how to measure them

**Test phone.** Pick one low-end Android phone typical of the pilot district (the owner
decides; something with 2 to 3 GB of memory). All numbers are measured on it, in a profile or
release build. Debug-build numbers do not count.

**Benchmark seed (task A6).** One farm, three years: 8 plots, 20 crop cycles, 40 workers,
10 groups, about 15,000 labour entries, 6,000 expenses with allocations, 1,500 harvests and
lots, 1,200 sales, and the roughly 50,000 event-log rows these produce.

| Budget | Target |
| --- | --- |
| Cold start to usable Home | under 2.5 s |
| Open any entry screen | under 300 ms |
| Save an entry (tap to toast) | under 150 ms |
| Any list or dashboard query, seed loaded | under 50 ms |
| Profit and loss for a full season, seed loaded | under 150 ms |
| Scrolling History, seed loaded | no dropped frames worth noticing; 99th-percentile frame under 16 ms |
| Taps to save a typical entry | 6 or fewer after opening the add sheet |
| Download size per CPU type | under 30 MB |
| Database file, seed loaded | under 60 MB |
| Sync of one day's entries on a slow mobile connection | under 5 s, in the background |
| First sync on a new phone to usable | under 10 s for the current season |

These are starting targets. If the test phone cannot meet one, report the measured number and
the reason, and let the owner decide whether to change the design or the target.

**How to measure.**

- Query timings: a benchmark test that loads the seed and times each repository query. Runs on
  the device for release decisions and in CI to catch large regressions.
- Frames and start-up: Flutter's performance tools in profile mode on the test phone, and an
  integration test that scrolls History and opens each entry screen while recording frame times.
- App size: the size analysis output of a release build. Record it in every phase's last pull
  request.

**Interface rules that keep it fast.**

- `const` constructors wherever possible; small widgets rather than large `build` methods.
- Lists are built lazily, with a fixed item height where the design allows.
- A provider exposes only what its widget needs; select single fields rather than whole
  objects, so typing an amount does not rebuild the screen.
- Animate with transforms and opacity on small subtrees. No animation of layout on long lists.
  Isolate animated parts so the rest of the screen is not repainted.
- Nothing heavy on the interface thread: export, image resizing, large JSON encoding and the
  database all run off it.
- Load the first screen first: defer anything Home does not need (templates for other screens,
  price history, old seasons) until after the first frame.
- Decode images at the size they are shown.
- Respect "reduce motion": all motion in the tokens is switched off.

---

## 15. UI and UX quality bar

The prototype is the visual reference and `design-tokens.md` is the source of values. "Best"
here means a farmer with little app experience can record a day's work quickly, in Malayalam,
outdoors, on a cheap phone, without fear of losing or breaking anything.

### Checklist for every screen (goes in the pull request)

**States**

- [ ] Empty state says what the screen is for and offers the first action.
- [ ] Offline looks identical to online. No spinner, no "no connection" wall (except the first
      sign-in and first sync, `CLAUDE.md` rule 1).
- [ ] Read-only state (closed season, or a role that cannot write it) is clear and explains why;
      what the role cannot open is hidden.
- [ ] Errors say what happened and what to do, in plain Malayalam, next to the field.
- [ ] Long content, many items and zero items all look right.

**Speed of entry**

- [ ] Opens with the most likely field focused and the right keyboard (numeric for amounts).
- [ ] Defaults filled: today, last plot, last rate, most used category first.
- [ ] "Last time" hint shown where the spec asks for it.
- [ ] Typical entry saved within the tap budget.
- [ ] Save shows a toast with undo; undo really restores the previous state.
- [ ] Leaving a half-filled form asks once, or keeps a draft.

**Touch and layout**

- [ ] Every target at least 48 dp, with spacing so neighbours are not hit by mistake.
- [ ] Main action reachable with one thumb, and never hidden under the keyboard.
- [ ] No text clipped or overlapping in Malayalam, in large-text mode, or at the system's
      largest font size.
- [ ] Works on a small screen (about 360 dp wide) without horizontal scrolling.

**Language and numbers**

- [ ] All text from ARB keys, Malayalam and English both present.
- [ ] Amounts in Indian grouping with tabular figures; units always shown.
- [ ] Dates show the Malayalam month where the design does.

**Accessibility**

- [ ] Contrast at least 4.5:1, checked outdoors on the test phone at low brightness.
- [ ] Every icon button has a label for screen readers; reading order is sensible.
- [ ] Colour never the only signal: income and expense carry a sign or label.
- [ ] Motion off when the system asks for reduced motion.

**Trust**

- [ ] Computed values show how they were worked out and can be edited by hand.
- [ ] Overridden values are marked and can be reset.
- [ ] Destructive actions are undoable instead of asking "are you sure?" wherever possible.

### Automated UI checks

- Golden tests per screen in four variants: Malayalam, English, Malayalam with large text, and
  the empty state.
- A test that pumps each screen at the largest text scale and fails on any overflow.
- A test that every tappable widget meets the minimum size.
- Screenshots of each finished screen beside the prototype screen in the pull request.

### Owner and farmer review

- At each phase checkpoint the owner uses the build on the test phone, outdoors, and records a
  real day's entries.
- In phase 6, farmers are observed, not interviewed: note where they stop, mis-tap, or ask.
  Each observation becomes a backlog item with the screen and step.

---

## 16. Code review process

Three layers: automated gates, a self-review, and an independent review. The owner reviews on
the phone, not line by line.

### Gates (task A6; run locally and in CI on every pull request)

| Gate | Fails when |
| --- | --- |
| `dart format` | Any file is unformatted |
| `flutter analyze` | Any issue, with the strict options from A1 |
| `flutter test` | Any unit, widget, golden or migration test fails |
| String check | A user-facing string literal appears in `lib/` outside `l10n/` |
| ARB check | Keys differ between `app_ml.arb` and `app_en.arb`, a key lacks a description, or placeholders differ |
| Token check | A colour literal or font name appears outside the theme and tokens files |
| Layering check | `ui/` imports Drift or Supabase; `domain/` imports Flutter, Drift or Supabase; anything outside `core/sync` and auth imports Supabase |
| Write-path check | An insert, update or delete on a synced table happens outside `writeWithHistory` |
| Query-plan tests | A listed query scans a whole table |
| Benchmark test | A query exceeds twice its budget (CI machines differ from phones, so the margin is wide) |
| Schema check | `supabase/migrations` and the Drift schema disagree on a synced table's columns (apart from the server-only `server_seq`) |

Keep the checks as small scripts in `tool/` so they run the same way locally and in CI.

### Self-review (the author fills this in on every pull request)

1. Which backlog task and which screen sections this covers.
2. The acceptance checks, each mapped to a test name.
3. The eight non-negotiable rules in `CLAUDE.md`, each answered "met" with where, or "not
   applicable" with why.
4. The screen checklist from section 15.
5. Measured numbers against section 14.
6. Anything guessed, skipped or left for later, stated plainly.

### Independent review

Run in a **fresh session** that has not seen the implementation being written, so the work is
not marking itself. Prompt:

```
Review the diff of branch <name> against main. You did not write this code.
Read CLAUDE.md, docs/implementation-plan.md sections 12 to 16, and the
sections of docs/screens.md and docs/product-spec.md for task <ID>.

Report, most serious first:
1. Wrong results: any calculation that does not match the worked examples
   or mishandles rounding, zero, empty or very large values.
2. Data safety: any write that skips the event log or outbox, any hard
   delete, any path that could lose or duplicate data on sync.
3. Offline: anything that waits on the network or fails without it.
4. Privacy: any way one farm or role could read another's data.
5. Performance: queries in loops, unindexed queries, whole-screen rebuilds,
   work on the interface thread.
6. UI and UX: items on the section 15 checklist that are not met.
7. Tests that would still pass if the feature were broken.

For each finding give the file and line, a concrete failing example, and the
smallest fix. Do not report style preferences.
```

Fix every finding in categories 1 to 4 before merging. Categories 5 to 7 are fixed or recorded
as backlog items with the owner's agreement.

**Second reviewer for the risky tasks.** B1 (security rules), B4, B7 and C6 (stock) get the
independent review twice, the second with the question "how could this lose or expose a
farmer's data?" only.

### Commit and merge rules

- Small commits, described by what changed for the farmer.
- A pull request merges only with gates green, self-review filled in, and independent review
  findings resolved.
- `main` always builds and runs.

---

## 17. Risks and open questions

| Risk | Why it matters | What to do |
| --- | --- | --- |
| SMS OTP delivery in India | Commercial SMS in India needs sender and template registration under the telecom regulator's rules; Supabase needs a third-party SMS provider configured. Unregistered messages may not arrive. | Phase 1 signs in with Google; phone OTP is task D6. Choose the provider and start registration during the foundation phase (section 5), well before D6. Check current Supabase and provider docs. Budget for per-message cost. |
| Price data licensing | "Live prices" depends on a source that may not permit reuse. | C11 ships with manual entry; integrate a source only after written confirmation. |
| Malayalam rendering and wording | Clipped conjuncts or wrong farming terms destroy trust quickly. | Golden tests from A4; native-speaker review at D2; test on the low-end phone throughout. |
| Sync correctness | The hardest part; errors here lose data silently. | Two-device harness in B7, soak test in D1, double review. |
| Overselling stock offline | Two devices can sell the same lot. | Server-side check and a user-facing conflict (section 13). |
| Local data loss before first sync | A phone lost before syncing loses that data. | Sync soon after writes when online; show "items waiting to sync" in Settings. |
| App size from fonts | Three font families with Malayalam glyphs are heavy. | Measure in A2; drop weights or a family if the budget is missed. |
| Hosted database limits | Plan limits (pausing, storage, connections) differ by tier and change over time. | Check the current terms of the chosen plan before beta. |
| Scope growth | The spec lists many later modules. | Phase 1 scope is fixed by `docs/phase-1-tasks.md`; anything else waits for phases 7 to 13. |

Open questions for the owner beyond phase 0: weather data source for the Home card; whether
crash reporting is allowed in the beta. How long history stays on the phone is in the owner
decision table (section 4).
