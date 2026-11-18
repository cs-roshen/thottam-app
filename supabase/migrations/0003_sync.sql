-- Sync (task B7): one server function per upload batch (implementation plan section 13).
-- Pulls need no function: the phone reads "rows with server_seq above my cursor" per farm and
-- table through the API, and row-level security decides what it sees.

-- Answers to batches already applied, so a batch sent twice changes nothing.
create table public.sync_batches (
  id uuid primary key,
  user_id uuid not null,
  farm_id uuid not null,
  result jsonb not null,
  created_at timestamptz not null default now()
);
alter table public.sync_batches enable row level security;
create policy sync_batches_select on public.sync_batches for select to authenticated
  using (user_id = (select auth.uid()));
create policy sync_batches_insert on public.sync_batches for insert to authenticated
  with check (user_id = (select auth.uid()));

-- On a same-field conflict these go to the farmer instead of "later upload wins": money,
-- quantities and the units they are counted in (120 kg must not become 120 quintal).
create function public.is_money_or_quantity(p_column text) returns boolean
language sql immutable set search_path = '' as $$
  select p_column like '%\_paise' or p_column = any (array[
    'quantity', 'piece_quantity', 'head_count', 'attendance', 'hours', 'overtime_hours',
    'area', 'area_share', 'deductions', 'unit', 'piece_unit', 'area_unit'])
$$;

-- Whether a farm id is taken, whoever owns it (row-level security would hide it).
create function public.farm_exists(p_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.farms where id = p_id)
$$;

-- The columns of p_row that p_table has, in table order, without server_seq. An app that
-- is a version behind the server sends fewer columns; the rest keep their values.
create function public.sync_columns(p_table text, p_row jsonb) returns text[]
language sql stable set search_path = '' as $$
  select coalesce(array_agg(a.attname::text order by a.attnum), '{}')
  from pg_catalog.pg_attribute a
  where a.attrelid = format('public.%I', p_table)::regclass and a.attnum > 0
    and not a.attisdropped and a.attname <> 'server_seq' and p_row ? a.attname
$$;

-- Inserts the columns p_row carries, under the caller's row-level security; the others
-- take their defaults.
create function public.sync_insert(p_table text, p_row jsonb) returns void
language plpgsql set search_path = '' as $$
declare
  v_cols text := (select string_agg(format('%I', c), ', ') from unnest(public.sync_columns(p_table, p_row)) c);
begin
  execute format('insert into public.%I (%s) select %s from jsonb_populate_record(null::public.%I, $1)',
    p_table, v_cols, v_cols, p_table) using p_row;
end $$;

-- Writes the columns p_row carries to an existing row, under the caller's row-level security.
create function public.sync_write(p_table text, p_id uuid, p_row jsonb) returns void
language plpgsql set search_path = '' as $$
declare
  v_set text := (select string_agg(format('%I = r.%I', c, c), ', ')
                 from unnest(public.sync_columns(p_table, p_row)) c where c <> 'id');
  v_n integer;
begin
  if v_set is null then
    return;
  end if;
  execute format('update public.%I t set %s from jsonb_populate_record(null::public.%I, $1) r where t.id = $2',
    p_table, v_set, p_table) using p_row, p_id;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    raise exception 'not allowed to change this row' using errcode = 'insufficient_privilege';
  end if;
end $$;

-- Applies one farm's batch from one phone in one transaction, under the caller's row-level
-- security. Each row is accepted, rejected (permission or validation; it never blocks the
-- rows after it) or returned as a conflict for the farmer to settle:
--   * base version = server version: the upload is taken as is.
--   * otherwise, field by field against the base values the phone sends (a row new on the
--     phone that exists already, such as a lot's cost every money phone works out, has no
--     base: every field it sets is its change). A field the phone did not really change
--     (changed and changed back) is left alone; a field only this phone changed is taken;
--     the same value on both is fine; a money, quantity or unit field both changed is a
--     conflict; any other field both changed is taken (the later upload wins).
--   * a delete against an edit, a new row under a parent deleted elsewhere, and sales that
--     take more from a lot than it holds are conflicts.
-- A merge is the one write where the server sets version: highest seen plus one.
-- p_user is the person whose queue this is; a session that changed under the phone fails
-- the batch instead of filing their rows under someone else's name.
create function public.sync_push(p_batch_id uuid, p_farm_id uuid, p_rows jsonb, p_user uuid) returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_result jsonb;
  v_accepted jsonb := '[]';
  v_rejected jsonb := '[]';
  v_conflicts jsonb := '[]';
  v_item jsonb;
  v_raw jsonb;
  v_entity text;
  v_farm_column text;
  v_id uuid;
  v_ref jsonb;
  v_base integer;
  v_changes jsonb;
  v_base_row jsonb;
  v_up jsonb;
  v_server jsonb;
  v_merged jsonb;
  v_took boolean;
  v_clash text[];
  v_field text;
  v_orphan text[];
  v_parent record;
  v_parent_deleted boolean;
  v_member jsonb;
  v_i_delete boolean;
  v_they_deleted boolean;
  v_lots uuid[] := '{}';
  v_lot uuid;
