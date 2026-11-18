-- B1 role and safety tests (implementation plan section 6, B1 "Tests"). Run with tool/server_tests.py.
--
-- Run against a database that has the migrations applied:
--   supabase db query --remote=<project ref> -f supabase/tests/b1_roles.sql
-- Everything runs in one transaction that ends by raising its summary as an error, so the
-- test users, farms and rows never stay in the database. Look for "TEST SUMMARY" in the output.

begin;

create temp table results (n serial, name text, ok boolean, detail text);
create temp table expected (cls text, role text, level integer);

-- Role defaults from product spec rule 7, written out by hand (not read from the schema).
-- 0 none, 1 read, 2 write.
insert into expected values
  ('setup', 'owner', 2), ('setup', 'manager', 2), ('setup', 'supervisor', 1), ('setup', 'accountant', 1), ('setup', 'viewer', 1),
  ('team', 'owner', 2), ('team', 'manager', 2), ('team', 'supervisor', 2), ('team', 'accountant', 1), ('team', 'viewer', 1),
  ('daily', 'owner', 2), ('daily', 'manager', 2), ('daily', 'supervisor', 2), ('daily', 'accountant', 1), ('daily', 'viewer', 1),
  ('stock', 'owner', 2), ('stock', 'manager', 2), ('stock', 'supervisor', 2), ('stock', 'accountant', 2), ('stock', 'viewer', 1),
  ('money', 'owner', 2), ('money', 'manager', 2), ('money', 'supervisor', 0), ('money', 'accountant', 2), ('money', 'viewer', 1),
  ('prices', 'owner', 2), ('prices', 'manager', 2), ('prices', 'supervisor', 1), ('prices', 'accountant', 2), ('prices', 'viewer', 1);

create function pg_temp.check(p_name text, p_ok boolean, p_detail text default null) returns void
language sql as $$ insert into results (name, ok, detail) values (p_name, coalesce(p_ok, false), p_detail) $$;

create function pg_temp.fx_id(p_tag text, p_name text) returns uuid
language sql immutable as $$ select md5('b1test:' || p_tag || ':' || p_name)::uuid $$;

create function pg_temp.u(p_name text) returns uuid
language sql immutable as $$ select pg_temp.fx_id('user', p_name) $$;

-- Runs p_sql as p_user and always undoes it; returns 'ok:<rows>' or 'err:<code> <message>'.
create function pg_temp.try_as(p_user uuid, p_sql text, p_role text default 'authenticated') returns text
language plpgsql as $$
declare
  n bigint;
  v text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', p_role)::text, true);
  begin
    execute format('set local role %I', p_role);
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

-- Runs p_sql as p_user and keeps the result.
create function pg_temp.run_as(p_user uuid, p_sql text) returns text
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
    execute 'reset role';
    v := 'ok:' || n;
  exception when others then
    v := 'err:' || sqlstate || ' ' || sqlerrm;
  end;
  perform set_config('request.jwt.claims', '', true);
  return v;
end $$;

-- ---------- fixtures ----------
insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at, raw_user_meta_data, created_at, updated_at)
select pg_temp.u(x), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
  x || '@example.com', now(), jsonb_build_object('full_name', x), now(), now()
from unnest(array['owner_a', 'manager_a', 'supervisor_a', 'accountant_a', 'viewer_a', 'owner_b', 'newcomer', 'stranger',
  'emailonly', 'creator']) x;
-- everyone signs in with Google except emailonly
insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
select pg_temp.u(x)::text, pg_temp.u(x), jsonb_build_object('sub', pg_temp.u(x)::text, 'email', x || '@example.com'),
  'google', now(), now(), now()
from unnest(array['owner_a', 'manager_a', 'supervisor_a', 'accountant_a', 'viewer_a', 'owner_b', 'newcomer', 'stranger',
  'creator']) x;

create function pg_temp.make_rows(t text, f uuid, o uuid) returns void
language plpgsql as $$
declare
  coconut uuid := (select id from public.crops where code = 'coconut' and owner_farm_id is null);
