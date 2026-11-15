import { useCallback, useEffect, useMemo, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { supabase } from './lib/supabase';
import { BranchesPage, CustomersPage, EmployeesPage, RolesPage, TaskLibraryPage, TasksPage } from './management';
import { ReportsPage } from './business';
import { ReportDesignerPage } from './reportDesigner';
import './styles.css';

type EmployeeProfile = {
  id: string;
  institutionId: string;
  employeeNo: string;
  fullName: string;
  email: string | null;
  phone: string | null;
  status: string;
  roles: Array<{ code: string; nameAr: string }>;
  permissions: string[];
  branches: Array<{ id: string; code: string; name: string; isDefault: boolean }>;
};

const modules = [
  ['الموظفون', 'employees.read', '/employees', 'إدارة ملفات الموظفين وحالاتهم'],
  ['الفروع', 'branches.read_all', '/branches', 'عرض نطاق الفروع المرتبطة بالمؤسسة'],
  ['الأدوار والصلاحيات', 'roles.read', '/roles', 'مراجعة الوصول المؤسسي'],
  ['المهام والمتابعة', 'tasks.read', '/tasks', 'متابعة الحالة والإنجاز'],
  ['مكتبة المهام', 'task_library.read', '/task-library', 'قوالب المهام ونماذج التقارير'],
  ['مصمم التقارير', 'report_forms.manage', '/report-designer', 'مكتبة القوالب وإصدارات التقارير'],
  ['العملاء والحسابات', 'customers.read', '/customers', 'كشوف الحساب والتحصيل والحدود'],
  ['التقارير والرقابة', 'finance.read', '/reports', 'ملخص مالي وتنبيهات وسجل التدقيق'],
] as const;

function Login({ onLoggedIn }: { onLoggedIn: () => void }) {
  const [employeeNo, setEmployeeNo] = useState('');
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!supabase) return setError('إعدادات Supabase العامة غير متاحة في هذه النسخة.');
    if (!employeeNo.trim() || !/^\S{8,64}$/.test(code)) return setError('أدخل رقم الموظف ورمزًا من 8 إلى 64 محرفًا دون مسافات.');
    setBusy(true); setError('');
    try {
      const { data, error: functionError } = await supabase.functions.invoke('employee-code-auth', { body: { action: 'login', employeeNo: employeeNo.trim(), code } });
      if (functionError) { const status = (functionError as { context?: { status?: number } }).context?.status; setError(status === 429 ? 'محاولات كثيرة. انتظر 15 دقيقة ثم حاول مجددًا.' : status === 401 ? 'رقم الموظف أو رمز الدخول غير صحيح.' : 'تعذر الاتصال بخدمة الدخول بالرمز.'); return; }
      if (typeof data?.access_token !== 'string' || typeof data?.refresh_token !== 'string') { setError('لم تُرجع خدمة الدخول جلسة صالحة.'); return; }
      const { error: sessionError } = await supabase.auth.setSession({ access_token: data.access_token, refresh_token: data.refresh_token });
      if (sessionError) throw sessionError;
      setCode(''); onLoggedIn();
    } catch { setError('تعذر إكمال تسجيل الدخول بالرمز. تحقق من الاتصال وحاول مجددًا.'); } finally { setBusy(false); }
  }
  return <main className="auth-shell"><section className="auth-card"><div className="brand-mark">ش</div><p className="eyebrow">دخول الموظفين بالرمز</p><h1>تسجيل الدخول إلى برنامج الشاعري</h1><p className="auth-copy">استخدم رقم الموظف والرمز الذي أنشأه صاحب المؤسسة أو المدير المخول. لا يحتاج الموظف إلى بريد إلكتروني للدخول.</p><form onSubmit={submit} className="auth-form"><label>رقم الموظف<input inputMode="numeric" autoComplete="username" value={employeeNo} onChange={(event) => setEmployeeNo(event.target.value)} required /></label><label>رمز الدخول<input type="password" autoComplete="current-password" value={code} onChange={(event) => setCode(event.target.value)} minLength={8} maxLength={64} required /></label>{error && <p className="form-error" role="alert">{error}</p>}<button type="submit" disabled={busy}>{busy ? 'جارٍ التحقق…' : 'دخول بالرمز'}</button></form><p className="auth-footnote">يتم التحقق من الرمز على خدمة Supabase مع تحديد محاولات الدخول.</p></section></main>;
}

