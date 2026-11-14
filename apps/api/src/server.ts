import 'dotenv/config';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import cors from 'cors';
import express from 'express';
import { randomUUID } from 'node:crypto';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { z } from 'zod';

const port = Number(process.env.PORT ?? (process.env.NODE_ENV === 'production' ? 3000 : 3001));
const app = express();
const currentFile = fileURLToPath(import.meta.url);
const webDist = path.resolve(path.dirname(currentFile), '../../web/dist');
const normalizedSupabaseUrl = process.env.SUPABASE_URL?.replace(/\/rest\/v1\/?$/, '');
const supabaseAdmin: SupabaseClient | null = normalizedSupabaseUrl && process.env.SUPABASE_SERVICE_ROLE_KEY
  ? createClient(normalizedSupabaseUrl, process.env.SUPABASE_SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
    })
  : null;

app.use(cors({ origin: true, credentials: true }));
app.use(express.json({ limit: '1mb' }));

app.get('/api/health', (_request, response) => {
  response.json({ ok: true, service: 'alshaeri-api', stage: 'phase-4' });
});

app.get('/api/config/status', (_request, response) => {
  const config = z.object({
    SUPABASE_URL: z.string().url(),
    SUPABASE_ANON_KEY: z.string().min(1),
    SUPABASE_SERVICE_ROLE_KEY: z.string().min(1),
  }).safeParse(process.env);

  response.json({
    configured: config.success,
    message: config.success ? 'Supabase configuration is present.' : 'Supabase secrets are not configured yet.',
  });
});

type AuthenticatedRequest = express.Request & {
  employee?: {
    id: string;
    institutionId: string;
    employeeNo: string;
    fullName: string;
    email: string | null;
    phone: string | null;
    status: string;
    lastLoginAt: string | null;
    roles: Array<{ code: string; nameAr: string }>;
    permissions: string[];
    branches: Array<{ id: string; code: string; name: string; isDefault: boolean }>;
  };
};

async function requireEmployee(request: AuthenticatedRequest, response: express.Response, next: express.NextFunction) {
  if (!supabaseAdmin) return response.status(503).json({ error: 'auth_not_configured' });
  const authorization = request.get('authorization');
  const token = authorization?.startsWith('Bearer ') ? authorization.slice(7) : null;
  if (!token) return response.status(401).json({ error: 'missing_bearer_token' });

  const { data: userData, error: userError } = await supabaseAdmin.auth.getUser(token);
  if (userError || !userData.user) return response.status(401).json({ error: 'invalid_session' });

  const { data: employee, error: employeeError } = await supabaseAdmin
    .from('employees')
    .select('id,institution_id,employee_no,full_name,email,phone,status,last_login_at')
    .eq('auth_user_id', userData.user.id)
    .maybeSingle();
  if (employeeError) return response.status(500).json({ error: 'employee_lookup_failed' });
  if (!employee || employee.status !== 'active') return response.status(403).json({ error: 'employee_not_active' });

  const [{ data: roleLinks }, { data: branchLinks }] = await Promise.all([
    supabaseAdmin.from('employee_roles').select('role_id').eq('institution_id', employee.institution_id).eq('employee_id', employee.id),
    supabaseAdmin.from('employee_branches').select('branch_id,is_default').eq('institution_id', employee.institution_id).eq('employee_id', employee.id),
  ]);
  const roleIds = (roleLinks ?? []).map((link) => link.role_id);
  const branchIds = (branchLinks ?? []).map((link) => link.branch_id);
  const [{ data: roles }, { data: rolePermissions }, { data: overrides }, { data: branches }] = await Promise.all([
    roleIds.length ? supabaseAdmin.from('roles').select('id,code,name_ar').eq('institution_id', employee.institution_id).in('id', roleIds) : Promise.resolve({ data: [] }),
    roleIds.length ? supabaseAdmin.from('role_permissions').select('permission_code').eq('institution_id', employee.institution_id).in('role_id', roleIds) : Promise.resolve({ data: [] }),
    supabaseAdmin.from('employee_permission_overrides').select('permission_code,allowed').eq('institution_id', employee.institution_id).eq('employee_id', employee.id),
    branchIds.length ? supabaseAdmin.from('branches').select('id,code,name').eq('institution_id', employee.institution_id).in('id', branchIds) : Promise.resolve({ data: [] }),
  ]);

  const permissions = new Set((rolePermissions ?? []).map((item) => item.permission_code));
  for (const override of overrides ?? []) {
    if (override.allowed) permissions.add(override.permission_code);
    else permissions.delete(override.permission_code);
  }
  await supabaseAdmin.from('employees').update({ last_login_at: new Date().toISOString() }).eq('id', employee.id);
  request.employee = {
    id: employee.id,
    institutionId: employee.institution_id,
    employeeNo: employee.employee_no,
    fullName: employee.full_name,
    email: employee.email,
    phone: employee.phone,
    status: employee.status,
    lastLoginAt: employee.last_login_at,
    roles: (roles ?? []).map((role) => ({ code: role.code, nameAr: role.name_ar })),
    permissions: [...permissions].sort(),
    branches: (branches ?? []).map((branch) => ({
      id: branch.id,
      code: branch.code,
      name: branch.name,
      isDefault: Boolean((branchLinks ?? []).find((link) => link.branch_id === branch.id)?.is_default),
    })),
  };
  return next();
}

app.get('/api/me', requireEmployee, (request: AuthenticatedRequest, response) => {
  response.json({ employee: request.employee });
});

function requirePermission(permission: string) {
  return (request: AuthenticatedRequest, response: express.Response, next: express.NextFunction) => {
    if (!request.employee?.permissions.includes(permission)) return response.status(403).json({ error: 'permission_denied', permission });
    return next();
  };
}

function requireAnyPermission(...permissions: string[]) {
  return (request: AuthenticatedRequest, response: express.Response, next: express.NextFunction) => {
    if (!permissions.some((permission) => request.employee?.permissions.includes(permission))) return response.status(403).json({ error: 'permission_denied', permissions });
    return next();
  };
}

const employeeCreateSchema = z.object({
  employeeNo: z.string().trim().min(1).max(32),
  fullName: z.string().trim().min(2).max(160),
  email: z.string().email(),
  password: z.string().min(8).max(128),
  phone: z.string().trim().max(40).optional().nullable(),
  baseBranchId: z.string().uuid(),
  roleCode: z.enum(['owner', 'admin_followup', 'accountant', 'warehouse_keeper', 'warehouse_worker']),
});

app.get('/api/branches', requireEmployee, async (request: AuthenticatedRequest, response) => {
  if (!supabaseAdmin || !request.employee) return response.status(503).json({ error: 'auth_not_configured' });
  let query = supabaseAdmin.from('branches').select('id,code,name,address,phone,is_active,branch_level,parent_branch_id,created_at').eq('institution_id', request.employee.institutionId).order('branch_level').order('name');
  if (!request.employee.permissions.includes('branches.read_all')) {
    const allowedIds = request.employee.branches.map((branch) => branch.id);
    if (!allowedIds.length) return response.json({ branches: [] });
    query = query.in('id', allowedIds);
  }
  const { data, error } = await query;
  if (error) return response.status(500).json({ error: 'branches_lookup_failed' });
  return response.json({ branches: data ?? [] });
});

app.post('/api/branches', requireEmployee, requirePermission('branches.manage'), async (request: AuthenticatedRequest, response) => {
  if (!supabaseAdmin || !request.employee) return response.status(503).json({ error: 'auth_not_configured' });
  const parsed = z.object({ code: z.string().trim().regex(/^[a-z0-9][a-z0-9_-]{1,31}$/), name: z.string().trim().min(2).max(160), address: z.string().trim().max(300).optional().nullable(), phone: z.string().trim().max(40).optional().nullable(), branchLevel: z.number().int().min(1).max(3).default(1), parentBranchId: z.string().uuid().optional().nullable() }).safeParse(request.body);
  if (!parsed.success) return response.status(400).json({ error: 'invalid_branch_payload' });
  const { data, error } = await supabaseAdmin.from('branches').insert({ code: parsed.data.code, name: parsed.data.name, address: parsed.data.address ?? null, phone: parsed.data.phone ?? null, branch_level: parsed.data.branchLevel, parent_branch_id: parsed.data.parentBranchId ?? null, institution_id: request.employee.institutionId }).select('id,code,name,address,phone,is_active,branch_level,parent_branch_id,created_at').single();
  if (error) return response.status(400).json({ error: 'branch_create_failed', detail: error.code === '23505' ? 'branch_code_exists' : undefined });
  return response.status(201).json({ branch: data });
});

