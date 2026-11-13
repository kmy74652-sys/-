import pg from 'pg';
const { Client } = pg;
for (const name of ['SUPABASE_URL', 'SUPABASE_DB_PASSWORD']) {
  if (!process.env[name]) throw new Error(`${name} is required`);
}
const url = new URL(process.env.SUPABASE_URL);
const ref = url.hostname.split('.')[0];
const client = new Client({
  host: process.env.SUPABASE_DB_HOST ?? `db.${ref}.supabase.co`,
  port: Number(process.env.SUPABASE_DB_PORT ?? 5432),
  user: process.env.SUPABASE_DB_USER ?? 'postgres',
  database: 'postgres',
  password: process.env.SUPABASE_DB_PASSWORD,
  ssl: { rejectUnauthorized: process.env.SUPABASE_DB_SSL_VERIFY !== 'false' },
  connectionTimeoutMillis: 15000,
});
await client.connect();
try {
  const migrations = await client.query('select filename from app.schema_migrations order by filename');
  const tables = await client.query("select table_name from information_schema.tables where table_schema = 'public' and table_type = 'BASE TABLE' order by table_name");
  const unsecured = await client.query(`
    select c.relname as table_name
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity
    order by c.relname
  `);
  const policyCount = await client.query("select count(*)::int as count from pg_policies where schemaname = 'public'");
  const institutions = await client.query('select count(*)::int as count from public.institutions');
  const auditTriggers = await client.query("select count(*)::int as count from pg_trigger where tgrelid = 'public.audit_logs'::regclass and not tgisinternal");
  const workflowFunctions = await client.query("select proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'app' and proname = any($1::text[])", [['record_task_update', 'review_task', 'generate_recurring_tasks']]);
  const workflowFunctionNames = new Set(workflowFunctions.rows.map((row) => row.proname));
  const financeFunctions = await client.query("select proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'app' and proname = any($1::text[])", [['create_customer_with_account', 'approve_credit_limit', 'approve_receipt']]);
  const financeFunctionNames = new Set(financeFunctions.rows.map((row) => row.proname));
  const financePolicies = await client.query("select policyname from pg_policies where schemaname = 'public' and policyname = any($1::text[])", [['customers_manage', 'accounts_read', 'credit_limits_propose', 'receipts_create', 'receipts_approve', 'ledger_insert']]);
  const financePolicyNames = new Set(financePolicies.rows.map((row) => row.policyname));
  const commerceFunctions = await client.query("select proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'app' and proname = any($1::text[])", [['create_sales_invoice_with_items', 'create_purchase_invoice_with_items', 'approve_sales_invoice', 'approve_purchase_invoice']]);
  const commerceFunctionNames = new Set(commerceFunctions.rows.map((row) => row.proname));
  const returnsFunctions = await client.query("select proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'app' and proname = any($1::text[])", [['create_return_transaction', 'create_stocktake_with_items', 'approve_stocktake']]);
  const returnsFunctionNames = new Set(returnsFunctions.rows.map((row) => row.proname));
  const movementSignColumn = await client.query("select 1 from information_schema.columns where table_schema = 'public' and table_name = 'inventory_transaction_items' and column_name = 'movement_sign'");
  const result = {
    ok: unsecured.rows.length === 0 && Number(auditTriggers.rows[0].count) >= 2 && workflowFunctionNames.size === 3 && financeFunctionNames.size === 3 && financePolicyNames.size === 6 && commerceFunctionNames.size === 4 && returnsFunctionNames.size === 3 && movementSignColumn.rowCount === 1,
    migrationFiles: migrations.rows.map((row) => row.filename),
    publicTableCount: tables.rows.length,
    policyCount: policyCount.rows[0].count,
    rlsMissingOn: unsecured.rows.map((row) => row.table_name),
    institutionRows: institutions.rows[0].count,
    auditTriggerCount: auditTriggers.rows[0].count,
    workflowFunctions: [...workflowFunctionNames].sort(),
    financeFunctions: [...financeFunctionNames].sort(),
    financePolicies: [...financePolicyNames].sort(),
    commerceFunctions: [...commerceFunctionNames].sort(),
    returnsFunctions: [...returnsFunctionNames].sort(),
    movementSignColumn: movementSignColumn.rowCount === 1,
  };
  console.log(JSON.stringify(result, null, 2));
  if (!result.ok) process.exitCode = 1;
} finally {
  await client.end();
}
