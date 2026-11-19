-- Thottam phase 1 server schema (task B1).
--
-- Rewritten from the never-run draft. Conventions:
-- * Ids are UUIDs generated on the device.
-- * Money is integer paise (bigint).
-- * Quantities, areas, hours, attendance and shares are integer thousandths of their unit
--   (bigint), so sums are exact and match the phone's database.
-- * Nothing is hard-deleted by a client: deleting sets deleted_at.
-- * Every farm-owned, synced table has the common columns
--   id, farm_id, created_at, created_by, updated_at, updated_by, version, deleted_at,
--   plus the server-only server_seq used to pull changes.
--   farms uses its own id as the farm id; crops uses owner_farm_id.
-- * version belongs to the device; the server sets it only when it settles a conflict.
-- * Every row write takes a per-farm transaction lock before it takes its server_seq, so
--   within one farm server_seq order is commit order and a pull by cursor never skips a row
--   committed late (implementation plan section 13).

-- ---------- sync plumbing ----------
create sequence public.sync_seq;

-- One row per synced table: the access class its rows belong to (role rules, product spec
-- rule 7), the column that holds its farm, and the dependency order for upload and pull.
create table public.sync_tables (
  name text primary key,
  access_class text check (access_class in ('setup', 'team', 'daily', 'stock', 'money', 'prices', 'members')),
  farm_column text,
  sort_order integer not null unique
);

insert into public.sync_tables (name, access_class, farm_column, sort_order) values
  ('template_items', null, null, 5),
  ('farms', 'setup', 'id', 10),
  ('farm_members', 'members', 'farm_id', 20),
  ('farm_invites', 'members', 'farm_id', 21),
  ('crops', 'setup', 'owner_farm_id', 30),
  ('template_overrides', 'setup', 'farm_id', 40),
  ('plots', 'setup', 'farm_id', 50),
  ('crop_cycles', 'setup', 'farm_id', 60),
  ('parties', 'money', 'farm_id', 70),
  ('workers', 'team', 'farm_id', 80),
  ('labour_groups', 'team', 'farm_id', 90),
  ('labour_group_members', 'team', 'farm_id', 95),
  ('harvests', 'daily', 'farm_id', 100),
  ('labour_entries', 'daily', 'farm_id', 110),
  ('expenses', 'money', 'farm_id', 120),
  ('notes', 'daily', 'farm_id', 130),
  ('tasks', 'daily', 'farm_id', 140),
  ('market_prices', 'prices', 'farm_id', 150),
  ('price_alerts', 'prices', 'farm_id', 160),
  ('lots', 'stock', 'farm_id', 170),
  ('lot_costs', 'money', 'farm_id', 180),
  ('sales', 'money', 'farm_id', 190),
  ('sale_lots', 'money', 'farm_id', 200),
  ('labour_allocations', 'daily', 'farm_id', 210),
  ('expense_allocations', 'money', 'farm_id', 220),
  ('labour_payments', 'money', 'farm_id', 230),
  ('expense_payments', 'money', 'farm_id', 240),
  ('sale_payments', 'money', 'farm_id', 250),
  ('other_income', 'money', 'farm_id', 260),
  ('event_log', null, 'farm_id', 900);

-- Common trigger for synced rows. tg_argv[0] names the farm column (null for master data).
-- Security definer so it can take the sequence value, which clients cannot touch.
create function public.sync_row() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_farm text;
begin
  if tg_argv[0] is not null then
    v_farm := to_jsonb(new) ->> tg_argv[0];
  end if;
  if tg_op = 'UPDATE' then
    if tg_argv[0] is not null and (to_jsonb(old) ->> tg_argv[0]) is distinct from v_farm then
      raise exception 'a row cannot move to another farm' using errcode = 'check_violation';
    end if;
    new.created_at := old.created_at;
    new.created_by := old.created_by;
  end if;
  -- Client writes are stamped with the signed-in user; service-role writes keep their values.
  if v_uid is not null then
    if tg_op = 'INSERT' then
      new.created_by := v_uid;
    end if;
    new.updated_by := v_uid;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(coalesce(v_farm, 'master'), 0));
  new.server_seq := nextval('public.sync_seq');
  return new;
end $$;

-- Master data rows (template_items) have no farm and no user columns.
create function public.master_row() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform pg_advisory_xact_lock(hashtextextended('master', 0));
  new.server_seq := nextval('public.sync_seq');
  return new;
end $$;

-- event_log is insert-only for everyone.
create function public.event_row() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op <> 'INSERT' then
    raise exception 'history cannot be changed' using errcode = 'insufficient_privilege';
  end if;
  if auth.uid() is not null then
    new.created_by := auth.uid();
  end if;
  perform pg_advisory_xact_lock(hashtextextended(new.farm_id::text, 0));
  new.server_seq := nextval('public.sync_seq');
  return new;
end $$;

-- ---------- people and farms ----------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null default '',
  phone text,
  language text not null default 'ml' check (language in ('ml', 'en', 'mixed')),
  large_text boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', ''))
  on conflict (id) do nothing;
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

create table public.farms (
  id uuid primary key,
  name text not null,
  district text,
  settings jsonb not null default '{}',          -- enabled pages, home cards, report rules
  accepted_template_version integer not null default 0,  -- "update available" when templates are newer
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  version integer not null default 1,
  deleted_at timestamptz,
  server_seq bigint not null default 0
);

