-- Makes a person an admin of the template console (C12). Run with the service role, for
-- example in the dashboard's SQL editor or with
--   supabase db query --remote=<project ref> -f supabase/admin/add_admin.sql
-- after replacing the address below. The person must have signed in once, so that their
-- account exists. Remove an admin with: delete from public.app_admins where user_id = ...;
insert into public.app_admins (user_id)
select id from auth.users where email = lower('admin@example.com')
on conflict (user_id) do nothing;
