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
  employeeNo: string;
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
      // Some self-hosted/legacy deployments expose a single value instead of a key map.
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

  // Keep the private throttle table bounded without storing old access attempts indefinitely.
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
  const canManageEmployees = profile?.permissions?.includes('employees.manage') ?? false;
  if (!profile || !ownerRole || !canManageEmployees) {
    return { authorized: false, error: response({ error: 'owner_permission_required' }, 403) };
  }
  return { authorized: true, profile };
}

function isAccessCode(value: unknown): value is string {
  return typeof value === 'string' && /^\S{8,64}$/.test(value);
}

function randomReplacementPassword() {
  const bytes = crypto.getRandomValues(new Uint8Array(48));
  return [...bytes].map((byte) => byte.toString(16).padStart(2, '0')).join('');
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

  const { data: matches, error: employeeError } = await clients.adminClient
    .from('employees')
    .select('id,institution_id,auth_user_id,status,access_code_set_at')
    .eq('employee_no', employeeNo)
    .limit(2);
  if (employeeError) {
    console.error('employee_code_login_employee_lookup_failed');
    return response({ error: 'database_update_required' }, 503);
  }

  const employee = matches?.length === 1 ? matches[0] : null;
  if (!employee || employee.status !== 'active' || !employee.auth_user_id || !employee.access_code_set_at) {
    await recordFailure(clients.adminClient, employeeHash, ipHash);
    return response({ error: 'invalid_credentials' }, 401);
  }

  const { data: authData, error: authLookupError } = await clients.adminClient.auth.admin.getUserById(employee.auth_user_id);
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
    ? { email: authUser.email, password: code }
    : { phone: authUser.phone!, password: code };
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

async function ownerOperation(body: Record<string, unknown>, request: Request, clients: FunctionClients): Promise<Response> {
  const authorized = await verifyOwner(request, clients);
  if (!authorized.authorized) return authorized.error;
  const owner = authorized.profile;

  if (body.action === 'list') {
    const { data, error } = await clients.adminClient
      .from('employees')
      .select('id,employee_no,full_name,status,auth_user_id,access_code_set_at')
      .eq('institution_id', owner.institutionId)
      .order('employee_no', { ascending: true })
      .limit(500);
    if (error) {
      console.error('employee_code_owner_list_failed');
      return response({ error: 'database_update_required' }, 503);
    }
    return response({ employees: (data ?? []).map((employee) => ({
      id: employee.id,
      employeeNo: employee.employee_no,
      fullName: employee.full_name,
      status: employee.status,
      hasAuthAccount: Boolean(employee.auth_user_id),
      codeSetAt: employee.access_code_set_at,
    })) });
  }

  const employeeId = typeof body.employeeId === 'string' ? body.employeeId : '';
  if (!/^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(employeeId)) {
    return response({ error: 'invalid_employee' }, 400);
  }
  const { data: target, error: targetError } = await clients.adminClient
    .from('employees')
    .select('id,auth_user_id,status')
    .eq('institution_id', owner.institutionId)
    .eq('id', employeeId)
    .maybeSingle();
  if (targetError) {
    console.error('employee_code_target_lookup_failed');
    return response({ error: 'database_update_required' }, 503);
  }
  if (!target || !target.auth_user_id) return response({ error: 'employee_auth_not_linked' }, 404);
  if (target.status !== 'active') return response({ error: 'employee_not_active' }, 400);

  const revoke = body.action === 'revoke_code';
  if (!revoke && (body.action !== 'set_code' || !isAccessCode(body.code))) {
    return response({ error: 'invalid_access_code' }, 400);
  }
  const nextPassword = revoke ? randomReplacementPassword() : body.code as string;
  const { error: passwordError } = await clients.adminClient.auth.admin.updateUserById(
    target.auth_user_id,
    { password: nextPassword },
  );
  if (passwordError) {
    console.error('employee_code_auth_update_failed');
    return response({ error: 'access_code_update_failed' }, 500);
  }

  const { error: metadataError } = await clients.adminClient
    .from('employees')
    .update({
      access_code_set_at: revoke ? null : new Date().toISOString(),
      access_code_updated_by: owner.id,
    })
    .eq('institution_id', owner.institutionId)
    .eq('id', employeeId);
  if (metadataError) {
    console.error('employee_code_metadata_update_failed_after_auth_update');
    return response({ error: 'access_code_status_update_failed' }, 500);
  }

  return response({ ok: true, revoked: revoke });
}

Deno.serve(async (request): Promise<Response> => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return response({ error: 'method_not_allowed' }, 405);

  try {
    const body = await request.json() as Record<string, unknown>;
    const clients = getClients();
    if (body.action === 'login') return await login(body, request, clients);
    if (body.action === 'list' || body.action === 'set_code' || body.action === 'revoke_code') {
      return await ownerOperation(body, request, clients);
    }
    return response({ error: 'unsupported_action' }, 400);
  } catch (error) {
    console.error('employee_code_auth_unhandled_error', error instanceof Error ? error.message : 'unknown');
    return response({ error: 'employee_code_auth_unavailable' }, 503);
  }
});
