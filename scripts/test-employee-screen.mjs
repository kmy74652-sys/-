import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = fs.readFileSync(new URL('../apps/mobile/app/tasks.tsx', import.meta.url), 'utf8');

assert.equal(source.includes("const [reportSection"), false, 'لا يجب إعادة حالة التبويب الداخلي للتقارير');
assert.equal(source.includes('reportSectionTabs'), false, 'لا يجب إعادة تبويبات التقارير الداخلية');
assert.equal(source.includes('reportSectionTab'), false, 'لا يجب إعادة أنماط تبويبات التقارير الداخلية');
assert.equal(source.includes('>المهام</Text>'), true, 'تبويب المهام الرئيسي مطلوب');
assert.equal(source.includes('>إعداد التقارير</Text>'), true, 'تبويب التقارير الرئيسي مطلوب');
assert.equal(source.includes('>تقارير المهام</Text>'), true, 'قسم تقارير المهام مطلوب داخل صفحة التقارير');
assert.equal(source.includes('>التقارير اليومية من الإدارة</Text>'), true, 'قسم التقارير المستقلة مطلوب داخل صفحة التقارير');
assert.equal(source.includes('<EmployeeRoleReportPanel'), true, 'يجب أن يبقى مسار التقارير المستقلة مرتبطًا بمكونه');
assert.equal(source.includes("!loading && filteredTasks.map((task)"), true, 'يجب عرض تقارير المهام مباشرة دون شرط تبويب داخلي');
assert.equal(source.includes("readSessionCache<Task[]>('employee-tasks'"), true, 'يجب قراءة آخر مهام ناجحة من cache الجلسة');
assert.equal(source.includes("writeSessionCache('employee-tasks'"), true, 'يجب تحديث cache المهام بعد نجاح الجلب');
assert.equal(source.includes('applyTaskRows(cachedTasks)'), true, 'يجب عرض cache قبل اكتمال التحديث الشبكي');
assert.equal(source.includes('setLoading(false);'), true, 'يجب إنهاء حالة الانتظار عند توفر cache');
assert.equal(source.includes('Promise.allSettled([listMyTasks'), true, 'يجب فصل فشل التنبيهات عن تحميل المهام');
assert.equal(source.includes("if (taskResult.status === 'rejected') throw taskResult.reason"), true, 'يجب اعتبار فشل المهام فقط فشلًا رئيسيًا');

const cache = fs.readFileSync(new URL('../apps/mobile/lib/mobileSessionCache.ts', import.meta.url), 'utf8');
assert.equal(cache.includes('DEFAULT_MAX_AGE_MS = 120_000'), true, 'يجب أن يكون cache قصير العمر');
assert.equal(cache.includes('cache.clear()'), true, 'يجب توفير إفراغ كامل للcache');

console.log(JSON.stringify({ ok: true, checks: 18, scope: 'employee-screen-simplification' }));
