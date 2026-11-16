export type ReportFieldType =
  | 'text' | 'number' | 'progress' | 'status' | 'notes' | 'textarea' | 'date' | 'select' | 'multiselect'
  | 'checkbox' | 'attachment' | 'short_text' | 'long_text' | 'integer' | 'quantity' | 'money' | 'datetime'
  | 'boolean' | 'table' | 'image' | 'file' | 'signature' | 'calculated' | 'decision_notes';

export type ReportColumnType = 'short_text' | 'long_text' | 'integer' | 'quantity' | 'money' | 'select' | 'boolean';
export type ReportTableColumn = {
  key: string;
  label: string;
  type: ReportColumnType;
  required?: boolean;
  options?: string[];
  validation?: Record<string, unknown>;
};
export type ReportField = {
  key: string;
  label: string;
  description?: string | null;
  type: ReportFieldType;
  options?: string[];
  required?: boolean;
  repeatable?: boolean;
  validation?: Record<string, unknown>;
  config?: Record<string, unknown>;
};
export type DesignerField = {
  field_key: string;
  label: string;
  description: string;
  field_type: ReportFieldType;
  is_required: boolean;
  repeatable: boolean;
  sort_order: number;
  options: string[];
  validation: Record<string, unknown>;
  config: Record<string, unknown>;
};
export type ReportValues = Record<string, unknown>;

const numericTypes = new Set(['number', 'progress', 'integer', 'quantity', 'money']);
const textTypes = new Set(['text', 'short_text', 'long_text', 'textarea', 'notes', 'decision_notes', 'status']);
const validFieldTypes = new Set<ReportFieldType>([
  'text', 'number', 'progress', 'status', 'notes', 'textarea', 'date', 'select', 'multiselect', 'checkbox', 'attachment',
  'short_text', 'long_text', 'integer', 'quantity', 'money', 'datetime', 'boolean', 'table', 'image', 'file', 'signature',
  'calculated', 'decision_notes',
]);
const validColumnTypes = new Set<ReportColumnType>(['short_text', 'long_text', 'integer', 'quantity', 'money', 'select', 'boolean']);

function asObject(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : {};
}
function isEmpty(value: unknown): boolean {
  if (value === null || value === undefined) return true;
  if (typeof value === 'string') return value.trim().length === 0;
  if (Array.isArray(value)) return value.length === 0;
  if (typeof value === 'object') return Object.keys(value as Record<string, unknown>).length === 0;
  return false;
}
function numericValue(value: unknown): number | null {
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  if (typeof value !== 'string' || !value.trim() || !/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$/.test(value.trim())) return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}
function message(field: ReportField, key: string, fallback: string): string {
  const messages = asObject(asObject(field.validation).messages);
  const custom = messages[key];
  return typeof custom === 'string' && custom.trim() ? custom.trim() : `«${field.label}»: ${fallback}`;
}

export function normalizeTableColumns(field: Pick<ReportField, 'config'>): ReportTableColumn[] {
  const raw = asObject(field.config).columns;
  if (!Array.isArray(raw)) return [];
  return raw.map((item, index) => {
    if (typeof item === 'string') {
      // Backward compatibility with snapshots that stored just column labels.
      return { key: item, label: item, type: 'short_text', required: false, validation: {} };
    }
    const column = asObject(item);
    const key = String(column.key ?? `column_${index + 1}`);
    const label = String(column.label ?? column.name ?? key);
    const typeValue = String(column.type ?? column.field_type ?? 'short_text') as ReportColumnType;
    return {
      key,
      label,
      type: validColumnTypes.has(typeValue) ? typeValue : 'short_text',
      required: Boolean(column.required ?? column.is_required),
      options: Array.isArray(column.options) ? column.options.map(String) : [],
      validation: asObject(column.validation),
    };
  });
}

export function reportDefaultValue(field: ReportField): unknown {
  const configured = asObject(field.config).default_value;
  if (configured !== undefined && configured !== null) return configured;
  if (field.type === 'multiselect' || field.type === 'table') return [];
  return undefined;
}

