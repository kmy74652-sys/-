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

console.log(JSON.stringify({ ok: true, checks: 9, scope: 'employee-screen-simplification' }));
