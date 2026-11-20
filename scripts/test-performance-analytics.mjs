import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const sql = readFileSync('supabase/migrations/071_employee_performance_analytics.sql', 'utf8');
assert(sql.includes('public.tasks') && sql.includes('assigned_to') && sql.includes('position_code') && sql.includes('branch_id'), 'analytics uses production task columns');
assert(sql.includes("t.status = 'completed_approved'") && sql.includes("t.status = 'late'"), 'analytics uses production task statuses');
assert(sql.includes("when 'critical' then 3.0") && sql.includes("when 'urgent' then 2.0") && sql.includes("when 'important' then 1.5"), 'priority weights are defined');
assert(sql.includes('earned_score / ts.max_possible_score'), 'score is normalized against weighted maximum');
assert(sql.includes('public.task_reports') && sql.includes("tr.status = 'approved'"), 'submitted and approved reports are counted');
assert(sql.includes('security_invoker = true') && sql.includes('grant select on public.employee_performance_analytics to authenticated'), 'view access follows RLS and authenticated access');
assert(!sql.includes('employee_daily_tasks') && !sql.includes('org_roles') && !sql.includes('org_branches'), 'legacy incompatible table names are not used');
console.log(JSON.stringify({ ok: true, checks: 7, scope: 'employee-performance-analytics' }));
