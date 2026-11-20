import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import ts from 'typescript';
const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
function compile(path, dependencies = {}) {
  const output = ts.transpileModule(read(path), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;
  const exports = {};
  new Function('exports', 'require', output)(exports, (key) => {
    if (!(key in dependencies)) throw new Error(`Unexpected runtime import: ${key}`);
    return dependencies[key];
  });
  return exports;
}
const model = compile('apps/mobile/lib/homeModel.ts');
const now = Date.parse('2026-11-19T14:00:00Z');
const old = '2026-11-18T14:00:00Z';
const future = '2099-11-20T14:00:00Z';
const rows = [
  { status: 'new', due_at: future }, { status: 'received', due_at: old },
  { status: 'in_progress', due_at: future }, { status: 'on_hold', due_at: old },
  { status: 'report_submitted', due_at: future }, { status: 'completed_approved', due_at: old },
  { status: 'cancelled', due_at: old }, { status: 'needs_revision', due_at: old },
  { status: 'late', due_at: future }, { status: 'in_progress', due_at: future, report_forms: [{ status: 'submitted' }, { status: 'submitted' }] },
];
assert.deepEqual(model.summarizeTasks(rows, now), { all: 10, in_progress: 3, submitted: 2, late: 4 });
assert.equal(model.taskMatchesFilter({ status: 'approved', due_at: old }, 'late', now), false);
assert.equal(model.taskMatchesFilter({ status: 'new', due_at: 'invalid' }, 'late', now), false);
assert.equal(model.taskMatchesFilter({ status: 'in_progress', due_at: '2026-11-19T14:00:00Z' }, 'late', now), false);
assert.equal(model.taskMatchesFilter({ status: 'needs_revision' }, 'rejected', now), true);
const employee = { institutionId: 'org-1', roles: [{ code: 'warehouse_worker', nameAr: 'عامل تحميل' }], permissions: ['tasks.execute'], branches: [{ id: 'b1', name: 'فرع 1' }] };
const manager = { ...employee, roles: [{ code: 'admin_followup', nameAr: 'المدير التنفيذي' }], permissions: ['tasks.manage', 'tasks.review', 'employees.manage', 'employees.read', 'branches.manage', 'task_library.manage', 'report_forms.manage'] };
assert.equal(model.homeAccess(employee).employees, false);
assert.equal(model.homeAccess(employee)['report-designer'], false);
assert.equal(model.homeAccess(manager).settings, true);
assert.equal(model.homeAccess(manager)['report-designer'], true);
assert.equal(model.homeAccess({ ...manager, permissions: ['tasks.manage', 'report_forms.manage'] })['task-designer'], false);
assert.equal(model.homeAccess({ ...manager, permissions: ['tasks.manage'] }).reports, false);
assert.equal(model.homeAccess({ ...employee, permissions: ['employees.manage'] }).settings, false);

// Minimal Supabase mock: evaluates actual queries, scope and page ranges.
const taskRows = Array.from({ length: 1201 }, (_, i) => ({ id: `task-${String(i).padStart(4, '0')}`, status: i % 2 ? 'on_hold' : 'new', due_at: future, organization_id: 'org-1', branch_id: i % 2 ? 'b1' : 'b2', assigned_to: i % 2 ? 'user-1' : 'user-2' }));
const tables = { tasks: taskRows, task_reports: [{ id: 'r1', task_id: 'task-0001', status: 'submitted' }, { id: 'r2', task_id: 'task-0001', status: 'submitted' }], notifications: [{ id: 'n1', read_at: null }, { id: 'n2', read_at: old }], branches: [], organization_memberships: [], role_assignments: [], task_report_fields: [], task_execution_steps: [], task_report_form_snapshots: [], task_report_drafts: [] };
const calls = [];
let failure = null;
const db = {
  auth: { getUser: async () => ({ data: { user: { id: 'user-1' } }, error: null }) },
  from(table) {
    const query = { table, filters: [], columns: null, start: 0, end: Infinity, options: {} };
    const builder = {
      select(columns, options = {}) { query.columns = columns; query.options = options; return this; },
      eq(key, value) { query.filters.push((row) => row[key] === value); return this; },
      is(key, value) { return this.eq(key, value); },
      in(key, values) { query.filters.push((row) => values.includes(row[key])); return this; },
      order() { return this; },
      limit(count) { query.end = count - 1; return this; },
      range(start, end) { query.start = start; query.end = end; return this; },
      then(resolve, reject) {
        calls.push(query);
        const filtered = tables[table].filter((row) => query.filters.every((filter) => filter(row)));
        const result = { data: query.options.head ? null : filtered.slice(query.start, query.end + 1), count: query.options.count ? filtered.length : null, error: failure };
        return Promise.resolve(result).then(resolve, reject);
      },
    };
    return builder;
  },
};
const data = compile('apps/mobile/lib/homeData.ts', { './supabase': { supabase: db }, './homeModel': model });
assert.deepEqual(await data.loadHomeSummary(manager, null), { all: 1201, in_progress: 600, submitted: 1, late: 0 });
assert.equal(calls.filter((query) => query.table === 'tasks').length, 3);
assert.equal((await data.loadHomeSummary(employee, null)).all, 600);
assert.equal((await data.loadHomeSummary(manager, 'b2')).all, 601);
assert.equal(await data.countUnreadNotifications(), 1);
const mobileData = compile('apps/mobile/lib/mobileData.ts', { './supabase': { supabase: db }, './offlineQueue': {} });
assert.equal((await mobileData.listMyTasks()).length, 1201, 'The destination list must contain all counted tasks');
failure = { code: 'PGRST205', message: 'missing notifications' };
assert.equal(await data.countUnreadNotifications(), 0);
failure = { code: '42501', message: 'permission denied' };
await assert.rejects(data.loadHomeSummary(manager, null));
await assert.rejects(data.countUnreadNotifications());

const home = read('apps/mobile/components/HomeDashboard.tsx');
const index = read('apps/mobile/app/index.tsx');
const admin = read('apps/mobile/app/admin.tsx');
const tasks = read('apps/mobile/app/tasks.tsx');
const config = JSON.parse(read('apps/mobile/app.json'));
assert.equal(config.expo.userInterfaceStyle, 'light');
assert.match(index, /return <HomeDashboard profile=\{profile\}/);
assert.match(index, /onSignOut=\{clearHomeProfile\}/);
assert.doesNotMatch(index, /router\.replace\('\/(admin|tasks)'\)/);
assert.match(home, /maxWidth: 840/);
assert.match(home, /paddingBottom: Math\.max\(insets\.bottom, 8\)/);
assert.match(home, /frame: \{[^}]*direction: 'rtl'/);
assert.match(home, /moduleGrid: \{[^}]*flexDirection: 'row'/);
assert.match(home, /chooseBranch/);
assert.match(home, /profile\.branches\.some/);
assert.doesNotMatch(home, /غير متاح حالياً/);
assert.match(home, /unread/);
assert.match(home, /countUnreadNotifications/);
assert.match(home, /serviceGroups/);
assert.match(home, /groupServices/);
assert.doesNotMatch(home, /!enabled && styles\.unavailableCard/);
assert.match(tasks, /taskMatchesFilter\(task, statusFilter\)/);
assert.match(tasks, /task\.branch_id === branchFilter/);
assert.match(tasks, /\['all', 'pending', 'in_progress', 'submitted', 'rejected', 'approved', 'late'\]/);
assert.match(admin, /section === 'overview' && profile\) return <HomeDashboard/);
assert.match(admin, /section === 'report-designer'.*canManageReports/);
assert.match(admin, /Promise\.all\(\[/);
assert.match(admin, /loadDashboardData\(\{ force, maxAgeMs: 30_000 \}\)/);
assert.match(admin, /onTaskUpdated/);
assert.match(admin, /onTaskDeleted/);
assert.match(admin, /onReportUpdated/);
assert.match(admin, /onReportDeleted/);
assert.match(admin, /updateManagedTask\(institutionId, task\.id, title, description, task\.dueAt\); onTaskUpdated/);
assert.match(admin, /deleteManagedTask\(institutionId, task\.id\); onTaskDeleted/);
assert.match(admin, /const createdTask = await createAdministrativeTask/);
assert.match(admin, /id: createdTask\.id/);
assert.match(admin, /tasks: \[\.\.\.current\.tasks/);
assert.equal(admin.includes("setShowCreate(false); setNotice('تم إنشاء المهمة وإسنادها للموظف المحدد.'); await load(true)"), false);
const adminData = read('apps/mobile/lib/adminData.ts');
assert.match(adminData, /dashboardCache/);
assert.match(adminData, /dashboardRequest/);
assert.match(adminData, /loadDashboardDataFresh/);
const titles = ['إدارة المهام', 'التقارير', 'إدارة الموظفين', 'إدارة الفروع', 'إحصائيات ومقارنة الأداء', 'مصمم المهام', 'مصمم التقارير', 'الصلاحيات'];
assert.doesNotMatch(home, /المخزون/);
let last = -1;
for (const title of titles) { const offset = home.indexOf(`title: '${title}'`); assert(offset > last, `Tile order: ${title}`); last = offset; }
console.log('Home dashboard executable checks passed: status/overdue/multi-form counts, 1201-row pagination, employee/organization/branch scope, notification failures, permissions and route/layout wiring.');