function Dashboard({ profile, onLogout }: { profile: EmployeeProfile; onLogout: () => void }) {
  const today = useMemo(() => new Intl.DateTimeFormat('ar-SA', { dateStyle: 'full' }).format(new Date()), []);
  const hasPermission = useCallback((permission: string) => profile.permissions.includes(permission), [profile.permissions]);
  const visibleModules = modules.filter(([, permission]) => hasPermission(permission));
  const roleLabel = profile.roles.map((role) => role.nameAr).join('، ') || 'دور غير محدد';

  return (
    <main className="shell">
      <aside className="sidebar">
        <div className="brand-mark">ش</div>
        <div><p className="eyebrow">مساحة موظف مصادق</p><h1>برنامج الشاعري</h1></div>
        <nav aria-label="التنقل الرئيسي">
          <a className="active" href="/">لوحة التحكم</a>
          {visibleModules.map(([title, , path, detail]) => <a href={path} key={title}>{title}<small>{detail}</small></a>)}
        </nav>
        <button className="sidebar-logout" onClick={onLogout}>تسجيل الخروج</button>
      </aside>
      <section className="workspace">
        <header className="topbar">
          <div><p className="eyebrow">{profile.employeeNo} · {roleLabel}</p><h2>مرحبًا، {profile.fullName}</h2></div>
          <span className="date">{today}</span>
        </header>
        <section className="hero-panel">
          <div><span className="pill">جلسة موثقة</span><h3>الوصول يظهر حسب صلاحيات حسابك</h3><p>تم ربط حسابك بموظف نشط. المؤسسة والفروع والأدوار تُقرأ من الخادم، ولا تعتمد على قيمة مرسلة من المتصفح.</p></div>
          <div className="hero-stat"><strong>{profile.branches.length.toString().padStart(2, '0')}</strong><span>فرع متاح</span></div>
        </section>
        <section className="metric-row" aria-label="ملخص الحساب">
          <div className="metric-card"><span>الدور</span><strong>{profile.roles.length.toString().padStart(2, '0')}</strong><small>{roleLabel}</small></div>
          <div className="metric-card"><span>الصلاحيات</span><strong>{profile.permissions.length.toString().padStart(2, '0')}</strong><small>مطبقة من قاعدة البيانات</small></div>
          <div className="metric-card"><span>الفروع</span><strong>{profile.branches.length.toString().padStart(2, '0')}</strong><small>{profile.branches.map((branch) => branch.name).join('، ') || 'لا يوجد ربط بعد'}</small></div>
        </section>
        <section className="module-section"><div className="section-heading"><div><p className="eyebrow">نطاق الحساب</p><h3>الوحدات المتاحة</h3></div><span className="muted">لا تظهر الوحدات غير المصرح بها</span></div><div className="module-grid">{visibleModules.map(([title, , , detail], index) => <article className="module-card" key={title}><span className="module-index">0{index + 1}</span><h4>{title}</h4><p>{detail}</p></article>)}</div></section>
      </section>
    </main>
  );
}

function App() {
  const [profile, setProfile] = useState<EmployeeProfile | null>(null);
  const [loading, setLoading] = useState(true);
  const [authError, setAuthError] = useState('');

  const loadProfile = useCallback(async () => {
    if (!supabase) { setLoading(false); return; }
    const { data: sessionData } = await supabase.auth.getSession();
    if (!sessionData.session) { setProfile(null); setLoading(false); return; }
    const response = await fetch('/api/me', { headers: { Authorization: `Bearer ${sessionData.session.access_token}` } });
    if (!response.ok) {
      await supabase.auth.signOut();
      setProfile(null);
      setAuthError(response.status === 403 ? 'الحساب صحيح، لكنه غير مرتبط بموظف نشط في المؤسسة.' : 'تعذر التحقق من ملف الموظف.');
      setLoading(false);
      return;
    }
    const body = await response.json() as { employee: EmployeeProfile };
    setProfile(body.employee);
    setAuthError('');
    setLoading(false);
  }, []);

  useEffect(() => {
    void loadProfile();
    if (!supabase) return;
    const { data } = supabase.auth.onAuthStateChange(() => { window.setTimeout(() => { void loadProfile(); }, 0); });
    return () => data.subscription.unsubscribe();
  }, [loadProfile]);

  if (loading) return <main className="loading-shell"><div className="brand-mark">ش</div><p>جارٍ التحقق من الجلسة…</p></main>;
  if (!profile) return <><Login onLoggedIn={() => { void loadProfile(); }} />{authError && <div className="floating-error" role="alert">{authError}</div>}</>;
  const backHome = () => window.location.assign('/');
  if (window.location.pathname === '/employees' && profile.permissions.includes('employees.read')) return <EmployeesPage onBack={backHome} />;
  if (window.location.pathname === '/branches' && profile.permissions.includes('branches.read_all')) return <BranchesPage onBack={backHome} />;
  if (window.location.pathname === '/roles' && profile.permissions.includes('roles.read')) return <RolesPage onBack={backHome} />;
  if (window.location.pathname === '/tasks' && profile.permissions.includes('tasks.read')) return <TasksPage onBack={backHome} />;
  if (window.location.pathname === '/task-library' && profile.permissions.includes('task_library.read')) return <TaskLibraryPage onBack={backHome} />;
  if (window.location.pathname === '/report-designer' && profile.permissions.includes('report_forms.manage')) return <ReportDesignerPage onBack={backHome} />;
  if (window.location.pathname === '/customers' && profile.permissions.includes('customers.read')) return <CustomersPage onBack={backHome} />;
  if (window.location.pathname === '/reports' && profile.permissions.includes('finance.read')) return <ReportsPage onBack={backHome} />;
  return <Dashboard profile={profile} onLogout={async () => { await supabase?.auth.signOut(); setProfile(null); }} />;
}

createRoot(document.getElementById('root')!).render(<App />);