app.patch('/api/branches/:branchId', requireEmployee, requirePermission('branches.manage'), async (request: AuthenticatedRequest, response) => {
  if (!supabaseAdmin || !request.employee) return response.status(503).json({ error: 'auth_not_configured' });
  const parsed = z.object({ name: z.string().trim().min(2).max(160).optional(), address: z.string().trim().max(300).optional().nullable(), phone: z.string().trim().max(40).optional().nullable(), branchLevel: z.number().int().min(1).max(3).optional(), parentBranchId: z.string().uuid().optional().nullable(), isActive: z.boolean().optional() }).safeParse(request.body);
  if (!parsed.success || !Object.keys(parsed.data).length) return response.status(400).json({ error: 'invalid_branch_payload' });
  const update = {
    ...(parsed.data.name === undefined ? {} : { name: parsed.data.name }),
    ...(parsed.data.address === undefined ? {} : { address: parsed.data.address }),
    ...(parsed.data.phone === undefined ? {} : { phone: parsed.data.phone }),
    ...(parsed.data.branchLevel === undefined ? {} : { branch_level: parsed.data.branchLevel }),
    ...(parsed.data.parentBranchId === undefined ? {} : { parent_branch_id: parsed.data.parentBranchId }),
    ...(parsed.data.isActive === undefined ? {} : { is_active: parsed.data.isActive }),
  } as Record<string, unknown>;
  const { data, error } = await supabaseAdmin.from('branches').update(update).eq('institution_id', request.employee.institutionId).eq('id', request.params.branchId).select('id,code,name,address,phone,is_active,branch_level,parent_branch_id,created_at').maybeSingle();
  if (error) return response.status(400).json({ error: 'branch_update_failed' });
  if (!data) return response.status(404).json({ error: 'branch_not_found' });
  return response.json({ branch: data });
});

app.get('/api/employees', requireEmployee, requirePermission('employees.read'), async (request: AuthenticatedRequest, response) => {
  if (!supabaseAdmin || !request.employee) return response.status(503).json({ error: 'auth_not_configured' });
  const { data, error } = await supabaseAdmin.from('employees').select('id,employee_no,full_name,email,phone,status,base_branch_id,last_login_at,created_at').eq('institution_id', request.employee.institutionId).order('full_name');
  if (error) return response.status(500).json({ error: 'employees_lookup_failed' });
  return response.json({ employees: data ?? [] });
});

app.post('/api/employees', requireEmployee, requirePermission('employees.manage'), async (request: AuthenticatedRequest, response) => {
  if (!supabaseAdmin || !request.employee) return response.status(503).json({ error: 'auth_not_configured' });
  const parsed = employeeCreateSchema.safeParse(request.body);
  if (!parsed.success) return response.status(400).json({ error: 'invalid_employee_payload' });
  if (parsed.data.roleCode === 'owner' && !request.employee.roles.some((role) => role.code === 'owner')) return response.status(403).json({ error: 'owner_role_required' });
  const { data: branch } = await supabaseAdmin.from('branches').select('id').eq('institution_id', request.employee.institutionId).eq('id', parsed.data.baseBranchId).maybeSingle();
  if (!branch) return response.status(400).json({ error: 'base_branch_not_found' });

  const { data: authData, error: authError } = await supabaseAdmin.auth.admin.createUser({ email: parsed.data.email, password: parsed.data.password, email_confirm: true });
  if (authError || !authData.user) return response.status(400).json({ error: 'auth_user_create_failed' });
  const authUserId = authData.user.id;
  const { data: employee, error: employeeError } = await supabaseAdmin.from('employees').insert({ institution_id: request.employee.institutionId, auth_user_id: authUserId, employee_no: parsed.data.employeeNo, full_name: parsed.data.fullName, email: parsed.data.email, phone: parsed.data.phone ?? null, base_branch_id: parsed.data.baseBranchId }).select('id,employee_no,full_name,email,phone,status,base_branch_id').single();
  if (employeeError || !employee) {
    await supabaseAdmin.auth.admin.deleteUser(authUserId);
    return response.status(400).json({ error: 'employee_create_failed', detail: employeeError?.code === '23505' ? 'employee_no_or_email_exists' : undefined });
  }
  const { data: role } = await supabaseAdmin.from('roles').select('id').eq('institution_id', request.employee.institutionId).eq('code', parsed.data.roleCode).maybeSingle();
  if (!role) {
    await supabaseAdmin.from('employees').delete().eq('id', employee.id);
    await supabaseAdmin.auth.admin.deleteUser(authUserId);
    return response.status(400).json({ error: 'role_not_found' });
  }
  const [{ error: roleError }, { error: branchError }] = await Promise.all([
    supabaseAdmin.from('employee_roles').insert({ institution_id: request.employee.institutionId, employee_id: employee.id, role_id: role.id }),
    supabaseAdmin.from('employee_branches').insert({ institution_id: request.employee.institutionId, employee_id: employee.id, branch_id: parsed.data.baseBranchId, is_default: true }),
  ]);
  if (roleError || branchError) {
    await supabaseAdmin.from('employees').delete().eq('id', employee.id);
    await supabaseAdmin.auth.admin.deleteUser(authUserId);
    return response.status(400).json({ error: 'employee_access_setup_failed' });
  }
  return response.status(201).json({ employee });
});

app.patch('/api/employees/:employeeId/status', requireEmployee, requirePermission('employees.manage'), async (request: AuthenticatedRequest, response) => {
  if (!supabaseAdmin || !request.employee) return response.status(503).json({ error: 'auth_not_configured' });
  if (request.params.employeeId === request.employee.id) return response.status(400).json({ error: 'cannot_change_own_status' });
  const parsed = z.object({ status: z.enum(['active', 'suspended', 'archived']) }).safeParse(request.body);
  if (!parsed.success) return response.status(400).json({ error: 'invalid_employee_status' });
  const { data, error } = await supabaseAdmin.from('employees').update({ status: parsed.data.status }).eq('institution_id', request.employee.institutionId).eq('id', request.params.employeeId).select('id,employee_no,full_name,email,phone,status,base_branch_id,last_login_at,created_at').maybeSingle();
  if (error) return response.status(400).json({ error: 'employee_status_update_failed' });
  if (!data) return response.status(404).json({ error: 'employee_not_found' });
  return response.json({ employee: data });
});

app.get('/api/roles', requireEmployee, requirePermission('roles.read'), async (request: AuthenticatedRequest, response) => {
  if (!supabaseAdmin || !request.employee) return response.status(503).json({ error: 'auth_not_configured' });
  const { data: roles, error } = await supabaseAdmin.from('roles').select('id,code,name_ar,description').eq('institution_id', request.employee.institutionId).order('name_ar');
  if (error) return response.status(500).json({ error: 'roles_lookup_failed' });
  return response.json({ roles: roles ?? [] });
});

