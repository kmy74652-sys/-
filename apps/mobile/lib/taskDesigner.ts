import { supabase } from './supabase';
import type { TaskCategory, TaskReportSelection, TaskTemplateDraft } from '../components/TaskDesigner';
import { approveDesignerVersion, saveDesignerTemplate, type ReportTemplate } from './reportDesigner';

export type TaskCategoryRow = { id: string; code: TaskCategory; title: string; parent_id: string | null; is_main: boolean; active: boolean };
export type StoredTaskTemplate = TaskTemplateDraft & { categoryId: string; subcategoryId: string | null; version: number; code: string };

// These records came from the old operational starter catalog. They remain in the
// database only for historical task references and must never appear as designer content.
const retiredStarterTemplateCodes = new Set([
  'acct_daily_close', 'acct_sales_collection', 'acct_returns_reconciliation', 'acct_debts_followup', 'acct_purchase_review',
  'wh_receive_goods', 'wh_issue_goods', 'wh_cycle_count', 'wh_stock_movement_review',
  'load_order_preparation', 'load_delivery_handover', 'admin_daily_branch_followup',
  'admin_weekly_consolidated_report', 'admin_supplier_followup', 'owner_final_review', 'owner_monthly_business_review',
]);

function client() { if (!supabase) throw new Error('supabase_not_configured'); return supabase; }

async function managementOrganization(requiredPermission: 'task_library.read' | 'task_library.manage' = 'task_library.manage') {
  const db = client();
  const { data: auth, error: authError } = await db.auth.getUser();
  if (authError || !auth.user) throw authError ?? new Error('not_authenticated');
  const { data: memberships, error } = await db.from('organization_memberships')
    .select('organization_id').eq('user_id', auth.user.id).eq('is_active', true).order('created_at').limit(20);
  if (error) throw error;
  for (const membership of memberships ?? []) {
    const { data: allowed, error: allowedError } = await db.rpc('task_library_allowed_for_org', { p_organization_id: membership.organization_id, p_required_permission: requiredPermission });
    if (allowedError) throw allowedError;
    if (allowed === true) return { db, organizationId: membership.organization_id as string };
  }
  throw new Error('permission_denied');
}

export async function listTaskDesignerCategories() {
  const { db, organizationId } = await managementOrganization('task_library.manage');
  const { data, error } = await db.from('task_categories')
    .select('id,code,title,parent_id,is_main,active').eq('organization_id', organizationId).eq('active', true).order('title').limit(200);
  if (error) throw error;
  return (data ?? []) as TaskCategoryRow[];
}

