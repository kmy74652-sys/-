import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
const migration = read('supabase/migrations/036_admin_management_atomicity.sql');
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

console.log('Admin management static checks passed.');
