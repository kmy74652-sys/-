import { useEffect, useMemo, useState } from 'react';
import { supabase } from './lib/supabase';

type Role = 'owner' | 'admin_followup' | 'accountant' | 'warehouse_keeper' | 'warehouse_worker';
type FieldType = 'short_text' | 'long_text' | 'integer' | 'quantity' | 'money' | 'datetime' | 'select' | 'multiselect' | 'boolean' | 'table' | 'image' | 'file' | 'signature' | 'calculated' | 'decision_notes';
type ColumnType = 'short_text' | 'long_text' | 'integer' | 'quantity' | 'money' | 'select' | 'boolean';
type Field = { field_key: string; label: string; description: string | null; field_type: FieldType; is_required: boolean; repeatable: boolean; sort_order: number; options: string[]; validation: Record<string, unknown>; config: Record<string, unknown> };
type TableColumn = { key: string; label: string; type: ColumnType; required: boolean; options: string[]; validation: Record<string, unknown> };
type Template = { id: string; title: string; description: string | null; role_code: Role; updated_at: string };

const roles: Array<[Role, string]> = [['owner', 'صاحب المؤسسة'], ['admin_followup', 'المدير التنفيذي'], ['accountant', 'المحاسب'], ['warehouse_keeper', 'أمين المخازن'], ['warehouse_worker', 'عمال التحميل']];
const fieldTypes: Array<[FieldType, string]> = [['short_text', 'نص قصير'], ['long_text', 'نص طويل'], ['integer', 'رقم صحيح'], ['quantity', 'كمية ووحدة'], ['money', 'مبلغ وعملة'], ['datetime', 'تاريخ ووقت'], ['select', 'قائمة اختيار'], ['multiselect', 'اختيار متعدد'], ['boolean', 'نعم أو لا'], ['table', 'جدول متعدد الصفوف'], ['image', 'صورة'], ['file', 'مستند'], ['signature', 'إقرار وتوقيع'], ['calculated', 'حقل محسوب'], ['decision_notes', 'ملاحظات وقرارات']];
const columnTypes: Array<[ColumnType, string]> = [['short_text', 'نص قصير'], ['long_text', 'نص طويل'], ['integer', 'رقم صحيح'], ['quantity', 'كمية'], ['money', 'مبلغ'], ['select', 'قائمة'], ['boolean', 'نعم أو لا']];
const fieldLabel = (type: FieldType) => fieldTypes.find(([code]) => code === type)?.[1] ?? type;
const blankField = (index: number): Field => ({ field_key: `field_${index + 1}`, label: '', description: '', field_type: 'short_text', is_required: false, repeatable: false, sort_order: index, options: [], validation: {}, config: {} });
const asObject = (value: unknown): Record<string, unknown> => value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : {};

function errorMessage(error: unknown): string {
  const message = String((error as { message?: string } | null)?.message ?? '');
  const translations: Array<[string, string]> = [
    ['permission_denied', 'لا يملك هذا الحساب صلاحية إدارة نماذج التقارير.'],
    ['report_field_label_required', 'اسم الحقل مطلوب ولا يمكن أن يكون فارغًا.'],
    ['invalid_report_field_key', 'مفتاح الحقل غير صالح؛ استخدم حروفًا إنجليزية صغيرة وأرقامًا وشرطة سفلية.'],
    ['duplicate_report_field_key', 'توجد مفاتيح حقول مكررة.'],
    ['report_field_options_required', 'أضف خيارًا واحدًا على الأقل لهذا الحقل.'],
    ['invalid_report_field_validation', 'تحقق من قواعد الحد الأدنى والأقصى والمنازل العشرية.'],
    ['invalid_report_table_column', 'تحقق من مفاتيح أعمدة الجدول.'],
    ['report_table_columns_missing', 'أضف عمودًا واحدًا على الأقل إلى الجدول.'],
    ['report_table_min_rows', 'عدد صفوف الجدول أقل من الحد الأدنى المطلوب.'],
    ['report_table_max_rows', 'عدد صفوف الجدول يتجاوز الحد الأقصى.'],
    ['invalid_calculated_report_formula', 'صيغة الحساب غير صالحة. استخدم + و- و* و/ ومفاتيح الحقول بين أقواس معقوفة.'],
    ['report_calculated_division_by_zero', 'لا يمكن القسمة على صفر.'],
    ['report_form_version_requires_approval', 'اعتمد الإصدار من صاحب المؤسسة قبل ربطه بمهمة.'],
    ['report_form_version_immutable', 'الإصدار محفوظ؛ أنشئ إصدارًا جديدًا بدل تعديل إصدار منشور.'],
    ['owner_approval_required', 'اعتماد الإصدار متاح لصاحب المؤسسة فقط.'],
  ];
  return translations.find(([token]) => message.includes(token))?.[1] ?? (message || 'تعذر تنفيذ العملية. تحقق من الاتصال والصلاحيات.');
}