begin
  insert into public.plots (id, farm_id, name) values (pg_temp.fx_id(t, 'plots'), f, 'Plot');
  insert into public.crop_cycles (id, farm_id, plot_id, crop_id)
    values (pg_temp.fx_id(t, 'crop_cycles'), f, pg_temp.fx_id(t, 'plots'), coconut);
  insert into public.template_overrides (id, farm_id, scope, list_type, code, name_ml, name_en)
    values (pg_temp.fx_id(t, 'template_overrides'), f, 'farm', 'expense_category', 'own', 'സ്വന്തം', 'Own');
  insert into public.tasks (id, farm_id, title) values (pg_temp.fx_id(t, 'tasks'), f, 'Task');
  insert into public.notes (id, farm_id, noted_on, body) values (pg_temp.fx_id(t, 'notes'), f, current_date, 'Note');
  insert into public.parties (id, farm_id, kind, name) values (pg_temp.fx_id(t, 'parties'), f, 'buyer', 'Buyer');
  insert into public.workers (id, farm_id, name) values (pg_temp.fx_id(t, 'workers'), f, 'Worker');
  insert into public.labour_groups (id, farm_id, label) values (pg_temp.fx_id(t, 'labour_groups'), f, 'Group');
  insert into public.labour_group_members (id, farm_id, group_id, worker_id)
    values (pg_temp.fx_id(t, 'labour_group_members'), f, pg_temp.fx_id(t, 'labour_groups'), pg_temp.fx_id(t, 'workers'));
  insert into public.harvests (id, farm_id, crop_cycle_id, plot_id, harvested_on, quantity)
    values (pg_temp.fx_id(t, 'harvests'), f, pg_temp.fx_id(t, 'crop_cycles'), pg_temp.fx_id(t, 'plots'), current_date, 120000);
  insert into public.labour_entries (id, farm_id, work_date, worker_id, rate_paise, amount_paise)
    values (pg_temp.fx_id(t, 'labour_entries'), f, current_date, pg_temp.fx_id(t, 'workers'), 90000, 90000);
  insert into public.labour_allocations (id, farm_id, labour_entry_id, crop_cycle_id, amount_paise)
    values (pg_temp.fx_id(t, 'labour_allocations'), f, pg_temp.fx_id(t, 'labour_entries'), pg_temp.fx_id(t, 'crop_cycles'), 90000);
  insert into public.labour_payments (id, farm_id, paid_on, worker_id, kind, amount_paise)
    values (pg_temp.fx_id(t, 'labour_payments'), f, current_date, pg_temp.fx_id(t, 'workers'), 'advance', 50000);
  insert into public.expenses (id, farm_id, spent_on, category_code, amount_paise)
    values (pg_temp.fx_id(t, 'expenses'), f, current_date, 'fertiliser', 360000);
  insert into public.expense_allocations (id, farm_id, expense_id, crop_cycle_id, amount_paise)
    values (pg_temp.fx_id(t, 'expense_allocations'), f, pg_temp.fx_id(t, 'expenses'), pg_temp.fx_id(t, 'crop_cycles'), 360000);
  insert into public.expense_payments (id, farm_id, expense_id, paid_on, amount_paise)
    values (pg_temp.fx_id(t, 'expense_payments'), f, pg_temp.fx_id(t, 'expenses'), current_date, 100000);
  insert into public.lots (id, farm_id, crop_cycle_id, harvest_id, quantity) values
    (pg_temp.fx_id(t, 'lots'), f, pg_temp.fx_id(t, 'crop_cycles'), pg_temp.fx_id(t, 'harvests'), 120000),
    (pg_temp.fx_id(t, 'lot_spare'), f, pg_temp.fx_id(t, 'crop_cycles'), null, 1000);
  insert into public.lot_costs (id, farm_id, cost_paise) values (pg_temp.fx_id(t, 'lots'), f, 2856000);
  insert into public.sales (id, farm_id, sold_on, quantity, rate_paise, net_paise)
    values (pg_temp.fx_id(t, 'sales'), f, current_date, 50000, 70500, 3508000);
  insert into public.sale_lots (id, farm_id, sale_id, lot_id, quantity)
    values (pg_temp.fx_id(t, 'sale_lots'), f, pg_temp.fx_id(t, 'sales'), pg_temp.fx_id(t, 'lots'), 50000);
  insert into public.sale_payments (id, farm_id, sale_id, received_on, amount_paise)
    values (pg_temp.fx_id(t, 'sale_payments'), f, pg_temp.fx_id(t, 'sales'), current_date, 3508000);
  insert into public.other_income (id, farm_id, received_on, source_code, amount_paise)
    values (pg_temp.fx_id(t, 'other_income'), f, current_date, 'subsidy', 100000);
  insert into public.market_prices (id, farm_id, crop_id, market, price_paise, source, published_at)
    values (pg_temp.fx_id(t, 'market_prices'), f, coconut, 'Kattappana', 3500, 'local', now());
  insert into public.price_alerts (id, farm_id, user_id, crop_id, threshold_paise)
    values (pg_temp.fx_id(t, 'price_alerts'), f, o, coconut, 4000);
  insert into public.event_log (id, farm_id, entity, entity_id, action, occurred_on) values
    (pg_temp.fx_id(t, 'event_plots'), f, 'plots', pg_temp.fx_id(t, 'plots'), 'create', current_date),
    (pg_temp.fx_id(t, 'event_expenses'), f, 'expenses', pg_temp.fx_id(t, 'expenses'), 'create', current_date);
end $$;

select pg_temp.check('owner A creates farm A',
  pg_temp.run_as(pg_temp.u('owner_a'), format('select public.create_farm(%L, %L, %L)',
    pg_temp.fx_id('farm', 'a'), pg_temp.fx_id('a', 'm_owner'), 'Farm A')) = 'ok:1');
select pg_temp.check('owner B creates farm B',
  pg_temp.run_as(pg_temp.u('owner_b'), format('select public.create_farm(%L, %L, %L)',
    pg_temp.fx_id('farm', 'b'), pg_temp.fx_id('b', 'm_owner'), 'Farm B')) = 'ok:1');

insert into public.farm_members (id, farm_id, user_id, role)
select pg_temp.fx_id('a', 'm_' || r), pg_temp.fx_id('farm', 'a'), pg_temp.u(r || '_a'), r
from unnest(array['manager', 'supervisor', 'accountant', 'viewer']) r;

select pg_temp.make_rows('a', pg_temp.fx_id('farm', 'a'), pg_temp.u('owner_a'));
select pg_temp.make_rows('b', pg_temp.fx_id('farm', 'b'), pg_temp.u('owner_b'));

-- ---------- farm creation ----------
select pg_temp.check('create_farm makes the creator owner',
  exists (select 1 from public.farm_members where farm_id = pg_temp.fx_id('farm', 'a')
          and user_id = pg_temp.u('owner_a') and role = 'owner'));
select pg_temp.check('create_farm again by the same person returns the farm',
  pg_temp.try_as(pg_temp.u('owner_a'), format('select public.create_farm(%L, %L, %L)',
    pg_temp.fx_id('farm', 'a'), pg_temp.fx_id('a', 'm_owner'), 'Farm A')) = 'ok:1');