create table public.farm_members (
  id uuid primary key,
  farm_id uuid not null references public.farms (id) on delete cascade deferrable initially deferred,
  -- no cascade: closing an account is a server procedure that hands over or closes its farms
  user_id uuid not null references auth.users (id),
  role text not null check (role in ('owner', 'manager', 'supervisor', 'accountant', 'viewer')),
  permissions jsonb not null default '{}',       -- access class -> 'none' | 'read' | 'write'
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  version integer not null default 1,
  deleted_at timestamptz,
  server_seq bigint not null default 0,
  unique (farm_id, user_id)
);
create index farm_members_user on public.farm_members (user_id);

create table public.farm_invites (
  id uuid primary key,
  farm_id uuid not null references public.farms (id) on delete cascade deferrable initially deferred,
  email text not null check (email = lower(email)),
  role text not null check (role in ('manager', 'supervisor', 'accountant', 'viewer', 'owner')),
  permissions jsonb not null default '{}',
  accepted_at timestamptz,
  accepted_by uuid,
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  version integer not null default 1,
  deleted_at timestamptz,
  server_seq bigint not null default 0
);
create index farm_invites_email on public.farm_invites (email) where accepted_at is null and deleted_at is null;

-- The user's role and per-person permissions reduced to one level per access class:
-- 0 none, 1 read, 2 write. Role defaults follow product spec rule 7.
create function public.access_level(p_role text, p_permissions jsonb, p_class text) returns integer
language sql immutable set search_path = '' as $$
  select case
    when p_role = 'owner' then 2
    else coalesce(
      case p_permissions ->> p_class when 'write' then 2 when 'read' then 1 when 'none' then 0 end,
      case p_class
        when 'setup' then case p_role when 'manager' then 2 else 1 end
        when 'team' then case p_role when 'manager' then 2 when 'supervisor' then 2 else 1 end
        when 'daily' then case p_role when 'manager' then 2 when 'supervisor' then 2 else 1 end
        when 'stock' then case p_role when 'viewer' then 1 else 2 end
        when 'money' then case p_role when 'manager' then 2 when 'accountant' then 2 when 'supervisor' then 0 else 1 end
        when 'prices' then case p_role when 'manager' then 2 when 'accountant' then 2 else 1 end
        when 'members' then 0
        else 0
      end)
  end
$$;

-- Farms where the signed-in user has at least p_min on p_class (p_min 0: any membership).
create function public.my_farms(p_class text, p_min integer) returns setof uuid
language sql stable security definer set search_path = '' as $$
  select m.farm_id from public.farm_members m
  where m.user_id = (select auth.uid()) and m.deleted_at is null
    and public.access_level(m.role, m.permissions, p_class) >= p_min
$$;

create function public.my_owned_farms() returns setof uuid
language sql stable security definer set search_path = '' as $$
  select m.farm_id from public.farm_members m
  where m.user_id = (select auth.uid()) and m.deleted_at is null and m.role = 'owner'
$$;

-- (farm, table) pairs the user may reach at p_min; used for event_log, whose rows belong to
-- the access class of the table they describe.
create function public.my_entities(p_min integer) returns table (farm_id uuid, entity text)
language sql stable security definer set search_path = '' as $$
  select m.farm_id, t.name
  from public.farm_members m
  join public.sync_tables t on t.access_class is not null
  where m.user_id = (select auth.uid()) and m.deleted_at is null
    and public.access_level(m.role, m.permissions, t.access_class) >= p_min
$$;

create function public.my_co_members() returns setof uuid
language sql stable security definer set search_path = '' as $$
  select distinct o.user_id from public.farm_members m
  join public.farm_members o on o.farm_id = m.farm_id and o.deleted_at is null
  where m.user_id = (select auth.uid()) and m.deleted_at is null
$$;

-- ---------- templates (admin-managed master data) ----------
create table public.crops (
  id uuid primary key,
  code text not null,                             -- stable code, e.g. 'pepper'
  name_ml text not null,
  name_en text not null,
  kind text not null check (kind in ('seasonal', 'annual', 'perennial')),
  default_unit text not null default 'kg',
  owner_farm_id uuid references public.farms (id) deferrable initially deferred,  -- null = standard crop
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  version integer not null default 1,
  deleted_at timestamptz,
  server_seq bigint not null default 0
);
create unique index crops_standard_code on public.crops (code) where owner_farm_id is null;
create unique index crops_farm_code on public.crops (owner_farm_id, code) where owner_farm_id is not null;
create index crops_farm_seq on public.crops (owner_farm_id, server_seq);

create table public.template_items (
  id uuid primary key,
  crop_id uuid references public.crops (id),  -- null = applies to all crops; retire items with is_active
  list_type text not null check (list_type in
    ('activity', 'input', 'expense_category', 'unit', 'grade', 'process_step', 'labour_task',
     'disease', 'sale_grade', 'rate_class', 'setting')),
  code text not null,
  name_ml text not null,
  name_en text not null,
  data jsonb not null default '{}',               -- default rate, conversion factor, split weight, etc.
  sort_order integer not null default 0,
  is_active boolean not null default true,
  template_version integer not null default 1,    -- the template release this item last changed in
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  server_seq bigint not null default 0,
  unique nulls not distinct (crop_id, list_type, code)
);
create index template_items_seq on public.template_items (server_seq);