app.patch('/api/employees/:employeeId/access', requireEmployee, requirePermission('employees.manage'), async (request: AuthenticatedRequest, response) => {
  if (!supabaseAdmin || !request.employee) return response.status(503).json({ error: 'auth_not_configured' });
  const parsed = z.object({ roleCodes: z.array(z.enum(['owner', 'admin_followup', 'accountant', 'warehouse_keeper', 'warehouse_worker'])).min(1).max(5), branchIds: z.array(z.string().uuid()).min(1).max(50), defaultBranchId: z.string().uuid() }).safeParse(request.body);
  if (!parsed.success || !parsed.data.branchIds.includes(parsed.data.defaultBranchId)) return response.status(400).json({ error: 'invalid_employee_access_payload' });
  if (request.params.employeeId === request.employee.id && !request.employee.roles.some((role) => role.code === 'owner')) return response.status(403).json({ error: 'owner_role_required' });
  if (parsed.data.roleCodes.includes('owner') && !request.employee.roles.some((role) => role.code === 'owner')) return response.status(403).json({ error: 'owner_role_required' });
  const [{ data: employee }, { data: roles }, { data: branches }] = await Promise.all([
    supabaseAdmin.from('employees').select('id').eq('institution_id', request.employee.institutionId).eq('id', request.params.employeeId).maybeSingle(),
    supabaseAdmin.from('roles').select('id,code').eq('institution_id', request.employee.institutionId).in('code', parsed.data.roleCodes),
    supabaseAdmin.from('branches').select('id').eq('institution_id', request.employee.institutionId).in('id', parsed.data.branchIds).eq('is_active', true),
  ]);
  if (!employee || (roles ?? []).length !== parsed.data.roleCodes.length || (branches ?? []).length !== parsed.data.branchIds.length) return response.status(404).json({ error: 'employee_access_reference_not_found' });
  await supabaseAdmin.from('employee_roles').delete().eq('institution_id', request.employee.institutionId).eq('employee_id', request.params.employeeId);
  await supabaseAdmin.from('employee_branches').delete().eq('institution_id', request.employee.institutionId).eq('employee_id', request.params.employeeId);
  const [{ error: roleError }, { error: branchError }] = await Promise.all([
    supabaseAdmin.from('employee_roles').insert((roles ?? []).map((role) => ({ institution_id: request.employee!.institutionId, employee_id: request.params.employeeId, role_id: role.id }))),
    supabaseAdmin.from('employee_branches').insert(parsed.data.branchIds.map((branchId) => ({ institution_id: request.employee!.institutionId, employee_id: request.params.employeeId, branch_id: branchId, is_default: branchId === parsed.data.defaultBranchId }))),
  ]);
  if (roleError || branchError) return response.status(400).json({ error: 'employee_access_update_failed' });
  await supabaseAdmin.from('employees').update({ base_branch_id: parsed.data.defaultBranchId }).eq('institution_id', request.employee.institutionId).eq('id', request.params.employeeId);
  return response.json({ employeeId: request.params.employeeId, roleCodes: parsed.data.roleCodes, branchIds: parsed.data.branchIds, defaultBranchId: parsed.data.defaultBranchId });
});

const TASK_POSITION_CODES = ['owner', 'admin_followup', 'accountant', 'warehouse_keeper', 'warehouse_worker'] as const;
const TASK_POSITION_LABELS: Record<(typeof TASK_POSITION_CODES)[number], string> = {
  owner: 'صاحب المؤسسة',
  admin_followup: 'المدير التنفيذي',
  accountant: 'المحاسب',
  warehouse_keeper: 'أمين المخازن',
  warehouse_worker: 'عمال التحميل',
};
const taskPositionCodeSchema = z.enum(TASK_POSITION_CODES);

const taskStatusSchema = z.enum(['pending', 'in_progress', 'submitted', 'approved', 'rejected', 'cancelled']);
const taskCreateSchema = z.object({
  title: z.string().trim().min(2).max(200),
  description: z.string().trim().max(5000).optional().nullable(),
  assigneeEmployeeId: z.string().uuid(),
  positionCode: taskPositionCodeSchema,
  branchId: z.string().uuid().optional().nullable(),
  startsAt: z.string().datetime({ offset: true }),
  dueAt: z.string().datetime({ offset: true }),
  priority: z.enum(['low', 'normal', 'high', 'urgent']).default('normal'),
  proofRequired: z.boolean().default(false),
  proofInstructions: z.string().trim().max(1000).optional().nullable(),
  reportFields: z.array(z.object({ key: z.string().trim().regex(/^[a-zA-Z][a-zA-Z0-9_]{1,39}$/), label: z.string().trim().min(2).max(120), type: z.enum(['text', 'number', 'progress', 'status', 'notes']), required: z.boolean().default(false) })).min(1).max(20),
  idempotencyKey: z.string().trim().min(8).max(160).optional(),
});

function canSeeTask(request: AuthenticatedRequest, task: { assignee_employee_id: string; created_by: string }) {
  return Boolean(request.employee && (request.employee.permissions.includes('tasks.read_all') || task.assignee_employee_id === request.employee.id || task.created_by === request.employee.id));
}

app.get('/api/tasks', requireEmployee, requirePermission('tasks.read'), async (request: AuthenticatedRequest, response) => {
  if (!supabaseAdmin || !request.employee) return response.status(503).json({ error: 'auth_not_configured' });
  let query = supabaseAdmin.from('tasks').select('id,branch_id,created_by,assignee_employee_id,title,description,starts_at,due_at,priority,status,proof_required,proof_instructions,report_schema,position_code,recurring_template_id,created_at,updated_at').eq('institution_id', request.employee.institutionId).order('due_at', { ascending: true });
  if (!request.employee.permissions.includes('tasks.read_all')) query = query.or(`assignee_employee_id.eq.${request.employee.id},created_by.eq.${request.employee.id}`);
  const { data, error } = await query;
  if (error) return response.status(500).json({ error: 'tasks_lookup_failed' });
  return response.json({ tasks: data ?? [] });
});

app.post('/api/tasks', requireEmployee, requirePermission('tasks.manage'), async (request: AuthenticatedRequest, response) => {
  if (!supabaseAdmin || !request.employee) return response.status(503).json({ error: 'auth_not_configured' });
  const parsed = taskCreateSchema.safeParse(request.body);
  if (!parsed.success || new Date(parsed.data.dueAt) < new Date(parsed.data.startsAt)) return response.status(400).json({ error: 'invalid_task_payload' });
  const { data: assignee } = await supabaseAdmin.from('employees').select('id,status').eq('institution_id', request.employee.institutionId).eq('id', parsed.data.assigneeEmployeeId).maybeSingle();
  if (!assignee || assignee.status !== 'active') return response.status(400).json({ error: 'assignee_not_active' });
  if (parsed.data.branchId) {
    const { data: branch } = await supabaseAdmin.from('branches').select('id').eq('institution_id', request.employee.institutionId).eq('id', parsed.data.branchId).maybeSingle();
    if (!branch) return response.status(400).json({ error: 'branch_not_found' });
  }
  const payload = { institution_id: request.employee.institutionId, branch_id: parsed.data.branchId ?? null, position_code: parsed.data.positionCode, created_by: request.employee.id, assignee_employee_id: parsed.data.assigneeEmployeeId, title: parsed.data.title, description: parsed.data.description ?? null, starts_at: parsed.data.startsAt, due_at: parsed.data.dueAt, priority: parsed.data.priority, proof_required: parsed.data.proofRequired, proof_instructions: parsed.data.proofInstructions ?? null, report_schema: parsed.data.reportFields, idempotency_key: parsed.data.idempotencyKey ?? request.get('idempotency-key') ?? randomUUID() };
  const { data, error } = await supabaseAdmin.from('tasks').upsert(payload, { onConflict: 'institution_id,idempotency_key', ignoreDuplicates: true }).select('id,branch_id,position_code,created_by,assignee_employee_id,title,description,starts_at,due_at,priority,status,proof_required,proof_instructions,report_schema,recurring_template_id,created_at,updated_at').maybeSingle();
  if (error) return response.status(400).json({ error: 'task_create_failed', detail: error.code === '23505' ? 'task_idempotency_conflict' : undefined });
  if (data) return response.status(201).json({ task: data });
  const { data: existing } = await supabaseAdmin.from('tasks').select('id,branch_id,position_code,created_by,assignee_employee_id,title,description,starts_at,due_at,priority,status,proof_required,proof_instructions,report_schema,recurring_template_id,created_at,updated_at').eq('institution_id', request.employee.institutionId).eq('idempotency_key', payload.idempotency_key).maybeSingle();
  return response.status(200).json({ task: existing, idempotentReplay: true });
});

