-- B7 server tests for sync_push (the same cases as test/core/sync/sync_test.dart, on Postgres).
-- Run with tool/server_tests.py.
-- One transaction that always ends in an error, so nothing is kept.

begin;

create temp table results (n serial, name text, ok boolean, detail text);

create function pg_temp.check(p_name text, p_ok boolean, p_detail text default null) returns void
language sql as $$ insert into results (name, ok, detail) values (p_name, coalesce(p_ok, false), p_detail) $$;

create function pg_temp.u(p_name text) returns uuid
language sql immutable as $$ select md5('b7test:user:' || p_name)::uuid $$;

create function pg_temp.id(p_name text) returns uuid
language sql immutable as $$ select md5('b7test:' || p_name)::uuid $$;

-- Calls sync_push as p_user and keeps the result.
create function pg_temp.push(p_user uuid, p_batch text, p_farm uuid, p_rows jsonb) returns jsonb
language plpgsql as $$
declare
  v jsonb;
  v_batch uuid := pg_temp.id(p_batch); -- before the role switch: pg_temp is not the caller's
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select public.sync_push(v_batch, p_farm, p_rows) into v;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return v;
end $$;

-- A row as the phone sends it: the common columns plus [cols].
create function pg_temp.r(p_entity text, p_id uuid, p_farm uuid, p_cols jsonb, p_version integer default 1,
  p_base integer default 0, p_changes jsonb default '{}') returns jsonb
language sql as $$
  select jsonb_build_object('entity', p_entity, 'base_version', p_base, 'changes', p_changes,
    'row', jsonb_build_object('id', p_id, 'farm_id', p_farm, 'created_at', '2026-11-18T08:00:00Z',
      'updated_at', '2026-11-18T08:00:00Z', 'version', p_version, 'deleted_at', null) || p_cols)
$$;

create function pg_temp.has(p_result jsonb, p_list text, p_id uuid) returns boolean
language sql as $$ select exists (select 1 from jsonb_array_elements(p_result -> p_list) x where x ->> 'id' = p_id::text) $$;

insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at, created_at, updated_at)
select pg_temp.u(x), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
  x || '@example.com', now(), now(), now()
from unnest(array['owner', 'manager', 'supervisor', 'other']) x;

-- ---------- a farm set up offline arrives in one batch ----------
create temp table res as select pg_temp.push(pg_temp.u('owner'), 'b1', pg_temp.id('farm'), jsonb_build_array(
  jsonb_build_object('entity', 'farms', 'base_version', 0, 'changes', '{}', 'row', jsonb_build_object(
    'id', pg_temp.id('farm'), 'name', 'Thottam', 'settings', '{}', 'accepted_template_version', 0,
    'created_at', '2026-11-18T08:00:00Z', 'updated_at', '2026-11-18T08:00:00Z', 'version', 1)),
  pg_temp.r('farm_members', pg_temp.id('m-owner'), pg_temp.id('farm'),
    jsonb_build_object('user_id', pg_temp.u('owner'), 'role', 'owner', 'permissions', '{}')),
  pg_temp.r('plots', pg_temp.id('p1'), pg_temp.id('farm'), '{"name": "Plot 1", "area_unit": "cent", "tenure": "owned", "details": {}}'),
  pg_temp.r('crop_cycles', pg_temp.id('c1'), pg_temp.id('farm'), jsonb_build_object('plot_id', pg_temp.id('p1'),
    'crop_id', md5('thottam:crop:pepper')::uuid, 'status', 'active')),
  pg_temp.r('expenses', pg_temp.id('e1'), pg_temp.id('farm'), jsonb_build_object('spent_on', '2026-11-17',
    'category_code', 'fertiliser', 'amount_paise', 360000, 'mode', 'cash', 'plot_id', pg_temp.id('p1'))),
  pg_temp.r('lots', pg_temp.id('lot1'), pg_temp.id('farm'), jsonb_build_object('crop_cycle_id', pg_temp.id('c1'),
    'quantity', 50000, 'unit', 'kg')),
  jsonb_build_object('entity', 'event_log', 'base_version', 0, 'changes', '{}', 'row', jsonb_build_object(
    'id', pg_temp.id('ev1'), 'farm_id', pg_temp.id('farm'), 'entity', 'expenses', 'entity_id', pg_temp.id('e1'),
    'action', 'create', 'summary', '{}', 'occurred_on', '2026-11-17', 'created_at', '2026-11-18T08:00:00Z'))
)) as v;
select pg_temp.check('farm set up offline: every row accepted',
  jsonb_array_length((select v from res) -> 'accepted') = 7 and jsonb_array_length((select v from res) -> 'rejected') = 0,
  (select v::text from res));
