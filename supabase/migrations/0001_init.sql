-- Thottam phase 1 schema (DRAFT: not yet run against a database; validate in task B1).
-- Conventions: UUID ids generated on the device, money in integer paise,
-- soft delete via deleted_at, version for sync, farm_id on every farm-owned row.

create extension if not exists pgcrypto;

-- ---------- helpers ----------
create or replace function set_updated() returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  new.version := coalesce(old.version, 0) + 1;
  return new;
end $$;

-- ---------- people and farms ----------
create table profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null default '',
  phone text,
  language text not null default 'ml' check (language in ('ml', 'en', 'mixed')),
  large_text boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table farms (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  district text,
  settings jsonb not null default '{}',          -- enabled pages, home cards, report rules
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id),
  version integer not null default 1,
  deleted_at timestamptz
);

create table farm_members (
  farm_id uuid not null references farms (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null check (role in ('owner', 'manager', 'supervisor', 'accountant', 'viewer')),
  permissions jsonb not null default '{}',       -- per-person overrides of the role defaults
  created_at timestamptz not null default now(),
  primary key (farm_id, user_id)
);

create or replace function is_farm_member(f uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from farm_members m where m.farm_id = f and m.user_id = auth.uid());
$$;

create or replace function farm_role(f uuid) returns text
language sql stable security definer set search_path = public as $$
  select role from farm_members m where m.farm_id = f and m.user_id = auth.uid();
$$;

-- ---------- templates (admin-managed master data) ----------
create table crops (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,                      -- stable code, e.g. 'pepper'
  name_ml text not null,
  name_en text not null,
  kind text not null check (kind in ('seasonal', 'annual', 'perennial')),
  default_unit text not null default 'kg',
  owner_farm_id uuid references farms (id),       -- null = standard crop, else farmer's own
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table template_items (
  id uuid primary key default gen_random_uuid(),
  crop_id uuid references crops (id) on delete cascade,   -- null = applies to all crops
  list_type text not null check (list_type in
    ('activity', 'input', 'expense_category', 'unit', 'grade', 'process_step', 'labour_task', 'disease', 'sale_grade', 'rate_class')),
  code text not null,
  name_ml text not null,
  name_en text not null,
  data jsonb not null default '{}',               -- default rate, conversion ratio, calendar month, etc.
  sort_order integer not null default 0,
  is_active boolean not null default true,
  template_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (crop_id, list_type, code)
);

-- farm, plot or crop-cycle level changes to a template item, or a farmer's own item
create table template_overrides (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references farms (id) on delete cascade,
  scope text not null check (scope in ('farm', 'plot', 'crop_cycle')),
  scope_id uuid,                                  -- plot or crop cycle id when scope is not 'farm'
  template_item_id uuid references template_items (id) on delete cascade,  -- null = farmer's own item
  crop_id uuid references crops (id),
  list_type text,
  name_ml text,
  name_en text,
  data jsonb not null default '{}',
  hidden boolean not null default false,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id),
  version integer not null default 1,
  deleted_at timestamptz
);

-- ---------- land and crops ----------
create table plots (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references farms (id) on delete cascade,
  name text not null,
  area numeric(12, 3),
  area_unit text not null default 'cent' check (area_unit in ('cent', 'acre', 'hectare', 'are')),
  tenure text not null default 'owned' check (tenure in ('owned', 'leased', 'shared')),
  details jsonb not null default '{}',            -- soil, water source, survey number, boundary
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id),
  version integer not null default 1,
  deleted_at timestamptz
);

create table crop_cycles (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references farms (id) on delete cascade,
  plot_id uuid not null references plots (id) on delete cascade,
  crop_id uuid not null references crops (id),
  variety text,
  plant_count integer,
  area_share numeric(5, 2),                       -- percent of the plot, used for default splits
  season text,
  planted_on date,
  started_on date,
  ended_on date,
  status text not null default 'active' check (status in ('planned', 'active', 'closed')),
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id),
  version integer not null default 1,
  deleted_at timestamptz
);

create table tasks (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references farms (id) on delete cascade,
  crop_cycle_id uuid references crop_cycles (id) on delete cascade,
  title text not null,
  due_on date,
  done_at timestamptz,
  source text not null default 'manual' check (source in ('manual', 'calendar', 'remedy')),
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id),
  version integer not null default 1,
  deleted_at timestamptz
);

-- ---------- parties ----------
create table parties (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references farms (id) on delete cascade,
  kind text not null check (kind in ('buyer', 'vendor', 'landlord', 'lender', 'contractor')),
  name text not null,
  phone text,
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id),
  version integer not null default 1,
  deleted_at timestamptz
);

