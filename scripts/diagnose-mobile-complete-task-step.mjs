import pg from 'pg';
import fs from 'node:fs/promises';
import path from 'node:path';

const { Client } = pg;

const args = process.argv.slice(2);
const getArg = (name) => {
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : undefined;
};
const hasArg = (name) => args.includes(name);

const logFile = getArg('--log-file');
const outFile = getArg('--out');
const taskId = getArg('--task-id');
const stepId = getArg('--step-id');
const actorUserId = getArg('--user-id');
const limit = Math.min(Math.max(Number(getArg('--limit') ?? 200), 1), 500);

if (hasArg('--help')) {
  console.log(`Usage:
  node scripts/diagnose-mobile-complete-task-step.mjs [options]

Options:
  --log-file <file>  JSON export from Supabase query_logs; parses 400/403 calls
  --out <file>       Write the diagnostic report as JSON
  --task-id <uuid>   Restrict database inspection to one task
  --step-id <uuid>   Restrict database inspection to one execution step
  --user-id <uuid>   Check assignment against a specific authenticated user
  --limit <n>        Maximum rows per read query (1-500, default 200)

Required environment for database inspection:
  SUPABASE_URL and SUPABASE_DB_PASSWORD
  Optional: SUPABASE_DB_HOST, SUPABASE_DB_PORT, SUPABASE_DB_USER, SUPABASE_DB_SSL_VERIFY

This script is read-only. It never calls the RPC and never writes to Supabase.`);
  process.exit(0);
}

const parseUuid = (value, name) => {
  if (!value) return undefined;
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)) {
    throw new Error(`${name} must be a UUID`);
  }
  return value;
};

parseUuid(taskId, '--task-id');
parseUuid(stepId, '--step-id');
parseUuid(actorUserId, '--user-id');

const parseLogRows = (input) => {
  if (!input) return [];
  let value = input;
  if (typeof input === 'string') value = JSON.parse(input);
  if (value?.result && typeof value.result === 'string') value = JSON.parse(value.result);
  if (value?.result && Array.isArray(value.result)) value = value.result;
  if (!Array.isArray(value)) return [];
  return value
    .map((row) => {
      const message = String(row.event_message ?? row.message ?? '');
      const status = message.match(/\|\s*(\d{3})\s*\|/)?.[1] ?? row.status_code ?? null;
      return {
        timestamp: row.timestamp ?? null,
        source: row.source ?? null,
        event_message: message,
        status_code: status ? Number(status) : null,
      };
    })
    .filter((row) => row.event_message.includes('/rpc/mobile_complete_task_step'))
    .sort((a, b) => String(a.timestamp).localeCompare(String(b.timestamp)));
};

const diagnosisForStep = (row, attachmentCount, providedEvidenceIds) => {
  const reasons = [];
  if (!row.task_id) reasons.push({ code: 'step_not_found', explanation: 'لم توجد خطوة تنفيذ بهذا المعرّف.' });
  if (row.deleted_at) reasons.push({ code: 'task_deleted', explanation: 'المهمة محذوفة حذفًا منطقيًا.' });
  if (row.assigned_to == null) reasons.push({ code: 'task_not_assigned', explanation: 'المهمة بلا موظف مستلم.' });
  if (actorUserId && row.assigned_to !== actorUserId) {
    reasons.push({ code: 'task_step_not_assigned', explanation: 'المستخدم المفحوص ليس الموظف المسند إليه.' });
  }
  if (row.status && !['in_progress', 'needs_revision'].includes(row.status)) {
    reasons.push({ code: 'task_must_be_in_progress', explanation: `حالة المهمة الحالية هي ${row.status}.` });
  }
  if (row.completed_at) {
    reasons.push({ code: 'step_already_completed', explanation: 'الخطوة مكتملة مسبقًا.' });
  }
  if (row.evidence_required && providedEvidenceIds.length === 0) {
    reasons.push({ code: 'task_step_evidence_required', explanation: `الخطوة تتطلب إثباتًا، وعدد المرفقات المرتبطة حاليًا ${attachmentCount}.` });
  }
  return {
    task_id: row.task_id,
    step_id: row.step_id,
    title: row.step_title,
    task_title: row.task_title,
    task_status: row.status,
    assigned_to: row.assigned_to,
    deleted_at: row.deleted_at,
    evidence_required: row.evidence_required,
    completed_at: row.completed_at,
    attachment_count: attachmentCount,
    likely_errors: reasons,
  };
};

let dbReport = {
  attempted: false,
  connected: false,
  read_only: true,
  rows: [],
  activity_matches: [],
  error: null,
};

