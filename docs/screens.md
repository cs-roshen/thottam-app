# Screens

Reference: the interactive prototype in `design/prototype/` and at https://claude.ai/artifact/PLuCg99aYUjk6cHCFVxY3d. Strings are in `lib/l10n/`. Sample values in the prototype are not real data.

Navigation: bottom bar with Home, My land, centre Add button, Money, More. Sub-screens have a back button and highlight their parent tab. The bar is hidden during set-up. A role that cannot open money does not see the Money tab. The current farm's name shows at the top of Home; Settings switches farm.

Every data screen must handle: empty state, offline (no spinner, just works), read-only (closed season, or a role that cannot write it), and large-text mode. Anything the user's role cannot open (`product-spec.md` rule 7) is hidden, including Home cards, quick add tiles and buttons such as "sell now".

## Phase 1

### 1. Welcome and language
Choose Malayalam, English or mixed; large-text switch. Continue → Google sign-in → set-up. If the account already belongs to a farm (its own, or one it joined), sign-in pulls it (first sync) and opens Home instead of set-up; with several farms it opens the last one used. If the account has open invites, sign-in first shows each one (farm name, role, who sent it) with Join and Decline: nobody is added to a farm until they tap Join. Joining pulls that farm and opens Home; declining every invite goes on to set-up. Mixed: Malayalam interface, with crop and category names shown in Malayalam followed by English. Units and numbers are always in English with Latin digits, in every language.
- Check: choice persists and applies immediately across the app.
- Check: after the first sign-in the app opens and works in flight mode; signing in as another user on the same phone shows none of the first user's data.
- Check: offline at first launch, the sign-in step says once that a connection is needed and continues by itself when one returns. This is the only step that waits for the network (with the first sync of a farm the account already has).
- Check: signing in on a new phone with an account that already has a farm restores it and opens Home, with no set-up and no second farm.

### 17. Set-up (3 steps)
Name (prefilled from the Google account) and phone (optional) → first farm (name, area, unit, owned or leased) → crops (multi-select). Finish creates farm, plot and crop cycles from templates, then opens Home.
- Check: can finish with only a name and farm name; everything else has defaults and can be added later.

### 2. Home
Date (with Malayalam month), greeting, language toggle, settings. Cards, each switchable in settings: weather, season profit with income and expense, today's price, today's tasks (tick to complete), wages due.
- Check: hiding a card in settings removes it; ticking a task writes to history.

### 3. Quick add sheet
Opens from the centre button on any tab. Voice entry (later phase; show disabled or hidden), tiles for Expense, Labour, Harvest, Sale, Note; Inputs and bill scan (later phases, hidden). Tiles follow enabled pages and the user's role.
- Note: text, date (today), plot and crop cycle (both optional); save with undo. Notes appear in History and the farm diary.
- Check: a note saved offline appears in History under its date.