-- ---------- labour ----------
create table workers (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references farms (id) on delete cascade,
  name text not null,
  phone text,
  skill text,
  wage_type text not null default 'daily' check (wage_type in ('daily', 'hourly', 'piece', 'contract', 'monthly')),
  default_rate_paise bigint not null default 0,
  is_family boolean not null default false,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id),
  version integer not null default 1,
  deleted_at timestamptz
);

create table labour_groups (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references farms (id) on delete cascade,
  label text not null,
  is_named boolean not null default false,        -- false = unnamed head-count group
  leader_party_id uuid references parties (id),
  usual_size integer,
  default_rates jsonb not null default '{}',      -- rate class code -> paise
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id),
  version integer not null default 1,
  deleted_at timestamptz
);

create table labour_group_members (
  group_id uuid not null references labour_groups (id) on delete cascade,
  worker_id uuid not null references workers (id) on delete cascade,
  primary key (group_id, worker_id)
);

-- one row per worker per day per task, or per group rate class per day per task
create table labour_entries (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references farms (id) on delete cascade,
  work_date date not null,
  worker_id uuid references workers (id),
  group_id uuid references labour_groups (id),
  crop_cycle_id uuid references crop_cycles (id),
  plot_id uuid references plots (id),
  task_code text,
  rate_class text,                                -- for groups: 'general', 'climber', ...
  head_count integer not null default 1,
  attendance numeric(3, 2) not null default 1,    -- 1 full, 0.5 half, 0 absent
  hours numeric(5, 2),
  wage_type text not null default 'daily',
  rate_paise bigint not null default 0,           -- per head per day, or per unit for piece rate
  piece_quantity numeric(12, 3),
  piece_unit text,
  amount_paise bigint not null default 0,         -- computed on device, manually overridable
  amount_overridden boolean not null default false,
  harvest_id uuid,                                -- set when the entry is a harvest team (fk added below)
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id),
  version integer not null default 1,
  deleted_at timestamptz,
  check (worker_id is not null or group_id is not null)
);

create table labour_payments (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references farms (id) on delete cascade,
  paid_on date not null,
  worker_id uuid references workers (id),
  group_id uuid references labour_groups (id),
  kind text not null check (kind in ('advance', 'wage', 'bonus', 'deduction')),
  amount_paise bigint not null,
  mode text not null default 'cash' check (mode in ('cash', 'upi', 'bank', 'cheque', 'in_kind')),
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id),
  version integer not null default 1,
  deleted_at timestamptz,
  check (worker_id is not null or group_id is not null)
);

-- ---------- expenses ----------
create table expenses (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references farms (id) on delete cascade,
  spent_on date not null,
  category_code text not null,
  amount_paise bigint not null,
  plot_id uuid references plots (id),
  vendor_party_id uuid references parties (id),
  mode text not null default 'cash' check (mode in ('cash', 'upi', 'bank', 'credit')),
  due_on date,
  notes text,
  photo_path text,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id),
  version integer not null default 1,
  deleted_at timestamptz
);

create table expense_allocations (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references farms (id) on delete cascade,
  expense_id uuid not null references expenses (id) on delete cascade,
  crop_cycle_id uuid not null references crop_cycles (id),
  amount_paise bigint not null,
  is_manual boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  deleted_at timestamptz
);

-- ---------- harvest, lots, sales ----------
create table harvests (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references farms (id) on delete cascade,
  crop_cycle_id uuid not null references crop_cycles (id),
  harvested_on date not null,
  quantity numeric(12, 3) not null,               -- total; equals the sum of team quantities when per-team is on
  unit text not null default 'kg',
  grade_code text,
  per_team_quantity boolean not null default false,
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id),
  version integer not null default 1,
  deleted_at timestamptz
);

-- Harvest teams are labour_entries rows with harvest_id set; piece_quantity holds the
-- team's harvested quantity when per-team quantity is on.
alter table labour_entries
  add constraint labour_entries_harvest_fk foreign key (harvest_id) references harvests (id) on delete cascade;

create table lots (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references farms (id) on delete cascade,
  crop_cycle_id uuid not null references crop_cycles (id),
  harvest_id uuid references harvests (id),
  label text,
  quantity numeric(12, 3) not null,
  quantity_left numeric(12, 3) not null,
  unit text not null default 'kg',
  grade_code text,
  cost_paise bigint not null default 0,           -- allocated cost of this lot
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id),
  version integer not null default 1,
  deleted_at timestamptz
);

create table sales (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references farms (id) on delete cascade,
  sold_on date not null,
  lot_id uuid not null references lots (id),
  buyer_party_id uuid references parties (id),
  sale_type text not null default 'trader',
  quantity numeric(12, 3) not null,
  unit text not null default 'kg',
  rate_paise bigint not null,
  deductions jsonb not null default '[]',         -- [{code, amount_paise}]
  net_paise bigint not null,
  received_paise bigint not null default 0,
  payment_due_on date,
  mode text not null default 'cash',
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id),
  version integer not null default 1,
  deleted_at timestamptz
);