select pg_temp.check('create_farm with someone else''s farm id fails',
  pg_temp.try_as(pg_temp.u('stranger'), format('select public.create_farm(%L, %L, %L)',
    pg_temp.fx_id('farm', 'a'), gen_random_uuid(), 'Mine')) like 'err:%');
select pg_temp.check('clients cannot insert farms directly',
  pg_temp.try_as(pg_temp.u('stranger'), format('insert into public.farms (id, name) values (%L, %L)',
    gen_random_uuid(), 'X')) like 'err:%');

-- ---------- the role table, for every farm-owned table ----------
do $$
declare
  r record;
  v_role text;
  v_user uuid;
  v_json jsonb;
  v_res text;
  v_exp integer;
  v_read integer;
  v_id uuid;
begin
  for r in select t.name, t.access_class from public.sync_tables t
    where t.name not in ('template_items', 'farms', 'farm_members', 'farm_invites', 'crops', 'event_log', 'price_alerts')
    order by t.sort_order
  loop
    -- a lot's cost row has its lot's id
    v_id := pg_temp.fx_id('a', case when r.name = 'lot_costs' then 'lots' else r.name end);
    execute format('select to_jsonb(x) from public.%I x where id = %L', r.name, v_id) into v_json;
    if v_json is null then
      perform pg_temp.check(r.name || ' fixture exists', false);
      continue;
    end if;
    v_json := v_json || jsonb_build_object('id',
      case when r.name = 'lot_costs' then pg_temp.fx_id('a', 'lot_spare') else gen_random_uuid() end);
    foreach v_role in array array['owner', 'manager', 'supervisor', 'accountant', 'viewer'] loop
      v_user := pg_temp.u(v_role || '_a');
      select level into v_exp from expected where cls = r.access_class and role = v_role;
      -- what was taken from a lot is part of its stock, so stock readers see sale_lots
      select level into v_read from expected
        where cls = case r.name when 'sale_lots' then 'stock' else r.access_class end and role = v_role;
      v_res := pg_temp.try_as(v_user, format('select 1 from public.%I where id = %L', r.name, v_id));
      perform pg_temp.check(format('%s reads %s: %s', v_role, r.name, v_read >= 1),
        v_res = case when v_read >= 1 then 'ok:1' else 'ok:0' end, v_res);
      v_res := pg_temp.try_as(v_user, format(
        'insert into public.%I select * from jsonb_populate_record(null::public.%I, %L::jsonb)', r.name, r.name, v_json));
      perform pg_temp.check(format('%s inserts %s: %s', v_role, r.name, v_exp = 2), (v_res = 'ok:1') = (v_exp = 2), v_res);
      v_res := pg_temp.try_as(v_user, format('update public.%I set updated_at = now() where id = %L', r.name, v_id));
      perform pg_temp.check(format('%s updates %s: %s', v_role, r.name, v_exp = 2), (v_res = 'ok:1') = (v_exp = 2), v_res);
      v_res := pg_temp.try_as(v_user, format('delete from public.%I where id = %L', r.name, v_id));
      perform pg_temp.check(format('%s cannot hard-delete %s', v_role, r.name), v_res like 'err:%', v_res);
    end loop;
    v_res := pg_temp.try_as(pg_temp.u('owner_b'), format('select 1 from public.%I where id = %L', r.name, v_id));
    perform pg_temp.check(format('farm B owner cannot read farm A %s', r.name), v_res = 'ok:0', v_res);
    v_res := pg_temp.try_as(pg_temp.u('owner_b'), format(
      'insert into public.%I select * from jsonb_populate_record(null::public.%I, %L::jsonb)', r.name, r.name, v_json));
    perform pg_temp.check(format('farm B owner cannot write farm A %s', r.name), v_res like 'err:%', v_res);
    v_res := pg_temp.try_as(pg_temp.u('owner_a'), format('truncate public.%I', r.name));
    perform pg_temp.check(format('owner cannot truncate %s', r.name), v_res like 'err:%', v_res);
    v_res := pg_temp.try_as(null, format('select 1 from public.%I', r.name), 'anon');
    perform pg_temp.check(format('signed-out user cannot read %s', r.name), v_res like 'err:%', v_res);
  end loop;
end $$;

-- ---------- farms and members ----------
select pg_temp.check(format('%s reads farm A', x),
  pg_temp.try_as(pg_temp.u(x || '_a'), format('select 1 from public.farms where id = %L', pg_temp.fx_id('farm', 'a'))) = 'ok:1')
from unnest(array['owner', 'manager', 'supervisor', 'accountant', 'viewer']) x;
select pg_temp.check('farm B owner cannot read farm A',
  pg_temp.try_as(pg_temp.u('owner_b'), format('select 1 from public.farms where id = %L', pg_temp.fx_id('farm', 'a'))) = 'ok:0');
select pg_temp.check('manager updates farm settings',
  pg_temp.try_as(pg_temp.u('manager_a'), format('update public.farms set name = %L where id = %L', 'A2', pg_temp.fx_id('farm', 'a'))) = 'ok:1');
select pg_temp.check('supervisor cannot update farm settings',
  pg_temp.try_as(pg_temp.u('supervisor_a'), format('update public.farms set name = %L where id = %L', 'A2', pg_temp.fx_id('farm', 'a'))) = 'ok:0');

select pg_temp.check('owner sees every member',
  pg_temp.try_as(pg_temp.u('owner_a'), format('select 1 from public.farm_members where farm_id = %L', pg_temp.fx_id('farm', 'a'))) = 'ok:5');
