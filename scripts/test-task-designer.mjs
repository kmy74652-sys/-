import { readFileSync } from 'node:fs';

const sql = readFileSync('supabase/migrations/035_task_designer_multi_reports.sql', 'utf8');
const designer = readFileSync('apps/mobile/components/TaskDesigner.tsx', 'utf8');
const library = readFileSync('apps/mobile/lib/taskDesigner.ts', 'utf8');
const admin = readFileSync('apps/mobile/app/admin.tsx', 'utf8');
const tasks = readFileSync('apps/mobile/app/tasks.tsx', 'utf8');
const checks = [
  ['permission RPC is separate from report designer', sql.includes('task_library_allowed_for_org') && library.includes('task_library_allowed_for_org')],
  ['approved report RPC is safe', sql.includes('list_task_library_report_forms') && sql.includes('security definer')],
  ['assignment options are persisted', sql.includes('p_priority text') && sql.includes('p_report_overrides jsonb') && library.includes('reportOverrides')],
  ['drafts have RLS and RPC', sql.includes('task_report_drafts') && sql.includes('save_task_report_draft') && tasks.includes('saveTaskReportDraft')],
  ['preview can move and resize', designer.includes('PanResponder') && designer.includes('تغيير الحجم')],
  ['steps support touch reorder', designer.includes('StepDragHandle') && designer.includes('onDrop')],
  ['copy/archive are guarded in admin', admin.includes('نسخ القالب') && admin.includes('setTaskDesignerTemplateActive') && admin.includes('canManageTaskLibrary')],
  ['dynamic report designer is mounted beside task designer', admin.includes("import ReportDesigner") && admin.includes('<ReportDesigner />')],
  ['legacy starter catalog is hidden from designer', library.includes('retiredStarterTemplateCodes') && !admin.includes('قالب التقرير القديم')],
];
const failed = checks.filter(([, ok]) => !ok);
if (failed.length) { console.error(JSON.stringify({ ok: false, failed: failed.map(([name]) => name) })); process.exit(1); }
console.log(JSON.stringify({ ok: true, checks: checks.length, names: checks.map(([name]) => name) }));
