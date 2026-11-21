-- Align HR defaults with مؤسسة الشاعري operating locale.
-- Existing employee records are intentionally preserved.
alter table public.employee_contracts
  alter column salary_currency set default 'YER';
alter table public.employee_payroll_entries
  alter column currency set default 'YER';
alter table public.employee_work_schedules
  alter column timezone set default 'Asia/Aden';
