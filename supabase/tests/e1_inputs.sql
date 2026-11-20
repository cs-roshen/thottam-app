-- E1 server tests for inputs and stock (0007). Run with tool/server_tests.py; nothing is kept.
-- Per-role read and write of every new table is in b1_roles.sql (it walks sync_tables);
-- this file checks what is particular to phase 7.

begin;

create temp table results (n serial, name text, ok boolean, detail text);

create function pg_temp.check(p_name text, p_ok boolean, p_detail text default null) returns void
language sql as $$ insert into results (name, ok, detail) values (p_name, coalesce(p_ok, false), p_detail) $$;

create function pg_temp.id(p_name text) returns uuid
language sql immutable as $$ select md5('e1test:' || p_name)::uuid $$;

-- Runs p_sql as p_user and always undoes it; returns 'ok:<rows>' or 'err:<code> <message>'.
create function pg_temp.try_as(p_user uuid, p_sql text) returns text
language plpgsql as $$
declare
  n bigint;
  v text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  begin
    execute 'set local role authenticated';
    execute p_sql;
    get diagnostics n = row_count;
    raise exception using errcode = 'TUNDO', message = n::text;
  exception
    when sqlstate 'TUNDO' then v := 'ok:' || sqlerrm;
    when others then v := 'err:' || sqlstate || ' ' || sqlerrm;
  end;
  perform set_config('request.jwt.claims', '', true);
  return v;
end $$;

-- Calls sync_push as p_user and keeps the result.
create function pg_temp.push(p_user uuid, p_batch text, p_farm uuid, p_rows jsonb) returns jsonb
language plpgsql as $$
declare
  v jsonb;
  v_batch uuid := pg_temp.id(p_batch);
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select public.sync_push(v_batch, p_farm, p_rows, p_user) into v;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return v;
end $$;

-- A row as the phone sends it: the common columns plus [cols].
create function pg_temp.r(p_entity text, p_id uuid, p_farm uuid, p_cols jsonb) returns jsonb
language sql as $$
  select jsonb_build_object('entity', p_entity, 'base_version', 0, 'changes', '{}',
    'row', jsonb_build_object('id', p_id, 'farm_id', p_farm, 'created_at', '2026-11-18T08:00:00Z',
      'updated_at', '2026-11-18T08:00:00Z', 'version', 1, 'deleted_at', null) || p_cols)
$$;

-- ---------- fixtures: farm A (owner, supervisor, accountant) and farm B ----------
insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at, raw_user_meta_data, created_at, updated_at)
select pg_temp.id('user:' || x), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
  x || '@example.com', now(), jsonb_build_object('full_name', x), now(), now()
from unnest(array['owner_a', 'supervisor_a', 'accountant_a', 'owner_b']) x;

do $$
declare
  coconut uuid := (select id from public.crops where code = 'coconut' and owner_farm_id is null);
  t text;
begin
  insert into public.farms (id, name) values (pg_temp.id('farm:a'), 'Farm A'), (pg_temp.id('farm:b'), 'Farm B');
  insert into public.farm_members (id, farm_id, user_id, role) values
    (pg_temp.id('m:owner_a'), pg_temp.id('farm:a'), pg_temp.id('user:owner_a'), 'owner'),
    (pg_temp.id('m:supervisor_a'), pg_temp.id('farm:a'), pg_temp.id('user:supervisor_a'), 'supervisor'),
    (pg_temp.id('m:accountant_a'), pg_temp.id('farm:a'), pg_temp.id('user:accountant_a'), 'accountant'),
    (pg_temp.id('m:owner_b'), pg_temp.id('farm:b'), pg_temp.id('user:owner_b'), 'owner');
  foreach t in array array['a', 'b'] loop
    insert into public.plots (id, farm_id, name) values (pg_temp.id(t || ':plot'), pg_temp.id('farm:' || t), 'Plot');
    insert into public.crop_cycles (id, farm_id, plot_id, crop_id)
      values (pg_temp.id(t || ':cycle'), pg_temp.id('farm:' || t), pg_temp.id(t || ':plot'), coconut);
    insert into public.input_items (id, farm_id, name_en, unit)
      values (pg_temp.id(t || ':potash'), pg_temp.id('farm:' || t), 'Potash', 'kg');
  end loop;
  insert into public.expenses (id, farm_id, spent_on, category_code, amount_paise)
    values (pg_temp.id('a:expense'), pg_temp.id('farm:a'), '2026-06-01', 'fertiliser', 150000);
  insert into public.stock_movements (id, farm_id, item_id, moved_on, kind, quantity, expense_id)
    values (pg_temp.id('a:bought'), pg_temp.id('farm:a'), pg_temp.id('a:potash'), '2026-06-01', 'purchase', 50000,
      pg_temp.id('a:expense'));
