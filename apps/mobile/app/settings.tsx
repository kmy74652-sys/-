import { useEffect, useState } from 'react';
import { useLocalSearchParams, useRouter, type ErrorBoundaryProps } from 'expo-router';
import {
  ActivityIndicator,
  Alert,
  Pressable,
  SafeAreaView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import AppShell, { ScreenHeader } from '../components/AppShell';
import { friendlyDataError, getMyEmployeeProfile } from '../lib/mobileData';
import { supabase } from '../lib/supabase';
import { loadOrganizationBranding, saveOrganizationBranding } from '../lib/organizationBranding';

type EmployeeAccess = {
  id: string;
  employeeNo: string | null;
  fullName: string | null;
  status: string;
  hasAuthAccount: boolean;
  codeSetAt: string | null;
  roleCode: string | null;
  branchId: string | null;
  branchName: string | null;
};
type Branch = { id: string; name: string };
type AuditEntry = { id: string; action: string; created_at: string; metadata?: Record<string, unknown> };
const roleOptions = [
  ['owner', 'صاحب المؤسسة'],
  ['admin_followup', 'المدير التنفيذي'],
  ['accountant', 'المحاسب'],
  ['warehouse_keeper', 'أمين المخازن'],
  ['warehouse_worker', 'عامل تحميل'],
] as const;

type EmployeeListResult = { employees?: EmployeeAccess[]; branches?: Array<Branch & { code: string; is_active: boolean }> };
type SettingsSnapshot = {
  employees: EmployeeAccess[];
  branches: Branch[];
  editForms: Record<string, { employeeNo: string; fullName: string; roleCode: string; branchId: string; status: 'active' | 'suspended' }>;
};

let settingsCache: SettingsSnapshot | null = null;

function functionStatus(error: unknown) {
  return (error as { context?: { status?: number } } | null)?.context?.status;
}

function functionErrorText(error: unknown) {
  const status = functionStatus(error);
  if (status === 401) return 'انتهت الجلسة. سجّل الدخول مجددًا.';
  if (status === 403) return 'هذه الإعدادات متاحة لصاحب المؤسسة أو المدير التنفيذي المخوّل.';
  if (status === 404 || status === 503) return 'خدمة الرموز أو تحديث قاعدة البيانات غير جاهز في Supabase بعد.';
  if (status === 429) return 'محاولات كثيرة. انتظر قليلًا ثم حاول مجددًا.';
  return 'تعذر إكمال الطلب. تحقق من الاتصال وحاول مجددًا.';
}

function normalizeEmployeeList(data: unknown): EmployeeAccess[] {
  const employees = (data as EmployeeListResult | null)?.employees;
  if (!Array.isArray(employees)) return [];
  return employees.filter((employee) => employee && typeof employee.id === 'string').map((employee) => ({
    id: employee.id,
    employeeNo: typeof employee.employeeNo === 'string' ? employee.employeeNo : null,
    fullName: typeof employee.fullName === 'string' ? employee.fullName : null,
    status: typeof employee.status === 'string' ? employee.status : 'inactive',
    hasAuthAccount: employee.hasAuthAccount === true,
    codeSetAt: typeof employee.codeSetAt === 'string' ? employee.codeSetAt : null,
    roleCode: typeof employee.roleCode === 'string' ? employee.roleCode : null,
    branchId: typeof employee.branchId === 'string' ? employee.branchId : null,
    branchName: typeof employee.branchName === 'string' ? employee.branchName : null,
  }));
}

export default function EmployeeAccessSettings() {
  const router = useRouter();
  const params = useLocalSearchParams<{ tab?: string | string[] }>();
  const activeTab = (Array.isArray(params.tab) ? params.tab[0] : params.tab) === 'employees' ? 'employees' : 'settings';
  const [employees, setEmployees] = useState<EmployeeAccess[]>([]);
  const [codes, setCodes] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [busyEmployeeId, setBusyEmployeeId] = useState<string | null>(null);
  const [expandedEmployeeId, setExpandedEmployeeId] = useState<string | null>(null);
  const [isOwner, setIsOwner] = useState(false);
  const [canEditBrand, setCanEditBrand] = useState(false);
  const [brandSettingsReady, setBrandSettingsReady] = useState(false);
  const [institutionId, setInstitutionId] = useState('');
  const [brandName, setBrandName] = useState('مؤسسة الشاعري للتجارة العامة');
  const [brandTagline, setBrandTagline] = useState('معًا... نحو إدارة أفضل');
  const [brandLogoUrl, setBrandLogoUrl] = useState('');
  const [brandBusy, setBrandBusy] = useState(false);
  const [canAssignOwner, setCanAssignOwner] = useState(false);
  const [branches, setBranches] = useState<Branch[]>([]);
  const [createForm, setCreateForm] = useState({ employeeNo: '', fullName: '', code: '', roleCode: 'warehouse_worker', branchId: '' });
  const [editForms, setEditForms] = useState<Record<string, { employeeNo: string; fullName: string; roleCode: string; branchId: string; status: 'active' | 'suspended' }>>({});
  const [audit, setAudit] = useState<Record<string, AuditEntry[]>>({});
  const [error, setError] = useState('');
  const [message, setMessage] = useState('');

  useEffect(() => {
    void loadSettings();
  }, []);
  useEffect(() => {
    const timer = setInterval(() => void loadSettings({ force: true }), 60_000);
    return () => clearInterval(timer);
  }, []);

  function applySnapshot(snapshot: SettingsSnapshot) {
    setEmployees(snapshot.employees);
    setBranches(snapshot.branches);
    setEditForms(snapshot.editForms);
    if (!createForm.branchId && createForm.roleCode !== 'owner' && snapshot.branches[0]) {
      setCreateForm((current) => ({ ...current, branchId: snapshot.branches[0].id }));
    }
  }

  function applyEmployeeList(data: unknown) {
    const nextEmployees = normalizeEmployeeList(data);
    setEmployees(nextEmployees);
    if (settingsCache) settingsCache = { ...settingsCache, employees: nextEmployees };
  }

  async function loadSettings(options: { force?: boolean } = {}) {
    if (!options.force && settingsCache) {
      applySnapshot(settingsCache);
      setLoading(false);
      return;
    }
    setLoading(true);
    setError('');
    try {
      if (!supabase) throw new Error('supabase_not_configured');
      const identity = await getMyEmployeeProfile();
      if (!identity?.employee) {
        setIsOwner(false);
        setError('يجب تسجيل الدخول بحساب صاحب المؤسسة أو المدير التنفيذي المخوّل لفتح هذه الإعدادات.');
        return;
      }
      const employeeRoles = Array.isArray(identity.employee.roles) ? identity.employee.roles : [];
      const employeePermissions = Array.isArray(identity.employee.permissions) ? identity.employee.permissions : [];
      const actualOwner = employeeRoles.some((role) => role?.code === 'owner');
      setCanAssignOwner(actualOwner);
      setCanEditBrand(actualOwner);
      setInstitutionId(identity.employee.institutionId);
      const branding = await loadOrganizationBranding(identity.employee.institutionId);
      setBrandName(branding.name);
      setBrandTagline(branding.tagline);
      setBrandLogoUrl(branding.logoUrl ?? '');
      setBrandSettingsReady(branding.settingsAvailable);
      const owner = employeeRoles.some((role) => role?.code === 'owner' || role?.code === 'admin_followup')
        && employeePermissions.includes('employees.manage');
      setIsOwner(owner);
      if (!owner) {
        setError('هذه الإعدادات متاحة لصاحب المؤسسة أو المدير التنفيذي المخوّل.');
        return;
      }
      const { data, error: listError } = await supabase.functions.invoke('employee-code-auth', {
        body: { action: 'list' },
      });
      if (listError) {
        setError(functionErrorText(listError));
        return;
      }
      const normalized = normalizeEmployeeList(data);
      const nextBranches = ((data as EmployeeListResult | null)?.branches ?? [])
        .filter((branch) => branch.is_active)
        .map((branch) => ({ id: branch.id, name: branch.name }));
      const snapshot: SettingsSnapshot = { employees: normalized, branches: nextBranches, editForms: Object.fromEntries(normalized.map((employee) => [employee.id, {
        employeeNo: employee.employeeNo ?? '',
        fullName: employee.fullName ?? '',
        roleCode: employee.roleCode ?? 'warehouse_worker',
        branchId: employee.roleCode === 'owner' ? '' : employee.branchId ?? nextBranches[0]?.id ?? '',
        status: employee.status === 'active' ? 'active' : 'suspended',
      }])) };
      settingsCache = snapshot;
      applySnapshot(snapshot);
    } catch (cause) {
      setError(friendlyDataError(cause, 'تعذر تحميل قائمة الموظفين. تحقق من الاتصال ثم أعد المحاولة.'));
    } finally {
      setLoading(false);
    }
  }

  async function saveBrandSettings() {
    if (!supabase || !institutionId || !canEditBrand) return;
    const cleanName = brandName.trim();
    const cleanTagline = brandTagline.trim();
    const cleanLogoUrl = brandLogoUrl.trim();
    if (cleanName.length < 2 || cleanName.length > 90) { setError('اسم المؤسسة يجب أن يكون بين حرفين و90 حرفًا.'); return; }
    if (cleanTagline.length > 100) { setError('العبارة التعريفية يجب ألا تتجاوز 100 حرف.'); return; }
    if (cleanLogoUrl && !/^https:\/\//i.test(cleanLogoUrl)) { setError('رابط الشعار يجب أن يبدأ بـ https://'); return; }
    setBrandBusy(true); setError(''); setMessage('');
    try {
      if (!brandSettingsReady) throw new Error('organization_branding_migration_required');
      await saveOrganizationBranding(institutionId, cleanName, cleanTagline, cleanLogoUrl || null);
      setMessage('تم حفظ هوية المؤسسة. ستظهر التغييرات في لوحة الإدارة على أجهزة الموظفين بعد تحديث التطبيق.');
    } catch (cause) {
      if (cause instanceof Error && cause.message === 'organization_branding_migration_required') {
        setError('ميزة حفظ الهوية تحتاج إلى تطبيق تحديث قاعدة البيانات أولاً. يمكنك استخدام لوحة الإدارة وإدارة الموظفين حالياً.');
      } else {
        setError(friendlyDataError(cause, 'تعذر حفظ الهوية. تحقق من صلاحية تعديل بيانات المؤسسة وتحديث قاعدة البيانات.'));
      }
    } finally { setBrandBusy(false); }
  }

  async function createEmployee() {
    if (!supabase) return;
    if (!/^\d{1,32}$/.test(createForm.employeeNo) || createForm.fullName.trim().length < 2 || !/^\S{8,64}$/.test(createForm.code) || (createForm.roleCode !== 'owner' && !createForm.branchId)) {
      setError('أدخل رقمًا وظيفيًا واسمًا وكلمة مرور أولية من 8 إلى 64 محرفًا واختر الفرع.');
      return;
    }
    setBusyEmployeeId('create'); setError(''); setMessage('');
    try {
      const { data, error: createError } = await supabase.functions.invoke('employee-code-auth', { body: { action: 'create_employee', employeeNo: createForm.employeeNo, fullName: createForm.fullName, code: createForm.code, roleCode: createForm.roleCode, branchId: createForm.roleCode === 'owner' ? null : createForm.branchId } });
      if (createError) { setError(functionErrorText(createError)); return; }
      setCreateForm({ employeeNo: '', fullName: '', code: '', roleCode: 'warehouse_worker', branchId: branches[0]?.id ?? '' });
      setMessage(`تم إنشاء الحساب للموظف ${data?.employee?.fullName ?? ''}. لن تظهر كلمة المرور مرة أخرى.`);
      await loadSettings({ force: true });
    } catch { setError('تعذر إنشاء حساب الموظف.'); } finally { setBusyEmployeeId(null); }
  }

  async function updateEmployee(employee: EmployeeAccess) {
    if (!supabase) return;
    const draft = editForms[employee.id];
    if (!draft) return;
    setBusyEmployeeId(employee.id); setError(''); setMessage('');
    try {
      const { error: updateError } = await supabase.functions.invoke('employee-code-auth', { body: { action: 'update_employee', employeeId: employee.id, ...draft, branchId: draft.roleCode === 'owner' ? null : draft.branchId } });
      if (updateError) { setError(functionErrorText(updateError)); return; }
      setMessage(`تم تحديث بيانات ${draft.fullName}.`);
      await loadSettings({ force: true });
    } catch { setError('تعذر تحديث بيانات الموظف.'); } finally { setBusyEmployeeId(null); }
  }

  async function saveCode(employee: EmployeeAccess) {
    const code = codes[employee.id] ?? '';
    if (!/^\S{8,64}$/.test(code)) {
      setError('اكتب رمزًا من 8 إلى 64 محرفًا دون مسافات.');
      setMessage('');
      return;
    }
    if (!supabase) return;
    setBusyEmployeeId(employee.id);
    setError('');
    setMessage('');
    try {
      const { error: saveError } = await supabase.functions.invoke('employee-code-auth', {
        body: { action: 'set_code', employeeId: employee.id, code },
      });
      if (saveError) {
        setError(functionErrorText(saveError));
        return;
      }
      setCodes((current) => ({ ...current, [employee.id]: '' }));
      setMessage(`تم تحديث رمز دخول ${employee.fullName}. لن يظهر الرمز المحفوظ على الشاشة.`);
      const { data, error: refreshError } = await supabase.functions.invoke('employee-code-auth', {
        body: { action: 'list' },
      });
      if (!refreshError) applyEmployeeList(data);
    } catch {
      setError('تعذر حفظ الرمز. تحقق من الاتصال ثم حاول مجددًا.');
    } finally {
      setBusyEmployeeId(null);
    }
  }

  async function loadAudit(employee: EmployeeAccess) {
    if (!supabase) return;
    const { data, error: auditError } = await supabase.functions.invoke('employee-code-auth', { body: { action: 'audit', employeeId: employee.id } });
    if (auditError) { setError(functionErrorText(auditError)); return; }
    setAudit((current) => ({ ...current, [employee.id]: Array.isArray(data?.audit) ? data.audit : [] }));
  }

  function confirmRevoke(employee: EmployeeAccess) {
    Alert.alert(
      'إلغاء رمز الدخول',
      `سيُمنع ${employee.fullName} من تسجيل دخول جديد بهذا الرمز. الجلسات المفتوحة حاليًا لن تُنهى فورًا. هل تريد المتابعة؟`,
      [
        { text: 'إلغاء', style: 'cancel' },
        { text: 'إلغاء الرمز', style: 'destructive', onPress: () => void revokeCode(employee) },
      ],
    );
  }

  async function revokeCode(employee: EmployeeAccess) {
    if (!supabase) return;
    setBusyEmployeeId(employee.id);
    setError('');
    setMessage('');
    try {
      const { error: revokeError } = await supabase.functions.invoke('employee-code-auth', {
        body: { action: 'revoke_code', employeeId: employee.id },
      });
      if (revokeError) {
        setError(functionErrorText(revokeError));
        return;
      }
      setMessage(`تم إلغاء رمز الدخول لـ ${employee.fullName}.`);
      const { data, error: refreshError } = await supabase.functions.invoke('employee-code-auth', {
        body: { action: 'list' },
      });
      if (!refreshError) applyEmployeeList(data);
    } catch {
      setError('تعذر إلغاء الرمز. تحقق من الاتصال ثم حاول مجددًا.');
    } finally {
      setBusyEmployeeId(null);
    }
  }

  function confirmDeleteEmployee(employee: EmployeeAccess) {
    Alert.alert(
      'حذف حساب الموظف نهائيًا',
      `سيُحذف حساب ${employee.fullName} وملف الموظف ورمز الدخول نهائيًا، ولا يمكن التراجع. هل تريد المتابعة؟`,
      [
        { text: 'إلغاء', style: 'cancel' },
        { text: 'حذف نهائي', style: 'destructive', onPress: () => void deleteEmployee(employee) },
      ],
    );
  }

  async function deleteEmployee(employee: EmployeeAccess) {
    if (!supabase) return;
    setBusyEmployeeId(employee.id); setError(''); setMessage('');
    try {
      const { error: deleteError } = await supabase.rpc('admin_delete_employee_record', { p_organization_id: institutionId, p_membership_id: employee.id });
      if (deleteError) { setError(functionErrorText(deleteError)); return; }
      setMessage(`تم حذف حساب ${employee.fullName} نهائيًا.`);
      await loadSettings({ force: true });
    } catch { setError('تعذر حذف حساب الموظف. تحقق من الصلاحية والاتصال.'); }
    finally { setBusyEmployeeId(null); }
  }

  if (!loading && !isOwner) {
    return <AppShell activeTab={activeTab} title={activeTab === 'employees' ? 'الموظفون' : 'الإعدادات'} subtitle="إدارة المؤسسة والموظفين">
      <ScreenHeader title={activeTab === 'employees' ? 'الموظفون' : 'الإعدادات'} subtitle="إدارة المؤسسة والموظفين" onBack={() => { if (router.canGoBack()) router.back(); else router.replace('/'); }} />
      <View style={styles.unavailable}><Text style={styles.title}>هذه الصفحة غير متاحة</Text><Text style={styles.copy}>{error || 'تحتاج إلى صلاحية صاحب المؤسسة أو المدير التنفيذي المخوّل.'}</Text><Pressable style={styles.refresh} onPress={() => void loadSettings({ force: true })}><Text style={styles.refreshText}>إعادة المحاولة</Text></Pressable></View>
    </AppShell>;
  }

  return (
    <AppShell activeTab={activeTab} title={activeTab === 'employees' ? 'الموظفون' : 'الإعدادات'} subtitle="إدارة المؤسسة والموظفين">
      <ScreenHeader title={activeTab === 'employees' ? 'الموظفون' : 'الإعدادات'} subtitle="إدارة المؤسسة والموظفين" onBack={() => { if (router.canGoBack()) router.back(); else router.replace('/'); }} />
      <View style={styles.content}>
        {activeTab === 'settings' && !loading && canEditBrand && <View style={styles.employeeCard}>
          <Text style={styles.employeeName}>هوية المؤسسة والواجهة الرئيسية</Text>
          <Text style={styles.copy}>يمكن لصاحب المؤسسة تغيير الاسم والعبارة التعريفية ورابط الشعار. تُحفظ الإعدادات مركزياً لتظهر في أجهزة المستخدمين.</Text>
          {!brandSettingsReady && <Text style={styles.warning}>تحديث قاعدة البيانات الخاص بهوية المؤسسة لم يُطبّق بعد؛ ستعمل بقية إعدادات الموظفين بصورة طبيعية.</Text>}
          <Text style={styles.employeeMeta}>اسم المؤسسة</Text>
          <TextInput style={styles.input} value={brandName} onChangeText={setBrandName} maxLength={90} placeholder="اسم المؤسسة" />
          <Text style={styles.employeeMeta}>العبارة التعريفية</Text>
          <TextInput style={styles.input} value={brandTagline} onChangeText={setBrandTagline} maxLength={100} placeholder="عبارة تظهر أسفل اسم المؤسسة" />
          <Text style={styles.employeeMeta}>رابط الشعار (HTTPS)</Text>
          <TextInput style={styles.input} value={brandLogoUrl} onChangeText={setBrandLogoUrl} autoCapitalize="none" autoCorrect={false} keyboardType="url" placeholder="https://example.com/logo.png" />
          <Text style={styles.employeeMeta}>اترك رابط الشعار فارغًا لاستخدام شعار التطبيق الافتراضي.</Text>
          <Pressable accessibilityRole="button" disabled={brandBusy || !brandSettingsReady} style={styles.primaryButton} onPress={() => void saveBrandSettings()}>{brandBusy ? <ActivityIndicator color="#fff" /> : <Text style={styles.buttonText}>حفظ هوية المؤسسة</Text>}</Pressable>
        </View>}
        {activeTab === 'employees' && <>
        <Text style={styles.eyebrow}>إدارة آمنة للدخول</Text>
        <Text style={styles.title}>رموز دخول الموظفين</Text>
        <Text style={styles.copy}>
          عيّن لكل موظف رمزًا خاصًا لا يقل عن 8 محارف. يُحفظ الرمز كبيانات اعتماد محمية لدى Supabase ولا يمكن استرجاعه بعد الحفظ؛ لتغييره أدخل رمزًا جديدًا.
        </Text>
        <Text style={styles.note}>
          إلغاء الرمز يمنع تسجيلات الدخول الجديدة، لكنه لا ينهي الجلسات المفتوحة حاليًا. لا تشارك الرمز في محادثة عامة.
        </Text>
        {!!error && <Text accessibilityRole="alert" style={styles.error}>{error}</Text>}
        {!!message && <Text accessibilityLiveRegion="polite" style={styles.success}>{message}</Text>}

        {activeTab === 'employees' && !loading && isOwner && (
          <View style={styles.employeeCard}>
            <Text style={styles.employeeName}>إنشاء حساب موظف</Text>
            <TextInput style={styles.input} placeholder="اسم الموظف" value={createForm.fullName} onChangeText={(value) => setCreateForm((current) => ({ ...current, fullName: value }))} />
            <TextInput style={styles.input} placeholder="رقم الموظف الفريد" keyboardType="number-pad" value={createForm.employeeNo} onChangeText={(value) => setCreateForm((current) => ({ ...current, employeeNo: value }))} />
            <TextInput style={styles.input} placeholder="كلمة المرور الأولية" secureTextEntry value={createForm.code} onChangeText={(value) => setCreateForm((current) => ({ ...current, code: value }))} />
            <Text style={styles.employeeMeta}>التصنيف الوظيفي</Text>
            <View style={styles.roleChoices}>{roleOptions.filter(([code]) => code !== 'owner' || canAssignOwner).map(([code, label]) => <Pressable key={code} accessibilityRole="button" style={[styles.roleChoice, createForm.roleCode === code && styles.roleChoiceActive]} onPress={() => setCreateForm((current) => ({ ...current, roleCode: code, branchId: code === 'owner' ? '' : current.branchId || branches[0]?.id || '' }))}><Text style={styles.roleChoiceText}>{label}</Text></Pressable>)}</View>
            {createForm.roleCode === 'owner' ? (
              <Text style={styles.employeeMeta}>نطاق الصلاحية: المؤسسة بالكامل، دون ربط بفرع.</Text>
            ) : (
              <>
                <Text style={styles.employeeMeta}>الفرع</Text>
                <View style={styles.roleChoices}>{branches.map((branch) => <Pressable key={branch.id} accessibilityRole="button" style={[styles.roleChoice, createForm.branchId === branch.id && styles.roleChoiceActive]} onPress={() => setCreateForm((current) => ({ ...current, branchId: branch.id }))}><Text style={styles.roleChoiceText}>{branch.name}</Text></Pressable>)}</View>
              </>
            )}
            <Pressable accessibilityRole="button" disabled={busyEmployeeId !== null} style={styles.primaryButton} onPress={() => void createEmployee()}><Text style={styles.buttonText}>{busyEmployeeId === 'create' ? 'جارٍ الإنشاء…' : 'إنشاء الحساب'}</Text></Pressable>
          </View>
        )}

        {loading ? (
          <View style={styles.loading}><ActivityIndicator size="large" color="#17324d" /><Text style={styles.copy}>جارٍ تحميل الموظفين…</Text></View>
        ) : isOwner && employees.length === 0 ? (
          <Text style={styles.copy}>لا توجد ملفات موظفين مرتبطة بهذه المؤسسة.</Text>
        ) : isOwner ? employees.map((employee) => {
          const active = employee.status === 'active';
          const busy = busyEmployeeId === employee.id;
          return (
            <View style={styles.employeeCard} key={employee.id}>
              <Text style={styles.employeeName}>{employee.fullName || 'موظف'}</Text>
              <Text style={styles.employeeMeta}>رقم الموظف: {employee.employeeNo || 'غير محدد'}</Text>
              <Text style={styles.employeeMeta}>
                {employee.codeSetAt ? 'تم تعيين رمز دخول' : 'لم يُعيّن رمز دخول بعد'}
                {!active ? ' · الحساب غير نشط' : ''}
              </Text>
              <Pressable accessibilityRole="button" accessibilityState={{ expanded: expandedEmployeeId === employee.id }} style={styles.manageToggle} onPress={() => setExpandedEmployeeId((current) => current === employee.id ? null : employee.id)}><Text style={styles.manageToggleText}>{expandedEmployeeId === employee.id ? 'إغلاق إدارة الحساب' : 'إدارة الحساب والرمز'}</Text></Pressable>
              {!employee.hasAuthAccount && (
                <Text style={styles.warning}>لا يوجد حساب مصادقة مرتبط بملف هذا الموظف؛ لا يمكن تعيين كلمة مرور له حتى يربطه مسؤول النظام.</Text>
              )}
              {isOwner && expandedEmployeeId === employee.id && editForms[employee.id] && (
                <>
                  <TextInput style={styles.input} placeholder="الاسم" value={editForms[employee.id].fullName} onChangeText={(value) => setEditForms((current) => ({ ...current, [employee.id]: { ...current[employee.id], fullName: value } }))} />
                  <TextInput style={styles.input} placeholder="الرقم الوظيفي" value={editForms[employee.id].employeeNo} onChangeText={(value) => setEditForms((current) => ({ ...current, [employee.id]: { ...current[employee.id], employeeNo: value } }))} />
                  <Text style={styles.employeeMeta}>التصنيف الوظيفي</Text>
                  <View style={styles.roleChoices}>{roleOptions.filter(([code]) => code !== 'owner' || canAssignOwner).map(([code, label]) => <Pressable key={code} accessibilityRole="button" style={[styles.roleChoice, editForms[employee.id].roleCode === code && styles.roleChoiceActive]} onPress={() => setEditForms((current) => ({ ...current, [employee.id]: { ...current[employee.id], roleCode: code, branchId: code === 'owner' ? '' : current[employee.id].branchId || branches[0]?.id || '' } }))}><Text style={styles.roleChoiceText}>{label}</Text></Pressable>)}</View>
                  {editForms[employee.id].roleCode === 'owner' ? (
                    <Text style={styles.employeeMeta}>نطاق الصلاحية: المؤسسة بالكامل، دون ربط بفرع.</Text>
                  ) : (
                    <>
                      <Text style={styles.employeeMeta}>الفرع الحالي: {employee.branchName ?? 'غير محدد'}</Text>
                      <View style={styles.roleChoices}>{branches.map((branch) => <Pressable key={branch.id} accessibilityRole="button" style={[styles.roleChoice, editForms[employee.id].branchId === branch.id && styles.roleChoiceActive]} onPress={() => setEditForms((current) => ({ ...current, [employee.id]: { ...current[employee.id], branchId: branch.id } }))}><Text style={styles.roleChoiceText}>{branch.name}</Text></Pressable>)}</View>
                    </>
                  )}
                  <Pressable accessibilityRole="button" style={styles.refresh} onPress={() => setEditForms((current) => ({ ...current, [employee.id]: { ...current[employee.id], status: current[employee.id].status === 'active' ? 'suspended' : 'active' } }))}><Text style={styles.refreshText}>{editForms[employee.id].status === 'active' ? 'تجهيز لإيقاف الحساب مع حفظ السجلات' : 'تجهيز لإعادة تفعيل الحساب'}</Text></Pressable>
                  <Pressable accessibilityRole="button" disabled={busyEmployeeId !== null} style={styles.primaryButton} onPress={() => void updateEmployee(employee)}><Text style={styles.buttonText}>{busyEmployeeId === employee.id ? 'جارٍ الحفظ…' : 'حفظ بيانات الحساب'}</Text></Pressable>
                  {employee.roleCode !== 'owner' && <Pressable accessibilityRole="button" disabled={busyEmployeeId !== null} style={styles.dangerButton} onPress={() => confirmDeleteEmployee(employee)}><Text style={styles.dangerText}>حذف الحساب نهائيًا</Text></Pressable>}
                  <Pressable accessibilityRole="button" style={styles.refresh} onPress={() => void loadAudit(employee)}><Text style={styles.refreshText}>عرض سجل التعديلات</Text></Pressable>
                  {(audit[employee.id] ?? []).map((entry) => <Text style={styles.employeeMeta} key={entry.id}>{entry.action} · {new Date(entry.created_at).toLocaleString('ar-SA')}</Text>)}
                </>
              )}
              {expandedEmployeeId === employee.id && active && employee.hasAuthAccount && (
                <>
                  <TextInput
                    style={styles.input}
                    placeholder={employee.codeSetAt ? 'أدخل رمزًا جديدًا للتغيير' : 'أنشئ رمز دخول لهذا الموظف'}
                    secureTextEntry
                    autoCapitalize="none"
                    autoCorrect={false}
                    autoComplete="off"
                    maxLength={64}
                    value={codes[employee.id] ?? ''}
                    onChangeText={(value) => setCodes((current) => ({ ...current, [employee.id]: value }))}
                    editable={!busy}
                    accessibilityLabel={`رمز دخول الموظف ${employee.fullName}`}
                  />
                  <Pressable
                    accessibilityRole="button"
                    accessibilityState={{ disabled: busy }}
                    style={({ pressed }) => [styles.primaryButton, pressed && !busy && styles.pressed]}
                    disabled={busy}
                    onPress={() => void saveCode(employee)}
                  >
                    {busy ? <ActivityIndicator color="#fff" /> : <Text style={styles.buttonText}>{employee.codeSetAt ? 'تغيير الرمز' : 'تعيين الرمز'}</Text>}
                  </Pressable>
                  {employee.codeSetAt && (
                    <Pressable
                      accessibilityRole="button"
                      accessibilityState={{ disabled: busy }}
                      style={({ pressed }) => [styles.dangerButton, pressed && !busy && styles.pressed]}
                      disabled={busy}
                      onPress={() => confirmRevoke(employee)}
                    >
                      <Text style={styles.dangerText}>إلغاء الرمز</Text>
                    </Pressable>
                  )}
                </>
              )}
            </View>
          );
        }) : null}

        </>}
      </View>
    </AppShell>
  );
}

export function ErrorBoundary({ error, retry }: ErrorBoundaryProps) {
  return (
    <SafeAreaView style={styles.safe}>
      <View style={styles.content}>
        <Text style={styles.title}>تعذر فتح إعدادات الموظفين</Text>
        <Text accessibilityRole="alert" style={styles.error}>
          أوقفنا هذا الجزء بأمان بدل إغلاق التطبيق. رمز الخطأ: {error?.name || 'غير معروف'}.
        </Text>
        <Pressable accessibilityRole="button" style={styles.refresh} onPress={() => { void retry(); }}>
          <Text style={styles.refreshText}>إعادة فتح الصفحة</Text>
        </Pressable>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: '#f4f7f8' },
  content: { padding: 18, paddingTop: 4, paddingBottom: 36, direction: 'rtl' },
  back: { alignSelf: 'flex-end', paddingVertical: 8, paddingHorizontal: 4, marginBottom: 12 },
  backText: { color: '#39556a', fontSize: 15, fontWeight: '700' },
  eyebrow: { color: '#718394', fontSize: 13, fontWeight: '700', marginBottom: 6, textAlign: 'right' },
  title: { color: '#17324d', fontSize: 26, fontWeight: '800', textAlign: 'right', marginBottom: 10, lineHeight: 38 },
  copy: { color: '#718394', fontSize: 14, lineHeight: 22, textAlign: 'right', marginBottom: 12 },
  note: { color: '#73521f', backgroundColor: '#fff5df', borderColor: '#f0dfb8', borderWidth: 1, borderRadius: 12, padding: 12, textAlign: 'right', lineHeight: 21, marginBottom: 14 },
  error: { color: '#a8443d', textAlign: 'right', lineHeight: 22, marginBottom: 10 },
  success: { color: '#23633c', textAlign: 'right', lineHeight: 22, marginBottom: 10 },
  loading: { alignItems: 'center', paddingVertical: 28 }, unavailable: { backgroundColor: '#fff', borderWidth: 1, borderColor: '#e2e9eb', borderRadius: 16, padding: 18, gap: 10, marginTop: 12 },
  employeeCard: { backgroundColor: '#fff', borderRadius: 16, padding: 16, marginTop: 12, borderWidth: 1, borderColor: '#e2e9eb' },
  employeeName: { color: '#17324d', fontSize: 17, fontWeight: '800', textAlign: 'right', lineHeight: 25 },
  employeeMeta: { color: '#718394', fontSize: 13, textAlign: 'right', marginTop: 5, lineHeight: 20 },
  warning: { color: '#8b3a2e', textAlign: 'right', lineHeight: 21, marginTop: 10 },
  input: { minHeight: 48, borderWidth: 1, borderColor: '#d6e0e4', borderRadius: 11, paddingHorizontal: 12, marginTop: 14, marginBottom: 10, textAlign: 'right', fontSize: 16, backgroundColor: '#fbfcfc' },
  primaryButton: { minHeight: 46, backgroundColor: '#17324d', borderRadius: 11, padding: 12, alignItems: 'center', justifyContent: 'center' },
  buttonText: { color: '#fff', fontWeight: '800' },
  dangerButton: { minHeight: 42, borderWidth: 1, borderColor: '#b55248', borderRadius: 10, padding: 10, alignItems: 'center', justifyContent: 'center', marginTop: 9 },
  dangerText: { color: '#a8443d', fontWeight: '800' },
  refresh: { minHeight: 46, alignItems: 'center', justifyContent: 'center', marginTop: 18, borderWidth: 1, borderColor: '#17324d', borderRadius: 11 },
  refreshText: { color: '#17324d', fontWeight: '800' },
  manageToggle: { minHeight: 40, borderRadius: 10, backgroundColor: '#e9f0f4', alignItems: 'center', justifyContent: 'center', marginTop: 12, paddingHorizontal: 10 }, manageToggleText: { color: '#17324d', fontWeight: '800' }, roleChoices: { flexDirection: 'row-reverse', flexWrap: 'wrap', gap: 8, marginBottom: 10 },
  roleChoice: { borderWidth: 1, borderColor: '#d6e0e4', borderRadius: 10, paddingVertical: 9, paddingHorizontal: 10, backgroundColor: '#fbfcfc' },
  roleChoiceActive: { backgroundColor: '#dceee7', borderColor: '#2f6654' },
  roleChoiceText: { color: '#39556a', fontSize: 13, fontWeight: '700' },
  pressed: { opacity: 0.82 },
});