select pg_temp.check('the owner membership keeps the phone''s id',
  exists (select 1 from public.farm_members where id = pg_temp.id('m-owner') and role = 'owner'));
create temp table seq_before as select server_seq from public.expenses where id = pg_temp.id('e1');
select pg_temp.check('the same batch again returns the same answer and writes nothing',
  pg_temp.push(pg_temp.u('owner'), 'b1', pg_temp.id('farm'), '[]') = (select v from res)
  and (select server_seq from public.expenses where id = pg_temp.id('e1')) = (select server_seq from seq_before));

insert into public.farm_members (id, farm_id, user_id, role)
values (pg_temp.id('m-manager'), pg_temp.id('farm'), pg_temp.u('manager'), 'manager'),
       (pg_temp.id('m-supervisor'), pg_temp.id('farm'), pg_temp.u('supervisor'), 'supervisor');

-- ---------- the same row edited on two phones ----------
-- owner changes notes (base 1 → 2); manager, still at base 1, changes the category
select pg_temp.push(pg_temp.u('owner'), 'b2', pg_temp.id('farm'), jsonb_build_array(
  pg_temp.r('expenses', pg_temp.id('e1'), pg_temp.id('farm'), jsonb_build_object('spent_on', '2026-11-17',
    'category_code', 'fertiliser', 'amount_paise', 360000, 'mode', 'cash', 'plot_id', pg_temp.id('p1'), 'notes', 'neem'),
    2, 1, '{"notes": null}')));
select pg_temp.check('an upload at the server''s version is taken as is',
  (select notes = 'neem' and version = 2 from public.expenses where id = pg_temp.id('e1')));
create temp table res2 as select pg_temp.push(pg_temp.u('manager'), 'b3', pg_temp.id('farm'), jsonb_build_array(
  pg_temp.r('expenses', pg_temp.id('e1'), pg_temp.id('farm'), jsonb_build_object('spent_on', '2026-11-17',
    'category_code', 'seeds', 'amount_paise', 360000, 'mode', 'cash', 'plot_id', pg_temp.id('p1'), 'notes', null),
    2, 1, '{"category_code": "fertiliser"}'))) as v;
select pg_temp.check('different fields merge',
  (select notes = 'neem' and category_code = 'seeds' from public.expenses where id = pg_temp.id('e1'))
  and pg_temp.has((select v from res2), 'accepted', pg_temp.id('e1')), (select v::text from res2));
select pg_temp.check('a merge is stored at the highest version plus one',
  (select version = 3 from public.expenses where id = pg_temp.id('e1')));
select pg_temp.check('the merge is stamped with who made it',
  (select updated_by = pg_temp.u('manager') from public.expenses where id = pg_temp.id('e1')));

-- a field only this phone changed is taken
select pg_temp.push(pg_temp.u('owner'), 'b4', pg_temp.id('farm'), jsonb_build_array(
  pg_temp.r('expenses', pg_temp.id('e1'), pg_temp.id('farm'), jsonb_build_object('spent_on', '2026-11-17',
    'category_code', 'seeds', 'amount_paise', 360000, 'mode', 'cash', 'plot_id', pg_temp.id('p1'), 'notes', 'later'),
    3, 2, '{"notes": "neem"}')));