select pg_temp.check('manager sees only their own membership',
  pg_temp.try_as(pg_temp.u('manager_a'), format('select 1 from public.farm_members where farm_id = %L', pg_temp.fx_id('farm', 'a'))) = 'ok:1');
select pg_temp.check('manager cannot change members',
  pg_temp.try_as(pg_temp.u('manager_a'), format('update public.farm_members set role = %L where id = %L', 'accountant', pg_temp.fx_id('a', 'm_viewer'))) = 'ok:0');
select pg_temp.check('owner changes a member''s role',
  pg_temp.try_as(pg_temp.u('owner_a'), format('update public.farm_members set role = %L where id = %L', 'accountant', pg_temp.fx_id('a', 'm_viewer'))) = 'ok:1');
select pg_temp.check('clients cannot insert memberships',
  pg_temp.try_as(pg_temp.u('owner_a'), format('insert into public.farm_members (id, farm_id, user_id, role) values (%L, %L, %L, %L)',
    gen_random_uuid(), pg_temp.fx_id('farm', 'a'), pg_temp.u('stranger'), 'viewer')) like 'err:%');
select pg_temp.check('a membership cannot move to another person',
  pg_temp.try_as(pg_temp.u('owner_a'), format('update public.farm_members set user_id = %L where id = %L',
    pg_temp.u('stranger'), pg_temp.fx_id('a', 'm_viewer'))) like 'err:%');

-- per-person permissions override the role
select pg_temp.check('owner lets the supervisor read money',
  pg_temp.run_as(pg_temp.u('owner_a'), format('update public.farm_members set permissions = %L where id = %L',
    '{"money": "read"}', pg_temp.fx_id('a', 'm_supervisor'))) = 'ok:1');
select pg_temp.check('supervisor with money read sees expenses',
  pg_temp.try_as(pg_temp.u('supervisor_a'), format('select 1 from public.expenses where id = %L', pg_temp.fx_id('a', 'expenses'))) = 'ok:1');
select pg_temp.check('supervisor with money read still cannot write expenses',
  pg_temp.try_as(pg_temp.u('supervisor_a'), format('update public.expenses set notes = %L where id = %L', 'x', pg_temp.fx_id('a', 'expenses'))) = 'ok:0');
select pg_temp.run_as(pg_temp.u('owner_a'), format('update public.farm_members set permissions = %L where id = %L',
  '{}', pg_temp.fx_id('a', 'm_supervisor')));

-- a member trusted with members cannot make or touch owners
select pg_temp.run_as(pg_temp.u('owner_a'), format('update public.farm_members set permissions = %L where id = %L',
  '{"members": "write"}', pg_temp.fx_id('a', 'm_manager')));
select pg_temp.check('manager with members write cannot make an owner',
  pg_temp.try_as(pg_temp.u('manager_a'), format('update public.farm_members set role = %L where id = %L', 'owner', pg_temp.fx_id('a', 'm_viewer'))) like 'err:42501%');
select pg_temp.check('manager with members write cannot remove the owner',
  pg_temp.try_as(pg_temp.u('manager_a'), format('update public.farm_members set deleted_at = now() where id = %L', pg_temp.fx_id('a', 'm_owner'))) = 'ok:0');
select pg_temp.check('manager with members write changes a viewer',
  pg_temp.try_as(pg_temp.u('manager_a'), format('update public.farm_members set role = %L where id = %L', 'accountant', pg_temp.fx_id('a', 'm_viewer'))) = 'ok:1');
select pg_temp.run_as(pg_temp.u('owner_a'), format('update public.farm_members set permissions = %L where id = %L',
  '{}', pg_temp.fx_id('a', 'm_manager')));

-- ---------- invites ----------
select pg_temp.check('owner invites a newcomer',
  pg_temp.run_as(pg_temp.u('owner_a'), format(
    'insert into public.farm_invites (id, farm_id, email, role) values (%L, %L, %L, %L), (%L, %L, %L, %L)',
    pg_temp.fx_id('a', 'invite_new'), pg_temp.fx_id('farm', 'a'), 'newcomer@example.com', 'accountant',
    pg_temp.fx_id('a', 'invite_stranger'), pg_temp.fx_id('farm', 'a'), 'stranger@example.com', 'viewer')) = 'ok:2');
select pg_temp.check('owner withdraws an invite',
  pg_temp.run_as(pg_temp.u('owner_a'), format('update public.farm_invites set deleted_at = now() where id = %L',
    pg_temp.fx_id('a', 'invite_stranger'))) = 'ok:1');
select pg_temp.check('manager cannot invite',
  pg_temp.try_as(pg_temp.u('manager_a'), format('insert into public.farm_invites (id, farm_id, email, role) values (%L, %L, %L, %L)',
    gen_random_uuid(), pg_temp.fx_id('farm', 'a'), 'x@example.com', 'viewer')) like 'err:%');
select pg_temp.check('manager cannot read invites',
  pg_temp.try_as(pg_temp.u('manager_a'), 'select 1 from public.farm_invites') = 'ok:0');
select pg_temp.check('newcomer accepts the invite at sign-in',
  pg_temp.run_as(pg_temp.u('newcomer'), 'select public.accept_invites()') = 'ok:1');
select pg_temp.check('newcomer is now an accountant on farm A',
  exists (select 1 from public.farm_members where farm_id = pg_temp.fx_id('farm', 'a')
          and user_id = pg_temp.u('newcomer') and role = 'accountant' and deleted_at is null));
select pg_temp.check('newcomer reads farm A money',
  pg_temp.try_as(pg_temp.u('newcomer'), format('select 1 from public.expenses where id = %L', pg_temp.fx_id('a', 'expenses'))) = 'ok:1');
