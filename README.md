# برنامج الشاعري — تطبيق الهاتف فقط

المنتج المعتمد هو تطبيق الهاتف Android/iOS المبني بـExpo وReact Native، مع خدمات Supabase للمصادقة والبيانات. أزيل تطبيق الويب ومصادره ومساراته من المستودع؛ لا توجد واجهة متصفح أو خطة لنشر موقع. تبقى API وقاعدة البيانات وEdge Functions كخدمات خلفية عند الحاجة، وليست موقعًا للمستخدم.

## التشغيل والتطوير
1. انسخ `.env.example` إلى بيئة آمنة أو استخدم أسرار المشروع المحمية.
2. نفذ `pnpm install`.
3. تحقق من المخطط عبر `pnpm schema:verify` ثم نفذ المهاجرات على مشروع Supabase المقصود عند الحاجة.
4. لتشغيل API محليًا استخدم `pnpm dev`؛ ولتطوير الهاتف استخدم `pnpm --filter @alshaeri/mobile start` أو `pnpm --filter @alshaeri/mobile android`.
5. فحوص المشروع: `pnpm typecheck` و`pnpm test:task-workflow` و`pnpm test:report-designer`.

لا تضع `SUPABASE_SERVICE_ROLE_KEY` في التطبيق أو Git. يتصل تطبيق الهاتف مباشرةً بـSupabase Auth وPostgREST/RPC حيث ينص التصميم، ولا يعتمد على استضافة موقع. راجع [دليل migrations للهاتف](supabase/README.md) قبل إصدار يستخدم ترحيلًا جديدًا.