-- farm, plot or crop-cycle level changes to a template item, or a farmer's own item
create table public.template_overrides (
  id uuid primary key,
  farm_id uuid not null references public.farms (id) on delete cascade deferrable initially deferred,
  scope text not null check (scope in ('farm', 'plot', 'crop_cycle')),
  scope_id uuid,                                  -- plot or crop cycle id when scope is not 'farm'
  template_item_id uuid references public.template_items (id),  -- null = farmer's own item; never cascades
  crop_id uuid references public.crops (id) deferrable initially deferred,
  list_type text,
  code text,
  name_ml text,
  name_en text,
  data jsonb not null default '{}',
  hidden boolean,                                 -- null: this level leaves it as it is
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  version integer not null default 1,
  deleted_at timestamptz,
  server_seq bigint not null default 0
);

-- ---------- land and crops ----------
create table public.plots (
  id uuid primary key,
  farm_id uuid not null references public.farms (id) on delete cascade deferrable initially deferred,
  name text not null,
  area bigint,                                    -- thousandths of area_unit
  area_unit text not null default 'cent',         -- unit code from templates
  tenure text not null default 'owned' check (tenure in ('owned', 'leased', 'shared')),
  details jsonb not null default '{}',            -- soil, water source, survey number, boundary
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  version integer not null default 1,
  deleted_at timestamptz,
  server_seq bigint not null default 0
);

create table public.crop_cycles (
  id uuid primary key,
  farm_id uuid not null references public.farms (id) on delete cascade deferrable initially deferred,
  plot_id uuid not null references public.plots (id) deferrable initially deferred,
  crop_id uuid not null references public.crops (id) deferrable initially deferred,
  variety text,
  plant_count integer,
  area_share bigint,                              -- thousandths of a percent of the plot
  season text,
  planted_on date,
  started_on date,
  ended_on date,
  status text not null default 'active' check (status in ('planned', 'active', 'closed')),
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  version integer not null default 1,
  deleted_at timestamptz,
  server_seq bigint not null default 0
);

create table public.tasks (
  id uuid primary key,
  farm_id uuid not null references public.farms (id) on delete cascade deferrable initially deferred,
  crop_cycle_id uuid references public.crop_cycles (id) deferrable initially deferred,
  plot_id uuid references public.plots (id) deferrable initially deferred,
  title text not null,
  due_on date,
  done_at timestamptz,
  source text not null default 'manual' check (source in ('manual', 'calendar', 'remedy')),
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  version integer not null default 1,
  deleted_at timestamptz,
  server_seq bigint not null default 0
);

create table public.notes (
  id uuid primary key,
  farm_id uuid not null references public.farms (id) on delete cascade deferrable initially deferred,
  noted_on date not null,
  body text not null,
  plot_id uuid references public.plots (id) deferrable initially deferred,
  crop_cycle_id uuid references public.crop_cycles (id) deferrable initially deferred,
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  version integer not null default 1,
  deleted_at timestamptz,
  server_seq bigint not null default 0
);

-- ---------- parties (buyers, vendors and others; money) ----------
create table public.parties (
  id uuid primary key,
  farm_id uuid not null references public.farms (id) on delete cascade deferrable initially deferred,
  kind text not null check (kind in ('buyer', 'vendor', 'landlord', 'lender', 'contractor')),
  name text not null,
  phone text,
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  version integer not null default 1,
  deleted_at timestamptz,
  server_seq bigint not null default 0
);

-- ---------- labour ----------
create table public.workers (
  id uuid primary key,
  farm_id uuid not null references public.farms (id) on delete cascade deferrable initially deferred,
  name text not null,
  phone text,
  skill text,
  wage_type text not null default 'daily' check (wage_type in ('daily', 'hourly', 'piece', 'contract', 'monthly')),
  default_rate_paise bigint not null default 0,
  is_family boolean not null default false,
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  version integer not null default 1,
  deleted_at timestamptz,
  server_seq bigint not null default 0
);

create table public.labour_groups (
  id uuid primary key,
  farm_id uuid not null references public.farms (id) on delete cascade deferrable initially deferred,
  label text not null,
  is_named boolean not null default false,        -- false = unnamed head-count group
  leader_worker_id uuid references public.workers (id) deferrable initially deferred,
  usual_size integer,
  default_rates jsonb not null default '{}',      -- rate class code -> paise
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  version integer not null default 1,
  deleted_at timestamptz,
  server_seq bigint not null default 0
);

create table public.labour_group_members (
  id uuid primary key,
  farm_id uuid not null references public.farms (id) on delete cascade deferrable initially deferred,
  group_id uuid not null references public.labour_groups (id) deferrable initially deferred,
  worker_id uuid not null references public.workers (id) deferrable initially deferred,
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  version integer not null default 1,
  deleted_at timestamptz,
  server_seq bigint not null default 0
);

create table public.harvests (
  id uuid primary key,
  farm_id uuid not null references public.farms (id) on delete cascade deferrable initially deferred,
  crop_cycle_id uuid not null references public.crop_cycles (id) deferrable initially deferred,
  plot_id uuid not null references public.plots (id) deferrable initially deferred,
  harvested_on date not null,
  quantity bigint not null,                       -- thousandths; the sum of team quantities when per-team is on
  unit text not null default 'kg',
  grade_code text,
  per_team_quantity boolean not null default false,
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  version integer not null default 1,
  deleted_at timestamptz,
  server_seq bigint not null default 0
);