select pg_temp.check('an accepted invite is not accepted twice',
  pg_temp.run_as(pg_temp.u('newcomer'), 'select public.accept_invites()') = 'ok:0');
select pg_temp.check('a withdrawn invite is never accepted',
  pg_temp.run_as(pg_temp.u('stranger'), 'select public.accept_invites()') = 'ok:0');
select pg_temp.check('stranger still cannot read farm A',
  pg_temp.try_as(pg_temp.u('stranger'), format('select 1 from public.plots where id = %L', pg_temp.fx_id('a', 'plots'))) = 'ok:0');

-- ---------- history ----------
select pg_temp.check('supervisor reads set-up history',
  pg_temp.try_as(pg_temp.u('supervisor_a'), format('select 1 from public.event_log where id = %L', pg_temp.fx_id('a', 'event_plots'))) = 'ok:1');
select pg_temp.check('supervisor cannot read money history',
  pg_temp.try_as(pg_temp.u('supervisor_a'), format('select 1 from public.event_log where id = %L', pg_temp.fx_id('a', 'event_expenses'))) = 'ok:0');
select pg_temp.check('viewer reads money history',
  pg_temp.try_as(pg_temp.u('viewer_a'), format('select 1 from public.event_log where id = %L', pg_temp.fx_id('a', 'event_expenses'))) = 'ok:1');
select pg_temp.check('supervisor writes history for daily work',
  pg_temp.try_as(pg_temp.u('supervisor_a'), format(
    'insert into public.event_log (id, farm_id, entity, entity_id, action, occurred_on) values (%L, %L, %L, %L, %L, current_date)',
    gen_random_uuid(), pg_temp.fx_id('farm', 'a'), 'harvests', gen_random_uuid(), 'create')) = 'ok:1');
select pg_temp.check('supervisor cannot write money history',
  pg_temp.try_as(pg_temp.u('supervisor_a'), format(
    'insert into public.event_log (id, farm_id, entity, entity_id, action, occurred_on) values (%L, %L, %L, %L, %L, current_date)',
    gen_random_uuid(), pg_temp.fx_id('farm', 'a'), 'expenses', gen_random_uuid(), 'create')) like 'err:%');
select pg_temp.check('viewer cannot write history',
  pg_temp.try_as(pg_temp.u('viewer_a'), format(
    'insert into public.event_log (id, farm_id, entity, entity_id, action, occurred_on) values (%L, %L, %L, %L, %L, current_date)',
    gen_random_uuid(), pg_temp.fx_id('farm', 'a'), 'plots', gen_random_uuid(), 'create')) like 'err:%');
select pg_temp.check('history of an unknown table cannot be written',
  pg_temp.try_as(pg_temp.u('owner_a'), format(
    'insert into public.event_log (id, farm_id, entity, entity_id, action, occurred_on) values (%L, %L, %L, %L, %L, current_date)',
    gen_random_uuid(), pg_temp.fx_id('farm', 'a'), 'secrets', gen_random_uuid(), 'create')) like 'err:%');
select pg_temp.check('owner cannot change history',
  pg_temp.try_as(pg_temp.u('owner_a'), format('update public.event_log set action = %L where id = %L', 'delete', pg_temp.fx_id('a', 'event_plots'))) <> 'ok:1');
select pg_temp.check('owner cannot delete history',
  pg_temp.try_as(pg_temp.u('owner_a'), format('delete from public.event_log where id = %L', pg_temp.fx_id('a', 'event_plots'))) like 'err:%');
select pg_temp.check('owner cannot truncate history',
  pg_temp.try_as(pg_temp.u('owner_a'), 'truncate public.event_log') like 'err:%');
do $$
begin
  update public.event_log set action = 'delete' where id = pg_temp.fx_id('a', 'event_plots');
  perform pg_temp.check('not even the server can change history', false);
exception when others then
  perform pg_temp.check('not even the server can change history', true);
end $$;

-- ---------- stamps, versions, server_seq ----------
create temp table before_update as
  select server_seq, version from public.plots where id = pg_temp.fx_id('a', 'plots');
select pg_temp.run_as(pg_temp.u('manager_a'), format('update public.plots set name = %L, created_by = %L where id = %L',
  'Renamed', pg_temp.u('stranger'), pg_temp.fx_id('a', 'plots')));
select pg_temp.check('an update is stamped with the person who made it',
  (select updated_by from public.plots where id = pg_temp.fx_id('a', 'plots')) = pg_temp.u('manager_a'));
select pg_temp.check('an update cannot change who created the row',
  (select created_by from public.plots where id = pg_temp.fx_id('a', 'plots')) is distinct from pg_temp.u('stranger'));
select pg_temp.check('the server does not change version',
  (select p.version = b.version from public.plots p, before_update b where p.id = pg_temp.fx_id('a', 'plots')));
select pg_temp.check('every write takes a new server_seq',
  (select p.server_seq > b.server_seq from public.plots p, before_update b where p.id = pg_temp.fx_id('a', 'plots')));
select pg_temp.run_as(pg_temp.u('manager_a'), format('insert into public.plots (id, farm_id, name, created_by) values (%L, %L, %L, %L)',
  pg_temp.fx_id('a', 'plot_2'), pg_temp.fx_id('farm', 'a'), 'Plot 2', pg_temp.u('owner_b')));
select pg_temp.check('an insert is stamped with the person who made it',
  (select created_by from public.plots where id = pg_temp.fx_id('a', 'plot_2')) = pg_temp.u('manager_a'));
