import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../shared/app_shell.dart';

class RoleDailyReportScreen extends StatefulWidget {
  const RoleDailyReportScreen({super.key});

  @override
  State<RoleDailyReportScreen> createState() => _RoleDailyReportScreenState();
}

class _RoleDailyReportScreenState extends State<RoleDailyReportScreen> {
  static const _configs = <String, _RoleConfig>{
    'accountant': _RoleConfig('التقرير اليومي للمحاسب', [
      _RoleField('sales_orders', 'عدد فواتير مبيعات الجملة وطلبات العملاء المستلمة والمنفذة'),
      _RoleField('collected_amounts', 'إجمالي المبالغ المحصلة'),
      _RoleField('purchase_invoices', 'عدد فواتير المشتريات المسجلة'),
      _RoleField('matched_suppliers', 'أسماء الموردين الذين تمت مطابقة حساباتهم', longText: true),
      _RoleField('handed_accounts', 'عدد الحسابات المسلمة للمتابعة'),
      _RoleField('delayed_work', 'الأعمال التي لم تنجز وأسباب التأخير', longText: true),
    ]),
    'warehouse_keeper': _RoleConfig('التقرير اليومي لأمين المخازن', [
      _RoleField('issued_orders', 'عدد أوامر الصرف المخزني المنفذة وتسليم الفواتير للمحاسب'),
      _RoleField('received_purchases', 'عدد توريدات المشتريات المستلمة والتحقق منها'),
      _RoleField('counted_items', 'الأصناف التي تم جردها أو رصد نقص فيها', longText: true),
      _RoleField('warehouse_notes', 'الفروقات أو الملاحظات المخزنية وأسبابها', longText: true),
    ]),
    'warehouse_worker': _RoleConfig('التقرير اليومي لعمال التحميل', [
      _RoleField('prepared_orders', 'عدد الطلبات والطرود التي تم تجهيزها أو تحميلها'),
      _RoleField('damage_status', 'حالة التلف أو الكسر إن وجدت', longText: true),
      _RoleField('warehouse_organization', 'ملاحظات تنظيم المستودع وأسباب أي تأخير', longText: true),
    ]),
    'admin_followup': _RoleConfig('تقرير المتابعة التنفيذية اليومي', [
      _RoleField('team_commitment', 'ملخص التزام الفروع والفرق بالمهام اليومية', longText: true),
      _RoleField('delays_priorities', 'أبرز التأخيرات أو حالات تعارض الأولويات ومعالجتها', longText: true),
      _RoleField('management_recommendations', 'التوصيات المرفوعة للإدارة', longText: true),
    ]),
    'owner': _RoleConfig('ملخص الاعتمادات والقرارات الإدارية', [
      _RoleField('daily_decisions', 'ملخص القرارات والاعتمادات المتخذة اليوم', longText: true),
      _RoleField('performance_notes', 'ملاحظات الإدارة على الأداء والمؤشرات', longText: true),
    ]),
  };

  final _client = Supabase.instance.client;
  final _values = <String, TextEditingController>{};
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _notice;
  String? _roleCode;
  String? _branchId;
  String? _employeeName;
  Map<String, dynamic>? _today;

