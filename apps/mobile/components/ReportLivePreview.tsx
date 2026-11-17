import { useMemo, useRef, useState } from 'react';
import { Animated, Modal, PanResponder, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import ReportFieldInput from './ReportFieldInput';
import { designerFieldsToPreviewFields, evaluateReportField, reportDefaultDraft, type DesignerField } from '../lib/reportSchema';

type Props = { fields: DesignerField[]; title: string; description: string };

export default function ReportLivePreview({ fields, title, description }: Props) {
  const [visible, setVisible] = useState(true);
  const [expanded, setExpanded] = useState(false);
  const [values, setValues] = useState<Record<string, string>>({});
  const position = useRef(new Animated.ValueXY({ x: 0, y: 0 })).current;
  const panResponder = useMemo(() => PanResponder.create({
    onStartShouldSetPanResponder: () => false,
    onMoveShouldSetPanResponder: (_, gesture) => Math.abs(gesture.dx) + Math.abs(gesture.dy) > 3,
    onPanResponderMove: Animated.event([null, { dx: position.x, dy: position.y }], { useNativeDriver: false }),
    onPanResponderGrant: () => position.extractOffset(),
    onPanResponderRelease: () => position.flattenOffset(),
  }), [position]);
  const previewFields = useMemo(() => designerFieldsToPreviewFields(fields), [fields]);
  const previewValues = useMemo(() => {
    const result: Record<string, unknown> = {};
    for (const field of previewFields) {
      const raw = values[field.key] ?? reportDefaultDraft(field);
      if (!raw) continue;
      if (['table', 'multiselect', 'signature'].includes(field.type)) {
        try { result[field.key] = JSON.parse(raw); } catch { /* incomplete preview input */ }
      } else if (['boolean', 'checkbox'].includes(field.type)) {
        if (raw === 'true' || raw === 'false') result[field.key] = raw === 'true';
      } else if (['number', 'progress', 'integer', 'quantity', 'money'].includes(field.type)) {
        result[field.key] = /^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$/.test(raw) ? Number(raw) : raw;
      } else result[field.key] = raw;
    }
    return result;
  }, [previewFields, values]);

  function body() {
    return <View style={styles.previewForm}>
      <View style={styles.formHeading}>
        <Text style={styles.formTitle}>{title.trim() || 'عنوان النموذج'}</Text>
        {!!description.trim() && <Text style={styles.formDescription}>{description.trim()}</Text>}
        <Text style={styles.localOnly}>معاينة تجريبية — لا تُحفظ أي قيمة أو تغييرات</Text>
      </View>
      {!previewFields.length ? <Text style={styles.empty}>أضف حقلًا إلى المخطط لتراه هنا فورًا.</Text> : previewFields.map((field) => {
        const raw = values[field.key] ?? reportDefaultDraft(field);
        const calculation = field.type === 'calculated' ? evaluateReportField(field, previewFields, previewValues) : { value: null, error: null };
        let rows: Array<Record<string, unknown>> = [];
        if (field.type === 'table' && raw) {
          try { const parsed: unknown = JSON.parse(raw); if (Array.isArray(parsed)) rows = parsed as Array<Record<string, unknown>>; } catch { /* empty table draft */ }
        }
        return <ReportFieldInput
          key={field.key}
          field={field}
          previewMode
          raw={raw}
          attachments={[]}
          calculated={calculation.value}
          calculationError={calculation.error}
          rows={rows}
          onDraftChange={(value) => setValues((current) => ({ ...current, [field.key]: value }))}
          onTableChange={(nextRows) => setValues((current) => ({ ...current, [field.key]: JSON.stringify(nextRows) }))}
          onChooseAttachment={() => undefined}
        />;
      })}
    </View>;
  }

  if (!visible) return <View style={styles.hiddenRow}><Text style={styles.hiddenHint}>المعاينة المباشرة مخفية مؤقتًا</Text><Pressable accessibilityRole="button" onPress={() => setVisible(true)} style={styles.smallButton}><Text style={styles.smallButtonText}>إظهار المعاينة</Text></Pressable></View>;

  return <View style={styles.panel}>
    <View style={styles.panelHeader}>
      <View style={styles.headingCopy}><Text style={styles.heading}>المعاينة المباشرة</Text><Text style={styles.subheading}>تتحدث مع كل تعديل دون حفظ النموذج</Text></View>
      <View style={styles.controls}>
        <Pressable accessibilityRole="button" onPress={() => { position.setValue({ x: 0, y: 0 }); position.setOffset({ x: 0, y: 0 }); setExpanded(true); }} style={styles.smallButton}><Text style={styles.smallButtonText}>تكبير</Text></Pressable>
        <Pressable accessibilityRole="button" onPress={() => setVisible(false)} style={styles.hideButton}><Text style={styles.hideButtonText}>إخفاء</Text></Pressable>
      </View>
    </View>
    <ScrollView style={styles.miniScroll} nestedScrollEnabled keyboardShouldPersistTaps="handled" showsVerticalScrollIndicator>
      {body()}
    </ScrollView>
    <Modal visible={expanded} transparent animationType="fade" statusBarTranslucent onRequestClose={() => setExpanded(false)}>
      <View style={styles.backdrop}>
        <Animated.View style={[styles.fullCard, { transform: position.getTranslateTransform() }]}>
          <View style={styles.dragHandle} {...panResponder.panHandlers}>
            <View style={styles.handlePill} />
            <View style={styles.fullHeader}>
              <View style={styles.headingCopy}><Text style={styles.heading}>معاينة التقرير كاملة</Text><Text style={styles.subheading}>اسحب من الشريط لتحريك اللوحة</Text></View>
              <Pressable accessibilityRole="button" onPress={() => setExpanded(false)} style={styles.hideButton}><Text style={styles.hideButtonText}>إغلاق</Text></Pressable>
            </View>
          </View>
          <ScrollView style={styles.fullScroll} contentContainerStyle={styles.fullContent} keyboardShouldPersistTaps="handled" nestedScrollEnabled>
            {body()}
          </ScrollView>
        </Animated.View>
      </View>
    </Modal>
  </View>;
}

const styles = StyleSheet.create({
  panel: { backgroundColor: '#fff', borderColor: '#b8cbd3', borderWidth: 1, borderRadius: 14, padding: 10, gap: 9 },
  panelHeader: { flexDirection: 'row-reverse', alignItems: 'center', justifyContent: 'space-between', gap: 8 },
  headingCopy: { flex: 1, gap: 2 }, heading: { color: '#17324d', fontSize: 15, fontWeight: '900', textAlign: 'right' },
  subheading: { color: '#718394', fontSize: 11, textAlign: 'right' }, controls: { flexDirection: 'row-reverse', gap: 6 },
  smallButton: { borderRadius: 8, backgroundColor: '#17324d', paddingHorizontal: 12, minHeight: 34, justifyContent: 'center', alignItems: 'center' },
  smallButtonText: { color: '#fff', fontWeight: '800', fontSize: 12 }, hideButton: { borderRadius: 8, backgroundColor: '#edf2f4', paddingHorizontal: 12, minHeight: 34, justifyContent: 'center', alignItems: 'center' },
  hideButtonText: { color: '#39556a', fontWeight: '800', fontSize: 12 }, miniScroll: { maxHeight: 280, borderRadius: 10, backgroundColor: '#f4f7f8' },
  previewForm: { gap: 9, padding: 10 }, formHeading: { gap: 5, paddingBottom: 4 }, formTitle: { color: '#17324d', fontWeight: '900', fontSize: 17, textAlign: 'right' },
  formDescription: { color: '#536978', lineHeight: 20, textAlign: 'right' }, localOnly: { color: '#718394', fontSize: 11, textAlign: 'right' },
  empty: { color: '#718394', textAlign: 'center', padding: 20 }, hiddenRow: { minHeight: 50, borderRadius: 12, borderColor: '#dce6e9', borderWidth: 1, backgroundColor: '#fff', padding: 8, flexDirection: 'row-reverse', alignItems: 'center', justifyContent: 'space-between' },
  hiddenHint: { color: '#718394', textAlign: 'right', fontSize: 12 }, backdrop: { flex: 1, backgroundColor: '#0b1a29aa', justifyContent: 'center', alignItems: 'center' },
  fullCard: { position: 'absolute', top: '7%', left: '3%', width: '94%', height: '86%', backgroundColor: '#f4f7f8', borderRadius: 18, overflow: 'hidden', borderWidth: 1, borderColor: '#bacbd2', elevation: 18 },
  dragHandle: { backgroundColor: '#fff', paddingHorizontal: 12, paddingBottom: 10, borderBottomWidth: 1, borderBottomColor: '#e1e9ec' }, handlePill: { width: 42, height: 5, backgroundColor: '#aebdc4', borderRadius: 4, alignSelf: 'center', marginVertical: 8 },
  fullHeader: { flexDirection: 'row-reverse', alignItems: 'center', gap: 8 }, fullScroll: { flex: 1 }, fullContent: { paddingBottom: 24 },
});
