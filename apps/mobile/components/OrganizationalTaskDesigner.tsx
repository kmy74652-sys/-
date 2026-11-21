import { useMemo, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import AdenDeadlinePicker, { adenDateTimeToIso, currentAdenDateTime } from './AdenDeadlinePicker';
import type { TaskReportSelection, TaskRoleCode, TaskTemplateDraft } from './TaskDesigner';
import type { DesignerField } from '../lib/reportSchema';

type ScheduleRow = { id: string; timeSlot: string; responsibility: string; kpiIndicator: string; proofRequirement: string; requiresProof: boolean; subItems: string[] };
type EmployeeOption = { id: string; userId?: string | null; name: string; active: boolean; roles?: string[]; assignments?: Array<{ roleCode: string; branchId: string | null }> };
type BranchOption = { id: string; name: string; isActive?: boolean };
type SaveResult = { templateId?: string; reports?: TaskReportSelection[] };
type Props = { initialTemplate?: Partial<TaskTemplateDraft>; employees?: EmployeeOption[]; branches?: BranchOption[]; canManage?: boolean; onSave?: (draft: TaskTemplateDraft) => void | Promise<SaveResult | void>; onSend?: (draft: TaskTemplateDraft, employeeId: string, branchId: string | null, dueAt: string, idempotencyKey: string) => void | Promise<void>; onList?: () => void | Promise<void> };

const roles: Array<[TaskRoleCode, string]> = [
  ['owner', 'صاحب المؤسسة'], ['admin_followup', 'المدير التنفيذي'], ['accountant', 'المحاسب'], ['warehouse_keeper', 'أمين المخازن'], ['warehouse_worker', 'عمال التحميل'],
];
const defaultKpis = ['طلبات العملاء', 'الرد على الجوال', 'فواتير المشتريات', 'مطابقة الموردين', 'الحسابات', 'تحصيل العملاء', 'الشكاوى', 'التقرير اليومي'];
const key = () => `${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
const defaults: ScheduleRow[] = [
  { id: key(), timeSlot: '08:00 - 08:30 ص', responsibility: 'مراجعة رسائل الجوال والطلبات الجديدة ومتابعة الأعمال المتبقية', kpiIndicator: 'الرد على الجوال', proofRequirement: 'تأكيد الإنجاز', requiresProof: false, subItems: ['التحقق من رسائل العملاء الجديدة', 'متابعة الطلبات العاجلة في الجوال'] },
  { id: key(), timeSlot: '02:00 - 03:00 م', responsibility: 'مطابقة حساب مورد واحد أو موردين على الأقل يومياً وتسجيل الفروقات', kpiIndicator: 'مطابقة الموردين', proofRequirement: 'إرفاق كشف / ملاحظة', requiresProof: true, subItems: ['مطابقة كشف الحساب مع الفواتير', 'توثيق أي فرق مالي مع السبب'] },
  { id: key(), timeSlot: '04:00 - 04:30 م', responsibility: 'تسليم الحسابات الجاهزة للمتابعة والسيطرة عليها', kpiIndicator: 'الحسابات', proofRequirement: 'إدخال العدد', requiresProof: true, subItems: ['مراجعة جاهزية الحسابات', 'تسليمها وتأكيد الاستلام'] },
  { id: key(), timeSlot: '09:45 - 10:30 م', responsibility: 'مراجعة الأعمال اليومية وإعداد تقرير الإنجاز وإقفال المهام', kpiIndicator: 'التقرير اليومي', proofRequirement: 'إرسال التقرير اليومي', requiresProof: true, subItems: ['مراجعة الأعمال اليومية', 'إقفال المهام غير المكتملة مع ذكر السبب'] },
];
const continuousDefaults = ['الرد على اتصالات ورسائل زبائن الجملة دون تأخير.', 'استقبال طلبات العملاء وتسجيلها ومتابعتها حتى التنفيذ.', 'عدم ترك أي فاتورة مشتريات دون تسجيل أو متابعة.'];
const reportDefaults = ['عدد فواتير مبيعات الجملة وطلبات العملاء المستلمة والمنفذة', 'إجمالي المبالغ المحصلة', 'عدد فواتير المشتريات المسجلة', 'أسماء الموردين الذين تمت مطابقة حساباتهم', 'عدد الحسابات المسلمة للمتابعة', 'الشكاوى التي تمت معالجتها', 'الأعمال التي لم تنجز وأسباب التأخير'];
const recommendationDefaults = ['خدمة العملاء ومبيعات الجملة لها الأولوية عند وجود زبائن أو طلبات عاجلة.', 'عدم تأجيل تسجيل فواتير المشتريات إلى اليوم التالي وتوثيق الفروقات.', 'إبلاغ الإدارة فوراً عن أي اختلاف في الأسعار أو الكميات أو الحسابات.'];

type RolePreset = { rows: Array<Omit<ScheduleRow, 'id'>>; continuous: string[]; reports: string[]; recommendations: string[] };
const rolePresets: Partial<Record<TaskRoleCode, RolePreset>> = {
  warehouse_keeper: {
    rows: [
      { timeSlot: '08:00 - 09:00 ص', responsibility: 'فتح المخزن والتأكد من جاهزية الأصناف سريعة الحركة والممرات ومناطق الاستلام والصرف', kpiIndicator: 'جاهزية المخزن', proofRequirement: 'قائمة فحص الجاهزية', requiresProof: true, subItems: ['مراجعة ملاحظات اليوم السابق', 'التأكد من ترتيب الممرات ومواقع الأصناف'] },
      { timeSlot: '09:00 - 10:00 ص', responsibility: 'تنفيذ جرد الأصناف المحددة وإعداد كشف الكميات الفعلية وإعادة العد عند وجود فرق', kpiIndicator: 'الجرد والمطابقة', proofRequirement: 'كشف جرد أو نتيجة مطابقة', requiresProof: true, subItems: ['تحديد الأصناف المكلف بها', 'توثيق العجز أو الزيادة وسببها'] },
      { timeSlot: '09:00 - 12:00 ظ', responsibility: 'استلام الشحنة وفحص الصنف والكمية والحالة والصلاحية ومطابقتها مع فاتورة المورد', kpiIndicator: 'الاستلام والفحص', proofRequirement: 'فاتورة الاستلام وملاحظة الفحص', requiresProof: true, subItems: ['عدم فتح الشحنة قبل الحضور والإذن', 'تسليم الفاتورة للمحاسب وتأكيد الكمية الفعلية'] },
      { timeSlot: '12:00 - 01:00 م', responsibility: 'تنفيذ صرف الأصناف وفق فاتورة أو إذن صرف معتمد والتحقق من النوع والكمية', kpiIndicator: 'الصرف المعتمد', proofRequirement: 'فاتورة أو إذن صرف', requiresProof: true, subItems: ['عدم إخراج أي صنف دون مستند', 'تحديث مستندات حركة المخزن'] },
      { timeSlot: '01:00 - 09:30 م', responsibility: 'تنظيم المخزن ومتابعة الصلاحية والتالف والراكد وحفظ مستندات الاستلام والصرف والجرد', kpiIndicator: 'سلامة وتنظيم المخزون', proofRequirement: 'قائمة تلف أو صلاحية عند وجودها', requiresProof: true, subItems: ['فصل التالف أو القريب من الانتهاء', 'إبلاغ الإدارة دون إجراء شطب أو تسوية ذاتية'] },
      { timeSlot: '09:30 - 10:00 م', responsibility: 'إغلاق حركة المخزن والتأكد من حفظ المستندات وعدم وجود بضاعة متروكة أو حركة غير موثقة', kpiIndicator: 'إقفال المخزن', proofRequirement: 'تأكيد إقفال المخزن', requiresProof: true, subItems: ['مراجعة الاستلام والصرف والجرد', 'رفع النواقص أو القرارات المطلوبة'] },
    ],
    continuous: ['عدم إدخال أو إخراج بضاعة دون إذن ومستند معتمد.', 'المحافظة على النظافة والترتيب طوال الدوام.', 'الإبلاغ الفوري عن التلف أو النقص أو الصنف الموجود في غير مكانه.'],
    reports: ['عدد الاستلامات والكميات المطابقة وغير المطابقة', 'عدد عمليات الصرف ومستنداتها', 'نتيجة الجرد والعجز أو الزيادة', 'التالف والقريب من الانتهاء والراكد', 'المستندات أو القرارات المطلوبة'],
    recommendations: ['الموظف المختص يعتمد نتيجة مخزنه ولا يجري تسوية أو شطبًا ذاتيًا.', 'خدمة الزبائن وسلامة البضاعة وتوثيق الحركة لها الأولوية عند ضغط العمل.'],
  },
  warehouse_worker: {
    rows: [
      { timeSlot: '08:00 - 08:30 ص', responsibility: 'تجهيز منطقة التحميل والتفريغ والعربات وأدوات النقل والتأكد من سلامتها', kpiIndicator: 'جاهزية التحميل', proofRequirement: 'تأكيد جاهزية المنطقة', requiresProof: true, subItems: ['إزالة العوائق من منطقة التحميل', 'فحص العربات وأدوات النقل'] },
      { timeSlot: '08:30 - 12:00 ظ', responsibility: 'مساندة أمين المخزن في تفريغ الشحنات ونقل الكراتين إلى المواقع التي يحددها دون فتحها قبل الإذن', kpiIndicator: 'الاستلام والتفريغ', proofRequirement: 'تأكيد العملية أو ملاحظة تلف', requiresProof: true, subItems: ['اتباع توجيه أمين المخزن فقط', 'الإبلاغ عن الكرتون المكسور أو المبلل أو التالف'] },
      { timeSlot: '01:00 - 05:00 م', responsibility: 'تجهيز وتحميل طلبات الزبائن بعد اعتماد إذن الصرف ومطابقة عدد الطرود', kpiIndicator: 'تجهيز وتحميل الطلبات', proofRequirement: 'تأكيد عدد الطرود أو صورة عند الحاجة', requiresProof: true, subItems: ['مطابقة الطرود مع أمر التسليم', 'المحافظة على سلامة التغليف'] },
      { timeSlot: '05:00 - 09:30 م', responsibility: 'نقل البضاعة وترتيب منطقة التحميل وإعادة العربات والكرتون الفارغ والأدوات إلى أماكنها', kpiIndicator: 'النقل والترتيب', proofRequirement: 'تأكيد إخلاء المنطقة', requiresProof: false, subItems: ['إعادة البضاعة غير المصروفة للمكان المحدد', 'عدم تغيير مواقع الأصناف من تلقاء النفس'] },
      { timeSlot: '09:30 - 10:00 م', responsibility: 'تنظيف منطقة التحميل والتفريغ والتأكد من خلو الممرات ورفع الأعمال المتبقية أو العوائق', kpiIndicator: 'إقفال منطقة التحميل', proofRequirement: 'تأكيد الإقفال', requiresProof: true, subItems: ['إعادة الأدوات والعربات', 'الإبلاغ عن أي تلف أو نقص أو عائق'] },
    ],
    continuous: ['تنفيذ أوامر أمين المخزن فقط في تحريك البضاعة وترتيبها.', 'الإبلاغ فورًا عن التلف أو الكسر أو النقص.', 'المحافظة على نظافة وسلامة الممرات طوال الدوام.'],
    reports: ['عمليات التحميل والتفريغ والنقل المنفذة', 'الشحنات التي تمت مساعدته في تفريغها', 'أي تلف أو كسر أو نقص تم الإبلاغ عنه', 'الطلبات التي تم تجهيزها أو تحميلها', 'الأعمال المتبقية أو العوائق'],
    recommendations: ['لا يوقع عامل التحميل على إذن الاستلام ولا يعتمد الكميات.', 'لا يبدأ التفريغ أو فتح الكراتين قبل أمر أمين المخزن.'],
  },
  admin_followup: {
    rows: [
      { timeSlot: '08:00 - 09:00 ص', responsibility: 'مراجعة المهام الجديدة وتوزيعها على الموظفين حسب الدور والفرع والأولوية', kpiIndicator: 'توزيع المهام', proofRequirement: 'قائمة الإسناد أو تأكيد الوصول', requiresProof: true, subItems: ['التحقق من الموظف والفرع والموعد', 'متابعة وصول المهمة إلى تبويب الموظف'] },
      { timeSlot: '09:00 - 10:00 ص', responsibility: 'مراجعة التقارير المرفوعة والمهام المتأخرة وتحديد ما يحتاج تصحيحًا أو تصعيدًا', kpiIndicator: 'مراجعة التقارير', proofRequirement: 'قرار مراجعة أو ملاحظة تصحيح', requiresProof: true, subItems: ['فحص اكتمال الحقول والإثباتات', 'إعادة التقرير للموظف عند وجود نقص واضح'] },
      { timeSlot: '10:00 - 12:00 ظ', responsibility: 'متابعة تنفيذ الفروع والموظفين ومعالجة العوائق التشغيلية ضمن الصلاحية', kpiIndicator: 'متابعة الفروع', proofRequirement: 'سجل متابعة وإجراء متخذ', requiresProof: true, subItems: ['تحديد سبب التأخير والمسؤول عنه', 'تصعيد ما يتطلب قرار الإدارة'] },
      { timeSlot: '01:00 - 04:00 م', responsibility: 'مقارنة أداء الموظفين والفروع ومراجعة مؤشرات الإنجاز والمهام الحرجة', kpiIndicator: 'مقارنة الأداء', proofRequirement: 'ملخص أداء أو قائمة مهام حرجة', requiresProof: true, subItems: ['مراجعة المهام المتأخرة', 'تحديد الأولويات والاحتياجات'] },
      { timeSlot: '04:00 - 06:00 م', responsibility: 'متابعة المشكلات المفتوحة والتأكد من تنفيذ إجراءات التصحيح وإبلاغ صاحب المؤسسة بالقرارات المطلوبة', kpiIndicator: 'إغلاق المشكلات', proofRequirement: 'سجل مشكلات محدث', requiresProof: true, subItems: ['تحديث حالة كل مشكلة', 'رفع التوصيات التي تحتاج اعتمادًا'] },
      { timeSlot: '09:30 - 10:00 م', responsibility: 'إعداد ملخص المتابعة اليومية وتوثيق المنجز والمتأخر وما يحتاج قرارًا لليوم التالي', kpiIndicator: 'التقرير اليومي', proofRequirement: 'إرسال تقرير المتابعة', requiresProof: true, subItems: ['حصر التقارير غير المكتملة', 'تحديد مهام اليوم التالي'] },
    ],
    continuous: ['متابعة وصول المهام والتقارير دون الدخول في تنفيذ عمل الموظف نيابة عنه.', 'عدم اعتماد التقرير دون مراجعة الحقول والإثباتات المطلوبة.', 'إبلاغ صاحب المؤسسة فورًا عن مشكلة حرجة أو تأخير متكرر.'],
    reports: ['عدد المهام المسندة والتي وصلت للموظفين', 'التقارير التي تمت مراجعتها أو إعادتها للتعديل', 'المهام المتأخرة وأسبابها والإجراء المتخذ', 'مقارنة مختصرة بين الفروع أو الموظفين', 'المشكلات المفتوحة والتوصيات والقرارات المطلوبة'],
    recommendations: ['المدير يتابع ويعيد التقرير للتعديل، ولا يعتمد استثناءً خارج صلاحياته.', 'الأولوية للمشكلات الحرجة والتأخير المؤثر على العملاء أو سلامة البضاعة.'],
  },
  owner: {
    rows: [
      { timeSlot: '09:00 - 10:00 ص', responsibility: 'مراجعة ملخص المهام المتأخرة والمهام الحرجة وتقارير الفروع التي تحتاج قرارًا', kpiIndicator: 'المراجعة الإدارية', proofRequirement: 'قائمة قرارات أو توجيهات', requiresProof: true, subItems: ['تحديد البنود الحرجة', 'توجيه المدير بما يلزم متابعته'] },
      { timeSlot: '10:00 - 11:00 ص', responsibility: 'مراجعة ملخص المبيعات والتحصيل والمشتريات وفروقات المخزون حسب الفروع', kpiIndicator: 'مؤشرات المؤسسة', proofRequirement: 'ملخص مؤشرات معتمد', requiresProof: true, subItems: ['مقارنة الفروع', 'تحديد الانحرافات التي تحتاج معالجة'] },
      { timeSlot: '01:00 - 02:00 م', responsibility: 'اعتماد القرارات والاستثناءات التي تتجاوز صلاحيات المدير أو الموظفين', kpiIndicator: 'الاعتمادات والقرارات', proofRequirement: 'قرار أو اعتماد موثق', requiresProof: true, subItems: ['اعتماد التسويات أو الاستثناءات عند الحاجة', 'تحديد المسؤول والموعد النهائي'] },
      { timeSlot: '04:00 - 05:00 م', responsibility: 'مراجعة أداء المدير التنفيذي والفروع وتوجيه الأولويات التشغيلية للفترة القادمة', kpiIndicator: 'أداء الإدارة', proofRequirement: 'توجيه إداري موثق', requiresProof: true, subItems: ['مراجعة التوصيات', 'تحديد الأولويات الجديدة'] },
      { timeSlot: '09:00 - 09:30 م', responsibility: 'مراجعة ملخص اليوم وتحديد القرارات أو المتابعات المطلوبة لليوم التالي', kpiIndicator: 'القرارات اليومية', proofRequirement: 'ملخص قرارات', requiresProof: true, subItems: ['تأكيد البنود المغلقة', 'تسجيل القرارات غير المنفذة'] },
    ],
    continuous: ['الاطلاع على الملخصات والقرارات دون التدخل في تنفيذ الموظف لمهمته اليومية.', 'اعتماد الاستثناءات والتسويات الحساسة فقط بعد مراجعة المستندات.', 'تحديد الأولويات بوضوح وإبلاغ المدير بما يحتاج متابعة.'],
    reports: ['المهام الحرجة والمتأخرة وسبب كل حالة', 'ملخص أداء الفروع والموظفين', 'ملخص المبيعات والتحصيل والمشتريات', 'فروقات المخزون أو المصروفات التي تحتاج قرارًا', 'القرارات والتوجيهات والتوصيات لليوم التالي'],
    recommendations: ['يبقى التنفيذ والمتابعة اليومية لدى المدير والموظفين، ويقتصر دور صاحب المؤسسة على الرقابة والاعتماد والتوجيه.', 'لا يعتمد أي تسوية أو استثناء دون مستند أو كشف واضح.'],
  },
};

function presetRows(role: TaskRoleCode) {
  const preset = rolePresets[role];
  return preset?.rows.map((row) => ({ ...row, id: key(), subItems: [...row.subItems] })) ?? null;
}
const accountantMissingRows: Array<Omit<ScheduleRow, 'id'>> = [
  { timeSlot: '08:30 - 10:00 ص', responsibility: 'تسجيل ومراجعة فواتير المبيعات والمشتريات والتأكد من اكتمال المستندات', kpiIndicator: 'فواتير المشتريات', proofRequirement: 'الفواتير المسجلة والمستندات الناقصة', requiresProof: true, subItems: ['مطابقة الصنف والكمية والسعر', 'عدم ترحيل الفاتورة قبل اكتمال المراجعة'] },
  { timeSlot: '10:00 - 11:00 ص', responsibility: 'تسجيل النواقص ورفع قائمة الشراء للإدارة دون إصدار أمر شراء غير معتمد', kpiIndicator: 'النواقص والمشتريات', proofRequirement: 'قائمة النواقص المرفوعة', requiresProof: true, subItems: ['تحديد الصنف والكمية المطلوبة', 'تحديد المورد أو ملاحظة عدم توفره'] },
  { timeSlot: '11:00 - 12:00 ظ', responsibility: 'مطابقة المخزون مع مسؤول المخزن والتحقيق في العجز أو الزيادة ومراجعة حركات الاستلام والصرف والمرتجعات', kpiIndicator: 'مطابقة الموردين', proofRequirement: 'كشف المطابقة ومحضر الفرق', requiresProof: true, subItems: ['إعادة العد عند وجود فرق', 'رفع التسوية للمدير وعدم تعديل الرصيد ذاتيًا'] },
  { timeSlot: '06:00 - 07:00 م', responsibility: 'متابعة مديونيات العملاء والموردين وتوثيق الاتصالات والوعود والتحصيل ورفع الاستثناءات للمدير', kpiIndicator: 'تحصيل العملاء', proofRequirement: 'كشف متابعة أو سجل اتصال', requiresProof: true, subItems: ['تحديد الحسابات المتأخرة', 'تسجيل نتيجة التواصل والموعد التالي'] },
];

function roleCode(value: string | undefined): TaskRoleCode { return roles.some(([code]) => code === value) ? value as TaskRoleCode : 'accountant'; }

export default function OrganizationalTaskDesigner({ initialTemplate, employees = [], branches = [], canManage = true, onSave, onSend, onList }: Props) {
  const isNewTemplate = !initialTemplate?.id;
  const [title, setTitle] = useState(initialTemplate?.title ?? '');
  const [selectedRole, setSelectedRole] = useState<TaskRoleCode>(roleCode(initialTemplate?.roleCode));
  const [kpis, setKpis] = useState(defaultKpis);
  const [newKpi, setNewKpi] = useState('');
  const [showKpiInput, setShowKpiInput] = useState(false);
  const [kpiTargetRowId, setKpiTargetRowId] = useState('');
  const [subItemDrafts, setSubItemDrafts] = useState<Record<string, string>>({});
  const [days, setDays] = useState(isNewTemplate ? '' : 'السبت إلى الخميس (الجمعة إجازة)');
  const [morning, setMorning] = useState(isNewTemplate ? '' : '08:00 ص - 12:00 م');
  const [breakTime, setBreakTime] = useState(isNewTemplate ? '' : '12:00 م - 01:00 م');
  const [evening, setEvening] = useState(isNewTemplate ? '' : '01:00 م - 10:30 م');
  const [rows, setRows] = useState<ScheduleRow[]>(() => initialTemplate?.steps?.length ? initialTemplate.steps.map((step, index) => ({ id: step.id || key(), timeSlot: `الفترة ${index + 1}`, responsibility: step.title, kpiIndicator: 'التقرير اليومي', proofRequirement: step.evidenceInstructions || 'تأكيد الإنجاز', requiresProof: step.evidenceRequired, subItems: [] })) : []);
  const [continuous, setContinuous] = useState(() => isNewTemplate ? [] : continuousDefaults);
  const [reportFields, setReportFields] = useState(() => initialTemplate?.reportFields?.length ? initialTemplate.reportFields.map((field) => field.label) : []);
  const [recommendations, setRecommendations] = useState(() => isNewTemplate ? [] : recommendationDefaults);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState('');
  const initialDeadline = currentAdenDateTime();
  const [selectedEmployeeId, setSelectedEmployeeId] = useState('');
  const [selectedBranchId, setSelectedBranchId] = useState('');
  const [dueDate, setDueDate] = useState(initialDeadline.date);
  const [dueTime, setDueTime] = useState(initialDeadline.time);
  const [dispatchKey] = useState(() => `task-dispatch:${Date.now()}:${Math.random().toString(36).slice(2, 10)}`);
  const activeBranches = branches.filter((branch) => branch.isActive !== false);
  const employeeOptions = employees.filter((employee) => employee.active && Boolean(employee.userId) && (employee.roles ?? []).includes(selectedRole) && (selectedBranchId === '' || (employee.assignments ?? []).some((assignment) => assignment.roleCode === selectedRole && assignment.branchId === selectedBranchId)));

  const updateRow = (id: string, patch: Partial<ScheduleRow>) => setRows((current) => current.map((row) => row.id === id ? { ...row, ...patch } : row));
  const addRow = () => setRows((current) => [...current, { id: key(), timeSlot: '05:00 - 05:30 م', responsibility: '', kpiIndicator: kpis[0], proofRequirement: 'تأكيد الإنجاز', requiresProof: false, subItems: [] }]);
  const removeRow = (id: string) => { if (rows.length <= 1) return; Alert.alert('تأكيد حذف المهمة', 'هل تريد حذف هذه البطاقة بالكامل؟', [{ text: 'إلغاء', style: 'cancel' }, { text: 'حذف', style: 'destructive', onPress: () => setRows((current) => current.filter((row) => row.id !== id)) }]); };
  const addKpi = () => { if (!canManage) return; const value = newKpi.trim(); if (!value || !kpiTargetRowId) return; if (!kpis.includes(value)) setKpis((current) => [...current, value]); setRows((current) => current.map((row) => row.id === kpiTargetRowId ? { ...row, kpiIndicator: value } : row)); setNewKpi(''); setShowKpiInput(false); };
  const addSubItem = (rowId: string) => { const value = (subItemDrafts[rowId] ?? '').trim(); if (!value) return; setRows((current) => current.map((row) => row.id === rowId ? { ...row, subItems: [...row.subItems, value] } : row)); setSubItemDrafts((current) => ({ ...current, [rowId]: '' })); };
  const removeSubItem = (rowId: string, index: number) => Alert.alert('تأكيد حذف البند', 'هل تريد حذف هذا البند من المهمة؟', [{ text: 'إلغاء', style: 'cancel' }, { text: 'حذف', style: 'destructive', onPress: () => setRows((current) => current.map((row) => row.id === rowId ? { ...row, subItems: row.subItems.filter((_, itemIndex) => itemIndex !== index) } : row)) }]);
  const updateList = (setter: (items: string[]) => void, items: string[], index: number, value: string) => setter(items.map((item, itemIndex) => itemIndex === index ? value : item));
  const dispatchError = (cause: unknown) => {
    const message = cause instanceof Error ? cause.message : String(cause ?? '');
    if (message.includes('no_employee_for_role_branch') || message.includes('employee_assignment_invalid')) return 'تعذر الإرسال: الموظف غير مرتبط بهذا الدور أو الفرع.';
    if (message.includes('employee_login_not_linked')) return 'تعذر الإرسال: الموظف لا يملك حساب دخول مرتبطًا.';
    if (message.includes('invalid_task_schedule')) return 'تعذر الإرسال: الموعد النهائي يجب أن يكون بعد وقت بدء المهمة.';
    if (message.includes('invalid_task_branch')) return 'تعذر الإرسال: الفرع المحدد غير نشط أو لا ينتمي إلى المؤسسة.';
    if (message.includes('invalid_task_priority')) return 'تعذر الإرسال: أولوية المهمة غير صالحة.';
    if (message.includes('task_template_not_found')) return 'تعذر الإرسال: لم يتم العثور على القالب المحفوظ أو أنه مؤرشف. أعد فتح المصمم ثم احفظه مرة أخرى.';
    if (message.includes('report_requires_owner_approval') || message.includes('report_form_version_requires_approval')) return 'تعذر الإرسال: نموذج التقرير المرتبط يحتاج اعتمادًا من صاحب المؤسسة قبل إرسال المهمة.';
    if (message.includes('required_report_cannot_be_optional')) return 'تعذر الإرسال: لا يمكن جعل نموذج التقرير الإلزامي اختياريًا.';
    if (message.includes('invalid_report_overrides')) return 'تعذر الإرسال: إعدادات التقرير المرتبط غير صالحة. افتح القالب واحفظه من جديد.';
    if (message.includes('task_template_save_response_invalid')) return 'تعذر الإرسال: لم يرجع حفظ القالب معرفًا صحيحًا. أعد المحاولة بعد تحديث الشاشة.';
    if (message.includes('permission_denied')) return 'تعذر الإرسال: لا تملك صلاحية إدارة المهام.';
    return 'تعذر إرسال المهمة للموظف. تحقق من الاتصال والموظف المحدد ثم حاول مرة أخرى.';
  };
  const addListItem = (setter: (items: string[]) => void, items: string[]) => setter([...items, '']);
  const applyRolePreset = (role: TaskRoleCode) => {
    const preset = rolePresets[role];
    if (!preset) return;
    setRows(presetRows(role) ?? []);
    setContinuous([...preset.continuous]);
    setReportFields([...preset.reports]);
    setRecommendations([...preset.recommendations]);
    setNotice(`تمت إضافة بطاقات ${roles.find(([code]) => code === role)?.[1] ?? 'الدور'} داخل المصمم الحالي. راجعها ثم احفظ الجدول.`);
  };
  const addAccountantMissingCards = () => {
    setRows((current) => [...current, ...accountantMissingRows.filter((candidate) => !current.some((row) => row.responsibility === candidate.responsibility)).map((row) => ({ ...row, id: key(), subItems: [...row.subItems] }))]);
    setNotice('تمت إضافة البطاقات المحاسبية الناقصة داخل المصمم الحالي. راجعها ثم احفظ الجدول.');
  };

  const summary = useMemo(() => `${days} · صباحية ${morning} · استراحة ${breakTime} · مسائية ${evening}`, [breakTime, days, evening, morning]);
  function reportFieldsToDesignerFields(): DesignerField[] {
    return reportFields.map((label, index) => ({
      field_key: `daily_report_${index + 1}`,
      label: label.trim() || `بند التقرير ${index + 1}`,
      description: 'يُعبّأ ضمن التقرير المرتبط بالمهمة.',
      field_type: 'short_text',
      is_required: true,
      repeatable: false,
      sort_order: index,
      options: [],
      validation: {},
      config: {},
    }));
  }
  function buildDraft(): TaskTemplateDraft {
    const description = JSON.stringify({
      __alshaairy_task_designer_v1: true,
      schedule: { days, morning, breakTime, evening, summary },
      rows: rows.map((row) => ({ timeSlot: row.timeSlot, responsibility: row.responsibility.trim(), kpiIndicator: row.kpiIndicator, proofRequirement: row.proofRequirement, requiresProof: row.requiresProof, subItems: row.subItems.filter(Boolean) })),
      continuous: continuous.filter(Boolean),
      reportFields: reportFields.filter(Boolean),
      recommendations: recommendations.filter(Boolean),
    });
    const steps = rows.map((row, index) => ({ id: row.id, title: row.responsibility.trim() || `مهمة تنظيمية ${index + 1}`, instructions: [`الفترة: ${row.timeSlot}`, `مؤشر الأداء: ${row.kpiIndicator}`, `الإثبات: ${row.proofRequirement}`, row.subItems.length ? `البنود الفرعية:\n${row.subItems.map((item) => `- ${item}`).join('\n')}` : ''].filter(Boolean).join('\n'), required: true, evidenceRequired: row.requiresProof, evidenceInstructions: row.proofRequirement }));
    const fields = reportFieldsToDesignerFields();
    return { id: initialTemplate?.id, category: 'admin', subcategory: 'الدوام والمهام اليومية', customSubcategory: '', title: title.trim() || 'الجدول التنظيمي للدوام والمهام اليومية', description, instructions: summary, roleCode: selectedRole, priority: initialTemplate?.priority ?? 'normal', expectedDurationMinutes: initialTemplate?.expectedDurationMinutes ?? null, steps, reports: initialTemplate?.reports ?? [], reportFields: fields, reportRequired: fields.length > 0, isActive: initialTemplate?.isActive ?? true };
  }
  async function dispatchNow(draft: TaskTemplateDraft, employee: EmployeeOption, dueAt: string) {
    setBusy(true); setNotice('');
    try {
      const saveResult = await onSave?.(draft);
      if (!saveResult?.templateId && !draft.id) throw new Error('task_template_save_response_invalid');
      await onSend?.({ ...draft, id: saveResult?.templateId ?? draft.id, reports: saveResult?.reports ?? draft.reports }, employee.id, selectedBranchId || null, dueAt, dispatchKey);
      setNotice(`تم حفظ المهمة وإرسالها إلى ${employee.name}. مفتاح الإرسال محفوظ لمنع التكرار عند ضعف الاتصال.`);
    } catch (cause) { setNotice(dispatchError(cause)); } finally { setBusy(false); }
  }
  function confirmAndDispatch() {
    if (busy) return;
    if (!title.trim()) { setNotice('اكتب عنوان الجدول قبل الإرسال.'); return; }
    if (!rows.length) { setNotice('أضف مهمة واحدة على الأقل قبل الإرسال.'); return; }
    if (rows.some((row) => !row.responsibility.trim())) { setNotice('اكتب وصف كل مهمة أو احذف البطاقة الفارغة.'); return; }
    const employee = employeeOptions.find((item) => item.id === selectedEmployeeId);
    const dueAt = adenDateTimeToIso(dueDate, dueTime);
    if (!employee) { setNotice('اختر الموظف المستلم للمهمة أولاً.'); return; }
    if (!dueAt) { setNotice('أدخل موعداً نهائياً صالحاً للمهمة.'); return; }
    if (new Date(dueAt).getTime() <= Date.now()) { setNotice('اختر موعداً نهائياً مستقبلياً، ثم أعد الإرسال.'); return; }
    const branchName = activeBranches.find((branch) => branch.id === selectedBranchId)?.name ?? 'كل الفروع';
    const reportText = reportFields.length ? `نموذج تقرير مرتبط (${reportFields.length} حقول)` : 'بدون نموذج تقرير مرتبط';
    Alert.alert('مراجعة وتأكيد الإرسال', `المهمة: ${title.trim()}\nالموظف: ${employee.name}\nالفرع: ${branchName}\nالموعد: ${dueDate} ${dueTime}\nالخطوات: ${rows.length}\n${reportText}`, [
      { text: 'إلغاء', style: 'cancel' },
      { text: 'تأكيد الإرسال', onPress: () => void dispatchNow(buildDraft(), employee, dueAt) },
    ]);
  }
  const save = confirmAndDispatch;
  const sendDirectly = confirmAndDispatch;

  return <View style={styles.shell}>
    <ScrollView contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
      <View style={styles.header}><View style={styles.headerCopy}><Text style={styles.eyebrow}>إدارة الدوام والمسؤوليات</Text><Text style={styles.title}>مصمم الجدول التنظيمي للمهام</Text></View><Pressable disabled={busy} style={styles.saveTop} onPress={() => void save()}><Text style={styles.saveText}>{busy ? 'جارٍ الحفظ…' : 'حفظ الجدول'}</Text></Pressable></View>
      {!!notice && <Text style={styles.notice}>{notice}</Text>}
      <View style={styles.card}><Text style={styles.sectionTitle}>إرسال المهمة</Text><Text style={styles.copy}>راجع بيانات المهمة قبل التأكيد، ثم أرسلها إلى الموظف المختار.</Text><Text style={styles.label}>الفرع المستلم</Text><View style={styles.chips}><Pressable style={[styles.chip, selectedBranchId === '' && styles.chipSelected]} onPress={() => { setSelectedBranchId(''); setSelectedEmployeeId(''); }}><Text style={selectedBranchId === '' ? styles.chipTextSelected : styles.chipText}>كل الفروع</Text></Pressable>{activeBranches.map((branch) => <Pressable key={branch.id} style={[styles.chip, selectedBranchId === branch.id && styles.chipSelected]} onPress={() => { setSelectedBranchId(branch.id); setSelectedEmployeeId(''); }}><Text style={selectedBranchId === branch.id ? styles.chipTextSelected : styles.chipText}>{branch.name}</Text></Pressable>)}</View><Text style={styles.label}>الموظف المستلم</Text><View style={styles.chips}>{employeeOptions.map((employee) => <Pressable key={employee.id} style={[styles.chip, selectedEmployeeId === employee.id && styles.chipSelected]} onPress={() => setSelectedEmployeeId(employee.id)}><Text style={selectedEmployeeId === employee.id ? styles.chipTextSelected : styles.chipText}>{employee.name}</Text></Pressable>)}</View>{!employeeOptions.length && <Text style={styles.notice}>لا يوجد موظف نشط مرتبط بهذا الدور والفرع بحساب دخول.</Text>}<Text style={styles.label}>الموعد النهائي</Text><AdenDeadlinePicker date={dueDate} time={dueTime} onChange={(date, time) => { setDueDate(date); setDueTime(time); }} /><Pressable disabled={busy || !selectedEmployeeId} style={styles.primary} onPress={sendDirectly}><Text style={styles.primaryText}>{busy ? 'جارٍ الإرسال…' : 'مراجعة وإرسال المهمة'}</Text></Pressable></View>
      <View style={styles.card}><Text style={styles.sectionTitle}>إعدادات الدوام</Text><TextInput style={styles.input} value={title} onChangeText={setTitle} placeholder="عنوان الجدول التنظيمي" /><Text style={styles.label}>الدور الوظيفي</Text><View style={styles.chips}>{roles.map(([code, label]) => <Pressable key={code} style={[styles.chip, selectedRole === code && styles.chipSelected]} onPress={() => setSelectedRole(code)}><Text style={selectedRole === code ? styles.chipTextSelected : styles.chipText}>{label}</Text></Pressable>)}</View>{rolePresets[selectedRole] && <Pressable style={styles.presetButton} onPress={() => applyRolePreset(selectedRole)}><Text style={styles.presetText}>إضافة بطاقات {roles.find(([code]) => code === selectedRole)?.[1]} الجاهزة</Text></Pressable>}{selectedRole === 'accountant' && <Pressable style={styles.presetButton} onPress={addAccountantMissingCards}><Text style={styles.presetText}>إضافة البطاقات المحاسبية الناقصة</Text></Pressable>}<TextInput style={styles.input} value={days} onChangeText={setDays} placeholder="أيام العمل" /><View style={styles.threeColumns}><TextInput style={styles.input} value={morning} onChangeText={setMorning} placeholder="الفترة الصباحية" /><TextInput style={styles.input} value={breakTime} onChangeText={setBreakTime} placeholder="فترة الاستراحة" /><TextInput style={styles.input} value={evening} onChangeText={setEvening} placeholder="الفترة المسائية" /></View></View>
      <View style={styles.card}><View style={styles.sectionHeader}><Text style={styles.sectionTitle}>توزيع المهام حسب ساعات الدوام</Text><Pressable style={styles.addButton} onPress={addRow}><Text style={styles.addText}>+ إضافة صف</Text></Pressable></View>{rows.map((row, index) => <View style={styles.rowCard} key={row.id}><View style={styles.rowHeader}><Text style={styles.rowTitle}>المهمة {index + 1}</Text><Pressable onPress={() => removeRow(row.id)}><Text style={styles.deleteText}>حذف</Text></Pressable></View><TextInput style={styles.input} value={row.timeSlot} onChangeText={(value) => updateRow(row.id, { timeSlot: value })} placeholder="الفترة الزمنية" /><TextInput style={[styles.input, styles.multiline]} value={row.responsibility} onChangeText={(value) => updateRow(row.id, { responsibility: value })} placeholder="اكتب المهمة والمسؤولية" multiline /><Text style={styles.label}>البنود الفرعية</Text>{row.subItems.map((item, itemIndex) => <View style={styles.subItemRow} key={`${row.id}-sub-${itemIndex}`}><Text style={styles.bullet}>•</Text><Text style={styles.subItemText}>{item}</Text><Pressable onPress={() => removeSubItem(row.id, itemIndex)}><Text style={styles.deleteText}>حذف</Text></Pressable></View>)}<View style={styles.kpiAddRow}><TextInput style={styles.input} value={subItemDrafts[row.id] ?? ""} onChangeText={(value) => setSubItemDrafts((current) => ({ ...current, [row.id]: value }))} placeholder="إضافة بند فرعي" /><Pressable style={styles.addButton} onPress={() => addSubItem(row.id)}><Text style={styles.addText}>+ إضافة</Text></Pressable></View><View style={styles.sectionHeader}><Text style={styles.label}>مؤشر الأداء</Text>{canManage && <Pressable style={styles.addButton} onPress={() => { setKpiTargetRowId(row.id); setShowKpiInput(true); }}><Text style={styles.addText}>+ إضافة مؤشر</Text></Pressable>}</View>{canManage && showKpiInput && kpiTargetRowId === row.id && <View style={styles.kpiAddRow}><TextInput autoFocus style={styles.input} value={newKpi} onChangeText={setNewKpi} placeholder="اسم مؤشر الأداء الجديد" /><Pressable style={styles.addButton} onPress={addKpi}><Text style={styles.addText}>إضافة</Text></Pressable></View>}<View style={styles.chips}>{kpis.map((kpi) => <Pressable key={kpi} style={[styles.chip, row.kpiIndicator === kpi && styles.chipSelected]} onPress={() => updateRow(row.id, { kpiIndicator: kpi })}><Text style={row.kpiIndicator === kpi ? styles.chipTextSelected : styles.chipText}>{kpi}</Text></Pressable>)}</View><TextInput style={styles.input} value={row.proofRequirement} onChangeText={(value) => updateRow(row.id, { proofRequirement: value })} placeholder="الإثبات أو الشرط" /><Pressable style={[styles.proofToggle, row.requiresProof && styles.proofToggleActive]} onPress={() => updateRow(row.id, { requiresProof: !row.requiresProof })}><Text style={row.requiresProof ? styles.proofTextActive : styles.proofText}>{row.requiresProof ? 'الإثبات مطلوب ✓' : 'الإثبات اختياري'}</Text></Pressable></View>)}</View>
      <EditableList title="المهام المستمرة طوال الدوام" items={continuous} icon="↻" onChange={(index, value) => updateList(setContinuous, continuous, index, value)} onAdd={() => addListItem(setContinuous, continuous)} />
      <EditableList title="بنود التقرير اليومي للموظف" items={reportFields} icon="✓" onChange={(index, value) => updateList(setReportFields, reportFields, index, value)} onAdd={() => addListItem(setReportFields, reportFields)} />
      <EditableList title="التوصيات والضوابط الإدارية" items={recommendations} icon="◆" onChange={(index, value) => updateList(setRecommendations, recommendations, index, value)} onAdd={() => addListItem(setRecommendations, recommendations)} />
      <View style={styles.actions}><Pressable disabled={busy} style={styles.primary} onPress={() => void save()}><Text style={styles.primaryText}>{busy ? 'جارٍ الحفظ…' : 'حفظ الجدول التنظيمي'}</Text></Pressable><Pressable style={styles.secondary} onPress={() => void onList?.()}><Text style={styles.secondaryText}>عرض الجداول المحفوظة</Text></Pressable></View>
    </ScrollView>
  </View>;
}

function EditableList({ title, items, icon, onChange, onAdd }: { title: string; items: string[]; icon: string; onChange: (index: number, value: string) => void; onAdd: () => void }) {
  return <View style={styles.card}><View style={styles.sectionHeader}><Text style={styles.sectionTitle}>{title}</Text><Text style={styles.icon}>{icon}</Text></View>{items.map((item, index) => <View style={styles.listRow} key={`${title}-${index}`}><Text style={styles.bullet}>•</Text><TextInput style={[styles.input, styles.listInput]} value={item} onChangeText={(value) => onChange(index, value)} placeholder="أدخل البند" /></View>)}<Pressable style={styles.addButton} onPress={onAdd}><Text style={styles.addText}>+ إضافة بند</Text></Pressable></View>;
}

const styles = StyleSheet.create({
  shell: { flex: 1, backgroundColor: '#f5f8f9' }, content: { gap: 12, padding: 12, paddingBottom: 28 }, header: { flexDirection: 'row-reverse', alignItems: 'center', justifyContent: 'space-between', gap: 10 }, headerCopy: { flex: 1 }, eyebrow: { color: '#718394', textAlign: 'right', fontSize: 12, fontWeight: '800' }, title: { color: '#17324d', textAlign: 'right', fontSize: 21, fontWeight: '900', marginTop: 3 }, saveTop: { minHeight: 42, borderRadius: 10, backgroundColor: '#17324d', paddingHorizontal: 13, alignItems: 'center', justifyContent: 'center' }, saveText: { color: '#fff', fontWeight: '900' }, notice: { color: '#23633c', backgroundColor: '#e8f5eb', borderRadius: 10, padding: 11, textAlign: 'right' }, card: { backgroundColor: '#fff', borderRadius: 14, borderWidth: 1, borderColor: '#dce6e9', padding: 13, gap: 10 }, sectionHeader: { flexDirection: 'row-reverse', alignItems: 'center', justifyContent: 'space-between', gap: 8 }, sectionTitle: { color: '#17324d', fontSize: 16, fontWeight: '900', textAlign: 'right' }, copy: { color: '#52687a', textAlign: 'right', lineHeight: 21 }, label: { color: '#29475a', fontWeight: '800', textAlign: 'right' }, input: { minHeight: 44, flex: 1, borderWidth: 1, borderColor: '#d6e0e4', borderRadius: 9, paddingHorizontal: 10, paddingVertical: 8, textAlign: 'right', color: '#17324d', backgroundColor: '#fbfcfc' }, multiline: { minHeight: 70, textAlignVertical: 'top' }, threeColumns: { flexDirection: 'row-reverse', gap: 7 }, chips: { flexDirection: 'row-reverse', flexWrap: 'wrap', gap: 6 }, chip: { borderWidth: 1, borderColor: '#cbd8de', borderRadius: 18, paddingHorizontal: 10, paddingVertical: 8, backgroundColor: '#fff' }, chipSelected: { backgroundColor: '#17324d', borderColor: '#17324d' }, chipText: { color: '#39556a', fontSize: 12 }, chipTextSelected: { color: '#fff', fontWeight: '800', fontSize: 12 }, addButton: { minHeight: 40, borderRadius: 9, borderWidth: 1, borderColor: '#cbd8de', paddingHorizontal: 11, alignItems: 'center', justifyContent: 'center', alignSelf: 'flex-start' }, addText: { color: '#17324d', fontWeight: '900' }, presetButton: { minHeight: 44, borderRadius: 10, backgroundColor: '#e8f1f6', borderWidth: 1, borderColor: '#b9cbd2', alignItems: 'center', justifyContent: 'center', padding: 10 }, presetText: { color: '#17324d', fontWeight: '900', textAlign: 'right' }, rowCard: { gap: 8, backgroundColor: '#f8fafb', borderRadius: 11, borderWidth: 1, borderColor: '#e2eaed', padding: 10 }, rowHeader: { flexDirection: 'row-reverse', alignItems: 'center', justifyContent: 'space-between' }, rowTitle: { color: '#17324d', fontWeight: '900' }, deleteText: { color: '#a8443d', fontWeight: '800' }, proofToggle: { minHeight: 40, borderRadius: 9, borderWidth: 1, borderColor: '#cbd8de', alignItems: 'center', justifyContent: 'center' }, proofToggleActive: { backgroundColor: '#eff8f2', borderColor: '#8bb5a0' }, proofText: { color: '#39556a', fontWeight: '800' }, proofTextActive: { color: '#285844', fontWeight: '900' }, kpiAddRow: { flexDirection: 'row-reverse', alignItems: 'center', gap: 7 }, subItemRow: { flexDirection: 'row-reverse', alignItems: 'center', gap: 7, backgroundColor: '#fff', borderRadius: 8, paddingHorizontal: 8, paddingVertical: 5 }, subItemText: { flex: 1, color: '#39556a', textAlign: 'right' }, listRow: { flexDirection: 'row-reverse', alignItems: 'center', gap: 7 }, listInput: { flex: 1 }, bullet: { color: '#b17c12', fontSize: 22, fontWeight: '900' }, icon: { color: '#b17c12', fontSize: 20, fontWeight: '900' }, actions: { flexDirection: 'row-reverse', gap: 8 }, primary: { flex: 1, minHeight: 48, borderRadius: 10, backgroundColor: '#17324d', alignItems: 'center', justifyContent: 'center', padding: 11 }, primaryText: { color: '#fff', fontWeight: '900' }, secondary: { minHeight: 48, borderRadius: 10, backgroundColor: '#e9f0f4', alignItems: 'center', justifyContent: 'center', padding: 11 }, secondaryText: { color: '#17324d', fontWeight: '900' },
});
