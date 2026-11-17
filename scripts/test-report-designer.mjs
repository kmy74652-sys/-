import assert from 'node:assert/strict';
import fs from 'node:fs';
import ts from 'typescript';

const read = (path) => fs.readFileSync(new URL(path, import.meta.url), 'utf8');
const migration = ['026_dynamic_report_designer.sql', '027_report_form_approval.sql', '028_snapshot_report_validation.sql', '029_snapshot_field_validation.sql', '030_calculated_report_validation.sql', '031_signature_report_validation.sql', '034_report_builder_integrity.sql']
  .map((file) => read(`../supabase/migrations/${file}`)).join('\n');
const currentMigration = read('../supabase/migrations/034_report_builder_integrity.sql');
const mobileDesigner = read('../apps/mobile/components/ReportDesigner.tsx');
const reportInput = read('../apps/mobile/components/ReportFieldInput.tsx');
const tasks = read('../apps/mobile/app/tasks.tsx');
const designerApi = read('../apps/mobile/lib/reportDesigner.ts');
const schemaSource = read('../apps/mobile/lib/reportSchema.ts');

const compiled = ts.transpileModule(schemaSource, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
}).outputText;
const schemaModule = { exports: {} };
new Function('exports', 'module', compiled)(schemaModule.exports, schemaModule);
const {
  calculateFormula,
  evaluateReportField,
  validateDesignerFields,
  validateReportFieldValue,
} = schemaModule.exports;

const designerField = (patch = {}) => ({
  field_key: 'quantity', label: 'الكمية', description: '', field_type: 'quantity', is_required: true,
  repeatable: false, sort_order: 0, options: [], validation: {}, config: {}, ...patch,
});
const runtimeField = (patch = {}) => ({
  key: 'quantity', label: 'الكمية', type: 'quantity', required: true, options: [], validation: {}, config: {}, ...patch,
});

// Safe arithmetic parser: precedence, parentheses, field references, division-by-zero and rejection of code.
assert.ok(Math.abs(calculateFormula('({quantity} * 2 + 4) / 3', { quantity: 5 }) - 14 / 3) < 1e-10);
assert.throws(() => calculateFormula('4 / 0', {}), /القسمة على صفر/);
assert.throws(() => calculateFormula('process.exit()', {}), /صيغة/);
assert.throws(() => calculateFormula('{missing} + 1', {}), /أكمل الحقل/);
const table = runtimeField({
  key: 'items', label: 'الأصناف', type: 'table', required: true,
  config: { columns: [{ key: 'qty', label: 'الكمية', type: 'quantity', required: true, validation: { min: 1 } }] },
});
const totalField = runtimeField({ key: 'total', label: 'الإجمالي', type: 'calculated', config: { formula: 'sum_rows(items.qty)' } });
assert.deepEqual(evaluateReportField(totalField, [table, totalField], { items: [{ qty: '2.5' }, { qty: 3 }] }), { value: 5.5, error: null });

// Validation rules for fields, list values, table columns and signatures.
assert.match(validateDesignerFields([designerField({ label: '   ' })]), /لا يمكن ترك الاسم فارغًا/);
assert.match(validateDesignerFields([designerField({ validation: { min: 10, max: 2 } })]), /الحد الأدنى أكبر/);
assert.equal(validateReportFieldValue(runtimeField({ validation: { min: 2, max: 10 } }), '1'), '«الكمية»: الحد الأدنى المسموح 2.');
assert.equal(validateReportFieldValue(runtimeField({ validation: { allow_negative: false } }), '-1'), '«الكمية»: القيم السالبة غير مسموحة.');
const selectField = runtimeField({ key: 'status', label: 'الحالة', type: 'select', options: ['جديد', 'مكتمل'] });
assert.match(validateReportFieldValue(selectField, 'غير معروف'), /الخيارات المتاحة/);
const listDesignerField = designerField({ field_key: 'status', label: 'الحالة', field_type: 'select', options: ['جديد', 'مكتمل'] });
assert.equal(validateDesignerFields([listDesignerField]), null);
const tableIssue = validateReportFieldValue(table, [{ qty: '0' }]);
assert.match(tableIssue, /الكمية/);
const consentSignature = runtimeField({
  key: 'signature', label: 'التوقيع', type: 'signature', required: false,
  config: { consent_text: 'أقر بصحة البيانات' },
});
assert.match(validateReportFieldValue(consentSignature, undefined), /التوقيع/);
assert.match(validateReportFieldValue(consentSignature, { strokes: ['M 1 1 L 2 2'], acknowledged: false }), /وافق/);
assert.equal(validateReportFieldValue(consentSignature, { strokes: ['M 1 1 L 2 2'], acknowledged: true }), null);

// UI/API coverage: structured editor, server draft RPC, dynamic tables, calculated values and drawn signatures.
assert(mobileDesigner.includes('مخطط الحقول') && mobileDesigner.includes('خصائص الحقل') && mobileDesigner.includes('معاينة الموظف'));
assert(mobileDesigner.includes('saveDesignerTemplate') && mobileDesigner.includes('approveDesignerVersion'));
assert(reportInput.includes('إضافة صف') && reportInput.includes('SignaturePad') && reportInput.includes('react-native-svg'));
assert(tasks.includes('validateReportFieldValue') && tasks.includes('evaluateReportField') && tasks.includes('reportDefaultDraft'));
assert(designerApi.includes("rpc('save_report_form_draft'") && designerApi.includes("rpc('approve_report_form_version'"));

// DB invariants: org-scoped access, approved versions, immutable snapshots/signatures and server validation.
for (const token of [
  'report_designer_allowed_for_org', 'report_can_review_in_org', 'save_report_form_draft',
  'approve_report_form_version', 'publish_task_report_form', 'create_task_with_report_form',
  'task_report_signature_immutable', 'task_reports_signature_protection', 'report_signature_immutable',
  'task_reports_select_scoped', 'report_form_version_requires_approval', 'task_report_snapshot_missing',
  'report_field_below_min', 'report_field_above_max', 'report_calculated_division_by_zero',
  'unknown_report_field', 'report_provenance_immutable',
]) assert(currentMigration.includes(token), `migration missing ${token}`);
assert.match(currentMigration, /revoke insert, update, delete on public\.task_reports/i);
assert.match(currentMigration, /grant select on public\.task_reports to authenticated/i);
assert.match(currentMigration, /length\(v_column->>'label'\)>200/i, 'table column label length check must compare outside length()');
assert.match(currentMigration, /a\.task_id=p_task_id and a\.uploaded_by=auth\.uid\(\) and a\.storage_path=v_attachment_path/i, 'report attachment must belong to the submitting user and task');
assert.match(currentMigration, /report_validate_field\(v_field,v_raw,p_values,v_task\.id\)/i, 'server field validation must receive the task id');
assert.match(migration, /alter table public\.report_form_templates enable row level security/i);
for (const protectedName of ['task_attachments', 'task_activity_log', 'mobile_task_timeline']) {
  assert(!new RegExp(`(?:create|alter|drop|truncate)\\s+(?:table|policy|trigger)?\\s*(?:if\\s+(?:not\\s+)?exists\\s+)?public\\.${protectedName}\\b`, 'i').test(currentMigration), `protected table ${protectedName} must not be structurally changed`);
}
assert(!/\b(?:insert|update|delete)\s+(?:into\s+)?storage\.buckets\b/i.test(currentMigration), 'protected storage bucket must not be modified');

console.log(JSON.stringify({ ok: true, safeFormulaEngine: true, validation: true, signatures: true, rlsAndSnapshots: true }));