-- One row per worker per day per task, or per group rate class per day per task.
-- Harvest teams are rows with harvest_id set; piece_quantity holds the team's quantity.
create table public.labour_entries (
  id uuid primary key,
  farm_id uuid not null references public.farms (id) on delete cascade deferrable initially deferred,
  work_date date not null,
  worker_id uuid references public.workers (id) deferrable initially deferred,
  group_id uuid references public.labour_groups (id) deferrable initially deferred,
  crop_cycle_id uuid references public.crop_cycles (id) deferrable initially deferred,  -- null when split (labour_allocations)
  plot_id uuid references public.plots (id) deferrable initially deferred,
  harvest_id uuid references public.harvests (id) deferrable initially deferred,
  task_code text,
  rate_class text,                                -- for groups: 'general', 'climber', ...
  head_count integer not null default 1,
  attendance bigint not null default 1000 check (attendance between 0 and 1000),  -- thousandths: 1000 full, 500 half, 0 absent
  wage_type text not null default 'daily' check (wage_type in ('daily', 'hourly', 'piece', 'contract', 'monthly')),
  hours bigint,                                   -- thousandths of an hour, for the hourly wage type
  overtime_hours bigint,                          -- thousandths of an hour beyond a full day
  overtime_rate_paise bigint,                     -- per hour; defaults from templates
  rate_paise bigint not null default 0,           -- per head per day, per hour, or per unit for piece rate
  piece_quantity bigint,                          -- thousandths of piece_unit
  piece_unit text,
  amount_paise bigint not null default 0,         -- computed on the device, can be edited by hand
  amount_overridden boolean not null default false,
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  version integer not null default 1,
  deleted_at timestamptz,
  server_seq bigint not null default 0,
  check (worker_id is not null or group_id is not null)
);

-- Wage cost of one labour entry split across a mixed plot's crop cycles.
create table public.labour_allocations (
  id uuid primary key,
  farm_id uuid not null references public.farms (id) on delete cascade deferrable initially deferred,
  labour_entry_id uuid not null references public.labour_entries (id) deferrable initially deferred,
  crop_cycle_id uuid not null references public.crop_cycles (id) deferrable initially deferred,
  amount_paise bigint not null,
  is_manual boolean not null default false,
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  version integer not null default 1,
  deleted_at timestamptz,
  server_seq bigint not null default 0
);

create table public.labour_payments (
  id uuid primary key,
  farm_id uuid not null references public.farms (id) on delete cascade deferrable initially deferred,
  paid_on date not null,
  worker_id uuid references public.workers (id) deferrable initially deferred,
  group_id uuid references public.labour_groups (id) deferrable initially deferred,
  kind text not null check (kind in ('advance', 'part_payment', 'settlement', 'bonus', 'deduction')),
  amount_paise bigint not null,
  mode text not null default 'cash' check (mode in ('cash', 'upi', 'bank', 'cheque', 'in_kind')),
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  version integer not null default 1,
  deleted_at timestamptz,
  server_seq bigint not null default 0,
  check (worker_id is not null or group_id is not null)
);

-- ---------- expenses ----------
create table public.expenses (
  id uuid primary key,
  farm_id uuid not null references public.farms (id) on delete cascade deferrable initially deferred,
  spent_on date not null,
  category_code text not null,
  amount_paise bigint not null,
  plot_id uuid references public.plots (id) deferrable initially deferred,
  vendor_party_id uuid references public.parties (id) deferrable initially deferred,
  mode text not null default 'cash' check (mode in ('cash', 'upi', 'bank', 'credit')),
  due_on date,
  notes text,
  photo_path text,
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  version integer not null default 1,
  deleted_at timestamptz,
  server_seq bigint not null default 0
);

create table public.expense_allocations (
  id uuid primary key,
  farm_id uuid not null references public.farms (id) on delete cascade deferrable initially deferred,
  expense_id uuid not null references public.expenses (id) deferrable initially deferred,
  crop_cycle_id uuid not null references public.crop_cycles (id) deferrable initially deferred,
  amount_paise bigint not null,
  is_manual boolean not null default false,
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  version integer not null default 1,
  deleted_at timestamptz,
  server_seq bigint not null default 0
);

-- Payments against an expense bought on credit (a payable), so it can be part-paid.
create table public.expense_payments (
  id uuid primary key,
  farm_id uuid not null references public.farms (id) on delete cascade deferrable initially deferred,
  expense_id uuid not null references public.expenses (id) deferrable initially deferred,
  paid_on date not null,
  amount_paise bigint not null,
  mode text not null default 'cash' check (mode in ('cash', 'upi', 'bank', 'cheque')),
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  version integer not null default 1,
  deleted_at timestamptz,
  server_seq bigint not null default 0
);

-- ---------- lots, sales ----------
-- Stock left in a lot is derived on the phone: quantity minus the sale_lots drawn from it.
-- (A stored remainder would merge wrongly: two offline sales of 10 from 50 both write 40.)
create table public.lots (
  id uuid primary key,
  farm_id uuid not null references public.farms (id) on delete cascade deferrable initially deferred,
  crop_cycle_id uuid not null references public.crop_cycles (id) deferrable initially deferred,
  harvest_id uuid references public.harvests (id) deferrable initially deferred,
  label text,
  quantity bigint not null,                       -- thousandths of unit
  unit text not null default 'kg',
  grade_code text,
  teams_stamp uuid,                               -- new random value on every edit to the harvest's teams
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  version integer not null default 1,
  deleted_at timestamptz,
  server_seq bigint not null default 0
);

