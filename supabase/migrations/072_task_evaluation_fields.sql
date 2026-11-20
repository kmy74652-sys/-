begin;

alter table public.tasks
  add column if not exists delay_reason text,
  add column if not exists result_flag text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'tasks_delay_reason_length_check') then
    alter table public.tasks add constraint tasks_delay_reason_length_check
      check (delay_reason is null or length(trim(delay_reason)) between 2 and 1000);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'tasks_result_flag_length_check') then
    alter table public.tasks add constraint tasks_result_flag_length_check
      check (result_flag is null or length(trim(result_flag)) between 1 and 120);
  end if;
end;
$$;

create index if not exists tasks_evaluation_status_idx
  on public.tasks (organization_id, assigned_to, status, priority)
  where deleted_at is null;

create or replace view public.employee_performance_analytics
with (security_invoker = true)
as
with task_stats as (
  select
    t.organization_id,
    t.assigned_to as employee_id,
    t.position_code as role_code,
    t.branch_id,
    count(*)::integer as total_tasks,
    count(*) filter (where t.status = 'completed_approved')::integer as completed_tasks,
    count(*) filter (where t.status = 'completed_approved')::integer as verified_tasks,
    count(*) filter (where t.status = 'late')::integer as delayed_tasks,
    count(*) filter (where t.status = 'late' and nullif(trim(t.delay_reason), '') is null)::integer as unexcused_delayed_tasks,
    count(*) filter (where t.status = 'late' and nullif(trim(t.delay_reason), '') is not null)::integer as excused_delayed_tasks,
    count(*) filter (where t.priority = 'critical')::integer as critical_tasks,
    count(*) filter (where t.priority = 'urgent')::integer as urgent_tasks,
    count(*) filter (where t.priority = 'important')::integer as important_tasks,
    count(*) filter (where t.priority = 'normal')::integer as normal_tasks,
    count(*) filter (where t.priority in ('critical', 'urgent'))::integer as high_priority_tasks,
    coalesce(sum(
      case t.priority
        when 'critical' then 3.0
        when 'urgent' then 2.0
        when 'important' then 1.5
        else 1.0
      end
      * case
          when t.result_flag in ('عجز', 'شكوى مصعدة') then 0.5
          else 1.0
        end
      * case
          when t.status = 'completed_approved' then 1.0
          when t.status = 'late' and nullif(trim(t.delay_reason), '') is not null then 0.7
          else 0.0
        end
    ), 0)::numeric as earned_score,
    coalesce(sum(
      case t.priority
        when 'critical' then 3.0
        when 'urgent' then 2.0
        when 'important' then 1.5
        else 1.0
      end
    ), 0)::numeric as max_possible_score
  from public.tasks t
  where t.deleted_at is null
    and t.assigned_to is not null
  group by t.organization_id, t.assigned_to, t.position_code, t.branch_id
), report_stats as (
  select
    t.organization_id,
    t.assigned_to as employee_id,
    count(tr.id)::integer as reports_submitted,
    count(tr.id) filter (where tr.status = 'approved')::integer as reports_approved
  from public.tasks t
  join public.task_reports tr on tr.task_id = t.id
  where t.deleted_at is null
    and t.assigned_to is not null
  group by t.organization_id, t.assigned_to
)
select
  ts.organization_id,
  ts.employee_id,
  m.display_name as employee_name,
  ts.role_code,
  coalesce(r.name_ar, ts.role_code, 'غير محدد') as role_title,
  ts.branch_id,
  coalesce(b.name, 'كل الفروع') as branch_name,
  ts.total_tasks,
  ts.completed_tasks,
  ts.verified_tasks,
  ts.delayed_tasks,
  ts.unexcused_delayed_tasks,
  ts.excused_delayed_tasks,
  ts.critical_tasks,
  ts.urgent_tasks,
  ts.important_tasks,
  ts.normal_tasks,
  ts.high_priority_tasks,
  coalesce(rs.reports_submitted, 0) as reports_submitted,
  coalesce(rs.reports_approved, 0) as reports_approved,
  round(case when ts.max_possible_score > 0 then (ts.earned_score / ts.max_possible_score) * 100 else 0 end, 1) as weighted_score_pct,
  case
    when ts.max_possible_score > 0 and (ts.earned_score / ts.max_possible_score) * 100 >= 90 then 'ممتاز (مرشح لحافز)'
    when ts.max_possible_score > 0 and (ts.earned_score / ts.max_possible_score) * 100 >= 80 then 'جيد جداً'
    when ts.max_possible_score > 0 and (ts.earned_score / ts.max_possible_score) * 100 >= 70 then 'جيد'
    else 'يحتاج متابعة وتدريب'
  end as evaluation_grade
from task_stats ts
left join public.organization_memberships m
  on m.organization_id = ts.organization_id
 and m.user_id = ts.employee_id
 and m.is_active
left join public.roles r on r.code = ts.role_code
left join public.branches b
  on b.organization_id = ts.organization_id
 and b.id = ts.branch_id
left join report_stats rs
  on rs.organization_id = ts.organization_id
 and rs.employee_id = ts.employee_id;

grant select on public.employee_performance_analytics to authenticated;

commit;