app.post('/api/tasks/:taskId/report', requireEmployee, requirePermission('tasks.read'), async (request: AuthenticatedRequest, response) => {
  if (!supabaseAdmin || !request.employee) return response.status(503).json({ error: 'auth_not_configured' });
  const parsed = z.object({ values: z.record(z.string(), z.unknown()) }).safeParse(request.body);
  if (!parsed.success) return response.status(400).json({ error: 'invalid_task_report_payload' });
  const { data: task } = await supabaseAdmin.from('tasks').select('id,assignee_employee_id,status,report_schema').eq('institution_id', request.employee.institutionId).eq('id', request.params.taskId).maybeSingle();
  if (!task || task.assignee_employee_id !== request.employee.id) return response.status(404).json({ error: 'task_not_found' });
  if (!['in_progress', 'rejected'].includes(task.status)) return response.status(400).json({ error: 'task_report_not_allowed' });
  const fields = Array.isArray(task.report_schema) ? task.report_schema as Array<{ key: string; required?: boolean }> : [];
  if (fields.some((field) => field.required && (parsed.data.values[field.key] === undefined || parsed.data.values[field.key] === null || parsed.data.values[field.key] === ''))) return response.status(400).json({ error: 'required_report_field_missing' });
  const { data: report, error } = await supabaseAdmin.from('task_reports').insert({ institution_id: request.employee.institutionId, task_id: task.id, submitted_by: request.employee.id, values: parsed.data.values }).select('id,task_id,submitted_by,values,created_at').single();
  if (error) return response.status(400).json({ error: 'task_report_create_failed' });
  const { error: updateError } = await supabaseAdmin.rpc('record_task_update', { p_task_id: task.id, p_author_employee_id: request.employee.id, p_status: 'submitted', p_note: 'تم رفع تقرير المهمة للمراجعة' });
  if (updateError) return response.status(400).json({ error: 'task_report_submit_failed', detail: ['task_must_be_in_progress', 'task_report_required'].find((code) => updateError.message.includes(code)) ?? 'transition_not_allowed' });
  return response.status(201).json({ report });
});

app.post('/api/tasks/:taskId/updates', requireEmployee, requirePermission('tasks.read'), async (request: AuthenticatedRequest, response) => {
  if (!supabaseAdmin || !request.employee) return response.status(503).json({ error: 'auth_not_configured' });
  const parsed = z.object({ status: z.enum(['pending', 'in_progress', 'submitted']), note: z.string().trim().max(3000).optional().nullable() }).safeParse(request.body);
  if (!parsed.success) return response.status(400).json({ error: 'invalid_task_update' });
  const { data: task } = await supabaseAdmin.from('tasks').select('id,assignee_employee_id,created_by').eq('institution_id', request.employee.institutionId).eq('id', request.params.taskId).maybeSingle();
  if (!task || !canSeeTask(request, task)) return response.status(404).json({ error: 'task_not_found' });
  const { data, error } = await supabaseAdmin.rpc('record_task_update', { p_task_id: request.params.taskId, p_author_employee_id: request.employee.id, p_status: parsed.data.status, p_note: parsed.data.note ?? null });
  if (error) return response.status(400).json({ error: 'task_update_failed', detail: ['task_proof_required', 'task_must_be_in_progress', 'invalid_progress_transition', 'task_actor_not_allowed'].find((code) => error.message.includes(code)) ?? 'transition_not_allowed' });
  return response.json({ taskId: data });
});

app.post('/api/tasks/:taskId/review', requireEmployee, requirePermission('tasks.review'), async (request: AuthenticatedRequest, response) => {
  if (!supabaseAdmin || !request.employee) return response.status(503).json({ error: 'auth_not_configured' });
  const parsed = z.object({ decision: z.enum(['approved', 'rejected']), note: z.string().trim().max(3000).optional().nullable() }).safeParse(request.body);
  if (!parsed.success) return response.status(400).json({ error: 'invalid_task_review' });
  const { data: task } = await supabaseAdmin.from('tasks').select('id,assignee_employee_id,created_by').eq('institution_id', request.employee.institutionId).eq('id', request.params.taskId).maybeSingle();
  if (!task || !canSeeTask(request, task)) return response.status(404).json({ error: 'task_not_found' });
  const { data, error } = await supabaseAdmin.rpc('review_task', { p_task_id: request.params.taskId, p_reviewer_employee_id: request.employee.id, p_decision: parsed.data.decision, p_note: parsed.data.note ?? null });
  if (error) return response.status(400).json({ error: 'task_review_failed', detail: ['task_must_be_submitted', 'task_reviewer_not_independent'].find((code) => error.message.includes(code)) ?? 'review_not_allowed' });
  return response.json({ taskId: data });
});

const recurrenceSchema = z.object({
  title: z.string().trim().min(2).max(200),
  description: z.string().trim().max(5000).optional().nullable(),
  assigneeEmployeeId: z.string().uuid(),
  positionCode: taskPositionCodeSchema,
  branchId: z.string().uuid().optional().nullable(),
  recurrence: z.enum(['daily', 'weekly', 'monthly']),
  weekDay: z.number().int().min(1).max(7).optional().nullable(),
  monthDay: z.number().int().min(1).max(31).optional().nullable(),
  startsOn: z.string().date(),
  endsOn: z.string().date().optional().nullable(),
});

app.post('/api/recurring-tasks', requireEmployee, requirePermission('tasks.manage'), async (request: AuthenticatedRequest, response) => {
  if (!supabaseAdmin || !request.employee) return response.status(503).json({ error: 'auth_not_configured' });
  const parsed = recurrenceSchema.safeParse(request.body);
  if (!parsed.success || (parsed.data.recurrence === 'weekly' && !parsed.data.weekDay) || (parsed.data.recurrence === 'monthly' && !parsed.data.monthDay)) return response.status(400).json({ error: 'invalid_recurrence_payload' });
  const { data: assignee } = await supabaseAdmin.from('employees').select('id,status').eq('institution_id', request.employee.institutionId).eq('id', parsed.data.assigneeEmployeeId).maybeSingle();
  if (!assignee || assignee.status !== 'active') return response.status(400).json({ error: 'assignee_not_active' });
  const { data, error } = await supabaseAdmin.from('recurring_task_templates').insert({ institution_id: request.employee.institutionId, branch_id: parsed.data.branchId ?? null, position_code: parsed.data.positionCode, created_by: request.employee.id, assignee_employee_id: parsed.data.assigneeEmployeeId, title: parsed.data.title, description: parsed.data.description ?? null, recurrence: parsed.data.recurrence, week_day: parsed.data.weekDay ?? null, month_day: parsed.data.monthDay ?? null, starts_on: parsed.data.startsOn, ends_on: parsed.data.endsOn ?? null }).select('id,title,position_code,recurrence,week_day,month_day,starts_on,ends_on,is_active,last_generated_for').single();
  if (error) return response.status(400).json({ error: 'recurrence_create_failed' });
  return response.status(201).json({ template: data });
});

app.post('/api/recurring-tasks/generate', requireEmployee, requirePermission('tasks.manage'), async (request: AuthenticatedRequest, response) => {
  if (!supabaseAdmin) return response.status(503).json({ error: 'auth_not_configured' });
  const parsed = z.object({ fromDate: z.string().date(), toDate: z.string().date() }).safeParse(request.body);
  if (!parsed.success) return response.status(400).json({ error: 'invalid_recurrence_window' });
  const from = new Date(`${parsed.data.fromDate}T00:00:00Z`);
  const to = new Date(`${parsed.data.toDate}T00:00:00Z`);
  if (to < from || (to.getTime() - from.getTime()) > 31 * 86400000) return response.status(400).json({ error: 'invalid_recurrence_window' });
  const { data, error } = await supabaseAdmin.rpc('generate_recurring_tasks', { p_from_date: parsed.data.fromDate, p_to_date: parsed.data.toDate });
  if (error) return response.status(400).json({ error: 'recurrence_generation_failed' });
  return response.json({ generated: data ?? 0 });
});

const reportFieldSchema = z.object({
  key: z.string().trim().regex(/^[a-zA-Z][a-zA-Z0-9_]{1,63}$/),
  labelAr: z.string().trim().min(2).max(160),
  fieldType: z.enum(['text', 'textarea', 'number', 'date', 'select', 'multiselect', 'checkbox', 'attachment']),
  required: z.boolean().default(false),
  sortOrder: z.number().int().min(0).default(0),
  options: z.array(z.string().trim().min(1).max(160)).max(100).default([]),
  config: z.record(z.string(), z.unknown()).default({}),
});

const reportFormSchema = z.object({
  code: z.string().trim().regex(/^[a-z0-9][a-z0-9_-]{1,63}$/),
  nameAr: z.string().trim().min(2).max(160),
  description: z.string().trim().max(2000).optional().nullable(),
  fields: z.array(reportFieldSchema).min(1).max(50),
});