begin
  if v_uid is null then
    raise exception 'sign in first' using errcode = 'insufficient_privilege';
  end if;
  if p_user is distinct from v_uid then
    raise exception 'signed in as someone else' using errcode = 'invalid_authorization_specification';
  end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 500 then
    raise exception 'a batch is a list of at most 500 rows' using errcode = 'program_limit_exceeded';
  end if;
  -- Only a member, or the creator of a new farm, may take the farm's lock.
  if public.farm_exists(p_farm_id) and not exists (select 1 from public.my_farms('setup', 0) f where f = p_farm_id) then
    raise exception 'not a member of this farm' using errcode = 'insufficient_privilege';
  end if;
  select result into v_result from public.sync_batches where id = p_batch_id and user_id = v_uid;
  if found then
    return v_result;
  end if;
  -- The same lock every row write of this farm takes, held from the first read, so no other
  -- batch changes these rows between reading and merging.
  perform pg_advisory_xact_lock(hashtextextended(p_farm_id::text, 0));
  -- a retry of a batch still running when it was sent waits here, then gets its answer
  select result into v_result from public.sync_batches where id = p_batch_id and user_id = v_uid;
  if found then
    return v_result;
  end if;
  -- A missing parent fails its own row, not the whole batch at commit.
  set constraints all immediate;

  for v_item in select * from jsonb_array_elements(p_rows) loop
    v_entity := v_item ->> 'entity';
    v_raw := v_item -> 'row';
    v_id := (v_raw ->> 'id')::uuid;
    v_ref := jsonb_build_object('entity', v_entity, 'id', v_id);
    v_base := coalesce((v_item ->> 'base_version')::integer, 0);
    v_changes := coalesce(v_item -> 'changes', '{}');
    begin
      select farm_column into v_farm_column from public.sync_tables
        where name = v_entity and name <> 'template_items';
      if not found then
        raise exception 'not a synced table' using errcode = 'invalid_parameter_value';
      end if;
      if (v_raw ->> v_farm_column) is distinct from p_farm_id::text then
        raise exception 'row of another farm' using errcode = 'invalid_parameter_value';
      end if;
      execute format('select to_jsonb(jsonb_populate_record(null::public.%I, $1))', v_entity)
        into v_up using v_raw;
      execute format('select to_jsonb(t) from public.%I t where id = $1', v_entity)
        into v_server using v_id;
      if v_entity = 'sale_lots' then
        v_lots := v_lots || (v_up ->> 'lot_id')::uuid;
      end if;

      if v_server is null then
        if v_entity = 'farms' then
          select r -> 'row' into v_member from jsonb_array_elements(p_rows) r
            where r ->> 'entity' = 'farm_members' and r -> 'row' ->> 'farm_id' = v_id::text
              and r -> 'row' ->> 'user_id' = v_uid::text
            limit 1;
          perform public.create_farm(v_id, coalesce((v_member ->> 'id')::uuid, gen_random_uuid()),
            v_up ->> 'name', v_up ->> 'district', coalesce(v_up -> 'settings', '{}'),
            coalesce((v_up ->> 'created_at')::timestamptz, now()));
          -- the fields create_farm does not take (template version, version)
          perform public.sync_write('farms', v_id, v_raw);
        else
          perform public.sync_insert(v_entity, v_raw);
        end if;
        v_orphan := '{}';
        -- references are (column, farm_id); the first column names the parent row
        for v_parent in
          select a.attname::text as col, c.confrelid::regclass::text as parent
          from pg_catalog.pg_constraint c
          join pg_catalog.pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
          where c.contype = 'f'
            and c.conrelid = format('public.%I', v_entity)::regclass
            -- template_items has no deleted_at: master data is switched off, never deleted
            and c.confrelid::regclass::text in
              (select 'public.' || name from public.sync_tables where name <> 'template_items')
        loop
          continue when v_up ->> v_parent.col is null;
          execute format('select deleted_at is not null from %s where id = $1', v_parent.parent)
            into v_parent_deleted using (v_up ->> v_parent.col)::uuid;
          if v_parent_deleted then
            v_orphan := v_orphan || v_parent.col;
          end if;
        end loop;
        if cardinality(v_orphan) > 0 then
          v_conflicts := v_conflicts || (v_ref || jsonb_build_object('kind', 'orphan',
            'fields', to_jsonb(v_orphan), 'theirs', v_up));
        else
          v_accepted := v_accepted || v_ref;
        end if;

      elsif v_entity = 'event_log' then
        -- insert-only: the same id is the same event, resent
        v_accepted := v_accepted || v_ref;

      elsif v_base > 0 and (v_server ->> 'version')::integer = v_base then
        perform public.sync_write(v_entity, v_id, v_raw);
        v_accepted := v_accepted || v_ref;

      else
        if v_base = 0 then
          -- new on the phone but here already: every field it sets is its change, from nothing
          select coalesce(jsonb_object_agg(k, null), '{}') into v_changes
          from jsonb_object_keys(v_raw) k
          where k not in ('id', 'created_at', 'created_by', 'updated_at', 'updated_by', 'version',
                          'deleted_at', 'server_seq') and k <> v_farm_column;
        end if;
        v_i_delete := v_changes ? 'deleted_at' and v_up ->> 'deleted_at' is not null
          and (v_changes ->> 'deleted_at') is null;
        v_they_deleted := v_server ->> 'deleted_at' is not null;
        if v_i_delete <> v_they_deleted
           and (v_i_delete or (v_changes - 'deleted_at') <> '{}') then
          v_conflicts := v_conflicts || (v_ref || jsonb_build_object('kind', 'delete_edit',
            'fields', '["deleted_at"]'::jsonb, 'theirs', v_server));
        elsif v_i_delete then
          v_accepted := v_accepted || v_ref;
        else
          execute format('select to_jsonb(jsonb_populate_record(null::public.%I, $1))', v_entity)
            into v_base_row using v_changes;
          v_merged := v_server;
          v_took := false;
          v_clash := '{}';
          for v_field in select jsonb_object_keys(v_changes) loop
            continue when not v_up ? v_field
              or v_field in ('id', 'created_at', 'created_by', 'updated_at', 'updated_by',
                             'version', 'server_seq')
              or v_field = v_farm_column;
            -- changed and changed back on the phone: not a change at all
            continue when (v_up -> v_field) is not distinct from (v_base_row -> v_field)
              and v_base > 0;
            if (v_server -> v_field) is not distinct from (v_up -> v_field) then
              null; -- the same value on both phones is not a conflict
            elsif (v_server -> v_field) is not distinct from (v_base_row -> v_field) then
              v_merged := jsonb_set(v_merged, array[v_field], v_up -> v_field);
              v_took := true;
            elsif public.is_money_or_quantity(v_field) then
              v_clash := v_clash || v_field;
            else
              v_merged := jsonb_set(v_merged, array[v_field], v_up -> v_field);
              v_took := true;
            end if;
          end loop;
          if v_took then
            v_merged := v_merged || jsonb_build_object(
              'version', greatest((v_server ->> 'version')::integer, (v_up ->> 'version')::integer) + 1,
              'updated_at', v_up -> 'updated_at');
            perform public.sync_write(v_entity, v_id, v_merged);
          end if;
          if cardinality(v_clash) = 0 then
            v_accepted := v_accepted || v_ref;
          else
            execute format('select to_jsonb(t) from public.%I t where id = $1', v_entity)
              into v_server using v_id;
            v_conflicts := v_conflicts || (v_ref || jsonb_build_object('kind', 'same_field',
              'fields', to_jsonb(v_clash), 'theirs', v_server));
          end if;
        end if;
      end if;
    exception when others then
      -- A lost race or an overloaded server is worth retrying: fail the whole batch.
      if sqlstate like '40%' or sqlstate like '53%' or sqlstate like '57%' then
        raise;
      end if;
      v_rejected := v_rejected || (v_ref || jsonb_build_object('code', sqlstate, 'message', sqlerrm));
    end;
  end loop;

  -- Two phones selling from one lot while offline can sell more than it holds.
  for v_lot in select distinct unnest(v_lots) loop
    if (select coalesce(sum(quantity), 0) from public.sale_lots where lot_id = v_lot and deleted_at is null)
       > (select quantity from public.lots where id = v_lot) then
      for v_item in select * from jsonb_array_elements(p_rows) r
        where r ->> 'entity' = 'sale_lots' and r -> 'row' ->> 'lot_id' = v_lot::text
      loop
        v_ref := jsonb_build_object('entity', 'sale_lots', 'id', v_item -> 'row' ->> 'id');
        if v_accepted @> jsonb_build_array(v_ref) then
          v_accepted := (select coalesce(jsonb_agg(x), '[]') from jsonb_array_elements(v_accepted) x where x <> v_ref);
          v_conflicts := v_conflicts || (v_ref || jsonb_build_object('kind', 'oversell',
            'fields', '["quantity"]'::jsonb, 'theirs', v_item -> 'row'));
        end if;
      end loop;
    end if;
  end loop;

  v_result := jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected, 'conflicts', v_conflicts);
  insert into public.sync_batches (id, user_id, farm_id, result) values (p_batch_id, v_uid, p_farm_id, v_result);
  return v_result;
