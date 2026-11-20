import { supabase } from './supabase';

export type RoleReportStatus = 'submitted' | 'approved' | 'returned';
export type RoleReport = {
  id: string;
  organization_id: string;
  employee_user_id: string;
  role_code: string;
  branch_id: string | null;
  report_date: string;
  report_title: string;
  values: Record<string, string>;
  status: RoleReportStatus;
  submitted_at: string;
  review_note: string | null;
};
export type RoleReportField = { key: string; label: string; long?: boolean };

export const roleReportConfigs: Record<string, { title: string; fields: RoleReportField[] }> = {
  accountant: { title: 'التقرير اليومي للمحاسب', fields: [
    { key: 'sales_orders', label: 'عدد فواتير مبيعات الجملة وطلبات العملاء المستلمة والمنفذة' },
    { key: 'collected_amounts', label: 'إجمالي المبالغ المحصلة' },
    { key: 'purchase_invoices', label: 'عدد فواتير المشتريات المسجلة' },
    { key: 'matched_suppliers', label: 'أسماء الموردين الذين تمت مطابقة حساباتهم', long: true },
    { key: 'handed_accounts', label: 'عدد الحسابات المسلمة للمتابعة' },
    { key: 'delayed_work', label: 'الأعمال التي لم تنجز وأسباب التأخير', long: true },
  ] },
  warehouse_keeper: { title: 'التقرير اليومي لأمين المخازن', fields: [
    { key: 'issued_orders', label: 'عدد أوامر الصرف المخزني المنفذة وتسليم الفواتير للمحاسب' },
    { key: 'received_purchases', label: 'عدد توريدات المشتريات المستلمة والتحقق منها' },
    { key: 'counted_items', label: 'الأصناف التي تم جردها أو رصد نقص فيها', long: true },
    { key: 'warehouse_notes', label: 'الفروقات أو الملاحظات المخزنية وأسبابها', long: true },
  ] },
  warehouse_worker: { title: 'التقرير اليومي لعمال التحميل', fields: [
    { key: 'prepared_orders', label: 'عدد الطلبات والطرود التي تم تجهيزها أو تحميلها' },
    { key: 'damage_status', label: 'حالة التلف أو الكسر إن وجدت', long: true },
    { key: 'warehouse_organization', label: 'ملاحظات تنظيم المستودع وأسباب أي تأخير', long: true },
  ] },
  admin_followup: { title: 'تقرير المتابعة التنفيذية اليومي', fields: [
    { key: 'team_commitment', label: 'ملخص التزام الفروع والفرق بالمهام اليومية', long: true },
    { key: 'delays_priorities', label: 'أبرز التأخيرات أو حالات تعارض الأولويات ومعالجتها', long: true },
    { key: 'management_recommendations', label: 'التوصيات المرفوعة للإدارة', long: true },
  ] },
  owner: { title: 'ملخص الاعتمادات والقرارات الإدارية', fields: [
    { key: 'daily_decisions', label: 'ملخص القرارات والاعتمادات المتخذة اليوم', long: true },
    { key: 'performance_notes', label: 'ملاحظات الإدارة على الأداء والمؤشرات', long: true },
  ] },
};

export function roleReportConfig(roleCode: string) {
  return roleReportConfigs[roleCode] ?? roleReportConfigs.accountant;
}
function db() { if (!supabase) throw new Error('supabase_not_configured'); return supabase; }

export async function listMyRoleReports(roleCode: string, branchId: string | null = null): Promise<RoleReport[]> {
  let query = db().from('employee_role_reports').select('id,organization_id,employee_user_id,role_code,branch_id,report_date,report_title,values,status,submitted_at,review_note').eq('role_code', roleCode).order('report_date', { ascending: false }).limit(30);
  query = branchId ? query.eq('branch_id', branchId) : query.is('branch_id', null);
  const { data, error } = await query;
  if (error) throw error;
  return (data ?? []) as RoleReport[];
}

export async function submitEmployeeRoleReport(input: { roleCode: string; branchId: string | null; reportDate: string; reportTitle: string; values: Record<string, string> }) {
  const { data, error } = await db().rpc('mobile_submit_employee_role_report', { p_role_code: input.roleCode, p_branch_id: input.branchId, p_report_date: input.reportDate, p_report_title: input.reportTitle, p_values: input.values });
  if (error) throw error;
  return data;
}

export async function reviewEmployeeRoleReport(reportId: string, decision: 'approved' | 'returned', note: string | null) {
  const { data, error } = await db().rpc('review_employee_role_report', { p_report_id: reportId, p_decision: decision, p_note: note });
  if (error) throw error;
  return data;
}
