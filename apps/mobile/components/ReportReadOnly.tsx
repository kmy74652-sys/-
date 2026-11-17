import { StyleSheet, Text, View } from 'react-native';
import type { ReportField } from '../lib/reportSchema';

type Props = { fields: ReportField[]; values: Record<string, unknown> | null | undefined };

function displayValue(field: ReportField, value: unknown): string {
  if (value === null || value === undefined || value === '') return '—';
  if (field.type === 'signature') {
    const data = value as { strokes?: unknown[]; acknowledged?: boolean; signature_attachment_id?: string };
    return data?.acknowledged || data?.signature_attachment_id || (Array.isArray(data?.strokes) && data.strokes.length) ? 'تم التوقيع والإقرار' : 'لم يوقّع';
  }
  if (field.type === 'boolean' || field.type === 'checkbox') return value === true ? 'نعم' : value === false ? 'لا' : String(value);
  if (['attachment', 'image', 'file'].includes(field.type)) {
    const items = Array.isArray(value) ? value : [value];
    return items.map((item) => {
      if (typeof item === 'string') return item;
      if (!item || typeof item !== 'object') return String(item);
      const file = item as Record<string, unknown>;
      return String(file.file_name ?? file.original_name ?? file.name ?? 'مرفق');
    }).join('، ');
  }
  if (typeof value === 'object') {
    try { return JSON.stringify(value); } catch { return 'قيمة محفوظة'; }
  }
  return String(value);
}

export default function ReportReadOnly({ fields, values }: Props) {
  return <View style={styles.container}>
    {fields.map((field) => <View key={field.key} style={styles.row}>
      <Text style={styles.label}>{field.label}{field.required ? ' *' : ''}</Text>
      <Text selectable style={styles.value}>{displayValue(field, values?.[field.key])}</Text>
      {!!field.description && <Text style={styles.description}>{field.description}</Text>}
    </View>)}
    {!fields.length && <Text style={styles.empty}>لا يحتوي هذا النموذج على حقول.</Text>}
  </View>;
}

const styles = StyleSheet.create({
  container: { gap: 9 },
  row: { backgroundColor: '#f7fafb', borderWidth: 1, borderColor: '#e2e9eb', borderRadius: 10, padding: 11, gap: 4 },
  label: { color: '#29475a', fontWeight: '800', textAlign: 'right' },
  value: { color: '#17324d', textAlign: 'right', lineHeight: 21 },
  description: { color: '#718394', textAlign: 'right', fontSize: 12 },
  empty: { color: '#718394', textAlign: 'right' },
});
