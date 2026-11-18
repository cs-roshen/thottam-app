# Server tests

SQL checks for the server schema: role rules, history, deletes and query plans
(B1), and the sync function (B7). They need a real Supabase project, so they are
not part of CI.

```
python tool/server_tests.py <project ref>
```

Each file runs in one transaction with every migration in `supabase/migrations`
and ends by raising `TEST SUMMARY <name>: passed=N failed=M`, so nothing is kept.
A new test file must end the same way (copy the last block of `b1_roles.sql`).