do $$
begin
  update public.plots set farm_id = pg_temp.fx_id('farm', 'b') where id = pg_temp.fx_id('a', 'plots');
  perform pg_temp.check('a row cannot move to another farm', false);
exception when others then
  perform pg_temp.check('a row cannot move to another farm', true);
end $$;

-- ---------- templates and crops ----------
select pg_temp.check('wave 1 crops are seeded',
  (select count(*) from public.crops where owner_farm_id is null
   and code in ('coconut', 'rubber', 'pepper', 'banana', 'paddy', 'cardamom')) = 6);
select pg_temp.check('every seeded crop has activities, grades and labour tasks',
  (select count(*) from public.crops c where c.owner_farm_id is null and
     (select count(distinct t.list_type) from public.template_items t
      where t.crop_id = c.id and t.list_type in ('activity', 'grade', 'labour_task', 'setting')) = 4) = 6);
select pg_temp.check('viewer reads templates',
  pg_temp.try_as(pg_temp.u('viewer_a'), 'select 1 from public.template_items limit 1') = 'ok:1');
select pg_temp.check('clients cannot write templates',
  pg_temp.try_as(pg_temp.u('owner_a'), format('update public.template_items set name_en = %L', 'x')) = 'ok:0');
do $$
begin
  insert into public.template_items (id, crop_id, list_type, code, name_ml, name_en)
  values (gen_random_uuid(), null, 'unit', 'kg', 'കിലോ', 'kg');
  perform pg_temp.check('no duplicate item for all crops', false);
exception when unique_violation then
  perform pg_temp.check('no duplicate item for all crops', true);
end $$;
do $$
begin
  insert into public.crops (id, code, name_ml, name_en, kind) values (gen_random_uuid(), 'coconut', 'തെങ്ങ്', 'Coconut', 'perennial');
  perform pg_temp.check('no duplicate standard crop code', false);
exception when unique_violation then
  perform pg_temp.check('no duplicate standard crop code', true);
end $$;
select pg_temp.check('owner adds their own crop',
  pg_temp.run_as(pg_temp.u('owner_a'), format('insert into public.crops (id, code, name_ml, name_en, kind, owner_farm_id) values (%L, %L, %L, %L, %L, %L)',
    pg_temp.fx_id('a', 'crop_jack'), 'jackfruit', 'പ്ലാവ്', 'Jackfruit', 'perennial', pg_temp.fx_id('farm', 'a'))) = 'ok:1');
select pg_temp.check('the same own crop code twice on one farm fails',
  pg_temp.try_as(pg_temp.u('owner_a'), format('insert into public.crops (id, code, name_ml, name_en, kind, owner_farm_id) values (%L, %L, %L, %L, %L, %L)',
    gen_random_uuid(), 'jackfruit', 'പ്ലാവ്', 'Jackfruit', 'perennial', pg_temp.fx_id('farm', 'a'))) like 'err:%');
select pg_temp.check('another farm can use the same own crop code',
  pg_temp.try_as(pg_temp.u('owner_b'), format('insert into public.crops (id, code, name_ml, name_en, kind, owner_farm_id) values (%L, %L, %L, %L, %L, %L)',
    gen_random_uuid(), 'jackfruit', 'പ്ലാവ്', 'Jackfruit', 'perennial', pg_temp.fx_id('farm', 'b'))) = 'ok:1');
select pg_temp.check('supervisor cannot add a crop',
  pg_temp.try_as(pg_temp.u('supervisor_a'), format('insert into public.crops (id, code, name_ml, name_en, kind, owner_farm_id) values (%L, %L, %L, %L, %L, %L)',
    gen_random_uuid(), 'mango', 'മാവ്', 'Mango', 'perennial', pg_temp.fx_id('farm', 'a'))) like 'err:%');
select pg_temp.check('farm B cannot see farm A''s own crop',
  pg_temp.try_as(pg_temp.u('owner_b'), format('select 1 from public.crops where id = %L', pg_temp.fx_id('a', 'crop_jack'))) = 'ok:0');
select pg_temp.check('clients cannot add standard crops',
  pg_temp.try_as(pg_temp.u('owner_a'), format('insert into public.crops (id, code, name_ml, name_en, kind) values (%L, %L, %L, %L, %L)',
    gen_random_uuid(), 'mango', 'മാവ്', 'Mango', 'perennial')) like 'err:%');

-- ---------- profiles ----------
select pg_temp.check('a profile is created for every new account',
  (select count(*) from public.profiles where id in (select pg_temp.u(x) from unnest(array['owner_a', 'manager_a',
    'supervisor_a', 'accountant_a', 'viewer_a', 'owner_b', 'newcomer', 'stranger']) x)) = 8);
select pg_temp.check('owner reads a co-member''s profile',
  pg_temp.try_as(pg_temp.u('owner_a'), format('select 1 from public.profiles where id = %L', pg_temp.u('manager_a'))) = 'ok:1');
select pg_temp.check('owner cannot read another farm''s profiles',
  pg_temp.try_as(pg_temp.u('owner_a'), format('select 1 from public.profiles where id = %L', pg_temp.u('owner_b'))) = 'ok:0');
select pg_temp.check('nobody edits someone else''s profile',
  pg_temp.try_as(pg_temp.u('owner_a'), format('update public.profiles set full_name = %L where id = %L', 'x', pg_temp.u('manager_a'))) = 'ok:0');

-- ---------- review fixes ----------
-- an invite never changes an active membership, so it cannot demote the owner
select pg_temp.run_as(pg_temp.u('owner_a'), format('update public.farm_members set permissions = %L where id = %L',
  '{"members": "write"}', pg_temp.fx_id('a', 'm_manager')));