export function reportDefaultDraft(field: ReportField): string {
  const value = reportDefaultValue(field);
  if (value === undefined) return '';
  if (typeof value === 'string') return value;
  if (typeof value === 'number' || typeof value === 'boolean') return String(value);
  try { return JSON.stringify(value); } catch { return ''; }
}

function validateScalar(type: string, value: unknown, rules: Record<string, unknown>, label: string): string | null {
  if (numericTypes.has(type)) {
    const parsed = numericValue(value);
    if (parsed === null) return `«${label}»: أدخل رقمًا صحيح الصيغة.`;
    const min = numericValue(rules.min);
    const max = numericValue(rules.max);
    const decimals = numericValue(rules.decimal_places);
    if (type === 'integer' && !Number.isInteger(parsed)) return `«${label}»: أدخل رقمًا صحيحًا بلا كسور.`;
    if (min !== null && parsed < min) return `«${label}»: الحد الأدنى المسموح ${min}.`;
    if (max !== null && parsed > max) return `«${label}»: الحد الأقصى المسموح ${max}.`;
    if (rules.allow_negative === false && parsed < 0) return `«${label}»: القيم السالبة غير مسموحة.`;
    if (rules.allow_zero === false && parsed === 0) return `«${label}»: يجب أن تكون القيمة أكبر من صفر.`;
    if (decimals !== null && decimals >= 0 && Math.round(decimals) === decimals && Number(parsed.toFixed(Math.min(decimals, 10))) !== parsed) {
      return `«${label}»: الحد الأقصى للمنازل العشرية ${decimals}.`;
    }
    return null;
  }
  if (textTypes.has(type)) {
    if (typeof value !== 'string') return `«${label}»: أدخل نصًا صالحًا.`;
    const rulesObject = rules;
    const minLength = numericValue(rulesObject.min_length);
    const maxLength = numericValue(rulesObject.max_length);
    if (minLength !== null && value.trim().length < minLength) return `«${label}»: أدخل ${minLength} أحرف على الأقل.`;
    if (maxLength !== null && value.length > maxLength) return `«${label}»: الحد الأقصى ${maxLength} حرفًا.`;
  }
  return null;
}