-- A lot's cost (product spec rule 9); money, so a supervisor cannot read it.
-- Its id is its lot's id, so every phone writes the same row. The cost is "not yet worked out"
-- when there is no row or teams_stamp differs from lots.teams_stamp.
create table public.lot_costs (
  id uuid primary key references public.lots (id) deferrable initially deferred,
  farm_id uuid not null references public.farms (id) on delete cascade deferrable initially deferred,
  cost_paise bigint not null default 0,
  cost_overridden boolean not null default false,
  teams_stamp uuid,                               -- the lot's teams_stamp this cost was worked out from
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  version integer not null default 1,
  deleted_at timestamptz,
  server_seq bigint not null default 0
);

-- How much has been received is derived from sale_payments.
create table public.sales (
  id uuid primary key,
  farm_id uuid not null references public.farms (id) on delete cascade deferrable initially deferred,
  sold_on date not null,
  buyer_party_id uuid references public.parties (id) deferrable initially deferred,
  sale_type text not null default 'trader',
  quantity bigint not null,                       -- thousandths of the sale unit
  unit text not null default 'kg',
  grade_code text,
  rate_paise bigint not null,                     -- per sale unit
  deductions jsonb not null default '[]',         -- [{code, amount_paise}]
  net_paise bigint not null,
  payment_due_on date,
  mode text not null default 'cash' check (mode in ('cash', 'upi', 'bank', 'cheque', 'credit')),
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  version integer not null default 1,
  deleted_at timestamptz,
  server_seq bigint not null default 0
);

create table public.sale_lots (
  id uuid primary key,
  farm_id uuid not null references public.farms (id) on delete cascade deferrable initially deferred,
  sale_id uuid not null references public.sales (id) deferrable initially deferred,
  lot_id uuid not null references public.lots (id) deferrable initially deferred,
  quantity bigint not null,                       -- thousandths of the lot's unit
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  version integer not null default 1,
  deleted_at timestamptz,
  server_seq bigint not null default 0
);

create table public.sale_payments (
  id uuid primary key,
  farm_id uuid not null references public.farms (id) on delete cascade deferrable initially deferred,
  sale_id uuid not null references public.sales (id) deferrable initially deferred,
  received_on date not null,
  amount_paise bigint not null,
  mode text not null default 'cash' check (mode in ('cash', 'upi', 'bank', 'cheque')),
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  version integer not null default 1,
  deleted_at timestamptz,
  server_seq bigint not null default 0
);

create table public.other_income (
  id uuid primary key,
  farm_id uuid not null references public.farms (id) on delete cascade deferrable initially deferred,
  received_on date not null,
  source_code text not null,
  amount_paise bigint not null,
  crop_cycle_id uuid references public.crop_cycles (id) deferrable initially deferred,
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  version integer not null default 1,
  deleted_at timestamptz,
  server_seq bigint not null default 0
);

-- ---------- prices ----------
-- Official prices have no farm (master data, written by the service role); a farmer's
-- locally entered prices carry their farm and the common columns.
create table public.market_prices (
  id uuid primary key,
  farm_id uuid references public.farms (id) on delete cascade deferrable initially deferred,
  crop_id uuid not null references public.crops (id) deferrable initially deferred,
  grade_code text,
  market text not null,
  price_paise bigint not null,
  unit text not null default 'kg',
  source text not null,                           -- official source name or 'local'
  published_at timestamptz not null,
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  version integer not null default 1,
  deleted_at timestamptz,
  server_seq bigint not null default 0
);

