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

-- On a same-field conflict these go to the farmer instead of "later upload wins".
create function public.is_money_or_quantity(p_column text) returns boolean
language sql immutable set search_path = '' as $$
  select p_column like '%\_paise' or p_column = any (array[
    'quantity', 'piece_quantity', 'head_count', 'attendance', 'hours', 'overtime_hours',
    'area', 'area_share', 'deductions'])
$$;

-- Writes every column of p_row (in the table's types) to an existing row, under the
-- caller's row-level security.
create function public.sync_write(p_table text, p_id uuid, p_row jsonb) returns void
language plpgsql set search_path = '' as $$
declare
  v_set text;
  v_n integer;
begin
  select string_agg(format('%I = r.%I', column_name, column_name), ', ')
    into v_set
    from information_schema.columns
    where table_schema = 'public' and table_name = p_table and column_name not in ('id', 'server_seq');
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
--   * otherwise, field by field against the base values the phone sends: a field only this
--     phone changed is taken; the same value on both is fine; a money or quantity field both
--     changed is a conflict; any other field both changed is taken (later upload wins).
--   * a delete against an edit, a new row under a parent deleted elsewhere, and sales that
--     take more from a lot than it holds are conflicts.
-- A merge is the one write where the server sets version: highest seen plus one.
create function public.sync_push(p_batch_id uuid, p_farm_id uuid, p_rows jsonb) returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_result jsonb;
  v_accepted jsonb := '[]';
  v_rejected jsonb := '[]';
  v_conflicts jsonb := '[]';
  v_item jsonb;
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
  select result into v_result from public.sync_batches where id = p_batch_id and user_id = v_uid;
  if found then
    return v_result;
  end if;
  -- The same lock every row write of this farm takes, held from the first read, so no other
  -- batch changes these rows between reading and merging.
  perform pg_advisory_xact_lock(hashtextextended(p_farm_id::text, 0));
  -- A missing parent fails its own row, not the whole batch at commit.
  set constraints all immediate;

  for v_item in select * from jsonb_array_elements(p_rows) loop
    v_entity := v_item ->> 'entity';
    v_id := (v_item -> 'row' ->> 'id')::uuid;
    v_ref := jsonb_build_object('entity', v_entity, 'id', v_id);
    v_base := coalesce((v_item ->> 'base_version')::integer, 0);
    v_changes := coalesce(v_item -> 'changes', '{}');
    begin
      select farm_column into v_farm_column from public.sync_tables
        where name = v_entity and name <> 'template_items';
      if not found then
        raise exception 'not a synced table' using errcode = 'invalid_parameter_value';
      end if;
      if (v_item -> 'row' ->> v_farm_column) is distinct from p_farm_id::text then
        raise exception 'row of another farm' using errcode = 'invalid_parameter_value';
      end if;
      execute format('select to_jsonb(jsonb_populate_record(null::public.%I, $1))', v_entity)
        into v_up using v_item -> 'row';
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
        else
          execute format('insert into public.%I select * from jsonb_populate_record(null::public.%I, $1)',
            v_entity, v_entity) using v_up;
        end if;
        v_orphan := '{}';
        for v_parent in
          select a.attname::text as col, c.confrelid::regclass::text as parent
          from pg_catalog.pg_constraint c
          join pg_catalog.pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
          where c.contype = 'f' and cardinality(c.conkey) = 1
            and c.conrelid = format('public.%I', v_entity)::regclass
            and c.confrelid::regclass::text in (select 'public.' || name from public.sync_tables)
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

      elsif v_entity = 'event_log' or v_base = 0 then
        -- already here: a resent row
        v_accepted := v_accepted || v_ref;

      elsif (v_server ->> 'version')::integer = v_base then
        perform public.sync_write(v_entity, v_id, v_up);
        v_accepted := v_accepted || v_ref;

      else
        v_i_delete := v_changes ? 'deleted_at' and v_up ->> 'deleted_at' is not null;
        v_they_deleted := v_server ->> 'deleted_at' is not null;
        if v_i_delete <> v_they_deleted then
          v_conflicts := v_conflicts || (v_ref || jsonb_build_object('kind', 'delete_edit',
            'fields', '["deleted_at"]'::jsonb, 'theirs', v_server));
        elsif v_i_delete then
          v_accepted := v_accepted || v_ref;
        else
          execute format('select to_jsonb(jsonb_populate_record(null::public.%I, $1))', v_entity)
            into v_base_row using v_changes;
          v_merged := v_server;
          v_clash := '{}';
          for v_field in select jsonb_object_keys(v_changes) loop
            continue when not v_up ? v_field;
            if (v_server -> v_field) is not distinct from (v_base_row -> v_field) then
              v_merged := jsonb_set(v_merged, array[v_field], v_up -> v_field);
            elsif (v_server -> v_field) is not distinct from (v_up -> v_field) then
              null; -- the same value on both phones is not a conflict
            elsif public.is_money_or_quantity(v_field) then
              v_clash := v_clash || v_field;
            else
              v_merged := jsonb_set(v_merged, array[v_field], v_up -> v_field);
            end if;
          end loop;
          v_merged := v_merged || jsonb_build_object(
            'version', greatest((v_server ->> 'version')::integer, (v_up ->> 'version')::integer) + 1,
            'updated_at', v_up -> 'updated_at');
          perform public.sync_write(v_entity, v_id, v_merged);
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

-- ---------- privileges (as in 0001, for the objects added here) ----------
revoke all on public.sync_batches from anon;
revoke truncate, delete, update, references, trigger on public.sync_batches from authenticated;
revoke execute on function public.sync_push(uuid, uuid, jsonb), public.sync_write(text, uuid, jsonb),
  public.is_money_or_quantity(text) from public, anon;
grant execute on function public.sync_push(uuid, uuid, jsonb) to authenticated;
-- sync_write and is_money_or_quantity run inside sync_push as the caller.
grant execute on function public.sync_write(text, uuid, jsonb), public.is_money_or_quantity(text) to authenticated;