if (process.env.SUPABASE_URL && process.env.SUPABASE_DB_PASSWORD) {
  dbReport.attempted = true;
  const url = new URL(process.env.SUPABASE_URL);
  const client = new Client({
    host: process.env.SUPABASE_DB_HOST ?? `db.${url.hostname.split('.')[0]}.supabase.co`,
    port: Number(process.env.SUPABASE_DB_PORT ?? 5432),
    user: process.env.SUPABASE_DB_USER ?? 'postgres',
    database: 'postgres',
    password: process.env.SUPABASE_DB_PASSWORD,
    ssl: { rejectUnauthorized: process.env.SUPABASE_DB_SSL_VERIFY !== 'false' },
    connectionTimeoutMillis: 15000,
    application_name: 'alshaeri-mobile-complete-step-diagnostic-readonly',
  });

  try {
    await client.connect();
    dbReport.connected = true;

    const filters = [];
    const values = [];
    if (stepId) {
      values.push(stepId);
      filters.push(`s.id = $${values.length}`);
    }
    if (taskId) {
      values.push(taskId);
      filters.push(`s.task_id = $${values.length}`);
    }
    const where = filters.length ? `where ${filters.join(' and ')}` : '';
    values.push(limit);

    const steps = await client.query(
      `select s.id as step_id, s.task_id, s.title as step_title, s.is_required,
              s.evidence_required, s.completed_by, s.completed_at,
              t.title as task_title, t.status, t.assigned_to, t.deleted_at,
              t.created_at, t.updated_at
         from public.task_execution_steps s
         left join public.tasks t on t.id = s.task_id
         ${where}
        order by coalesce(t.updated_at, t.created_at) desc nulls last
        limit $${values.length}`,
      values,
    );

    for (const row of steps.rows) {
      const attachments = await client.query(
        `select count(*)::int as count
           from public.task_attachments
          where task_id = $1 and (execution_step_id = $2 or execution_step_id is null)
          limit 1`,
        [row.task_id, row.step_id],
      );
      dbReport.rows.push(diagnosisForStep(row, attachments.rows[0]?.count ?? 0, []));
    }

    const activityValues = [];
    const activityFilter = taskId ? 'where l.task_id = $1' : '';
    if (taskId) activityValues.push(taskId);
    activityValues.push(limit);
    const activity = await client.query(
      `select l.task_id, l.actor_id, l.action, l.details, l.created_at
         from public.task_activity_log l
         ${activityFilter}
        order by l.created_at desc
        limit $${activityValues.length}`,
      activityValues,
    );
    dbReport.activity_matches = activity.rows.filter((row) =>
      ['task_step_completed', 'started'].includes(row.action),
    );
  } catch (error) {
    dbReport.error = { name: error.name, message: error.message };
  } finally {
    await client.end().catch(() => undefined);
  }
} else {
  dbReport.error = {
    name: 'MissingEnvironment',
    message: 'تخطى فحص قاعدة البيانات: SUPABASE_URL وSUPABASE_DB_PASSWORD غير متوفرين.',
  };
}

let logs = [];
if (logFile) {
  const raw = await fs.readFile(logFile, 'utf8');
  logs = parseLogRows(raw);
}

const report = {
  generated_at: new Date().toISOString(),
  read_only: true,
  target_rpc: 'mobile_complete_task_step',
  filters: { task_id: taskId ?? null, step_id: stepId ?? null, user_id: actorUserId ?? null, limit },
  log_summary: {
    input_file: logFile ?? null,
    matched_calls: logs.length,
    failed_calls: logs.filter((row) => row.status_code >= 400).length,
    calls_by_status: logs.reduce((acc, row) => {
      const key = String(row.status_code ?? 'unknown');
      acc[key] = (acc[key] ?? 0) + 1;
      return acc;
    }, {}),
  },
  failed_log_calls: logs.filter((row) => row.status_code >= 400),
  database: dbReport,
  interpretation: {
    known_rpc_guards: [
      'task_step_not_assigned (42501)',
      'task_must_be_in_progress (22023)',
      'task_step_evidence_required (22023)',
    ],
    limitation: 'Supabase unified edge logs expose HTTP status and endpoint but not always the PostgreSQL exception message; use database rows and application RPC error payload together.',
  },
};

const output = JSON.stringify(report, null, 2);
console.log(output);
if (outFile) {
  await fs.mkdir(path.dirname(path.resolve(outFile)), { recursive: true });
  await fs.writeFile(outFile, `${output}\n`, 'utf8');
  console.error(`Diagnostic report written to ${outFile}`);
}

const hasFailedCalls = report.log_summary.failed_calls > 0;
const hasDbError = Boolean(dbReport.error && dbReport.attempted);
if (hasFailedCalls || hasDbError) process.exitCode = 1;