create table public.price_alerts (
  id uuid primary key,
  farm_id uuid not null references public.farms (id) on delete cascade deferrable initially deferred,
  user_id uuid not null references auth.users (id) on delete cascade,
  crop_id uuid not null references public.crops (id) deferrable initially deferred,
  market text,
  threshold_paise bigint not null,
  direction text not null default 'above' check (direction in ('above', 'below')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  version integer not null default 1,
  deleted_at timestamptz,
  server_seq bigint not null default 0
);

-- ---------- history ----------
-- Insert-only. Rows belong to the access class of the table named in entity.
create table public.event_log (
  id uuid primary key,
  farm_id uuid not null references public.farms (id) on delete cascade deferrable initially deferred,
  entity text not null,                           -- table name
  entity_id uuid not null,
  action text not null check (action in ('create', 'update', 'delete', 'restore')),
  summary jsonb not null default '{}',            -- display fields for the timeline (plot, crop, amount, quantity)
  old_values jsonb,                               -- changed fields only for updates
  new_values jsonb,
  occurred_on date not null,                      -- the date the event belongs to (may be backdated)
  created_at timestamptz not null default now(),
  created_by uuid,
  server_seq bigint not null default 0
);

-- ---------- triggers and pull indexes ----------
create trigger template_items_sync before insert or update on public.template_items
  for each row execute function public.master_row();
create trigger event_log_sync before insert or update on public.event_log
  for each row execute function public.event_row();
create index event_log_farm_seq on public.event_log (farm_id, server_seq);

do $$
declare r record;
begin
  for r in select name, farm_column from public.sync_tables where name not in ('template_items', 'event_log')
  loop
    execute format('create trigger %1$I_sync before insert or update on public.%1$I for each row execute function public.sync_row(%2$L)',
      r.name, r.farm_column);
    if r.name not in ('crops', 'farms') then
      execute format('create index %1$I_farm_seq on public.%1$I (farm_id, server_seq)', r.name);
    end if;
  end loop;
end $$;
create index farms_seq on public.farms (server_seq);

create function public.farm_members_guard() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.user_id <> old.user_id then
    raise exception 'a membership cannot move to another person' using errcode = 'check_violation';
  end if;
  if old.role = 'owner' and old.deleted_at is null
     and (new.role <> 'owner' or new.deleted_at is not null) then
    -- the farm's lock first, so two owners cannot remove each other at the same time
    perform pg_advisory_xact_lock(hashtextextended(new.farm_id::text, 0));
    if not exists (select 1 from public.farm_members m where m.farm_id = new.farm_id and m.id <> new.id
                   and m.role = 'owner' and m.deleted_at is null) then
      raise exception 'a farm keeps at least one owner' using errcode = 'check_violation';
    end if;
  end if;
  return new;
end $$;
create trigger farm_members_guard before update on public.farm_members
  for each row execute function public.farm_members_guard();

-- ---------- functions clients call ----------
-- Creates a farm and its owner's membership in one transaction. Ids come from the device;
-- calling again with the same farm id by the same person returns the existing farm.
create function public.create_farm(
  p_id uuid, p_member_id uuid, p_name text, p_district text default null,
  p_settings jsonb default '{}', p_created_at timestamptz default now()
) returns public.farms
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_farm public.farms;
begin
  if v_uid is null then
    raise exception 'sign in first' using errcode = 'insufficient_privilege';
  end if;
  select * into v_farm from public.farms where id = p_id;
  if found then
    if v_farm.created_by = v_uid and exists (select 1 from public.farm_members m
         where m.farm_id = p_id and m.user_id = v_uid and m.deleted_at is null) then
      return v_farm;
    end if;
    raise exception 'farm id already used' using errcode = 'unique_violation';
  end if;
  insert into public.farms (id, name, district, settings, created_at, updated_at)
  values (p_id, p_name, p_district, coalesce(p_settings, '{}'), p_created_at, p_created_at)
  returning * into v_farm;
  insert into public.farm_members (id, farm_id, user_id, role, created_at, updated_at)
  values (p_member_id, p_id, v_uid, 'owner', p_created_at, p_created_at);
  return v_farm;
end $$;

-- Milliseconds since the epoch: how the phone stores times, also inside history values.
create function public.epoch_ms(p_time timestamptz) returns bigint
language sql immutable set search_path = '' as $$
  select (extract(epoch from p_time) * 1000)::bigint
$$;

-- A history row written by the server, with values in the phone's form. Runs with the
-- caller's rights, so a client calling it can do no more than insert into event_log itself.
create function public.log_event(p_entity text, p_entity_id uuid, p_farm_id uuid, p_action text,
  p_old jsonb, p_new jsonb) returns void
language sql set search_path = '' as $$
  insert into public.event_log (id, farm_id, entity, entity_id, action, old_values, new_values, occurred_on)
  values (gen_random_uuid(), p_farm_id, p_entity, p_entity_id, p_action, p_old, p_new, current_date)
$$;

-- Invites go by Google email, so only an email a Google sign-in confirmed counts: the
-- signed-in account's, or null.
create function public.my_invite_email() returns text
language sql stable security definer set search_path = '' as $$
  select lower(u.email) from auth.users u
  where u.id = auth.uid() and u.email_confirmed_at is not null
    and exists (select 1 from auth.identities i where i.user_id = u.id and i.provider = 'google'
                and lower(i.identity_data ->> 'email') = lower(u.email))
$$;

-- The signed-in account's open invites, so the person can choose to join or decline: nobody
-- is added to a farm until they accept. Shows the farm's name, the role and who invited them;
-- a withdrawn or declined invite never shows, nor one to a farm they are already active in.
create function public.my_invites()
returns table (id uuid, farm_id uuid, farm_name text, role text, invited_by text, created_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select i.id, i.farm_id, f.name, i.role, p.full_name, i.created_at
  from public.farm_invites i
  join public.farms f on f.id = i.farm_id and f.deleted_at is null
  left join public.profiles p on p.id = i.created_by
  where i.email = public.my_invite_email() and i.accepted_at is null and i.deleted_at is null
    and not exists (select 1 from public.farm_members m
                    where m.farm_id = i.farm_id and m.user_id = auth.uid() and m.deleted_at is null)
  order by i.created_at, i.id
$$;

-- Joins the farm of one open invite when the person taps Join. An invite only adds a person
-- or brings back a removed one: it never changes an active membership, so it cannot demote
-- anyone. Every open invite from that farm to the same email closes with it, so an old one
-- cannot bring the person back after a later removal. Returns the farm id, or null when the
-- invite is not theirs or no longer open. Every change is written to history.
create function public.accept_invite(p_invite uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_email text := public.my_invite_email();
  v_invite public.farm_invites;
  r public.farm_invites;
  v_old public.farm_members;
  v_new public.farm_members;
  v_now timestamptz := now();
begin
  select * into v_invite from public.farm_invites i
  where i.id = p_invite and i.email = v_email and i.accepted_at is null and i.deleted_at is null
  for update;
  if not found then
    return null;
  end if;
  select * into v_old from public.farm_members m where m.farm_id = v_invite.farm_id and m.user_id = v_uid;
  if not found then
    insert into public.farm_members (id, farm_id, user_id, role, permissions)
    values (gen_random_uuid(), v_invite.farm_id, v_uid, v_invite.role, v_invite.permissions)
    returning * into v_new;
    perform public.log_event('farm_members', v_new.id, v_invite.farm_id, 'create', null,
      jsonb_build_object('user_id', v_uid, 'role', v_new.role, 'permissions', v_new.permissions::text));
  elsif v_old.deleted_at is not null then
    update public.farm_members
      set role = v_invite.role, permissions = v_invite.permissions, deleted_at = null,
          updated_at = v_now, version = version + 1
      where id = v_old.id
      returning * into v_new;
    perform public.log_event('farm_members', v_old.id, v_invite.farm_id, 'update',
      jsonb_build_object('role', v_old.role, 'permissions', v_old.permissions::text,
        'deleted_at', public.epoch_ms(v_old.deleted_at)),
      jsonb_build_object('role', v_new.role, 'permissions', v_new.permissions::text, 'deleted_at', null));
  end if;
  for r in
    select * from public.farm_invites i
    where i.farm_id = v_invite.farm_id and i.email = v_email and i.accepted_at is null and i.deleted_at is null
    order by i.created_at, i.id
  loop
    update public.farm_invites
      set accepted_at = v_now, accepted_by = v_uid, updated_at = v_now, version = version + 1
      where id = r.id;
    perform public.log_event('farm_invites', r.id, r.farm_id, 'update',
      jsonb_build_object('accepted_at', null, 'accepted_by', null),
      jsonb_build_object('accepted_at', public.epoch_ms(v_now), 'accepted_by', v_uid));
  end loop;
  return v_invite.farm_id;
end $$;

-- Declines one open invite when the person taps Decline: every open invite from that farm to
-- the same email closes (deleted_at, as if withdrawn), written to history under their name.
-- Returns the farm id, or null when the invite is not theirs or no longer open.
create function public.decline_invite(p_invite uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_email text := public.my_invite_email();
  v_farm uuid;
  r public.farm_invites;
  v_now timestamptz := now();
begin
  select i.farm_id into v_farm from public.farm_invites i
  where i.id = p_invite and i.email = v_email and i.accepted_at is null and i.deleted_at is null;
  if v_farm is null then
    return null;
  end if;
  for r in
    select * from public.farm_invites i
    where i.farm_id = v_farm and i.email = v_email and i.accepted_at is null and i.deleted_at is null
    order by i.created_at, i.id
  loop
    update public.farm_invites
      set deleted_at = v_now, updated_at = v_now, version = version + 1
      where id = r.id;
    perform public.log_event('farm_invites', r.id, r.farm_id, 'delete',
      jsonb_build_object('email', r.email, 'role', r.role), null);
  end loop;
  return v_farm;
end $$;

-- ---------- row-level security ----------
-- Every policy names its role; membership lookups are security-definer functions called
-- once per statement inside a sub-select. There is no delete policy on any table.
alter table public.sync_tables enable row level security;
create policy sync_tables_select on public.sync_tables for select to authenticated using (true);

alter table public.profiles enable row level security;
create policy profiles_select on public.profiles for select to authenticated
  using (id = (select auth.uid()) or id in (select public.my_co_members()));
create policy profiles_update on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

alter table public.farms enable row level security;
create policy farms_select on public.farms for select to authenticated
  using (id in (select public.my_farms('setup', 0)));
create policy farms_update on public.farms for update to authenticated
  using (id in (select public.my_farms('setup', 2))) with check (id in (select public.my_farms('setup', 2)));

-- Memberships are created by create_farm and accept_invite; clients only change them.
alter table public.farm_members enable row level security;
create policy farm_members_select on public.farm_members for select to authenticated
  using (user_id = (select auth.uid()) or farm_id in (select public.my_farms('members', 1)));
create policy farm_members_update on public.farm_members for update to authenticated
  using (farm_id in (select public.my_farms('members', 2))
         and (role <> 'owner' or farm_id in (select public.my_owned_farms())))
  with check (farm_id in (select public.my_farms('members', 2))
         and (role <> 'owner' or farm_id in (select public.my_owned_farms())));

alter table public.farm_invites enable row level security;
create policy farm_invites_select on public.farm_invites for select to authenticated
  using (farm_id in (select public.my_farms('members', 1)));
create policy farm_invites_insert on public.farm_invites for insert to authenticated
  with check (farm_id in (select public.my_farms('members', 2))
         and (role <> 'owner' or farm_id in (select public.my_owned_farms())));
create policy farm_invites_update on public.farm_invites for update to authenticated
  using (accepted_at is null and farm_id in (select public.my_farms('members', 2))
         and (role <> 'owner' or farm_id in (select public.my_owned_farms())))
  with check (farm_id in (select public.my_farms('members', 2))
         and (role <> 'owner' or farm_id in (select public.my_owned_farms())));

alter table public.crops enable row level security;
create policy crops_select on public.crops for select to authenticated
  using (owner_farm_id is null or owner_farm_id in (select public.my_farms('setup', 1)));
create policy crops_insert on public.crops for insert to authenticated
  with check (owner_farm_id in (select public.my_farms('setup', 2)));
create policy crops_update on public.crops for update to authenticated
  using (owner_farm_id in (select public.my_farms('setup', 2)))
  with check (owner_farm_id in (select public.my_farms('setup', 2)));

-- Admin writes to standard crops, template items and official prices use the service role.
alter table public.template_items enable row level security;
create policy template_items_select on public.template_items for select to authenticated using (true);

alter table public.market_prices enable row level security;
create policy market_prices_select on public.market_prices for select to authenticated
  using (farm_id is null or farm_id in (select public.my_farms('prices', 1)));
create policy market_prices_insert on public.market_prices for insert to authenticated
  with check (farm_id in (select public.my_farms('prices', 2)));
create policy market_prices_update on public.market_prices for update to authenticated
  using (farm_id in (select public.my_farms('prices', 2)))
  with check (farm_id in (select public.my_farms('prices', 2)));

alter table public.event_log enable row level security;
create policy event_log_select on public.event_log for select to authenticated
  using ((farm_id, entity) in (select e.farm_id, e.entity from public.my_entities(1) e));
create policy event_log_insert on public.event_log for insert to authenticated
  with check ((farm_id, entity) in (select e.farm_id, e.entity from public.my_entities(2) e));

do $$
declare r record;
begin
  for r in select name, access_class from public.sync_tables
    where name not in ('template_items', 'farms', 'farm_members', 'farm_invites', 'crops', 'market_prices',
      'price_alerts', 'event_log')
  loop
    execute format('alter table public.%I enable row level security', r.name);
    -- what has been taken from a lot is part of its stock left, which stock readers see
    execute format('create policy %1$I_select on public.%1$I for select to authenticated using (farm_id in (select public.my_farms(%2$L, 1)))',
      r.name, case r.name when 'sale_lots' then 'stock' else r.access_class end);
    execute format('create policy %1$I_insert on public.%1$I for insert to authenticated with check (farm_id in (select public.my_farms(%2$L, 2)))',
      r.name, r.access_class);
    execute format('create policy %1$I_update on public.%1$I for update to authenticated using (farm_id in (select public.my_farms(%2$L, 2))) with check (farm_id in (select public.my_farms(%2$L, 2)))',
      r.name, r.access_class);
  end loop;
end $$;

-- A price alert belongs to the person who set it.
alter table public.price_alerts enable row level security;
create policy price_alerts_select on public.price_alerts for select to authenticated
  using (user_id = (select auth.uid()) and farm_id in (select public.my_farms('prices', 1)));
create policy price_alerts_insert on public.price_alerts for insert to authenticated
  with check (user_id = (select auth.uid()) and farm_id in (select public.my_farms('prices', 2)));
create policy price_alerts_update on public.price_alerts for update to authenticated
  using (user_id = (select auth.uid()) and farm_id in (select public.my_farms('prices', 2)))
  with check (user_id = (select auth.uid()) and farm_id in (select public.my_farms('prices', 2)));

-- ---------- same-farm references ----------
-- A row may only point at a parent of its own farm: every reference between farm-owned
-- tables is (column, farm_id) -> parent (id, farm_id). Otherwise a member of two farms
-- could claim another farm's lot cost row, or file farm A's expense against farm B's plot.
do $$
declare r record;
begin
  for r in
    select distinct c.confrelid::regclass::text as parent
    from pg_catalog.pg_constraint c
    join public.sync_tables p on c.confrelid = format('public.%I', p.name)::regclass and p.farm_column = 'farm_id'
    join public.sync_tables ch on c.conrelid = format('public.%I', ch.name)::regclass and ch.farm_column = 'farm_id'
    where c.contype = 'f'
  loop
    execute format('alter table %s add unique (id, farm_id)', r.parent);
  end loop;
  for r in
    select c.conname, c.conrelid::regclass::text as child, a.attname::text as col,
      c.confrelid::regclass::text as parent
    from pg_catalog.pg_constraint c
    join pg_catalog.pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
    join public.sync_tables p on c.confrelid = format('public.%I', p.name)::regclass and p.farm_column = 'farm_id'
    join public.sync_tables ch on c.conrelid = format('public.%I', ch.name)::regclass and ch.farm_column = 'farm_id'
    where c.contype = 'f' and cardinality(c.conkey) = 1
  loop
    execute format('alter table %s drop constraint %I', r.child, r.conname);
    execute format('alter table %s add constraint %I foreign key (%I, farm_id) references %s (id, farm_id) '
      'deferrable initially deferred', r.child, r.conname, r.col, r.parent);
  end loop;
end $$;

-- ---------- privileges ----------
-- The app always signs in, so anon gets nothing. TRUNCATE ignores row-level security, and
-- clients never hard-delete, so neither right is granted to signed-in users.
revoke all on all tables in schema public from anon;
revoke truncate, delete, references, trigger on all tables in schema public from authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke execute on all functions in schema public from public, anon;
-- Members see each other's names, never phone numbers.
revoke select on public.profiles from authenticated;
grant select (id, full_name, language, large_text, created_at, updated_at) on public.profiles to authenticated;
-- Supabase's default privileges would grant every future table, sequence and function to
-- anon and every right to authenticated; later migrations start from these rules instead.
alter default privileges in schema public revoke all on tables from anon;
alter default privileges in schema public revoke truncate, delete, references, trigger on tables from authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke execute on functions from anon;
-- PUBLIC's right to run new functions is a global default, not a per-schema one
alter default privileges revoke execute on functions from public;
grant execute on function public.create_farm(uuid, uuid, text, text, jsonb, timestamptz),
  public.my_invites(), public.accept_invite(uuid), public.decline_invite(uuid),
  public.my_farms(text, integer), public.my_owned_farms(),
  public.my_entities(integer), public.my_co_members(), public.access_level(text, jsonb, text)
  to authenticated;