function normalizeColumns(field: Field): TableColumn[] {
  const raw = field.config.columns;
  if (!Array.isArray(raw)) return [];
  return raw.map((item, index) => {
    if (typeof item === 'string') return { key: item, label: item, type: 'short_text', required: false, options: [], validation: {} };
    const column = asObject(item);
    const rawType = String(column.type ?? column.field_type ?? 'short_text') as ColumnType;
    return {
      key: String(column.key ?? `column_${index + 1}`), label: String(column.label ?? column.name ?? ''),
      type: columnTypes.some(([code]) => code === rawType) ? rawType : 'short_text',
      required: Boolean(column.required ?? column.is_required),
      options: Array.isArray(column.options) ? column.options.map(String) : [],
      validation: asObject(column.validation),
    };
  });
}

function OptionsEditor({ options, onChange }: { options: string[]; onChange: (options: string[]) => void }) {
  const [newOption, setNewOption] = useState('');
  function move(index: number, offset: number) {
    const target = index + offset;
    if (target < 0 || target >= options.length) return;
    const next = [...options]; [next[index], next[target]] = [next[target], next[index]]; onChange(next);
  }
  return <div className="option-editor">
    {options.map((option, index) => <div className="option-row" key={`${index}-${option}`}>
      <input aria-label={`الخيار ${index + 1}`} value={option} onChange={(event) => onChange(options.map((item, i) => i === index ? event.target.value : item))} />
      <div className="row-actions">
        <button type="button" className="text-button" aria-label="تحريك لأعلى" disabled={index === 0} onClick={() => move(index, -1)}>↑</button>
        <button type="button" className="text-button" aria-label="تحريك لأسفل" disabled={index === options.length - 1} onClick={() => move(index, 1)}>↓</button>
        <button type="button" className="text-button reject" onClick={() => onChange(options.filter((_, i) => i !== index))}>حذف</button>
      </div>
    </div>)}
    <div className="option-add"><input value={newOption} onChange={(event) => setNewOption(event.target.value)} placeholder="خيار جديد" onKeyDown={(event) => { if (event.key === 'Enter') { event.preventDefault(); const value = newOption.trim(); if (value) { onChange([...options, value]); setNewOption(''); } } }} /><button type="button" className="text-button" onClick={() => { const value = newOption.trim(); if (value) { onChange([...options, value]); setNewOption(''); } }}>إضافة خيار</button></div>
  </div>;
}