const taskLibrarySchema = z.object({
  code: z.string().trim().regex(/^[a-z0-9][a-z0-9_-]{1,63}$/),
  title: z.string().trim().min(2).max(200),
  description: z.string().trim().max(5000).optional().nullable(),
  taskType: z.string().trim().min(2).max(100),
  positionCode: taskPositionCodeSchema,
  branchIds: z.array(z.string().uuid()).max(100).default([]),
  employeeIds: z.array(z.string().uuid()).max(100).default([]),
  recurrence: z.enum(['daily', 'weekly', 'monthly']).optional().nullable(),
  weekDay: z.number().int().min(1).max(7).optional().nullable(),
  monthDay: z.number().int().min(1).max(31).optional().nullable(),
  defaultDurationMinutes: z.number().int().min(1).max(10080).optional().nullable(),
  reportFormId: z.string().uuid().optional().nullable(),
});

const libraryConversionSchema = z.object({
  assigneeEmployeeId: z.string().uuid(),
  branchId: z.string().uuid().optional().nullable(),
  startsAt: z.string().datetime({ offset: true }),
  dueAt: z.string().datetime({ offset: true }),
  priority: z.enum(['low', 'normal', 'high', 'urgent']).default('normal'),
  idempotencyKey: z.string().trim().min(8).max(160).optional(),
});

app.get('/api/job-titles', requireEmployee, requirePermission('tasks.read'), async (request: AuthenticatedRequest, response) => {
  if (!supabaseAdmin || !request.employee) return response.status(503).json({ error: 'auth_not_configured' });
  const { data, error } = await supabaseAdmin.from('job_titles').select('id,code,name_ar,description,is_active').eq('institution_id', request.employee.institutionId).order('name_ar');
  if (error) return response.status(500).json({ error: 'job_titles_lookup_failed' });
  return response.json({ jobTitles: data ?? [] });
});

app.post('/api/job-titles', requireEmployee, requirePermission('task_library.manage'), async (request: AuthenticatedRequest, response) => {
  if (!supabaseAdmin || !request.employee) return response.status(503).json({ error: 'auth_not_configured' });
  const parsed = z.object({ code: z.string().trim().regex(/^[a-z0-9][a-z0-9_-]{1,63}$/), nameAr: z.string().trim().min(2).max(160), description: z.string().trim().max(1000).optional().nullable() }).safeParse(request.body);
  if (!parsed.success) return response.status(400).json({ error: 'invalid_job_title_payload' });
  const { data, error } = await supabaseAdmin.from('job_titles').insert({ institution_id: request.employee.institutionId, code: parsed.data.code, name_ar: parsed.data.nameAr, description: parsed.data.description ?? null }).select('id,code,name_ar,description,is_active').single();
  if (error) return response.status(400).json({ error: 'job_title_create_failed' });
  return response.status(201).json({ jobTitle: data });
});

app.get('/api/report-forms', requireEmployee, requirePermission('tasks.read'), async (request: AuthenticatedRequest, response) => {
  if (!supabaseAdmin || !request.employee) return response.status(503).json({ error: 'auth_not_configured' });
  const { data, error } = await supabaseAdmin.from('report_forms').select('id,code,name_ar,description,version,is_active,created_at,updated_at,report_form_fields(id,field_key,label_ar,field_type,is_required,sort_order,options,config)').eq('institution_id', request.employee.institutionId).eq('is_active', true).order('name_ar');
  if (error) return response.status(500).json({ error: 'report_forms_lookup_failed' });
  return response.json({ reportForms: data ?? [] });
});

app.post('/api/report-forms', requireEmployee, requirePermission('report_forms.manage'), async (request: AuthenticatedRequest, response) => {
  if (!supabaseAdmin || !request.employee) return response.status(503).json({ error: 'auth_not_configured' });
  const parsed = reportFormSchema.safeParse(request.body);
  if (!parsed.success) return response.status(400).json({ error: 'invalid_report_form_payload' });
  const { data: form, error: formError } = await supabaseAdmin.from('report_forms').insert({ institution_id: request.employee.institutionId, code: parsed.data.code, name_ar: parsed.data.nameAr, description: parsed.data.description ?? null, created_by: request.employee.id, updated_by: request.employee.id }).select('id,code,name_ar,description,version,is_active').single();
  if (formError || !form) return response.status(400).json({ error: 'report_form_create_failed' });
  const { error: fieldsError } = await supabaseAdmin.from('report_form_fields').insert(parsed.data.fields.map((field) => ({ institution_id: request.employee!.institutionId, form_id: form.id, field_key: field.key, label_ar: field.labelAr, field_type: field.fieldType, is_required: field.required, sort_order: field.sortOrder, options: field.options, config: field.config })));
  if (fieldsError) { await supabaseAdmin.from('report_forms').delete().eq('institution_id', request.employee.institutionId).eq('id', form.id); return response.status(400).json({ error: 'report_form_fields_create_failed' }); }
  return response.status(201).json({ reportForm: form });
});

app.get('/api/task-library', requireEmployee, requirePermission('task_library.read'), async (request: AuthenticatedRequest, response) => {
  if (!supabaseAdmin || !request.employee) return response.status(503).json({ error: 'auth_not_configured' });
  let query = supabaseAdmin.from('task_library_templates').select('id,code,title,description,task_type,position_code,recurrence,week_day,month_day,default_duration_minutes,report_form_id,version,is_active,created_at,updated_at,report_forms(id,code,name_ar,version)').eq('institution_id', request.employee.institutionId).order('title');
  if (request.query.taskType) query = query.eq('task_type', String(request.query.taskType));
  if (request.query.recurrence) query = query.eq('recurrence', String(request.query.recurrence));
  if (request.query.positionCode) query = query.eq('position_code', String(request.query.positionCode));
  const { data: templates, error } = await query;
  if (error) return response.status(500).json({ error: 'task_library_lookup_failed' });
  const ids = (templates ?? []).map((template) => template.id);
  const [{ data: branchLinks }, { data: employeeLinks }] = await Promise.all([
    ids.length ? supabaseAdmin.from('task_library_branches').select('template_id,branch_id,branches(id,code,name,branch_level,parent_branch_id)').eq('institution_id', request.employee.institutionId).in('template_id', ids) : Promise.resolve({ data: [] }),
    ids.length ? supabaseAdmin.from('task_library_employees').select('template_id,employee_id,employees(id,employee_no,full_name)').eq('institution_id', request.employee.institutionId).in('template_id', ids) : Promise.resolve({ data: [] }),
  ]);
  return response.json({ templates: (templates ?? []).map((template) => ({ ...template, branches: (branchLinks ?? []).filter((link) => link.template_id === template.id).map((link) => link.branches), employees: (employeeLinks ?? []).filter((link) => link.template_id === template.id).map((link) => link.employees) })) });
});

app.post('/api/task-library', requireEmployee, requirePermission('task_library.manage'), async (request: AuthenticatedRequest, response) => {
  if (!supabaseAdmin || !request.employee) return response.status(503).json({ error: 'auth_not_configured' });
  const parsed = taskLibrarySchema.safeParse(request.body);
  if (!parsed.success || (parsed.data.recurrence === 'weekly' && !parsed.data.weekDay) || (parsed.data.recurrence === 'monthly' && !parsed.data.monthDay)) return response.status(400).json({ error: 'invalid_task_library_payload' });
  if (!parsed.data.reportFormId) return response.status(400).json({ error: 'task_library_report_form_required' });
  const { data: template, error } = await supabaseAdmin.from('task_library_templates').insert({ institution_id: request.employee.institutionId, code: parsed.data.code, title: parsed.data.title, description: parsed.data.description ?? null, task_type: parsed.data.taskType, position_code: parsed.data.positionCode, recurrence: parsed.data.recurrence ?? null, week_day: parsed.data.weekDay ?? null, month_day: parsed.data.monthDay ?? null, default_duration_minutes: parsed.data.defaultDurationMinutes ?? null, report_form_id: parsed.data.reportFormId ?? null, created_by: request.employee.id, updated_by: request.employee.id }).select('id,code,title,position_code,version').single();
  if (error || !template) return response.status(400).json({ error: 'task_library_create_failed' });
  const branchRows = parsed.data.branchIds.map((branchId) => ({ institution_id: request.employee!.institutionId, template_id: template.id, branch_id: branchId }));
  const employeeRows = parsed.data.employeeIds.map((employeeId) => ({ institution_id: request.employee!.institutionId, template_id: template.id, employee_id: employeeId }));
  const [{ error: branchError }, { error: employeeError }] = await Promise.all([
    branchRows.length ? supabaseAdmin.from('task_library_branches').insert(branchRows) : Promise.resolve({ error: null }),
    employeeRows.length ? supabaseAdmin.from('task_library_employees').insert(employeeRows) : Promise.resolve({ error: null }),
  ]);
  if (branchError || employeeError) return response.status(400).json({ error: 'task_library_categories_create_failed' });
  return response.status(201).json({ template });
});

