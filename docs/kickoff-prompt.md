# Kickoff prompt for Claude Code

Paste this as the first message after opening the repository in Claude Code.

```
Read CLAUDE.md, docs/implementation-plan.md, docs/product-spec.md, docs/screens.md,
docs/design-tokens.md and docs/phase-1-tasks.md. Skim design/prototype/README.md.

Then:
1. Check that git, Flutter (stable) and the Supabase CLI are installed and tell me the
   versions. If something is missing, stop and tell me how to install it.
2. Do phase 0 from docs/implementation-plan.md section 4: ask me the owner decisions,
   show me each doc contradiction with its recommended answer, and after I confirm,
   edit the docs and add the backlog fixes (A6 and C12). One commit.
3. Do tasks A1 to A6 from docs/phase-1-tasks.md following the task loop in section 1
   of the plan, one branch and one commit per task. Look up current setup steps for
   each package in its docs rather than relying on memory.
4. Stop after A6 and show me how to run the app, so I can check the theme, Malayalam
   text and navigation on my phone before we start the data core.
```

## Follow-up prompts

- Any single task: use the session start prompt in section 1 of `docs/implementation-plan.md`.
- Data core: `Do tasks B1 to B5 following the plan. For B1, start a local Supabase instance, apply the schema fixes listed in section 6, and show me what you changed in the SQL.`
- Reference feature: `Do task C4 (Expenses) as the reference feature described in section 7 of the plan. Show me the failing tests first.`
- Review: use the independent review prompt in section 16 of the plan, in a fresh session.
- Later modules: `Start phase <N> from section 11 of the plan with its docs task only, and stop for my review.`
