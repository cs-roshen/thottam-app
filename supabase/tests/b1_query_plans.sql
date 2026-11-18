-- B1 query plans (implementation plan section 13): the pulls the phone makes, run as a
-- signed-in user on seeded data, use the (farm_id, server_seq) indexes and work out the
-- membership lookup once per statement, not once per row.
--   supabase db query --remote=<project ref> -f supabase/tests/b1_query_plans.sql
-- Ends by raising its summary (with the plans), so nothing is kept.

begin;

create temp table results (n serial, name text, ok boolean, detail text);

create function pg_temp.u(p_name text) returns uuid
language sql immutable as $$ select md5('b1plan:user:' || p_name)::uuid $$;

create function pg_temp.id(p_name text) returns uuid
language sql immutable as $$ select md5('b1plan:' || p_name)::uuid $$;

insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at, created_at, updated_at)
select pg_temp.u(x), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
  x || '@example.com', now(), now(), now()
from unnest(array['owner_a', 'owner_b', 'supervisor_a']) x;

-- Two farms with a season of entries each, so a plan that reads the other farm shows.
do $$
declare f text;
begin
  foreach f in array array['a', 'b'] loop
    perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.u('owner_' || f))::text, true);
    perform public.create_farm(pg_temp.id('farm_' || f), pg_temp.id('member_' || f), 'Farm ' || f);
  end loop;
  perform set_config('request.jwt.claims', '', true);
end $$;
insert into public.farm_members (id, farm_id, user_id, role)
values (pg_temp.id('member_sup'), pg_temp.id('farm_a'), pg_temp.u('supervisor_a'), 'supervisor');

insert into public.workers (id, farm_id, name)
select pg_temp.id('worker_' || f), pg_temp.id('farm_' || f), 'Worker' from unnest(array['a', 'b']) f;
insert into public.labour_entries (id, farm_id, work_date, worker_id, rate_paise, amount_paise)
select gen_random_uuid(), pg_temp.id('farm_' || f), date '2026-01-01' + (i % 300), pg_temp.id('worker_' || f), 90000, 90000
from unnest(array['a', 'b']) f, generate_series(1, 20000) i;
insert into public.expenses (id, farm_id, spent_on, category_code, amount_paise)
select gen_random_uuid(), pg_temp.id('farm_' || f), date '2026-01-01' + (i % 300), 'fertiliser', 10000
from unnest(array['a', 'b']) f, generate_series(1, 8000) i;
insert into public.event_log (id, farm_id, entity, entity_id, action, occurred_on)
select gen_random_uuid(), pg_temp.id('farm_' || f), case when i % 3 = 0 then 'expenses' else 'labour_entries' end,
  gen_random_uuid(), 'create', date '2026-01-01' + (i % 300)
from unnest(array['a', 'b']) f, generate_series(1, 30000) i;
analyze public.labour_entries, public.expenses, public.event_log, public.farm_members, public.sync_tables;

-- The plan of p_sql as p_user, as one text block.
create function pg_temp.plan(p_user uuid, p_sql text) returns text
language plpgsql as $$
declare
  v text := '';
  line text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  for line in execute 'explain (analyze, costs off, timing off, summary off) ' || p_sql loop
    v := v || line || chr(10);
  end loop;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return v;
end $$;

create function pg_temp.check_plan(p_name text, p_user uuid, p_sql text, p_index text, p_rows integer) returns void
language plpgsql as $$
declare
  v_plan text := pg_temp.plan(p_user, p_sql);
  v_rows integer;
begin
  execute 'select count(*) from (' || p_sql || ') x' into v_rows;  -- as the server, for scale
  insert into results (name, ok, detail) values (p_name,
    v_plan like '%' || p_index || '%'
      and v_plan not like '%Seq Scan on ' || split_part(p_index, '_farm', 1) || '%'
      -- the policy's membership lookup runs once (an InitPlan, or a hashed SubPlan
      -- built once), not once per row
      and (v_plan like '%InitPlan%' or v_plan like '%hashed SubPlan%')
      and v_plan not like '%SubPlan%loops=500%',
    v_plan);
end $$;

select pg_temp.check_plan('owner pulls labour entries by cursor',
  pg_temp.u('owner_a'),
  format('select * from public.labour_entries where farm_id = %L and server_seq > 0 order by server_seq limit 500',
    pg_temp.id('farm_a')),
  'labour_entries_farm_seq', 500);
select pg_temp.check_plan('owner pulls expenses by cursor',
  pg_temp.u('owner_a'),
  format('select * from public.expenses where farm_id = %L and server_seq > 0 order by server_seq limit 500',
    pg_temp.id('farm_a')),
  'expenses_farm_seq', 500);
select pg_temp.check_plan('supervisor pulls history by cursor, money rows left out',
  pg_temp.u('supervisor_a'),
  format('select * from public.event_log where farm_id = %L and server_seq > 0 order by server_seq limit 500',
    pg_temp.id('farm_a')),
  'event_log_farm_seq', 500);

-- what each pull actually returned, as the signed-in user
do $$
declare n integer;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.u('supervisor_a'), 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from public.event_log where entity = 'expenses';
  reset role;
  insert into results (name, ok, detail) values ('supervisor sees no money history', n = 0, n::text);
  set local role authenticated;
  select count(*) into n from public.expenses;
  reset role;
  insert into results (name, ok, detail) values ('supervisor sees no expenses', n = 0, n::text);
  perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.u('owner_a'), 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from public.labour_entries;
  reset role;
  insert into results (name, ok, detail) values ('owner A sees only farm A entries', n = 20000, n::text);
  perform set_config('request.jwt.claims', '', true);
end $$;

-- ---------- result ----------
-- Always raises, so nothing above can be committed; the message is the summary, with the
-- plans of any check that failed.
do $$
declare
  v_passed integer;
  v_failed integer;
  v_failures text;
begin
  select count(*) filter (where ok), count(*) filter (where not ok),
    coalesce(string_agg(name || ' -> ' || coalesce(detail, ''), chr(10) order by n) filter (where not ok), '')
    into v_passed, v_failed, v_failures
  from results;
  raise exception 'TEST SUMMARY b1_query_plans: passed=% failed=% %', v_passed, v_failed,
    case when v_failed > 0 then chr(10) || v_failures else '' end;
end $$;

rollback;
