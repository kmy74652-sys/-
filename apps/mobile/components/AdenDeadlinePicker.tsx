import { useState } from 'react';
import { Modal, Platform, Pressable, StyleSheet, Text, View } from 'react-native';
import DateTimePicker, { type DateTimePickerEvent } from '@react-native-community/datetimepicker';

export const ADEN_TIME_ZONE = 'Asia/Aden';

export function currentAdenDateTime() {
  // A deadline set to the current minute can become earlier than the dispatch
  // request by the time the assignment RPC runs.
  const target = new Date(Date.now() + 60 * 60 * 1000);
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: ADEN_TIME_ZONE, year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  }).formatToParts(target);
  const value = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return { date: `${value.year}-${value.month}-${value.day}`, time: `${value.hour}:${value.minute}` };
}

type Props = {
  date: string;
  time: string;
  onChange: (date: string, time: string) => void;
};

function partsFromDate(date: Date) {
  return {
    date: `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`,
    time: `${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`,
  };
}

function dateFromParts(date: string, time: string) {
  const [year, month, day] = date.split('-').map(Number);
  const [hour, minute] = time.split(':').map(Number);
  return new Date(year, month - 1, day, hour, minute);
}

export function adenDateTimeToIso(date: string, time: string): string | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || !/^\d{2}:\d{2}$/.test(time)) return null;
  const [year, month, day] = date.split('-').map(Number);
  const [hour, minute] = time.split(':').map(Number);
  const calendarDate = new Date(Date.UTC(year, month - 1, day));
  if (calendarDate.getUTCFullYear() !== year || calendarDate.getUTCMonth() !== month - 1 || calendarDate.getUTCDate() !== day || hour > 23 || minute > 59) return null;
  const instant = new Date(Date.UTC(year, month - 1, day, hour - 3, minute));
  return instant.toISOString();
}

function formattedDateTime(date: string, time: string) {
  if (!adenDateTimeToIso(date, time)) return 'اختر التاريخ والوقت';
  const instant = new Date(adenDateTimeToIso(date, time)!);
  const dateLabel = new Intl.DateTimeFormat('en-GB', { timeZone: ADEN_TIME_ZONE, day: '2-digit', month: '2-digit', year: 'numeric' }).format(instant);
  const timeParts = new Intl.DateTimeFormat('en-GB', { timeZone: ADEN_TIME_ZONE, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).formatToParts(instant);
  const timeValues = Object.fromEntries(timeParts.map((part) => [part.type, part.value]));
  const hour24 = Number(timeValues.hour);
  const hour12 = hour24 % 12 || 12;
  const timeLabel = `${hour12}:${timeValues.minute} ${hour24 < 12 ? 'صباحًا' : 'مساءً'}`;
  return `${dateLabel} · ${timeLabel}`;
}

export default function AdenDeadlinePicker({ date, time, onChange }: Props) {
  const [mode, setMode] = useState<'date' | 'time' | null>(null);
  const value = date && time ? dateFromParts(date, time) : new Date();
  const onPickerChange = (event: DateTimePickerEvent, selected?: Date) => {
    if (Platform.OS === 'android') setMode(null);
    if (event.type !== 'set' || !selected) return;
    const parts = partsFromDate(selected);
    onChange(mode === 'date' ? parts.date : date || parts.date, mode === 'time' ? parts.time : time || parts.time);
  };
  return <View style={styles.container}>
    <Text style={styles.label}>الموعد النهائي — توقيت عدن</Text>
    <View style={styles.row}>
      <Pressable accessibilityRole="button" style={styles.button} onPress={() => setMode('date')}><Text style={styles.buttonText}>اختيار التاريخ</Text></Pressable>
      <Pressable accessibilityRole="button" style={styles.button} onPress={() => setMode('time')}><Text style={styles.buttonText}>اختيار الوقت</Text></Pressable>
    </View>
    <Text accessibilityLiveRegion="polite" style={styles.value}>{formattedDateTime(date, time)}</Text>
    {mode && <Modal transparent animationType="fade" visible onRequestClose={() => setMode(null)}>
      <View style={styles.backdrop}><View style={styles.modal}>
        <Text style={styles.label}>{mode === 'date' ? 'اختر التاريخ' : 'اختر الوقت'}</Text>
        <DateTimePicker value={value} mode={mode} display={Platform.OS === 'ios' ? 'spinner' : 'default'} onChange={onPickerChange} is24Hour={false} locale="ar-YE" themeVariant="light" />
        {Platform.OS === 'ios' && <Pressable style={styles.done} onPress={() => setMode(null)}><Text style={styles.doneText}>تم</Text></Pressable>}
      </View></View>
    </Modal>}
  </View>;
}

const styles = StyleSheet.create({
  container: { gap: 8 }, label: { color: '#29475a', fontWeight: '800', textAlign: 'right' },
  row: { flexDirection: 'row-reverse', gap: 8 }, button: { flex: 1, minHeight: 46, alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#b9cbd2', borderRadius: 10, backgroundColor: '#f8fbfc', padding: 10 },
  buttonText: { color: '#17324d', fontWeight: '800' }, value: { textAlign: 'right', color: '#536978', paddingVertical: 4 },
  backdrop: { flex: 1, justifyContent: 'center', padding: 20, backgroundColor: '#0007' }, modal: { backgroundColor: '#fff', borderRadius: 16, padding: 16, gap: 10 },
  done: { minHeight: 44, alignItems: 'center', justifyContent: 'center', borderRadius: 10, backgroundColor: '#17324d' }, doneText: { color: '#fff', fontWeight: '800' },
});
