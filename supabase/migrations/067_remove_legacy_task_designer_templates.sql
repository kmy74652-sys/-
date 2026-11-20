-- The legacy task designer is retired. Organizational schedules use the
-- dedicated subcategory and are never removed by this cleanup.
with candidates as (
  select t.id
  from public.task_templates t
  left join public.task_categories sc on sc.id = t.subcategory_id
  where coalesce(sc.title, '') <> 'الدوام والمهام اليومية'
    and not exists (select 1 from public.tasks x where x.template_id = t.id)
    and not exists (select 1 from public.task_template_assignments a where a.template_id = t.id)
  limit 100
)
delete from public.task_templates t
using candidates c
where t.id = c.id;

with candidates as (
  select t.id
  from public.task_templates t
  left join public.task_categories sc on sc.id = t.subcategory_id
  where coalesce(sc.title, '') <> 'الدوام والمهام اليومية'
    and exists (select 1 from public.tasks x where x.template_id = t.id)
  limit 100
)
update public.task_templates t
set is_active = false, updated_at = now()
from candidates c
where t.id = c.id;
