import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
const migration = read('supabase/migrations/081_task_cost_permissions.sql');
const taskCostsMigration = read('supabase/migrations/080_task_costs.sql');
const admin = read('apps/mobile/app/admin.tsx');
const adminData = read('apps/mobile/lib/adminData.ts');
const dashboardData = adminData;
const designer = read('apps/mobile/components/OrganizationalTaskDesigner.tsx');

for (const permission of ['task_costs.read', 'task_costs.propose', 'task_costs.approve']) {
  assert(migration.includes(permission), `missing ${permission} permission`);
}
assert.match(migration, /\('owner', 'task_costs\.approve'\)/);
assert.match(migration, /\('admin_followup', 'task_costs\.propose'\)/);
assert.match(migration, /\('admin_followup', 'task_costs\.read'\)/);
assert.match(migration, /\('accountant', 'task_costs\.read'\)/);
assert.match(migration, /task_costs_approve_scoped[\s\S]*task_costs\.approve/);
assert.doesNotMatch(migration, /task_costs_approve_scoped[\s\S]{0,400}tasks\.manage/);
assert.match(migration, /task_costs_read_scoped[\s\S]*task_costs\.read/);
assert.match(migration, /create or replace function public\.propose_task_cost[\s\S]*task_costs\.propose/);
assert.match(migration, /estimated_amount = excluded\.estimated_amount/);
assert.match(migration, /proposed_by = excluded\.proposed_by/);
assert.doesNotMatch(migration, /set estimated_amount = excluded\.estimated_amount,[\s\S]{0,180}budget_amount\s*=/i);
assert.doesNotMatch(migration, /set estimated_amount = excluded\.estimated_amount,[\s\S]{0,180}spent_amount\s*=/i);
assert.match(migration, /revoke all on function public\.propose_task_cost[\s\S]*from public, anon, authenticated/i);
assert.match(migration, /grant execute on function public\.propose_task_cost[\s\S]*to authenticated/i);
assert.match(taskCostsMigration, /tasks\.manage/);

assert.match(admin, /const canManageTasks = permissions\.includes\('tasks\.manage'\)/);
assert.match(admin, /canReadCosts=\{canReadTaskCosts\}/);
assert.match(admin, /canProposeCosts=\{canProposeTaskCosts\}/);
assert.match(admin, /canApproveCosts=\{canApproveTaskCosts\}/);
assert.match(admin, /canReadCosts && <Text style=\{styles\.taskListCost\}/);
assert.match(admin, /canManage=\{canManageTasks\}/);
assert.doesNotMatch(admin, /canManage=\{canManageEmployees\}/);

assert.match(adminData, /task_costs\.approve/);
assert.match(adminData, /approved_by: authData\.user\.id/);
assert.match(adminData, /rpc\('propose_task_cost'/);
assert.match(adminData, /task_costs\.propose/);
assert.match(adminData, /task_cost_permission_denied/);
assert.match(adminData, /export async function approveAdministrativeTaskCost/);
assert.match(adminData, /task_cost_approval_permission_denied/);
assert.match(adminData, /approved_at: approvedAt/);
assert.match(adminData, /proposed_at,approved_at/);
assert.match(admin, /onTaskCostApproved=\{approveTaskCost\}/);
assert.match(admin, /اعتماد الميزانية والمصروفات/);
assert.match(admin, /يوجد مقترح تكلفة بانتظار اعتماد صاحب المؤسسة/);
assert.match(admin, /costApprovedAt: result\.approvedAt/);
assert.match(dashboardData, /const dashboardCache = new Map<string, \{ value: DashboardData; loadedAt: number \}>\(\)/);
assert.match(dashboardData, /const dashboardRequests = new Map<string, Promise<DashboardData>>\(\)/);
assert.ok(dashboardData.includes('const cacheKey = `${authData.user.id}:${organizationId}`;'));
assert.match(dashboardData, /dashboardCache\.get\(cacheKey\)/);
assert.match(dashboardData, /dashboardRequests\.get\(cacheKey\)/);

assert.match(designer, /canProposeCosts\?: boolean; canApproveCosts\?: boolean/);
assert.match(designer, /canApproveCosts \? <View style=\{styles\.threeColumns\}/);
assert.match(designer, /التكلفة التقديرية المقترحة/);
assert.match(designer, /ريال يمني/);
assert.doesNotMatch(designer, /ر\.س/);
console.log('Task cost permission regression checks passed.');
