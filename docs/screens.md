# Screens

Reference: the interactive prototype in `design/prototype/` and at https://claude.ai/artifact/PLuCg99aYUjk6cHCFVxY3d. Strings are in `lib/l10n/`. Sample values in the prototype are not real data.

Navigation: bottom bar with Home, My land, centre Add button, Money, More. Sub-screens have a back button and highlight their parent tab. The bar is hidden during set-up. A role that cannot open money does not see the Money tab. The current farm's name shows at the top of Home; Settings switches farm.

Every data screen must handle: empty state, offline (no spinner, just works), read-only (closed season, or a role that cannot write it), and large-text mode. Anything the user's role cannot open (`product-spec.md` rule 7) is hidden, including Home cards, quick add tiles and buttons such as "sell now".

## Phase 1

### 1. Welcome and language
Choose Malayalam, English or mixed; large-text switch. Continue → Google sign-in → set-up. If the account already belongs to a farm (its own, or one it joined), sign-in pulls it (first sync) and opens Home instead of set-up; with several farms it opens the last one used. If the account has open invites, sign-in first shows each one (farm name, role, who sent it) with Join and Decline: nobody is added to a farm until they tap Join. Joining pulls that farm and opens Home; declining every invite goes on to set-up. Mixed: Malayalam interface, with crop, category and unit names shown in Malayalam followed by English. Digits are always Latin.
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
- Check: totals on plot detail equal the sum of that plot's crop cycles.

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
- Members (owner only): add a person by their Google email, choose a role, change per-person permissions, remove a person. The person sees the farm after their next sign-in or sync; a removed person loses access at once on the server.
- Sync status: last synced time and items waiting to sync. Never a blocking dialog.
- Account: the signed-in Google account, and sign out. Signing out with items waiting to sync warns first; those items stay on the phone, tied to that user, until they sync.
- Check: a supervisor added here cannot open money screens or profit and loss; a removed member can no longer read or write the farm; switching farm shows only that farm's data; signing out with items waiting to sync shows the warning and loses nothing.

### 23. Admin console (web, may start minimal)
Crop chips, list type (activities, inputs, harvest grades), table with Malayalam and English names, source tag, shown-to-farmers switch, add item, publish with version number.

## Phase 2 and later

After the first release (implementation plan phases 7 to 13).

- **10. Crop doctor:** photos, affected part, severity, suggest remedy and/or send to expert, save disease record.
- **19. Inputs and stock:** safe-to-harvest countdown, stock rows with used / bought, low-stock tag, soil test.
- **20. Processing:** batch progress, steps, dry weight, ratio, loss, move to stock.
- **21. Community** and **22. Schemes.**