export function validateReportFieldValue(field: ReportField, value: unknown): string | null {
  const required = Boolean(field.required);
  if (isEmpty(value)) {
    const consentRequired = field.type === 'signature' && Boolean(String(asObject(field.config).consent_text ?? '').trim());
    if (field.type === 'signature' && (required || consentRequired)) return message(field, consentRequired ? 'consent' : 'required', consentRequired ? 'ارسم توقيعك ووافق على نص الإقرار.' : 'ارسم التوقيع قبل الإرسال.');
    const minRows = field.type === 'table' ? numericValue(asObject(field.config).min_rows) : null;
    if (minRows !== null && minRows > 0) return `«${field.label}»: أضف ${minRows} صفوف على الأقل.`;
    return required ? message(field, 'required', 'هذا الحقل مطلوب.') : null;
  }
  const rules = asObject(field.validation);
  if (numericTypes.has(field.type) || textTypes.has(field.type)) {
    const issue = validateScalar(field.type, value, rules, field.label);
    if (issue) {
      const min = numericValue(rules.min);
      const max = numericValue(rules.max);
      const minLength = numericValue(rules.min_length);
      const maxLength = numericValue(rules.max_length);
      if (issue.includes('الحد الأدنى المسموح') && typeof rules.messages === 'object') return message(field, 'min', issue);
      if (issue.includes('الحد الأقصى المسموح') && typeof rules.messages === 'object') return message(field, 'max', issue);
      if (minLength !== null && issue.includes('على الأقل')) return message(field, 'min_length', issue);
      if (maxLength !== null && issue.includes('الحد الأقصى')) return message(field, 'max_length', issue);
      if (String(asObject(rules.messages).invalid ?? '').trim()) return message(field, 'invalid', issue);
      return issue;
    }
    return null;
  }
  if (field.type === 'select') {
    const options = (field.options ?? []).map(String);
    return typeof value === 'string' && options.includes(value) ? null : message(field, 'option', 'اختر قيمة من الخيارات المتاحة.');
  }
  if (field.type === 'multiselect') {
    if (!Array.isArray(value) || value.some((item) => typeof item !== 'string' || !(field.options ?? []).includes(item))) return message(field, 'option', 'تحقق من الاختيارات المحددة.');
    if (new Set(value).size !== value.length) return message(field, 'option', 'لا تكرر الاختيار نفسه.');
    return null;
  }
  if (field.type === 'boolean' || field.type === 'checkbox') return typeof value === 'boolean' ? null : message(field, 'type', 'اختر نعم أو لا.');
  if (field.type === 'datetime' || field.type === 'date') {
    if (typeof value !== 'string' || !value.trim() || Number.isNaN(Date.parse(value))) return message(field, 'type', 'أدخل تاريخًا صالحًا.');
    return null;
  }
  if (field.type === 'table') {
    if (!Array.isArray(value)) return message(field, 'type', 'أدخل صفوف الجدول بصيغة صحيحة.');
    const config = asObject(field.config);
    const minRows = numericValue(config.min_rows);
    const maxRows = numericValue(config.max_rows);
    if (minRows !== null && value.length < minRows) return `«${field.label}»: أضف ${minRows} صفوف على الأقل.`;
    if (maxRows !== null && value.length > maxRows) return `«${field.label}»: الحد الأقصى ${maxRows} صفًا.`;
    const columns = normalizeTableColumns(field);
    for (let rowIndex = 0; rowIndex < value.length; rowIndex += 1) {
      const row = asObject(value[rowIndex]);
      for (const column of columns) {
        const cell = row[column.key];
        if (isEmpty(cell)) {
          if (column.required) return `«${field.label}»، الصف ${rowIndex + 1}: أكمل «${column.label}».`;
          continue;
        }
        const cellIssue = validateScalar(column.type, cell, asObject(column.validation), column.label);
        if (cellIssue) return `«${field.label}»، الصف ${rowIndex + 1}: ${cellIssue}`;
        if (column.type === 'select' && !(column.options ?? []).includes(String(cell))) return `«${field.label}»، الصف ${rowIndex + 1}: اختر «${column.label}» من القائمة.`;
        if (column.type === 'boolean' && typeof cell !== 'boolean' && cell !== 'true' && cell !== 'false') return `«${field.label}»، الصف ${rowIndex + 1}: اختر نعم أو لا في «${column.label}».`;
      }
    }
    return null;
  }
  if (field.type === 'calculated') return numericValue(value) === null ? message(field, 'type', 'تعذر حساب قيمة رقمية صالحة.') : null;
  if (field.type === 'signature') {
    const signature = asObject(value);
    const strokes = signature.strokes;
    const consentText = String(asObject(field.config).consent_text ?? '').trim();
    if ((required || consentText) && (!Array.isArray(strokes) || strokes.length === 0)) return message(field, consentText ? 'consent' : 'required', consentText ? 'ارسم توقيعك ووافق على نص الإقرار.' : 'ارسم التوقيع قبل الإرسال.');
    if (Array.isArray(strokes) && strokes.some((path) => typeof path !== 'string' || path.length > 16000)) return message(field, 'type', 'بيانات التوقيع غير صالحة.');
    if (consentText && signature.acknowledged !== true) return message(field, 'consent', 'وافق على نص الإقرار قبل التوقيع.');
    return null;
  }
  if (field.type === 'image' || field.type === 'file' || field.type === 'attachment') {
    return Array.isArray(value) || (typeof value === 'object' && value !== null) ? null : message(field, 'type', 'اختر مرفقًا صالحًا.');
  }
  return null;
}

