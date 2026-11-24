import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Cache-Control': 'no-store',
};
const RATE_WINDOW_MS = 15 * 60 * 1000;
const MAX_EMPLOYEE_FAILURES = 8;
const MAX_IP_FAILURES = 40;
const OWNER_EMAIL = 'als43870@gmail.com';
type AdminClient = SupabaseClient<any, 'public', 'public', any, any>;
type FunctionClients = {
  url: string;
  publishableKey: string;
  adminClient: AdminClient;
  secretKey: string;
};

type EmployeeProfile = {
  id: string;
  institutionId: string;
  employeeNo: string | null;
  fullName: string;
  status: string;
  roles: Array<{ code: string }>;
  permissions: string[];
};
type OwnerVerification =
  | { authorized: true; profile: EmployeeProfile }
  | { authorized: false; error: Response };

function response(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function defaultNamedKey(envName: string, legacyNames: string[]) {
  const source = Deno.env.get(envName);
  if (source) {
    try {
      const parsed = JSON.parse(source) as Record<string, unknown>;
      if (typeof parsed.default === 'string') return parsed.default;
    } catch {
      if (!source.trim().startsWith('{')) return source;
    }
  }
  for (const name of legacyNames) {
    const value = Deno.env.get(name);
    if (value) return value;
  }
  return null;
}

function getClients(): FunctionClients {
  const url = Deno.env.get('SUPABASE_URL');
  const publishableKey = defaultNamedKey('SUPABASE_PUBLISHABLE_KEYS', [
    'SUPABASE_PUBLISHABLE_KEY',
    'SUPABASE_ANON_KEY',
  ]);
  const secretKey = defaultNamedKey('SUPABASE_SECRET_KEYS', [
    'SUPABASE_SECRET_KEY',
    'SUPABASE_SERVICE_ROLE_KEY',
  ]);
  if (!url || !publishableKey || !secretKey) throw new Error('supabase_function_environment_missing');

  const adminClient = createClient(url, secretKey, {
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
  });
  return { url, publishableKey, adminClient, secretKey };
}

async function sha256Hex(value: string) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

async function hmacHex(secret: string, value: string) {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(value));
  return [...new Uint8Array(signature)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function clientIp(request: Request) {
  const direct = request.headers.get('cf-connecting-ip')?.trim();
  if (direct) return direct;
  const forwarded = request.headers.get('x-forwarded-for')?.split(',')[0]?.trim();
  return forwarded || 'unknown';
}

function isAccessCode(value: unknown): value is string {
  return typeof value === 'string' && /^\S{3,30}$/.test(value);
}

function randomReplacementPassword() {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return [...bytes].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function randomAccessCode() {
  const bytes = crypto.getRandomValues(new Uint8Array(8));
  return [...bytes].map((byte) => String(byte % 10)).join('');
}

async function findAuthUserByEmail(admin: AdminClient, email: string) {
  const { data, error } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
  if (error) return { user: null, error };
  return {
    user: data.users.find((user) => user.email?.toLowerCase() === email.toLowerCase()) ?? null,
    error: null,
  };
}

function toBase64(bytes: Uint8Array) {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function fromBase64(value: string) {
  return Uint8Array.from(atob(value), (character) => character.charCodeAt(0));
}

async function deriveAccessCodeHash(code: string, salt: Uint8Array) {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(code), 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt: salt.buffer as ArrayBuffer, iterations: 310_000 }, key, 256);
  return new Uint8Array(bits);
}

function constantTimeEqual(left: Uint8Array, right: Uint8Array) {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) difference |= left[index] ^ right[index];
  return difference === 0;
}

async function setEmployeeAccessCode(admin: AdminClient, membershipId: string, userId: string, code: string) {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const codeHash = await deriveAccessCodeHash(code, salt);
  const bridgePassword = randomReplacementPassword();
  const { error: authError } = await admin.auth.admin.updateUserById(userId, { password: bridgePassword });
  if (authError) return { error: 'auth_update_failed' } as const;
  const { error: credentialError } = await admin.from('employee_access_credentials').upsert({
    membership_id: membershipId,
    code_salt: toBase64(salt),
    code_hash: toBase64(codeHash),
    auth_bridge_password: bridgePassword,
    updated_at: new Date().toISOString(),
  });
  if (credentialError) return { error: 'credential_store_failed' } as const;
  return { error: null } as const;
}

async function removeEmployeeAccessCode(admin: AdminClient, membershipId: string, userId: string) {
  const { error: authError } = await admin.auth.admin.updateUserById(userId, { password: randomReplacementPassword() });
  if (authError) return { error: 'auth_update_failed' } as const;
  const { error: credentialError } = await admin.from('employee_access_credentials').delete().eq('membership_id', membershipId);
  if (credentialError) return { error: 'credential_store_failed' } as const;
  return { error: null } as const;
}

async function countRecentFailures(admin: AdminClient, employeeHash: string, ipHash: string) {
  const cutoff = new Date(Date.now() - RATE_WINDOW_MS).toISOString();
  const [employeeResult, ipResult] = await Promise.all([
    admin.from('employee_access_code_login_attempts')
      .select('id', { count: 'exact', head: true })
      .eq('employee_key_hash', employeeHash)
      .gte('attempted_at', cutoff),
    admin.from('employee_access_code_login_attempts')
      .select('id', { count: 'exact', head: true })
      .eq('ip_key_hash', ipHash)
      .gte('attempted_at', cutoff),
  ]);
  if (employeeResult.error || ipResult.error) throw new Error('login_rate_limit_lookup_failed');
  return {
    employeeLimited: (employeeResult.count ?? 0) >= MAX_EMPLOYEE_FAILURES,
    ipLimited: (ipResult.count ?? 0) >= MAX_IP_FAILURES,
  };
}

async function recordFailure(admin: AdminClient, employeeHash: string, ipHash: string) {
  const { error } = await admin.from('employee_access_code_login_attempts').insert({
    employee_key_hash: employeeHash,
    ip_key_hash: ipHash,
  });
  if (error) throw new Error('login_rate_limit_write_failed');
  await admin.from('employee_access_code_login_attempts')
    .delete()
    .lt('attempted_at', new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString());
}

async function verifyOwner(request: Request, clients: FunctionClients): Promise<OwnerVerification> {
  const authorization = request.headers.get('Authorization') ?? '';
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  if (!match) return { authorized: false, error: response({ error: 'not_authenticated' }, 401) };

  const userClient = createClient(clients.url, clients.publishableKey, {
    global: { headers: { Authorization: `Bearer ${match[1]}` } },
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
  });
  const { data: authData, error: authError } = await userClient.auth.getUser(match[1]);
  if (authError || !authData.user) return { authorized: false, error: response({ error: 'not_authenticated' }, 401) };

  const { data, error } = await userClient.rpc('mobile_my_profile');
  if (error) {
    console.error('employee_code_owner_profile_lookup_failed');
    return { authorized: false, error: response({ error: 'mobile_profile_unavailable' }, 503) };
  }
  const profile = (data as { employee?: EmployeeProfile } | null)?.employee;
  const ownerRole = profile?.roles?.some((role) => role.code === 'owner') ?? false;
  const executiveRole = profile?.roles?.some((role) => role.code === 'admin_followup') ?? false;
  const canManageEmployees = profile?.permissions?.includes('employees.manage') ?? false;
  if (!profile || (!ownerRole && !executiveRole) || !canManageEmployees) {
    return { authorized: false, error: response({ error: 'employee_access_management_permission_required' }, 403) };
  }
  return { authorized: true, profile };
}

function isOwnerProfile(profile: EmployeeProfile) {
  return profile.roles.some((role) => role.code === 'owner');
}

async function targetIsOwner(admin: AdminClient, organizationId: string, membershipId: string) {
  const { data } = await admin.from('role_assignments')
    .select('id')
    .eq('organization_id', organizationId)
    .eq('membership_id', membershipId)
    .eq('role_code', 'owner')
    .limit(1);
  return Boolean(data?.length);
}

async function writeAudit(admin: AdminClient, organizationId: string, membershipId: string | null, actorId: string, action: string, metadata: Record<string, unknown> = {}) {
  const { error } = await admin.from('employee_access_audit_log').insert({
    organization_id: organizationId,
    membership_id: membershipId,
    actor_membership_id: actorId,
    action,
    metadata,
  });
  return error;
}

async function login(body: Record<string, unknown>, request: Request, clients: FunctionClients) {
  const employeeNo = typeof body.employeeNo === 'string' ? body.employeeNo.trim() : '';
  const code = body.code;
  if (!employeeNo || employeeNo.length > 32 || !isAccessCode(code)) {
    return response({ error: 'invalid_credentials' }, 401);
  }

  const [employeeHash, ipHash] = await Promise.all([
    hmacHex(clients.secretKey, `employee:${employeeNo}`),
    hmacHex(clients.secretKey, `ip:${clientIp(request)}`),
  ]);
  const limits = await countRecentFailures(clients.adminClient, employeeHash, ipHash);
  if (limits.employeeLimited || limits.ipLimited) {
    return response({ error: 'too_many_attempts' }, 429);
  }

  const { data: matches, error: membershipError } = await clients.adminClient
    .from('organization_memberships')
    .select('id,organization_id,user_id,is_active,employee_no,access_code_set_at')
    .eq('employee_no', employeeNo)
    .limit(2);
  if (membershipError) {
    console.error('employee_code_login_membership_lookup_failed');
    return response({ error: 'database_update_required' }, 503);
  }
  const membership = matches?.length === 1 ? matches[0] : null;
  if (!membership || !membership.is_active || !membership.access_code_set_at) {
    await recordFailure(clients.adminClient, employeeHash, ipHash);
    return response({ error: 'invalid_credentials' }, 401);
  }

  const { data: credential, error: credentialError } = await clients.adminClient
    .from('employee_access_credentials')
    .select('code_salt,code_hash,auth_bridge_password')
    .eq('membership_id', membership.id)
    .maybeSingle();
  if (credentialError) {
    console.error('employee_code_login_credential_lookup_failed');
    return response({ error: 'database_update_required' }, 503);
  }
  let codeMatches = false;
  if (credential) {
    try {
      const [derived, stored] = await Promise.all([
        deriveAccessCodeHash(code, fromBase64(credential.code_salt)),
        Promise.resolve(fromBase64(credential.code_hash)),
      ]);
      codeMatches = constantTimeEqual(derived, stored);
    } catch {
      codeMatches = false;
    }
  }
  if (!credential || !codeMatches) {
    await recordFailure(clients.adminClient, employeeHash, ipHash);
    return response({ error: 'invalid_credentials' }, 401);
  }

  const { data: authData, error: authLookupError } = await clients.adminClient.auth.admin.getUserById(membership.user_id);
  const authUser = authData?.user;
  if (authLookupError || !authUser || (!authUser.email && !authUser.phone)) {
    console.error('employee_code_login_auth_user_lookup_failed');
    await recordFailure(clients.adminClient, employeeHash, ipHash);
    return response({ error: 'invalid_credentials' }, 401);
  }

  const authClient = createClient(clients.url, clients.publishableKey, {
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
  });
  const credentials = authUser.email
    ? { email: authUser.email, password: credential.auth_bridge_password }
    : { phone: authUser.phone!, password: credential.auth_bridge_password };
  const { data: sessionData, error: signInError } = await authClient.auth.signInWithPassword(credentials);
  if (signInError || !sessionData.session) {
    await recordFailure(clients.adminClient, employeeHash, ipHash);
    return response({ error: 'invalid_credentials' }, 401);
  }

  await clients.adminClient.from('employee_access_code_login_attempts')
    .delete()
    .eq('employee_key_hash', employeeHash);
  return response({
    access_token: sessionData.session.access_token,
    refresh_token: sessionData.session.refresh_token,
  });
}

async function bootstrapOwner(body: Record<string, unknown>, clients: FunctionClients) {
  const token = typeof body.bootstrapToken === 'string' ? body.bootstrapToken : '';
  const code = body.code;
  if (token.length < 32 || !isAccessCode(code)) return response({ error: 'invalid_bootstrap_request' }, 400);

  const tokenHash = await sha256Hex(token);
  const { data: claimed, error: claimError } = await clients.adminClient
    .rpc('claim_employee_access_code_bootstrap', { p_token_hash: tokenHash });
  if (claimError || claimed !== true) return response({ error: 'bootstrap_token_invalid_or_expired' }, 401);

  const { data: members, error: memberError } = await clients.adminClient
    .from('organization_memberships')
    .select('id,organization_id,user_id,is_active,employee_no')
    .eq('employee_no', '1')
    .eq('is_active', true)
    .limit(2);
  if (memberError || members?.length !== 1) {
    console.error('employee_code_bootstrap_owner_membership_lookup_failed');
    return response({ error: 'owner_membership_not_unique' }, 409);
  }
  const membership = members[0];

  const { data: ownerRole, error: roleError } = await clients.adminClient
    .from('role_assignments')
    .select('id')
    .eq('organization_id', membership.organization_id)
    .eq('membership_id', membership.id)
    .eq('role_code', 'owner')
    .limit(1);
  if (roleError || !ownerRole?.length) return response({ error: 'owner_permission_required' }, 403);

  const { data: authData, error: authError } = await clients.adminClient.auth.admin.getUserById(membership.user_id);
  if (authError || authData.user?.email?.toLowerCase() !== OWNER_EMAIL) {
    console.error('employee_code_bootstrap_designated_owner_check_failed');
    return response({ error: 'designated_owner_check_failed' }, 403);
  }

  const credentialUpdate = await setEmployeeAccessCode(clients.adminClient, membership.id, membership.user_id, code as string);
  if (credentialUpdate.error) {
    console.error('employee_code_bootstrap_credential_update_failed', credentialUpdate.error);
    return response({ error: 'owner_code_update_failed' }, 500);
  }
  const { error: metadataError } = await clients.adminClient
    .from('organization_memberships')
    .update({ access_code_set_at: new Date().toISOString(), access_code_updated_by: membership.id })
    .eq('id', membership.id)
    .eq('organization_id', membership.organization_id);
  if (metadataError) {
    console.error('employee_code_bootstrap_metadata_update_failed_after_auth_update');
    return response({ error: 'owner_code_status_update_failed' }, 500);
  }
  return response({ ok: true, employeeNo: '1' });
}

async function ownerOperation(body: Record<string, unknown>, request: Request, clients: FunctionClients): Promise<Response> {
  const authorized = await verifyOwner(request, clients);
  if (!authorized.authorized) return authorized.error;
  const owner = authorized.profile;

  if (body.action === 'list') {
    const { data, error } = await clients.adminClient
      .from('organization_memberships')
      .select('id,employee_no,display_name,is_active,user_id,access_code_set_at')
      .eq('organization_id', owner.institutionId)
      .order('employee_no', { ascending: true })
      .limit(500);
    if (error) {
      console.error('employee_code_owner_list_failed');
      return response({ error: 'database_update_required' }, 503);
    }
    const memberIds = (data ?? []).map((member) => member.id);
    const [{ data: assignments, error: assignmentError }, { data: branches, error: branchError }] = await Promise.all([
      clients.adminClient.from('role_assignments').select('membership_id,role_code,branch_id').eq('organization_id', owner.institutionId).in('membership_id', memberIds),
      clients.adminClient.from('branches').select('id,name,code,is_active').eq('organization_id', owner.institutionId).order('name'),
    ]);
    if (assignmentError || branchError) return response({ error: 'employee_access_lookup_failed' }, 503);
    const branchById = new Map((branches ?? []).map((branch) => [branch.id, branch]));
    const assignmentByMember = new Map((assignments ?? []).map((assignment) => [assignment.membership_id, assignment]));
    return response({
      employees: (data ?? []).map((member) => {
        const assignment = assignmentByMember.get(member.id);
        const branch = assignment?.branch_id ? branchById.get(assignment.branch_id) : null;
        return {
          id: member.id,
          employeeNo: member.employee_no,
          fullName: member.display_name,
          status: member.is_active ? 'active' : 'inactive',
          hasAuthAccount: Boolean(member.user_id),
          codeSetAt: member.access_code_set_at,
          roleCode: assignment?.role_code ?? null,
          branchId: assignment?.branch_id ?? null,
          branchName: branch?.name ?? null,
        };
      }),
      branches: branches ?? [],
    });
  }

  if (body.action === 'manage_branch') {
    const branchAction = typeof body.branchAction === 'string' ? body.branchAction : '';
    const branchId = typeof body.branchId === 'string' ? body.branchId : null;
    const code = typeof body.code === 'string' ? body.code.trim().toUpperCase() : null;
    const name = typeof body.name === 'string' ? body.name.trim() : null;
    if (!['create','update','archive','activate'].includes(branchAction)) return response({ error: 'invalid_branch_action' }, 400);
    if (branchAction === 'create' && (!code || !/^[A-Z0-9_-]{2,24}$/.test(code))) return response({ error: 'invalid_branch_code' }, 400);
    const { data, error } = await clients.adminClient.rpc('admin_manage_branch', {
      p_organization_id: owner.institutionId,
      p_actor_membership_id: owner.id,
      p_action: branchAction,
      p_branch_id: branchId,
      p_code: code,
      p_name: name,
    });
    if (error) {
      if (error.message?.includes('duplicate key')) return response({ error: 'branch_code_exists' }, 409);
      if (error.message?.includes('permission_required')) return response({ error: 'branch_management_permission_required' }, 403);
      return response({ error: 'branch_operation_failed' }, 400);
    }
    return response({ ok: true, result: data });
  }

  const employeeId = typeof body.employeeId === 'string' ? body.employeeId : '';
  if (!/^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(employeeId)) {
    return response({ error: 'invalid_employee' }, 400);
  }
  const { data: target, error: targetError } = await clients.adminClient
    .from('organization_memberships')
    .select('id,user_id,is_active')
    .eq('organization_id', owner.institutionId)
    .eq('id', employeeId)
    .maybeSingle();
  if (targetError) {
    console.error('employee_code_target_lookup_failed');
    return response({ error: 'database_update_required' }, 503);
  }
  if (!target || !target.user_id) return response({ error: 'employee_auth_not_linked' }, 404);
  const targetOwner = await targetIsOwner(clients.adminClient, owner.institutionId, employeeId);
  if (targetOwner && !isOwnerProfile(owner)) return response({ error: 'owner_account_protected' }, 403);
  if (!target.is_active && !['update_employee', 'audit'].includes(String(body.action))) return response({ error: 'employee_not_active' }, 400);

  if (body.action === 'audit') {
    const { data, error } = await clients.adminClient
      .from('employee_access_audit_log')
      .select('id,membership_id,actor_membership_id,action,created_at,metadata')
      .eq('organization_id', owner.institutionId)
      .or(`membership_id.eq.${employeeId},actor_membership_id.eq.${employeeId}`)
      .order('created_at', { ascending: false })
      .limit(200);
    if (error) return response({ error: 'audit_lookup_failed' }, 500);
    return response({ audit: data ?? [] });
  }

  if (body.action === 'update_employee') {
    const fullName = typeof body.fullName === 'string' ? body.fullName.trim() : '';
    const employeeNo = typeof body.employeeNo === 'string' ? body.employeeNo.trim() : '';
    const status = body.status === 'suspended' ? false : body.status === 'active' ? true : undefined;
    const roleCode = typeof body.roleCode === 'string' ? body.roleCode : undefined;
    const branchId = typeof body.branchId === 'string' ? body.branchId : null;
    if (fullName.length < 2 || fullName.length > 160 || !/^\d{1,32}$/.test(employeeNo) || !['owner', 'admin_followup', 'accountant', 'warehouse_keeper', 'warehouse_worker'].includes(roleCode ?? '') || (!isOwnerProfile(owner) && roleCode === 'owner') || (roleCode !== 'owner' && !/^[0-9a-f-]{36}$/i.test(branchId ?? ''))) {
      return response({ error: 'invalid_employee_payload' }, 400);
    }
    if (status === undefined) return response({ error: 'invalid_employee_status' }, 400);
    if (targetOwner && employeeId === owner.id && (roleCode !== 'owner' || status !== true)) {
      return response({ error: 'owner_self_protection' }, 403);
    }
    const { data: updateResult, error: updateError } = await clients.adminClient.rpc('admin_update_employee', {
      p_organization_id: owner.institutionId,
      p_actor_membership_id: owner.id,
      p_employee_id: employeeId,
      p_full_name: fullName,
      p_employee_no: employeeNo,
      p_role_code: roleCode,
      p_branch_id: roleCode === 'owner' ? null : branchId,
      p_is_active: status,
    });
    if (updateError) {
      const message = updateError.message ?? '';
      if (message.includes('employee_no_exists')) return response({ error: 'employee_no_exists' }, 409);
      if (message.includes('branch_not_found')) return response({ error: 'branch_not_found' }, 400);
      if (message.includes('owner_role_requires_owner')) return response({ error: 'owner_account_protected' }, 403);
      return response({ error: 'employee_update_failed' }, 400);
    }
    return response({ ok: true, result: updateResult });
  }

  const revoke = body.action === 'revoke_code';
  if (!revoke && (body.action !== 'set_code' || !isAccessCode(body.code))) {
    return response({ error: 'invalid_access_code' }, 400);
  }
  const credentialUpdate = revoke
    ? await removeEmployeeAccessCode(clients.adminClient, target.id, target.user_id)
    : await setEmployeeAccessCode(clients.adminClient, target.id, target.user_id, body.code as string);
  if (credentialUpdate.error) {
    console.error('employee_code_credential_update_failed', credentialUpdate.error);
    return response({ error: 'access_code_update_failed' }, 500);
  }

  const { error: metadataError } = await clients.adminClient
    .from('organization_memberships')
    .update({
      access_code_set_at: revoke ? null : new Date().toISOString(),
      access_code_updated_by: owner.id,
    })
    .eq('organization_id', owner.institutionId)
    .eq('id', employeeId);
  if (metadataError) {
    console.error('employee_code_metadata_update_failed_after_auth_update');
    return response({ error: 'access_code_status_update_failed' }, 500);
  }

  const { error: auditError } = await writeAudit(clients.adminClient, owner.institutionId, target.id, owner.id, revoke ? 'code_revoked' : 'password_reset');
  if (auditError) {
    console.error('employee_code_audit_write_failed');
    return response({ error: 'access_code_audit_failed' }, 500);
  }

  return response({ ok: true, revoked: revoke });
}

async function createEmployee(body: Record<string, unknown>, request: Request, clients: FunctionClients): Promise<Response> {
  const authorized = await verifyOwner(request, clients);
  if (!authorized.authorized) return authorized.error;
  const owner = authorized.profile;
  const employeeNo = typeof body.employeeNo === 'string' ? body.employeeNo.trim() : '';
  const fullName = typeof body.fullName === 'string' ? body.fullName.trim() : '';
  const roleCode = typeof body.roleCode === 'string' ? body.roleCode : '';
  const branchId = typeof body.branchId === 'string' ? body.branchId : null;
  const requestedCode = isAccessCode(body.code) ? body.code : null;
  const allowedRoles = new Set(['owner', 'admin_followup', 'accountant', 'warehouse_keeper', 'warehouse_worker']);
  if (!/^\d{1,32}$/.test(employeeNo) || fullName.length < 2 || fullName.length > 160 || !allowedRoles.has(roleCode) || (roleCode === 'owner' && !isOwnerProfile(owner)) || (roleCode !== 'owner' && !/^[0-9a-f-]{36}$/i.test(branchId ?? ''))) {
    return response({ error: 'invalid_employee_payload' }, 400);
  }

  const [{ data: existing }, branchResult] = await Promise.all([
    clients.adminClient.from('organization_memberships').select('id').eq('organization_id', owner.institutionId).eq('employee_no', employeeNo).maybeSingle(),
    roleCode === 'owner'
      ? Promise.resolve({ data: { id: null }, error: null })
      : clients.adminClient.from('branches').select('id').eq('organization_id', owner.institutionId).eq('id', branchId).eq('is_active', true).maybeSingle(),
  ]);
  if (existing) return response({ error: 'employee_no_exists' }, 409);
  if (!branchResult.data) return response({ error: 'branch_not_found' }, 400);

  const syntheticEmail = `employee-${owner.institutionId}-${employeeNo}@employee.invalid`;
  const { data: authData, error: authError } = await clients.adminClient.auth.admin.createUser({
    email: syntheticEmail,
    password: randomReplacementPassword(),
    email_confirm: true,
    user_metadata: { employee_no: employeeNo, organization_id: owner.institutionId },
  });
  let authUser = authData.user;
  let createdAuthUser = Boolean(authUser);
  if (!authUser && authError?.code === 'email_exists') {
    const existingAuth = await findAuthUserByEmail(clients.adminClient, syntheticEmail);
    if (existingAuth.error) return response({ error: 'employee_auth_lookup_failed' }, 503);
    if (!existingAuth.user) return response({ error: 'employee_auth_create_failed' }, 400);
    const { data: linkedMembership, error: linkedMembershipError } = await clients.adminClient
      .from('organization_memberships')
      .select('id,organization_id,employee_no')
      .eq('user_id', existingAuth.user.id)
      .limit(1)
      .maybeSingle();
    if (linkedMembershipError) return response({ error: 'employee_auth_lookup_failed' }, 503);
    if (linkedMembership) {
      const sameOrganization = linkedMembership.organization_id === owner.institutionId;
      const previousEmployeeNo = linkedMembership.employee_no?.trim() ?? '';
      if (!sameOrganization || !previousEmployeeNo || previousEmployeeNo === employeeNo) {
        return response({ error: 'employee_auth_exists' }, 409);
      }
      const repairedEmail = `employee-${owner.institutionId}-${previousEmployeeNo}@employee.invalid`;
      const { error: repairError } = await clients.adminClient.auth.admin.updateUserById(existingAuth.user.id, {
        email: repairedEmail,
        email_confirm: true,
      });
      if (repairError) return response({ error: 'employee_auth_exists' }, 409);
      const retry = await clients.adminClient.auth.admin.createUser({
        email: syntheticEmail,
        password: randomReplacementPassword(),
        email_confirm: true,
        user_metadata: { employee_no: employeeNo, organization_id: owner.institutionId },
      });
      authUser = retry.data.user;
      if (!authUser) return response({ error: 'employee_auth_create_failed' }, 400);
      createdAuthUser = true;
    } else {
      authUser = existingAuth.user;
      createdAuthUser = false;
    }
  }
  if (!authUser) return response({ error: 'employee_auth_create_failed' }, 400);

  const { data: membership, error: membershipError } = await clients.adminClient
    .from('organization_memberships')
    .insert({ organization_id: owner.institutionId, user_id: authUser.id, display_name: fullName, is_active: true, employee_no: employeeNo })
    .select('id,employee_no,display_name,is_active')
    .single();
  if (membershipError || !membership) {
    if (createdAuthUser) await clients.adminClient.auth.admin.deleteUser(authUser.id);
    return response({ error: 'employee_create_failed' }, 400);
  }

  const { error: roleError } = await clients.adminClient.from('role_assignments').insert({ organization_id: owner.institutionId, membership_id: membership.id, role_code: roleCode, branch_id: roleCode === 'owner' ? null : branchId });
  if (roleError) {
    await clients.adminClient.from('organization_memberships').delete().eq('id', membership.id);
    if (createdAuthUser) await clients.adminClient.auth.admin.deleteUser(authUser.id);
    return response({ error: 'employee_access_setup_failed' }, 400);
  }

  const code = requestedCode ?? randomAccessCode();
  const credentialUpdate = await setEmployeeAccessCode(clients.adminClient, membership.id, authUser.id, code);
  if (credentialUpdate.error) {
    await clients.adminClient.from('organization_memberships').delete().eq('id', membership.id);
    if (createdAuthUser) await clients.adminClient.auth.admin.deleteUser(authUser.id);
    return response({ error: 'access_code_create_failed' }, 500);
  }
  const now = new Date().toISOString();
  const { error: metadataError } = await clients.adminClient.from('organization_memberships').update({ access_code_set_at: now, access_code_updated_by: owner.id }).eq('id', membership.id);
  const { error: auditError } = await clients.adminClient.from('employee_access_audit_log').insert({ organization_id: owner.institutionId, membership_id: membership.id, actor_membership_id: owner.id, action: 'created', metadata: { roleCode, branchId } });
  if (metadataError || auditError) return response({ error: 'access_code_status_update_failed' }, 500);
  return response({ ok: true, employee: { id: membership.id, employeeNo, fullName, status: 'active', roleCode, branchId }, accessCode: code }, 201);
}

Deno.serve(async (request): Promise<Response> => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return response({ error: 'method_not_allowed' }, 405);

  try {
    const body = await request.json() as Record<string, unknown>;
    const clients = getClients();
    if (body.action === 'login') return await login(body, request, clients);
    if (body.action === 'bootstrap_owner') return await bootstrapOwner(body, clients);
    if (body.action === 'create_employee') return await createEmployee(body, request, clients);
    if (body.action === 'list' || body.action === 'set_code' || body.action === 'revoke_code' || body.action === 'update_employee' || body.action === 'audit' || body.action === 'manage_branch') {
      return await ownerOperation(body, request, clients);
    }
    return response({ error: 'unsupported_action' }, 400);
  } catch (error) {
    console.error('employee_code_auth_unhandled_error', error instanceof Error ? error.message : 'unknown');
    return response({ error: 'employee_code_auth_unavailable' }, 503);
  }
});
