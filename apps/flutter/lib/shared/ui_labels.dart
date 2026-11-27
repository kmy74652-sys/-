String uiStatusLabel(String value) => const {
      'new': 'جديدة',
      'pending': 'جديدة',
      'received': 'مستلمة',
      'in_progress': 'قيد التنفيذ',
      'on_hold': 'معلّقة',
      'report_submitted': 'بانتظار المراجعة',
      'submitted': 'بانتظار المراجعة',
      'needs_revision': 'يحتاج تعديلًا',
      'returned': 'يحتاج تعديلًا',
      'rejected': 'مرفوضة',
      'completed': 'مكتملة',
      'approved': 'معتمدة',
      'completed_approved': 'مكتملة ومعتمدة',
      'late': 'متأخرة',
      'cancelled': 'ملغاة',
      'active': 'نشطة',
      'inactive': 'غير نشطة',
      'expired': 'منتهية',
      'terminated': 'منتهية',
      'draft': 'مسودة',
      'reviewed': 'تمت مراجعتها',
      'present': 'حاضر',
      'absent': 'غائب',
      'leave': 'إجازة',
      'holiday': 'عطلة',
    }[value.trim()] ?? 'غير محددة';

String uiPriorityLabel(String value) => const {
      'low': 'منخفضة',
      'normal': 'عادية',
      'high': 'عالية',
      'urgent': 'عاجلة',
      'important': 'مهمة',
      'critical': 'حرجة',
    }[value.trim()] ?? 'غير محددة';

String uiRoleLabel(String value) => const {
      'owner': 'صاحب المؤسسة',
      'admin_followup': 'المدير التنفيذي',
      'accountant': 'المحاسب',
      'warehouse_keeper': 'أمين المخازن',
      'warehouse_worker': 'عمال التحميل',
      'manager': 'مدير',
      'supervisor': 'مشرف',
      'employee': 'موظف',
      'admin': 'مسؤول النظام',
    }[value.trim()] ?? 'غير محدد';

String uiCurrencyLabel(String value) => const {
      'YER': 'ريال يمني',
      'SAR': 'ريال سعودي',
      'USD': 'دولار أمريكي',
      'EUR': 'يورو',
    }[value.trim().toUpperCase()] ?? 'عملة غير محددة';

String uiActivityLabel(String value) => const {
      'started': 'بدأ التنفيذ',
      'task_opened': 'تم فتح المهمة',
      'task_started': 'بدأ تنفيذ المهمة',
      'task_submitted': 'تم إرسال المهمة للمراجعة',
      'task_status_updated': 'تم تحديث حالة المهمة',
      'report_submitted': 'تم إرسال التقرير',
      'report_returned': 'تم رفض التقرير وإعادته',
      'report_approved': 'تم اعتماد التقرير',
      'report_form_published': 'تم نشر نموذج التقرير',
      'report_form_updated': 'تم تحديث نموذج التقرير',
      'unified_task_created': 'تم إنشاء مهام الجدول الموحد',
      'unified_task_updated': 'تم تحديث مهام الجدول الموحد',
    }[value.trim()] ?? 'نشاط إداري';

class UiLabels {
  const UiLabels._();

  static String reportStatus(String value) => const {
        'draft': 'مسودة',
        'submitted': 'بانتظار المراجعة',
        'reviewed': 'بانتظار الاعتماد',
        'approved': 'معتمدة',
        'returned': 'يحتاج تعديلًا',
        'rejected': 'مرفوضة',
      }[value.trim()] ?? 'غير محددة';
}
