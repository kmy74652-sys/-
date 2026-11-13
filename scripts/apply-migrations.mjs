import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { readdir } from 'node:fs/promises';
import { join } from 'node:path';
import pg from 'pg';

const { Client } = pg;
const required = ['SUPABASE_URL', 'SUPABASE_DB_PASSWORD'];
for (const name of required) {
  if (!process.env[name]) throw new Error(`${name} is required`);
}

const supabaseUrl = new URL(process.env.SUPABASE_URL);
const projectRef = supabaseUrl.hostname.split('.')[0];
const client = new Client({
  host: process.env.SUPABASE_DB_HOST ?? `db.${projectRef}.supabase.co`,
  port: Number(process.env.SUPABASE_DB_PORT ?? 5432),
  user: process.env.SUPABASE_DB_USER ?? 'postgres',
  database: 'postgres',
  password: process.env.SUPABASE_DB_PASSWORD,
  ssl: { rejectUnauthorized: process.env.SUPABASE_DB_SSL_VERIFY !== 'false' },
  connectionTimeoutMillis: 15000,
});

const migrationsDir = join(process.cwd(), 'supabase', 'migrations');
const seedDir = join(process.cwd(), 'supabase', 'seed');
const files = [
  ...(await readdir(migrationsDir)).filter((file) => file.endsWith('.sql')).sort().map((file) => join(migrationsDir, file)),
  ...(await readdir(seedDir)).filter((file) => file.endsWith('.sql')).sort().map((file) => join(seedDir, file)),
];

await client.connect();
try {
  await client.query(`
    create schema if not exists app;
    create table if not exists app.schema_migrations (
      filename text primary key,
      checksum text not null,
      applied_at timestamptz not null default now()
    );
  `);

  const existing = new Map((await client.query('select filename, checksum from app.schema_migrations')).rows.map((row) => [row.filename, row.checksum]));
  const before = await client.query("select count(*)::int as count from information_schema.tables where table_schema = 'public'");
  console.log(JSON.stringify({ target: `${projectRef}.supabase.co`, publicTablesBefore: before.rows[0].count, migrations: files.length }));

  for (const file of files) {
    const filename = file.split('/').pop();
    const source = await readFile(file, 'utf8');
    const checksum = createHash('sha256').update(source).digest('hex');
    const prior = existing.get(filename);
    if (prior === checksum) {
      console.log(`skip ${filename}`);
      continue;
    }
    if (prior) throw new Error(`checksum_mismatch_for_applied_migration:${filename}`);

    await client.query('begin');
    try {
      await client.query(source);
      await client.query('insert into app.schema_migrations (filename, checksum) values ($1, $2)', [filename, checksum]);
      await client.query('commit');
      console.log(`applied ${filename}`);
    } catch (error) {
      await client.query('rollback');
      throw error;
    }
  }

  const after = await client.query("select count(*)::int as count from information_schema.tables where table_schema = 'public'");
  const required = ['institutions', 'branches', 'employees', 'roles', 'permissions', 'tasks', 'customers', 'sales_invoices', 'inventory_transactions', 'audit_logs'];
  const checks = await client.query(
    "select table_name from information_schema.tables where table_schema = 'public' and table_name = any($1::text[])",
    [required],
  );
  const found = new Set(checks.rows.map((row) => row.table_name));
  const missing = required.filter((name) => !found.has(name));
  if (missing.length) throw new Error(`missing_tables_after_migration:${missing.join(',')}`);
  console.log(JSON.stringify({ ok: true, publicTablesAfter: after.rows[0].count, requiredTablesVerified: required.length }));
} finally {
  await client.end();
}
