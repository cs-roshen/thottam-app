-- Phase 7: inputs and stock (task E1; docs/product-spec.md "Inputs and stock",
-- docs/screens.md screen 19). Additive only: new tables, one new nullable column on
-- harvests, two new template list types and their items, and the unit ml. Conventions as
-- in 0001.
--
-- Owner decisions, 2026-11-20: an input's cost counts when it is bought, as the purchase's
-- expense, so a use carries a quantity and no cost; the farmer chooses waiting periods and
-- doses; ml joins the standard units.
--
-- Who reads and writes what (product spec, Inputs and stock, rule 10):
-- * input_items and stock_movements are stock, like lots: everyone reads them, and both
--   daily-work and money roles write them, since purchases add stock and applications
--   take it away. A purchase's price lives only on its expense (money), so a supervisor
--   sees how much was bought, never what it cost.
-- * input_applications and soil_tests are daily work.

-- ---------- tables ----------
-- The farm's own list of inputs. A row made from a template item keeps the link, and its
-- names stay null until the farmer renames it.
create table public.input_items (
  id uuid primary key,
  farm_id uuid not null references public.farms (id) on delete cascade deferrable initially deferred,
  template_item_id uuid references public.template_items (id),  -- never cascades
  name_ml text,
  name_en text,
  category_code text not null default 'fertiliser',  -- expense category its purchases go to
  unit text not null default 'kg',
  pack_size bigint check (pack_size > 0),            -- thousandths of unit
  reorder_level bigint check (reorder_level >= 0),   -- thousandths of unit
  waiting_days integer check (waiting_days >= 0),    -- the farmer's own default for a use
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  version integer not null default 1,
  deleted_at timestamptz,
  server_seq bigint not null default 0,
  check (template_item_id is not null or name_ml is not null or name_en is not null)
);

-- Applying an input to one crop cycle. Its quantity is on its stock movement (kind
-- 'application'), saved with it. It has no cost: the money counted when it was bought.
create table public.input_applications (
  id uuid primary key,
  farm_id uuid not null references public.farms (id) on delete cascade deferrable initially deferred,
  applied_on date not null,
  item_id uuid not null references public.input_items (id) deferrable initially deferred,
  plot_id uuid not null references public.plots (id) deferrable initially deferred,
  crop_cycle_id uuid not null references public.crop_cycles (id) deferrable initially deferred,
  method_code text,
  worker_id uuid references public.workers (id) deferrable initially deferred,
  group_id uuid references public.labour_groups (id) deferrable initially deferred,
  waiting_days integer check (waiting_days >= 0),    -- copied from the item, editable on the entry
  dose text,                                         -- as the farmer writes it: "2 ml per litre"
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  version integer not null default 1,
  deleted_at timestamptz,
  server_seq bigint not null default 0
);

-- Every change to an item's stock. Stock on hand is the sum of quantity, never a stored
-- number (two phones using stock offline both add their own row; nothing merges wrongly).
create table public.stock_movements (
  id uuid primary key,
  farm_id uuid not null references public.farms (id) on delete cascade deferrable initially deferred,
  item_id uuid not null references public.input_items (id) deferrable initially deferred,
  moved_on date not null,
  kind text not null check (kind in ('purchase', 'application', 'adjustment')),
  quantity bigint not null check (quantity <> 0),     -- thousandths of the item's unit; out is negative
  expense_id uuid references public.expenses (id) deferrable initially deferred,
  application_id uuid references public.input_applications (id) deferrable initially deferred,
  batch text,
  expires_on date,
  reason text,                                       -- an adjustment's reason
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  version integer not null default 1,
  deleted_at timestamptz,
  server_seq bigint not null default 0,
  check (kind <> 'purchase' or (quantity > 0 and expense_id is not null)),
  check (kind <> 'application' or (quantity < 0 and application_id is not null)),
  check (kind <> 'adjustment' or (expense_id is null and application_id is null))
);

-- results: parameter code (template list soil_parameter) to its value in thousandths.
create table public.soil_tests (
  id uuid primary key,
  farm_id uuid not null references public.farms (id) on delete cascade deferrable initially deferred,
  plot_id uuid not null references public.plots (id) deferrable initially deferred,
  tested_on date not null,
  lab text,
  results jsonb not null default '{}',
  photo_path text,
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  version integer not null default 1,
  deleted_at timestamptz,
  server_seq bigint not null default 0
);

-- Harvesting inside a waiting period needs a reason, kept with the harvest and in history.
alter table public.harvests add column waiting_override_reason text;

-- ---------- sync, history and security, as 0001 and 0003 do for every synced table ----------
insert into public.sync_tables (name, access_class, farm_column, sort_order) values
  ('input_items', 'stock', 'farm_id', 265),
  ('input_applications', 'daily', 'farm_id', 270),
  ('stock_movements', 'stock', 'farm_id', 275),
  ('soil_tests', 'daily', 'farm_id', 280);

do $$
declare r record;
begin
  for r in select name, access_class, farm_column from public.sync_tables
    where name in ('input_items', 'input_applications', 'stock_movements', 'soil_tests')
  loop
    execute format('create trigger %1$I_sync before insert or update on public.%1$I for each row execute function public.sync_row(%2$L)',
      r.name, r.farm_column);
    execute format('create trigger %1$I_keep_version after update on public.%1$I '
      'for each row execute function public.keep_row_version(%2$L)', r.name, r.farm_column);
    execute format('create index %1$I_farm_seq on public.%1$I (farm_id, server_seq)', r.name);
    execute format('alter table public.%I enable row level security', r.name);
    execute format('create policy %1$I_select on public.%1$I for select to authenticated using (farm_id in (select public.my_farms(%2$L, 1)))',
      r.name, r.access_class);
    execute format('create policy %1$I_insert on public.%1$I for insert to authenticated with check (farm_id in (select public.my_farms(%2$L, 2)))',
      r.name, r.access_class);
    execute format('create policy %1$I_update on public.%1$I for update to authenticated using (farm_id in (select public.my_farms(%2$L, 2))) with check (farm_id in (select public.my_farms(%2$L, 2)))',
      r.name, r.access_class);
  end loop;
