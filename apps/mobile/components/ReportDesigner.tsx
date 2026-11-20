import { useEffect, useMemo, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { approveDesignerVersion, designerFieldTypes, getLatestDesignerVersion, listDesignerTemplates, saveDesignerTemplate, type ReportTemplate } from '../lib/reportDesigner';
import { normalizeTableColumns, validateDesignerFields, type DesignerField, type ReportTableColumn } from '../lib/reportSchema';
import ReportLivePreview from './ReportLivePreview';
import { deleteManagedReportTemplate } from '../lib/managementData';

const roles: Array<[string, string]> = [
  ['owner', 'صاحب المؤسسة'], ['admin_followup', 'المدير التنفيذي'], ['accountant', 'المحاسب'],
  ['warehouse_keeper', 'أمين المخازن'], ['warehouse_worker', 'عمال التحميل'],
];
const columnTypes: Array<[ReportTableColumn['type'], string]> = [
  ['short_text', 'نص'], ['long_text', 'نص طويل'], ['integer', 'عدد صحيح'], ['decimal', 'رقم عشري'], ['quantity', 'كمية'], ['money', 'مبلغ'], ['select', 'قائمة'], ['boolean', 'نعم/لا'],
];
const roleName = (code: string) => roles.find(([value]) => value === code)?.[1] ?? code;
const typeName = (code: string) => designerFieldTypes.find(([value]) => value === code)?.[1] ?? code;
const fieldTypeGroups: Array<[string, string[]]> = [
  ['نصوص', ['short_text', 'long_text']],
  ['أرقام ومالية', ['money', 'quantity', 'percentage']],
  ['اختيارات', ['boolean', 'select']],
  ['مرفقات وجداول', ['image', 'file', 'table']],
];
const emptyField = (index: number, used: Set<string>): DesignerField => {
  let serial = index + 1;
  while (used.has(`field_${serial}`)) serial += 1;
  return { field_key: `field_${serial}`, label: '', description: '', field_type: 'short_text', is_required: false, repeatable: false, sort_order: index, options: [], validation: {}, config: {} };
};
const obj = (value: unknown): Record<string, unknown> => value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : {};
function ensureFieldKeys(items: DesignerField[]) {
  const used = new Set<string>();
  return items.map((field, index) => {
    let key = field.field_key.trim();
    let serial = index + 1;
    while (!key || used.has(key)) key = `field_${serial++}`;
    used.add(key);
    return { ...field, field_key: key, sort_order: index };
  });
}

export default function ReportDesigner({ organizationId = '' }: { organizationId?: string }) {
  const [templates, setTemplates] = useState<ReportTemplate[]>([]);
  const [search, setSearch] = useState('');
  const [roleFilter, setRoleFilter] = useState('all');
  const [mode, setMode] = useState<'library' | 'builder'>('library');
  const [builderSection, setBuilderSection] = useState<'fields' | 'properties'>('fields');
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [roleCode, setRoleCode] = useState('admin_followup');
  const [reportRequired, setReportRequired] = useState(true);
  const [fields, setFields] = useState<DesignerField[]>([]);
  const [activeField, setActiveField] = useState<number | null>(null);
  const [templateId, setTemplateId] = useState<string>();
  const [versionId, setVersionId] = useState<string>();
  const [versionStatus, setVersionStatus] = useState('draft');
  const [notice, setNotice] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  async function refreshTemplates() {
    setTemplates(await listDesignerTemplates());
  }
  useEffect(() => { void refreshTemplates().catch((cause) => setError(String((cause as { message?: string })?.message ?? 'تعذر تحميل مكتبة النماذج.'))); }, []);
  function resetBuilder() {
    setTemplateId(undefined); setVersionId(undefined); setVersionStatus('draft'); setTitle(''); setDescription('');
    setRoleCode('admin_followup'); setReportRequired(true); setFields([]); setActiveField(null); setBuilderSection('fields'); setNotice(''); setError(''); setMode('builder');
  }
  async function openTemplate(template: ReportTemplate, clone = false) {
    setBusy(true); setError(''); setNotice('');
    try {
      const latest = await getLatestDesignerVersion(template.id);
      setTemplateId(clone ? undefined : template.id); setVersionId(clone ? undefined : latest.version.id); setVersionStatus(clone ? 'draft' : latest.version.status);
      setTitle(clone ? `${template.title} — نسخة` : template.title); setDescription(template.description ?? ''); setRoleCode(template.role_code);
      setReportRequired(latest.version.report_required);
      setFields(latest.fields.map((field, index) => ({ ...field, field_key: field.field_key, label: field.label, description: field.description ?? '', field_type: field.field_type, is_required: field.is_required, repeatable: field.repeatable, sort_order: index, options: field.options ?? [], validation: field.validation ?? {}, config: field.config ?? {} })));
      setActiveField(latest.fields.length ? 0 : null); setBuilderSection('fields'); setMode('builder');
      setNotice(clone ? 'تم نسخ النموذج؛ التعديلات تحفظ كقالب مستقل.' : `تحرير إصدار جديد انطلاقًا من الإصدار ${latest.version.version_no}.`);
    } catch (cause) { setError(String((cause as { message?: string })?.message ?? 'تعذر فتح النموذج.')); }
    finally { setBusy(false); }
  }
  function updateField(index: number, patch: Partial<DesignerField>) {
    setFields((current) => current.map((field, itemIndex) => itemIndex === index ? { ...field, ...patch } : field));
  }
  function addField() {
    if (fields.length >= 100) return;
    const field = emptyField(fields.length, new Set(fields.map((item) => item.field_key)));
    setFields((current) => [...current, field]);
    setActiveField(fields.length);
    setBuilderSection('properties');
  }
  function duplicateField(index: number) {
    if (fields.length >= 100) { setError('لا يمكن أن يتجاوز النموذج 100 حقل.'); return; }
    const source = fields[index];
    if (!source) return;
    const used = new Set(fields.map((item) => item.field_key));
    let serial = 2;
    let key = `${source.field_key}_copy`;
    while (used.has(key)) key = `${source.field_key}_copy_${serial++}`;
    const copy: DesignerField = { ...source, field_key: key, label: `${source.label.trim() || 'حقل'} — نسخة`, sort_order: index + 1, config: { ...source.config }, validation: { ...source.validation }, options: [...source.options] };
    setFields((current) => [...current.slice(0, index + 1), copy, ...current.slice(index + 1)].map((item, sort_order) => ({ ...item, sort_order })));
    setActiveField(index + 1);
    setBuilderSection('properties');
  }
  function moveField(index: number, offset: -1 | 1) {
    const destination = index + offset;
    if (destination < 0 || destination >= fields.length) return;
    setFields((current) => {
      const next = [...current]; [next[index], next[destination]] = [next[destination], next[index]];
      return next.map((field, sort_order) => ({ ...field, sort_order }));
    });
    setActiveField(destination);
  }
  function removeField(index: number) {
    setFields((current) => current.filter((_, fieldIndex) => fieldIndex !== index).map((field, sort_order) => ({ ...field, sort_order })));
    setActiveField((current) => current === null ? null : fields.length <= 1 ? null : Math.max(0, current > index ? current - 1 : Math.min(current, fields.length - 2)));
  }
  async function save() {
    const normalizedFields = ensureFieldKeys(fields);
    const fieldIssue = validateDesignerFields(normalizedFields);
    if (title.trim().length < 2) { setError('أدخل اسمًا للنموذج بطول حرفين على الأقل.'); return; }
    if (fieldIssue) { setError(fieldIssue); return; }
    setBusy(true); setError(''); setNotice('');
    try {
      setFields(normalizedFields);
      const saved = await saveDesignerTemplate({ templateId, title, description, roleCode, fields: normalizedFields, reportRequired });
      setTemplateId(saved.templateId); setVersionId(saved.versionId); setVersionStatus('draft');
      setNotice('حُفظ إصدار مسودة جديد. اعتمده صاحب المؤسسة قبل ربطه بمهمة.');
      await refreshTemplates();
    } catch (cause) { setError(String((cause as { message?: string })?.message ?? 'تعذر حفظ النموذج.')); }
    finally { setBusy(false); }
  }
  async function approve() {
    if (!versionId) return;
    setBusy(true); setError('');
    try { await approveDesignerVersion(versionId); setVersionStatus('published'); setNotice('تم اعتماد الإصدار. سيبقى هذا الإصدار ثابتًا وتُحفظ نسخ مستقلة للمهام الجديدة.'); }
    catch (cause) { setError(String((cause as { message?: string })?.message ?? 'اعتماد الإصدار متاح لصاحب المؤسسة فقط.')); }
    finally { setBusy(false); }
  }
  function confirmDelete(template: ReportTemplate) {
    Alert.alert('حذف قالب التقرير نهائيًا', 'سيُحذف القالب من مكتبة التقارير نهائيًا، وتُفصل ارتباطاته الحالية بالمهام. ستبقى المهام والتقارير السابقة ولقطاتها وإصداراتها محفوظة وقابلة للقراءة. هل تريد المتابعة؟', [
      { text: 'إلغاء', style: 'cancel' },
      { text: 'حذف نهائي', style: 'destructive', onPress: () => void (async () => { setBusy(true); setError(''); try { await deleteManagedReportTemplate(organizationId, template.id); setNotice('تم حذف القالب وفصل ارتباطاته. بقيت المهام والتقارير السابقة محفوظة.'); await refreshTemplates(); } catch (cause) { setError(String((cause as { message?: string })?.message ?? 'تعذر حذف قالب التقرير. لم تُحذف أي مهام أو تقارير تاريخية.')); } finally { setBusy(false); } })() },
    ]);
  }
  const visibleTemplates = useMemo(() => templates.filter((template) =>
    (roleFilter === 'all' || template.role_code === roleFilter) &&
    `${template.title} ${template.description ?? ''}`.toLocaleLowerCase('ar').includes(search.trim().toLocaleLowerCase('ar')),
  ), [templates, roleFilter, search]);

  if (mode === 'builder') {
    const field = activeField === null ? null : fields[activeField] ?? null;
    return <View style={styles.shell}>
      <View style={styles.header}><View style={styles.headerCopy}><Text style={styles.eyebrow}>مصمم التقارير · {templateId ? 'إصدار جديد' : 'قالب جديد'}</Text><Text style={styles.title}>بناء نموذج التقرير</Text></View><View style={styles.headerActions}><Pressable disabled={busy} style={[styles.primarySmall, busy && styles.disabled]} onPress={() => void save()}><Text style={styles.primaryText}>{busy ? 'جارٍ الحفظ…' : 'حفظ القالب'}</Text></Pressable><Pressable style={styles.ghost} onPress={() => { setMode('library'); setError(''); }}><Text style={styles.ghostText}>المكتبة</Text></Pressable></View></View>
      {!!error && <Text accessibilityRole="alert" style={styles.error}>{error}</Text>}{!!notice && <Text style={styles.notice}>{notice}</Text>}
      <View style={styles.metaCard}>
        <TextInput style={styles.input} placeholder="اسم النموذج" value={title} onChangeText={setTitle} maxLength={160} />
        <TextInput style={[styles.input, styles.multiline]} placeholder="الوصف وتعليمات الموظف (اختياري)" value={description} onChangeText={setDescription} multiline />
        <Text style={styles.sectionLabel}>يرتبط هذا النموذج بدور وظيفي واحد</Text>
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.chips}>{roles.map(([code, label]) => <Chip key={code} label={label} selected={roleCode === code} disabled={Boolean(templateId)} onPress={() => setRoleCode(code)} />)}</ScrollView>
        {templateId && <Text style={styles.panelSub}>لا يتغير دور القالب بعد إنشائه؛ استخدم «نسخ» لإنشاء قالب بدور آخر.</Text>}
        <Pressable style={styles.toggle} onPress={() => setReportRequired((current) => !current)}><Text style={styles.toggleText}>{reportRequired ? 'التقرير مطلوب عند التنفيذ ✓' : 'التقرير اختياري'}</Text></Pressable>
      </View>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.chips}>
        <Chip label={`مخطط الحقول · ${fields.length}`} selected={builderSection === 'fields'} onPress={() => setBuilderSection('fields')} />
        <Chip label="خصائص الحقل" selected={builderSection === 'properties'} disabled={activeField === null} onPress={() => setBuilderSection('properties')} />
      </ScrollView>
      <View style={styles.builderGrid}>
        {builderSection === 'fields' && <View style={styles.panel}>
          <View style={styles.panelHeader}><View><Text style={styles.sectionLabel}>مخطط الحقول</Text><Text style={styles.panelSub}>{fields.length} من 100 حقل</Text></View><Pressable style={styles.primarySmall} onPress={addField}><Text style={styles.primaryText}>+ إضافة حقل</Text></Pressable></View>
          {!fields.length && <Text style={styles.empty}>ابدأ بإضافة الحقل الأول، ثم خصصه من اللوحة المجاورة.</Text>}
          {fields.map((item, index) => <Pressable key={`${item.field_key}-${index}`} onPress={() => { setActiveField(index); setBuilderSection('properties'); }} style={[styles.fieldRow, activeField === index && styles.fieldRowActive]}>
            <View style={styles.fieldRowText}><Text style={styles.fieldRowTitle}>{item.label.trim() || `حقل ${index + 1} — يحتاج اسمًا`}</Text><Text style={styles.panelSub}>{typeName(item.field_type)}{item.is_required ? ' · إلزامي' : ''}</Text></View>
            <View style={styles.rowButtons}><SmallAction label="↑" disabled={index === 0} onPress={() => moveField(index, -1)} /><SmallAction label="↓" disabled={index === fields.length - 1} onPress={() => moveField(index, 1)} /><SmallAction label="⧉" onPress={() => duplicateField(index)} /><SmallAction label="×" danger onPress={() => removeField(index)} /></View>
          </Pressable>)}
        </View>}
        {builderSection === 'properties' && <View style={styles.panel}>
          <Text style={styles.sectionLabel}>{field ? `خصائص: ${field.label.trim() || field.field_key}` : 'خصائص الحقل'}</Text>
          {!field || activeField === null ? <Text style={styles.empty}>اختر حقلًا من المخطط لتعديل نوعه وقواعده.</Text> : <FieldEditor field={field} update={(patch) => updateField(activeField, patch)} />}
        </View>}
      </View>
      <ReportLivePreview fields={fields} title={title} description={description} />
      <View style={styles.actions}><Pressable disabled={busy} style={[styles.primary, busy && styles.disabled]} onPress={() => void save()}><Text style={styles.primaryText}>{busy ? 'جارٍ الحفظ…' : templateId ? 'حفظ إصدار جديد' : 'حفظ القالب'}</Text></Pressable>{!!versionId && versionStatus === 'draft' && <Pressable disabled={busy} style={styles.secondary} onPress={() => void approve()}><Text style={styles.secondaryText}>اعتماد الإصدار من المالك</Text></Pressable>}{versionStatus === 'published' && <Text style={styles.approved}>الإصدار معتمد وثابت ✓</Text>}</View>
    </View>;
  }

  return <View style={styles.shell}>
    <View style={styles.header}><View style={styles.headerCopy}><Text style={styles.eyebrow}>إدارة النماذج المرتبطة بالمهام</Text><Text style={styles.title}>مكتبة التقارير</Text></View><Pressable style={styles.primarySmall} onPress={resetBuilder}><Text style={styles.primaryText}>+ نموذج جديد</Text></Pressable></View>
    {!!error && <Text accessibilityRole="alert" style={styles.error}>{error}</Text>}{!!notice && <Text style={styles.notice}>{notice}</Text>}
    <TextInput style={styles.input} placeholder="ابحث باسم النموذج أو وصفه" value={search} onChangeText={setSearch} />
    <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.chips}><Chip label="كل الأدوار" selected={roleFilter === 'all'} onPress={() => setRoleFilter('all')} />{roles.map(([code, label]) => <Chip key={code} label={label} selected={roleFilter === code} onPress={() => setRoleFilter(code)} />)}</ScrollView>
    {!visibleTemplates.length && <View style={styles.emptyCard}><Text style={styles.sectionLabel}>لا توجد قوالب مطابقة</Text><Text style={styles.panelSub}>أنشئ نموذجًا جديدًا أو غيّر عبارة البحث والتصنيف.</Text></View>}
    {visibleTemplates.map((template) => <View style={styles.templateCard} key={template.id}><View style={styles.templateInfo}><Text style={styles.templateTitle}>{template.title}</Text><Text style={styles.panelSub}>{roleName(template.role_code)}{template.updated_at ? ` · تحديث ${new Date(template.updated_at).toLocaleDateString('ar-SA')}` : ''}</Text>{!!template.description && <Text style={styles.description}>{template.description}</Text>}</View><View style={[styles.chips, styles.templateActions]}><Pressable style={styles.ghost} onPress={() => void openTemplate(template)}><Text style={styles.ghostText}>تعديل / إصدار جديد</Text></Pressable><Pressable style={styles.ghost} onPress={() => void openTemplate(template, true)}><Text style={styles.ghostText}>نسخ</Text></Pressable><Pressable style={styles.ghost} onPress={() => confirmDelete(template)}><Text style={styles.ghostText}>حذف نهائي</Text></Pressable></View></View>)}
  </View>;
}

