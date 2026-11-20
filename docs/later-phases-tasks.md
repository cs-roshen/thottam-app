# Later phases backlog

Implementation plan section 11. Work in order; one task per branch and pull request, each
following the task loop in section 1 and the "Rules for every later module" in section 11.
Tick a task only when its checks pass.

## Owner decision (2026-11-20)

Start phases 7 (inputs and stock), 8 (processing), 9 (crop doctor), 11 (voice and bill scan),
12 (organisations and web dashboard) and 13 (community, schemes, documents, equipment,
livestock, custom records) now, ahead of the closed beta that the plan had them follow. Phase
10 (full money: loans, budgets, recurring and capital costs, cash flow) is not wanted yet.
Phase 1 group D (release readiness) carries on beside them.

Each phase starts with one docs pull request (rules and worked examples in
`product-spec.md`, screens and checks in `screens.md`, tables in a new migration and the
Drift schema with a migration test, strings in both ARB files, and its tasks here). The owner
reviews it before the phase's build tasks start.

## E. Phase 7: inputs and stock

- [ ] E1. Docs, schema and strings: `product-spec.md` Inputs and stock, `screens.md` screen 19,
  migration `0007_inputs_stock.sql` with `supabase/tests/e1_inputs.sql`, Drift schema 2 with
  the copy-before-upgrade and integrity check (the review follow-up "before schema version
  2"), template release 3 (input methods, soil parameters, ml), strings. Merged in #30; the
  owner's answers below follow in a second pull request. The server tests wait for the CLI
  sign-in to Thottam-App.
- [ ] E2. Domain, pure functions with the spec's worked examples as tests: stock on hand,
  safe-to-harvest date and days left (from days or a picked date), low stock, expiry (oldest
  used first, only purchases with an expiry date).
- [ ] E3. Items, purchases and the stock list (19, 19a, 19c): a purchase saves its expense
  (with the expense screen's plot and crop split) and its movement in one `writeWithHistory`;
  an expense made by a purchase opens as it; adjust stock; Inputs page switch and More tile;
  benchmark seed extended with items, purchases and applications, every budget re-run;
  query-plan tests for the stock queries.
- [ ] E4. Applications (19b): found-stock offer; dose and waiting period (days or date) with
  their defaults; quick add tile and plot detail button; History filter and titles.
- [ ] E5. Safe to harvest and alerts: countdown on 19 and plot detail, harvest banner and
  reason, Low, Expires soon, Expired and Check stock tags.
- [ ] E6. Soil tests (19d) with the report photo: add `image_picker` at its current stable
  version (checked on pub.dev then), made smaller with its own `maxWidth` and `imageQuality`
  options; a storage bucket and policies for farm photos in a new migration (phase 9 uses the
  same); upload from the outbox when online.

Exit check (plan section 11): a scripted season with purchases and applications gives the
expected stock and safe dates; profit and loss matches the phase 1 result plus the purchases.

### Owner answers (phase 7, 2026-11-20)

1. **When an input's money counts:** when it is bought. The purchase is an expense like any
   other, on its date and crops; a use carries no cost (Inputs rule 4).
2. **Which price a use carries:** none. A purchase records its cost and quantity; a use takes a
   quantity from the item's stock without naming a purchase or lot (Inputs rule 4). So there
   is no average cost, no edited cost and no stock value: `input_application_costs` is gone
   from 0007.
3. **Mixed plot:** one crop per application (Inputs rule 5).
4. **Harvest warning with the Inputs page off:** it still shows (Inputs rule 11).
5. **Waiting periods and doses:** the farmer chooses them. The app ships none and asks for no
   source (Inputs rule 7): `input_items.waiting_source` is gone from 0007 and
   `input_applications.dose` holds the dose as the farmer writes it.
6. **Millilitre:** both ml and litre. `ml` (0.001 litre) is a standard unit in template
   release 3.
7. **Expiry warning:** 30 days, only when an expiry date is recorded (Inputs rule 8).
8. **Photo packages:** approved, at stable versions. Only `image_picker` (Flutter team) is
   needed: on Android and iOS it resizes and recompresses the photo itself, so no separate
   compression package is added. E6 adds it; the crop doctor (phase 9) uses the same.
