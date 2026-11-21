begin;

-- Keep task administration separate from financial authority.
insert into public.permissions (code, name_ar)
values
  ('task_costs.read', 'عرض تكاليف المهام'),
  ('task_costs.propose', 'اقتراح تكلفة المهمة'),
  ('task_costs.approve', 'اعتماد ميزانية ومصروفات المهمة')
on conflict (code) do update
set name_ar = excluded.name_ar;

-- The owner has final cost authority. The executive manager may view and
-- propose estimates only. Accountants may view cost figures, not approve them.
insert into public.role_permissions (role_code, permission_code)
values
  ('owner', 'task_costs.read'),
  ('owner', 'task_costs.approve'),
  ('admin_followup', 'task_costs.read'),
  ('admin_followup', 'task_costs.propose'),
  ('accountant', 'task_costs.read')
on conflict (role_code, permission_code) do nothing;

alter table public.task_costs
  add column if not exists proposed_by uuid references auth.users(id),
  add column if not exists proposed_at timestamptz,
  add column if not exists approved_by uuid references auth.users(id),
  add column if not exists approved_at timestamptz;

-- Replace the old task-management permission that accidentally granted
-- full write access to the financial cost row.
drop policy if exists task_costs_manage_scoped on public.task_costs;
drop policy if exists task_costs_read_scoped on public.task_costs;

create policy task_costs_read_scoped
on public.task_costs
for select
to authenticated
using (
  exists (
    select 1
    from public.tasks t
    where t.id = task_costs.task_id
      and t.organization_id = task_costs.organization_id
      and alshaari_private.has_permission(
        t.organization_id,
        'task_costs.read',
        t.branch_id
      )
  )
);

create policy task_costs_approve_scoped
on public.task_costs
for all
to authenticated
using (
  alshaari_private.has_permission(
    organization_id,
    'task_costs.approve',
    null::uuid
  )
)
with check (
  alshaari_private.has_permission(
    organization_id,
    'task_costs.approve',
    null::uuid
  )
);

-- Executive follow-up can submit or revise the estimate only. It cannot
-- alter the approved budget, actual spend, or approval metadata.
create or replace function public.propose_task_cost(
  p_organization_id uuid,
  p_task_id uuid,
  p_estimated_amount numeric,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user uuid := auth.uid();
  v_branch_id uuid;
  v_cost_id uuid;
  v_proposed_at timestamptz := pg_catalog.now();
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  if p_estimated_amount is null or p_estimated_amount < 0 then
    raise exception using errcode = '22023', message = 'invalid_estimated_amount';
  end if;

  select t.branch_id
    into v_branch_id
  from public.tasks t
  where t.id = p_task_id
    and t.organization_id = p_organization_id
    and t.deleted_at is null;

  if not found then
    raise exception using errcode = 'P0002', message = 'task_not_found';
  end if;

  if not alshaari_private.has_permission(
    p_organization_id,
    'task_costs.propose',
    v_branch_id
  ) then
    raise exception using errcode = '42501', message = 'task_cost_proposal_permission_denied';
  end if;

  insert into public.task_costs (
    organization_id,
    task_id,
    budget_amount,
    estimated_amount,
    spent_amount,
    notes,
    proposed_by,
    proposed_at
  )
  values (
    p_organization_id,
    p_task_id,
    0,
    p_estimated_amount,
    0,
    nullif(pg_catalog.btrim(coalesce(p_notes, '')), ''),
    v_user,
    v_proposed_at
  )
  on conflict (task_id) do update
  set estimated_amount = excluded.estimated_amount,
      notes = excluded.notes,
      proposed_by = excluded.proposed_by,
      proposed_at = excluded.proposed_at,
      updated_at = v_proposed_at
  where public.task_costs.organization_id = p_organization_id
  returning id into v_cost_id;

  if v_cost_id is null then
    raise exception using errcode = '23505', message = 'task_cost_organization_mismatch';
  end if;

  return pg_catalog.jsonb_build_object(
    'ok', true,
    'task_id', p_task_id,
    'cost_id', v_cost_id,
    'proposed_at', v_proposed_at
  );
end;
$function$;

revoke all on function public.propose_task_cost(uuid, uuid, numeric, text)
from public, anon, authenticated;
grant execute on function public.propose_task_cost(uuid, uuid, numeric, text)
to authenticated;

-- Trigger-only helper: do not expose direct execution to API roles.
create or replace function public.set_task_cost_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog
as $function$
begin
  new.updated_at = pg_catalog.now();
  return new;
end;
$function$;

revoke all on function public.set_task_cost_updated_at()
from public, anon, authenticated;

commit;