function Chip({ label, selected, onPress, disabled = false }: { label: string; selected: boolean; onPress: () => void; disabled?: boolean }) {
  return <Pressable disabled={disabled} accessibilityRole="button" accessibilityState={{ selected, disabled }} style={[styles.chip, selected && styles.chipSelected, disabled && styles.disabled]} onPress={onPress}><Text style={selected ? styles.chipTextSelected : styles.chipText}>{label}</Text></Pressable>;
}
function SmallAction({ label, onPress, disabled = false, danger = false }: { label: string; onPress: () => void; disabled?: boolean; danger?: boolean }) {
  return <Pressable disabled={disabled} style={[styles.smallAction, danger && styles.smallDanger, disabled && styles.disabled]} onPress={onPress}><Text style={styles.smallActionText}>{label}</Text></Pressable>;
}
function setRule(field: DesignerField, key: string, value: unknown) {
  return { ...field.validation, [key]: value };
}
function FieldEditor({ field, update }: { field: DesignerField; update: (patch: Partial<DesignerField>) => void }) {
  const config = obj(field.config); const validation = obj(field.validation);
  const [advancedOpen, setAdvancedOpen] = useState(false);
  const changeConfig = (key: string, value: unknown) => update({ config: { ...config, [key]: value } });
  const changeRule = (key: string, value: unknown) => update({ validation: setRule(field, key, value) });
  const textType = ['short_text', 'long_text', 'decision_notes'].includes(field.field_type);
  const numericType = ['integer', 'decimal', 'percentage', 'quantity', 'money'].includes(field.field_type);
  const listType = field.field_type === 'select' || field.field_type === 'multiselect';
  const selectedDefaults = Array.isArray(config.default_value) ? config.default_value.map(String) : [];
  return <View style={styles.editor}>
    <TextInput style={styles.input} placeholder="اسم الحقل — مطلوب" value={field.label} onChangeText={(label) => update({ label })} maxLength={200} />
    <TextInput style={[styles.input, styles.multiline]} placeholder="تعليمات تظهر للموظف (اختياري)" value={field.description} onChangeText={(description) => update({ description })} multiline />
    <Text style={styles.sectionLabel}>نوع الحقل</Text>{fieldTypeGroups.map(([groupLabel, codes]) => <View key={groupLabel} style={styles.typeGroup}><Text style={styles.groupLabel}>{groupLabel}</Text><View style={styles.chips}>{codes.map((code) => { const item = designerFieldTypes.find(([value]) => value === code); return item ? <Chip key={code} label={item[1]} selected={field.field_type === code} onPress={() => update({ field_type: code as DesignerField['field_type'] })} /> : null; })}</View></View>)}
    <View style={styles.requiredBox}><Text style={styles.groupLabel}>إعداد الحقل</Text><Chip label={field.is_required ? 'مطلوب ✓' : 'اختياري'} selected={field.is_required} onPress={() => update({ is_required: !field.is_required })} /></View>
    <Pressable accessibilityRole="button" accessibilityState={{ expanded: advancedOpen }} style={styles.advancedToggle} onPress={() => setAdvancedOpen((current) => !current)}><Text style={styles.advancedToggleText}>{advancedOpen ? 'إخفاء الإعدادات المتقدمة' : 'إعدادات متقدمة (اختياري)'}</Text><Text style={styles.advancedChevron}>{advancedOpen ? '⌃' : '⌄'}</Text></Pressable>
    {advancedOpen && <View style={styles.advancedPanel}>
      {numericType && <><Text style={styles.sectionLabel}>الحدود ودقة الرقم</Text><View style={styles.twoColumns}><RuleInput label="الحد الأدنى" value={validation.min} onChange={(value) => changeRule('min', value)} /><RuleInput label="الحد الأقصى" value={validation.max} onChange={(value) => changeRule('max', value)} /></View>{field.field_type !== 'integer' && <RuleInput label="المنازل العشرية (0–8)" value={validation.decimal_places} onChange={(value) => changeRule('decimal_places', value)} integer />}<View style={styles.chips}><Chip label={validation.allow_negative === false ? 'القيم السالبة ممنوعة' : 'السالب مسموح'} selected={validation.allow_negative !== false} onPress={() => changeRule('allow_negative', validation.allow_negative === false)} /><Chip label={validation.allow_zero === false ? 'الصفر ممنوع' : 'الصفر مسموح'} selected={validation.allow_zero !== false} onPress={() => changeRule('allow_zero', validation.allow_zero === false)} /></View></>}
      {textType && <><Text style={styles.sectionLabel}>طول النص</Text><View style={styles.twoColumns}><RuleInput label="الحد الأدنى للأحرف" value={validation.min_length} onChange={(value) => changeRule('min_length', value)} integer /><RuleInput label="الحد الأقصى للأحرف" value={validation.max_length} onChange={(value) => changeRule('max_length', value)} integer /></View></>}
      {(numericType || textType) && <TextInput style={styles.input} placeholder="رسالة خطأ مخصصة لهذا الحقل (اختياري)" value={String(obj(validation.messages).invalid ?? '')} onChangeText={(value) => changeRule('messages', { ...obj(validation.messages), invalid: value })} />}
      {listType && <><Text style={styles.sectionLabel}>خيارات القائمة</Text><OptionsEditor options={field.options ?? []} onChange={(options) => { let defaultValue = config.default_value; if (field.field_type === 'select' && typeof defaultValue === 'string' && !options.includes(defaultValue)) defaultValue = undefined; if (field.field_type === 'multiselect' && Array.isArray(defaultValue)) defaultValue = defaultValue.filter((value) => options.includes(String(value))); update({ options, config: { ...config, default_value: defaultValue } }); }} /><Text style={styles.sectionLabel}>القيمة الافتراضية</Text>{field.field_type === 'select' ? <View style={styles.chips}><Chip label="بدون قيمة افتراضية" selected={config.default_value === undefined} onPress={() => changeConfig('default_value', undefined)} />{(field.options ?? []).map((option) => <Chip key={option} label={option} selected={config.default_value === option} onPress={() => changeConfig('default_value', option)} />)}</View> : <View style={styles.chips}>{(field.options ?? []).map((option) => <Chip key={option} label={option} selected={selectedDefaults.includes(option)} onPress={() => changeConfig('default_value', selectedDefaults.includes(option) ? selectedDefaults.filter((value) => value !== option) : [...selectedDefaults, option])} />)}</View>}</>}
      {field.field_type === 'table' && <><Text style={styles.sectionLabel}>أعمدة الجدول</Text><TableColumnsEditor columns={normalizeTableColumns({ config: field.config })} onChange={(columns) => changeConfig('columns', columns)} /><View style={styles.twoColumns}><RuleInput label="أقل عدد صفوف" value={config.min_rows} onChange={(value) => changeConfig('min_rows', value)} integer /><RuleInput label="أقصى عدد صفوف" value={config.max_rows} onChange={(value) => changeConfig('max_rows', value)} integer /></View></>}
      {field.field_type === 'calculated' && <><Text style={styles.sectionLabel}>صيغة حساب آمنة</Text><TextInput style={styles.input} value={String(config.formula ?? '')} onChangeText={(formula) => changeConfig('formula', formula)} placeholder="مثال: {quantity} * {unit_price} - {discount}" autoCapitalize="none" /><Text style={styles.panelSub}>يدعم العمليات الحسابية الآمنة فقط.</Text></>}
      {field.field_type === 'datetime' && <Pressable style={styles.toggle} onPress={() => changeConfig('auto_now', config.auto_now !== true)}><Text style={styles.toggleText}>{config.auto_now === true ? 'يُسجل تلقائيًا عند الإرسال ✓' : 'إدخال التاريخ والوقت يدويًا'}</Text></Pressable>}
      {field.field_type === 'system_reference' && <><Text style={styles.sectionLabel}>نوع المرجع من النظام</Text><View style={styles.chips}>{[['branch', 'فرع'], ['employee', 'موظف'], ['product', 'صنف / منتج'], ['customer', 'عميل / مورد']].map(([value, label]) => <Chip key={value} label={label} selected={config.reference_type === value} onPress={() => changeConfig('reference_type', value)} />)}</View></>}
      {!['calculated', 'datetime', 'date_range'].includes(field.field_type) && <View style={styles.conditionalBox}><Text style={styles.sectionLabel}>الإظهار الشرطي (اختياري)</Text><TextInput style={styles.input} placeholder="مفتاح الحقل السابق" value={String(obj(config.visibility).depends_on ?? '')} onChangeText={(value) => changeConfig('visibility', { ...obj(config.visibility), depends_on: value })} autoCapitalize="none" /><TextInput style={styles.input} placeholder="يظهر عندما تساوي القيمة" value={String(obj(config.visibility).equals ?? '')} onChangeText={(value) => changeConfig('visibility', { ...obj(config.visibility), equals: value })} /></View>}
      {field.field_type === 'signature' && <><Text style={styles.sectionLabel}>الإقرار والتوقيع</Text><TextInput style={[styles.input, styles.multiline]} value={String(config.consent_text ?? '')} onChangeText={(consent_text) => changeConfig('consent_text', consent_text)} placeholder="نص الإقرار الاختياري قبل التوقيع" multiline /></>}
      {['short_text', 'long_text', 'integer', 'decimal', 'percentage', 'quantity', 'money', 'datetime', 'boolean', 'select', 'multiselect'].includes(field.field_type) && <><Text style={styles.sectionLabel}>قيمة افتراضية (اختيارية)</Text>{field.field_type === 'boolean' ? <View style={styles.chips}><Chip label="نعم" selected={config.default_value === true} onPress={() => changeConfig('default_value', true)} /><Chip label="لا" selected={config.default_value === false} onPress={() => changeConfig('default_value', false)} /><Chip label="بدون افتراضي" selected={config.default_value === undefined} onPress={() => changeConfig('default_value', undefined)} /></View> : !listType && <TextInput style={styles.input} value={config.default_value == null ? '' : String(config.default_value)} onChangeText={(value) => changeConfig('default_value', value)} placeholder="القيمة الافتراضية" keyboardType={numericType ? 'decimal-pad' : 'default'} />}</>}
    </View>}
  </View>;
}
function RuleInput({ label, value, onChange, integer = false }: { label: string; value: unknown; onChange: (value: number | undefined) => void; integer?: boolean }) {
  return <TextInput style={[styles.input, styles.ruleInput]} placeholder={label} value={value == null ? '' : String(value)} keyboardType="decimal-pad" onChangeText={(raw) => { const parsed = raw.trim() === '' ? undefined : Number(raw); onChange(parsed === undefined || Number.isFinite(parsed) && (!integer || Number.isInteger(parsed)) ? parsed : undefined); }} />;
}
function OptionsEditor({ options, onChange }: { options: string[]; onChange: (options: string[]) => void }) {
  const [draft, setDraft] = useState('');
  return <View style={styles.editorGroup}>
    {options.map((option, index) => <View style={styles.optionRow} key={`${index}-${option}`}><TextInput style={[styles.input, styles.optionInput]} value={option} onChangeText={(value) => onChange(options.map((item, itemIndex) => itemIndex === index ? value : item))} /><SmallAction label="↑" disabled={index === 0} onPress={() => { const next = [...options]; [next[index - 1], next[index]] = [next[index], next[index - 1]]; onChange(next); }} /><SmallAction label="↓" disabled={index === options.length - 1} onPress={() => { const next = [...options]; [next[index + 1], next[index]] = [next[index], next[index + 1]]; onChange(next); }} /><SmallAction label="×" danger onPress={() => onChange(options.filter((_, itemIndex) => itemIndex !== index))} /></View>)}
    <View style={styles.optionRow}><TextInput style={[styles.input, styles.optionInput]} value={draft} onChangeText={setDraft} placeholder="خيار جديد" /><Pressable style={styles.ghost} onPress={() => { const value = draft.trim(); if (!value || options.some((item) => item.trim() === value)) return; onChange([...options, value]); setDraft(''); }}><Text style={styles.ghostText}>إضافة</Text></Pressable></View>
  </View>;
}
function TableColumnsEditor({ columns, onChange }: { columns: ReportTableColumn[]; onChange: (columns: ReportTableColumn[]) => void }) {
  function update(index: number, patch: Partial<ReportTableColumn>) { onChange(columns.map((column, columnIndex) => columnIndex === index ? { ...column, ...patch } : column)); }
  return <View style={styles.editorGroup}>
    {columns.map((column, index) => <View style={styles.columnCard} key={`${column.key}-${index}`}>
      <View style={styles.optionRow}><TextInput style={[styles.input, styles.optionInput]} value={column.label} onChangeText={(label) => update(index, { label })} placeholder="اسم العمود" /><SmallAction label="↑" disabled={index === 0} onPress={() => { const next = [...columns]; [next[index - 1], next[index]] = [next[index], next[index - 1]]; onChange(next); }} /><SmallAction label="↓" disabled={index === columns.length - 1} onPress={() => { const next = [...columns]; [next[index + 1], next[index]] = [next[index], next[index + 1]]; onChange(next); }} /><SmallAction label="×" danger onPress={() => onChange(columns.filter((_, columnIndex) => columnIndex !== index))} /></View>
      <Text style={styles.key}>المفتاح: {column.key}</Text><View style={styles.chips}>{columnTypes.map(([type, label]) => <Chip key={type} label={label} selected={column.type === type} onPress={() => update(index, { type })} />)}<Chip label={column.required ? 'إلزامي ✓' : 'اختياري'} selected={Boolean(column.required)} onPress={() => update(index, { required: !column.required })} /></View>
      {column.type === 'select' && <TextInput style={styles.input} value={(column.options ?? []).join('، ')} onChangeText={(value) => update(index, { options: value.split('،').map((item) => item.trim()).filter(Boolean) })} placeholder="خيارات العمود مفصولة بعلامة ،" />}
      {['integer', 'decimal', 'quantity', 'money'].includes(column.type) && <View style={styles.twoColumns}><RuleInput label="حد أدنى" value={column.validation?.min} onChange={(value) => update(index, { validation: { ...column.validation, min: value } })} /><RuleInput label="حد أقصى" value={column.validation?.max} onChange={(value) => update(index, { validation: { ...column.validation, max: value } })} /></View>}
    </View>)}
    <Pressable style={styles.ghost} onPress={() => { const serial = columns.length + 1; onChange([...columns, { key: `column_${serial}`, label: `عمود ${serial}`, type: 'short_text', required: false, validation: {} }]); }}><Text style={styles.ghostText}>+ إضافة عمود</Text></Pressable>
  </View>;
}
const styles = StyleSheet.create({
  shell: { gap: 12 }, header: { flexDirection: 'row-reverse', flexWrap: 'wrap', alignItems: 'center', justifyContent: 'space-between', gap: 10 }, headerCopy: { flex: 1, minWidth: 0 }, headerActions: { flexDirection: 'row-reverse', flexWrap: 'wrap', alignItems: 'center', gap: 6 }, eyebrow: { color: '#718394', textAlign: 'right', fontWeight: '700', fontSize: 12 }, title: { color: '#17324d', textAlign: 'right', fontSize: 22, fontWeight: '900', marginTop: 2 }, sectionLabel: { color: '#17324d', textAlign: 'right', fontWeight: '900', fontSize: 15 }, panelSub: { color: '#718394', textAlign: 'right', lineHeight: 19, fontSize: 12 },
  metaCard: { backgroundColor: '#fff', borderColor: '#dce6e9', borderWidth: 1, borderRadius: 14, padding: 12, gap: 9 }, builderGrid: { gap: 10 }, panel: { backgroundColor: '#fff', borderColor: '#dce6e9', borderWidth: 1, borderRadius: 14, padding: 12, gap: 10 }, panelHeader: { flexDirection: 'row-reverse', justifyContent: 'space-between', alignItems: 'center', gap: 8 },
  fieldRow: { flexDirection: 'row-reverse', alignItems: 'center', gap: 8, borderColor: '#e1e9ec', borderWidth: 1, borderRadius: 11, padding: 8, minHeight: 62 }, fieldRowActive: { borderColor: '#17324d', backgroundColor: '#f1f6f8' }, fieldRowText: { flex: 1, gap: 3 }, fieldRowTitle: { color: '#17324d', fontWeight: '800', textAlign: 'right' }, rowButtons: { flexDirection: 'row-reverse', gap: 4 }, smallAction: { width: 34, height: 34, alignItems: 'center', justifyContent: 'center', borderRadius: 8, backgroundColor: '#e9f0f4' }, smallDanger: { backgroundColor: '#fff0ef' }, smallActionText: { color: '#17324d', fontWeight: '900' },
  editor: { gap: 8 }, editorGroup: { gap: 7 }, typeGroup: { gap: 5, padding: 8, borderRadius: 10, backgroundColor: '#f7fafb', borderWidth: 1, borderColor: '#e3ecef' }, requiredBox: { gap: 6, padding: 8, borderRadius: 10, backgroundColor: '#fff8e8', borderWidth: 1, borderColor: '#ead8a9' }, advancedToggle: { minHeight: 44, borderRadius: 10, borderWidth: 1, borderColor: '#cbd8de', backgroundColor: '#f7fafb', paddingHorizontal: 12, flexDirection: 'row-reverse', alignItems: 'center', justifyContent: 'space-between' }, advancedToggleText: { color: '#17324d', fontWeight: '900', textAlign: 'right' }, advancedChevron: { color: '#b1841d', fontSize: 20, fontWeight: '900' }, advancedPanel: { gap: 8, padding: 10, borderRadius: 10, backgroundColor: '#fbfcfc', borderWidth: 1, borderColor: '#e3ecef' }, conditionalBox: { gap: 8, paddingTop: 8, borderTopWidth: 1, borderTopColor: '#e3ecef' }, groupLabel: { color: '#39556a', textAlign: 'right', fontWeight: '900', fontSize: 13 }, input: { minHeight: 44, borderWidth: 1, borderColor: '#d6e0e4', borderRadius: 9, paddingHorizontal: 10, paddingVertical: 8, textAlign: 'right', color: '#17324d', backgroundColor: '#fbfcfc' }, multiline: { minHeight: 68, textAlignVertical: 'top' }, key: { color: '#718394', textAlign: 'right', fontSize: 11 }, chips: { flexDirection: 'row-reverse', flexWrap: 'wrap', gap: 6 }, chip: { borderWidth: 1, borderColor: '#cbd8de', borderRadius: 18, paddingHorizontal: 10, paddingVertical: 7, backgroundColor: '#fff' }, chipSelected: { borderColor: '#17324d', backgroundColor: '#17324d' }, chipText: { color: '#39556a', fontSize: 12 }, chipTextSelected: { color: '#fff', fontWeight: '800', fontSize: 12 }, twoColumns: { flexDirection: 'row-reverse', gap: 7 }, ruleInput: { flex: 1 }, toggle: { borderWidth: 1, borderColor: '#dce6e9', borderRadius: 9, minHeight: 42, alignItems: 'center', justifyContent: 'center' }, toggleText: { color: '#17324d', fontWeight: '800' }, optionRow: { flexDirection: 'row-reverse', gap: 5, alignItems: 'center' }, optionInput: { flex: 1 }, columnCard: { borderWidth: 1, borderColor: '#edf1f3', borderRadius: 10, padding: 8, gap: 6 },
  primary: { minHeight: 46, flex: 1, backgroundColor: '#17324d', borderRadius: 10, alignItems: 'center', justifyContent: 'center', padding: 11 }, primarySmall: { backgroundColor: '#17324d', borderRadius: 9, paddingHorizontal: 12, paddingVertical: 9 }, primaryText: { color: '#fff', fontWeight: '900', textAlign: 'center' }, secondary: { minHeight: 46, borderRadius: 10, borderWidth: 1, borderColor: '#2f6654', padding: 10, alignItems: 'center', justifyContent: 'center' }, secondaryText: { color: '#2f6654', fontWeight: '900' }, ghost: { minHeight: 38, borderRadius: 9, borderWidth: 1, borderColor: '#cbd8de', paddingHorizontal: 11, alignItems: 'center', justifyContent: 'center' }, ghostText: { color: '#17324d', fontWeight: '800' }, actions: { flexDirection: 'row-reverse', flexWrap: 'wrap', alignItems: 'center', gap: 7 }, templateActions: { width: '100%' }, disabled: { opacity: 0.45 }, approved: { color: '#23633c', fontWeight: '800', backgroundColor: '#e8f5eb', padding: 10, borderRadius: 9 }, error: { color: '#a8443d', backgroundColor: '#fff0ef', borderRadius: 9, padding: 10, textAlign: 'right', lineHeight: 20 }, notice: { color: '#23633c', backgroundColor: '#e8f5eb', borderRadius: 9, padding: 10, textAlign: 'right', lineHeight: 20 }, empty: { color: '#718394', textAlign: 'right', lineHeight: 21, paddingVertical: 8 }, emptyCard: { backgroundColor: '#fff', borderWidth: 1, borderColor: '#dce6e9', borderRadius: 13, padding: 15, gap: 6 }, templateCard: { flexDirection: 'column', alignItems: 'stretch', gap: 12, backgroundColor: '#fff', borderWidth: 1, borderColor: '#dce6e9', borderRadius: 13, padding: 12 }, templateInfo: { width: '100%', gap: 4 }, templateTitle: { color: '#17324d', fontSize: 16, fontWeight: '900', textAlign: 'right' }, description: { color: '#536978', textAlign: 'right', lineHeight: 20, fontSize: 12 }, previewGrid: { gap: 8 }, previewField: { backgroundColor: '#f7fafb', borderColor: '#edf1f3', borderWidth: 1, borderRadius: 10, padding: 9, gap: 5 }, previewLabel: { color: '#29475a', textAlign: 'right', fontWeight: '800' }, previewInput: { minHeight: 34, borderWidth: 1, borderColor: '#d6e0e4', borderRadius: 8, justifyContent: 'center', paddingHorizontal: 9 }, calculated: { color: '#17324d', textAlign: 'right', fontWeight: '800' }, signaturePlaceholder: { height: 48, borderWidth: 1, borderStyle: 'dashed', borderColor: '#9aacb6', borderRadius: 8, alignItems: 'center', justifyContent: 'center' },
});