function tokenize(expression: string): string[] {
  const result: string[] = [];
  const tokenPattern = /\s*(\d+(?:\.\d+)?|\{[a-z][a-z0-9_]{0,63}\}|[()+\-*/])\s*/gy;
  let cursor = 0;
  while (cursor < expression.length) {
    tokenPattern.lastIndex = cursor;
    const match = tokenPattern.exec(expression);
    if (!match || match.index !== cursor) throw new Error('صيغة الحقل المحسوب غير صالحة. استخدم الأرقام ومفاتيح الحقول بين أقواس معقوفة والعمليات + - * /.');
    result.push(match[1]);
    cursor = tokenPattern.lastIndex;
  }
  if (!result.length) throw new Error('صيغة الحقل المحسوب فارغة.');
  return result;
}

export function formulaReferences(expression: string): string[] {
  return [...new Set((expression.match(/\{([a-z][a-z0-9_]{0,63})\}/g) ?? []).map((token) => token.slice(1, -1)))];
}

export function calculateFormula(expression: string, values: ReportValues): number | null {
  const normalized = expression.trim();
  const legacySum = normalized.match(/^sum\(([a-z][a-z0-9_]*)\)$/);
  if (legacySum) {
    const value = values[legacySum[1]];
    return isEmpty(value) ? 0 : numericValue(value);
  }
  const legacyDifference = normalized.match(/^difference\(([a-z][a-z0-9_]*),\s*([a-z][a-z0-9_]*)\)$/);
  if (legacyDifference) {
    const left = numericValue(values[legacyDifference[1]]) ?? 0;
    const right = numericValue(values[legacyDifference[2]]) ?? 0;
    return left - right;
  }
  const tokens = tokenize(normalized);
  let index = 0;
  function primary(): number {
    const token = tokens[index++];
    if (!token) throw new Error('صيغة الحقل المحسوب غير مكتملة.');
    if (token === '+') return primary();
    if (token === '-') return -primary();
    if (token === '(') {
      const value = expressionValue();
      if (tokens[index++] !== ')') throw new Error('قوس إغلاق مفقود في الصيغة.');
      return value;
    }
    if (token.startsWith('{')) {
      const key = token.slice(1, -1);
      const value = numericValue(values[key]);
      if (value === null) throw new Error(`أكمل الحقل «${key}» قبل الحساب.`);
      return value;
    }
    if (/^\d/.test(token)) return Number(token);
    throw new Error('متوقع رقم أو مفتاح حقل في صيغة الحساب.');
  }
  function term(): number {
    let value = primary();
    while (tokens[index] === '*' || tokens[index] === '/') {
      const operator = tokens[index++];
      const right = primary();
      if (operator === '/' && right === 0) throw new Error('لا يمكن القسمة على صفر.');
      value = operator === '*' ? value * right : value / right;
    }
    return value;
  }
  function expressionValue(): number {
    let value = term();
    while (tokens[index] === '+' || tokens[index] === '-') {
      const operator = tokens[index++];
      const right = term();
      value = operator === '+' ? value + right : value - right;
    }
    return value;
  }
  const value = expressionValue();
  if (index !== tokens.length) throw new Error('يوجد جزء غير مفهوم بعد صيغة الحساب.');
  if (!Number.isFinite(value)) throw new Error('نتيجة الحساب خارج النطاق الرقمي.');
  return value;
}

export type ReportCalculationResult = { value: number | null; error: string | null };

export function evaluateReportField(field: ReportField, allFields: ReportField[], values: ReportValues): ReportCalculationResult {
  const formula = String(asObject(field.config).formula ?? '').trim();
  const sumRows = formula.match(/^sum_rows\(([^.]{1,64})\.([^)]{1,64})\)$/);
  if (sumRows) {
    const sourceField = allFields.find((item) => item.key === sumRows[1]);
    if (!sourceField || sourceField.type !== 'table') return { value: null, error: 'جدول المصدر غير موجود.' };
    const rows = values[sumRows[1]];
    if (!Array.isArray(rows)) return { value: 0, error: null };
    let total = 0;
    for (const rawRow of rows) {
      const rawValue = asObject(rawRow)[sumRows[2]];
      if (isEmpty(rawValue)) continue;
      const numeric = numericValue(rawValue);
      if (numeric === null) return { value: null, error: `أدخل قيمة رقمية صالحة في عمود ${sumRows[2]}.` };
      total += numeric;
    }
    return { value: total, error: null };
  }
  try { return { value: calculateFormula(formula, values), error: null }; }
  catch (cause) { return { value: null, error: cause instanceof Error ? cause.message : 'تعذر حساب الصيغة.' }; }
}