end $$;

-- Same-farm references (as 0001): every reference from a new table to a farm-owned
-- table becomes (column, farm_id) -> parent (id, farm_id). The phase 1 parents have their
-- (id, farm_id) key from 0001; the two new parents get theirs here.
alter table public.input_items add unique (id, farm_id);
alter table public.input_applications add unique (id, farm_id);
do $$
declare r record;
begin
  for r in
    select c.conname, c.conrelid::regclass::text as child, a.attname::text as col,
      c.confrelid::regclass::text as parent
    from pg_catalog.pg_constraint c
    join pg_catalog.pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
    join public.sync_tables p on c.confrelid = format('public.%I', p.name)::regclass and p.farm_column = 'farm_id'
    join public.sync_tables ch on c.conrelid = format('public.%I', ch.name)::regclass and ch.farm_column = 'farm_id'
    where c.contype = 'f' and cardinality(c.conkey) = 1 and ch.sort_order between 265 and 280
  loop
    execute format('alter table %s drop constraint %I', r.child, r.conname);
    execute format('alter table %s add constraint %I foreign key (%I, farm_id) references %s (id, farm_id) '
      'deferrable initially deferred', r.child, r.conname, r.col, r.parent);
  end loop;
end $$;

-- ---------- templates: release 3 ----------
-- How an input is applied, what a soil test reports (the Soil Health Card's twelve
-- parameters; data.unit is how labs print them), and ml, since pesticides are sold and
-- mixed by the millilitre. No waiting periods or doses: the farmer chooses them, from the
-- label or their own practice.
alter table public.template_items drop constraint template_items_list_type_check;
alter table public.template_items add constraint template_items_list_type_check check (list_type in
  ('activity', 'input', 'expense_category', 'unit', 'grade', 'process_step', 'labour_task',
   'disease', 'sale_grade', 'rate_class', 'setting', 'input_method', 'soil_parameter'));

insert into public.template_items (id, crop_id, list_type, code, name_ml, name_en, sort_order, data, template_version)
select
  md5('thottam:item:' || coalesce(v.crop, '*') || ':' || v.list_type || ':' || v.code)::uuid,
  c.id, v.list_type, v.code, v.name_ml, v.name_en, v.sort_order, v.data::jsonb, 3
from (values
  -- input methods
  (null, 'input_method', 'spray', 'തളിക്കൽ', 'Spray', 10, '{}'),
  (null, 'input_method', 'soil', 'മണ്ണിൽ ചേർക്കൽ', 'Soil application', 20, '{}'),
  (null, 'input_method', 'drench', 'ചുവട്ടിൽ ഒഴിക്കൽ', 'Drench at the base', 30, '{}'),
  (null, 'input_method', 'other', 'മറ്റുള്ളവ', 'Other', 900, '{}'),

  -- unit, beside litre (0002)
  (null, 'unit', 'ml', 'മില്ലി', 'ml', 55, '{"dimension": "volume", "factor": 0.001}'),

  -- soil test parameters
  (null, 'soil_parameter', 'ph', 'അമ്ലത (pH)', 'pH', 10, '{"unit": ""}'),
  (null, 'soil_parameter', 'ec', 'വൈദ്യുത ചാലകത (EC)', 'Electrical conductivity (EC)', 20, '{"unit": "dS/m"}'),
  (null, 'soil_parameter', 'oc', 'ജൈവ കാർബൺ', 'Organic carbon', 30, '{"unit": "%"}'),
  (null, 'soil_parameter', 'n', 'നൈട്രജൻ', 'Nitrogen (N)', 40, '{"unit": "kg/ha"}'),
  (null, 'soil_parameter', 'p', 'ഫോസ്ഫറസ്', 'Phosphorus (P)', 50, '{"unit": "kg/ha"}'),
  (null, 'soil_parameter', 'k', 'പൊട്ടാസ്യം', 'Potassium (K)', 60, '{"unit": "kg/ha"}'),
  (null, 'soil_parameter', 's', 'സൾഫർ', 'Sulphur (S)', 70, '{"unit": "ppm"}'),
  (null, 'soil_parameter', 'zn', 'സിങ്ക്', 'Zinc (Zn)', 80, '{"unit": "ppm"}'),
  (null, 'soil_parameter', 'fe', 'ഇരുമ്പ്', 'Iron (Fe)', 90, '{"unit": "ppm"}'),
  (null, 'soil_parameter', 'cu', 'ചെമ്പ്', 'Copper (Cu)', 100, '{"unit": "ppm"}'),
  (null, 'soil_parameter', 'mn', 'മാംഗനീസ്', 'Manganese (Mn)', 110, '{"unit": "ppm"}'),
  (null, 'soil_parameter', 'b', 'ബോറോൺ', 'Boron (B)', 120, '{"unit": "ppm"}')
) as v (crop, list_type, code, name_ml, name_en, sort_order, data)
left join public.crops c on c.code = v.crop and c.owner_farm_id is null
on conflict do nothing;