select pg_temp.check('a member trusted with members can invite the owner''s email',
  pg_temp.run_as(pg_temp.u('manager_a'), format('insert into public.farm_invites (id, farm_id, email, role) values (%L, %L, %L, %L)',
    pg_temp.fx_id('a', 'invite_owner'), pg_temp.fx_id('farm', 'a'), 'owner_a@example.com', 'viewer')) = 'ok:1');
select pg_temp.check('the owner accepts it at the next sync',
  pg_temp.run_as(pg_temp.u('owner_a'), 'select public.accept_invites()') = 'ok:1');
select pg_temp.check('the owner is still the owner',
  (select role = 'owner' and deleted_at is null from public.farm_members where id = pg_temp.fx_id('a', 'm_owner')));
select pg_temp.check('an accepted invite cannot be reopened',
  pg_temp.try_as(pg_temp.u('manager_a'), format('update public.farm_invites set accepted_at = null where id = %L',
    pg_temp.fx_id('a', 'invite_owner'))) = 'ok:0');
select pg_temp.run_as(pg_temp.u('owner_a'), format('update public.farm_members set permissions = %L where id = %L',
  '{}', pg_temp.fx_id('a', 'm_manager')));

-- only an email confirmed by a Google sign-in claims an invite
select pg_temp.run_as(pg_temp.u('owner_a'), format('insert into public.farm_invites (id, farm_id, email, role) values (%L, %L, %L, %L)',
  pg_temp.fx_id('a', 'invite_emailonly'), pg_temp.fx_id('farm', 'a'), 'emailonly@example.com', 'viewer'));
select pg_temp.check('an account without a Google sign-in cannot claim an invite',
  pg_temp.run_as(pg_temp.u('emailonly'), 'select public.accept_invites()') = 'ok:0'
  and not exists (select 1 from public.farm_members where user_id = pg_temp.u('emailonly')));

select pg_temp.check('accepting an invite is written to history',
  exists (select 1 from public.event_log e join public.farm_members m on m.id = e.entity_id
          where e.entity = 'farm_members' and e.action = 'create' and m.user_id = pg_temp.u('newcomer'))
  and exists (select 1 from public.event_log where entity = 'farm_invites' and entity_id = pg_temp.fx_id('a', 'invite_new')));

-- memberships get their own id, so an invite id cannot clash with one
select pg_temp.run_as(pg_temp.u('owner_b'), format('insert into public.farm_invites (id, farm_id, email, role) values (%L, %L, %L, %L)',
  pg_temp.fx_id('a', 'm_owner'), pg_temp.fx_id('farm', 'b'), 'stranger@example.com', 'viewer'));
select pg_temp.check('an invite reusing a membership id cannot block the invitee',
  pg_temp.run_as(pg_temp.u('stranger'), 'select public.accept_invites()') = 'ok:1'
  and exists (select 1 from public.farm_members where farm_id = pg_temp.fx_id('farm', 'b') and user_id = pg_temp.u('stranger')));

-- a row can only point at rows of its own farm
set constraints all immediate;
select pg_temp.check('another farm cannot claim this farm''s lot cost row',
  pg_temp.try_as(pg_temp.u('owner_b'), format('insert into public.lot_costs (id, farm_id, cost_paise) values (%L, %L, 0)',
    pg_temp.fx_id('a', 'lot_spare'), pg_temp.fx_id('farm', 'b'))) like 'err:23503%');
select pg_temp.check('an entry cannot point at another farm''s plot',
  pg_temp.try_as(pg_temp.u('owner_b'), format('insert into public.notes (id, farm_id, noted_on, body, plot_id) values (%L, %L, current_date, %L, %L)',
    gen_random_uuid(), pg_temp.fx_id('farm', 'b'), 'x', pg_temp.fx_id('a', 'plots'))) like 'err:23503%');
select pg_temp.check('an entry still points at its own farm''s plot',
  pg_temp.try_as(pg_temp.u('owner_a'), format('insert into public.notes (id, farm_id, noted_on, body, plot_id) values (%L, %L, current_date, %L, %L)',
    gen_random_uuid(), pg_temp.fx_id('farm', 'a'), 'x', pg_temp.fx_id('a', 'plots'))) = 'ok:1');
set constraints all deferred;

-- nothing a farm changed is hard-deleted from under it
insert into public.template_overrides (id, farm_id, scope, template_item_id, data)
values (pg_temp.fx_id('a', 'override_climber'), pg_temp.fx_id('farm', 'a'), 'farm',
  md5('thottam:item:*:rate_class:climber')::uuid, '{"default_rate_paise": 110000}');
do $$
begin
  delete from public.template_items where id = md5('thottam:item:*:rate_class:climber')::uuid;
  perform pg_temp.check('a template item a farm has changed cannot be hard-deleted', false);
exception when others then
  perform pg_temp.check('a template item a farm has changed cannot be hard-deleted', sqlstate = '23503', sqlerrm);
end $$;
do $$
begin
  delete from auth.users where id = pg_temp.u('viewer_a');
  perform pg_temp.check('an account with a farm cannot be hard-deleted', false);
exception when others then
  perform pg_temp.check('an account with a farm cannot be hard-deleted', sqlstate = '23503', sqlerrm);
end $$;

-- a farm always keeps an owner
select pg_temp.check('the last owner cannot step down',
  pg_temp.try_as(pg_temp.u('owner_a'), format('update public.farm_members set role = %L where id = %L',
    'manager', pg_temp.fx_id('a', 'm_owner'))) like 'err:23514%');
