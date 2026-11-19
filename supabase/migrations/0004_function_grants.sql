-- Supabase's own default privileges grant every new function in public to authenticated,
-- so the grant lists in 0001 and 0003 limited nothing: signed-in users could also call the
-- internal helpers. None of them gave more than the API already does, but close them, and
-- start every later function closed to signed-in users too; each migration grants what the
-- app calls. (Trigger functions cannot be called directly, so they are left as they are.)
revoke execute on function public.epoch_ms(timestamptz),
  public.log_event(text, uuid, uuid, text, jsonb, jsonb), public.my_invite_email()
  from authenticated;
alter default privileges in schema public revoke execute on functions from authenticated;
