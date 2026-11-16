import { supabase } from './supabase';
import { validateDesignerFields, type DesignerField } from './reportSchema';
export type { DesignerField } from './reportSchema';

export type DesignerFieldType = DesignerField['field_type'];
export type ReportTemplate = {
  id: string;
  code: string;
  title: string;
  description: string | null;
  role_code: string;
  is_active: boolean;
  created_by?: string;
  updated_by?: string | null;
  created_at?: string;
  updated_at?: string;
  approved_version_id?: string;
  approved_version_no?: number;
};
export type ReportVersion = {
  id: string;
  template_id: string;
  version_no: number;
  status: string;
  report_required: boolean;
  approved_by?: string | null;
  approved_at?: string | null;
};
type VersionFieldRow = DesignerField;

function client() {
  if (!supabase) throw new Error('supabase_not_configured');
  return supabase;
}
async function userAndOrganization() {
  const db = client();
  const { data: auth, error: authError } = await db.auth.getUser();
  if (authError || !auth.user) throw authError ?? new Error('not_authenticated');
  const { data: memberships, error } = await db.from('organization_memberships')
    .select('organization_id').eq('user_id', auth.user.id).eq('is_active', true)
    .order('created_at', { ascending: true }).limit(100);
  if (error) throw error;
  for (const membership of memberships ?? []) {
    const { data: allowed, error: permissionError } = await db.rpc('report_designer_allowed_for_org', { p_organization_id: membership.organization_id });
    if (permissionError) throw permissionError;
    if (allowed === true) return { db, userId: auth.user.id, organizationId: membership.organization_id as string };
  }
  throw new Error('permission_denied');
}
async function readVersionFields(db: ReturnType<typeof client>, versionId: string) {
  const { data, error } = await db.from('report_form_version_fields')
    .select('field_key,label,description,field_type,is_required,repeatable,sort_order,options,validation,config')
    .eq('version_id', versionId).order('sort_order').limit(200);
  if (error) throw error;
  return (data ?? []) as VersionFieldRow[];
}
export async function listDesignerTemplates(): Promise<ReportTemplate[]> {
  const { db, organizationId } = await userAndOrganization();
  const { data, error } = await db.from('report_form_templates')
    .select('id,code,title,description,role_code,is_active,created_by,updated_by,created_at,updated_at')
    .eq('organization_id', organizationId).eq('is_active', true).order('title').limit(100);
  if (error) throw error;
  return (data ?? []) as ReportTemplate[];
}
export async function listApprovedDesignerTemplates(): Promise<ReportTemplate[]> {
  const { db, organizationId } = await userAndOrganization();
  const { data: templates, error } = await db.from('report_form_templates')
    .select('id,code,title,description,role_code,is_active,created_by,updated_by,created_at,updated_at')
    .eq('organization_id', organizationId).eq('is_active', true).order('title').limit(100);
  if (error) throw error;
  if (!templates?.length) return [];
  const { data: versions, error: versionsError } = await db.from('report_form_versions')
    .select('id,template_id,version_no,status,report_required,approved_by,approved_at')
    .in('template_id', templates.map((template) => template.id)).eq('status', 'published')
    .not('approved_by', 'is', null).not('approved_at', 'is', null)
    .order('version_no', { ascending: false }).limit(500);
  if (versionsError) throw versionsError;
  const latestByTemplate = new Map<string, { id: string; version_no: number }>();
  for (const version of versions ?? []) {
    if (!latestByTemplate.has(version.template_id)) latestByTemplate.set(version.template_id, { id: version.id, version_no: version.version_no });
  }
  return (templates ?? []).flatMap((template) => {
    const approved = latestByTemplate.get(template.id);
    return approved ? [{ ...template, approved_version_id: approved.id, approved_version_no: approved.version_no } as ReportTemplate] : [];
  });
}
export async function getLatestDesignerVersion(templateId: string) {
  const { db } = await userAndOrganization();
  const { data: version, error } = await db.from('report_form_versions')
    .select('id,template_id,version_no,status,report_required,approved_by,approved_at')
    .eq('template_id', templateId).order('version_no', { ascending: false }).limit(1).single();
  if (error) throw error;
  return { version: version as ReportVersion, fields: await readVersionFields(db, version.id) };
}
export async function getLatestApprovedDesignerVersion(templateId: string) {
  const { db } = await userAndOrganization();
  const { data: version, error } = await db.from('report_form_versions')
    .select('id,template_id,version_no,status,report_required,approved_by,approved_at')
    .eq('template_id', templateId).eq('status', 'published')
    .not('approved_by', 'is', null).not('approved_at', 'is', null)
    .order('version_no', { ascending: false }).limit(1).single();
  if (error) throw error;
  return { version: version as ReportVersion, fields: await readVersionFields(db, version.id) };
}
export async function saveDesignerTemplate(input: { templateId?: string; title: string; description: string; roleCode: string; fields: DesignerField[]; reportRequired: boolean }) {
  const { db, organizationId } = await userAndOrganization();
  const title = input.title.trim();
  if (title.length < 2 || title.length > 160) throw new Error('designer_title_invalid');
  const fieldIssue = validateDesignerFields(input.fields);
  if (fieldIssue) throw new Error(fieldIssue);
  const fields = input.fields.map((field, index) => ({
    field_key: field.field_key.trim(), label: field.label.trim(), description: field.description?.trim() || null,
    field_type: field.field_type, is_required: Boolean(field.is_required), repeatable: Boolean(field.repeatable),
    sort_order: index, options: field.options ?? [], validation: field.validation ?? {}, config: field.config ?? {},
  }));
  const { data, error } = await db.rpc('save_report_form_draft', {
    p_organization_id: organizationId,
    p_template_id: input.templateId ?? null,
    p_title: title,
    p_description: input.description.trim() || null,
    p_role_code: input.roleCode,
    p_fields: fields,
    p_report_required: input.reportRequired,
  });
  if (error) throw error;
  const saved = data as { template_id?: string; version_id?: string } | null;
  if (!saved?.template_id || !saved.version_id) throw new Error('designer_save_response_invalid');
  return { templateId: saved.template_id, versionId: saved.version_id };
}
export async function publishDesignerVersion(taskId: string, templateId: string, versionId: string, reportRequired: boolean) {
  const { data, error } = await client().rpc('publish_task_report_form', {
    p_task_id: taskId, p_template_id: templateId, p_version_id: versionId, p_report_required: reportRequired,
  });
  if (error) throw error;
  return data as string;
}
export async function approveDesignerVersion(versionId: string) {
  const { data, error } = await client().rpc('approve_report_form_version', { p_version_id: versionId });
  if (error) throw error;
  return data as string;
}
export const designerFieldTypes: Array<[DesignerFieldType, string]> = [
  ['short_text', 'نص قصير'], ['long_text', 'نص طويل وملاحظات'], ['integer', 'رقم صحيح'], ['quantity', 'كمية ووحدة قياس'],
  ['money', 'مبلغ وعملة'], ['datetime', 'تاريخ ووقت'], ['select', 'قائمة اختيار'], ['multiselect', 'اختيار متعدد'],
  ['boolean', 'نعم أو لا'], ['table', 'جدول متعدد الصفوف'], ['image', 'صورة'], ['file', 'ملف أو مستند'],
  ['signature', 'توقيع أو إقرار'], ['calculated', 'حقل محسوب'], ['decision_notes', 'ملاحظات وقرارات'],
];
