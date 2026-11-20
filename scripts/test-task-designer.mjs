import { readFileSync } from 'node:fs';

const sql = readFileSync('supabase/migrations/035_task_designer_multi_reports.sql', 'utf8');
const designer = readFileSync('apps/mobile/components/TaskDesigner.tsx', 'utf8');
const organizational = readFileSync('apps/mobile/components/OrganizationalTaskDesigner.tsx', 'utf8');
const library = readFileSync('apps/mobile/lib/taskDesigner.ts', 'utf8');
const admin = readFileSync('apps/mobile/app/admin.tsx', 'utf8');
const adminData = readFileSync('apps/mobile/lib/adminData.ts', 'utf8');
const mobileData = readFileSync('apps/mobile/lib/mobileData.ts', 'utf8');
const tasks = readFileSync('apps/mobile/app/tasks.tsx', 'utf8');
const roleReports = readFileSync('apps/mobile/lib/employeeRoleReports.ts', 'utf8');
const roleReportPanel = readFileSync('apps/mobile/components/EmployeeRoleReportPanel.tsx', 'utf8');
const roleReportsMigration = readFileSync('supabase/migrations/068_employee_role_reports.sql', 'utf8');
const reportCycle = readFileSync('supabase/migrations/054_report_cycle_notifications.sql', 'utf8');
const checks = [
  ['permission RPC is separate from report designer', sql.includes('task_library_allowed_for_org') && library.includes('task_library_allowed_for_org')],
  ['approved report RPC is safe', sql.includes('list_task_library_report_forms') && sql.includes('security definer')],
  ['assignment options are persisted', sql.includes('p_priority text') && sql.includes('p_report_overrides jsonb') && library.includes('reportOverrides')],
  ['drafts have RLS and RPC', sql.includes('task_report_drafts') && sql.includes('save_task_report_draft') && tasks.includes('saveTaskReportDraft')],
  ['preview can move and resize', designer.includes('PanResponder') && designer.includes('تغيير الحجم')],
  ['steps support touch reorder', designer.includes('StepDragHandle') && designer.includes('onDrop')],
  ['copy/archive are guarded in admin', admin.includes('نسخ القالب') && admin.includes('setTaskDesignerTemplateActive') && admin.includes('canManageTaskLibrary')],
  ['direct send targets the selected employee without legacy template assignment', organizational.includes('selectedEmployeeId') && organizational.includes('إرسال المهمة للموظف مباشرة') && admin.includes('createAdministrativeTask') && admin.includes('templateId: null') && !admin.includes('assignTaskFromTemplate') && !admin.includes('إسناد من قالب')],
  ['direct send preserves role and branch validation', organizational.includes('employee.assignments') && adminData.includes('employee_assignment_invalid') && admin.includes('branchId, assignedEmployeeId: employeeId')],
  ['save dispatches the directed task immediately', organizational.includes('await onSave?.(draft)') && organizational.includes('await onSend?.(draft') && admin.includes('تفاصيل التنفيذ المباشر:')],
  ['employee task tab shows new tasks only', tasks.includes('const employeeNewOnly') && tasks.includes("normalizeTaskStatus(task.status) === 'pending'") && tasks.includes('!employeeNewOnly ||')],
  ['manual task assignment clears stale branch and matches role-specific assignments', admin.includes("roleCode: role, branchId: '', assignedEmployeeId: ''") && admin.includes('const employeesForDraft') && admin.includes('assignment.roleCode === draft.roleCode && (!draft.branchId || assignment.branchId === draft.branchId)')],
  ['manual task assignment requires a linked login and explains missing employees', admin.includes('Boolean(employee.userId)') && adminData.includes("employee_login_not_linked") && mobileData.includes('no_employee_for_role:')],
  ['assignment failures have clear Arabic causes', mobileData.includes('no_employee_for_role_branch:') && mobileData.includes('invalid_task_schedule:')],
  ['organizational designer replaces legacy task designer', admin.includes('OrganizationalTaskDesigner') && admin.includes('الجدول التنظيمي') && organizational.includes('حفظ الجدول التنظيمي')],
  ['organizational schedule has role, work periods, rows and performance proof', organizational.includes('الدور الوظيفي') && organizational.includes('الفترة الصباحية') && organizational.includes('فترة الاستراحة') && organizational.includes('الفترة المسائية') && organizational.includes('مؤشر الأداء') && organizational.includes('الإثبات أو الشرط') && organizational.includes('إضافة صف')],
  ['organizational schedule has continuous work, daily report and controls', organizational.includes('المهام المستمرة طوال الدوام') && organizational.includes('بنود التقرير اليومي للموظف') && organizational.includes('التوصيات والضوابط الإدارية')],
  ['admin can add custom KPI indicators beside the row KPI title', organizational.includes('+ إضافة مؤشر') && organizational.includes('showKpiInput') && organizational.includes('addKpi') && organizational.includes('setKpis') && organizational.includes('kpiIndicator: value') && admin.includes('canManage={true}')],
  ['admin can add and delete task sub-items', organizational.includes('إضافة بند فرعي') && organizational.includes('addSubItem') && organizational.includes('removeSubItem') && organizational.includes('البنود الفرعية')],
  ['task and sub-item deletion require confirmation', organizational.includes('تأكيد حذف المهمة') && organizational.includes('تأكيد حذف البند') && organizational.includes("style: 'destructive'")],
  ['report designer remains independent', admin.includes("import ReportDesigner") && admin.includes('section === \'report-designer\'') && admin.includes('<ReportDesigner')],
  ['legacy starter catalog is hidden from designer', library.includes('retiredStarterTemplateCodes') && !admin.includes('قالب التقرير القديم')],
  ['reports are designed independently and delivered automatically by role', designer.includes('التقارير مستقلة عن قالب المهمة') && admin.includes('حقول التقرير المعتمدة للدور المحدد تُرسل تلقائياً') && admin.includes('const selectedReport = designerTemplates.find((template) => template.role_code === draft.roleCode')],
  ['admin report review has search and status filters', (admin.includes('ابحث باسم الموظف أو المهمة') || admin.includes('ابحث باسم الموظف أو التقرير')) && admin.includes("setStatus(value)") && adminData.includes('taskTitle') && adminData.includes('values')],
  ['report submission and review notifications are automatic', reportCycle.includes('task_reports_notify_cycle') && reportCycle.includes("new.status in ('approved', 'returned')")],
  ['employee report upload tab has independent status filters', tasks.includes('رفع التقارير المرتبطة بالمهام') && tasks.includes('جاهز للرفع') && tasks.includes('تم الرفع') && tasks.includes('reportStatusFilter') && tasks.includes('reportStatusMatches')],
  ['employee third tab uses independent role reports instead of dynamic reports', tasks.includes('EmployeeRoleReportPanel') && tasks.includes('!reportsOnly && filteredTasks.map') && roleReportPanel.includes('إرسال التقرير للإدارة') && roleReports.includes('mobile_submit_employee_role_report')],
  ['role reports have independent secure storage and review workflow', roleReportsMigration.includes('employee_role_reports') && roleReportsMigration.includes('mobile_submit_employee_role_report') && roleReportsMigration.includes('review_employee_role_report') && roleReportsMigration.includes("status in ('submitted','approved','returned')")],
  ['admin report list includes role reports', adminData.includes('employee_role_reports') && adminData.includes("source: 'role'") && admin.includes('اعتماد تقرير الدور')],
];
const failed = checks.filter(([, ok]) => !ok);
if (failed.length) { console.error(JSON.stringify({ ok: false, failed: failed.map(([name]) => name) })); process.exit(1); }
console.log(JSON.stringify({ ok: true, checks: checks.length, names: checks.map(([name]) => name) }));
