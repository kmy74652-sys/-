begin;
do $$ declare c record; begin for c in select conname from pg_constraint where conrelid='public.report_form_version_fields'::regclass and contype='c' and pg_get_constraintdef(oid) ilike '%field_type%' loop execute format('alter table public.report_form_version_fields drop constraint %I', c.conname); end loop; end $$;
alter table public.report_form_version_fields add constraint report_form_version_fields_field_type_check check (field_type in ('short_text','long_text','integer','decimal','percentage','quantity','money','datetime','date_range','system_reference','barcode','multi_image','select','multiselect','boolean','table','image','file','attachment','signature','calculated','decision_notes','text','number','progress','status','notes','textarea','date','checkbox'));
commit;
