import { readFileSync } from 'node:fs';

const sql = readFileSync('supabase/migrations/035_task_designer_multi_reports.sql', 'utf8');
const decouplingMigration = readFileSync('supabase/migrations/079_decouple_task_report_fields.sql', 'utf8');
const publicationMigration = readFileSync('supabase/migrations/20261121170000_task_publication_review_and_group_publish.sql', 'utf8');
const publicationPanel = readFileSync('apps/mobile/components/TaskPublicationReviewPanel.tsx', 'utf8');
const publicationClient = readFileSync('apps/mobile/lib/taskPublication.ts', 'utf8');
const designer = readFileSync('apps/mobile/components/TaskDesigner.tsx', 'utf8');
const organizational = readFileSync('apps/mobile/components/OrganizationalTaskDesigner.tsx', 'utf8');
const library = readFileSync('apps/mobile/lib/taskDesigner.ts', 'utf8');
const admin = readFileSync('apps/mobile/app/admin.tsx', 'utf8');
const adminData = readFileSync('apps/mobile/lib/adminData.ts', 'utf8');
const mobileData = readFileSync('apps/mobile/lib/mobileData.ts', 'utf8');
const tasks = readFileSync('apps/mobile/app/tasks.tsx', 'utf8');
const dynamicReports = readFileSync('apps/mobile/components/EmployeeDynamicReportsPanel.tsx', 'utf8');
const dynamicReportsClient = readFileSync('apps/mobile/lib/dynamicReports.ts', 'utf8');
const dynamicReportsMigration = readFileSync('supabase/migrations/073_employee_dynamic_reports.sql', 'utf8');
if (!tasks.includes('inAppNotification') || !tasks.includes('مهمة جديدة') || !tasks.includes("payload?.eventType === 'INSERT'") || !tasks.includes('notifiedTaskIds')) {
  console.error(JSON.stringify({ ok: false, failed: ['in-app new-task banner and deduplication'] }));
  process.exit(1);
}
if (!tasks.includes('EmployeeDynamicReportsPanel') || !dynamicReports.includes('إرسال التقرير للإدارة') || !dynamicReportsClient.includes('list_my_dynamic_report_forms') || !dynamicReportsMigration.includes('submit_my_dynamic_report')) {
  console.error(JSON.stringify({ ok: false, failed: ['independent dynamic report delivery to employee'] }));
  process.exit(1);
}
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
  ['final template delete is guarded and copy/archive are hidden', admin.includes('حذف نهائي') && admin.includes('deleteTaskDesignerTemplate') && !admin.includes('نسخ القالب') && !admin.includes('setTaskDesignerTemplateActive') && admin.includes('canManageTaskLibrary') && library.includes("delete_task_designer_template")],
  ['designer targets a role and branch without selecting an employee', organizational.includes('eligibleCount') && organizational.includes('لا يلزم اختيار موظف بالاسم') && !organizational.includes('selectedEmployeeId') && organizational.includes('حفظ وإرسال للمراجعة الإدارية') && organizational.includes('dispatchKey') && publicationClient.includes('p_idempotency_key')],
  ['publication waits for owner review before group delivery', publicationMigration.includes('pending_approval') && publicationMigration.includes('review_and_publish_task_request') && publicationMigration.includes("ra.role_code='owner'") && publicationMigration.includes('approved-template:') && publicationMigration.includes('request_key') && publicationMigration.includes('ON CONFLICT (organization_id, request_key) DO NOTHING') && publicationClient.includes('submit_task_publication_request') && publicationPanel.includes('اعتماد ونشر للموظفين') && admin.includes('TaskPublicationReviewPanel') && admin.includes('submitTaskPublicationRequest')],
  ['delivery milestones are persisted and shown', tasks.includes('delivery_status') && tasks.includes('حالة الوصول') && mobileData.includes('markTaskOpened') && sql.includes('task_activity_log')],
  ['task management embeds the designer and routes publication to review', admin.includes('onDesignerSave={saveDesignerTask}') && admin.includes('onDesignerSend={sendDesignerTask}') && admin.includes('＋ من مصمم المهام') && admin.includes('<OrganizationalTaskDesigner employees={data?.employees ?? []}') && admin.includes('await submitTaskPublicationRequest')],
  ['publication validates eligible active role and branch recipients', publicationMigration.includes('m.is_active AND m.user_id IS NOT NULL') && publicationMigration.includes('ra.role_code=v_template.role_code') && publicationMigration.includes('invalid_task_branch')],
  ['save snapshots the complete design before submitting it for review', organizational.includes('const saveResult = await onSave?.(draft)') && organizational.includes('saveResult?.templateId') && organizational.includes('await onSend?.({ ...draft') && publicationMigration.includes('template_snapshot') && publicationMigration.includes("'report_fields'")],
  ['employee task tab receives assigned tasks automatically', tasks.includes('task.assignee_employee_id === currentUserId') && tasks.includes('postgres_changes') && tasks.includes('assigned_to=eq.') && tasks.includes('load({ force: true })') && mobileData.includes('assignedTo?: string')],
  ['dynamic test cards stay hidden while designer tasks remain visible', tasks.includes('isDynamicTestTitle') && tasks.includes('!isDynamicTestTitle(task.title)') && tasks.includes('اختبار مهمة ديناميكية')],
  ['manual task assignment clears stale branch and matches role-specific assignments', admin.includes("roleCode: role, branchId: '', assignedEmployeeId: ''") && admin.includes('const employeesForDraft') && admin.includes('assignment.roleCode === draft.roleCode && (!draft.branchId || assignment.branchId === draft.branchId)')],
  ['manual task assignment requires a linked login and explains missing employees', admin.includes('Boolean(employee.userId)') && adminData.includes("employee_login_not_linked") && mobileData.includes('no_employee_for_role:')],
  ['assignment failures have clear Arabic causes', mobileData.includes('no_employee_for_role_branch:') && mobileData.includes('invalid_task_schedule:')],
  ['organizational designer replaces legacy task designer', admin.includes('OrganizationalTaskDesigner') && admin.includes('الجدول التنظيمي') && organizational.includes('حفظ وإرسال للمراجعة')],
  ['organizational schedule has role, work periods, rows and performance proof', organizational.includes('الدور الوظيفي') && organizational.includes('الفترة الصباحية') && organizational.includes('فترة الاستراحة') && organizational.includes('الفترة المسائية') && organizational.includes('مؤشر الأداء') && organizational.includes('الإثبات أو الشرط') && organizational.includes('إضافة صف')],
  ['organizational schedule has continuous work, daily report and controls', organizational.includes('المهام المستمرة طوال الدوام') && organizational.includes('بنود التقرير اليومي للموظف') && organizational.includes('التوصيات والضوابط الإدارية')],
  ['admin can add custom KPI indicators beside the row KPI title', organizational.includes('+ إضافة مؤشر') && organizational.includes('showKpiInput') && organizational.includes('addKpi') && organizational.includes('setKpis') && organizational.includes('kpiIndicator: value') && admin.includes('canManage={true}')],
  ['admin can add and delete task sub-items', organizational.includes('إضافة بند فرعي') && organizational.includes('addSubItem') && organizational.includes('removeSubItem') && organizational.includes('البنود الفرعية')],
  ['task and sub-item deletion require confirmation', organizational.includes('تأكيد حذف المهمة') && organizational.includes('تأكيد حذف البند') && organizational.includes("style: 'destructive'")],
  ['report designer remains independent', admin.includes("import ReportDesigner") && admin.includes('section === \'report-designer\'') && admin.includes('<ReportDesigner')],
  ['legacy starter catalog is hidden from designer', library.includes('retiredStarterTemplateCodes') && !admin.includes('قالب التقرير القديم')],
  ['task report fields stay inside task designer and are not report-designer forms', library.includes('task_template_report_fields') && library.includes('report_fields: draft.reportFields') && !library.includes('saveDesignerTemplate({') && publicationMigration.includes('v_field_count > 0') && publicationMigration.includes('task_report_form_snapshots') && designer.includes('لا تُنشئ نموذجاً داخل «مصمم التقارير»') && decouplingMigration.includes('task_template_report_fields') && decouplingMigration.includes('embedded_report_fields')],
  ['admin report review has search and status filters', (admin.includes('ابحث باسم الموظف أو المهمة') || admin.includes('ابحث باسم الموظف أو التقرير')) && admin.includes("setStatus(value)") && adminData.includes('taskTitle') && adminData.includes('values')],
  ['report submission and review notifications are automatic', reportCycle.includes('task_reports_notify_cycle') && reportCycle.includes("new.status in ('approved', 'returned')")],
  ['employee report upload tab has independent status filters', tasks.includes('تقارير المهام') && tasks.includes('جاهز للرفع') && tasks.includes('تم الرفع') && tasks.includes('reportStatusFilter') && tasks.includes('reportStatusMatches')],
  ['employee third tab uses independent role reports instead of dynamic reports', tasks.includes('EmployeeRoleReportPanel') && tasks.includes('filteredTasks.map((task)') && roleReportPanel.includes('إرسال التقرير للإدارة') && roleReports.includes('mobile_submit_employee_role_report')],
  ['employee reports are split into linked-task and administration-designed sections', tasks.includes('تقارير المهام') && tasks.includes('التقارير اليومية من الإدارة') && tasks.includes('EmployeeRoleReportPanel') && tasks.includes('reportsOnly')],
  ['role reports have independent secure storage and review workflow', roleReportsMigration.includes('employee_role_reports') && roleReportsMigration.includes('mobile_submit_employee_role_report') && roleReportsMigration.includes('review_employee_role_report') && roleReportsMigration.includes("status in ('submitted','approved','returned')")],
  ['admin report list includes role reports', adminData.includes('employee_role_reports') && adminData.includes("source: 'role'") && admin.includes('اعتماد تقرير الدور')],
  ['legacy submitted report values are shown to employees', mobileData.includes('legacy_report_values') && tasks.includes('task.legacy_report_values ?? {}')],
  ['role reports are isolated by branch and reload on branch changes', roleReports.includes('listMyRoleReports(roleCode: string, branchId: string | null') && roleReports.includes(".eq('branch_id', branchId)") && roleReportPanel.includes('useEffect(() => { void load(); }, [roleCode, branchId])')],
  ['specialized role report errors have Arabic messages', mobileData.includes('role_report_assignment_invalid:') && mobileData.includes('role_report_already_submitted:') && mobileData.includes('review_note_required:') && mobileData.includes('invalid_role_report_payload:')],
  ['role task cards are added inside the existing designer', organizational.includes('warehouse_keeper') && organizational.includes('warehouse_worker') && organizational.includes('admin_followup') && organizational.includes('owner') && organizational.includes('إضافة بطاقات') && organizational.includes('إضافة البطاقات المحاسبية الناقصة') && organizational.includes('accountantMissingRows')],
];
const failed = checks.filter(([, ok]) => !ok);
if (failed.length) { console.error(JSON.stringify({ ok: false, failed: failed.map(([name]) => name) })); process.exit(1); }
console.log(JSON.stringify({ ok: true, checks: checks.length, names: checks.map(([name]) => name) }));
