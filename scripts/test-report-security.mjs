import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync('supabase/migrations/062_enable_task_report_drafts_rls.sql', 'utf8');
const policies = fs.readFileSync('supabase/migrations/051_staging_task_designer_rpcs.sql', 'utf8');
const storage = fs.readFileSync('supabase/migrations/052_staging_task_rls_storage.sql', 'utf8');

assert.match(migration, /alter table public\.task_report_drafts enable row level security/i);
assert.match(policies, /create policy task_report_drafts_select/i);
assert.match(policies, /employee_id=auth\.uid\(\)/i);
assert.match(policies, /task_report_drafts_insert[\s\S]*task\.assigned_to=auth\.uid\(\)/i);
assert.match(storage, /task_report_drafts/);
assert.match(storage, /revoke insert,update,delete[\s\S]*task_report_drafts/i);

console.log(JSON.stringify({ ok: true, checks: 6, reportDraftRls: true, rpcOnlyWrites: true }));
