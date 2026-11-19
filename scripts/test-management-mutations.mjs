import assert from 'node:assert/strict';
import fs from 'node:fs';

const sql = fs.readFileSync('supabase/migrations/055_management_mutations_rbac.sql', 'utf8');
const admin = fs.readFileSync('apps/mobile/app/admin.tsx', 'utf8');
const settings = fs.readFileSync('apps/mobile/app/settings.tsx', 'utf8');
const designer = fs.readFileSync('apps/mobile/components/ReportDesigner.tsx', 'utf8');

assert.match(sql, /role_code in \('owner', 'admin_followup'\)/);
for (const fn of ['admin_update_task', 'admin_delete_task', 'admin_update_branch', 'admin_delete_branch', 'admin_delete_report', 'admin_delete_employee_record']) assert.match(sql, new RegExp(`create or replace function public\\.${fn}`));
assert.match(admin, /deleteManagedTask/);
assert.match(admin, /deleteManagedReport/);
assert.match(admin, /deleteManagedBranch/);
assert.match(settings, /admin_delete_employee_record/);
assert.match(settings, /حذف حساب الموظف نهائيًا/);
assert.match(designer, /deleteManagedReportTemplate/);
assert.match(designer, /حذف قالب التقرير نهائيًا/);
console.log('Management mutation RBAC checks passed.');
