-- C12 admin console tests (screen 23). Run with tool/server_tests.py; nothing is kept.
--
-- Only an admin reaches the console's functions; drafts reach no phone until published;
-- publishing writes one release with a new number, bumps server_seq so phones pull it,
-- retires items with is_active, and gives new items the seed's kind of id.

begin;

create temp table results (n serial, name text, ok boolean, detail text);

create function pg_temp.check(p_name text, p_ok boolean, p_detail text default null) returns void
language sql as $$ insert into results (name, ok, detail) values (p_name, coalesce(p_ok, false), p_detail) $$;

create function pg_temp.u(p_name text) returns uuid
language sql immutable as $$ select md5('c12test:user:' || p_name)::uuid $$;

-- Runs p_sql as p_user and keeps the result: 'ok:<rows>' or 'err:<code> <message>'.
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
    execute 'reset role';
    v := 'err:' || sqlstate || ' ' || sqlerrm;
  end;
  perform set_config('request.jwt.claims', '', true);
  return v;
end $$;

-- ---------- fixtures ----------
insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at, raw_user_meta_data, created_at, updated_at)
select pg_temp.u(x), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
  x || '@example.com', now(), jsonb_build_object('full_name', x), now(), now()
from unnest(array['admin', 'farmer']) x;
insert into public.app_admins (user_id) values (pg_temp.u('admin'));

create temp table item_before as
select id, name_en, template_version, server_seq, is_active from public.template_items;
create temp table vars (k text primary key, v text);
insert into vars values
  ('pepper', (select id::text from public.crops where code = 'pepper' and owner_farm_id is null)),
  ('mulching', (select id::text from public.template_items where code = 'mulching' and list_type = 'activity')),
  ('release', (select greatest(coalesce(max(version), 0), (select max(template_version) from public.template_items))::text
    from public.template_releases));

-- ---------- only admins ----------
select pg_temp.check('a farmer cannot list items for the console',
  pg_temp.run_as(pg_temp.u('farmer'), 'select * from public.admin_items(''activity'', null)') like 'err:42501%');
select pg_temp.check('a farmer cannot save a draft',
  pg_temp.run_as(pg_temp.u('farmer'), format(
    'select public.admin_save_item(%L, null, null, null, %L, %L, null, null, true)',
    (select v from vars where k = 'mulching'), 'x', 'x')) like 'err:42501%');
select pg_temp.check('a farmer cannot publish',
  pg_temp.run_as(pg_temp.u('farmer'), 'select public.admin_publish(null)') like 'err:42501%');
select pg_temp.check('a farmer cannot read or add admins',
  pg_temp.run_as(pg_temp.u('farmer'), format('insert into public.app_admins values (%L)', pg_temp.u('farmer'))) like 'err:%'
  and pg_temp.run_as(pg_temp.u('farmer'), 'select * from public.app_admins') = 'ok:0');
select pg_temp.check('a farmer cannot read drafts directly',
  pg_temp.run_as(pg_temp.u('farmer'), 'select * from public.template_drafts') = 'ok:0');
select pg_temp.check('is_app_admin tells the console who may enter',
  pg_temp.run_as(pg_temp.u('admin'), 'select 1 where public.is_app_admin()') = 'ok:1'
  and pg_temp.run_as(pg_temp.u('farmer'), 'select 1 where public.is_app_admin()') = 'ok:0');

-- ---------- drafts ----------
select pg_temp.check('an admin lists a crop''s activities',
  pg_temp.run_as(pg_temp.u('admin'), format('select * from public.admin_items(%L, %L)',
    'activity', (select v from vars where k = 'pepper'))) ~ '^ok:[1-9]');
select pg_temp.check('an admin renames an item as a draft',
  pg_temp.run_as(pg_temp.u('admin'), format(
    'select public.admin_save_item(%L, null, null, null, %L, %L, null, null, true)',
    (select v from vars where k = 'mulching'), 'പുതയിടൽ (ഉണങ്ങിയ ഇല)', 'Mulching (dry leaves)')) = 'ok:1');
select pg_temp.check('an admin retires an item as a draft',
  pg_temp.run_as(pg_temp.u('admin'), format(
    'select public.admin_save_item(%L, null, null, null, %L, %L, null, null, false)',
    (select id from public.template_items where code = 'shade_regulation' and list_type = 'activity'),
    'തണൽ ക്രമീകരണം', 'Shade regulation')) = 'ok:1');
