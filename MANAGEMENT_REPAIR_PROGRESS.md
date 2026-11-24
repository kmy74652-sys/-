

## إصلاح خطأ حذف قالب التقرير بسبب جدول غير موجود — مكتمل

أظهرت شاشة مصمم التقارير خطأ PostgreSQL: `relation public.task_template_report_forms does not exist`. فحص مخطط Supabase الإنتاجي `fjmryqhdwxsocdzswnkq` أكد أن هذا الجدول غير موجود، بينما كانت دالة `admin_delete_report_template` تشير إليه مباشرة.

تم إنشاء وتطبيق migration `supabase/migrations/20261124165500_fix_safe_report_template_delete_missing_relation.sql`. أصبحت الدالة تتحقق من وجود الجدول عبر `to_regclass`، وتستخدم SQL ديناميكيًا لتنظيفه فقط إن كان موجودًا في بيئة أخرى، وتتابع الحذف الآمن للقالب وإصداراته عندما لا يكون الجدول موجودًا. لم يتم إنشاء جدول أو حذف بيانات أو تعديل RLS أو الصلاحيات.

تم التحقق عبر SQL من الإنتاج: `optional_table` يساوي NULL، وموضع SQL الديناميكي موجود داخل تعريف الدالة. الخطوة التالية: تجربة زر الحذف من التطبيق بحساب الإدارة، مع بقاء CI الخاص بالكود كما هو ناجحًا.
