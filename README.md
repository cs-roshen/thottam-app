# Thottam (തോട്ടം)

A complete farm management app for Kerala farmers: land and mixed crops, labour, expenses, inputs, harvest, processing, selling, live prices, profit and loss, and a history of everything. Malayalam first, works offline.

This repository currently holds the starter kit: specifications, design reference, draft database schema and localisation strings. The Flutter project itself is created in the first task.

## Start in Claude Code

1. Clone this repository and open it in Claude Code.
2. Make sure Flutter (stable) and the Supabase CLI are installed.
3. Paste the prompt from `docs/kickoff-prompt.md`.

## What is here

| Path | Contents |
| --- | --- |
| `CLAUDE.md` | Project rules Claude Code follows in every session |
| `docs/product-spec.md` | Modules and cross-cutting rules |
| `docs/screens.md` | Screen-by-screen behaviour and acceptance checks |
| `docs/phase-1-tasks.md` | Ordered backlog for the first release |
| `docs/implementation-plan.md` | Detailed phase plan, review process, performance and offline rules |
| `docs/design-tokens.md` | Colours, type, spacing, motion |
| `docs/kickoff-prompt.md` | First prompt to paste into Claude Code |
| `design/prototype/` | Interactive HTML prototype source (reference only) |
| `lib/l10n/` | Malayalam and English strings taken from the prototype |
| `supabase/migrations/0001_init.sql` | Draft schema with row-level security (not yet run) |

## Status

Planning and design complete for phase 1. No app code yet. All numbers, names and prices in the prototype are sample data. Malayalam wording needs a native-speaker review before release.