export async function listTaskDesignerTemplates(): Promise<StoredTaskTemplate[]> {
  const { db, organizationId } = await managementOrganization('task_library.manage');
  const [templatesResult, categoriesResult] = await Promise.all([
    db.from('task_templates').select('id,code,title,description,instructions,role_code,default_priority,default_duration_minutes,is_active,version,category_id,subcategory_id')
      .eq('organization_id', organizationId).order('title').limit(200),
    db.from('task_categories').select('id,code,title,parent_id,is_main,active')
      .eq('organization_id', organizationId).eq('active', true).limit(200),
  ]);
  if (templatesResult.error) throw templatesResult.error;
  if (categoriesResult.error) throw categoriesResult.error;
  const rows = (templatesResult.data ?? []).filter((row) => !retiredStarterTemplateCodes.has(row.code));
  if (!rows.length) return [];
  const ids = rows.map((row) => row.id);
  const [stepsResult, linksResult] = await Promise.all([
    db.from('task_template_steps').select('id,template_id,title,instructions,sort_order,is_required,evidence_required,evidence_instructions').in('template_id', ids).order('sort_order').limit(2000),
    db.from('task_template_report_forms').select('id,template_id,version_id,sort_order,is_required').in('template_id', ids).order('sort_order').limit(1000),
  ]);
  if (stepsResult.error) throw stepsResult.error;
  if (linksResult.error) throw linksResult.error;
  const versionIds = [...new Set((linksResult.data ?? []).map((row) => row.version_id))];
  const versionResult = versionIds.length ? await db.from('report_form_versions').select('id,template_id,version_no').in('id', versionIds).limit(1000) : { data: [], error: null };
  if (versionResult.error) throw versionResult.error;
  const fieldsResult = versionIds.length ? await db.from('report_form_version_fields').select('version_id,field_key,label,description,field_type,is_required,repeatable,sort_order,options,validation,config').in('version_id', versionIds).order('sort_order').limit(5000) : { data: [], error: null };
  if (fieldsResult.error) throw fieldsResult.error;
  const formTemplateByVersion = new Map((versionResult.data ?? []).map((row) => [row.id, row.template_id]));
  const fieldsByVersion = new Map<string, NonNullable<TaskTemplateDraft['reportFields']>>();
  for (const row of fieldsResult.data ?? []) fieldsByVersion.set(row.version_id, [...(fieldsByVersion.get(row.version_id) ?? []), {
    field_key: row.field_key, label: row.label, description: row.description ?? '', field_type: row.field_type,
    is_required: row.is_required, repeatable: row.repeatable, sort_order: row.sort_order, options: row.options ?? [],
    validation: row.validation ?? {}, config: row.config ?? {},
  }]);
  const categoryById = new Map((categoriesResult.data ?? []).map((row) => [row.id, row]));
  const stepsByTemplate = new Map<string, NonNullable<TaskTemplateDraft['steps']>>();
  for (const row of stepsResult.data ?? []) stepsByTemplate.set(row.template_id, [...(stepsByTemplate.get(row.template_id) ?? []), {
    id: row.id, title: row.title, instructions: row.instructions ?? '', required: row.is_required,
    evidenceRequired: row.evidence_required, evidenceInstructions: row.evidence_instructions ?? '',
  }]);
  const reportsByTemplate = new Map<string, TaskReportSelection[]>();
  for (const row of linksResult.data ?? []) {
    const reportTemplateId = formTemplateByVersion.get(row.version_id);
    if (!reportTemplateId) continue;
    reportsByTemplate.set(row.template_id, [...(reportsByTemplate.get(row.template_id) ?? []), {
      reportTemplateId, approvedVersionId: row.version_id, required: row.is_required,
    }]);
  }
  // The legacy task designer is retired. Only organizational schedules enter
  // the management and assignment UI.
  return rows.map((row) => {
    const mainCategory = categoryById.get(row.category_id);
    const subcategory = row.subcategory_id ? categoryById.get(row.subcategory_id) : undefined;
    return {
      id: row.id, code: row.code, version: row.version, categoryId: row.category_id,
      subcategoryId: row.subcategory_id, category: (mainCategory?.code ?? 'other') as TaskCategory,
      subcategory: subcategory?.title ?? '', customSubcategory: subcategory?.title ?? '',
      title: row.title, description: row.description ?? '', instructions: row.instructions ?? '',
      roleCode: row.role_code as TaskTemplateDraft['roleCode'],
      priority: row.default_priority as TaskTemplateDraft['priority'],
      expectedDurationMinutes: row.default_duration_minutes,
      steps: stepsByTemplate.get(row.id) ?? [], reports: reportsByTemplate.get(row.id) ?? [],
      reportFields: (() => { const first = reportsByTemplate.get(row.id)?.[0]; return first ? fieldsByVersion.get(first.approvedVersionId) ?? [] : []; })(),
      reportRequired: reportsByTemplate.get(row.id)?.some((item) => item.required) ?? true, isActive: row.is_active,
    };
  }).filter((row) => row.category === 'admin' && row.subcategory === 'الدوام والمهام اليومية');
}

async function ensureSubcategory(categoryId: string, title: string) {
  const { db, organizationId } = await managementOrganization('task_library.manage');
  const clean = title.trim();
  if (!clean) return null;
  const { data: existing, error } = await db.from('task_categories').select('id')
    .eq('organization_id', organizationId).eq('parent_id', categoryId).eq('title', clean).eq('active', true).limit(1).maybeSingle();
  if (error) throw error;
  if (existing?.id) return existing.id as string;
  const suffix = Math.random().toString(36).slice(2, 12);
  const { data, error: insertError } = await db.from('task_categories').insert({
    organization_id: organizationId, code: `sub_${suffix}`, title: clean, parent_id: categoryId, is_main: false,
  }).select('id').single();
  if (insertError) throw insertError;
  return data.id as string;
}

