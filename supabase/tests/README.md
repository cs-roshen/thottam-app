# Server tests

SQL checks for the server schema: role rules, history, deletes and query plans
(B1), and the sync function (B7). They need a real Supabase project, so they are
not part of CI.

```
python tool/server_tests.py <project ref>
```

Each file runs in one transaction with every migration in `supabase/migrations`
that the project has not applied yet (the runner reads its migration history), and
ends by raising `TEST SUMMARY <name>: passed=N failed=M`, so nothing is kept. An
applied migration is never edited: a change is a new migration, tested this way
before it is applied with `supabase db push --remote=<project ref>`.
A new test file must end the same way (copy the last block of `b1_roles.sql`).
