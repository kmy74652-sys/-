import { readFile } from 'node:fs/promises';
import { readdir } from 'node:fs/promises';
import { join } from 'node:path';

const root = new URL('../supabase/migrations/', import.meta.url);
const files = (await readdir(root)).filter((file) => file.endsWith('.sql')).sort();
const sql = (await Promise.all(files.map((file) => readFile(new URL(file, root), 'utf8')))).join('\n');

const requiredTables = [
  'institutions', 'branches', 'employees', 'roles', 'permissions', 'employee_roles',
  'tasks', 'task_updates', 'task_reviews', 'recurring_task_templates', 'task_runs',
  'customers', 'suppliers', 'products', 'units', 'warehouses', 'inventory_transactions',
  'sales_invoices', 'purchase_invoices', 'account_ledger_entries', 'receipts', 'payments',
  'stocktakes', 'audit_logs', 'notifications', 'attachments',
];
const requiredTokens = [
  "create type public.task_status",
  "create type public.recurrence_type",
  "alter table public.tasks",
  "enable row level security",
  "app.current_institution_id",
  "app.has_permission",
  "audit_logs_are_append_only",
];

const missingTables = requiredTables.filter((name) => !new RegExp(`create table if not exists public\\.${name}\\b`, 'i').test(sql));
const missingTokens = requiredTokens.filter((token) => !sql.toLowerCase().includes(token.toLowerCase()));
if (missingTables.length || missingTokens.length || files.length < 5) {
  console.error(JSON.stringify({ ok: false, files, missingTables, missingTokens }, null, 2));
  process.exit(1);
}

console.log(JSON.stringify({ ok: true, migrationFiles: files, requiredTables: requiredTables.length, securityTokens: requiredTokens.length }, null, 2));