end $$;

-- ---------- rows that can never be right ----------
select pg_temp.check('a purchase without its expense is refused',
  pg_temp.try_as(pg_temp.id('user:owner_a'), format(
    'insert into public.stock_movements (id, farm_id, item_id, moved_on, kind, quantity) values (%L, %L, %L, %L, %L, 1000)',
    gen_random_uuid(), pg_temp.id('farm:a'), pg_temp.id('a:potash'), '2026-06-02', 'purchase')) like 'err:23514%');
select pg_temp.check('an application that adds stock is refused',
  pg_temp.try_as(pg_temp.id('user:owner_a'), format(
    'insert into public.stock_movements (id, farm_id, item_id, moved_on, kind, quantity) values (%L, %L, %L, %L, %L, 1000)',
    gen_random_uuid(), pg_temp.id('farm:a'), pg_temp.id('a:potash'), '2026-06-02', 'application')) like 'err:23514%');
select pg_temp.check('a movement of nothing is refused',
  pg_temp.try_as(pg_temp.id('user:owner_a'), format(
    'insert into public.stock_movements (id, farm_id, item_id, moved_on, kind, quantity) values (%L, %L, %L, %L, %L, 0)',
    gen_random_uuid(), pg_temp.id('farm:a'), pg_temp.id('a:potash'), '2026-06-02', 'adjustment')) like 'err:23514%');
select pg_temp.check('the farmer''s own waiting period is kept, with no source asked',
  pg_temp.try_as(pg_temp.id('user:owner_a'), format(
    'update public.input_items set waiting_days = 15 where id = %L', pg_temp.id('a:potash'))) = 'ok:1');
select pg_temp.check('a negative waiting period is refused',
  pg_temp.try_as(pg_temp.id('user:owner_a'), format(
    'update public.input_items set waiting_days = -1 where id = %L', pg_temp.id('a:potash'))) like 'err:23514%');
select pg_temp.check('an item with no name and no template item is refused',
  pg_temp.try_as(pg_temp.id('user:owner_a'), format(
    'insert into public.input_items (id, farm_id) values (%L, %L)', gen_random_uuid(), pg_temp.id('farm:a'))) like 'err:23514%');
select pg_temp.check('a movement cannot use another farm''s item',
  pg_temp.try_as(pg_temp.id('user:owner_a'), format(
    'insert into public.stock_movements (id, farm_id, item_id, moved_on, kind, quantity, reason) values (%L, %L, %L, %L, %L, 1000, %L)',
    gen_random_uuid(), pg_temp.id('farm:a'), pg_temp.id('b:potash'), '2026-06-02', 'adjustment', 'found')) like 'err:23503%');

-- ---------- who sees what ----------
select pg_temp.check('a supervisor sees how much was bought',
  pg_temp.try_as(pg_temp.id('user:supervisor_a'), format(
    'select 1 from public.stock_movements where id = %L', pg_temp.id('a:bought'))) = 'ok:1');
select pg_temp.check('a supervisor never sees what it cost',
  pg_temp.try_as(pg_temp.id('user:supervisor_a'), format(
    'select 1 from public.expenses where id = %L', pg_temp.id('a:expense'))) = 'ok:0');