export async function saveTaskDesignerTemplate(draft: TaskTemplateDraft, categories: TaskCategoryRow[]) {
  const { db, organizationId } = await managementOrganization('task_library.manage');
  if (draft.category !== 'admin' || draft.subcategory.trim() !== 'الدوام والمهام اليومية') throw new Error('organizational_schedule_only');
  const title = draft.title.trim();
  if (title.length < 2 || title.length > 200) throw new Error('task_template_title_invalid');
  if (draft.steps.some((step) => !step.title.trim())) throw new Error('task_step_title_required');
  const main = categories.find((category) => category.is_main && category.code === draft.category);
  if (!main) throw new Error('task_category_not_found');
  const subcategoryId = await ensureSubcategory(main.id, draft.subcategory);
  let reportForms = draft.reports;
  if (draft.reportFields.length > 0) {
    const reportDraft = await saveDesignerTemplate({
      templateId: draft.reports[0]?.reportTemplateId,
      title: `${title} — تقرير التنفيذ`, description: draft.description, roleCode: draft.roleCode,
      fields: draft.reportFields, reportRequired: draft.reportRequired,
    });
    try {
      await approveDesignerVersion(reportDraft.versionId);
    } catch (cause) {
      const message = cause instanceof Error ? cause.message : String(cause);
      if (message.includes('owner_approval_required')) throw new Error('report_requires_owner_approval');
      throw cause;
    }
    reportForms = [{ reportTemplateId: reportDraft.templateId, approvedVersionId: reportDraft.versionId, required: draft.reportRequired }];
  }
  const payload = {
    title, description: draft.description.trim() || null, instructions: draft.instructions.trim() || null,
    role_code: draft.roleCode, task_type: 'administrative',
    default_priority: draft.priority, default_duration_minutes: draft.expectedDurationMinutes,
    category_id: main.id, subcategory_id: subcategoryId, is_active: draft.isActive,
    steps: draft.steps.map((step, sort_order) => ({ title: step.title.trim(), instructions: step.instructions.trim() || null, sort_order, is_required: step.required, evidence_required: step.evidenceRequired, evidence_instructions: step.evidenceInstructions.trim() || null })),
    report_forms: reportForms.map((report, sort_order) => ({ version_id: report.approvedVersionId, required: report.required, sort_order })),
  };
  const { data, error } = await db.rpc('save_task_designer_template', { p_organization_id: organizationId, p_template_id: draft.id ?? null, p_payload: payload });
  if (error) throw error;
  return { templateId: data as string, reports: reportForms };
}

export async function setTaskDesignerTemplateActive(templateId: string, isActive: boolean) {
  const { db, organizationId } = await managementOrganization('task_library.manage');
  const { error } = await db.from('task_templates').update({ is_active: isActive }).eq('id', templateId).eq('organization_id', organizationId);
  if (error) throw error;
}

export async function deleteTaskDesignerTemplate(templateId: string) {
  const { db, organizationId } = await managementOrganization('task_library.manage');
  const { error } = await db.rpc('delete_task_designer_template', {
    p_organization_id: organizationId,
    p_template_id: templateId,
  });
  if (error) throw error;
}

export async function assignTaskFromTemplate(input: {
  templateId: string; assignedTo: string; branchId: string | null; startsAt: string; dueAt: string;
  priority?: TaskTemplateDraft['priority']; instructions?: string; reportOverrides?: Array<{ approvedVersionId: string; required: boolean }>;
}) {
  const { db, organizationId } = await managementOrganization('task_library.manage');
  if (new Date(input.dueAt).getTime() < new Date(input.startsAt).getTime()) throw new Error('invalid_task_schedule');
  const { data, error } = await db.rpc('assign_task_from_template', {
    p_organization_id: organizationId, p_template_id: input.templateId, p_assigned_to: input.assignedTo,
    p_branch_id: input.branchId, p_starts_at: input.startsAt, p_due_at: input.dueAt,
    p_priority: input.priority ?? null, p_instructions: input.instructions?.trim() || null,
    p_report_overrides: input.reportOverrides ?? [],
  });
  if (error) throw error;
  return data as string;
}

export async function listApprovedTaskReportForms(): Promise<ReportTemplate[]> {
  const { db, organizationId } = await managementOrganization('task_library.manage');
  const { data, error } = await db.rpc('list_task_library_report_forms', { p_organization_id: organizationId });
  if (error) throw error;
  return (data ?? []) as ReportTemplate[];
}
