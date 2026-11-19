# Admin console (minimal, task C12)

One web page for app admins to edit the standard crop templates in Malayalam and
English and publish them as a template release (screens.md, screen 23).

- Changes are saved as drafts. No phone sees them until you press **Publish to all
  farmers**, which writes every draft into `template_items` with the next release
  number. Phones pull the changes at their next sync and show "new items available".
  A farmer's own edits are never overwritten.
- Items are retired with the **Shown to farmers** switch (`is_active`), never deleted.
- Saving an item clears its `ml_review` flag (the wording has been reviewed).

## Security

The page signs in as an ordinary Supabase user (email and password; Google once B6
sets up the provider). Every action is one of the security-definer functions in
`supabase/migrations/0006_admin_console.sql`, and each checks that the signed-in
person is listed in `app_admins`. Only the service role can add a row there, so the
service-role key never reaches the browser. `config.js` holds only the public project
address and publishable key.

## Setting it up

1. Apply migration `0006_admin_console.sql`. It needs the owner's yes first; test it with
   `python tool/server_tests.py <project ref>`, then run
   `supabase db push --remote=<project ref>`.
2. Create the admin's account (Supabase dashboard → Authentication → Add user), then
   edit the address in `supabase/admin/add_admin.sql` and run it with the service role.
3. Fill in `admin/config.js` with the project address and publishable key.
4. Serve the folder, for example `python -m http.server 8080` inside `admin/`, and open
   http://localhost:8080. Host it anywhere static later; it needs no server of its own.