-- ---------- sync ----------
select pg_temp.check('a supervisor uploads an application and its movement',
  (select (v -> 'rejected') = '[]' and (v -> 'conflicts') = '[]' and jsonb_array_length(v -> 'accepted') = 2
   from pg_temp.push(pg_temp.id('user:supervisor_a'), 'batch:apply', pg_temp.id('farm:a'), jsonb_build_array(
     pg_temp.r('input_applications', pg_temp.id('a:apply'), pg_temp.id('farm:a'), jsonb_build_object(
       'applied_on', '2026-06-15', 'item_id', pg_temp.id('a:potash'), 'plot_id', pg_temp.id('a:plot'),
       'crop_cycle_id', pg_temp.id('a:cycle'), 'waiting_days', 15, 'dose', '2 ml per litre')),
     pg_temp.r('stock_movements', pg_temp.id('a:used'), pg_temp.id('farm:a'), jsonb_build_object(
       'item_id', pg_temp.id('a:potash'), 'moved_on', '2026-06-15', 'kind', 'application', 'quantity', -30000,
       'application_id', pg_temp.id('a:apply'))))) v)
  and (select dose from public.input_applications where id = pg_temp.id('a:apply')) = '2 ml per litre');
select pg_temp.check('an accountant cannot upload an application (daily work)',
  (select jsonb_array_length(v -> 'rejected') = 1
   from pg_temp.push(pg_temp.id('user:accountant_a'), 'batch:accountant', pg_temp.id('farm:a'), jsonb_build_array(
     pg_temp.r('input_applications', pg_temp.id('a:apply2'), pg_temp.id('farm:a'), jsonb_build_object(
       'applied_on', '2026-06-16', 'item_id', pg_temp.id('a:potash'), 'plot_id', pg_temp.id('a:plot'),
       'crop_cycle_id', pg_temp.id('a:cycle'))))) v));
select pg_temp.check('a harvest keeps its reason for harvesting inside a waiting period',
  (select jsonb_array_length(v -> 'accepted') = 1
   from pg_temp.push(pg_temp.id('user:supervisor_a'), 'batch:harvest', pg_temp.id('farm:a'), jsonb_build_array(
     pg_temp.r('harvests', pg_temp.id('a:harvest'), pg_temp.id('farm:a'), jsonb_build_object(
       'crop_cycle_id', pg_temp.id('a:cycle'), 'plot_id', pg_temp.id('a:plot'), 'harvested_on', '2026-06-20',
       'quantity', 120000, 'waiting_override_reason', 'Rain expected')))) v)
  and (select waiting_override_reason from public.harvests where id = pg_temp.id('a:harvest')) = 'Rain expected');
select pg_temp.check('the history of an application is daily work, so a supervisor reads it',
  pg_temp.try_as(pg_temp.id('user:supervisor_a'), format(
    'insert into public.event_log (id, farm_id, entity, entity_id, action, occurred_on) values (%L, %L, %L, %L, %L, %L)',
    gen_random_uuid(), pg_temp.id('farm:a'), 'input_applications', pg_temp.id('a:apply'), 'create', '2026-06-15')) = 'ok:1');

-- ---------- templates ----------
select pg_temp.check('release 3 brings four input methods and twelve soil parameters',
  (select count(*) from public.template_items where list_type = 'input_method' and template_version = 3) = 4
  and (select count(*) from public.template_items where list_type = 'soil_parameter' and template_version = 3) = 12);
select pg_temp.check('release 3 brings ml, a thousandth of a litre',
  (select count(*) from public.template_items where list_type = 'unit' and code = 'ml' and crop_id is null
     and template_version = 3 and data = '{"dimension": "volume", "factor": 0.001}'::jsonb) = 1);
select pg_temp.check('no template item carries a waiting period or dose',
  not exists (select 1 from public.template_items where data ? 'waiting_days' or data ? 'dose'));

-- ---------- result ----------
-- Always raises, so nothing above can be committed; the message is the summary.
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
  raise exception 'TEST SUMMARY e1_inputs: passed=% failed=% %', v_passed, v_failed,
    case when v_failed > 0 then chr(10) || v_failures else '' end;
end $$;

rollback;