export function calculateReportField(field: ReportField, allFields: ReportField[], values: ReportValues): number | null {
  return evaluateReportField(field, allFields, values).value;
}

export function validateDesignerFields(fields: DesignerField[]): string | null {
  if (!fields.length) return 'أضف حقلًا واحدًا على الأقل إلى النموذج.';
  if (fields.length > 100) return 'لا يمكن أن يتجاوز النموذج 100 حقل.';
  const keys = new Set<string>();
  for (let index = 0; index < fields.length; index += 1) {
    const field = fields[index];
    const label = field.label.trim();
    if (!label) return `أدخل اسمًا واضحًا للحقل ${index + 1}؛ لا يمكن ترك الاسم فارغًا.`;
    if (label.length > 200) return `اسم الحقل «${label.slice(0, 30)}» أطول من 200 محرف.`;
    if (!/^[a-z][a-z0-9_]{0,63}$/.test(field.field_key)) return `مفتاح الحقل «${field.field_key}» غير صالح؛ استخدم حروفًا إنجليزية صغيرة وأرقامًا وشرطة سفلية.`;
    if (keys.has(field.field_key)) return `مفتاح الحقل «${field.field_key}» مكرر.`;
    keys.add(field.field_key);
    if (!validFieldTypes.has(field.field_type)) return `نوع الحقل «${field.field_type}» غير مدعوم.`;
    const rules = asObject(field.validation);
    const min = numericValue(rules.min); const max = numericValue(rules.max);
    const minLength = numericValue(rules.min_length); const maxLength = numericValue(rules.max_length);
    const decimals = numericValue(rules.decimal_places);
    if (min !== null && max !== null && min > max) return `في الحقل «${label}»، الحد الأدنى أكبر من الحد الأقصى.`;
    if (minLength !== null && maxLength !== null && minLength > maxLength) return `في الحقل «${label}»، أقل طول للنص أكبر من أقصاه.`;
    if (decimals !== null && (!Number.isInteger(decimals) || decimals < 0 || decimals > 8)) return `في الحقل «${label}»، المنازل العشرية يجب أن تكون من 0 إلى 8.`;
    if ((field.field_type === 'select' || field.field_type === 'multiselect') && (!field.options.length || field.options.some((option) => !option.trim()))) return `أضف خيارًا صحيحًا واحدًا على الأقل للحقل «${label}».`;
    if (new Set(field.options.map((option) => option.trim())).size !== field.options.length) return `توجد خيارات مكررة في الحقل «${label}».`;
    if (field.field_type === 'select' && field.config.default_value !== undefined && !field.options.includes(String(field.config.default_value))) return `القيمة الافتراضية للحقل «${label}» غير موجودة في الخيارات.`;
    if (field.field_type === 'multiselect' && field.config.default_value !== undefined && (!Array.isArray(field.config.default_value) || field.config.default_value.some((value) => !field.options.includes(String(value))))) return `تحقق من القيمة الافتراضية للحقل «${label}».`;
    if (field.field_type === 'table') {
      const columns = normalizeTableColumns({ config: field.config });
      if (!columns.length) return `أضف عمودًا واحدًا على الأقل إلى جدول «${label}».`;
      if (columns.length > 20) return `لا يمكن أن يتجاوز جدول «${label}» 20 عمودًا.`;
      const columnKeys = new Set<string>();
      for (const column of columns) {
        if (!column.label.trim() || !/^[a-z][a-z0-9_]{0,63}$/.test(column.key)) return `تحقق من اسم ومفتاح العمود «${column.label}» في «${label}».`;
        if (columnKeys.has(column.key)) return `مفتاح العمود «${column.key}» مكرر في «${label}».`;
        columnKeys.add(column.key);
        if (column.type === 'select' && (!column.options?.length || column.options.some((option) => !option.trim()) || new Set(column.options.map((option) => option.trim())).size !== column.options.length)) return `تحقق من الخيارات في عمود «${column.label}» ضمن «${label}».`;
        const columnRules = asObject(column.validation);
        const columnMin = numericValue(columnRules.min); const columnMax = numericValue(columnRules.max);
        const columnDecimals = numericValue(columnRules.decimal_places);
        if (columnMin !== null && columnMax !== null && columnMin > columnMax) return `في عمود «${column.label}»، الحد الأدنى أكبر من الحد الأقصى.`;
        if (columnDecimals !== null && (!Number.isInteger(columnDecimals) || columnDecimals < 0 || columnDecimals > 8)) return `في عمود «${column.label}»، المنازل العشرية يجب أن تكون من 0 إلى 8.`;
      }
      const tableConfig = asObject(field.config);
      const minRows = numericValue(tableConfig.min_rows); const maxRows = numericValue(tableConfig.max_rows);
      if (minRows !== null && (!Number.isInteger(minRows) || minRows < 0 || minRows > 500)) return `الحد الأدنى لصفوف «${label}» يجب أن يكون من 0 إلى 500.`;
      if (maxRows !== null && (!Number.isInteger(maxRows) || maxRows < 1 || maxRows > 500)) return `الحد الأعلى لصفوف «${label}» يجب أن يكون من 1 إلى 500.`;
      if (minRows !== null && maxRows !== null && minRows > maxRows) return `عدد الصفوف الأدنى أكبر من الأقصى في «${label}».`;
    }
    if (field.field_type === 'calculated') {
      const formula = String(field.config.formula ?? '').trim();
      if (!formula) return `أدخل صيغة الحقل المحسوب «${label}».`;
      const allowedKeys = new Set(fields.filter((candidate) => numericTypes.has(candidate.field_type)).map((candidate) => candidate.field_key));
      const sumRows = formula.match(/^sum_rows\(([^.]{1,64})\.([^)]{1,64})\)$/);
      if (sumRows) {
        const source = fields.find((candidate) => candidate.field_key === sumRows[1]);
        const rawColumns = asObject(source?.config).columns;
        const legacyColumn = Array.isArray(rawColumns) && rawColumns.some((column) => typeof column === 'string' && column === sumRows[2]);
        if (!source || source.field_type !== 'table' || (!legacyColumn && !normalizeTableColumns({ config: source.config }).some((column) => column.key === sumRows[2] && numericTypes.has(column.type)))) return `صيغة الجمع في «${label}» تشير إلى عمود غير رقمي أو غير موجود.`;
      } else {
        const legacy = formula.match(/^sum\(([a-z][a-z0-9_]*)\)$/) || formula.match(/^difference\(([a-z][a-z0-9_]*),\s*([a-z][a-z0-9_]*)\)$/);
        if (legacy) {
          const references = legacy.slice(1).filter(Boolean);
          if (references.some((key) => !allowedKeys.has(key))) return `صيغة «${label}» تشير إلى حقل رقمي غير موجود.`;
        } else {
          try {
            const references = formulaReferences(formula);
            if (!references.length || references.some((key) => !allowedKeys.has(key) || key === field.field_key)) return `صيغة «${label}» يجب أن تشير إلى حقول رقمية موجودة بين أقواس معقوفة.`;
            calculateFormula(formula, Object.fromEntries(references.map((key) => [key, 2])));
          } catch (cause) { return (cause as Error).message; }
        }
      }
    }
    const defaultValue = field.config.default_value;
    if (defaultValue !== undefined && defaultValue !== null && !isEmpty(defaultValue)) {
      const runtimeField: ReportField = { key: field.field_key, label, type: field.field_type, options: field.options, required: field.is_required, validation: field.validation, config: field.config };
      const defaultIssue = validateReportFieldValue(runtimeField, defaultValue);
      if (defaultIssue) return `القيمة الافتراضية للحقل «${label}» غير صالحة: ${defaultIssue}`;
    }
  }
  return null;
}
