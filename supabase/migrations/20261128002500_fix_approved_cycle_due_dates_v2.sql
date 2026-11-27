begin;

create or replace function public.set_approved_cycle_issue_schedule()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_cycle_id uuid;
  v_issue_date date;
  v_cycle public.approved_task_cycles%rowtype;
  v_source public.tasks%rowtype;
  v_org public.organizations%rowtype;
  v_local_due timestamp;
  v_due_at timestamptz;
begin
  if coalesce(new.idempotency_key, '') not like 'approved-cycle:%:%' then return new; end if;
  begin
    v_cycle_id := split_part(new.idempotency_key, ':', 2)::uuid;
    v_issue_date := split_part(new.idempotency_key, ':', 3)::date;
  exception when others then return new;
  end;
  select * into v_cycle from public.approved_task_cycles where id = v_cycle_id;
  if not found then return new; end if;
  select * into v_source from public.tasks where id = v_cycle.source_task_id;
  select * into v_org from public.organizations where id = v_cycle.organization_id;
  v_local_due := timezone(coalesce(nullif(v_org.timezone, ''), 'Asia/Aden'), coalesce(v_source.due_at, now()));
  v_due_at := make_timestamptz(
    extract(year from v_issue_date)::integer,
    extract(month from v_issue_date)::integer,
    extract(day from v_issue_date)::integer,
    extract(hour from v_local_due)::integer,
    extract(minute from v_local_due)::integer,
    extract(second from v_local_due)::double precision,
    coalesce(nullif(v_org.timezone, ''), 'Asia/Aden')
  );
  new.due_at := v_due_at;
  new.starts_at := v_due_at;
  return new;
end;
$$;

drop trigger if exists set_approved_cycle_issue_schedule on public.tasks;
create trigger set_approved_cycle_issue_schedule before insert on public.tasks for each row execute function public.set_approved_cycle_issue_schedule();

alter table public.tasks disable trigger trg_guard_task_executor_update;
update public.tasks t
set due_at = make_timestamptz(
      extract(year from i.issue_date)::integer,
      extract(month from i.issue_date)::integer,
      extract(day from i.issue_date)::integer,
      extract(hour from timezone(coalesce(nullif(o.timezone, ''), 'Asia/Aden'), coalesce(source.due_at, now())))::integer,
      extract(minute from timezone(coalesce(nullif(o.timezone, ''), 'Asia/Aden'), coalesce(source.due_at, now())))::integer,
      extract(second from timezone(coalesce(nullif(o.timezone, ''), 'Asia/Aden'), coalesce(source.due_at, now())))::double precision,
      coalesce(nullif(o.timezone, ''), 'Asia/Aden')
    ),
    starts_at = make_timestamptz(
      extract(year from i.issue_date)::integer,
      extract(month from i.issue_date)::integer,
      extract(day from i.issue_date)::integer,
      extract(hour from timezone(coalesce(nullif(o.timezone, ''), 'Asia/Aden'), coalesce(source.due_at, now())))::integer,
      extract(minute from timezone(coalesce(nullif(o.timezone, ''), 'Asia/Aden'), coalesce(source.due_at, now())))::integer,
      extract(second from timezone(coalesce(nullif(o.timezone, ''), 'Asia/Aden'), coalesce(source.due_at, now())))::double precision,
      coalesce(nullif(o.timezone, ''), 'Asia/Aden')
    ),
    updated_at = now()
from public.approved_task_cycle_issues i
join public.approved_task_cycles c on c.id = i.cycle_id
join public.tasks source on source.id = c.source_task_id
join public.organizations o on o.id = c.organization_id
where t.id = i.issued_task_id and t.idempotency_key like 'approved-cycle:%:%';
alter table public.tasks enable trigger trg_guard_task_executor_update;

commit;
