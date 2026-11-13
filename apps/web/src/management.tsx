import { useEffect, useState } from 'react';
import { supabase } from './lib/supabase';

type Branch = { id: string; code: string; name: string; address?: string | null; phone?: string | null; is_active: boolean; branch_level?: number; parent_branch_id?: string | null };
type Employee = { id: string; employee_no: string; full_name: string; email: string | null; phone: string | null; status: 'active' | 'suspended' | 'archived'; base_branch_id: string | null; last_login_at: string | null };
type Role = { id: string; code: string; name_ar: string; description: string | null };

async function apiRequest<T>(path: string, init?: RequestInit): Promise<T> {
  const session = (await supabase?.auth.getSession())?.data.session;
  if (!session) throw new Error('missing_session');
  const response = await fetch(path, { ...init, headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${session.access_token}`, ...(init?.headers ?? {}) } });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(body.error ?? 'request_failed');
  return body as T;
}

function ManagementFrame({ title, eyebrow, onBack, children }: { title: string; eyebrow: string; onBack: () => void; children: React.ReactNode }) {
  return <section className="management-page"><div className="management-head"><div><p className="eyebrow">{eyebrow}</p><h2>{title}</h2></div><button className="ghost-button" onClick={onBack}>العودة للوحة التحكم</button></div>{children}</section>;
}

export function EmployeesPage({ onBack }: { onBack: () => void }) {
  const [employees, setEmployees] = useState<Employee[]>([]);
  const [branches, setBranches] = useState<Branch[]>([]);
  const [form, setForm] = useState({ employeeNo: '', fullName: '', email: '', password: '', baseBranchId: '', roleCode: 'warehouse_worker' });
  const [accessEmployee, setAccessEmployee] = useState<Employee | null>(null);
  const [accessForm, setAccessForm] = useState({ roleCode: 'warehouse_worker', branchId: '' });
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [busy, setBusy] = useState(false);

  async function load() {
    try {
      const [employeeBody, branchBody] = await Promise.all([apiRequest<{ employees: Employee[] }>('/api/employees'), apiRequest<{ branches: Branch[] }>('/api/branches')]);
      setEmployees(employeeBody.employees); setBranches(branchBody.branches);
      if (!form.baseBranchId && branchBody.branches[0]) setForm((current) => ({ ...current, baseBranchId: branchBody.branches[0].id }));
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'تعذر تحميل الموظفين'); }
  }
  useEffect(() => { void load(); }, []);

  async function createEmployee(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); setBusy(true); setError(''); setNotice('');
    try { await apiRequest('/api/employees', { method: 'POST', body: JSON.stringify(form) }); setNotice('تم إنشاء الحساب وربطه بالموظف.'); setForm({ employeeNo: '', fullName: '', email: '', password: '', baseBranchId: branches[0]?.id ?? '', roleCode: 'warehouse_worker' }); await load(); }
    catch (cause) { setError(cause instanceof Error ? cause.message : 'تعذر إنشاء الموظف'); }
    finally { setBusy(false); }
  }

  async function changeStatus(employee: Employee) {
    const status = employee.status === 'active' ? 'suspended' : 'active';
    try { await apiRequest(`/api/employees/${employee.id}/status`, { method: 'PATCH', body: JSON.stringify({ status }) }); await load(); }
    catch (cause) { setError(cause instanceof Error ? cause.message : 'تعذر تعديل حالة الموظف'); }
  }

  async function updateAccess(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); setError(''); setNotice('');
    if (!accessEmployee || !accessForm.branchId) return;
    try { await apiRequest(`/api/employees/${accessEmployee.id}/access`, { method: 'PATCH', body: JSON.stringify({ roleCodes: [accessForm.roleCode], branchIds: [accessForm.branchId], defaultBranchId: accessForm.branchId }) }); setNotice('تم تحديث دور الموظف وفرعه.'); await load(); }
    catch (cause) { setError(cause instanceof Error ? cause.message : 'تعذر تحديث وصول الموظف'); }
  }

  return <ManagementFrame title="الموظفون" eyebrow="إدارة الهوية الوظيفية" onBack={onBack}>
    {error && <p className="form-error" role="alert">{error}</p>}{notice && <p className="form-success">{notice}</p>}
    <div className="management-grid"><section className="table-card"><div className="card-heading"><h3>قائمة الموظفين</h3><span>{employees.length} سجل</span></div><div className="data-list">{employees.map((employee) => <article className="data-row" key={employee.id}><div><strong>{employee.full_name}</strong><small>{employee.employee_no} · {employee.email ?? 'بلا بريد'}</small></div><div className="row-actions"><span className={`status-badge ${employee.status}`}>{employee.status === 'active' ? 'نشط' : employee.status === 'suspended' ? 'موقوف' : 'مؤرشف'}</span><button className="text-button" onClick={() => { setAccessEmployee(employee); setAccessForm({ roleCode: 'warehouse_worker', branchId: employee.base_branch_id ?? branches[0]?.id ?? '' }); }}>الوصول</button><button className="text-button" onClick={() => void changeStatus(employee)}>{employee.status === 'active' ? 'إيقاف' : 'تنشيط'}</button></div></article>)}{!employees.length && <p className="empty-state">لا توجد سجلات موظفين متاحة لهذا الحساب.</p>}</div></section>
      <section className="form-card"><div className="card-heading"><h3>إضافة موظف</h3><span>للمصرح لهم فقط</span></div><form className="management-form" onSubmit={createEmployee}><label>الرقم الوظيفي<input value={form.employeeNo} onChange={(e) => setForm({ ...form, employeeNo: e.target.value })} required /></label><label>الاسم الكامل<input value={form.fullName} onChange={(e) => setForm({ ...form, fullName: e.target.value })} required /></label><label>البريد الإلكتروني<input type="email" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} required /></label><label>كلمة مرور مؤقتة<input type="password" minLength={8} value={form.password} onChange={(e) => setForm({ ...form, password: e.target.value })} required /></label><label>الدور<select value={form.roleCode} onChange={(e) => setForm({ ...form, roleCode: e.target.value })}><option value="admin_followup">مسؤول المتابعة</option><option value="accountant">المحاسب</option><option value="warehouse_keeper">أمين المخزن</option><option value="warehouse_worker">عامل المخزن</option><option value="owner">صاحب المؤسسة</option></select></label><label>الفرع الأساسي<select value={form.baseBranchId} onChange={(e) => setForm({ ...form, baseBranchId: e.target.value })} required><option value="">اختر الفرع</option>{branches.map((branch) => <option value={branch.id} key={branch.id}>{branch.name}</option>)}</select></label><button type="submit" disabled={busy}>{busy ? 'جارٍ الإنشاء…' : 'إنشاء وربط الموظف'}</button></form></section></div>
    {accessEmployee && <section className="form-card access-editor"><div className="card-heading"><h3>تعديل وصول {accessEmployee.full_name}</h3><span>الدور والفرع الافتراضي</span></div><form className="management-form" onSubmit={updateAccess}><label>الدور<select value={accessForm.roleCode} onChange={(e) => setAccessForm({ ...accessForm, roleCode: e.target.value })}><option value="admin_followup">مسؤول المتابعة</option><option value="accountant">المحاسب</option><option value="warehouse_keeper">أمين المخزن</option><option value="warehouse_worker">عامل المخزن</option><option value="owner">صاحب المؤسسة</option></select></label><label>الفرع<select value={accessForm.branchId} onChange={(e) => setAccessForm({ ...accessForm, branchId: e.target.value })} required><option value="">اختر الفرع</option>{branches.map((branch) => <option value={branch.id} key={branch.id}>{branch.name}</option>)}</select></label><button type="submit">حفظ الوصول</button></form></section>}
  </ManagementFrame>;
}

export function BranchesPage({ onBack }: { onBack: () => void }) {
  const [branches, setBranches] = useState<Branch[]>([]);
  const [form, setForm] = useState({ code: '', name: '', address: '', phone: '' });
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  async function load() { try { setBranches((await apiRequest<{ branches: Branch[] }>('/api/branches')).branches); } catch (cause) { setError(cause instanceof Error ? cause.message : 'تعذر تحميل الفروع'); } }
  useEffect(() => { void load(); }, []);
  async function createBranch(event: React.FormEvent<HTMLFormElement>) { event.preventDefault(); setBusy(true); setError(''); try { await apiRequest('/api/branches', { method: 'POST', body: JSON.stringify(form) }); setForm({ code: '', name: '', address: '', phone: '' }); await load(); } catch (cause) { setError(cause instanceof Error ? cause.message : 'تعذر إنشاء الفرع'); } finally { setBusy(false); } }
  return <ManagementFrame title="الفروع" eyebrow="نطاق المؤسسة" onBack={onBack}>{error && <p className="form-error" role="alert">{error}</p>}<div className="management-grid"><section className="table-card"><div className="card-heading"><h3>الفروع الحالية</h3><span>{branches.length} سجل</span></div><div className="data-list">{branches.map((branch) => <article className="data-row" key={branch.id}><div><strong>{branch.name}</strong><small>{branch.code} · {branch.address || 'لا يوجد عنوان'}</small></div><span className={`status-badge ${branch.is_active ? 'active' : 'archived'}`}>{branch.is_active ? 'نشط' : 'مؤرشف'}</span></article>)}{!branches.length && <p className="empty-state">لا توجد فروع متاحة لهذا الحساب.</p>}</div></section><section className="form-card"><div className="card-heading"><h3>إضافة فرع</h3><span>صلاحية branches.manage</span></div><form className="management-form" onSubmit={createBranch}><label>رمز الفرع<input value={form.code} onChange={(e) => setForm({ ...form, code: e.target.value })} pattern="[a-z0-9][a-z0-9_-]{1,31}" required /></label><label>اسم الفرع<input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} required /></label><label>العنوان<input value={form.address} onChange={(e) => setForm({ ...form, address: e.target.value })} /></label><label>الهاتف<input value={form.phone} onChange={(e) => setForm({ ...form, phone: e.target.value })} /></label><button type="submit" disabled={busy}>{busy ? 'جارٍ الحفظ…' : 'حفظ الفرع'}</button></form></section></div></ManagementFrame>;
}

export function RolesPage({ onBack }: { onBack: () => void }) {
  const [roles, setRoles] = useState<Role[]>([]);
  const [error, setError] = useState('');
  useEffect(() => { void apiRequest<{ roles: Role[] }>('/api/roles').then((body) => setRoles(body.roles)).catch((cause) => setError(cause instanceof Error ? cause.message : 'تعذر تحميل الأدوار')); }, []);
  return <ManagementFrame title="الأدوار والصلاحيات" eyebrow="الوصول المؤسسي" onBack={onBack}>{error && <p className="form-error" role="alert">{error}</p>}<section className="table-card"><div className="card-heading"><h3>الأدوار المعتمدة</h3><span>تُدار على الخادم</span></div><div className="role-grid">{roles.map((role) => <article className="role-card" key={role.id}><span className="module-index">{role.code}</span><h3>{role.name_ar}</h3><p>{role.description || 'صلاحيات مؤسسية قابلة للمراجعة.'}</p></article>)}{!roles.length && <p className="empty-state">لا توجد أدوار متاحة لهذا الحساب.</p>}</div></section></ManagementFrame>;
}


type ReportField = { key: string; label: string; type: 'text' | 'number' | 'progress' | 'status' | 'notes'; required: boolean };
type Task = { id: string; title: string; description: string | null; assignee_employee_id: string; starts_at: string; due_at: string; priority: 'low' | 'normal' | 'high' | 'urgent'; status: 'pending' | 'in_progress' | 'submitted' | 'approved' | 'rejected' | 'cancelled'; proof_required: boolean; proof_instructions: string | null; report_schema: ReportField[] };

const taskStatusLabels: Record<Task['status'], string> = { pending: 'معلقة', in_progress: 'قيد التنفيذ', submitted: 'بانتظار المراجعة', approved: 'معتمدة', rejected: 'معادة', cancelled: 'ملغاة' };

export function TasksPage({ onBack }: { onBack: () => void }) {
  const [tasks, setTasks] = useState<Task[]>([]);
  const [employees, setEmployees] = useState<Employee[]>([]);
  const [form, setForm] = useState({ title: '', description: '', assigneeEmployeeId: '', startsAt: '', dueAt: '', priority: 'normal', proofRequired: false, proofInstructions: '', reportFieldsText: '' });
  const [reportDrafts, setReportDrafts] = useState<Record<string, string>>({});
  const [note, setNote] = useState('');
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [busy, setBusy] = useState(false);
  async function load() {
    try {
      const taskBody = await apiRequest<{ tasks: Task[] }>('/api/tasks'); setTasks(taskBody.tasks);
      try { const employeeBody = await apiRequest<{ employees: Employee[] }>('/api/employees'); setEmployees(employeeBody.employees); if (!form.assigneeEmployeeId && employeeBody.employees[0]) setForm((current) => ({ ...current, assigneeEmployeeId: employeeBody.employees[0].id })); } catch { setEmployees([]); }
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'تعذر تحميل المهام'); }
  }
  useEffect(() => { void load(); }, []);
  async function createTask(event: React.FormEvent<HTMLFormElement>) { event.preventDefault(); setBusy(true); setError(''); setNotice(''); try { const reportFields = form.reportFieldsText.trim() ? JSON.parse(form.reportFieldsText) as ReportField[] : []; if (!Array.isArray(reportFields)) throw new Error('يجب أن تكون حقول التقرير قائمة JSON.'); await apiRequest('/api/tasks', { method: 'POST', body: JSON.stringify({ ...form, reportFields, startsAt: new Date(form.startsAt).toISOString(), dueAt: new Date(form.dueAt).toISOString(), description: form.description || null, proofInstructions: form.proofInstructions || null }) }); setNotice('تم إنشاء المهمة مع مخطط التقرير.'); setForm({ title: '', description: '', assigneeEmployeeId: employees[0]?.id ?? '', startsAt: '', dueAt: '', priority: 'normal', proofRequired: false, proofInstructions: '', reportFieldsText: '' }); await load(); } catch (cause) { setError(cause instanceof Error ? cause.message : 'تعذر إنشاء المهمة أو قراءة مخطط التقرير'); } finally { setBusy(false); } }
  async function progress(task: Task, status: 'in_progress' | 'submitted') { setError(''); setNotice(''); try { await apiRequest(`/api/tasks/${task.id}/updates`, { method: 'POST', body: JSON.stringify({ status, note: note || null }) }); setNote(''); setNotice(status === 'submitted' ? 'أرسلت المهمة للمراجعة، ولم تعتبر معتمدة بعد.' : 'تم تسجيل بدء التنفيذ.'); await load(); } catch (cause) { setError(cause instanceof Error ? cause.message : 'تعذر تحديث المهمة'); } }
  async function review(task: Task, decision: 'approved' | 'rejected') { setError(''); try { await apiRequest(`/api/tasks/${task.id}/review`, { method: 'POST', body: JSON.stringify({ decision, note: note || null }) }); setNote(''); await load(); } catch (cause) { setError(cause instanceof Error ? cause.message : 'تعذر مراجعة المهمة'); } }
  async function submitReport(task: Task) { setError(''); try { const values = reportDrafts[task.id]?.trim() ? JSON.parse(reportDrafts[task.id]) : {}; await apiRequest(`/api/tasks/${task.id}/report`, { method: 'POST', body: JSON.stringify({ values }) }); setReportDrafts((current) => ({ ...current, [task.id]: '' })); setNotice('تم رفع التقرير للمراجعة.'); await load(); } catch (cause) { setError(cause instanceof Error ? cause.message : 'تعذر رفع التقرير؛ تحقق من صيغة JSON والحقول المطلوبة.'); } }
  const employeeName = (id: string) => employees.find((employee) => employee.id === id)?.full_name ?? 'موظف مرتبط';

  return <ManagementFrame title="المهام والمتابعة" eyebrow="دورة تنفيذ قابلة للمراجعة" onBack={onBack}>
    {error && <p className="form-error" role="alert">{error}</p>}{notice && <p className="form-success">{notice}</p>}
    <div className="management-grid"><section className="table-card"><div className="card-heading"><h3>المهام</h3><span>{tasks.length} سجل</span></div><label className="note-field">ملاحظة التحديث أو المراجعة<input value={note} onChange={(e) => setNote(e.target.value)} placeholder="سبب الإرجاع أو تفاصيل الإنجاز" /></label><div className="data-list">{tasks.map((task) => <article className="task-row" key={task.id}><div className="task-main"><div className="task-title-line"><strong>{task.title}</strong><span className={`status-badge ${task.status}`}>{taskStatusLabels[task.status]}</span></div><small>{employeeName(task.assignee_employee_id)} · {new Intl.DateTimeFormat('ar-SA', { dateStyle: 'medium' }).format(new Date(task.due_at))}</small>{task.proof_required && <small className="proof-label">يتطلب دليل إنجاز</small>}</div><div className="row-actions">{['pending', 'rejected'].includes(task.status) && <button className="text-button" onClick={() => void progress(task, 'in_progress')}>بدء</button>}{task.status === 'in_progress' && task.report_schema.length === 0 && <button className="text-button" onClick={() => void progress(task, 'submitted')}>إرسال للمراجعة</button>}{task.status === 'submitted' && <><button className="text-button approve" onClick={() => void review(task, 'approved')}>اعتماد</button><button className="text-button reject" onClick={() => void review(task, 'rejected')}>إرجاع</button></>}{['in_progress', 'rejected'].includes(task.status) && task.report_schema.length > 0 && <><textarea className="task-report-input" value={reportDrafts[task.id] ?? ''} onChange={(e) => setReportDrafts((current) => ({ ...current, [task.id]: e.target.value }))} placeholder="قيم التقرير بصيغة JSON" rows={2} /><button className="text-button" onClick={() => void submitReport(task)}>رفع التقرير</button></>}</div></article>)}{!tasks.length && <p className="empty-state">لا توجد مهام في نطاق حسابك.</p>}</div></section>
      <section className="form-card"><div className="card-heading"><h3>إنشاء مهمة</h3><span>صلاحية tasks.manage</span></div><form className="management-form" onSubmit={createTask}><label>عنوان المهمة<input value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} required /></label><label>التفاصيل<textarea value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} rows={3} /></label><label>الموظف المكلف<select value={form.assigneeEmployeeId} onChange={(e) => setForm({ ...form, assigneeEmployeeId: e.target.value })} required><option value="">اختر الموظف</option>{employees.map((employee) => <option value={employee.id} key={employee.id}>{employee.full_name}</option>)}</select></label><label>الأولوية<select value={form.priority} onChange={(e) => setForm({ ...form, priority: e.target.value })}><option value="low">منخفضة</option><option value="normal">عادية</option><option value="high">عالية</option><option value="urgent">عاجلة</option></select></label><label>يبدأ في<input type="datetime-local" value={form.startsAt} onChange={(e) => setForm({ ...form, startsAt: e.target.value })} required /></label><label>يستحق في<input type="datetime-local" value={form.dueAt} onChange={(e) => setForm({ ...form, dueAt: e.target.value })} required /></label><label className="check-label"><input type="checkbox" checked={form.proofRequired} onChange={(e) => setForm({ ...form, proofRequired: e.target.checked })} /> يتطلب دليل إنجاز</label>{form.proofRequired && <label>تعليمات الدليل<textarea value={form.proofInstructions} onChange={(e) => setForm({ ...form, proofInstructions: e.target.value })} rows={2} /></label>}<label>حقول التقرير بصيغة JSON اختيارية<textarea value={form.reportFieldsText} onChange={(e) => setForm({ ...form, reportFieldsText: e.target.value })} rows={4} placeholder="مثال: { &quot;done&quot;: 3 }" /></label><button type="submit" disabled={busy}>{busy ? 'جارٍ الحفظ…' : 'إنشاء المهمة'}</button></form></section></div>
  </ManagementFrame>;
}


type LibraryField = { key: string; labelAr: string; fieldType: 'text' | 'textarea' | 'number' | 'date' | 'select' | 'multiselect' | 'checkbox' | 'attachment'; required: boolean; optionsText: string; sortOrder: number };
type LibraryTemplate = { id: string; code: string; title: string; description: string | null; task_type: string; job_title_id: string | null; recurrence: 'daily' | 'weekly' | 'monthly' | null; week_day: number | null; month_day: number | null; default_duration_minutes: number | null; report_form_id: string | null; version: number; is_active: boolean; job_titles?: { id: string; name_ar: string } | null; report_forms?: { id: string; name_ar: string; version: number } | null; branches: Array<{ id: string; name: string; branch_level?: number }>; employees: Array<{ id: string; full_name: string }> };
type JobTitle = { id: string; code: string; name_ar: string };
type ReportForm = { id: string; code: string; name_ar: string; version: number; report_form_fields?: Array<{ field_key: string; label_ar: string; field_type: string; is_required: boolean }> };

const emptyLibraryField = (): LibraryField => ({ key: `field_${Date.now()}`, labelAr: '', fieldType: 'text', required: false, optionsText: '', sortOrder: 0 });

export function TaskLibraryPage({ onBack }: { onBack: () => void }) {
  const [templates, setTemplates] = useState<LibraryTemplate[]>([]);
  const [branches, setBranches] = useState<Branch[]>([]);
  const [employees, setEmployees] = useState<Employee[]>([]);
  const [jobTitles, setJobTitles] = useState<JobTitle[]>([]);
  const [forms, setForms] = useState<ReportForm[]>([]);
  const [filter, setFilter] = useState({ taskType: '', recurrence: '', jobTitleId: '' });
  const [libraryForm, setLibraryForm] = useState({ code: '', title: '', description: '', taskType: 'general', jobTitleId: '', branchIds: [] as string[], employeeIds: [] as string[], recurrence: '', weekDay: '', monthDay: '', defaultDurationMinutes: '', reportFormId: '' });
  const [formMeta, setFormMeta] = useState({ code: '', nameAr: '', description: '' });
  const [formFields, setFormFields] = useState<LibraryField[]>([emptyLibraryField()]);
  const [convert, setConvert] = useState({ templateId: '', assigneeEmployeeId: '', branchId: '', startsAt: '', dueAt: '', priority: 'normal' });
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [busy, setBusy] = useState(false);

  async function load() {
    try {
      const params = new URLSearchParams(); if (filter.taskType) params.set('taskType', filter.taskType); if (filter.recurrence) params.set('recurrence', filter.recurrence); if (filter.jobTitleId) params.set('jobTitleId', filter.jobTitleId);
      const [library, branchBody, employeeBody, jobBody, formBody] = await Promise.all([
        apiRequest<{ templates: LibraryTemplate[] }>(`/api/task-library?${params.toString()}`),
        apiRequest<{ branches: Branch[] }>('/api/branches'),
        apiRequest<{ employees: Employee[] }>('/api/employees'),
        apiRequest<{ jobTitles: JobTitle[] }>('/api/job-titles'),
        apiRequest<{ reportForms: ReportForm[] }>('/api/report-forms'),
      ]);
      setTemplates(library.templates); setBranches(branchBody.branches); setEmployees(employeeBody.employees); setJobTitles(jobBody.jobTitles); setForms(formBody.reportForms);
      if (!convert.assigneeEmployeeId && employeeBody.employees[0]) setConvert((current) => ({ ...current, assigneeEmployeeId: employeeBody.employees[0].id }));
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'تعذر تحميل مكتبة المهام'); }
  }
  useEffect(() => { void load(); }, [filter.taskType, filter.recurrence, filter.jobTitleId]);

  function toggleValue(key: 'branchIds' | 'employeeIds', value: string) { setLibraryForm((current) => ({ ...current, [key]: current[key].includes(value) ? current[key].filter((item) => item !== value) : [...current[key], value] })); }
  function updateField(index: number, patch: Partial<LibraryField>) { setFormFields((current) => current.map((field, fieldIndex) => fieldIndex === index ? { ...field, ...patch } : field)); }

  async function createReportForm(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); setBusy(true); setError(''); setNotice('');
    try {
      await apiRequest('/api/report-forms', { method: 'POST', body: JSON.stringify({ ...formMeta, fields: formFields.map((field, index) => ({ key: field.key, labelAr: field.labelAr, fieldType: field.fieldType, required: field.required, sortOrder: index, options: field.optionsText.split(',').map((item) => item.trim()).filter(Boolean), config: {} })) }) });
      setNotice('تم حفظ نموذج التقرير من المنشئ المرئي.'); setFormMeta({ code: '', nameAr: '', description: '' }); setFormFields([emptyLibraryField()]); await load();
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'تعذر حفظ نموذج التقرير'); } finally { setBusy(false); }
  }

  async function createLibraryTemplate(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); setBusy(true); setError(''); setNotice('');
    try {
      await apiRequest('/api/task-library', { method: 'POST', body: JSON.stringify({ ...libraryForm, jobTitleId: libraryForm.jobTitleId || null, branchIds: libraryForm.branchIds, employeeIds: libraryForm.employeeIds, recurrence: libraryForm.recurrence || null, weekDay: libraryForm.weekDay ? Number(libraryForm.weekDay) : null, monthDay: libraryForm.monthDay ? Number(libraryForm.monthDay) : null, defaultDurationMinutes: libraryForm.defaultDurationMinutes ? Number(libraryForm.defaultDurationMinutes) : null, reportFormId: libraryForm.reportFormId || null }) });
      setNotice('تمت إضافة المهمة إلى المكتبة دون إنشاء مهمة تنفيذية.'); setLibraryForm({ code: '', title: '', description: '', taskType: 'general', jobTitleId: '', branchIds: [], employeeIds: [], recurrence: '', weekDay: '', monthDay: '', defaultDurationMinutes: '', reportFormId: '' }); await load();
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'تعذر حفظ قالب المهمة'); } finally { setBusy(false); }
  }

  async function convertTemplate(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); setBusy(true); setError(''); setNotice('');
    try { await apiRequest(`/api/task-library/${convert.templateId}/convert`, { method: 'POST', body: JSON.stringify({ assigneeEmployeeId: convert.assigneeEmployeeId, branchId: convert.branchId || null, startsAt: new Date(convert.startsAt).toISOString(), dueAt: new Date(convert.dueAt).toISOString(), priority: convert.priority }) }); setNotice('تم تحويل قالب المكتبة إلى مهمة فعلية للمراجعة والتنفيذ.'); await load(); }
    catch (cause) { setError(cause instanceof Error ? cause.message : 'تعذر تحويل القالب إلى مهمة'); } finally { setBusy(false); }
  }

  return <ManagementFrame title="مكتبة المهام ونماذج التقارير" eyebrow="قوالب قابلة للتطوير دون برمجة" onBack={onBack}>
    {error && <p className="form-error" role="alert">{error}</p>}{notice && <p className="form-success">{notice}</p>}
    <section className="table-card library-filters"><div className="card-heading"><h3>تصنيف المكتبة</h3><span>{templates.length} قالب</span></div><div className="filter-grid"><label>نوع المهمة<input value={filter.taskType} onChange={(event) => setFilter({ ...filter, taskType: event.target.value })} placeholder="مثال: متابعة" /></label><label>الدورية<select value={filter.recurrence} onChange={(event) => setFilter({ ...filter, recurrence: event.target.value })}><option value="">كل الدوريات</option><option value="daily">يومية</option><option value="weekly">أسبوعية</option><option value="monthly">شهرية</option></select></label><label>الوظيفة<select value={filter.jobTitleId} onChange={(event) => setFilter({ ...filter, jobTitleId: event.target.value })}><option value="">كل الوظائف</option>{jobTitles.map((job) => <option value={job.id} key={job.id}>{job.name_ar}</option>)}</select></label></div></section>
    <div className="management-grid library-grid"><section className="table-card"><div className="card-heading"><h3>قوالب المهام الجاهزة</h3><span>لا تنشئ مهمة إلا عند التحويل</span></div><div className="data-list">{templates.map((template) => <article className="data-row library-row" key={template.id}><div><strong>{template.title}</strong><small>{template.code} · {template.task_type} · {template.job_titles?.name_ar ?? 'كل الوظائف'} · {template.recurrence === 'daily' ? 'يومية' : template.recurrence === 'weekly' ? 'أسبوعية' : template.recurrence === 'monthly' ? 'شهرية' : 'عند الحاجة'}</small><small>الفروع: {template.branches.map((branch) => `${branch.name}${branch.branch_level ? ` (م${branch.branch_level})` : ''}`).join('، ') || 'غير محدد'} · النموذج: {template.report_forms?.name_ar ?? 'بدون نموذج'}</small></div><button className="text-button" onClick={() => setConvert((current) => ({ ...current, templateId: template.id }))}>تحويل إلى مهمة</button></article>)}{!templates.length && <p className="empty-state">لم تتم إضافة قوالب بعد. أضفها من نموذج المكتبة دون إدخال بيانات تجريبية.</p>}</div></section>
      <section className="form-card"><div className="card-heading"><h3>إضافة قالب مهمة</h3><span>مكتبة قابلة للتعديل</span></div><form className="management-form" onSubmit={createLibraryTemplate}><label>رمز القالب<input value={libraryForm.code} onChange={(event) => setLibraryForm({ ...libraryForm, code: event.target.value })} pattern="[a-z0-9][a-z0-9_-]{1,63}" required /></label><label>عنوان المهمة<input value={libraryForm.title} onChange={(event) => setLibraryForm({ ...libraryForm, title: event.target.value })} required /></label><label>الوصف<textarea value={libraryForm.description} onChange={(event) => setLibraryForm({ ...libraryForm, description: event.target.value })} rows={2} /></label><label>نوع المهمة<input value={libraryForm.taskType} onChange={(event) => setLibraryForm({ ...libraryForm, taskType: event.target.value })} required /></label><label>الوظيفة<select value={libraryForm.jobTitleId} onChange={(event) => setLibraryForm({ ...libraryForm, jobTitleId: event.target.value })}><option value="">كل الوظائف</option>{jobTitles.map((job) => <option value={job.id} key={job.id}>{job.name_ar}</option>)}</select></label><label>نموذج التقرير<select value={libraryForm.reportFormId} onChange={(event) => setLibraryForm({ ...libraryForm, reportFormId: event.target.value })}><option value="">بدون نموذج</option>{forms.map((form) => <option value={form.id} key={form.id}>{form.name_ar} · إصدار {form.version}</option>)}</select></label><label>الدورية<select value={libraryForm.recurrence} onChange={(event) => setLibraryForm({ ...libraryForm, recurrence: event.target.value })}><option value="">عند الحاجة</option><option value="daily">يومية</option><option value="weekly">أسبوعية</option><option value="monthly">شهرية</option></select></label>{libraryForm.recurrence === 'weekly' && <label>يوم الأسبوع<input type="number" min="1" max="7" value={libraryForm.weekDay} onChange={(event) => setLibraryForm({ ...libraryForm, weekDay: event.target.value })} placeholder="السبت 1 — الجمعة 7" required /></label>}{libraryForm.recurrence === 'monthly' && <label>يوم الشهر<input type="number" min="1" max="31" value={libraryForm.monthDay} onChange={(event) => setLibraryForm({ ...libraryForm, monthDay: event.target.value })} required /></label>}<label>المدة الافتراضية بالدقائق<input type="number" min="1" value={libraryForm.defaultDurationMinutes} onChange={(event) => setLibraryForm({ ...libraryForm, defaultDurationMinutes: event.target.value })} /></label><fieldset className="choice-field"><legend>الفروع المصنفة</legend>{branches.map((branch) => <label className="check-label" key={branch.id}><input type="checkbox" checked={libraryForm.branchIds.includes(branch.id)} onChange={() => toggleValue('branchIds', branch.id)} /> {branch.name} — المستوى {branch.branch_level ?? 1}</label>)}</fieldset><fieldset className="choice-field"><legend>الموظفون المصنفون اختياريًا</legend>{employees.map((employee) => <label className="check-label" key={employee.id}><input type="checkbox" checked={libraryForm.employeeIds.includes(employee.id)} onChange={() => toggleValue('employeeIds', employee.id)} /> {employee.full_name}</label>)}</fieldset><button type="submit" disabled={busy}>{busy ? 'جارٍ الحفظ…' : 'حفظ القالب في المكتبة'}</button></form></section></div>
    <section className="form-card form-builder-card"><div className="card-heading"><div><h3>منشئ نماذج التقارير</h3><span>حقول مرئية: نص، رقم، تاريخ، قائمة، اختيار، مرفقات</span></div><span>{formFields.length} حقول</span></div><form className="management-form" onSubmit={createReportForm}><div className="filter-grid"><label>رمز النموذج<input value={formMeta.code} onChange={(event) => setFormMeta({ ...formMeta, code: event.target.value })} pattern="[a-z0-9][a-z0-9_-]{1,63}" required /></label><label>اسم النموذج<input value={formMeta.nameAr} onChange={(event) => setFormMeta({ ...formMeta, nameAr: event.target.value })} required /></label><label>وصف النموذج<input value={formMeta.description} onChange={(event) => setFormMeta({ ...formMeta, description: event.target.value })} /></label></div><div className="builder-fields">{formFields.map((field, index) => <div className="builder-field" key={field.key}><input value={field.key} onChange={(event) => updateField(index, { key: event.target.value })} placeholder="المفتاح" required /><input value={field.labelAr} onChange={(event) => updateField(index, { labelAr: event.target.value })} placeholder="اسم الحقل بالعربية" required /><select value={field.fieldType} onChange={(event) => updateField(index, { fieldType: event.target.value as LibraryField['fieldType'] })}><option value="text">نص قصير</option><option value="textarea">نص طويل</option><option value="number">رقم</option><option value="date">تاريخ</option><option value="select">قائمة اختيار</option><option value="multiselect">اختيارات متعددة</option><option value="checkbox">نعم/لا</option><option value="attachment">صورة أو مستند</option></select>{['select', 'multiselect'].includes(field.fieldType) && <input value={field.optionsText} onChange={(event) => updateField(index, { optionsText: event.target.value })} placeholder="الخيارات مفصولة بفواصل" />}<label className="check-label"><input type="checkbox" checked={field.required} onChange={(event) => updateField(index, { required: event.target.checked })} /> مطلوب</label><button type="button" className="text-button reject" onClick={() => setFormFields((current) => current.filter((_, fieldIndex) => fieldIndex !== index))}>حذف</button></div>)}</div><div className="builder-actions"><button type="button" className="ghost-button" onClick={() => setFormFields((current) => [...current, { ...emptyLibraryField(), sortOrder: current.length }])}>إضافة حقل</button><button type="submit" disabled={busy}>{busy ? 'جارٍ الحفظ…' : 'حفظ النموذج'}</button></div></form></section>
    {convert.templateId && <section className="form-card conversion-card"><div className="card-heading"><h3>تحويل قالب إلى مهمة فعلية</h3><span>تحدد المسؤول والفرع والموعد هنا</span></div><form className="management-form" onSubmit={convertTemplate}><label>الموظف المسؤول<select value={convert.assigneeEmployeeId} onChange={(event) => setConvert({ ...convert, assigneeEmployeeId: event.target.value })} required><option value="">اختر الموظف</option>{employees.map((employee) => <option value={employee.id} key={employee.id}>{employee.full_name}</option>)}</select></label><label>الفرع<select value={convert.branchId} onChange={(event) => setConvert({ ...convert, branchId: event.target.value })}><option value="">كل الفروع</option>{branches.map((branch) => <option value={branch.id} key={branch.id}>{branch.name}</option>)}</select></label><label>الأولوية<select value={convert.priority} onChange={(event) => setConvert({ ...convert, priority: event.target.value })}><option value="low">منخفضة</option><option value="normal">عادية</option><option value="high">عالية</option><option value="urgent">عاجلة</option></select></label><label>يبدأ التنفيذ<input type="datetime-local" value={convert.startsAt} onChange={(event) => setConvert({ ...convert, startsAt: event.target.value })} required /></label><label>الموعد النهائي<input type="datetime-local" value={convert.dueAt} onChange={(event) => setConvert({ ...convert, dueAt: event.target.value })} required /></label><div className="builder-actions"><button type="submit" disabled={busy}>{busy ? 'جارٍ التحويل…' : 'إنشاء المهمة الفعلية'}</button><button type="button" className="ghost-button" onClick={() => setConvert((current) => ({ ...current, templateId: '' }))}>إلغاء</button></div></form></section>}
  </ManagementFrame>;
}


type Customer = { id: string; branch_id: string | null; code: string; name: string; phone: string | null; address: string | null; is_active: boolean; accountId: string | null; balance: number; approvedCreditLimit: number };
type Receipt = { id: string; receipt_no: string; amount: number; status: 'draft' | 'submitted' | 'approved' | 'rejected' | 'cancelled'; customer_id: string; created_at: string };

export function CustomersPage({ onBack }: { onBack: () => void }) {
  const [customers, setCustomers] = useState<Customer[]>([]);
  const [receipts, setReceipts] = useState<Receipt[]>([]);
  const [branches, setBranches] = useState<Branch[]>([]);
  const [customerForm, setCustomerForm] = useState({ code: '', name: '', branchId: '', phone: '', address: '' });
  const [receiptForm, setReceiptForm] = useState({ receiptNo: '', branchId: '', customerId: '', amount: '' });
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [busy, setBusy] = useState(false);
  async function load() {
    try {
      const [customerBody, branchBody, receiptBody] = await Promise.all([apiRequest<{ customers: Customer[] }>('/api/customers'), apiRequest<{ branches: Branch[] }>('/api/branches'), apiRequest<{ receipts: Receipt[] }>('/api/receipts')]);
      setCustomers(customerBody.customers); setBranches(branchBody.branches); setReceipts(receiptBody.receipts);
      if (!customerForm.branchId && branchBody.branches[0]) setCustomerForm((current) => ({ ...current, branchId: branchBody.branches[0].id }));
      if (!receiptForm.branchId && branchBody.branches[0]) setReceiptForm((current) => ({ ...current, branchId: branchBody.branches[0].id }));
      if (!receiptForm.customerId && customerBody.customers[0]) setReceiptForm((current) => ({ ...current, customerId: customerBody.customers[0].id }));
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'تعذر تحميل العملاء والحسابات'); }
  }
  useEffect(() => { void load(); }, []);
  async function createCustomer(event: React.FormEvent<HTMLFormElement>) { event.preventDefault(); setBusy(true); setError(''); setNotice(''); try { await apiRequest('/api/customers', { method: 'POST', body: JSON.stringify({ ...customerForm, phone: customerForm.phone || null, address: customerForm.address || null }) }); setNotice('تم إنشاء العميل وفتح حسابه الفرعي.'); setCustomerForm({ code: '', name: '', branchId: branches[0]?.id ?? '', phone: '', address: '' }); await load(); } catch (cause) { setError(cause instanceof Error ? cause.message : 'تعذر إنشاء العميل'); } finally { setBusy(false); } }
  async function createReceipt(event: React.FormEvent<HTMLFormElement>) { event.preventDefault(); setBusy(true); setError(''); setNotice(''); try { await apiRequest('/api/receipts', { method: 'POST', body: JSON.stringify({ receiptNo: receiptForm.receiptNo, branchId: receiptForm.branchId, customerId: receiptForm.customerId, amount: Number(receiptForm.amount) }) }); setNotice('تم إنشاء سند القبض بانتظار الاعتماد.'); setReceiptForm({ receiptNo: '', branchId: branches[0]?.id ?? '', customerId: customers[0]?.id ?? '', amount: '' }); await load(); } catch (cause) { setError(cause instanceof Error ? cause.message : 'تعذر إنشاء سند القبض'); } finally { setBusy(false); } }
  async function approveReceipt(receiptId: string) { setError(''); try { await apiRequest(`/api/receipts/${receiptId}/approve`, { method: 'POST', body: '{}' }); setNotice('تم اعتماد السند وترحيله إلى دفتر الحساب.'); await load(); } catch (cause) { setError(cause instanceof Error ? cause.message : 'تعذر اعتماد السند'); } }
  return <ManagementFrame title="العملاء والحسابات" eyebrow="الرصيد والتحصيل" onBack={onBack}>
    {error && <p className="form-error" role="alert">{error}</p>}{notice && <p className="form-success">{notice}</p>}
    <section className="table-card finance-card"><div className="card-heading"><h3>كشف العملاء المختصر</h3><span>{customers.length} عميل</span></div><div className="customer-grid">{customers.map((customer) => <article className="customer-card" key={customer.id}><div className="customer-card-head"><div><strong>{customer.name}</strong><small>{customer.code} · {customer.phone || 'بلا هاتف'}</small></div><span className={`status-badge ${customer.is_active ? 'active' : 'archived'}`}>{customer.is_active ? 'نشط' : 'موقوف'}</span></div><div className="customer-numbers"><div><span>الرصيد المستحق</span><strong>{customer.balance.toFixed(3)}</strong></div><div><span>الحد المعتمد</span><strong>{customer.approvedCreditLimit.toFixed(3)}</strong></div></div></article>)}{!customers.length && <p className="empty-state">لا يوجد عملاء في نطاق المؤسسة.</p>}</div></section>
    <div className="management-grid finance-grid"><section className="form-card"><div className="card-heading"><h3>إضافة عميل</h3><span>customers.manage</span></div><form className="management-form" onSubmit={createCustomer}><label>رمز العميل<input value={customerForm.code} onChange={(e) => setCustomerForm({ ...customerForm, code: e.target.value })} required /></label><label>اسم العميل<input value={customerForm.name} onChange={(e) => setCustomerForm({ ...customerForm, name: e.target.value })} required /></label><label>الفرع<select value={customerForm.branchId} onChange={(e) => setCustomerForm({ ...customerForm, branchId: e.target.value })} required><option value="">اختر الفرع</option>{branches.map((branch) => <option value={branch.id} key={branch.id}>{branch.name}</option>)}</select></label><label>الهاتف<input value={customerForm.phone} onChange={(e) => setCustomerForm({ ...customerForm, phone: e.target.value })} /></label><label>العنوان<input value={customerForm.address} onChange={(e) => setCustomerForm({ ...customerForm, address: e.target.value })} /></label><button type="submit" disabled={busy}>{busy ? 'جارٍ الحفظ…' : 'فتح حساب العميل'}</button></form></section><section className="form-card"><div className="card-heading"><h3>سند قبض</h3><span>يُرحّل بعد الاعتماد</span></div><form className="management-form" onSubmit={createReceipt}><label>رقم السند<input value={receiptForm.receiptNo} onChange={(e) => setReceiptForm({ ...receiptForm, receiptNo: e.target.value })} required /></label><label>العميل<select value={receiptForm.customerId} onChange={(e) => setReceiptForm({ ...receiptForm, customerId: e.target.value })} required><option value="">اختر العميل</option>{customers.map((customer) => <option value={customer.id} key={customer.id}>{customer.name}</option>)}</select></label><label>الفرع<select value={receiptForm.branchId} onChange={(e) => setReceiptForm({ ...receiptForm, branchId: e.target.value })} required><option value="">اختر الفرع</option>{branches.map((branch) => <option value={branch.id} key={branch.id}>{branch.name}</option>)}</select></label><label>المبلغ<input type="number" min="0.001" step="0.001" value={receiptForm.amount} onChange={(e) => setReceiptForm({ ...receiptForm, amount: e.target.value })} required /></label><button type="submit" disabled={busy}>{busy ? 'جارٍ الحفظ…' : 'إنشاء سند قبض'}</button></form></section></div>
    <section className="table-card receipts-card"><div className="card-heading"><h3>آخر سندات القبض</h3><span>{receipts.length} سند</span></div><div className="data-list">{receipts.map((receipt) => <article className="data-row" key={receipt.id}><div><strong>{receipt.receipt_no}</strong><small>{new Intl.DateTimeFormat('ar-SA', { dateStyle: 'medium' }).format(new Date(receipt.created_at))} · {Number(receipt.amount).toFixed(3)}</small></div><div className="row-actions"><span className={`status-badge ${receipt.status}`}>{receipt.status === 'submitted' ? 'بانتظار الاعتماد' : receipt.status === 'approved' ? 'معتمد' : receipt.status}</span>{receipt.status === 'submitted' && <button className="text-button approve" onClick={() => void approveReceipt(receipt.id)}>اعتماد وترحيل</button>}</div></article>)}{!receipts.length && <p className="empty-state">لا توجد سندات قبض.</p>}</div></section>
  </ManagementFrame>;
}
