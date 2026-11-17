# Thottam product spec (condensed)

Full plan with business, content and roadmap detail: https://claude.ai/artifact/VfapWCaXRc3absDQQsPk5U
Interactive screens: https://claude.ai/artifact/PLuCg99aYUjk6cHCFVxY3d

## Users

Smallholders (under 2 acres, mixed crops), plantation owners (rubber, pepper, cardamom, coconut, arecanut), farm managers and supervisors, family members (read-only), accountants (money entries only). Later: FPOs and officers.

## Cross-cutting rules

1. **Data spine.** Every transaction carries farm, plot, crop cycle and date, so costs and yields roll up to profit per plot, crop and season.
2. **History of everything (main feature).** Each plot, crop cycle, tree, worker, group, input, buyer, lot and loan has a timeline. A farm diary shows all events by day with filters. Entry screens show "last time" hints. Every edit and delete is kept with old and new values and can be restored. Closed seasons and sold plots stay in the archive.
3. **Override model.** App default → farm → plot or crop → single entry; the most specific wins. Lists, units, rates, calendars, doses, formulas, forms, modules, reminders and report rules are all editable. Overridden values are marked and can be reset.
4. **Templates.** Per-crop predefined lists (activities, calendar, inputs, expense categories, units and grades, process steps and ratios, labour tasks and rates, diseases, sale grades). Three levels: app admin, organisation admin, farmer. Admin updates never overwrite a farmer's changes; they arrive as "update available". Templates are versioned.
5. **Offline first.** All features work without network; sync by outbox with per-record versions. Different fields merge; same-field conflicts take the change the server accepted last (server order, not the phone's clock), except money and quantity, which ask the user.
6. **Languages.** Malayalam, English, or mixed. Mixed means a Malayalam interface with crop, category and unit names shown in Malayalam followed by English. Digits are always Latin, in every language setting. Search works in Malayalam script, English and Manglish. Local units (cent, acre, para, kg, quintal) with custom conversions. Malayalam calendar alongside Gregorian.
7. **Roles.** Owner, manager, supervisor, accountant, viewer. Defaults:
   - Owner: reads and writes everything, including members and permissions.
   - Manager: reads and writes everything except members and permissions.
   - Supervisor: records daily work (labour attendance, harvest, inputs, tasks, notes) and sees the wages on those entries. Cannot open money (expenses, payables, sales, receivables, labour payments and balances, other income, loans) or profit and loss.
   - Accountant: reads everything; writes money entries, not daily work.
   - Viewer: reads everything; writes nothing.
   The owner can change any permission per person.
8. **Rounding.** Calculations keep full precision; values are rounded only for display, to one decimal for quantities and to whole paise for money. A stored amount (quantity × rate, half-day wage, percentage share) is rounded once to whole paise when it is saved, half away from zero; per-unit and per-person figures are never stored. When an amount is split (crop cycles, teams, people), each part gets its rounded-down share in paise, then the leftover paise go one at a time to the parts with the largest fractional remainders; ties go to the part listed first. The parts always sum to the original amount.
9. **Lot cost.** A lot's cost is every cost posted to its crop cycle after the cycle's previous harvest (or from the cycle's start, for the first harvest) up to and including this harvest, this harvest's wages included, divided by the quantity harvested. It is editable on the lot. A sale that draws from several lots uses the average cost weighted by the quantity taken from each lot.

## Modules

### Land and crops
Farms → plots → crop cycles. Area in cent, acre, hectare. Ownership: owned, leased, shared. Mono, mixed and intercrop on one plot with area share or plant count. Seasonal, annual and perennial crops; perennials carry planting year. Optional per-tree tracking. Seasons (Virippu, Mundakan, Puncha, custom). Editable crop calendar generating tasks.

### Labour
Three ways to record, mixed freely on one day:
- **Named worker:** profile, skill, wage type, default rate, attendance (full, half, absent, overtime), task, advances, balance.
- **Unnamed group:** label, head count per rate class, rate per head or lump sum, hours, task, plot, crop, amount, who was paid. Created in one line, no profiles.
- **Named group:** leader, usual size, default rates, optional members, group ledger.
An unnamed group can later be named or have members added without losing records. Wage types: daily, hourly, piece rate, contract, monthly. Half-day is an attendance value (0.5 of the daily rate), not a wage type. Overtime is a full day plus extra hours at the worker's overtime rate per hour (from templates, editable on the entry). Payments: advance, part payment, settlement, bonus, deduction. Wage cost posts to the crop cycle worked on.

### Expenses
Categories from templates. Entry by amount with defaults for date, plot and category. Payment mode: cash, UPI, bank, credit (creates a payable). Split across crop cycles by area, plant count, equal share or custom percentages (editable). Recurring and capital expenses. Budget per crop cycle.

### Inputs and stock
Purchases add stock, applications deduct. Application log: item, quantity, method, plot, crop, worker, cost. Low-stock and expiry alerts. Soil test records. After a spray, a safe-to-harvest countdown and a warning if harvest is logged inside it.

### Harvest
One harvest entry: plot, crop cycle, date, unit, grade, and **any number of teams**. A team is an unnamed group, a named group or a named worker. Each group has one common rate per head; rates differ between teams and are editable on the entry. Per-team quantity is optional:
- on: each team has a quantity; total = sum; show per-team quantity per person, labour cost per unit, wages;
- off: enter the total only; show overall quantity per person and cost per unit.
Piece-rate teams (per kg, per nut, per tree) can sit beside daily-rate teams. Each harvest creates a lot. The app keeps harvest-rate history and estimates labour needed (people, days, wage budget) from past rates; every estimate is editable.

### Processing
Batch: input lots → steps (from template) → output lots, with weight in and out, conversion ratio, loss and processing cost. Storage location and stock ageing. Lot traceability back to plot and harvest.

### Selling and prices
Sell from one or more lots: buyer, quantity, grade, rate, deductions (commission, weighing, loading, transport, quality cut), net amount, payment mode and status, part payments, advance. Part sale leaves the rest in stock. Buyer book with ledger. Profit at sale: net amount per sale unit (after deductions) minus lot cost per unit (rule 9), shown before saving, with the deductions line visible so the farmer sees why it is below the rate.
Prices: latest published price per crop and grade with source and time, market comparison, history chart, alerts, stock valued at today's price, locally entered shop rates shown separately. Official sources publish daily, so "live" means latest published.

### Money
Income (sales and other), expenses, receivables and payables, loans with schedules. Profit and loss by farm, plot, crop, season or period, with switches for family labour, own inputs, depreciation and loan interest. Cost per acre and per kg, break-even price, cash flow by month. Export to PDF and Excel.

### Diseases and remedies
A disease record: several photos, crop, plot, affected part, severity, area affected, note. From the record the farmer can see suggested remedies (library content, organic and chemical, label doses only) and/or send it to an expert in one tap. Status: open, awaiting expert, treated, resolved. Treatment, cost, follow-up photos and outcome are added later; the expert's reply is stored on the record. The farmer can correct a suggested diagnosis. A remedy can become a task.

### Later modules
Community and case studies, schemes and insurance, documents, equipment, livestock, custom records, voice entry, bill scan, photo diagnosis, web dashboard.

## Worked examples (use these as unit tests)

- **Expense split:** ₹3,600 on a plot with coconut 60%, pepper 30%, banana 10% → ₹2,160, ₹1,080, ₹360.
- **Attendance:** rates 900, 900, 700, 900 with full, full, half, absent → ₹2,150.
- **Overtime:** daily rate ₹900, full day plus 2 hours at ₹150 per hour → ₹1,200.
- **Unnamed group:** 5 at ₹800 and 1 at ₹1,200 → ₹5,200.
- **Harvest, per-team quantity on:** Group A 6 people at ₹800 with 75 kg; Group B 3 at ₹900 with 30 kg; one named worker at ₹1,000 with 15 kg → total 120 kg, wages ₹8,500, Group A 12.5 kg per person and ₹64 per kg, overall 12 kg per person and ₹70.83 per kg (8,500 / 120 = 70.833…, shown to whole paise).
- **Lot cost:** costs posted to the crop cycle since its previous harvest ₹20,060, plus this harvest's wages ₹8,500 → ₹28,560 over 120 kg = ₹238 per kg (the lot in the sale example).
- **Lot cost, sale from two lots:** 30 kg from a lot at ₹238 per kg and 20 kg from a lot at ₹250 per kg → (7,140 + 5,000) / 50 = ₹242.80 per kg.
- **Sale:** 50 kg at ₹705 with ₹170 deductions → gross ₹35,250, net ₹35,080; net per kg ₹701.60; with lot cost ₹238 per kg, profit per kg ₹463.60.
- **Split rounding:** ₹100 split equally across three crop cycles → ₹33.34, ₹33.33, ₹33.33 (10,000 paise: 3,333 each, the leftover paisa goes to the first listed).
- **Stored amount:** 12.5 kg at ₹64.33 → 80,412.5 paise, stored as ₹804.13.
- **Processing:** 100 kg in, 33 kg out → ratio 33%, loss 67 kg.
- **Profit and loss:** income 92,000 + 68,500 + 24,000 = ₹1,84,500; expense 31,000 + 44,200 + 21,000 = ₹96,200; profit ₹88,300. With family labour (5,000 + 4,000 + 3,000) included: expense ₹1,08,200, profit ₹76,300.
