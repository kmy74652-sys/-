create extension if not exists pgcrypto;
create extension if not exists citext;

create schema if not exists app;

DO $$
BEGIN
  CREATE TYPE public.employee_status AS ENUM ('active', 'suspended', 'archived');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE public.task_status AS ENUM ('pending', 'in_progress', 'submitted', 'approved', 'rejected', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE public.task_priority AS ENUM ('low', 'normal', 'high', 'urgent');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE public.recurrence_type AS ENUM ('daily', 'weekly', 'monthly');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE public.document_status AS ENUM ('draft', 'submitted', 'approved', 'rejected', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE public.inventory_transaction_type AS ENUM ('purchase_receipt', 'sales_issue', 'sales_return', 'purchase_return', 'transfer_in', 'transfer_out', 'stocktake_adjustment', 'opening_balance');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