create table other_income (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references farms (id) on delete cascade,
  received_on date not null,
  source_code text not null,
  amount_paise bigint not null,
  crop_cycle_id uuid references crop_cycles (id),
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id),
  version integer not null default 1,
  deleted_at timestamptz
);

-- ---------- prices ----------
create table market_prices (
  id uuid primary key default gen_random_uuid(),
  crop_id uuid not null references crops (id),
  grade_code text,
  market text not null,
  price_paise bigint not null,
  unit text not null default 'kg',
  source text not null,                           -- official source name or 'local'
  published_at timestamptz not null,
  farm_id uuid references farms (id),             -- set for locally entered prices
  created_at timestamptz not null default now()
);
create index market_prices_lookup on market_prices (crop_id, market, published_at desc);

create table price_alerts (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references farms (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  crop_id uuid not null references crops (id),
  market text,
  threshold_paise bigint not null,
  direction text not null default 'above' check (direction in ('above', 'below')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  deleted_at timestamptz
);

-- ---------- history ----------
create table event_log (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references farms (id) on delete cascade,
  entity text not null,                           -- table name
  entity_id uuid not null,
  action text not null check (action in ('create', 'update', 'delete', 'restore')),
  summary jsonb not null default '{}',            -- display fields for the timeline (plot, crop, amount, quantity)
  old_values jsonb,
  new_values jsonb,
  occurred_on date not null,                      -- the date the event belongs to (may be backdated)
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id)
);
create index event_log_farm_day on event_log (farm_id, occurred_on desc, created_at desc);
create index event_log_entity on event_log (entity, entity_id, created_at desc);

-- ---------- triggers ----------
do $$
declare t text;
begin
  foreach t in array array['farms', 'template_overrides', 'plots', 'crop_cycles', 'tasks', 'parties', 'workers',
    'labour_groups', 'labour_entries', 'labour_payments', 'expenses', 'expense_allocations', 'harvests', 'lots',
    'sales', 'other_income', 'price_alerts']
  loop
    execute format('create trigger %I_set_updated before update on %I for each row execute function set_updated()', t, t);
  end loop;
end $$;

-- ---------- row-level security ----------
alter table profiles enable row level security;
create policy profiles_self on profiles for all using (id = auth.uid()) with check (id = auth.uid());

alter table farms enable row level security;
create policy farms_read on farms for select using (is_farm_member(id));
create policy farms_insert on farms for insert with check (created_by = auth.uid());
create policy farms_update on farms for update using (farm_role(id) in ('owner', 'manager'));

alter table farm_members enable row level security;
create policy members_read on farm_members for select using (is_farm_member(farm_id));
create policy members_write on farm_members for all using (farm_role(farm_id) = 'owner') with check (farm_role(farm_id) = 'owner');
-- NOTE (B1): the farm creator needs a first 'owner' row; add it with a security-definer
-- function or trigger on farms insert, since the policy above blocks it.

alter table crops enable row level security;
create policy crops_read on crops for select using (owner_farm_id is null or is_farm_member(owner_farm_id));
create policy crops_write on crops for all using (owner_farm_id is not null and is_farm_member(owner_farm_id))
  with check (owner_farm_id is not null and is_farm_member(owner_farm_id));

alter table template_items enable row level security;
create policy template_items_read on template_items for select using (true);
-- Admin writes to crops and template_items go through the service role (admin console).

alter table market_prices enable row level security;
create policy prices_read on market_prices for select using (farm_id is null or is_farm_member(farm_id));
create policy prices_local_write on market_prices for insert with check (farm_id is not null and is_farm_member(farm_id));

alter table labour_group_members enable row level security;
create policy group_members_all on labour_group_members for all
  using (exists (select 1 from labour_groups g where g.id = group_id and is_farm_member(g.farm_id)))
  with check (exists (select 1 from labour_groups g where g.id = group_id and is_farm_member(g.farm_id)));

do $$
declare t text;
begin
  foreach t in array array['template_overrides', 'plots', 'crop_cycles', 'tasks', 'parties', 'workers', 'labour_groups',
    'labour_entries', 'labour_payments', 'expenses', 'expense_allocations', 'harvests', 'lots', 'sales',
    'other_income', 'price_alerts', 'event_log']
  loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy %I_read on %I for select using (is_farm_member(farm_id))', t, t);
    execute format('create policy %I_write on %I for all using (farm_role(farm_id) in (''owner'', ''manager'', ''supervisor'', ''accountant'')) with check (farm_role(farm_id) in (''owner'', ''manager'', ''supervisor'', ''accountant''))', t, t);
  end loop;
end $$;
-- NOTE (B1/D3): role rules are coarse here. Tighten per docs (supervisor cannot read
-- money tables; accountant cannot write daily entries) and enforce per-person permissions.