app.patch('/api/task-library/:templateId', requireEmployee, requirePermission('task_library.manage'), async (request: AuthenticatedRequest, response) => {
  if (!supabaseAdmin || !request.employee) return response.status(503).json({ error: 'auth_not_configured' });
  const parsed = taskLibrarySchema.partial().safeParse(request.body);
  if (!parsed.success) return response.status(400).json({ error: 'invalid_task_library_payload' });
  const updatePayload: Record<string, unknown> = { updated_by: request.employee.id };
  if (parsed.data.code !== undefined) updatePayload.code = parsed.data.code;
  if (parsed.data.title !== undefined) updatePayload.title = parsed.data.title;
  if (parsed.data.description !== undefined) updatePayload.description = parsed.data.description;
  if (parsed.data.taskType !== undefined) updatePayload.task_type = parsed.data.taskType;
  if (parsed.data.positionCode !== undefined) updatePayload.position_code = parsed.data.positionCode;
  if (parsed.data.recurrence !== undefined) updatePayload.recurrence = parsed.data.recurrence;
  if (parsed.data.weekDay !== undefined) updatePayload.week_day = parsed.data.weekDay;
  if (parsed.data.monthDay !== undefined) updatePayload.month_day = parsed.data.monthDay;
  if (parsed.data.defaultDurationMinutes !== undefined) updatePayload.default_duration_minutes = parsed.data.defaultDurationMinutes;
  if (parsed.data.reportFormId !== undefined) updatePayload.report_form_id = parsed.data.reportFormId;
  const { data: template, error } = await supabaseAdmin.from('task_library_templates').update(updatePayload).eq('institution_id', request.employee.institutionId).eq('id', request.params.templateId).select('id,code,title,version').maybeSingle();
  if (error || !template) return response.status(404).json({ error: 'task_library_not_found' });
  if (parsed.data.branchIds || parsed.data.employeeIds) {
    if (parsed.data.branchIds) { await supabaseAdmin.from('task_library_branches').delete().eq('institution_id', request.employee.institutionId).eq('template_id', template.id); if (parsed.data.branchIds.length) await supabaseAdmin.from('task_library_branches').insert(parsed.data.branchIds.map((branchId) => ({ institution_id: request.employee!.institutionId, template_id: template.id, branch_id: branchId }))); }
    if (parsed.data.employeeIds) { await supabaseAdmin.from('task_library_employees').delete().eq('institution_id', request.employee.institutionId).eq('template_id', template.id); if (parsed.data.employeeIds.length) await supabaseAdmin.from('task_library_employees').insert(parsed.data.employeeIds.map((employeeId) => ({ institution_id: request.employee!.institutionId, template_id: template.id, employee_id: employeeId }))); }
  }
  return response.json({ template });
});

app.post('/api/task-library/:templateId/convert', requireEmployee, requirePermission('task_library.convert'), async (request: AuthenticatedRequest, response) => {
  if (!supabaseAdmin || !request.employee) return response.status(503).json({ error: 'auth_not_configured' });
  const parsed = libraryConversionSchema.safeParse(request.body);
  if (!parsed.success || new Date(parsed.data.dueAt) < new Date(parsed.data.startsAt)) return response.status(400).json({ error: 'invalid_library_conversion_payload' });
  const { data: template } = await supabaseAdmin.from('task_library_templates').select('id,title,description,version,position_code,default_duration_minutes,report_form_id,report_forms(id,report_form_fields(field_key,label_ar,field_type,is_required,sort_order,options,config))').eq('institution_id', request.employee.institutionId).eq('id', request.params.templateId).eq('is_active', true).maybeSingle();
  if (!template) return response.status(404).json({ error: 'task_library_not_found' });
  if (!template.position_code) return response.status(409).json({ error: 'task_library_position_required' });
  const { data: assignee } = await supabaseAdmin.from('employees').select('id,status').eq('institution_id', request.employee.institutionId).eq('id', parsed.data.assigneeEmployeeId).maybeSingle();
  if (!assignee || assignee.status !== 'active') return response.status(400).json({ error: 'assignee_not_active' });
  if (parsed.data.branchId) { const { data: branch } = await supabaseAdmin.from('branches').select('id').eq('institution_id', request.employee.institutionId).eq('id', parsed.data.branchId).maybeSingle(); if (!branch) return response.status(400).json({ error: 'branch_not_found' }); }
  const form = Array.isArray(template.report_forms) ? template.report_forms[0] : template.report_forms;
  const fields = form && Array.isArray(form.report_form_fields) ? form.report_form_fields : [];
  if (!template.report_form_id || !fields.length) return response.status(409).json({ error: 'task_library_report_form_required' });
  const reportSchema = fields.sort((a, b) => a.sort_order - b.sort_order).map((field) => ({ key: field.field_key, label: field.label_ar, type: field.field_type, required: field.is_required, options: field.options, config: field.config }));
  const payload = { institution_id: request.employee.institutionId, branch_id: parsed.data.branchId ?? null, position_code: template.position_code, created_by: request.employee.id, assignee_employee_id: parsed.data.assigneeEmployeeId, title: template.title, description: template.description, starts_at: parsed.data.startsAt, due_at: parsed.data.dueAt, priority: parsed.data.priority, proof_required: reportSchema.some((field) => field.type === 'attachment' && field.required), proof_instructions: null, report_schema: reportSchema, library_template_id: template.id, library_template_version: template.version, idempotency_key: parsed.data.idempotencyKey ?? request.get('idempotency-key') ?? randomUUID() };
  const { data: task, error } = await supabaseAdmin.from('tasks').upsert(payload, { onConflict: 'institution_id,idempotency_key', ignoreDuplicates: true }).select('id,title,branch_id,assignee_employee_id,position_code,starts_at,due_at,priority,status,report_schema,library_template_id,library_template_version').maybeSingle();
  if (error) return response.status(400).json({ error: 'library_conversion_failed' });
  if (task) return response.status(201).json({ task });
  const { data: existing } = await supabaseAdmin.from('tasks').select('id,title,branch_id,assignee_employee_id,position_code,starts_at,due_at,priority,status,report_schema,library_template_id,library_template_version').eq('institution_id', request.employee.institutionId).eq('idempotency_key', payload.idempotency_key).maybeSingle();
  return response.status(200).json({ task: existing, idempotentReplay: true });
});

const customerSchema = z.object({ code: z.string().trim().min(1).max(40), name: z.string().trim().min(2).max(180), branchId: z.string().uuid(), phone: z.string().trim().max(40).optional().nullable(), address: z.string().trim().max(300).optional().nullable() });

app.get('/api/customers', requireEmployee, requirePermission('customers.read'), async (request: AuthenticatedRequest, response) => {
  if (!supabaseAdmin || !request.employee) return response.status(503).json({ error: 'auth_not_configured' });
  const { data: customers, error } = await supabaseAdmin.from('customers').select('id,branch_id,code,name,phone,address,is_active,created_at,updated_at').eq('institution_id', request.employee.institutionId).order('name');
  if (error) return response.status(500).json({ error: 'customers_lookup_failed' });
  const customerIds = (customers ?? []).map((customer) => customer.id);
  if (!customerIds.length) return response.json({ customers: [] });
  const [{ data: accounts }, { data: ledger }, { data: limits }] = await Promise.all([
    supabaseAdmin.from('accounts').select('id,customer_id').eq('institution_id', request.employee.institutionId).in('customer_id', customerIds),
    supabaseAdmin.from('account_ledger_entries').select('account_id,amount,entry_type').eq('institution_id', request.employee.institutionId),
    supabaseAdmin.from('credit_limits').select('customer_id,amount,valid_from,valid_to,approved_at').eq('institution_id', request.employee.institutionId).not('approved_by', 'is', null).lte('valid_from', new Date().toISOString().slice(0, 10)).order('valid_from', { ascending: false }),
  ]);
  const accountByCustomer = new Map((accounts ?? []).map((account) => [account.customer_id, account.id]));
  const balanceByAccount = new Map<string, number>();
  for (const entry of ledger ?? []) balanceByAccount.set(entry.account_id, (balanceByAccount.get(entry.account_id) ?? 0) + (entry.entry_type === 'debit' ? Number(entry.amount) : -Number(entry.amount)));
  const limitByCustomer = new Map<string, number>();
  for (const limit of limits ?? []) if (!limitByCustomer.has(limit.customer_id) && (!limit.valid_to || limit.valid_to >= new Date().toISOString().slice(0, 10))) limitByCustomer.set(limit.customer_id, Number(limit.amount));
  return response.json({ customers: (customers ?? []).map((customer) => ({ ...customer, accountId: accountByCustomer.get(customer.id) ?? null, balance: balanceByAccount.get(accountByCustomer.get(customer.id) ?? '') ?? 0, approvedCreditLimit: limitByCustomer.get(customer.id) ?? 0 })) });
});

