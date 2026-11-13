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
type Notification = { id: string; title: string; body: string; severity: string; read_at: string | null };
type AuditLog = { id: string; action: string; entity_type: string; created_at: string };

export function ReportsPage({ onBack }: { onBack: () => void }) {
  const [summary, setSummary] = useState<Summary | null>(null);
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [logs, setLogs] = useState<AuditLog[]>([]);
  const [error, setError] = useState('');
  useEffect(() => { void (async () => { try { const [s, n, l] = await Promise.all([request<Summary>('/api/reports/summary'), request<{ notifications: Notification[] }>('/api/notifications'), request<{ logs: AuditLog[] }>('/api/audit-logs')]); setSummary(s); setNotifications(n.notifications); setLogs(l.logs); } catch (e) { setError(e instanceof Error ? e.message : 'تعذر تحميل التقارير'); } })(); }, []);
  return <Frame title="التقارير والرقابة" onBack={onBack}>
    {error && <p className="form-error" role="alert">{error}</p>}
    <section className="metric-row"><div className="metric-card"><span>تحصيل معتمد</span><strong>{(summary?.receiptsApproved ?? 0).toFixed(3)}</strong><small>من سندات القبض</small></div><div className="metric-card"><span>المهام</span><strong>{Object.values(summary?.taskStatuses ?? {}).reduce((sum, count) => sum + count, 0)}</strong><small>ضمن نطاق المؤسسة</small></div></section>
    <div className="management-grid"><section className="table-card"><div className="card-heading"><h3>التنبيهات</h3><span>{notifications.filter((n) => !n.read_at).length} غير مقروء</span></div><div className="data-list">{notifications.map((n) => <article className="data-row" key={n.id}><div><strong>{n.title}</strong><small>{n.body}</small></div><span className={`status-badge ${n.read_at ? 'archived' : n.severity}`}>{n.read_at ? 'مقروء' : 'جديد'}</span></article>)}{!notifications.length && <p className="empty-state">لا توجد تنبيهات.</p>}</div></section><section className="table-card"><div className="card-heading"><h3>سجل الرقابة</h3><span>آخر 100 عملية</span></div><div className="data-list">{logs.map((log) => <article className="data-row" key={log.id}><div><strong>{log.action}</strong><small>{log.entity_type} · {new Intl.DateTimeFormat('ar-SA', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(log.created_at))}</small></div></article>)}{!logs.length && <p className="empty-state">لا توجد سجلات رقابة.</p>}</div></section></div>
  </Frame>;
}
