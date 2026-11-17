# Prototype source (reference only)

These are the source files of the interactive prototype published at
https://claude.ai/artifact/PLuCg99aYUjk6cHCFVxY3d (open that link and press Play to use it).
They do not run on their own: they depend on the design tool's runtime (`support.js`).

- `app-prototype.dc.html` — every phone screen in one file. The markup inside `<x-dc>` has one
  block per screen (`isHome`, `isLand`, `isLabour`, `isHarvest`, `isSell`, ...); the script at the
  bottom holds the Malayalam and English strings (`STR`), sample data and all calculations
  (`renderVals`). Read it for layout, wording, states and formulas.
- `welcome.dc.html` — language selection.
- `admin-console.dc.html` — web template editor.

Use it as the reference for look and behaviour. Do not port the HTML line by line; build proper
Flutter widgets from `docs/design-tokens.md`. All numbers and names in it are sample data.