app.post('/api/customers', requireEmployee, requirePermission('customers.manage'), async (request: AuthenticatedRequest, response) => {
  if (!supabaseAdmin || !request.employee) return response.status(503).json({ error: 'auth_not_configured' });
  const parsed = customerSchema.safeParse(request.body);
  if (!parsed.success) return response.status(400).json({ error: 'invalid_customer_payload' });
  const { data: branch } = await supabaseAdmin.from('branches').select('id').eq('institution_id', request.employee.institutionId).eq('id', parsed.data.branchId).maybeSingle();
  if (!branch) return response.status(400).json({ error: 'branch_not_found' });
  const { data: customerId, error } = await supabaseAdmin.rpc('create_customer_with_account', { p_institution_id: request.employee.institutionId, p_branch_id: parsed.data.branchId, p_code: parsed.data.code, p_name: parsed.data.name, p_phone: parsed.data.phone ?? null, p_address: parsed.data.address ?? null });
  if (error) return response.status(400).json({ error: 'customer_create_failed', detail: error.message.includes('customer_code_or_account_exists') ? 'customer_code_or_account_exists' : undefined });
  return response.status(201).json({ customerId });
});

app.patch('/api/customers/:customerId', requireEmployee, requirePermission('customers.manage'), async (request: AuthenticatedRequest, response) => {
  if (!supabaseAdmin || !request.employee) return response.status(503).json({ error: 'auth_not_configured' });
  const parsed = z.object({ name: z.string().trim().min(2).max(180).optional(), phone: z.string().trim().max(40).optional().nullable(), address: z.string().trim().max(300).optional().nullable(), isActive: z.boolean().optional() }).safeParse(request.body);
  if (!parsed.success || !Object.keys(parsed.data).length) return response.status(400).json({ error: 'invalid_customer_payload' });
  const update = { ...parsed.data, ...(parsed.data.isActive === undefined ? {} : { is_active: parsed.data.isActive }) } as Record<string, unknown>; delete update.isActive;
  const { data, error } = await supabaseAdmin.from('customers').update(update).eq('institution_id', request.employee.institutionId).eq('id', request.params.customerId).select('id,branch_id,code,name,phone,address,is_active,created_at,updated_at').maybeSingle();
  if (error) return response.status(400).json({ error: 'customer_update_failed' });
  if (!data) return response.status(404).json({ error: 'customer_not_found' });
  return response.json({ customer: data });
});

app.post('/api/credit-limits', requireEmployee, requirePermission('credit_limits.propose'), async (request: AuthenticatedRequest, response) => {
  if (!supabaseAdmin || !request.employee) return response.status(503).json({ error: 'auth_not_configured' });
  const parsed = z.object({ customerId: z.string().uuid(), amount: z.number().nonnegative(), validFrom: z.string().date(), validTo: z.string().date().optional().nullable(), reason: z.string().trim().min(3).max(500) }).safeParse(request.body);
  if (!parsed.success) return response.status(400).json({ error: 'invalid_credit_limit_payload' });
  const { data: customer } = await supabaseAdmin.from('customers').select('id').eq('institution_id', request.employee.institutionId).eq('id', parsed.data.customerId).maybeSingle();
  if (!customer) return response.status(404).json({ error: 'customer_not_found' });
  const { data, error } = await supabaseAdmin.from('credit_limits').insert({ institution_id: request.employee.institutionId, customer_id: parsed.data.customerId, amount: parsed.data.amount, valid_from: parsed.data.validFrom, valid_to: parsed.data.validTo ?? null, proposed_by: request.employee.id, reason: parsed.data.reason }).select('id,customer_id,amount,valid_from,valid_to,approved_by,approved_at,reason,created_at').single();
  if (error) return response.status(400).json({ error: 'credit_limit_proposal_failed' });
  return response.status(201).json({ creditLimit: data });
});

app.post('/api/credit-limits/:creditLimitId/approve', requireEmployee, requirePermission('credit_limits.approve'), async (request: AuthenticatedRequest, response) => {
  if (!supabaseAdmin || !request.employee) return response.status(503).json({ error: 'auth_not_configured' });
  const { data, error } = await supabaseAdmin.rpc('approve_credit_limit', { p_credit_limit_id: request.params.creditLimitId, p_approver_employee_id: request.employee.id });
  if (error) return response.status(400).json({ error: 'credit_limit_approval_failed', detail: ['credit_limit_not_found', 'credit_limit_already_approved', 'credit_limit_approver_not_independent'].find((code) => error.message.includes(code)) ?? 'approval_not_allowed' });
  return response.json({ creditLimitId: data });
});

app.get('/api/receipts', requireEmployee, requirePermission('finance.read'), async (request: AuthenticatedRequest, response) => {
  if (!supabaseAdmin || !request.employee) return response.status(503).json({ error: 'auth_not_configured' });
  const { data, error } = await supabaseAdmin.from('receipts').select('id,branch_id,customer_id,account_id,amount,receipt_no,status,created_by,approved_by,approved_at,created_at').eq('institution_id', request.employee.institutionId).order('created_at', { ascending: false });
  if (error) return response.status(500).json({ error: 'receipts_lookup_failed' });
  return response.json({ receipts: data ?? [] });
});

app.post('/api/receipts', requireEmployee, requirePermission('finance.receipts.create'), async (request: AuthenticatedRequest, response) => {
  if (!supabaseAdmin || !request.employee) return response.status(503).json({ error: 'auth_not_configured' });
  const parsed = z.object({ receiptNo: z.string().trim().min(1).max(40), branchId: z.string().uuid(), customerId: z.string().uuid(), amount: z.number().positive(), idempotencyKey: z.string().trim().min(8).max(160).optional() }).safeParse(request.body);
  if (!parsed.success) return response.status(400).json({ error: 'invalid_receipt_payload' });
  const [{ data: customer }, { data: account }, { data: branch }] = await Promise.all([
    supabaseAdmin.from('customers').select('id').eq('institution_id', request.employee.institutionId).eq('id', parsed.data.customerId).maybeSingle(),
    supabaseAdmin.from('accounts').select('id').eq('institution_id', request.employee.institutionId).eq('customer_id', parsed.data.customerId).maybeSingle(),
    supabaseAdmin.from('branches').select('id').eq('institution_id', request.employee.institutionId).eq('id', parsed.data.branchId).maybeSingle(),
  ]);
  if (!customer || !account || !branch) return response.status(400).json({ error: 'receipt_reference_not_found' });
  const { data, error } = await supabaseAdmin.from('receipts').upsert({ institution_id: request.employee.institutionId, branch_id: parsed.data.branchId, customer_id: parsed.data.customerId, account_id: account.id, amount: parsed.data.amount, receipt_no: parsed.data.receiptNo, status: 'submitted', created_by: request.employee.id, idempotency_key: parsed.data.idempotencyKey ?? request.get('idempotency-key') ?? randomUUID() }, { onConflict: 'institution_id,idempotency_key', ignoreDuplicates: true }).select('id,receipt_no,amount,status,customer_id,account_id,created_at').maybeSingle();
  if (error) return response.status(400).json({ error: 'receipt_create_failed' });
  return response.status(data ? 201 : 200).json({ receipt: data, idempotentReplay: !data });
});

