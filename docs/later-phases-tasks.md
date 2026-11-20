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
  2"), template release 3 (input methods, soil parameters), strings.
- [ ] E2. Domain, pure functions with the spec's worked examples as tests: stock on hand,
  running average cost (with edited costs and stock below zero), safe-to-harvest date and
  days left, low stock, expiry (oldest used first).
- [ ] E3. Items, purchases and the stock list (19, 19a, 19c): a purchase saves its expense and
  movement in one `writeWithHistory`; an expense made by a purchase opens as it; adjust stock;
  Inputs page switch and More tile; benchmark seed extended with items, purchases and
  applications, every budget re-run; query-plan tests for the stock queries.
- [ ] E4. Applications and cost posting (19b): found-stock offer; edited costs; quick add tile
  and plot detail button; profit and loss leaves purchases out, counts applications and
  adjustments out, and shows stock on hand; History filter and titles.
- [ ] E5. Safe to harvest and alerts: countdown on 19 and plot detail, harvest banner and
  reason, Low, Expires soon, Expired and Check stock tags.
- [ ] E6. Soil tests (19d), with the photo once the package is chosen.

Exit check (plan section 11): a scripted season with purchases and applications gives the
expected stock, crop costs and safe dates; profit and loss matches the phase 1 result plus
input costs.

### Open for the owner (phase 7)

Answer in the E1 review; the build tasks follow the answers.

1. When an input's cost reaches a crop: at use (proposed, as the plan recommends) or at
   purchase.
2. Average cost: the running weighted average in `product-spec.md` Inputs rule 5, with found
   or opening stock coming in at no value (proposed), or at the current average.
3. One crop per application (proposed), or splitting one application across a mixed plot's
   crops by their shares.
4. Whether the harvest warning stays when the Inputs page is switched off (proposed: yes, it
   is safety information).
5. Waiting periods and label doses: who reviews them and from which source (product labels,
   Kerala Agricultural University, the agriculture department). Until then the templates carry
   none and the farmer enters the period from the label, with its source.
6. Millilitre: pesticides are measured in ml, which is not in the standard units decided on
   2026-11-19. Add `ml` (0.001 litre)? Until then 250 ml is entered as 0.25 litre.
7. Expiry warning window: 30 days (proposed), changeable per farm.
8. A package for the soil test photo (camera or gallery picker, and image compression): which
   one, if any. E6 ships without the photo until then.
