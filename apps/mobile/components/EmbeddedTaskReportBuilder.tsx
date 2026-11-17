import React from 'react';
import { Pressable, Text, TextInput, View, StyleSheet } from 'react-native';
import { designerFieldTypes, type DesignerField } from '../lib/reportDesigner';

type Props = { fields: DesignerField[]; required: boolean; onChange: (fields: DesignerField[]) => void; onRequiredChange: (required: boolean) => void };

const keyFor = (label: string, index: number) => {
  const ascii = label.trim().toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
  return ascii || `field_${index + 1}`;
};
const emptyField = (index: number): DesignerField => ({ field_key: `field_${index + 1}`, label: '', description: '', field_type: 'short_text', is_required: false, repeatable: false, sort_order: index, options: [], validation: {}, config: {} });

export default function EmbeddedTaskReportBuilder({ fields, required, onChange, onRequiredChange }: Props) {
  const update = (index: number, patch: Partial<DesignerField>) => onChange(fields.map((field, current) => current === index ? { ...field, ...patch } : field));
  const add = () => onChange([...fields, emptyField(fields.length)]);
  const remove = (index: number) => onChange(fields.filter((_, current) => current !== index).map((field, sort_order) => ({ ...field, sort_order })));
  return <View style={styles.panel}>
    <View style={styles.header}><View style={{ flex: 1 }}><Text style={styles.title}>نموذج التقرير داخل المهمة</Text><Text style={styles.hint}>أنشئ الحقول التي سيعبئها الموظف لهذه المهمة. لا تحتاج لفتح مصمم تقارير منفصل.</Text></View><Pressable style={styles.add} onPress={add}><Text style={styles.addText}>+ حقل</Text></Pressable></View>
    <Pressable style={[styles.required, required && styles.requiredOn]} onPress={() => onRequiredChange(!required)}><Text style={styles.requiredText}>{required ? 'التقرير إلزامي عند تنفيذ المهمة ✓' : 'التقرير اختياري عند تنفيذ المهمة ○'}</Text></Pressable>
    {fields.length === 0 && <Text style={styles.hint}>أضف أول حقل حسب طبيعة العمل: مبلغ، صنف، كمية، عميل، صورة، ملاحظة أو جدول.</Text>}
    {fields.map((field, index) => <View key={`${field.field_key}-${index}`} style={styles.card}>
      <View style={styles.header}><Text style={styles.number}>الحقل {index + 1}</Text><Pressable onPress={() => remove(index)}><Text style={styles.remove}>حذف</Text></Pressable></View>
      <TextInput style={styles.input} value={field.label} onChangeText={(label) => update(index, { label, field_key: field.field_key.startsWith('field_') ? keyFor(label, index) : field.field_key })} placeholder="اسم الحقل للموظف" textAlign="right" />
      <TextInput style={styles.input} value={field.description} onChangeText={(description) => update(index, { description })} placeholder="شرح أو تعليمات الحقل (اختياري)" textAlign="right" />
      <Text style={styles.label}>نوع الحقل</Text><View style={styles.chips}>{designerFieldTypes.map(([code, label]) => <Pressable key={code} style={[styles.chip, field.field_type === code && styles.chipSelected]} onPress={() => update(index, { field_type: code })}><Text style={field.field_type === code ? styles.chipSelectedText : styles.chipText}>{label}</Text></Pressable>)}</View>
      {(field.field_type === 'select' || field.field_type === 'multiselect') && <TextInput style={styles.input} value={field.options.join('، ')} onChangeText={(value) => update(index, { options: value.split('،').map((item) => item.trim()).filter(Boolean) })} placeholder="خيارات مفصولة بعلامة ،" textAlign="right" />}
      {field.field_type === 'calculated' && <TextInput style={styles.input} value={String(field.config.formula ?? '')} onChangeText={(formula) => update(index, { config: { ...field.config, formula } })} placeholder="مثال: difference(book_balance,actual_quantity)" autoCapitalize="none" textAlign="right" />}
      <View style={styles.toggles}><Pressable style={[styles.toggle, field.is_required && styles.toggleOn]} onPress={() => update(index, { is_required: !field.is_required })}><Text style={styles.toggleText}>{field.is_required ? 'إلزامي ✓' : 'اختياري ○'}</Text></Pressable><Pressable style={[styles.toggle, field.repeatable && styles.toggleOn]} onPress={() => update(index, { repeatable: !field.repeatable })}><Text style={styles.toggleText}>{field.repeatable ? 'متكرر ✓' : 'غير متكرر ○'}</Text></Pressable></View>
    </View>)}
  </View>;
}

const styles = StyleSheet.create({ panel: { backgroundColor: '#fff', borderColor: '#dce6e9', borderWidth: 1, borderRadius: 14, padding: 12, gap: 10 }, header: { flexDirection: 'row-reverse', alignItems: 'flex-start', justifyContent: 'space-between', gap: 8 }, title: { color: '#17324d', fontWeight: '900', fontSize: 15, textAlign: 'right' }, hint: { color: '#718394', fontSize: 12, lineHeight: 19, textAlign: 'right' }, add: { backgroundColor: '#17324d', borderRadius: 9, paddingHorizontal: 11, paddingVertical: 9 }, addText: { color: '#fff', fontWeight: '900' }, required: { borderWidth: 1, borderColor: '#dce6e9', borderRadius: 9, padding: 10, alignSelf: 'flex-end' }, requiredOn: { backgroundColor: '#eff8f2', borderColor: '#8bb5a0' }, requiredText: { color: '#285844', fontWeight: '800', textAlign: 'right' }, card: { borderWidth: 1, borderColor: '#e2eaed', borderRadius: 11, padding: 10, gap: 8, backgroundColor: '#fbfcfc' }, number: { color: '#17324d', fontWeight: '900', textAlign: 'right' }, remove: { color: '#a8443d', fontWeight: '800' }, input: { minHeight: 42, borderWidth: 1, borderColor: '#d6e0e4', borderRadius: 9, paddingHorizontal: 10, paddingVertical: 8, backgroundColor: '#fff', color: '#17324d' }, label: { color: '#39556a', fontWeight: '800', textAlign: 'right' }, chips: { flexDirection: 'row-reverse', flexWrap: 'wrap', gap: 6 }, chip: { borderWidth: 1, borderColor: '#cbd8de', borderRadius: 16, paddingHorizontal: 8, paddingVertical: 7 }, chipSelected: { backgroundColor: '#17324d', borderColor: '#17324d' }, chipText: { color: '#39556a', fontSize: 11 }, chipSelectedText: { color: '#fff', fontWeight: '800', fontSize: 11 }, toggles: { flexDirection: 'row-reverse', gap: 7 }, toggle: { borderWidth: 1, borderColor: '#dce6e9', borderRadius: 9, paddingHorizontal: 9, paddingVertical: 8 }, toggleOn: { backgroundColor: '#eff8f2', borderColor: '#8bb5a0' }, toggleText: { color: '#285844', fontWeight: '800', fontSize: 12 } });