export function ReportDesignerPage({ onBack }: { onBack: () => void }) {
  const [templates, setTemplates] = useState<Template[]>([]);
  const [selected, setSelected] = useState<string>();
  const [activeIndex, setActiveIndex] = useState<number | null>(null);
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [role, setRole] = useState<Role>('admin_followup');
  const [fields, setFields] = useState<Field[]>([]);
  const [required, setRequired] = useState(true);
  const [search, setSearch] = useState('');
  const [roleFilter, setRoleFilter] = useState('all');
  const [notice, setNotice] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [versionId, setVersionId] = useState<string>();

  async function loadTemplates() {
    if (!supabase) throw new Error('supabase_not_configured');
    const { data, error: queryError } = await supabase.from('report_form_templates')
      .select('id,title,description,role_code,updated_at').eq('is_active', true).order('updated_at', { ascending: false }).limit(100);
    if (queryError) throw queryError;
    setTemplates((data ?? []) as Template[]);
  }
  useEffect(() => { void loadTemplates().catch((cause) => setError(errorMessage(cause))); }, []);

  async function openTemplate(template: Template, clone = false) {
    if (!supabase) return;
    setBusy(true); setError(''); setNotice('');
    try {
      const { data: version, error: versionError } = await supabase.from('report_form_versions')
        .select('id,report_required').eq('template_id', template.id).order('version_no', { ascending: false }).limit(1).single();
      if (versionError) throw versionError;
      const { data: loaded, error: fieldsError } = await supabase.from('report_form_version_fields')
        .select('field_key,label,description,field_type,is_required,repeatable,sort_order,options,validation,config')
        .eq('version_id', version.id).order('sort_order').limit(100);
      if (fieldsError) throw fieldsError;
      setSelected(clone ? undefined : template.id);
      setVersionId(version.id);
      setTitle(clone ? `${template.title} — نسخة` : template.title);
      setDescription(template.description ?? '');
      setRole(template.role_code);
      setRequired(version.report_required);
      const rows = (loaded ?? []) as Field[];
      setFields(rows);
      setActiveIndex(rows.length ? 0 : null);
      setNotice(clone ? 'تم نسخ القالب إلى محرر جديد.' : 'تم تحميل أحدث إصدار؛ سيحفظ التعديل إصدارًا جديدًا.');
    } catch (cause) { setError(errorMessage(cause)); }
    finally { setBusy(false); }
  }

  function updateField(index: number, patch: Partial<Field>) {
    setFields((current) => current.map((field, fieldIndex) => fieldIndex === index ? { ...field, ...patch } : field));
  }
  function setFieldOptions(index: number, options: string[]) { updateField(index, { options }); }
  function updateConfig(index: number, key: string, value: unknown) {
    const field = fields[index]; if (!field) return;
    updateField(index, { config: { ...field.config, [key]: value } });
  }
  function updateValidation(index: number, key: string, value: unknown) {
    const field = fields[index]; if (!field) return;
    const validation = { ...field.validation };
    if (value === undefined || value === '') delete validation[key]; else validation[key] = value;
    updateField(index, { validation });
  }
  function moveField(index: number, offset: number) {
    const target = index + offset;
    if (target < 0 || target >= fields.length) return;
    setFields((current) => { const next = [...current]; [next[index], next[target]] = [next[target], next[index]]; return next; });
    setActiveIndex(target);
  }
  function validateBeforeSave(): string | null {
    if (title.trim().length < 2 || title.trim().length > 160) return 'اسم النموذج مطلوب، ويجب أن يكون بين 2 و160 محرفًا.';
    if (!fields.length) return 'أضف حقلًا واحدًا على الأقل إلى النموذج.';
    const keys = new Set<string>();
    for (let i = 0; i < fields.length; i += 1) {
      const field = fields[i]; const label = field.label.trim();
      if (!label) return `أدخل اسمًا واضحًا للحقل ${i + 1}؛ لا يمكن ترك الاسم فارغًا.`;
      if (label.length > 200) return `اسم الحقل «${label.slice(0, 30)}» أطول من 200 محرف.`;
      if (!/^[a-z][a-z0-9_]{0,63}$/.test(field.field_key)) return `مفتاح الحقل «${field.field_key}» غير صالح.`;
      if (keys.has(field.field_key)) return `مفتاح الحقل «${field.field_key}» مكرر.`;
      keys.add(field.field_key);
      if (['select', 'multiselect'].includes(field.field_type)) {
        if (!field.options.length || field.options.some((option) => !option.trim())) return `أضف خيارات صحيحة للحقل «${label}».`;
        if (new Set(field.options.map((option) => option.trim())).size !== field.options.length) return `الخيارات مكررة في الحقل «${label}».`;
        const defaultValue = field.config.default_value;
        if (field.field_type === 'select' && defaultValue !== undefined && !field.options.includes(String(defaultValue))) return `القيمة الافتراضية للحقل «${label}» ليست ضمن الخيارات.`;
        if (field.field_type === 'multiselect' && defaultValue !== undefined && (!Array.isArray(defaultValue) || defaultValue.some((value) => !field.options.includes(String(value))))) return `تحقق من القيم الافتراضية للحقل «${label}».`;
      }
      const min = Number(field.validation.min); const max = Number(field.validation.max);
      if (field.validation.min !== undefined && field.validation.max !== undefined && min > max) return `في «${label}»، الحد الأدنى أكبر من الحد الأقصى.`;
      if (field.field_type === 'table') {
        const columns = normalizeColumns(field);
        if (!columns.length) return `أضف عمودًا واحدًا على الأقل إلى جدول «${label}».`;
        if (columns.length > 20) return `لا يمكن أن يتجاوز جدول «${label}» 20 عمودًا.`;
        const columnKeys = new Set<string>();
        for (const column of columns) {
          if (!column.label.trim() || !column.key.trim() || column.key.length > 128) return `تحقق من مفتاح واسم العمود في جدول «${label}».`;
          if (columnKeys.has(column.key)) return `مفتاح العمود «${column.key}» مكرر في «${label}».`;
          columnKeys.add(column.key);
          if (column.type === 'select' && (!column.options.length || column.options.some((option) => !option.trim()))) return `أضف خيارات لعمود «${column.label}».`;
          const columnMin = Number(column.validation.min); const columnMax = Number(column.validation.max);
          if (column.validation.min !== undefined && column.validation.max !== undefined && columnMin > columnMax) return `الحد الأدنى أكبر من الأقصى في عمود «${column.label}».`;
        }
        const minRows = Number(field.config.min_rows); const maxRows = Number(field.config.max_rows);
        if (field.config.min_rows !== undefined && field.config.max_rows !== undefined && minRows > maxRows) return `عدد الصفوف الأدنى أكبر من الأقصى في «${label}».`;
        if ((field.config.min_rows !== undefined && (!Number.isInteger(minRows) || minRows < 0 || minRows > 500)) || (field.config.max_rows !== undefined && (!Number.isInteger(maxRows) || maxRows < 1 || maxRows > 500))) return `حدود صفوف «${label}» يجب أن تكون أعدادًا صحيحة حتى 500.`;
      }
      if (field.field_type === 'calculated' && !String(field.config.formula ?? '').trim()) return `أدخل صيغة الحقل المحسوب «${label}».`;
    }
    return null;
  }

  async function findManagedOrganization(userId: string): Promise<string> {
    if (!supabase) throw new Error('supabase_not_configured');
    const { data: memberships, error: membershipError } = await supabase.from('organization_memberships')
      .select('organization_id').eq('user_id', userId).eq('is_active', true).order('created_at').limit(100);
    if (membershipError) throw membershipError;
    for (const membership of memberships ?? []) {
      const { data: allowed, error: permissionError } = await supabase.rpc('report_designer_allowed_for_org', { p_organization_id: membership.organization_id });
      if (permissionError) throw permissionError;
      if (allowed === true) return membership.organization_id;
    }
    throw new Error('permission_denied');
  }

  async function save() {
    if (!supabase) return;
    const issue = validateBeforeSave();
    if (issue) { setError(issue); return; }
    setBusy(true); setError(''); setNotice('');
    try {
      const { data: auth, error: authError } = await supabase.auth.getUser();
      if (authError || !auth.user) throw authError ?? new Error('not_authenticated');
      const organizationId = await findManagedOrganization(auth.user.id);
      const payload = fields.map((field, index) => ({
        field_key: field.field_key.trim(), label: field.label.trim(), description: field.description?.trim() || null,
        field_type: field.field_type, is_required: Boolean(field.is_required), repeatable: Boolean(field.repeatable),
        sort_order: index, options: field.options.map((option) => option.trim()), validation: field.validation, config: field.config,
      }));
      const { data, error: saveError } = await supabase.rpc('save_report_form_draft', {
        p_organization_id: organizationId, p_template_id: selected ?? null, p_title: title.trim(),
        p_description: description.trim() || null, p_role_code: role, p_fields: payload, p_report_required: required,
      });
      if (saveError) throw saveError;
      const result = data as { template_id?: string; version_id?: string } | null;
      if (!result?.template_id || !result.version_id) throw new Error('استجابة حفظ النموذج غير مكتملة.');
      setSelected(result.template_id); setVersionId(result.version_id); setActiveIndex(fields.length ? 0 : null);
      setNotice('حُفظ إصدار جديد كمسودة؛ لا يؤثر في النماذج المرتبطة بمهام سابقة.');
      await loadTemplates();
    } catch (cause) { setError(errorMessage(cause)); }
    finally { setBusy(false); }
  }

  async function approve() {
    if (!supabase || !versionId) return;
    setBusy(true); setError(''); setNotice('');
    try {
      const { error: approveError } = await supabase.rpc('approve_report_form_version', { p_version_id: versionId });
      if (approveError) throw approveError;
      setNotice('تم اعتماد الإصدار؛ يمكن ربطه بالمهام الجديدة فقط.');
      await loadTemplates();
    } catch (cause) { setError(errorMessage(cause)); }
    finally { setBusy(false); }
  }

  const visible = useMemo(() => templates.filter((template) =>
    (roleFilter === 'all' || template.role_code === roleFilter) &&
    `${template.title} ${template.description ?? ''}`.toLocaleLowerCase('ar').includes(search.toLocaleLowerCase('ar')),
  ), [templates, roleFilter, search]);
  const activeField = activeIndex === null ? null : fields[activeIndex] ?? null;
  const activeColumns = activeField?.field_type === 'table' ? normalizeColumns(activeField) : [];

  return <main className="shell">
    <aside className="sidebar"><div className="brand-mark">ش</div><p className="eyebrow">إدارة النماذج</p><h1>مصمم التقارير</h1><nav><button className="text-button" onClick={onBack}>العودة إلى اللوحة</button></nav></aside>
    <section className="workspace">
      <header className="topbar"><div><p className="eyebrow">إصدارات معتمدة ولقطات ثابتة</p><h2>مكتبة القوالب ومصمم التقارير</h2></div><span className="date">مصادق عبر Supabase</span></header>
      {error && <p className="form-error" role="alert">{error}</p>}{notice && <p className="form-success" role="status">{notice}</p>}
      <div className="report-designer-grid">
        <section className="table-card report-library">
          <div className="card-heading"><h3>مكتبة القوالب</h3><span>{visible.length} قالب</span></div>
          <input className="report-search" value={search} onChange={(event) => setSearch(event.target.value)} placeholder="ابحث في القوالب" aria-label="ابحث في القوالب" />
          <div className="report-role-filters">{[['all', 'الكل'], ...roles].map(([code, label]) => <button type="button" className={`text-button ${roleFilter === code ? 'active-filter' : ''}`} key={code} onClick={() => setRoleFilter(code)}>{label}</button>)}</div>
          <div className="report-template-list">{visible.map((template) => <article className="report-template" key={template.id}>
            <div className="report-template-main"><strong>{template.title}</strong><small>{roles.find(([code]) => code === template.role_code)?.[1]} · {new Date(template.updated_at).toLocaleDateString('ar-SA')}</small>{template.description && <small>{template.description}</small>}</div>
            <div className="report-template-actions"><button className="text-button" disabled={busy} onClick={() => void openTemplate(template)}>إصدار جديد</button><button className="text-button" disabled={busy} onClick={() => void openTemplate(template, true)}>نسخ</button></div>
          </article>)}</div>
          {!visible.length && <p className="empty-state">لا توجد قوالب مطابقة؛ أنشئ نموذجًا جديدًا من المحرر.</p>}
        </section>

        <section className="form-card report-editor-card">
          <div className="card-heading"><div><h3>{selected ? 'إنشاء إصدار جديد' : 'نموذج جديد'}</h3><small>{fields.length} حقل · {versionId ? 'آخر إصدار محمّل' : 'مسودة غير محفوظة'}</small></div><button type="button" className="text-button" onClick={() => { setSelected(undefined); setVersionId(undefined); setTitle(''); setDescription(''); setRole('admin_followup'); setFields([]); setActiveIndex(null); setNotice(''); setError(''); }}>نموذج جديد</button></div>
          <div className="report-meta-grid">
            <label className="report-control">اسم النموذج<input value={title} maxLength={160} onChange={(event) => setTitle(event.target.value)} /></label>
            <label className="report-control">التصنيف الوظيفي<select value={role} disabled={Boolean(selected)} onChange={(event) => setRole(event.target.value as Role)}>{roles.map(([code, label]) => <option value={code} key={code}>{label}</option>)}</select>{selected && <small>لتغيير التصنيف، استخدم «نسخ» لإنشاء قالب مستقل.</small>}</label>
            <label className="report-control report-description">وصف النموذج<textarea value={description} maxLength={2000} onChange={(event) => setDescription(event.target.value)} rows={2} /></label>
            <label className="check-label"><input type="checkbox" checked={required} onChange={(event) => setRequired(event.target.checked)} /> التقرير مطلوب عند إنشاء المهمة</label>
          </div>

          <div className="report-workbench">
            <section className="report-field-list">
              <div className="report-subhead"><div><h4>حقول النموذج</h4><small>اختر حقلًا لتحرير تفاصيله</small></div><button type="button" className="ghost-button" disabled={fields.length >= 100} onClick={() => { const index = fields.length; setFields((current) => [...current, blankField(index)]); setActiveIndex(index); }}>＋ إضافة حقل</button></div>
              {fields.map((field, index) => <div className={`report-field-row ${activeIndex === index ? 'selected' : ''}`} key={`${field.field_key}-${index}`}>
                <button type="button" className="report-field-pick" aria-pressed={activeIndex === index} onClick={() => setActiveIndex(index)}><strong>{field.label.trim() || `حقل ${index + 1} — الاسم مطلوب`}</strong><small>{fieldLabel(field.field_type)} · {field.field_key}</small></button>
                <div className="report-field-actions"><button type="button" className="text-button" aria-label="تحريك لأعلى" disabled={index === 0} onClick={() => moveField(index, -1)}>↑</button><button type="button" className="text-button" aria-label="تحريك لأسفل" disabled={index === fields.length - 1} onClick={() => moveField(index, 1)}>↓</button><button type="button" className="text-button reject" onClick={() => { setFields((current) => current.filter((_, fieldIndex) => fieldIndex !== index)); setActiveIndex(index > 0 ? index - 1 : fields.length > 1 ? 0 : null); }}>حذف</button></div>
              </div>)}
              {!fields.length && <div className="empty-state">ابدأ بإضافة أول حقل إلى النموذج.</div>}
            </section>

            <section className="report-field-editor">
              {!activeField || activeIndex === null ? <div className="report-empty-editor"><strong>خصائص الحقل</strong><p>اختر حقلًا من القائمة أو أضف حقلًا جديدًا.</p></div> : <>
                <div className="report-subhead"><div><h4>خصائص الحقل</h4><small>الإعدادات تحفظ ضمن إصدار مستقل</small></div><span className="report-type-pill">{fieldLabel(activeField.field_type)}</span></div>
                <div className="report-control-grid">
                  <label className="report-control">اسم الحقل *<input value={activeField.label} maxLength={200} onChange={(event) => updateField(activeIndex, { label: event.target.value })} placeholder="مثال: كمية المستلم" /></label>
                  <label className="report-control">مفتاح الحقل<input value={activeField.field_key} maxLength={64} onChange={(event) => updateField(activeIndex, { field_key: event.target.value.toLowerCase().replace(/[^a-z0-9_]/g, '_') })} placeholder="received_quantity" /><small>حروف إنجليزية صغيرة وأرقام وشرطة سفلية.</small></label>
                  <label className="report-control">نوع الحقل<select value={activeField.field_type} onChange={(event) => updateField(activeIndex, { field_type: event.target.value as FieldType })}>{fieldTypes.map(([code, label]) => <option value={code} key={code}>{label}</option>)}</select></label>
                  <label className="report-control">تعليمات للموظف<input value={activeField.description ?? ''} maxLength={1000} onChange={(event) => updateField(activeIndex, { description: event.target.value })} placeholder="تظهر أسفل اسم الحقل" /></label>
                  <label className="check-label"><input type="checkbox" checked={activeField.is_required} onChange={(event) => updateField(activeIndex, { is_required: event.target.checked })} /> حقل إلزامي</label>
                </div>

                {['select', 'multiselect'].includes(activeField.field_type) && <div className="report-settings-block"><h5>خيارات القائمة</h5><OptionsEditor options={activeField.options} onChange={(options) => setFieldOptions(activeIndex, options)} /></div>}

                {['integer', 'quantity', 'money'].includes(activeField.field_type) && <div className="report-settings-block"><h5>قواعد التحقق الرقمي</h5><div className="report-control-grid"><label className="report-control">الحد الأدنى<input type="number" value={String(activeField.validation.min ?? '')} onChange={(event) => updateValidation(activeIndex, 'min', event.target.value === '' ? undefined : Number(event.target.value))} /></label><label className="report-control">الحد الأقصى<input type="number" value={String(activeField.validation.max ?? '')} onChange={(event) => updateValidation(activeIndex, 'max', event.target.value === '' ? undefined : Number(event.target.value))} /></label><label className="report-control">المنازل العشرية<input type="number" min="0" max="8" value={String(activeField.validation.decimal_places ?? '')} onChange={(event) => updateValidation(activeIndex, 'decimal_places', event.target.value === '' ? undefined : Number(event.target.value))} /></label><label className="check-label"><input type="checkbox" checked={activeField.validation.allow_negative !== false} onChange={(event) => updateValidation(activeIndex, 'allow_negative', event.target.checked)} /> السماح بالقيم السالبة</label><label className="check-label"><input type="checkbox" checked={activeField.validation.allow_zero !== false} onChange={(event) => updateValidation(activeIndex, 'allow_zero', event.target.checked)} /> السماح بالصفر</label></div></div>}

                {['short_text', 'long_text', 'decision_notes'].includes(activeField.field_type) && <div className="report-settings-block"><h5>قواعد طول النص</h5><div className="report-control-grid"><label className="report-control">أقل عدد أحرف<input type="number" min="0" max="20000" value={String(activeField.validation.min_length ?? '')} onChange={(event) => updateValidation(activeIndex, 'min_length', event.target.value === '' ? undefined : Number(event.target.value))} /></label><label className="report-control">أقصى عدد أحرف<input type="number" min="1" max="20000" value={String(activeField.validation.max_length ?? '')} onChange={(event) => updateValidation(activeIndex, 'max_length', event.target.value === '' ? undefined : Number(event.target.value))} /></label></div></div>}

                {['select', 'multiselect', 'integer', 'quantity', 'money', 'short_text', 'long_text', 'decision_notes', 'signature'].includes(activeField.field_type) && <div className="report-settings-block"><h5>رسائل التحقق المخصصة (اختياري)</h5><div className="report-control-grid"><label className="report-control">رسالة الحقل المطلوب<input value={String(asObject(activeField.validation.messages).required ?? '')} onChange={(event) => updateValidation(activeIndex, 'messages', { ...asObject(activeField.validation.messages), required: event.target.value })} placeholder="يرجى تعبئة هذا الحقل" /></label><label className="report-control">رسالة التحقق العامة<input value={String(asObject(activeField.validation.messages).invalid ?? '')} onChange={(event) => updateValidation(activeIndex, 'messages', { ...asObject(activeField.validation.messages), invalid: event.target.value })} placeholder="تحقق من القيمة المدخلة" /></label></div></div>}

                {!['table', 'calculated', 'signature', 'image', 'file'].includes(activeField.field_type) && <div className="report-settings-block"><h5>القيمة الافتراضية</h5>{activeField.field_type === 'boolean' ? <select value={activeField.config.default_value === true ? 'true' : activeField.config.default_value === false ? 'false' : ''} onChange={(event) => updateConfig(activeIndex, 'default_value', event.target.value === '' ? undefined : event.target.value === 'true')}><option value="">بدون قيمة افتراضية</option><option value="true">نعم</option><option value="false">لا</option></select> : activeField.field_type === 'select' ? <select value={String(activeField.config.default_value ?? '')} onChange={(event) => updateConfig(activeIndex, 'default_value', event.target.value || undefined)}><option value="">بدون قيمة افتراضية</option>{activeField.options.map((option) => <option value={option} key={option}>{option}</option>)}</select> : activeField.field_type === 'multiselect' ? <input value={Array.isArray(activeField.config.default_value) ? activeField.config.default_value.join(', ') : ''} onChange={(event) => updateConfig(activeIndex, 'default_value', event.target.value.split(',').map((item) => item.trim()).filter(Boolean))} placeholder="قيم افتراضية متعددة مفصولة بفواصل" /> : <input value={String(activeField.config.default_value ?? '')} onChange={(event) => updateConfig(activeIndex, 'default_value', ['integer', 'quantity', 'money'].includes(activeField.field_type) && event.target.value !== '' ? Number(event.target.value) : event.target.value || undefined)} placeholder="اختياري" />}</div>}

                {activeField.field_type === 'table' && <div className="report-settings-block"><h5>أعمدة الجدول وقواعده</h5><div className="report-control-grid"><label className="report-control">أقل عدد صفوف<input type="number" min="0" max="500" value={String(activeField.config.min_rows ?? '')} onChange={(event) => updateConfig(activeIndex, 'min_rows', event.target.value === '' ? undefined : Number(event.target.value))} /></label><label className="report-control">أقصى عدد صفوف<input type="number" min="1" max="500" value={String(activeField.config.max_rows ?? '')} onChange={(event) => updateConfig(activeIndex, 'max_rows', event.target.value === '' ? undefined : Number(event.target.value))} /></label></div>
                  {activeColumns.map((column, columnIndex) => <div className="table-column-editor" key={`${column.key}-${columnIndex}`}><div className="report-control-grid"><label className="report-control">مفتاح العمود<input value={column.key} onChange={(event) => { const next = [...activeColumns]; next[columnIndex] = { ...column, key: event.target.value.toLowerCase().replace(/[^a-z0-9_]/g, '_') }; updateConfig(activeIndex, 'columns', next); }} /></label><label className="report-control">اسم العمود<input value={column.label} onChange={(event) => { const next = [...activeColumns]; next[columnIndex] = { ...column, label: event.target.value }; updateConfig(activeIndex, 'columns', next); }} /></label><label className="report-control">نوع البيانات<select value={column.type} onChange={(event) => { const next = [...activeColumns]; next[columnIndex] = { ...column, type: event.target.value as ColumnType }; updateConfig(activeIndex, 'columns', next); }}>{columnTypes.map(([code, label]) => <option value={code} key={code}>{label}</option>)}</select></label><label className="check-label"><input type="checkbox" checked={column.required} onChange={(event) => { const next = [...activeColumns]; next[columnIndex] = { ...column, required: event.target.checked }; updateConfig(activeIndex, 'columns', next); }} /> عمود إلزامي</label></div>
                    {column.type === 'select' && <OptionsEditor options={column.options} onChange={(options) => { const next = [...activeColumns]; next[columnIndex] = { ...column, options }; updateConfig(activeIndex, 'columns', next); }} />}
                    {['integer', 'quantity', 'money'].includes(column.type) && <div className="report-control-grid"><label className="report-control">الحد الأدنى<input type="number" value={String(column.validation.min ?? '')} onChange={(event) => { const next = [...activeColumns]; next[columnIndex] = { ...column, validation: { ...column.validation, min: event.target.value === '' ? undefined : Number(event.target.value) } }; updateConfig(activeIndex, 'columns', next); }} /></label><label className="report-control">الحد الأقصى<input type="number" value={String(column.validation.max ?? '')} onChange={(event) => { const next = [...activeColumns]; next[columnIndex] = { ...column, validation: { ...column.validation, max: event.target.value === '' ? undefined : Number(event.target.value) } }; updateConfig(activeIndex, 'columns', next); }} /></label></div>}
                    <div className="report-field-actions"><button type="button" className="text-button" disabled={columnIndex === 0} onClick={() => { const next = [...activeColumns]; [next[columnIndex - 1], next[columnIndex]] = [next[columnIndex], next[columnIndex - 1]]; updateConfig(activeIndex, 'columns', next); }}>↑ ترتيب</button><button type="button" className="text-button" disabled={columnIndex === activeColumns.length - 1} onClick={() => { const next = [...activeColumns]; [next[columnIndex + 1], next[columnIndex]] = [next[columnIndex], next[columnIndex + 1]]; updateConfig(activeIndex, 'columns', next); }}>↓ ترتيب</button><button type="button" className="text-button reject" onClick={() => updateConfig(activeIndex, 'columns', activeColumns.filter((_, index) => index !== columnIndex))}>حذف العمود</button></div>
                  </div>)}
                  <button type="button" className="text-button" disabled={activeColumns.length >= 20} onClick={() => updateConfig(activeIndex, 'columns', [...activeColumns, { key: `column_${activeColumns.length + 1}`, label: '', type: 'short_text', required: false, options: [], validation: {} }])}>＋ إضافة عمود</button>
                </div>}

                {activeField.field_type === 'calculated' && <div className="report-settings-block"><h5>صيغة آمنة</h5><label className="report-control">الصيغة<input value={String(activeField.config.formula ?? '')} onChange={(event) => updateConfig(activeIndex, 'formula', event.target.value)} placeholder="{quantity} * {unit_price}" /></label><small>العمليات المدعومة: + − × ÷ والأقواس. اجمع عمود جدول باستخدام sum_rows(table_key.column_key). لا يستخدم eval.</small></div>}
                {activeField.field_type === 'signature' && <div className="report-settings-block"><h5>الإقرار والتوقيع</h5><label className="report-control">نص الإقرار الاختياري<textarea rows={3} maxLength={2000} value={String(activeField.config.consent_text ?? '')} onChange={(event) => updateConfig(activeIndex, 'consent_text', event.target.value)} placeholder="أقر بصحة البيانات المدخلة…" /></label><p className="muted">يرتبط التوقيع بالتقرير كملحق immutable ولا يحفظ داخل حاوية task-attachments.</p></div>}
                <div className="report-preview"><strong>معاينة الحقل</strong><div className="report-preview-card"><span>{activeField.label.trim() || 'اسم الحقل'}{activeField.is_required ? ' *' : ''}</span><small>{fieldLabel(activeField.field_type)}{activeField.description ? ` · ${activeField.description}` : ''}</small></div></div>
              </>}
            </section>
          </div>
          <div className="builder-actions"><button type="button" className="ghost-button" disabled={busy} onClick={() => void save()}>{busy ? 'جارٍ الحفظ…' : 'حفظ كمسودة إصدار جديد'}</button>{versionId && <button type="button" className="text-button" disabled={busy} onClick={() => void approve()}>اعتماد الإصدار</button>}</div>
        </section>
      </div>
    </section>
  </main>;
}
