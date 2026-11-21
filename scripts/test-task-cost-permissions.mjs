import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
const admin = read('apps/mobile/app/admin.tsx');
const adminData = read('apps/mobile/lib/adminData.ts');
const designer = read('apps/mobile/components/OrganizationalTaskDesigner.tsx');
const taskUi = admin + adminData + designer;
for (const forbidden of ['TaskCostDraft','approveAdministrativeTaskCost','task_costs.read','task_costs.propose','task_costs.approve','budgetAmount','estimatedAmount','spentAmount','costNotes','بيانات التكلفة','اعتماد تكلفة المهمة']) {
  assert.equal(taskUi.includes(forbidden), false, `task management must not include ${forbidden}`);
}
assert.match(adminData, /export type AdminTask = \{/);
assert.match(adminData, /export async function createAdministrativeTask/);
assert.match(designer, /onSend\\?: \\(draft: TaskTemplateDraft, branchId: string \\| null, dueAt: string, idempotencyKey: string\\)/);
console.log('Task cost separation checks passed.');
