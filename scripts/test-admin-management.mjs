import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
const migration = read('supabase/migrations/036_admin_management_atomicity.sql');
const brandingMigration = read('supabase/migrations/043_institution_branding_owner_permission.sql');
const archiveMigration = read('supabase/migrations/044_allow_employee_archive_audit.sql');
const branding = read('apps/mobile/lib/organizationBranding.ts');
const auth = read('supabase/functions/employee-code-auth/index.ts');
const settings = read('apps/mobile/app/settings.tsx');
const admin = read('apps/mobile/app/admin.tsx');
const data = read('apps/mobile/lib/adminData.ts');

assert.match(migration, /admin_update_employee/);
assert.match(migration, /admin_manage_branch/);
assert.match(migration, /for update/);
assert.match(migration, /set is_active=false/);
assert.match(migration, /branches\.manage/);
assert.match(migration, /revoke all on function public\.admin_update_employee[\s\S]*from public, anon, authenticated/);
assert.match(migration, /grant execute on function public\.admin_manage_branch[\s\S]*to service_role/);
assert.match(auth, /admin_update_employee/);
assert.match(auth, /admin_manage_branch/);
assert.match(auth, /employeeId === owner.id/);
assert.match(auth, /owner_self_protection/);
assert.match(auth, /'activate'/);
assert.match(auth, /roleCode: assignment\?\.role_code/);
assert.match(settings, /roleCode: employee\.roleCode \?\? 'warehouse_worker'/);
assert.match(settings, /branches\.map\(\(branch\)/);
assert.doesNotMatch(settings, /placeholder="معرّف الفرع"/);
assert.match(admin, /branchAction: action/);
assert.match(admin, /أرشفة الفرع/);
assert.match(admin, /إعادة تفعيل الفرع/);
assert.match(data, /id: row\.id,[\s\S]*name: row\.display_name/);
assert.doesNotMatch(data, /id: row\.user_id/);
assert.match(brandingMigration, /alter table public\.organizations[\s\S]*settings jsonb/i);
assert.match(brandingMigration, /role_permissions \(role_code, permission_code\)/);
assert.match(brandingMigration, /organizations\.update/);
assert.match(brandingMigration, /alshaari_private\.has_permission/);
assert.match(brandingMigration, /grant update \(name, settings\) on public\.organizations to authenticated/i);
assert.match(brandingMigration, /revoke execute on function public\.guard_multi_form_task_completion\(\) from public, anon, authenticated/i);
assert.match(brandingMigration, /revoke execute on function public\.guard_report_signature_mutation\(\) from public, anon, authenticated/i);
assert.match(brandingMigration, /revoke execute on function public\.guard_task_report_snapshot_and_signature\(\) from public, anon, authenticated/i);
assert.match(brandingMigration, /revoke execute on function public\.report_designer_allowed\(uuid\) from public, anon, authenticated/i);
assert.match(brandingMigration, /alter function public\.prevent_task_activity_mutation\(\) set search_path = pg_catalog, public/i);
assert.match(brandingMigration, /drop policy if exists tasks_read on public\.tasks/i);
assert.match(brandingMigration, /or a\.role_code = 'admin_followup'/i);

assert.match(branding, /from\('organizations'\)/);
assert.match(branding, /settingsAvailable: false/);
assert.match(admin, /loadOrganizationBranding/);
assert.doesNotMatch(admin, /from\('institutions'\)/);
assert.match(settings, /loadOrganizationBranding/);
assert.match(settings, /saveOrganizationBranding/);
assert.doesNotMatch(settings, /from\('institutions'\)/);


assert.match(migration, /case when p_is_active then 'updated' else 'archived' end/);
assert.match(archiveMigration, /drop constraint if exists employee_access_audit_log_action_check/i);
assert.match(archiveMigration, /'archived'/i);
assert.match(archiveMigration, /add constraint employee_access_audit_log_action_check/i);

console.log('Admin management static checks passed.');

// Dashboard layout regression checks: KPI cards remain readable on phones,
// the fixed navigation does not cover the final content, and the app is RTL.
assert.match(admin, /metrics: \{[^}]*flexDirection: 'row-reverse'[^}]*justifyContent: 'space-between'/);
assert.match(admin, /metric: \{[^}]*width: '48%'[^}]*minHeight: 112/);
assert.match(admin, /content: \{[^}]*paddingBottom: 124/);
assert.match(admin, /moduleGrid: \{[^}]*flexDirection:'row-reverse'/);
assert.match(admin, /bottomBar: \{[^}]*flexDirection:'row-reverse'/);
const layout = read('apps/mobile/app/_layout.tsx');
assert.match(layout, /I18nManager\.allowRTL\(true\)/);
assert.match(layout, /I18nManager\.forceRTL\(true\)/);
assert.match(layout, /direction: 'rtl'/);
const tasksScreen = read('apps/mobile/app/tasks.tsx');
assert.match(admin, /async function signOut\(\)/);
assert.match(admin, /تسجيل الخروج وتبديل الحساب/);
assert.match(admin, /supabase\.auth\.signOut\(\)/);
assert.match(tasksScreen, /async function signOut\(\)/);
assert.match(tasksScreen, /تسجيل الخروج وتبديل الحساب/);
assert.match(tasksScreen, /supabase\.auth\.signOut\(\)/);



// Suspended accounts may retain an unexpired JWT; task-owned RLS paths
// must also require an active organization membership.
const suspendedAccess = read('supabase/migrations/045_revoke_suspended_employee_task_access.sql');
assert.match(suspendedAccess, /tasks_select_assigned_or_manager[\s\S]*organization_memberships[\s\S]*m\.is_active/i);
assert.match(suspendedAccess, /task_activity_log_read[\s\S]*m\.is_active/i);
assert.match(suspendedAccess, /task_attachments_insert_uploader_on_visible_task[\s\S]*m\.is_active/i);
assert.match(suspendedAccess, /task_attachments_read_assigned_or_manager[\s\S]*m\.is_active/i);
assert.match(suspendedAccess, /task_execution_steps_read[\s\S]*m\.is_active/i);
assert.match(suspendedAccess, /task_report_drafts_insert[\s\S]*m\.is_active/i);
assert.match(suspendedAccess, /task_report_drafts_select[\s\S]*m\.is_active/i);
assert.match(suspendedAccess, /task_report_drafts_update[\s\S]*m\.is_active/i);


// The owner role is organization-wide and must never be assigned a branch.
const ownerScopeMigration = read('supabase/migrations/046_preserve_owner_organization_scope.sql');
assert.match(ownerScopeMigration, /p_role_code\s*=\s*'owner'[\s\S]*branch_id\s*=\s*case when p_role_code\s*=\s*'owner' then null/i);
assert.match(auth, /p_branch_id: roleCode === 'owner' \? null : branchId/);
assert.match(auth, /branch_id: roleCode === 'owner' \? null : branchId/);
assert.match(settings, /branchId: employee\.roleCode === 'owner' \? ''/);
assert.match(settings, /createForm\.roleCode === 'owner' \? null : createForm\.branchId/);
assert.match(settings, /draft\.roleCode === 'owner' \? null : draft\.branchId/);
