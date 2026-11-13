create or replace function app.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.institutions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[a-z0-9][a-z0-9_-]{1,31}$'),
  name text not null check (length(trim(name)) >= 2),
  timezone text not null,
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  settings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.branches (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id),
  code text not null,
  name text not null check (length(trim(name)) >= 2),
  address text,
  phone text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (institution_id, code),
  unique (institution_id, id)
);

create table if not exists public.employees (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id),
  auth_user_id uuid unique references auth.users(id) on delete set null,
  employee_no text not null,
  full_name text not null check (length(trim(full_name)) >= 2),
  email citext,
  phone text,
  base_branch_id uuid,
  status public.employee_status not null default 'active',
  last_login_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (institution_id, employee_no),
  unique (institution_id, id),
  foreign key (institution_id, base_branch_id) references public.branches(institution_id, id)
);

create table if not exists public.employee_branches (
  institution_id uuid not null references public.institutions(id),
  employee_id uuid not null,
  branch_id uuid not null,
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (institution_id, employee_id, branch_id),
  foreign key (institution_id, employee_id) references public.employees(institution_id, id) on delete cascade,
  foreign key (institution_id, branch_id) references public.branches(institution_id, id) on delete cascade
);

create unique index if not exists employee_one_default_branch
  on public.employee_branches (institution_id, employee_id)
  where is_default;

create table if not exists public.roles (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id),
  code text not null,
  name_ar text not null,
  description text,
  is_system boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (institution_id, code),
  unique (institution_id, id)
);

create table if not exists public.permissions (
  code text primary key,
  name_ar text not null,
  domain text not null,
  action text not null,
  description text,
  created_at timestamptz not null default now()
);

create table if not exists public.role_permissions (
  institution_id uuid not null references public.institutions(id) on delete cascade,
  role_id uuid not null,
  permission_code text not null references public.permissions(code),
  created_at timestamptz not null default now(),
  primary key (institution_id, role_id, permission_code),
  foreign key (institution_id, role_id) references public.roles(institution_id, id) on delete cascade
);

create table if not exists public.employee_roles (
  institution_id uuid not null references public.institutions(id) on delete cascade,
  employee_id uuid not null,
  role_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (institution_id, employee_id, role_id),
  foreign key (institution_id, employee_id) references public.employees(institution_id, id) on delete cascade,
  foreign key (institution_id, role_id) references public.roles(institution_id, id) on delete cascade
);

create table if not exists public.employee_permission_overrides (
  institution_id uuid not null references public.institutions(id) on delete cascade,
  employee_id uuid not null,
  permission_code text not null references public.permissions(code),
  allowed boolean not null,
  reason text not null check (length(trim(reason)) >= 3),
  created_by uuid,
  created_at timestamptz not null default now(),
  primary key (institution_id, employee_id, permission_code),
  foreign key (institution_id, employee_id) references public.employees(institution_id, id) on delete cascade,
  foreign key (institution_id, created_by) references public.employees(institution_id, id)
);

create trigger institutions_set_updated_at before update on public.institutions
for each row execute function app.set_updated_at();
create trigger branches_set_updated_at before update on public.branches
for each row execute function app.set_updated_at();
create trigger employees_set_updated_at before update on public.employees
for each row execute function app.set_updated_at();
create trigger roles_set_updated_at before update on public.roles
for each row execute function app.set_updated_at();
