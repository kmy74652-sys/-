import { useMemo, useRef, useState } from 'react';
import { PanResponder, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import Svg, { Path } from 'react-native-svg';
import type { PickedAttachment } from '../lib/taskAttachments';
import { normalizeTableColumns, type ReportField, type ReportTableColumn } from '../lib/reportSchema';

type Attachment = PickedAttachment & { path?: string };
type TableRow = Record<string, unknown>;
type SignatureValue = { strokes: string[]; acknowledged: boolean };
type Props = {
  field: ReportField;
  previewMode?: boolean;
  raw: string;
  attachments: Attachment[];
  calculated: number | null;
  calculationError?: string | null;
  rows: TableRow[];
  onDraftChange: (value: string) => void;
  onTableChange: (rows: TableRow[]) => void;
  onChooseAttachment: () => void;
};

function objectValue(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : {};
}
function parseStringArray(value: string): string[] {
  try {
    const parsed = JSON.parse(value);
    return Array.isArray(parsed) ? parsed.filter((item): item is string => typeof item === 'string') : [];
  } catch { return []; }
}
function parseSignature(value: string): SignatureValue {
  try {
    const parsed = objectValue(JSON.parse(value));
    return { strokes: Array.isArray(parsed.strokes) ? parsed.strokes.filter((path): path is string => typeof path === 'string') : [], acknowledged: parsed.acknowledged === true };
  } catch { return { strokes: [], acknowledged: false }; }
}
function validationHint(field: ReportField): string {
  const rules = objectValue(field.validation);
  const config = objectValue(field.config);
  const parts: string[] = [];
  if (rules.min !== undefined || rules.max !== undefined) parts.push(`النطاق ${rules.min ?? '—'} إلى ${rules.max ?? '—'}`);
  if (rules.min_length !== undefined || rules.max_length !== undefined) parts.push(`طول النص ${rules.min_length ?? 0}–${rules.max_length ?? 'مفتوح'}`);
  if (rules.decimal_places !== undefined) parts.push(`حتى ${rules.decimal_places} منازل عشرية`);
  if (config.min_rows !== undefined || config.max_rows !== undefined) parts.push(`الصفوف ${config.min_rows ?? 0}–${config.max_rows ?? 'مفتوحة'}`);
  if (config.unit) parts.push(`الوحدة: ${String(config.unit)}`);
  return parts.join(' · ');
}

export default function ReportFieldInput(props: Props) {
  const { field, previewMode = false, raw, attachments, calculated, calculationError, rows, onDraftChange, onTableChange, onChooseAttachment } = props;
  const description = field.description?.trim();
  const hint = validationHint(field);
  const setBoolean = () => onDraftChange(raw === 'true' ? 'false' : 'true');
  return (
    <View style={styles.field}>
      <View style={styles.labelLine}>
        <Text style={styles.label}>{field.label}{field.required ? ' *' : ''}</Text>
        <Text style={styles.typeBadge}>{field.type.replace('_', ' ')}</Text>
      </View>
      {!!description && <Text style={styles.description}>{description}</Text>}
      {!!hint && <Text style={styles.hint}>{hint}</Text>}
      {field.type === 'calculated' ? (
        <View style={styles.calculated}>
          <Text style={calculationError ? styles.calculationError : styles.calculatedValue}>{calculationError ?? (calculated === null ? 'أكمل الحقول المرتبطة' : new Intl.NumberFormat('ar-SA', { maximumFractionDigits: 8 }).format(calculated))}</Text>
          {!calculationError && <Text style={styles.hint}>يُحسب آليًا · {String(objectValue(field.config).formula ?? 'صيغة غير محددة')}</Text>}
        </View>
      ) : field.type === 'table' ? (
        <TableEditor field={field} rows={rows} onChange={onTableChange} />
      ) : ['attachment', 'image', 'file'].includes(field.type) ? (
        <View style={styles.attachmentBox}>
          <Pressable accessibilityRole="button" disabled={previewMode} style={[styles.secondaryButton, previewMode && styles.disabled]} onPress={onChooseAttachment}>
            <Text style={styles.secondaryText}>{previewMode ? 'معاينة المرفقات فقط — لا يتم الرفع' : 'اختيار مرفق من الهاتف'}</Text>
          </Pressable>
          {!!attachments.length && <Text style={styles.description}>{attachments.map((file) => file.name).join('، ')}</Text>}
        </View>
      ) : field.type === 'signature' ? (
        <SignaturePad value={parseSignature(raw)} consentText={String(objectValue(field.config).consent_text ?? '')} onChange={(value) => onDraftChange(JSON.stringify(value))} />
      ) : field.type === 'boolean' || field.type === 'checkbox' ? (
        <Pressable accessibilityRole="checkbox" accessibilityState={{ checked: raw === 'true' }} style={[styles.booleanButton, raw === 'true' && styles.booleanSelected]} onPress={setBoolean}>
          <Text style={[styles.booleanText, raw === 'true' && styles.booleanTextSelected]}>{raw === '' ? 'لم يتم الاختيار' : raw === 'true' ? 'نعم ✓' : 'لا ✓'}</Text>
        </Pressable>
      ) : (field.type === 'select' || field.type === 'multiselect') && field.options?.length ? (
        <View style={styles.choices}>
          {field.options.map((option) => {
            const selected = field.type === 'multiselect' ? parseStringArray(raw || '[]').includes(option) : raw === option;
            return <Pressable key={option} accessibilityRole="button" accessibilityState={{ selected }} style={[styles.choice, selected && styles.choiceSelected]} onPress={() => {
              const next = field.type === 'multiselect'
                ? JSON.stringify(selected ? parseStringArray(raw || '[]').filter((item) => item !== option) : [...parseStringArray(raw || '[]'), option])
                : option;
              onDraftChange(next);
            }}><Text style={selected ? styles.choiceSelectedText : styles.choiceText}>{option}</Text></Pressable>;
          })}
        </View>
      ) : (
        field.type === 'money' && previewMode ? <View style={styles.moneyPreview}>
          <TextInput
            accessibilityLabel={field.label}
            style={[styles.input, styles.moneyInput]}
            value={raw}
            onChangeText={onDraftChange}
            keyboardType="decimal-pad"
            placeholder="أدخل المبلغ"
          />
          <View style={styles.currencyHint}><Text style={styles.currencyHintText}>عملة</Text></View>
        </View> : <TextInput
            accessibilityLabel={field.label}
            style={[styles.input, ['long_text', 'textarea', 'notes', 'decision_notes'].includes(field.type) && styles.multiline]}
            value={raw}
            onChangeText={onDraftChange}
            keyboardType={['number', 'progress', 'integer', 'quantity', 'money'].includes(field.type) ? 'decimal-pad' : 'default'}
            multiline={['long_text', 'textarea', 'notes', 'decision_notes'].includes(field.type)}
            placeholder={field.type === 'progress' ? 'أدخل نسبة الإنجاز' : ['date', 'datetime'].includes(field.type) ? 'أدخل التاريخ أو الوقت' : field.type === 'money' ? 'أدخل المبلغ' : field.required ? 'مطلوب' : 'اختياري'}
          />
      )}
    </View>
  );
}

function TableEditor({ field, rows, onChange }: { field: ReportField; rows: TableRow[]; onChange: (rows: TableRow[]) => void }) {
  const normalizedColumns = normalizeTableColumns(field);
  const columns = normalizedColumns.length ? normalizedColumns : [{ key: 'value', label: 'القيمة', type: 'short_text' as const, required: false }];
  const config = objectValue(field.config);
  const maxRows = Number(config.max_rows);
  const canAdd = !Number.isFinite(maxRows) || maxRows <= 0 || rows.length < maxRows;
  const numericColumns = columns.filter((column) => ['integer', 'quantity', 'money'].includes(column.type));
  const updateCell = (rowIndex: number, key: string, value: unknown) => onChange(rows.map((row, index) => index === rowIndex ? { ...row, [key]: value } : row));
  const addRow = () => onChange([...rows, Object.fromEntries(columns.map((column) => [column.key, column.type === 'boolean' ? null : '']))]);
  return (
    <View style={styles.tableEditor}>
      {!!config.min_rows && <Text style={styles.hint}>الحد الأدنى: {String(config.min_rows)} صفوف</Text>}
      {rows.map((row, rowIndex) => (
        <View style={styles.tableRow} key={`${field.key}-${rowIndex}`}>
          <View style={styles.rowHeading}><Text style={styles.rowTitle}>صف {rowIndex + 1}</Text><Pressable accessibilityRole="button" style={styles.deleteRow} onPress={() => onChange(rows.filter((_, index) => index !== rowIndex))}><Text style={styles.deleteText}>حذف الصف</Text></Pressable></View>
          <ScrollView horizontal showsHorizontalScrollIndicator contentContainerStyle={styles.tableCells}>
            {columns.map((column) => <TableCell key={column.key} column={column} value={row[column.key]} onChange={(value) => updateCell(rowIndex, column.key, value)} />)}
          </ScrollView>
        </View>
      ))}
      {numericColumns.length > 0 && rows.length > 0 && (
        <View style={styles.totalBox}>
          {numericColumns.map((column) => {
            const total = rows.reduce((sum, row) => {
              const value = Number(row[column.key]);
              return sum + (Number.isFinite(value) ? value : 0);
            }, 0);
            return <Text style={styles.totalText} key={column.key}>إجمالي {column.label}: {new Intl.NumberFormat('ar-SA', { maximumFractionDigits: 4 }).format(total)}</Text>;
          })}
        </View>
      )}
      <Pressable accessibilityRole="button" disabled={!canAdd} style={[styles.addRow, !canAdd && styles.disabled]} onPress={addRow}><Text style={styles.addRowText}>{canAdd ? '＋ إضافة صف' : `بلغت الحد الأعلى (${maxRows})`}</Text></Pressable>
    </View>
  );
}

function TableCell({ column, value, onChange }: { column: ReportTableColumn; value: unknown; onChange: (value: unknown) => void }) {
  const raw = value === null || value === undefined ? '' : String(value);
  return (
    <View style={styles.tableCell}>
      <Text style={styles.columnLabel}>{column.label}{column.required ? ' *' : ''}</Text>
      {column.type === 'select' ? (
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.cellChoices}>
          {(column.options ?? []).map((option) => <Pressable key={option} style={[styles.cellChoice, raw === option && styles.choiceSelected]} onPress={() => onChange(raw === option ? '' : option)}><Text style={raw === option ? styles.choiceSelectedText : styles.choiceText}>{option}</Text></Pressable>)}
        </ScrollView>
      ) : column.type === 'boolean' ? (
        <Pressable style={[styles.cellInput, raw === 'true' && styles.choiceSelected]} onPress={() => onChange(raw === 'true' ? 'false' : 'true')}><Text style={raw === 'true' ? styles.choiceSelectedText : styles.choiceText}>{raw === '' ? 'اختيار' : raw === 'true' ? 'نعم' : 'لا'}</Text></Pressable>
      ) : (
        <TextInput
          style={styles.cellInput}
          value={raw}
          onChangeText={onChange}
          keyboardType={['integer', 'quantity', 'money'].includes(column.type) ? 'decimal-pad' : 'default'}
          multiline={column.type === 'long_text'}
          placeholder={column.required ? 'مطلوب' : 'اختياري'}
        />
      )}
    </View>
  );
}

