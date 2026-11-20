import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const sql = readFileSync('supabase/migrations/072_task_evaluation_fields.sql', 'utf8');
assert(sql.includes('add column if not exists delay_reason text'), 'delay_reason column is added');
assert(sql.includes('add column if not exists result_flag text'), 'result_flag column is added');
assert(sql.includes('tasks_delay_reason_length_check') && sql.includes('tasks_result_flag_length_check'), 'input length constraints exist');
assert(sql.includes("nullif(trim(t.delay_reason), '') is null") && sql.includes("nullif(trim(t.delay_reason), '') is not null"), 'justified and unjustified delays are separated');
assert(sql.includes("t.result_flag in ('عجز', 'شكوى مصعدة')"), 'special result flags reduce earned score');
assert(sql.includes("when t.status = 'late' and nullif(trim(t.delay_reason), '') is not null then 0.7"), 'justified late tasks receive the configured partial score');
assert(sql.includes('security_invoker = true') && sql.includes('grant select on public.employee_performance_analytics to authenticated'), 'analytics view remains protected');
console.log(JSON.stringify({ ok: true, checks: 7, scope: 'task-evaluation-fields' }));
