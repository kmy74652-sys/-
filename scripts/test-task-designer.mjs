import { readFileSync } from 'node:fs';

const sql = readFileSync('supabase/migrations/035_task_designer_multi_reports.sql', 'utf8');
const designer = readFileSync('apps/mobile/components/TaskDesigner.tsx', 'utf8');
const library = readFileSync('apps/mobile/lib/taskDesigner.ts', 'utf8');
const admin = readFileSync('apps/mobile/app/admin.tsx', 'utf8');
const adminData = readFileSync('apps/mobile/lib/adminData.ts', 'utf8');
const mobileData = readFileSync('apps/mobile/lib/mobileData.ts', 'utf8');
const tasks = readFileSync('apps/mobile/app/tasks.tsx', 'utf8');
const reportCycle = readFileSync('supabase/migrations/054_report_cycle_notifications.sql', 'utf8');
const checks = [
  ['permission RPC is separate from report designer', sql.includes('task_library_allowed_for_org') && library.includes('task_library_allowed_for_org')],
  ['approved report RPC is safe', sql.includes('list_task_library_report_forms') && sql.includes('security definer')],
  ['assignment options are persisted', sql.includes('p_priority text') && sql.includes('p_report_overrides jsonb') && library.includes('reportOverrides')],
  ['drafts have RLS and RPC', sql.includes('task_report_drafts') && sql.includes('save_task_report_draft') && tasks.includes('saveTaskReportDraft')],
  ['preview can move and resize', designer.includes('PanResponder') && designer.includes('تغيير الحجم')],
  ['steps support touch reorder', designer.includes('StepDragHandle') && designer.includes('onDrop')],
  ['copy/archive are guarded in admin', admin.includes('نسخ القالب') && admin.includes('setTaskDesignerTemplateActive') && admin.includes('canManageTaskLibrary')],
  ['assignee uses auth user id rather than membership id', adminData.includes('userId: row.user_id') && admin.includes('assignedTo: employee.userId!')],
  ['multi-recipient send reports success and partial failures', admin.includes('employeeIds') && admin.includes('assignedCount') && admin.includes('تعذر الإسناد إلى')],
  ['employee choices respect role and branch assignment', adminData.includes('assignments: assignmentsByMembership.get(row.id)') && admin.includes('assignment.roleCode === selectedTemplate.roleCode && (!branchId || assignment.branchId === branchId)')],
  ['manual task assignment clears stale branch and matches role-specific assignments', admin.includes("roleCode: role, branchId: '', assignedEmployeeId: ''") && admin.includes('const employeesForDraft') && admin.includes('assignment.roleCode === draft.roleCode && (!draft.branchId || assignment.branchId === draft.branchId)')],
  ['manual task assignment requires a linked login and explains missing employees', admin.includes('Boolean(employee.userId)') && adminData.includes("employee_login_not_linked") && mobileData.includes('no_employee_for_role:')],
  ['assignment failures have clear Arabic causes', mobileData.includes('no_employee_for_role_branch:') && mobileData.includes('invalid_task_schedule:')],
  ['save template is explicitly distinguished from sending a task', admin.includes('حفظ القالب يحفظ التصميم فقط ولا يرسل تكليفًا')],
  ['dynamic report designer is mounted beside task designer', admin.includes("import ReportDesigner") && admin.includes('<ReportDesigner />')],
  ['legacy starter catalog is hidden from designer', library.includes('retiredStarterTemplateCodes') && !admin.includes('قالب التقرير القديم')],
  ['approved report templates can be linked to task templates', designer.includes('reportTemplates') && designer.includes('نموذج التقرير الذي سيعبئه الموظف') && admin.includes('reportTemplates={designerTemplates.flatMap')],
  ['admin report review has search and status filters', admin.includes('ابحث باسم الموظف أو المهمة') && admin.includes("setStatus(value)") && adminData.includes('taskTitle') && adminData.includes('values')],
  ['report submission and review notifications are automatic', reportCycle.includes('task_reports_notify_cycle') && reportCycle.includes("new.status in ('approved', 'returned')")],
];
const failed = checks.filter(([, ok]) => !ok);
if (failed.length) { console.error(JSON.stringify({ ok: false, failed: failed.map(([name]) => name) })); process.exit(1); }
console.log(JSON.stringify({ ok: true, checks: checks.length, names: checks.map(([name]) => name) }));
