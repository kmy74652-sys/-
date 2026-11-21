begin;

create table if not exists public.task_costs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  task_id uuid not null unique references public.tasks(id) on delete cascade,
  budget_amount numeric(18,2) not null default 0 check (budget_amount >= 0),
  estimated_amount numeric(18,2) not null default 0 check (estimated_amount >= 0),
  spent_amount numeric(18,2) not null default 0 check (spent_amount >= 0),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists task_costs_organization_idx on public.task_costs (organization_id, updated_at desc);

alter table public.task_costs enable row level security;

drop policy if exists task_costs_read_scoped on public.task_costs;
create policy task_costs_read_scoped on public.task_costs for select to authenticated using (
  exists (
    select 1 from public.tasks t
    where t.id = task_id
      and (t.assigned_to = auth.uid() or t.created_by = auth.uid() or alshaari_private.has_permission(t.organization_id, 'tasks.read_all', null::uuid))
  )
);

drop policy if exists task_costs_manage_scoped on public.task_costs;
create policy task_costs_manage_scoped on public.task_costs for all to authenticated using (
  alshaari_private.has_permission(organization_id, 'tasks.manage', null::uuid)
) with check (
  alshaari_private.has_permission(organization_id, 'tasks.manage', null::uuid)
);

grant select on public.task_costs to authenticated;
grant insert, update on public.task_costs to authenticated;

create or replace function public.set_task_cost_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists task_costs_set_updated_at on public.task_costs;
create trigger task_costs_set_updated_at before update on public.task_costs
for each row execute function public.set_task_cost_updated_at();

commit;