select pg_temp.check('an admin adds a new item for pepper',
  pg_temp.run_as(pg_temp.u('admin'), format(
    'select public.admin_save_item(null, %L, %L, %L, %L, %L, null, 500, true)',
    (select v from vars where k = 'pepper'), 'activity', 'vine_tying_check', 'വള്ളി പരിശോധന', 'Checking vines')) = 'ok:1');
select pg_temp.check('a new item cannot reuse a standard code',
  pg_temp.run_as(pg_temp.u('admin'), format(
    'select public.admin_save_item(null, %L, %L, %L, %L, %L, null, 0, true)',
    (select v from vars where k = 'pepper'), 'activity', 'mulching', 'x', 'x')) like 'err:23505%');
select pg_temp.check('a draft needs both names',
  pg_temp.run_as(pg_temp.u('admin'), format(
    'select public.admin_save_item(null, %L, %L, %L, %L, %L, null, 0, true)',
    (select v from vars where k = 'pepper'), 'activity', 'blank_name', ' ', 'Blank')) like 'err:23514%');
select pg_temp.check('drafts change nothing phones can see',
  not exists (select 1 from public.template_items i join item_before b using (id)
    where i.name_en <> b.name_en or i.server_seq <> b.server_seq or i.is_active <> b.is_active)
  and (select count(*) from public.template_items) = (select count(*) from item_before));
select pg_temp.check('the console shows the draft over the item',
  pg_temp.run_as(pg_temp.u('admin'), format(
    'select 1 from public.admin_items(%L, %L) where code = %L and name_en = %L and draft_id is not null',
    'activity', (select v from vars where k = 'pepper'), 'mulching', 'Mulching (dry leaves)')) = 'ok:1');
select pg_temp.check('the status counts three drafts',
  pg_temp.run_as(pg_temp.u('admin'), 'select 1 from public.admin_status() where drafts = 3') = 'ok:1');

-- ---------- publish ----------
select pg_temp.check('an admin publishes',
  pg_temp.run_as(pg_temp.u('admin'), 'select public.admin_publish(''Pepper review'')') = 'ok:1');
select pg_temp.check('the release has the next number and counts its items',
  exists (select 1 from public.template_releases
    where version = (select v::integer + 1 from vars where k = 'release') and items = 3
      and note = 'Pepper review' and published_by = pg_temp.u('admin')));
select pg_temp.check('the renamed item carries the new release, a new server_seq, and no review flag',
  exists (select 1 from public.template_items i join item_before b using (id)
    where i.id = (select v::uuid from vars where k = 'mulching')
      and i.name_en = 'Mulching (dry leaves)'
      and i.template_version = (select v::integer + 1 from vars where k = 'release')
      and i.server_seq > b.server_seq and not (i.data ? 'ml_review')));
select pg_temp.check('the retired item is switched off, not deleted',
  exists (select 1 from public.template_items where code = 'shade_regulation'
    and list_type = 'activity' and not is_active));
select pg_temp.check('the new item has the seed''s kind of id',
  exists (select 1 from public.template_items
    where id = md5('thottam:item:pepper:activity:vine_tying_check')::uuid
      and template_version = (select v::integer + 1 from vars where k = 'release')));
select pg_temp.check('untouched items are as they were',
  not exists (select 1 from public.template_items i join item_before b using (id)
    where i.code not in ('mulching', 'shade_regulation')
      and (i.server_seq <> b.server_seq or i.template_version <> b.template_version)));
select pg_temp.check('drafts are gone after publishing',
  not exists (select 1 from public.template_drafts));
select pg_temp.check('a farmer sees the published item',
  pg_temp.run_as(pg_temp.u('farmer'), format(
    'select 1 from public.template_items where id = %L', md5('thottam:item:pepper:activity:vine_tying_check')::uuid)) = 'ok:1');
select pg_temp.check('nothing to publish is refused',
  pg_temp.run_as(pg_temp.u('admin'), 'select public.admin_publish(null)') like 'err:P0002%');

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
  raise exception 'TEST SUMMARY c12_admin: passed=% failed=% %', v_passed, v_failed,
    case when v_failed > 0 then chr(10) || v_failures else '' end;
end $$;

rollback;
