import { useEffect, useState } from 'react';
import { supabase } from './lib/supabase';

async function request<T>(path: string): Promise<T> {
  const session = (await supabase?.auth.getSession())?.data.session;
  if (!session) throw new Error('missing_session');
  const response = await fetch(path, { headers: { Authorization: `Bearer ${session.access_token}` } });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(body.error ?? 'request_failed');
  return body as T;
}

function Frame({ title, onBack, children }: { title: string; onBack: () => void; children: React.ReactNode }) {
  return <section className="management-page"><div className="management-head"><div><p className="eyebrow">المتابعة الإدارية والتنفيذية</p><h2>{title}</h2></div><button className="ghost-button" onClick={onBack}>العودة للوحة التحكم</button></div>{children}</section>;
}

type Summary = { receiptsApproved: number; taskStatuses: Record<string, number> };
type Notification = { id: string; title: string; body: string; severity: string; read_at: string | null; created_at: string };
type AuditLog = { id: string; action: string; entity_type: string; created_at: string };

export function ReportsPage({ onBack }: { onBack: () => void }) {
  const [summary, setSummary] = useState<Summary | null>(null);
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [logs, setLogs] = useState<AuditLog[]>([]);
  const [error, setError] = useState('');
  const [fromDate, setFromDate] = useState('');
  const [toDate, setToDate] = useState('');
  useEffect(() => { void (async () => { try { const [s, n, l] = await Promise.all([request<Summary>('/api/reports/summary'), request<{ notifications: Notification[] }>('/api/notifications'), request<{ logs: AuditLog[] }>('/api/audit-logs')]); setSummary(s); setNotifications(n.notifications); setLogs(l.logs); } catch (e) { setError(e instanceof Error ? e.message : 'تعذر تحميل التقارير'); } })(); }, []);
  const inDateRange = (value: string) => {
    const date = new Date(value).toISOString().slice(0, 10);
    return (!fromDate || date >= fromDate) && (!toDate || date <= toDate);
  };
  const visibleLogs = logs.filter((log) => inDateRange(log.created_at));
  const visibleNotifications = notifications.filter((notification) => inDateRange(notification.created_at));
  function exportLogs() {
    const escape = (value: string) => `"${value.replaceAll('"', '""')}"`;
    const rows = [['العملية', 'نوع السجل', 'المعرف', 'التاريخ'], ...visibleLogs.map((log) => [log.action, log.entity_type, log.id, log.created_at])];
    const csv = `\uFEFF${rows.map((row) => row.map(escape).join(',')).join('\r\n')}`;
    const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }));
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = `alshaeri-audit-${fromDate || 'all'}-${toDate || 'all'}.csv`;
    anchor.click();
    URL.revokeObjectURL(url);
  }
  return <Frame title="التقارير والرقابة" onBack={onBack}>
    {error && <p className="form-error" role="alert">{error}</p>}
    <section className="metric-row"><div className="metric-card"><span>تحصيل معتمد</span><strong>{(summary?.receiptsApproved ?? 0).toFixed(3)}</strong><small>إجمالي سندات القبض ضمن نطاق المؤسسة</small></div><div className="metric-card"><span>المهام</span><strong>{Object.values(summary?.taskStatuses ?? {}).reduce((sum, count) => sum + count, 0)}</strong><small>ملخص المؤسسة غير مفلتر بالتاريخ</small></div></section>
    <section className="table-card"><div className="card-heading"><div><h3>تصفية وتصدير</h3><span>الفلاتر تطبق على السجل والتنبيهات المحمّلة (آخر 100 سجل و50 تنبيهًا)</span></div><button className="ghost-button" type="button" onClick={exportLogs} disabled={!visibleLogs.length}>تصدير السجل CSV</button></div><div className="filter-grid"><label>من تاريخ<input type="date" value={fromDate} onChange={(event) => setFromDate(event.target.value)} /></label><label>إلى تاريخ<input type="date" value={toDate} onChange={(event) => setToDate(event.target.value)} /></label></div></section>
    <div className="management-grid"><section className="table-card"><div className="card-heading"><h3>التنبيهات</h3><span>{visibleNotifications.filter((n) => !n.read_at).length} غير مقروء</span></div><div className="data-list">{visibleNotifications.map((n) => <article className="data-row" key={n.id}><div><strong>{n.title}</strong><small>{n.body}</small></div><span className={`status-badge ${n.read_at ? 'archived' : n.severity}`}>{n.read_at ? 'مقروء' : 'جديد'}</span></article>)}{!visibleNotifications.length && <p className="empty-state">لا توجد تنبيهات ضمن الفترة المختارة.</p>}</div></section><section className="table-card"><div className="card-heading"><h3>سجل الرقابة</h3><span>{visibleLogs.length} من آخر 100 عملية</span></div><div className="data-list">{visibleLogs.map((log) => <article className="data-row" key={log.id}><div><strong>{log.action}</strong><small>{log.entity_type} · {new Intl.DateTimeFormat('ar-SA', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(log.created_at))}</small></div></article>)}{!visibleLogs.length && <p className="empty-state">لا توجد سجلات ضمن الفترة المختارة.</p>}</div></section></div>
  </Frame>;
}