end $$;

-- ---------- the server's own record of changed rows ----------
-- The app writes history itself, so a member calling the API directly could change a row
-- and leave none. Every change to a synced row keeps the row as it was here, whoever made
-- it and however. Owners can read it; nothing but this trigger writes it.
create table public.sync_row_versions (
  id bigint generated always as identity primary key,
  farm_id uuid,
  entity text not null,
  row_id uuid not null,
  old_row jsonb not null,
  changed_by uuid,
  changed_at timestamptz not null default now()
);
create index sync_row_versions_row on public.sync_row_versions (entity, row_id, changed_at);
create index sync_row_versions_farm on public.sync_row_versions (farm_id, changed_at);
alter table public.sync_row_versions enable row level security;
create policy sync_row_versions_select on public.sync_row_versions for select to authenticated
  using (farm_id in (select public.my_owned_farms()));

create function public.keep_row_version() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.sync_row_versions (farm_id, entity, row_id, old_row, changed_by)
  values ((to_jsonb(old) ->> tg_argv[0])::uuid, tg_table_name, old.id, to_jsonb(old), auth.uid());
  return null;
end $$;

do $$
declare r record;
begin
  for r in select name, farm_column from public.sync_tables where name not in ('template_items', 'event_log')
  loop
    execute format('create trigger %1$I_keep_version after update on public.%1$I '
      'for each row execute function public.keep_row_version(%2$L)', r.name, r.farm_column);
  end loop;
end $$;

-- ---------- privileges (as in 0001, for the objects added here) ----------
revoke all on public.sync_row_versions from anon;
revoke insert, update, delete, truncate, references, trigger on public.sync_row_versions from authenticated;
revoke all on public.sync_batches from anon;
revoke truncate, delete, update, references, trigger on public.sync_batches from authenticated;
revoke execute on function public.sync_push(uuid, uuid, jsonb, uuid), public.sync_write(text, uuid, jsonb),
  public.sync_insert(text, jsonb), public.sync_columns(text, jsonb), public.farm_exists(uuid),
  public.is_money_or_quantity(text) from public, anon;
grant execute on function public.sync_push(uuid, uuid, jsonb, uuid) to authenticated;
-- These run inside sync_push as the caller; called directly they allow no more than the API.
grant execute on function public.sync_write(text, uuid, jsonb), public.sync_insert(text, jsonb),
  public.sync_columns(text, jsonb), public.farm_exists(uuid), public.is_money_or_quantity(text)
  to authenticated;
