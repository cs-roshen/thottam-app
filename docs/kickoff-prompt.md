# Kickoff prompt for Claude Code

Paste this as the first message after opening the repository in Claude Code.

```
Read CLAUDE.md, docs/product-spec.md, docs/screens.md, docs/design-tokens.md and
docs/phase-1-tasks.md. Skim design/prototype/README.md.

Then:
1. Check that Flutter (stable) and the Supabase CLI are installed and tell me the
   versions. If something is missing, stop and tell me how to install it.
2. Tell me, in a short list, anything in the docs that is unclear or contradictory
   before writing code.
3. Do tasks A1 to A5 from docs/phase-1-tasks.md, one commit per task. Ask me for the
   app id before A1. Look up current setup steps for each package in its docs
   rather than relying on memory.
4. Stop after A5 and show me how to run the app, so I can check the theme,
   Malayalam text and navigation on my phone before we start the data core.
```

## Follow-up prompts

- Data core: `Do tasks B1 to B5. For B1, start a local Supabase instance, run the migration, fix any errors and show me what you changed in the SQL.`
- A feature: `Do task C3 (Labour). Write the tests from docs/screens.md and the worked examples in docs/product-spec.md first, show me the failing tests, then build it.`
- Review: `Review the last feature against CLAUDE.md's non-negotiable rules and list any violations.`