app.post('/api/receipts/:receiptId/approve', requireEmployee, requirePermission('finance.receipts.approve'), async (request: AuthenticatedRequest, response) => {
  if (!supabaseAdmin || !request.employee) return response.status(503).json({ error: 'auth_not_configured' });
  const { data, error } = await supabaseAdmin.rpc('approve_receipt', { p_receipt_id: request.params.receiptId, p_approver_employee_id: request.employee.id });
  if (error) return response.status(400).json({ error: 'receipt_approval_failed', detail: ['receipt_not_found', 'receipt_must_be_submitted', 'receipt_approver_not_independent'].find((code) => error.message.includes(code)) ?? 'approval_not_allowed' });
  return response.json({ receiptId: data });
});

app.get('/api/reports/oversight', requireEmployee, requireAnyPermission('reports.read_all', 'tasks.read_all'), async (request: AuthenticatedRequest, response) => {
  if (!supabaseAdmin || !request.employee) return response.status(503).json({ error: 'auth_not_configured' });
  const [tasksResult, reportsResult, reviewsResult] = await Promise.all([
    supabaseAdmin.from('tasks').select('id,title,status,due_at,assignee_employee_id,branch_id,position_code,created_at').eq('institution_id', request.employee.institutionId).order('due_at', { ascending: true }),
    supabaseAdmin.from('task_reports').select('id,task_id,submitted_by,values,branch_id,execution_date,created_at').eq('institution_id', request.employee.institutionId).order('created_at', { ascending: false }).limit(100),
    supabaseAdmin.from('task_reviews').select('id,task_id,reviewer_employee_id,decision,note,created_at').eq('institution_id', request.employee.institutionId).order('created_at', { ascending: false }).limit(100),
  ]);
  if (tasksResult.error || reportsResult.error || reviewsResult.error) return response.status(500).json({ error: 'oversight_lookup_failed' });
  const tasks = tasksResult.data ?? [];
  const employeeIds = [...new Set([...tasks.map((task) => task.assignee_employee_id), ...(reportsResult.data ?? []).map((report) => report.submitted_by), ...(reviewsResult.data ?? []).map((review) => review.reviewer_employee_id)])];
  const branchIds = [...new Set(tasks.map((task) => task.branch_id).filter(Boolean) as string[])];
  const [{ data: employees }, { data: branches }] = await Promise.all([
    employeeIds.length ? supabaseAdmin.from('employees').select('id,full_name,employee_no').eq('institution_id', request.employee.institutionId).in('id', employeeIds) : Promise.resolve({ data: [] }),
    branchIds.length ? supabaseAdmin.from('branches').select('id,name,branch_level,parent_branch_id').eq('institution_id', request.employee.institutionId).in('id', branchIds) : Promise.resolve({ data: [] }),
  ]);
  const employeeName = new Map((employees ?? []).map((employee) => [employee.id, employee.full_name]));
  const branchName = new Map((branches ?? []).map((branch) => [branch.id, branch.name]));
  const now = Date.now();
  const taskStatuses = tasks.reduce<Record<string, number>>((result, task) => { result[task.status] = (result[task.status] ?? 0) + 1; return result; }, {});
  const positionLabel = (code: string | null) => code && code in TASK_POSITION_LABELS ? TASK_POSITION_LABELS[code as keyof typeof TASK_POSITION_LABELS] : null;
  const withPositionLabel = <T extends { position_code: string | null }>(row: T) => ({ ...row, position_label_ar: positionLabel(row.position_code) });
  const overdueTasks = tasks.filter((task) => !['approved', 'cancelled'].includes(task.status) && new Date(task.due_at).getTime() < now).map((task) => ({ ...withPositionLabel(task), assignee_name: employeeName.get(task.assignee_employee_id) ?? 'موظف', branch_name: task.branch_id ? branchName.get(task.branch_id) ?? 'فرع' : 'كل الفروع' }));
  const pendingReports = tasks.filter((task) => task.status === 'submitted').map((task) => ({ ...withPositionLabel(task), assignee_name: employeeName.get(task.assignee_employee_id) ?? 'موظف', branch_name: task.branch_id ? branchName.get(task.branch_id) ?? 'فرع' : 'كل الفروع' }));
  const taskById = new Map(tasks.map((task) => [task.id, task]));
  const reports = (reportsResult.data ?? []).map((report) => { const task = taskById.get(report.task_id); return { ...report, task_title: task?.title ?? 'مهمة', position_code: task?.position_code ?? null, position_label_ar: positionLabel(task?.position_code ?? null), submitted_by_name: employeeName.get(report.submitted_by) ?? 'موظف' }; });
  const positionCounts = Object.fromEntries(TASK_POSITION_CODES.map((code) => [code, tasks.filter((task) => task.position_code === code).length]));
  const reviews = (reviewsResult.data ?? []).map((review) => ({ ...review, reviewer_name: employeeName.get(review.reviewer_employee_id) ?? 'مراجع' }));
  return response.json({ taskStatuses, positionCounts, unclassifiedTaskCount: tasks.filter((task) => !task.position_code).length, overdueTasks, pendingReports, reports, reviews, totals: { tasks: tasks.length, reports: reports.length, approved: tasks.filter((task) => task.status === 'approved').length, overdue: overdueTasks.length, pending: pendingReports.length } });
});

app.get('/api/reports/summary', requireEmployee, requirePermission('finance.read'), async (request: AuthenticatedRequest, response) => {
  if (!supabaseAdmin || !request.employee) return response.status(503).json({ error: 'auth_not_configured' });
  const [receipts, tasks] = await Promise.all([
    supabaseAdmin.from('receipts').select('amount,status').eq('institution_id', request.employee.institutionId),
    supabaseAdmin.from('tasks').select('status').eq('institution_id', request.employee.institutionId),
  ]);
  const sumApproved = (rows: Array<{ amount?: number; status: string }> | null) => (rows ?? []).filter((row) => row.status === 'approved').reduce((sum, row) => sum + Number(row.amount ?? 0), 0);
  const countByStatus = (rows: Array<{ status: string }> | null) => (rows ?? []).reduce<Record<string, number>>((result, row) => { result[row.status] = (result[row.status] ?? 0) + 1; return result; }, {});
  return response.json({ receiptsApproved: sumApproved(receipts.data), taskStatuses: countByStatus(tasks.data) });
});

app.get('/api/notifications', requireEmployee, async (request: AuthenticatedRequest, response) => {
  if (!supabaseAdmin || !request.employee) return response.status(503).json({ error: 'auth_not_configured' });
  const { data, error } = await supabaseAdmin.from('notifications').select('id,title,body,severity,read_at,created_at').eq('institution_id', request.employee.institutionId).or(`employee_id.eq.${request.employee.id},employee_id.is.null`).order('created_at', { ascending: false }).limit(50);
  if (error) return response.status(500).json({ error: 'notifications_lookup_failed' });
  return response.json({ notifications: data ?? [] });
});

app.patch('/api/notifications/:notificationId/read', requireEmployee, async (request: AuthenticatedRequest, response) => {
  if (!supabaseAdmin || !request.employee) return response.status(503).json({ error: 'auth_not_configured' });
  const { data, error } = await supabaseAdmin.from('notifications').update({ read_at: new Date().toISOString() }).eq('institution_id', request.employee.institutionId).eq('employee_id', request.employee.id).eq('id', request.params.notificationId).select('id,read_at').maybeSingle();
  if (error) return response.status(400).json({ error: 'notification_update_failed' });
  if (!data) return response.status(404).json({ error: 'notification_not_found' });
  return response.json({ notification: data });
});

app.get('/api/audit-logs', requireEmployee, requirePermission('audit.read'), async (request: AuthenticatedRequest, response) => {
  if (!supabaseAdmin || !request.employee) return response.status(503).json({ error: 'auth_not_configured' });
  const { data, error } = await supabaseAdmin.from('audit_logs').select('id,actor_employee_id,action,entity_type,entity_id,before_data,after_data,request_id,created_at').eq('institution_id', request.employee.institutionId).order('created_at', { ascending: false }).limit(100);
  if (error) return response.status(500).json({ error: 'audit_lookup_failed' });
  return response.json({ logs: data ?? [] });
});

if (existsSync(webDist)) {
  app.use(express.static(webDist, { index: 'index.html' }));
  app.get('*', (request, response, next) => {
    if (request.path.startsWith('/api/')) return next();
    response.sendFile(path.join(webDist, 'index.html'));
  });
}

app.listen(port, '0.0.0.0', () => {
  console.log(`alshaeri-api listening on ${port}`);
});
