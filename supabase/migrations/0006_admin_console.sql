-- C12 admin console (minimal, screen 23): admins edit standard template items in Malayalam
-- and English and publish them as one template release.
--
-- Edits wait as drafts and reach no phone until an admin publishes. Publishing writes every
-- draft into template_items with the new release number, so phones pull the changes at their
-- next sync and show "new items available"; a farmer's own changes stay, as the override
-- rules already promise. Items are retired with is_active, never deleted.
--
-- The console signs in as an ordinary user. Being an admin is a row in app_admins, which
-- only the service role (the dashboard, or supabase/admin/add_admin.sql) can write. Every
-- console call is one of the security-definer functions below, which check that row first,
-- so the service-role key never leaves the server.

create table public.app_admins (
  user_id uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);
-- no policies: signed-in users can neither read nor write it
alter table public.app_admins enable row level security;

create table public.template_releases (
  version integer primary key,
  note text,
  items integer not null,
  published_at timestamptz not null default now(),
  published_by uuid references auth.users (id)
);
alter table public.template_releases enable row level security;

-- one pending change per item; a new item has no item_id yet
create table public.template_drafts (
  id uuid primary key default gen_random_uuid(),
  item_id uuid references public.template_items (id),
  crop_id uuid references public.crops (id),
  list_type text not null check (list_type in
    ('activity', 'input', 'expense_category', 'unit', 'grade', 'process_step', 'labour_task',
     'disease', 'sale_grade', 'rate_class', 'setting')),
  code text not null check (code ~ '^[a-z][a-z0-9_]{0,47}$'),
  name_ml text not null check (btrim(name_ml) <> ''),
  name_en text not null check (btrim(name_en) <> ''),
  data jsonb not null default '{}',
  sort_order integer not null default 0,
  is_active boolean not null default true,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id),
  unique nulls not distinct (crop_id, list_type, code)
);
alter table public.template_drafts enable row level security;

create function public.is_app_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.app_admins where user_id = (select auth.uid()))
$$;

create function public.require_app_admin() returns void
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_app_admin() then
    raise exception 'admins only' using errcode = 'insufficient_privilege';
  end if;
end $$;

-- The items of one list for one crop (null: every crop) as the console shows them: each
-- standard item with its draft, if any, laid over it, and new drafted items.
create function public.admin_items(p_list_type text, p_crop_id uuid)
returns table (item_id uuid, draft_id uuid, code text, name_ml text, name_en text,
  data jsonb, sort_order integer, is_active boolean, template_version integer)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.require_app_admin();
  return query
  select i.id, d.id, coalesce(d.code, i.code), coalesce(d.name_ml, i.name_ml),
    coalesce(d.name_en, i.name_en), coalesce(d.data, i.data), coalesce(d.sort_order, i.sort_order),
    coalesce(d.is_active, i.is_active), i.template_version
  from public.template_items i
  left join public.template_drafts d on d.item_id = i.id
  where i.list_type = p_list_type and i.crop_id is not distinct from p_crop_id
  union all
  select null, d.id, d.code, d.name_ml, d.name_en, d.data, d.sort_order, d.is_active, null
  from public.template_drafts d
  where d.item_id is null and d.list_type = p_list_type and d.crop_id is not distinct from p_crop_id
  order by 7, 3;
end $$;

-- Saves a change to an item, or a new item when p_item_id is null, as a draft.
create function public.admin_save_item(p_item_id uuid, p_crop_id uuid, p_list_type text,
  p_code text, p_name_ml text, p_name_en text, p_data jsonb, p_sort_order integer,
  p_is_active boolean) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_item public.template_items;
  v_id uuid;
begin
  perform public.require_app_admin();
  if p_item_id is not null then
    select * into v_item from public.template_items where id = p_item_id;
    if v_item.id is null then
      raise exception 'no such item' using errcode = 'no_data_found';
    end if;
  elsif exists (select 1 from public.template_items where list_type = p_list_type
      and crop_id is not distinct from p_crop_id and code = p_code) then
    raise exception 'an item with this code exists' using errcode = 'unique_violation';
  end if;
  insert into public.template_drafts as d (item_id, crop_id, list_type, code, name_ml, name_en,
    data, sort_order, is_active, updated_by)
  values (p_item_id, coalesce(v_item.crop_id, p_crop_id), coalesce(v_item.list_type, p_list_type),
    coalesce(v_item.code, p_code), btrim(p_name_ml), btrim(p_name_en),
    -- an admin saving an item has reviewed its wording
    coalesce(p_data, v_item.data, '{}') - 'ml_review', coalesce(p_sort_order, v_item.sort_order, 0),
    coalesce(p_is_active, true), auth.uid())
  on conflict (crop_id, list_type, code) do update
    set name_ml = excluded.name_ml, name_en = excluded.name_en, data = excluded.data,
        sort_order = excluded.sort_order, is_active = excluded.is_active,
        updated_at = now(), updated_by = excluded.updated_by
  returning d.id into v_id;
  return v_id;
end $$;

create function public.admin_discard_draft(p_draft_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.require_app_admin();
  delete from public.template_drafts where id = p_draft_id;
end $$;

-- The release phones have now, and how many drafts wait for the next.
create function public.admin_status() returns table (version integer, drafts integer)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.require_app_admin();
  return query select
    greatest((select max(r.version) from public.template_releases r),
             (select max(i.template_version) from public.template_items i), 0),
    (select count(*)::integer from public.template_drafts);
end $$;

-- Publishes every draft as the next template release and returns its number.
create function public.admin_publish(p_note text) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_version integer;
  v_count integer;
begin
  perform public.require_app_admin();
  -- one publish at a time
  perform pg_advisory_xact_lock(hashtextextended('template_release', 0));
  select count(*) into v_count from public.template_drafts;
  if v_count = 0 then
    raise exception 'nothing to publish' using errcode = 'no_data_found';
  end if;
  select greatest((select max(version) from public.template_releases),
                  (select max(template_version) from public.template_items), 0) + 1
    into v_version;
  update public.template_items i
  set name_ml = d.name_ml, name_en = d.name_en, data = d.data, sort_order = d.sort_order,
      is_active = d.is_active, template_version = v_version, updated_at = now()
  from public.template_drafts d
  where d.item_id = i.id;
  -- new items get the same kind of id the seed uses, so every environment agrees
  insert into public.template_items (id, crop_id, list_type, code, name_ml, name_en, data,
    sort_order, is_active, template_version)
  select md5('thottam:item:' || coalesce(c.code, '*') || ':' || d.list_type || ':' || d.code)::uuid,
    d.crop_id, d.list_type, d.code, d.name_ml, d.name_en, d.data, d.sort_order, d.is_active,
    v_version
  from public.template_drafts d
  left join public.crops c on c.id = d.crop_id
  where d.item_id is null;
  delete from public.template_drafts;
  insert into public.template_releases (version, note, items, published_by)
  values (v_version, nullif(btrim(p_note), ''), v_count, auth.uid());
  return v_version;
end $$;

-- The console's calls only; 0004 keeps every other new function closed.
grant execute on function public.is_app_admin(), public.admin_items(text, uuid),
  public.admin_save_item(uuid, uuid, text, text, text, text, jsonb, integer, boolean),
  public.admin_discard_draft(uuid), public.admin_status(), public.admin_publish(text)
  to authenticated;
