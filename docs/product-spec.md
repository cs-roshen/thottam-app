# Thottam product spec (condensed)

Full plan with business, content and roadmap detail: https://claude.ai/artifact/VfapWCaXRc3absDQQsPk5U
Interactive screens: https://claude.ai/artifact/PLuCg99aYUjk6cHCFVxY3d

## Users

Smallholders (under 2 acres, mixed crops), plantation owners (rubber, pepper, cardamom, coconut, arecanut), farm managers and supervisors, family members (read-only), accountants (read everything, write money entries). Later: FPOs and officers.

## Cross-cutting rules

1. **Data spine.** Every transaction carries farm, plot, crop cycle and date, so costs and yields roll up to profit per plot, crop and season.
2. **History of everything (main feature).** Each plot, crop cycle, tree, worker, group, input, buyer, lot and loan has a timeline. A farm diary shows all events by day with filters. Entry screens show "last time" hints. Every edit and delete is kept with old and new values and can be restored. Closed seasons and sold plots stay in the archive. Deleting a plot or crop cycle asks first and keeps its entries, shown under the deleted plot or crop cycle.
3. **Override model.** App default → farm → plot or crop → single entry; the most specific wins. Lists, units, rates, calendars, doses, formulas, forms, modules, reminders and report rules are all editable. Overridden values are marked and can be reset.
4. **Templates.** Per-crop predefined lists (activities, calendar, inputs, expense categories, units and grades, process steps and ratios, labour tasks and rates, diseases, sale grades). Three levels: app admin, organisation admin, farmer. Admin updates never overwrite a farmer's changes; they arrive as "update available". Templates are versioned.
5. **Offline first.** All features work without network; sync by outbox with per-record versions. Different fields merge; on the same field the upload that reaches the server later wins (server order, not the phone's clock), except money and quantity, which ask the user. A delete on one phone against an edit on another also asks the user, and so does a new record on one phone under a record deleted on another (labour on a crop cycle deleted elsewhere). Two changes that set a field to the same value are not a conflict.
6. **Languages.** Malayalam, English, or mixed. Mixed means a Malayalam interface with crop and category names shown in Malayalam followed by English. Units and numbers are always in English with Latin digits, in every language setting (50 kg, 2.5 acre, 3 quintal, ₹1,84,500). Search works in Malayalam script, English and Manglish. Standard units only (kg, quintal, litre, cent, acre, hectare and counts such as nuts or bunches), with the farmer's own conversion ratios; no traditional local measures. Malayalam calendar alongside Gregorian.
7. **Roles.** Owner, manager, supervisor, accountant, viewer. Defaults:
   - Owner: reads and writes everything, including members and permissions.
   - Manager: reads and writes everything except members and permissions.
   - Supervisor: records daily work (labour attendance, harvest, inputs, tasks, notes), adds and edits workers and groups, and sees the wages on those entries. Cannot open money (expenses, payables, sales, receivables, labour payments and balances, other income, loans, buyers and vendors, lot cost) or profit and loss, nor the history of those records.
   - Accountant: reads everything; writes money entries, not daily work.
   - Viewer: reads everything; writes nothing.
   - Set-up records (plots, crop cycles, workers, groups, My lists, farm settings): owner and manager write them, a supervisor also writes workers and groups, and everyone else reads them. Buyers and vendors and lot cost count as money.
   Roles are per farm: one account can belong to several farms, with a different role on each. The owner can change any permission per person.
8. **Rounding.** Calculations keep full precision; values are rounded only for display, to one decimal for quantities and to whole paise for money, half away from zero. A stored amount (quantity × rate, half-day wage, a percentage of one amount such as a commission) is rounded once to whole paise when it is saved, half away from zero; per-unit and per-person figures are never stored. A computed quantity (after a unit conversion, for example) is stored to thousandths of its unit, half away from zero. When an amount is split (crop cycles, teams, people, by share or by percentage), each part gets its rounded-down share in paise, then the leftover paise go one at a time to the parts with the largest fractional remainders; ties go to the part listed first. The parts always sum to the original amount. Parts of a split always follow this split rule, never the half-away rule.
9. **Lot cost.** A lot's cost is every cost posted to its crop cycle after the cycle's previous harvest (or from the cycle's start, for the first harvest) up to and including this harvest, this harvest's wages included. Family labour is left out, matching the profit-and-loss default. The lot stores this total in paise, worked out when the harvest is saved; the farmer can edit it. Cost per unit is the total divided by the quantity harvested; it is shown, not stored. A cost entered later with an earlier date does not change a saved lot unless the farmer recalculates it. An edited cost is marked and can be reset to the worked-out value. Editing the harvest's teams recalculates its lot, unless the cost was edited by hand. When the person saving the harvest, or editing its teams, cannot write money (a supervisor), the lot's cost is marked "not yet worked out"; the next phone of a role that can write money (owner, manager, accountant) works it out by this rule, keeps a cost that was edited by hand, and saves it, recorded in history as a money entry. A sale that draws from several lots uses the average cost per unit weighted by the quantity taken from each lot.

## Modules

### Land and crops
Farms → plots → crop cycles. Area in cent, acre, hectare. Ownership: owned, leased, shared. Mono, mixed and intercrop on one plot with area share or plant count. Seasonal, annual and perennial crops; perennials carry planting year. Optional per-tree tracking. Seasons (Virippu, Mundakan, Puncha, custom). Editable crop calendar generating tasks.

### Labour
Three ways to record, mixed freely on one day:
- **Named worker:** profile, skill, wage type, default rate, attendance (full, half, absent, overtime), task, advances, balance.
- **Unnamed group:** label, head count per rate class, rate per head or lump sum, hours, task, plot, crop, amount, who was paid. Created in one line, no profiles.
- **Named group:** leader, usual size, default rates, optional members, group ledger.
An unnamed group can later be named or have members added without losing records. Wage types: daily, hourly, piece rate, contract, monthly. Half-day is an attendance value (0.5 of the daily rate), not a wage type. Overtime is a full day plus extra hours at an overtime rate per hour (from templates, editable on the entry). Payments: advance, part payment, settlement, bonus, deduction. Wage cost posts to the crop cycles worked on. On a mixed plot it either splits across the plot's crop cycles (rule 8) or posts to one crop cycle. Which of the two is the default is a setting under the override model (app default: split the same way as an expense on that plot), changeable per farm, plot or entry; the shares are editable on the entry.

### Expenses
Categories from templates. Entry by amount with defaults for date, plot and category. Payment mode: cash, UPI, bank, credit (creates a payable). Split across crop cycles by template default share, area, plant count, equal share or custom percentages (editable). Recurring and capital expenses. Budget per crop cycle.

### Inputs and stock
Purchases add stock, applications deduct. Application log: item, quantity, method, dose, plot, crop, worker. Low-stock and expiry alerts. Soil test records. After a spray, a safe-to-harvest countdown and a warning if harvest is logged inside it.

Rules (phase 7). The owner decided the open points on 2026-11-20 (`docs/later-phases-tasks.md`); rules that carry one of those decisions say so.

1. **Items.** The farm's own list of inputs (fertiliser, pesticide, seed and the like), started from the crop templates' input lists or typed by the farmer. Each item has a standard unit (ml joined the standard units on 2026-11-20, beside litre, since pesticides are sold and mixed by the millilitre), an optional pack size (a 50 kg bag), an optional reorder level, the expense category its purchases go to, and an optional waiting period before harvest, the farmer's own default (rule 7).
2. **Stock is a sum.** Every change of stock is one stock movement: a purchase (in), an application (out) or an adjustment (in or out, with a reason). Stock on hand is the sum of an item's movements, never a stored number, so two phones using stock offline never overwrite each other.
3. **A purchase is an expense with a quantity.** Saving a purchase saves one expense and one purchase movement linked to it, together, with one undo. The expense works like any other expense (date, amount, plot and crop split, vendor, payment mode), in the item's category by default. The amount is entered once, on the expense; price per unit (amount ÷ quantity) is shown, never stored. One purchase is one item: a bill with three items is three purchases. An expense made by a purchase opens as that purchase, and deleting either deletes both. A credit purchase makes a payable like any credit expense.
4. **Cost counts when bought** (owner, 2026-11-20). A purchase's expense counts in profit and loss on its date and on the crops it is split to, like any expense. An application records only how much was taken from the item's stock, never which purchase it came from, and carries no cost; neither does an adjustment. So an input's money is counted once, when it is bought, and stock left in the store has no money line.
5. **One crop cycle per application** (owner, 2026-11-20). An application is recorded against one crop cycle of a plot. On a mixed plot the farmer picks the crop (default: the crop this item was last used on in that plot). Using an input on two crops is two applications, each with its own quantity.
6. **Stock does not go below zero by accident.** Saving an application or an adjustment that would take the item's stock below zero says how much is in stock and offers two ways on: change the quantity, or record the missing quantity as found stock (an adjustment in, reason "found when using") and save. Two phones using the same stock offline can still take it below zero after they sync: the item then shows "check stock", and counting it (an adjustment) settles it. That is not a sync conflict: stock is a sum, so nothing is lost or overwritten.
7. **Waiting period, dose and safe to harvest.** The farmer chooses the waiting period and the dose (owner, 2026-11-20). Thottam never suggests or invents either, and the templates carry none. An application copies the item's waiting period, editable on the entry, as days or as the safe-to-harvest date (changing one changes the other; days are stored). The dose is written the way the farmer says it ("2 ml per litre"); it defaults to the dose of this item's last application. A crop cycle's safe-to-harvest date is the latest of (application date + waiting days) over its applications that have a waiting period; harvesting on or after that date is safe. Days left = safe date − today. A harvest dated before the safe date shows the item, the application date and the period, and saves only with a reason, which is kept on the harvest and shown in history.
8. **Alerts work offline.** Low stock: stock on hand at or below the item's reorder level (no alert when no level is set). Expiry, only for purchases with an expiry date: stock is taken to be used oldest purchase first, so the stock on hand is the latest purchases; the item shows "expires soon" when the earliest expiry date among those purchases is within 30 days (owner, 2026-11-20; changeable per farm) and "expired" once it has passed. Both are worked out on the phone from the movements.
9. **Soil tests.** Plot, date, lab, a result for any of the parameters in the template list (the Soil Health Card parameters, with the units labs print), a photo of the report and a note. The photo is taken or picked with the `image_picker` package and made smaller on the phone before it is saved (owner approved the package, 2026-11-20). The latest test shows on the plot and on the inputs screen. The lab fee is an ordinary expense.
10. **Roles.** Items and stock movements are stock, like lots: everyone reads them, and owner, manager, supervisor and accountant write them. Applications and soil tests are daily work. A purchase needs money write, since it makes an expense: owner, manager and accountant. A supervisor sees how much was bought, used and is left, never a price.
11. **Switchable.** Inputs is a page in Settings. When it is off there is no More tile, no quick add tile and no button on plot detail; purchases already saved stay in the expense list and in profit and loss. The harvest warning for applications already recorded still shows, because it is safety information (owner, 2026-11-20).

### Harvest
One harvest entry: plot, crop cycle, date, unit, grade, and **any number of teams**. A team is an unnamed group, a named group or a named worker. Each group has one common rate per head; rates differ between teams and are editable on the entry. Per-team quantity is optional:
- on: each team has a quantity; total = sum; show per-team quantity per person, labour cost per unit, wages;
- off: enter the total only (a piece-rate team still enters its own quantity); show overall quantity per person and cost per unit.
Wages shown on a harvest are paid wages. Family labour is a separate, marked line, and labour cost per unit leaves it out, matching the lot cost (rule 9).
Piece-rate teams (per kg, per nut, per tree) can sit beside daily-rate teams. Each harvest creates a lot. The app keeps harvest-rate history and estimates labour needed (people, days, wage budget) from past rates; every estimate is editable.

### Processing
Batch: input lots → steps (from template) → output lots, with weight in and out, conversion ratio, loss and processing cost. Storage location and stock ageing. Lot traceability back to plot and harvest.

### Selling and prices
Sell from one or more lots: buyer, quantity, grade, rate, deductions (commission, weighing, loading, transport, quality cut), net amount, payment mode and status, part payments, advance. Part sale leaves the rest in stock. Buyer book with ledger. Profit at sale: net amount per sale unit (after deductions) minus lot cost per unit (rule 9, converted to the sale unit with the farm's unit conversions), shown before saving, with the deductions line visible so the farmer sees why it is below the rate.
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
- **Lot cost:** costs posted to the crop cycle since its previous harvest ₹20,060, plus this harvest's wages ₹8,500 → the lot stores ₹28,560; over 120 kg that is ₹238 per kg (the lot in the sale example). Adding a family worker to a team would not change this total; if the ₹1,000 named worker were family, the lot would store ₹27,560 (₹229.67 per kg).
- **Lot cost, sale from two lots:** 30 kg from a lot at ₹238 per kg and 20 kg from a lot at ₹250 per kg → (7,140 + 5,000) / 50 = ₹242.80 per kg.
- **Sale:** 50 kg at ₹705 with ₹170 deductions → gross ₹35,250, net ₹35,080; net per kg ₹701.60; with lot cost ₹238 per kg, profit per kg ₹463.60.
- **Split rounding:** ₹100 split equally across three crop cycles → ₹33.34, ₹33.33, ₹33.33 (10,000 paise: 3,333 each, the leftover paisa goes to the first listed).
- **Split by percentage:** ₹3,333 split 50.5% / 49.5% → 168,316.5 and 164,983.5 paise → ₹1,683.17 and ₹1,649.83 (the leftover paisa goes to the first listed on a tie; rounding each part half away from zero would give one paisa too many).
- **Stored amount:** 12.5 kg at ₹64.33 → 80,412.5 paise, stored as ₹804.13.
- **Processing:** 100 kg in, 33 kg out → ratio 33%, loss 67 kg.
- **Input stock:** potash, in kg. 1 June buy 50 kg for ₹1,500 (₹30.00 per kg shown) and 10 June 50 kg for ₹2,000 (₹40.00 per kg) → 100 kg in stock. 15 June use 30 kg on coconut → 70 kg; the use has no cost. 20 June the farmer counts 68 kg → an adjustment of −2 kg with its reason → 68 kg. Stock = 50 + 50 − 30 − 2.
- **Stock taken below zero by two phones:** 10 kg in stock. Offline, phone A records 8 kg used on 3 March and phone B 6 kg on 4 March. After both sync the stock is −4 kg and the item shows "check stock". Counting 0 kg saves an adjustment of +4 kg and clears it.
- **Profit and loss with inputs:** the profit and loss example below, plus 100 kg of potash bought for ₹3,500 and split to coconut → coconut's expense rises by ₹3,500 on the purchase date → expense ₹99,700, profit ₹84,800. Using 30 kg on coconut later changes neither; the 70 kg left shows on the stock list, with no money line.
- **Safe to harvest:** on one pepper crop cycle, spray X (waiting period 15 days) applied 3 Nov and spray Y (7 days) applied 10 Nov → safe dates 18 Nov and 17 Nov → safe from 18 Nov. On 15 Nov the card says 3 more days. A harvest dated 17 Nov asks for a reason; one dated 18 Nov does not. Entering the safe date 18 Nov on the 3 Nov application stores 15 days. (X and Y stand for any products; the periods here are not real label values.)
- **Expiry, oldest used first:** bought 20 kg on 1 Jan (expires 30 Jun) and 20 kg on 1 Mar (expires 31 Dec). With 25 kg used, the 15 kg on hand are all from March → earliest expiry 31 Dec. With 15 kg used, the 25 kg on hand are 20 kg from March and 5 kg from January → earliest expiry 30 Jun, so on 5 Jun the item shows "expires soon", and from 1 Jul "expired". A purchase with no expiry date never shows either.
- **Low stock:** reorder level 20 kg, 15 kg on hand → Low; 20 kg on hand → Low; 21 kg → not low.
- **Profit and loss:** income 92,000 + 68,500 + 24,000 = ₹1,84,500; expense 31,000 + 44,200 + 21,000 = ₹96,200; profit ₹88,300. With family labour (5,000 + 4,000 + 3,000) included: expense ₹1,08,200, profit ₹76,300.