select pg_temp.check('a field only this phone changed is taken',
  (select notes = 'later' from public.expenses where id = pg_temp.id('e1')));

-- the same money field: the farmer chooses
select pg_temp.push(pg_temp.u('owner'), 'b5', pg_temp.id('farm'), jsonb_build_array(
  pg_temp.r('expenses', pg_temp.id('e1'), pg_temp.id('farm'), jsonb_build_object('spent_on', '2026-11-17',
    'category_code', 'seeds', 'amount_paise', 370000, 'mode', 'cash', 'plot_id', pg_temp.id('p1'), 'notes', 'later'),
    5, (select version from public.expenses where id = pg_temp.id('e1')), '{"amount_paise": 360000}')));
create temp table res3 as select pg_temp.push(pg_temp.u('manager'), 'b6', pg_temp.id('farm'), jsonb_build_array(
  pg_temp.r('expenses', pg_temp.id('e1'), pg_temp.id('farm'), jsonb_build_object('spent_on', '2026-11-17',
    'category_code', 'seeds', 'amount_paise', 380000, 'mode', 'cash', 'plot_id', pg_temp.id('p1'), 'notes', 'later'),
    4, 3, '{"amount_paise": 360000}'))) as v;
select pg_temp.check('the same money field is a conflict and the server keeps its amount',
  pg_temp.has((select v from res3), 'conflicts', pg_temp.id('e1'))
  and ((select v from res3) -> 'conflicts' -> 0 ->> 'kind') = 'same_field'
  and ((select v from res3) -> 'conflicts' -> 0 -> 'theirs' ->> 'amount_paise')::bigint = 370000
  and (select amount_paise = 370000 from public.expenses where id = pg_temp.id('e1')), (select v::text from res3));
select pg_temp.check('the same value on both is not a conflict',
  not pg_temp.has(pg_temp.push(pg_temp.u('manager'), 'b7', pg_temp.id('farm'), jsonb_build_array(
    pg_temp.r('expenses', pg_temp.id('e1'), pg_temp.id('farm'), jsonb_build_object('spent_on', '2026-11-17',
      'category_code', 'seeds', 'amount_paise', 370000, 'mode', 'cash', 'plot_id', pg_temp.id('p1'), 'notes', 'later'),
      4, 3, '{"amount_paise": 360000}'))), 'conflicts', pg_temp.id('e1')));

-- ---------- delete against edit ----------
select pg_temp.push(pg_temp.u('owner'), 'b8', pg_temp.id('farm'), jsonb_build_array(
  pg_temp.r('plots', pg_temp.id('p1'), pg_temp.id('farm'), '{"name": "Plot 1", "area_unit": "cent", "tenure": "owned", "details": {}}'
    ::jsonb || jsonb_build_object('deleted_at', '2026-11-18T09:00:00Z'), 2, 1, '{"deleted_at": null}')));
create temp table res4 as select pg_temp.push(pg_temp.u('manager'), 'b9', pg_temp.id('farm'), jsonb_build_array(
  pg_temp.r('plots', pg_temp.id('p1'), pg_temp.id('farm'), '{"name": "Renamed", "area_unit": "cent", "tenure": "owned", "details": {}}',
    2, 1, '{"name": "Plot 1"}'))) as v;
select pg_temp.check('an edit against a delete goes to the farmer',
  ((select v from res4) -> 'conflicts' -> 0 ->> 'kind') = 'delete_edit'
  and (select name = 'Plot 1' and deleted_at is not null from public.plots where id = pg_temp.id('p1')), (select v::text from res4));

-- ---------- a new row under a parent deleted elsewhere ----------
create temp table res5 as select pg_temp.push(pg_temp.u('manager'), 'b10', pg_temp.id('farm'), jsonb_build_array(
  pg_temp.r('notes', pg_temp.id('n1'), pg_temp.id('farm'), jsonb_build_object('noted_on', '2026-11-18', 'body', 'x',
    'plot_id', pg_temp.id('p1'))))) as v;
