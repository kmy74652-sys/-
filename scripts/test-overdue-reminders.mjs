import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const migration = readFileSync('supabase/migrations/070_overdue_task_reminders.sql', 'utf8');
assert(migration.includes('notification_reminder_log'), 'reminder deduplication log exists');
assert(migration.includes('primary key (task_id, recipient_user_id, reminder_date)'), 'one reminder per task/user/day is enforced');
assert(migration.includes("t.due_at < now()") && migration.includes("t.deleted_at is null"), 'only active overdue tasks are selected');
assert(migration.includes("'completed_approved'") && migration.includes("'cancelled'") && migration.includes("'report_submitted'"), 'completed, cancelled and submitted tasks are excluded');
assert(migration.includes("'تذكير بمهمة متأخرة'") && migration.includes("'warning'"), 'Arabic warning notification is created');
assert(migration.includes('create extension if not exists pg_cron'), 'pg_cron is enabled');
assert(migration.includes("'overdue-task-reminders-hourly'") && migration.includes("'5 * * * *'"), 'hourly schedule is configured');
assert(migration.includes('on conflict (task_id, recipient_user_id, reminder_date) do nothing'), 'scheduled execution is idempotent');
console.log(JSON.stringify({ ok: true, checks: 8, scope: 'overdue-task-reminders' }));