select pg_temp.check('the last owner cannot remove themselves',
  pg_temp.try_as(pg_temp.u('owner_a'), format('update public.farm_members set deleted_at = now() where id = %L',
    pg_temp.fx_id('a', 'm_owner'))) like 'err:23514%');

-- a removed creator gets nothing back from create_farm
select pg_temp.run_as(pg_temp.u('creator'), format('select public.create_farm(%L, %L, %L)',
  pg_temp.fx_id('farm', 'c'), pg_temp.fx_id('c', 'm_creator'), 'Farm C'));
insert into public.farm_members (id, farm_id, user_id, role)
values (pg_temp.fx_id('c', 'm_owner_b'), pg_temp.fx_id('farm', 'c'), pg_temp.u('owner_b'), 'owner');
select pg_temp.check('a second owner removes the creator',
  pg_temp.run_as(pg_temp.u('owner_b'), format('update public.farm_members set deleted_at = now() where id = %L',
    pg_temp.fx_id('c', 'm_creator'))) = 'ok:1');
select pg_temp.check('a removed creator cannot read the farm through create_farm',
  pg_temp.try_as(pg_temp.u('creator'), format('select public.create_farm(%L, %L, %L)',
    pg_temp.fx_id('farm', 'c'), gen_random_uuid(), 'Mine')) like 'err:%');

-- a price alert belongs to the person who set it
select pg_temp.check('a member cannot set a price alert for someone else',
  pg_temp.try_as(pg_temp.u('manager_a'), format('insert into public.price_alerts (id, farm_id, user_id, crop_id, threshold_paise) values (%L, %L, %L, %L, 1)',
    gen_random_uuid(), pg_temp.fx_id('farm', 'a'), pg_temp.u('owner_a'), md5('thottam:crop:coconut')::uuid)) like 'err:42501%');
select pg_temp.check('a member sets their own price alert',
  pg_temp.try_as(pg_temp.u('manager_a'), format('insert into public.price_alerts (id, farm_id, user_id, crop_id, threshold_paise) values (%L, %L, %L, %L, 1)',
    gen_random_uuid(), pg_temp.fx_id('farm', 'a'), pg_temp.u('manager_a'), md5('thottam:crop:coconut')::uuid)) = 'ok:1');
select pg_temp.check('nobody else reads my price alerts',
  pg_temp.try_as(pg_temp.u('manager_a'), format('select 1 from public.price_alerts where id = %L', pg_temp.fx_id('a', 'price_alerts'))) = 'ok:0');
select pg_temp.check('I read and change my own price alerts',
  pg_temp.try_as(pg_temp.u('owner_a'), format('update public.price_alerts set threshold_paise = 1 where id = %L', pg_temp.fx_id('a', 'price_alerts'))) = 'ok:1');
select pg_temp.check('a viewer cannot set a price alert',
  pg_temp.try_as(pg_temp.u('viewer_a'), format('insert into public.price_alerts (id, farm_id, user_id, crop_id, threshold_paise) values (%L, %L, %L, %L, 1)',
    gen_random_uuid(), pg_temp.fx_id('farm', 'a'), pg_temp.u('viewer_a'), md5('thottam:crop:coconut')::uuid)) like 'err:42501%');

-- members see names, never phone numbers
select pg_temp.check('members cannot read each other''s phone numbers',
  pg_temp.try_as(pg_temp.u('owner_a'), format('select phone from public.profiles where id = %L', pg_temp.u('manager_a'))) like 'err:42501%');

-- later migrations start closed
create table public.zz_later_table (id int);
create function public.zz_later_function() returns int language sql as 'select 1';
select pg_temp.check('a table added later is closed to signed-out users',
  not has_table_privilege('anon', 'public.zz_later_table', 'select'));
select pg_temp.check('a table added later cannot be truncated or hard-deleted by clients',
  not has_table_privilege('authenticated', 'public.zz_later_table', 'truncate')
  and not has_table_privilege('authenticated', 'public.zz_later_table', 'delete'));
select pg_temp.check('a function added later is closed to signed-out users',
  not has_function_privilege('anon', 'public.zz_later_function()', 'execute'));

-- ---------- a removed member loses access at once ----------
select pg_temp.check('owner removes the supervisor',
  pg_temp.run_as(pg_temp.u('owner_a'), format('update public.farm_members set deleted_at = now() where id = %L',
    pg_temp.fx_id('a', 'm_supervisor'))) = 'ok:1');
select pg_temp.check('removed supervisor cannot read the farm',
  pg_temp.try_as(pg_temp.u('supervisor_a'), format('select 1 from public.plots where id = %L', pg_temp.fx_id('a', 'plots'))) = 'ok:0');
select pg_temp.check('removed supervisor cannot write daily work',
  pg_temp.try_as(pg_temp.u('supervisor_a'), format('insert into public.notes (id, farm_id, noted_on, body) values (%L, %L, current_date, %L)',
    gen_random_uuid(), pg_temp.fx_id('farm', 'a'), 'x')) like 'err:%');
select pg_temp.check('removed supervisor cannot read history',
  pg_temp.try_as(pg_temp.u('supervisor_a'), format('select 1 from public.event_log where id = %L', pg_temp.fx_id('a', 'event_plots'))) = 'ok:0');
select pg_temp.check('removed supervisor still sees their own membership, so the phone learns',
  pg_temp.try_as(pg_temp.u('supervisor_a'), format('select 1 from public.farm_members where id = %L', pg_temp.fx_id('a', 'm_supervisor'))) = 'ok:1');

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
  raise exception 'TEST SUMMARY b1_roles: passed=% failed=% %', v_passed, v_failed,
    case when v_failed > 0 then chr(10) || v_failures else '' end;
end $$;

rollback;