select pg_temp.check('a new row under a deleted parent is kept and goes to the farmer',
  ((select v from res5) -> 'conflicts' -> 0 ->> 'kind') = 'orphan'
  and exists (select 1 from public.notes where id = pg_temp.id('n1')), (select v::text from res5));

-- ---------- selling more than a lot holds ----------
create function pg_temp.sale(p_n text) returns jsonb language sql as $$
  select jsonb_build_array(
    pg_temp.r('sales', pg_temp.id('s' || p_n), pg_temp.id('farm'), '{"sold_on": "2026-11-18", "sale_type": "trader",
      "quantity": 30000, "unit": "kg", "rate_paise": 70500, "deductions": [], "net_paise": 2115000, "mode": "cash"}'),
    pg_temp.r('sale_lots', pg_temp.id('sl' || p_n), pg_temp.id('farm'), jsonb_build_object('sale_id', pg_temp.id('s' || p_n),
      'lot_id', pg_temp.id('lot1'), 'quantity', 30000)))
$$;
select pg_temp.check('the first sale from the lot is accepted',
  pg_temp.has(pg_temp.push(pg_temp.u('owner'), 'b11', pg_temp.id('farm'), pg_temp.sale('a')), 'accepted', pg_temp.id('sla')));
create temp table res6 as select pg_temp.push(pg_temp.u('manager'), 'b12', pg_temp.id('farm'), pg_temp.sale('b')) as v;
select pg_temp.check('the second phone''s sale beyond the stock goes to the farmer',
  pg_temp.has((select v from res6), 'conflicts', pg_temp.id('slb'))
  and ((select v from res6) -> 'conflicts' -> 0 ->> 'kind') = 'oversell', (select v::text from res6));

-- ---------- refusals never block later rows ----------
create temp table res7 as select pg_temp.push(pg_temp.u('supervisor'), 'b13', pg_temp.id('farm'), jsonb_build_array(
  pg_temp.r('expenses', pg_temp.id('e2'), pg_temp.id('farm'), '{"spent_on": "2026-11-18", "category_code": "seeds",
    "amount_paise": 100, "mode": "cash"}'),
  pg_temp.r('notes', pg_temp.id('n2'), pg_temp.id('farm'), '{"noted_on": "2026-11-18", "body": "ok"}'),
  pg_temp.r('notes', pg_temp.id('n3'), pg_temp.id('other farm'), '{"noted_on": "2026-11-18", "body": "elsewhere"}'),
  pg_temp.r('template_items', pg_temp.id('t1'), pg_temp.id('farm'), '{}')
)) as v;
select pg_temp.check('a supervisor''s expense is refused, their note is taken',
  pg_temp.has((select v from res7), 'rejected', pg_temp.id('e2'))
  and pg_temp.has((select v from res7), 'accepted', pg_temp.id('n2'))
  and not exists (select 1 from public.expenses where id = pg_temp.id('e2')), (select v::text from res7));
select pg_temp.check('a row of another farm in the batch is refused',
  pg_temp.has((select v from res7), 'rejected', pg_temp.id('n3')));
select pg_temp.check('templates cannot be uploaded',
  pg_temp.has((select v from res7), 'rejected', pg_temp.id('t1')));
select pg_temp.check('someone outside the farm cannot push to it',
  (select count(*) = 1 from jsonb_array_elements(pg_temp.push(pg_temp.u('other'), 'b14', pg_temp.id('farm'),
    jsonb_build_array(pg_temp.r('notes', pg_temp.id('n4'), pg_temp.id('farm'), '{"noted_on": "2026-11-18", "body": "x"}')))
    -> 'rejected')));
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
  raise exception 'TEST SUMMARY b7_sync: passed=% failed=% %', v_passed, v_failed,
    case when v_failed > 0 then chr(10) || v_failures else '' end;
end $$;

rollback;
