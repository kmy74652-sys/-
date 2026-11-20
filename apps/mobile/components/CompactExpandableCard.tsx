import { ReactNode, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

export default function CompactExpandableCard({ title, subtitle, status, children, defaultExpanded = false, onEdit, onDelete }: { title: string; subtitle?: string; status?: string; children: ReactNode; defaultExpanded?: boolean; onEdit?: () => void; onDelete?: () => void }) {
  const [expanded, setExpanded] = useState(defaultExpanded);
  return <View style={styles.card}>
    <View style={styles.summary}>
      <Pressable accessibilityRole="button" accessibilityState={{ expanded }} accessibilityLabel={expanded ? `طي ${title}` : `فتح ${title}`} style={styles.toggle} onPress={() => setExpanded((value) => !value)}><Text style={styles.chevron}>{expanded ? '⌃' : '⌄'}</Text></Pressable>
      <View style={styles.copy}><Text style={styles.title}>{title}</Text>{!!subtitle && <Text style={styles.subtitle}>{subtitle}</Text>}{!!status && <Text style={styles.status}>{status}</Text>}</View>
      <View style={styles.actions}>{onEdit && <Pressable accessibilityRole="button" accessibilityLabel={`تعديل ${title}`} style={styles.iconButton} onPress={onEdit}><Text style={styles.editGlyph}>✎</Text></Pressable>}{onDelete && <Pressable accessibilityRole="button" accessibilityLabel={`حذف ${title}`} style={[styles.iconButton, styles.deleteButton]} onPress={onDelete}><Text style={styles.deleteGlyph}>حذف</Text></Pressable>}</View>
    </View>
    {expanded && <View style={styles.body}>{children}</View>}
  </View>;
}
const styles = StyleSheet.create({ card: { backgroundColor: '#fff', borderRadius: 16, borderWidth: 1, borderColor: '#dce5ef', padding: 12, shadowColor: '#17324d', shadowOpacity: 0.07, shadowRadius: 7, shadowOffset: { width: 0, height: 3 }, elevation: 2, gap: 10 }, summary: { flexDirection: 'row-reverse', alignItems: 'center', gap: 8 }, toggle: { width: 34, height: 34, borderRadius: 10, backgroundColor: '#eef4f8', alignItems: 'center', justifyContent: 'center' }, chevron: { color: '#0b3458', fontSize: 20, fontWeight: '900', lineHeight: 22 }, copy: { flex: 1, minWidth: 0, alignItems: 'flex-end', gap: 2 }, title: { color: '#0b3458', fontSize: 16, fontWeight: '900', textAlign: 'right' }, subtitle: { color: '#637188', fontSize: 11, textAlign: 'right' }, status: { color: '#9a6814', fontSize: 11, fontWeight: '800', textAlign: 'right' }, actions: { flexDirection: 'row-reverse', gap: 5 }, iconButton: { width: 34, height: 34, borderRadius: 9, backgroundColor: '#f4f8fb', alignItems: 'center', justifyContent: 'center' }, editGlyph: { color: '#0b3458', fontSize: 19, fontWeight: '900' }, deleteButton: { backgroundColor: '#fff0ef' }, deleteGlyph: { color: '#a8443d', fontSize: 10, fontWeight: '900' }, body: { borderTopWidth: 1, borderTopColor: '#edf1f3', paddingTop: 10, gap: 10 } });
