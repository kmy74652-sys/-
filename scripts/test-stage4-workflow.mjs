import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (name) => fs.readFileSync(new URL(`../${name}`, import.meta.url), 'utf8');
const designer = read('apps/mobile/components/OrganizationalTaskDesigner.tsx');
const admin = read('apps/mobile/app/admin.tsx');
const adminData = read('apps/mobile/lib/adminData.ts');
const mobile = read('apps/mobile/app/tasks.tsx');
const mobileData = read('apps/mobile/lib/mobileData.ts');
const taskDesigner = read('apps/mobile/lib/taskDesigner.ts');
const roleReports = read('apps/mobile/lib/employeeRoleReports.ts');
const designerSql = read('supabase/migrations/035_task_designer_multi_reports.sql');
const workflowSql = read('supabase/migrations/022_mobile_modern_task_workflows.sql');

const checks = [
  ['المصمم يختار الموظف والفرع والموعد', designer.includes('selectedBranchId') && designer.includes('الفرع المستلم') && designer.includes('selectedEmployeeId') && designer.includes('AdenDeadlinePicker')],
  ['الإرسال يمر من المصمم الحالي إلى إنشاء المهمة المباشرة', designer.includes('onSend?.') && admin.includes('createAdministrativeTask') && admin.includes('templateId: draft.id ?? null') && admin.includes('assignedEmployeeId: employeeId') && admin.includes('dueAt')],
  ['لوحة الإدارة تمرر الفروع الفعلية للمصمم', admin.includes('branches={data?.branches ?? []}') && admin.includes('branches: NonNullable<DashboardData>[\'branches\']')],
  ['الخلفية تتحقق من الموظف والدور والفرع والحساب المرتبط', adminData.includes('employee_assignment_invalid') && adminData.includes('employee_login_not_linked') && designerSql.includes('no_employee_for_role_branch')],
  ['الإسناد ينشئ مهمة متعددة النماذج للموظف مع الموعد', designerSql.includes('assigned_to,created_by,due_at,starts_at') && designerSql.includes("'multi_form'") && designerSql.includes('p_due_at<p_starts_at')],
  ['المهمة تظهر للموظف من خلال هوية الحساب وليس التقرير المستقل', mobileData.includes("from('tasks')") && mobile.includes('task.assignee_employee_id === currentUserId') && !mobile.includes('employeeNewOnly')],
  ['تبويب المهام يحتفظ بالمهمة بعد البدء ويعرض زر بدء التنفيذ', mobile.includes("task.status === 'in_progress'") && mobile.includes('بدء التنفيذ') && mobile.includes('updateTaskStatus(task.id, \'in_progress\')')],
  ['حقول التقرير المرتبط لا تفتح إلا أثناء التنفيذ أو بعد الإرجاع', mobile.includes("const canEdit=['in_progress','rejected','submitted']") && mobile.includes('form.schema.filter')],
  ['إرسال التقرير المرتبط محكوم بالتحقق وقفل الإرسال والتكرار', mobile.includes('إرسال التقرير مرة واحدة') && designerSql.includes('report_form_already_submitted') && designerSql.includes('idempotency_key')],
  ['التقرير يصل لقائمة الإدارة مع مصدر task', adminData.includes("source: 'task'") && admin.includes('فتح المهمة للمراجعة والاعتماد')],
  ['الإدارة تعتمد أو ترجع مع ملاحظة عبر RPC محمي', mobile.includes("reviewTaskFormReport(form.report_id!,'approved'") && mobile.includes("reviewTaskFormReport(form.report_id!,'returned',reviewNote)") && designerSql.includes('review_note') && designerSql.includes("p_decision not in ('approved','returned')")],
  ['الإرجاع يعيد المهمة إلى needs_revision ويسمح بإعادة التعبئة فقط', designerSql.includes("set status='needs_revision'") && mobile.includes("form.status==='returned'") && mobile.includes("form.status!=='submitted'&&form.status!=='approved'")],
  ['التقارير المستقلة تستخدم جدولًا وRPC منفصلين عن task_reports', roleReports.includes("from('employee_role_reports')") && roleReports.includes('mobile_submit_employee_role_report') && adminData.includes('employee_role_reports') && adminData.includes("source: 'role'")],
  ['مساحة إعداد التقارير تفصل نماذج المهام عن التقرير المستقل', mobile.includes('تقارير المهام') && mobile.includes('التقارير اليومية من الإدارة') && mobile.includes('EmployeeRoleReportPanel') && mobile.includes('reportsOnly')],
];

const failed = checks.filter(([, ok]) => !ok);
if (failed.length) {
  console.error(JSON.stringify({ ok: false, failed: failed.map(([name]) => name) }));
  process.exit(1);
}
console.log(JSON.stringify({ ok: true, checks: checks.length, scenario: 'stage4-task-report-cycle' }));