function SignaturePad({ value, consentText, onChange }: { value: SignatureValue; consentText: string; onChange: (value: SignatureValue) => void }) {
  const [currentPath, setCurrentPath] = useState('');
  const activePath = useRef('');
  const [width, setWidth] = useState(300);
  const height = 170;
  const responder = useMemo(() => PanResponder.create({
    onStartShouldSetPanResponder: () => true,
    onMoveShouldSetPanResponder: () => true,
    onPanResponderGrant: (event) => {
      const { locationX, locationY } = event.nativeEvent;
      activePath.current = `M ${locationX.toFixed(1)} ${locationY.toFixed(1)}`;
      setCurrentPath(activePath.current);
    },
    onPanResponderMove: (event) => {
      if (activePath.current.length > 15000) return;
      const { locationX, locationY } = event.nativeEvent;
      activePath.current += ` L ${locationX.toFixed(1)} ${locationY.toFixed(1)}`;
      setCurrentPath(activePath.current);
    },
    onPanResponderRelease: () => {
      const completed = activePath.current;
      activePath.current = '';
      setCurrentPath('');
      if (completed.length > 10) onChange({ ...value, strokes: [...value.strokes, completed] });
    },
    onPanResponderTerminate: () => { activePath.current = ''; setCurrentPath(''); },
  }), [onChange, value]);
  const clear = () => onChange({ ...value, strokes: [] });
  return (
    <View style={styles.signatureBox}>
      {!!consentText && <Text style={styles.consentText}>{consentText}</Text>}
      <View style={styles.signatureCanvas} onLayout={(event) => setWidth(Math.max(1, event.nativeEvent.layout.width))} {...responder.panHandlers}>
        <Svg width={width} height={height} viewBox={`0 0 ${width} ${height}`}>
          {value.strokes.map((path, index) => <Path key={index} d={path} stroke="#17324d" strokeWidth={3} strokeLinecap="round" strokeLinejoin="round" fill="none" />)}
          {!!currentPath && <Path d={currentPath} stroke="#17324d" strokeWidth={3} strokeLinecap="round" strokeLinejoin="round" fill="none" />}
        </Svg>
        {!value.strokes.length && !currentPath && <Text style={styles.signaturePlaceholder}>ارسم توقيعك بإصبعك هنا</Text>}
      </View>
      <View style={styles.signatureActions}>
        <Pressable accessibilityRole="button" onPress={clear} style={styles.secondaryButton}><Text style={styles.secondaryText}>مسح التوقيع</Text></Pressable>
        {!!consentText && <Pressable accessibilityRole="checkbox" accessibilityState={{ checked: value.acknowledged }} onPress={() => onChange({ ...value, acknowledged: !value.acknowledged })} style={[styles.consentButton, value.acknowledged && styles.choiceSelected]}><Text style={value.acknowledged ? styles.choiceSelectedText : styles.choiceText}>{value.acknowledged ? 'أوافق على الإقرار ✓' : 'أوافق على الإقرار'}</Text></Pressable>}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  field: { gap: 7, padding: 12, backgroundColor: '#fbfcfc', borderWidth: 1, borderColor: '#e2e9eb', borderRadius: 12 },
  labelLine: { flexDirection: 'row-reverse', alignItems: 'center', justifyContent: 'space-between', gap: 8 },
  label: { color: '#263f52', textAlign: 'right', fontWeight: '800', flex: 1 },
  typeBadge: { color: '#557184', backgroundColor: '#edf3f5', borderRadius: 12, paddingHorizontal: 8, paddingVertical: 4, fontSize: 11 },
  description: { color: '#657988', textAlign: 'right', lineHeight: 20 },
  hint: { color: '#718394', fontSize: 12, textAlign: 'right', lineHeight: 18 },
  input: { minHeight: 46, borderWidth: 1, borderColor: '#d6e0e4', borderRadius: 10, paddingHorizontal: 12, paddingVertical: 10, textAlign: 'right', color: '#17324d', backgroundColor: '#fff' },
  multiline: { minHeight: 100, textAlignVertical: 'top' },
  choices: { flexDirection: 'row-reverse', flexWrap: 'wrap', gap: 8 },
  choice: { borderRadius: 18, borderWidth: 1, borderColor: '#ccd9df', paddingHorizontal: 12, paddingVertical: 8, backgroundColor: '#fff' },
  choiceSelected: { backgroundColor: '#17324d', borderColor: '#17324d' },
  choiceText: { color: '#39556a', textAlign: 'center' },
  choiceSelectedText: { color: '#fff', fontWeight: '700', textAlign: 'center' },
  booleanButton: { minHeight: 46, alignItems: 'center', justifyContent: 'center', borderRadius: 10, borderWidth: 1, borderColor: '#ccd9df', backgroundColor: '#fff' },
  booleanSelected: { backgroundColor: '#17324d', borderColor: '#17324d' },
  booleanText: { color: '#39556a', fontWeight: '700' },
  booleanTextSelected: { color: '#fff' },
  calculated: { backgroundColor: '#eef5f7', borderRadius: 10, padding: 12, gap: 4 },
  calculatedValue: { color: '#17324d', fontSize: 19, fontWeight: '900', textAlign: 'right' },
  calculationError: { color: '#a8443d', fontSize: 13, fontWeight: '700', textAlign: 'right', lineHeight: 20 },
  attachmentBox: { gap: 8 },
  secondaryButton: { minHeight: 42, borderRadius: 10, padding: 10, alignItems: 'center', justifyContent: 'center', backgroundColor: '#e9f0f4' },
  secondaryText: { color: '#17324d', fontWeight: '800' },
  tableEditor: { gap: 10, borderWidth: 1, borderColor: '#dce6e9', borderRadius: 12, padding: 10, backgroundColor: '#fff' },
  tableRow: { gap: 8, borderBottomWidth: 1, borderBottomColor: '#edf1f3', paddingBottom: 10 },
  rowHeading: { flexDirection: 'row-reverse', justifyContent: 'space-between', alignItems: 'center' },
  rowTitle: { color: '#17324d', fontWeight: '800' },
  deleteRow: { paddingHorizontal: 10, paddingVertical: 6, backgroundColor: '#fff0ef', borderRadius: 8 },
  deleteText: { color: '#a8443d', fontWeight: '700', fontSize: 12 },
  tableCells: { flexDirection: 'row-reverse', gap: 8, paddingVertical: 2 },
  tableCell: { width: 180, gap: 5 },
  columnLabel: { color: '#39556a', textAlign: 'right', fontSize: 12, fontWeight: '700' },
  cellInput: { minHeight: 42, borderWidth: 1, borderColor: '#d6e0e4', borderRadius: 8, paddingHorizontal: 9, textAlign: 'right', color: '#17324d', backgroundColor: '#fbfcfc', justifyContent: 'center' },
  cellChoices: { flexDirection: 'row-reverse', gap: 5 },
  cellChoice: { borderRadius: 14, borderWidth: 1, borderColor: '#ccd9df', paddingHorizontal: 9, paddingVertical: 7 },
  totalBox: { gap: 4, padding: 9, borderRadius: 8, backgroundColor: '#eff6f1' },
  totalText: { color: '#23633c', textAlign: 'right', fontWeight: '700', fontSize: 12 },
  addRow: { minHeight: 42, alignItems: 'center', justifyContent: 'center', borderRadius: 9, backgroundColor: '#e8f0f4' },
  addRowText: { color: '#17324d', fontWeight: '800' },
  disabled: { opacity: 0.5 },
  moneyPreview: { flexDirection: 'row-reverse', alignItems: 'center', gap: 7 },
  moneyInput: { flex: 1 },
  currencyHint: { minHeight: 44, minWidth: 58, borderRadius: 9, backgroundColor: '#edf3f5', alignItems: 'center', justifyContent: 'center', paddingHorizontal: 8 },
  currencyHintText: { color: '#39556a', fontSize: 12, fontWeight: '800' },
  signatureBox: { gap: 8 },
  consentText: { color: '#39556a', textAlign: 'right', lineHeight: 22, padding: 10, backgroundColor: '#f7f9fa', borderRadius: 9 },
  signatureCanvas: { height: 170, borderWidth: 1, borderColor: '#b8c8d0', borderRadius: 10, backgroundColor: '#fff', overflow: 'hidden', justifyContent: 'center' },
  signaturePlaceholder: { position: 'absolute', alignSelf: 'center', color: '#a0afb7' },
  signatureActions: { flexDirection: 'row-reverse', alignItems: 'center', gap: 8 },
  consentButton: { flex: 1, minHeight: 42, alignItems: 'center', justifyContent: 'center', borderRadius: 9, borderWidth: 1, borderColor: '#ccd9df', paddingHorizontal: 8 },
});