  String get _todayDate {
    final local = DateTime.now().toUtc().add(const Duration(hours: 3));
    return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  _RoleConfig get _config => _configs[_roleCode] ?? _configs.values.first;
  bool get _locked => _today?['status'] == 'submitted' || _today?['status'] == 'approved';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _values.values) controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await _client.rpc('mobile_my_profile');
      final root = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      final employee = root['employee'];
      if (employee is! Map) throw Exception('لا يوجد ملف موظف نشط مرتبط بهذا الحساب.');
      final profile = Map<String, dynamic>.from(employee);
      final roles = profile['roles'] is List ? (profile['roles'] as List) : const [];
      for (final role in roles.whereType<Map>()) {
        final code = (role['code'] ?? role['role_code'] ?? '').toString();
        if (_configs.containsKey(code)) {
          _roleCode = code;
          _branchId = (role['branch_id'] ?? role['branchId'])?.toString();
          break;
        }
      }
      _employeeName = (profile['fullName'] ?? profile['full_name'] ?? '').toString();
      if (_roleCode == null) throw Exception('لا يوجد دور يدعم التقرير اليومي لهذا الحساب.');
      final rows = await _client.from('employee_role_reports')
          .select('id,report_date,report_title,values,status,review_note')
          .eq('role_code', _roleCode!)
          .eq('report_date', _todayDate)
          .order('submitted_at', ascending: false)
          .limit(1);
      final list = (rows as List).whereType<Map>().toList();
      if (list.isNotEmpty) {
        _today = Map<String, dynamic>.from(list.first);
        final values = _today?['values'];
        if (values is Map) {
          for (final entry in values.entries) {
            _controller(entry.key.toString()).text = entry.value?.toString() ?? '';
          }
        }
      } else {
        _today = null;
      }
    } catch (error) {
      _error = error.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  TextEditingController _controller(String key) => _values.putIfAbsent(key, TextEditingController.new);

  Future<void> _submit() async {
    if (_roleCode == null || _locked || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      final values = <String, String>{
        for (final field in _config.fields) field.key: _controller(field.key).text.trim(),
      };
      await _client.rpc('mobile_submit_employee_role_report', params: {
        'p_role_code': _roleCode,
        'p_branch_id': _branchId,
        'p_report_date': _todayDate,
        'p_report_title': _config.title,
        'p_values': values,
      });
      if (!mounted) return;
      setState(() => _notice = 'تم إرسال التقرير للإدارة للمراجعة.');
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = 'تعذر إرسال التقرير. تحقق من الاتصال وصلاحية الدور ثم حاول مجددًا.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppShell(
        title: 'التقرير اليومي',
        subtitle: _employeeName == null || _employeeName!.isEmpty
            ? 'إرسال تقرير الدور اليومي'
            : '$_employeeName · ${_config.title}',
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Text(_config.title, textAlign: TextAlign.right,
                        style: const TextStyle(color: AppColors.navy, fontSize: 19, fontWeight: FontWeight.bold)),
                    Text('تاريخ التقرير: $_todayDate', textAlign: TextAlign.right,
                        style: const TextStyle(color: Colors.black54)),
                    if (_today?['status'] == 'returned')
                      _message('أُعيد التقرير للتعديل${(_today?['review_note'] ?? '').toString().trim().isEmpty ? '' : ': ${_today?['review_note']}', warning: true),
                    if (_locked)
                      _message(_today?['status'] == 'approved' ? 'تم اعتماد تقرير اليوم.' : 'تم إرسال تقرير اليوم وبانتظار المراجعة.'),
                    if (_error != null) _message(_error!, warning: true),
                    if (_notice != null) _message(_notice!),
                    const SizedBox(height: 8),
                    for (final field in _config.fields) ...[
                      TextField(
                        controller: _controller(field.key),
                        enabled: !_locked,
                        textAlign: TextAlign.right,
                        maxLines: field.longText ? 4 : 1,
                        decoration: InputDecoration(labelText: field.label, border: const OutlineInputBorder()),
                      ),
                      const SizedBox(height: 10),
                    ],
                    FilledButton.icon(
                      onPressed: _locked || _saving ? null : _submit,
                      icon: const Icon(Icons.send_outlined),
                      label: Text(_saving ? 'جارٍ الإرسال…' : 'إرسال التقرير للإدارة'),
                    ),
                  ],
                ),
        ),
      );

  Widget _message(String text, {bool warning = false}) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: warning ? const Color(0xFFFFF1DC) : const Color(0xFFE8F5EB),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text, textAlign: TextAlign.right),
      );
}

class _RoleConfig {
  const _RoleConfig(this.title, this.fields);
  final String title;
  final List<_RoleField> fields;
}

class _RoleField {
  const _RoleField(this.key, this.label, {this.longText = false});
  final String key;
  final String label;
  final bool longText;
}
