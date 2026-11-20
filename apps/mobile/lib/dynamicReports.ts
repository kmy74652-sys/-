import { supabase } from './supabase';
import type { ReportField } from './reportSchema';

export type DynamicEmployeeReport = {
  template_id: string;
  version_id: string;
  title: string;
  description: string | null;
  role_code: string;
  report_date: string;
  status: 'submitted' | 'approved' | 'returned' | null;
  review_note: string | null;
  values: Record<string, unknown>;
  fields: ReportField[];
};

function client() {
  if (!supabase) throw new Error('supabase_not_configured');
  return supabase;
}

export async function listMyDynamicReports(): Promise<DynamicEmployeeReport[]> {
  const { data, error } = await client().rpc('list_my_dynamic_report_forms');
  if (error) throw error;
  return (Array.isArray(data) ? data : []) as DynamicEmployeeReport[];
}

export async function submitMyDynamicReport(input: {
  templateId: string;
  versionId: string;
  reportDate: string;
  branchId: string | null;
  values: Record<string, unknown>;
}) {
  const { data, error } = await client().rpc('submit_my_dynamic_report', {
    p_template_id: input.templateId,
    p_version_id: input.versionId,
    p_report_date: input.reportDate,
    p_values: input.values,
    p_branch_id: input.branchId,
  });
  if (error) throw error;
  return data as string;
}
