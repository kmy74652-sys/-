import { supabase } from './supabase';

export type DesignerFieldType = 'short_text' | 'long_text' | 'integer' | 'quantity' | 'money' | 'datetime' | 'select' | 'multiselect' | 'boolean' | 'table' | 'image' | 'file' | 'signature' | 'calculated' | 'decision_notes';
export type DesignerField = {
  field_key: string;
  label: string;
  description: string;
  field_type: DesignerFieldType;
  is_required: boolean;
  repeatable: boolean;
  sort_order: number;
  options: string[];
  validation: Record<string, unknown>;
  config: Record<string, unknown>;
};
export type ReportTemplate = { id: string; code: string; title: string; description: string | null; role_code: string; is_active: boolean; created_by?: string; updated_by?: string | null; created_at?: string; updated_at?: string };
export type ReportVersion = { id: string; template_id: string; version_no: number; status: string; report_required: boolean };

function client() { if (!supabase) throw new Error('supabase_not_configured'); return supabase; }
async function userAndOrganization() {
  const db = client();
  const { data: auth, error: authError } = await db.auth.getUser();
  if (authError || !auth.user) throw authError ?? new Error('not_authenticated');
  const { data: membership, error } = await db.from('organization_memberships').select('organization_id').eq('user_id', auth.user.id).eq('is_active', true).limit(1).single();
  if (error) throw error;
  return { db, userId: auth.user.id, organizationId: membership.organization_id as string };
}
export async function listDesignerTemplates() {
  const { db } = await userAndOrganization();
  const { data, error } = await db.from('report_form_templates').select('id,code,title,description,role_code,is_active,created_by,updated_by,created_at,updated_at').eq('is_active', true).order('title').limit(100);
  if (error) throw error;
  return (data ?? []) as ReportTemplate[];
}
export async function getLatestDesignerVersion(templateId: string) {
  const { db } = await userAndOrganization();
  const { data: version, error } = await db.from('report_form_versions').select('id,template_id,version_no,status,report_required').eq('template_id', templateId).order('version_no', { ascending: false }).limit(1).single();
  if (error) throw error;
  const { data: fields, error: fieldsError } = await db.from('report_form_version_fields').select('field_key,label,description,field_type,is_required,repeatable,sort_order,options,validation,config').eq('version_id', version.id).order('sort_order').limit(200);
  if (fieldsError) throw fieldsError;
  return { version: version as ReportVersion, fields: (fields ?? []) as DesignerField[] };
}
export async function saveDesignerTemplate(input: { templateId?: string; title: string; description: string; roleCode: string; fields: DesignerField[]; reportRequired: boolean }) {
  const { db, userId, organizationId } = await userAndOrganization();
  const title = input.title.trim();
  if (title.length < 2 || input.fields.length === 0) throw new Error('designer_title_and_fields_required');
  let templateId = input.templateId;
  if (!templateId) {
    const code = `form_${Date.now().toString(36)}`;
    const { data, error } = await db.from('report_form_templates').insert({ organization_id: organizationId, code, title, description: input.description.trim() || null, role_code: input.roleCode, created_by: userId, updated_by: userId }).select('id').single();
    if (error) throw error;
    templateId = data.id;
  } else {
    const { error } = await db.from('report_form_templates').update({ title, description: input.description.trim() || null, role_code: input.roleCode, updated_by: userId, updated_at: new Date().toISOString() }).eq('id', templateId);
    if (error) throw error;
  }
  const { data: latest } = await db.from('report_form_versions').select('version_no').eq('template_id', templateId).order('version_no', { ascending: false }).limit(1).maybeSingle();
  const { data: version, error: versionError } = await db.from('report_form_versions').insert({ template_id: templateId, version_no: (latest?.version_no ?? 0) + 1, status: 'draft', report_required: input.reportRequired, created_by: userId }).select('id').single();
  if (versionError) throw versionError;
  const rows = input.fields.map((field, index) => ({ version_id: version.id, field_key: field.field_key || `field_${index + 1}`, label: field.label.trim(), description: field.description?.trim() || null, field_type: field.field_type, is_required: field.is_required, repeatable: field.repeatable, sort_order: index, options: field.options ?? [], validation: field.validation ?? {}, config: field.config ?? {} }));
  const { error: fieldsError } = await db.from('report_form_version_fields').insert(rows);
  if (fieldsError) throw fieldsError;
  return { templateId, versionId: version.id };
}
export async function publishDesignerVersion(taskId: string, templateId: string, versionId: string, reportRequired: boolean) {
  const { data, error } = await client().rpc('publish_task_report_form', { p_task_id: taskId, p_template_id: templateId, p_version_id: versionId, p_report_required: reportRequired });
  if (error) throw error;
  return data as string;
}
export async function approveDesignerVersion(versionId: string) {
  const { data, error } = await client().rpc('approve_report_form_version', { p_version_id: versionId });
  if (error) throw error;
  return data as string;
}
export const designerFieldTypes: Array<[DesignerFieldType, string]> = [
  ['short_text', 'نص قصير'], ['long_text', 'نص طويل وملاحظات'], ['integer', 'رقم صحيح'], ['quantity', 'كمية ووحدة قياس'], ['money', 'مبلغ وعملة'], ['datetime', 'تاريخ ووقت'], ['select', 'قائمة اختيار'], ['multiselect', 'اختيار متعدد'], ['boolean', 'نعم أو لا'], ['table', 'جدول متعدد الصفوف'], ['image', 'صورة'], ['file', 'ملف أو مستند'], ['signature', 'توقيع أو إقرار'], ['calculated', 'حقل محسوب'], ['decision_notes', 'ملاحظات وقرارات'],
];
