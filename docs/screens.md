# Screens

Reference: the interactive prototype in `design/prototype/` and at https://claude.ai/artifact/PLuCg99aYUjk6cHCFVxY3d. Strings are in `lib/l10n/`. Sample values in the prototype are not real data.

Navigation: bottom bar with Home, My land, centre Add button, Money, More. Sub-screens have a back button and highlight their parent tab. The bar is hidden during set-up.

Every data screen must handle: empty state, offline (no spinner, just works), read-only (closed season), and large-text mode.

## Phase 1

### 1. Welcome and language
Choose Malayalam, English or mixed; large-text switch. Continue → set-up.
- Check: choice persists and applies immediately across the app.

### 17. Set-up (3 steps)
Name and phone → first farm (name, area, unit, owned or leased) → crops (multi-select). Finish creates farm, plot and crop cycles from templates, then opens Home.
- Check: can finish with only a name and farm name; everything else has defaults and can be added later.

### 2. Home
Date (with Malayalam month), greeting, language toggle, settings. Cards, each switchable in settings: weather, season profit with income and expense, today's price, today's tasks (tick to complete), wages due.
- Check: hiding a card in settings removes it; ticking a task writes to history.

### 3. Quick add sheet
Opens from the centre button on any tab. Voice entry (later phase; show disabled or hidden), tiles for Expense, Labour, Harvest, Inputs, Sale, Note; bill scan (later). Tiles follow enabled pages.

### 4. My land, and 18. Plot detail
List of plots with area, tenure, crop chips, "mixed crop" tag and next task. Tap → plot detail: stats (crops, season cost, yield, today's price), tabs for crops, costs by category, and recent history with a link to full history; quick buttons to add expense or harvest for this plot.
- Check: totals on plot detail equal the sum of that plot's crop cycles.

### 8 and 11. Labour
Segmented switch: named workers | group (head count).
- Named: "same as yesterday", per-worker full / half / absent, live total, save.
- Group: optional group name, a stepper per rate class with its rate per day, live total, save. No profiles needed.
- Check: both examples in the spec (₹2,150 and ₹5,200); saving posts wage cost to the chosen crop cycle and to each worker's or group's history.

### 9. Add expense
Amount (large input), category chips, split across the plot's crops (default by template share, "edit manually"), payment mode, save with undo.
- Check: split always sums to the amount, including after manual edits and rounding.

### 12. Harvest
"Last time" banner. Total quantity with unit chips. Switch: log quantity for each team. Team cards: name, tag (group or named), remove; head-count stepper for groups; wage per person; quantity when the switch is on; computed line. Buttons to add a group or a named worker. Summary: quantity per person per day, labour cost per unit, total wages. Save creates a lot and goes to history; "sell now" opens selling.
- Check: the harvest example in the spec, with the switch on and off; removing a team recalculates.

### 13. Sell
Today's price banner with source and time (links to prices). Quantity and rate (rate prefilled from price), buyer type, gross, deductions (editable), net, profit per kg against lot cost. Save reduces stock.
- Check: cannot sell more than stock; part sale leaves the remainder.

### 14. Prices
List of the farmer's crops: price, change, source and time. Selecting one shows a 30-day chart, market comparison and a price-alert switch with threshold.
- Check: a price older than one day is visibly marked stale.

### 15. History
"This week last year" card, filter chips (all, labour, expense, harvest, sales, edits), events grouped by day with icon, title, context and amount. Edit events show old → new and who changed it. Export.
- Check: every create, edit and delete from any screen appears here.

### 5. Profit and loss
Profit, income, expense; by-crop rows with income and expense bars; switch to include family labour; share report.
- Check: the profit example in the spec, both switch positions.

### 16. My lists (farmer templates)
Crop chips; activity list with on/off switches; "new items available" banner for admin updates; add own item; reset to default.
- Check: an admin update never changes an item the farmer has edited or switched off.

### 6. More, and 7. Settings
More: tiles for every enabled page, then Settings. Settings: language, large text, pages on/off (drives More and quick add), home cards on/off, reset to default.

### 23. Admin console (web, may start minimal)
Crop chips, list type (activities, inputs, harvest grades), table with Malayalam and English names, source tag, shown-to-farmers switch, add item, publish with version number.

## Phase 2 and later

- **10. Crop doctor:** photos, affected part, severity, suggest remedy and/or send to expert, save disease record.
- **19. Inputs and stock:** safe-to-harvest countdown, stock rows with used / bought, low-stock tag, soil test.
- **20. Processing:** batch progress, steps, dry weight, ratio, loss, move to stock.
- **21. Community** and **22. Schemes.**