### 4. My land, and 18. Plot detail
List of plots with area, tenure, crop chips, "mixed crop" tag and next task. Tap → plot detail: stats (crops, season cost, yield, today's price), tabs for crops, costs by category, and recent history with a link to full history; quick buttons to add expense or harvest for this plot.
- Deleting a plot or a crop cycle asks first, saying how many entries sit under it. The entries are kept: they stay in profit and loss and history, shown under the deleted plot or crop cycle, and undo brings it back (owner decision, 2026-11-19).
- Check: totals on plot detail equal the sum of that plot's crop cycles.
- Check: deleting a plot that has entries keeps every entry and leaves the farm's profit and loss unchanged; undo restores the plot.

### 8 and 11. Labour
Segmented switch: named workers | group (head count).
- Named: "same as yesterday", per-worker full / half / absent / overtime (with extra hours), live total, save.
- Group: optional group name, a stepper per rate class with its rate per day (or one lump sum for the group), hours, live total, save. No profiles needed.
- On a mixed plot the wage splits across the plot's crop cycles or goes to one, as set under the override model (`product-spec.md`, Labour); shares are editable on the entry.
- Check: the examples in the spec (₹2,150, ₹1,200 overtime and ₹5,200); saving posts wage cost to the chosen crop cycle, or splits it across the plot's crop cycles with the parts summing to the wage, and to each worker's or group's history.

### 9. Add expense
Amount (large input), category chips, split across the plot's crops (default by template share, "edit manually"), payment mode, save with undo.
- Check: split always sums to the amount, including after manual edits and rounding. Leftover paise follow the largest-remainder rule in `product-spec.md` (₹100 across three equal crops → ₹33.34, ₹33.33, ₹33.33; ₹3,333 split 50.5% / 49.5% → ₹1,683.17, ₹1,649.83).

### 12. Harvest
"Last time" banner. Total quantity with unit chips. Switch: log quantity for each team. Team cards: name, tag (group or named), remove; head-count stepper for groups; wage per person; quantity when the switch is on, and always for a piece-rate team; computed line. Buttons to add a group or a named worker. Summary: quantity per person per day, labour cost per unit, total wages (paid), and family labour on its own marked line. Save creates a lot and goes to history; "sell now" opens selling.
- Saved lot: its stored cost and cost per unit, or "not yet worked out" when saved or edited by someone who cannot write money; edit and recalculate. An edited cost is marked and can be reset.
- Check: the harvest example in the spec, with the switch on and off; removing a team recalculates; with the switch off a piece-rate team still enters its quantity; editing a team recalculates the lot unless its cost was edited by hand; a supervisor's harvest saves with the cost not yet worked out, and the cost appears after an owner's, manager's or accountant's phone syncs; a supervisor's edit to the teams marks it not yet worked out again; a supervisor's phone never holds the lot cost.

### 13. Sell
Today's price banner with source and time (links to prices). Lots to sell from (one or more), quantity and rate (rate prefilled from price), buyer and buyer type, gross, deductions (editable), net, payment mode and status (paid, part paid with the amount received, due), profit per sale unit (net per unit minus lot cost per unit in the sale unit, `product-spec.md` rule 9). Save reduces stock.
- Check: cannot sell more than stock; part sale leaves the remainder; the sale and two-lot examples in the spec.

### 14. Prices
List of the farmer's crops: price, change, source and time. Selecting one shows a 30-day chart, market comparison and a price-alert switch with threshold.
- Check: a price older than one day is visibly marked stale.

### 15. History
"This week last year" card, filter chips (all, labour, expense, harvest, sales, edits), events grouped by day with icon, title, context and amount. Edit events show old → new and who changed it. Export.
- Check: every create, edit and delete from any screen appears here; a supervisor sees no money events.

### 5. Profit and loss
Profit, income, expense; by-crop rows with income and expense bars; switch to include family labour; share report.
- Check: the profit example in the spec, both switch positions.

### 16. My lists (farmer templates)
Crop chips; activity list with on/off switches; "new items available" banner for admin updates; add own item; reset to default.
- Check: an admin update never changes an item the farmer has edited or switched off.

### 6. More, and 7. Settings
More: tiles for every enabled page, then Settings. Settings: language, large text, pages on/off (drives More and quick add), home cards on/off, reset to default, farms, members, account, sync status.
- Farms: the farms this account belongs to, with its role on each; switch farm; add a farm (set-up steps 2 and 3). An open invite to another farm shows here with Join and Decline (checked at each sign-in and sync); the farm is added only after Join.
- Members (owner only): add a person by their Google email, choose a role, change per-person permissions, remove a person. The person joins once they tap Join on the invite (at sign-in or under Farms); a removed person loses access at once on the server.
- Sync status: last synced time and items waiting to sync. Never a blocking dialog.
- Account: the signed-in Google account, and sign out. Signing out with items waiting to sync warns first; those items stay on the phone, tied to that user, until they sync.
- Check: a supervisor added here cannot open money screens or profit and loss; a removed member can no longer read or write the farm; switching farm shows only that farm's data; signing out with items waiting to sync shows the warning and loses nothing.

### 23. Admin console (web, may start minimal)
Crop chips, list type (activities, inputs, harvest grades), table with Malayalam and English names, source tag, shown-to-farmers switch, add item, publish with version number.

## Phase 2 and later

Implementation plan phases 7 to 13, started ahead of the closed beta (owner decision, 2026-11-20). Each phase gets its full section here in its docs pull request.

- **10. Crop doctor:** photos, affected part, severity, suggest remedy and/or send to expert, save disease record.
- **20. Processing:** batch progress, steps, dry weight, ratio, loss, move to stock.
- **21. Community** and **22. Schemes.**

## Phase 7: inputs and stock

Rules, roles and worked examples: `product-spec.md`, Inputs and stock. Page code `inputs`; the page needs stock read. A supervisor never sees a price, a cost or a stock value on any of these screens.

### 19. Inputs and stock
More → Inputs. Title and subtitle ("Stock and use").
- Safe-to-harvest card for each crop cycle still inside a waiting period, soonest first: days left in large type, the crop and plot, the item and how long ago it was applied, a bar of the period gone by. No card when nothing is waiting.
- Stock: one row per item, name and stock on hand with unit; tags Low, Expires soon, Expired, Check stock (below zero), each a word with its colour, never colour alone. Two buttons on each row: Used (opens 19b for this item) and Bought (opens 19a; hidden from a role that cannot write money). Tapping the row opens 19c.
- For a role that can see money: "Stock on hand worth ₹X, not yet in crop costs".
- Soil test row: the latest test (main values and how long ago) with Add new (19d), or "No soil test yet".
- Empty state: what the screen is for, and Add a purchase (or Add an item for a role that cannot write money).
- Check: the stock list shows the average-cost example's 60 kg after its purchases and applications, worth ₹2,280; the low-stock example is tagged Low; the expiry example is tagged Expires soon on 5 Jun; two phones taking stock below zero show Check stock after sync.
- Check: a supervisor sees the quantities and no amount anywhere on the screen.

### 19a. Add purchase
Item (search the farm's items, with the crop templates' input items offered as new items; "New item" adds name, category, unit and pack size in line), quantity (pack chips when the item has a pack size: "2 × 50 kg"), total amount (large input), price per unit worked out and shown, vendor (optional), date (today), payment mode (cash, UPI, bank, credit), and under More details batch and expiry date. Save with undo.
- Check: one save makes one expense in the item's category and one purchase movement; the expense shows once in the expense list and opens as this purchase; undo removes both; deleting either removes both.
- Check: profit and loss is unchanged by a purchase; the stock on hand rises by its quantity and its value by its amount.
- Check: a credit purchase shows as a payable.

### 19b. Log input used
Opens from the Used button, the quick add tile and plot detail. Item (default: last used), quantity with unit, with "In stock: 40 kg" beside it; plot (default: last plot) and crop (chips on a mixed plot; default per `product-spec.md` rule 7 of Inputs); date (today); method chips (template list); who applied (optional worker or group); waiting period in days, prefilled from the item with its source shown, editable; note. For a role that can see money: cost at average ("₹1,050: 30 kg × ₹35.00 average") with edit, and "Cost not known yet" when the item has no purchase. Save with undo; the toast gives the safe-to-harvest date when there is one.
- Check: the average-cost, rounding and edited-cost examples give their costs to the paisa; an edited cost is marked and resets to the worked-out value.
- Check: using more than is in stock offers "record the rest as found stock and save" or changing the quantity, and never saves below zero without that choice.
- Check: the waiting period comes from the item, can be changed on the entry, and the source shows beside it.
- Check: a supervisor logs an application and sees no cost; an accountant cannot open this screen (daily work).

### 19c. Item detail
Stock on hand, average cost per unit and stock value (money roles), unit, pack size, reorder level, waiting period with source (edit: a period cannot be saved without its source), and every movement newest first: bought (+quantity, amount for money roles, vendor), used (−quantity, crop and plot), adjusted (± quantity, reason). Adjust stock: enter the counted stock; the difference is saved as an adjustment with a reason.
- Check: the movements add up to the stock on hand; an adjustment to a counted 58 kg from 60 kg saves −2 kg with its reason and costs ₹76 at the example's ₹38 average.
- Check: a waiting period without a source is refused next to the field.

### 19d. Soil test
Plot (default: last plot), date, lab, a number field for each parameter in the template list with its unit (all optional), photo of the report (once the photo package is chosen), note. Save with undo. The plot shows its tests newest first.
- Check: a test with only pH saves; the latest test shows on 19 and on plot detail with its age.

### Changes to phase 1 screens
- **3. Quick add:** an Inputs tile (opens 19b), shown when the page is on and the role can write daily work.
- **18. Plot detail:** the safe-to-harvest countdown on each crop cycle inside a waiting period; a Log input button (19b with this plot); the latest soil test.
- **12. Harvest:** when the chosen crop cycle is inside a waiting period on the harvest date, a banner names the item, the application date, the period and its source, and the safe date. Saving asks for a reason (required) and keeps it on the harvest.
- **5. Profit and loss:** purchases are not counted; applications count on their crop cycle at their cost; adjustments out count as a farm cost on no crop; a line shows stock on hand at its value, apart from profit.
- **15. History:** an Inputs filter chip; purchases, applications, adjustments, item changes, edited costs and soil tests appear with their quantities. A supervisor sees purchases and applications as quantities only; edited costs are money and hidden from them. A harvest saved inside a waiting period shows its reason.
- **7. Settings:** an Inputs page switch (`product-spec.md`, Inputs rule 13).
- Check: the profit and loss example with inputs (`product-spec.md`): expense ₹98,770, profit ₹85,730, stock on hand ₹2,280.
- Check: the safe-to-harvest example: on 15 Nov the plot shows 3 more days; a harvest dated 17 Nov needs a reason and history shows it; one dated 18 Nov saves without asking.
- Check: with the Inputs page off there is no tile on More or quick add, no plot button and no Money line; a harvest inside a recorded waiting period still warns.
