import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const sql = readFileSync('supabase/migrations/071_employee_performance_analytics.sql', 'utf8');
const analytics = readFileSync('apps/mobile/lib/performanceAnalytics.ts', 'utf8');
const component = readFileSync('apps/mobile/components/PerformanceAnalytics.tsx', 'utf8');
assert(sql.includes('public.tasks') && sql.includes('assigned_to') && sql.includes('position_code') && sql.includes('branch_id'), 'analytics uses production task columns');
assert(sql.includes("t.status = 'completed_approved'") && sql.includes("t.status = 'late'"), 'analytics uses production task statuses');
assert(sql.includes("when 'critical' then 3.0") && sql.includes("when 'urgent' then 2.0") && sql.includes("when 'important' then 1.5"), 'priority weights are defined');
assert(sql.includes('earned_score / ts.max_possible_score'), 'score is normalized against weighted maximum');
assert(sql.includes('public.task_reports') && sql.includes("tr.status = 'approved'"), 'submitted and approved reports are counted');
assert(sql.includes('security_invoker = true') && sql.includes('grant select on public.employee_performance_analytics to authenticated'), 'view access follows RLS and authenticated access');
assert(!sql.includes('employee_daily_tasks') && !sql.includes('org_roles') && !sql.includes('org_branches'), 'legacy incompatible table names are not used');
assert(analytics.includes('assigned_at,received_at,opened_at') && analytics.includes('receivedTotalMs') && analytics.includes('openedTotalMs'), 'delivery timing reads production task timestamps');
assert(analytics.includes(".is('deleted_at', null)") && analytics.includes('received >= assigned') && analytics.includes('opened >= received'), 'delivery timing excludes deleted and invalid intervals');
assert(component.includes('زمن الاستلام والفتح') && component.includes('متوسط الاستلام') && component.includes('متوسط الفتح'), 'delivery timing report is visible in the performance dashboard');
console.log(JSON.stringify({ ok: true, checks: 10, scope: 'employee-performance-analytics-and-delivery-timing' }));
