import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/app_shell.dart';
import '../../core/theme.dart';

class HrScreen extends StatefulWidget {
  const HrScreen({super.key});
  @override
  State<HrScreen> createState() => _HrScreenState();
}

class _HrScreenState extends State<HrScreen> {
  final _client = Supabase.instance.client;
  static const _tabs = ['العقود', 'الدوام', 'الحضور', 'الرواتب'];
  int _tab = 0;
  bool _loading = true, _busy = false, _canManage = false;
  String? _error, _notice, _organizationId;
  List<Map<String, dynamic>> _members = [],
      _contracts = [],
      _schedules = [],
      _attendance = [],
      _periods = [];
  String? _memberId, _periodId;
  final Map<String, TextEditingController> _c = {};
  TextEditingController field(String key, String initial) =>
      _c.putIfAbsent(key, () => TextEditingController(text: initial));

  @override
  void initState() {
    super.initState();
    for (final e in {
      'contractNo': '',
      'contractType': 'employment',
      'startDate': DateTime.now().toIso8601String().substring(0, 10),
      'endDate': '',
      'salary': '',
      'duties': '',
      'scheduleName': 'الدوام الأساسي',
      'startTime': '08:00',
      'endTime': '17:00',
      'breakMinutes': '60',
      'workDate': DateTime.now().toIso8601String().substring(0, 10),
      'attendanceStatus': 'present',
      'checkIn': '08:00',
      'checkOut': '17:00',
      'note': '',
      'periodStart': '${DateTime.now().toIso8601String().substring(0, 7)}-01',
      'periodEnd': DateTime.now().toIso8601String().substring(0, 10),
      'base': '',
      'additions': '0',
      'deductions': '0'
    }.entries) {
      field(e.key, e.value);
    }
    _load();
  }

  @override
  void dispose() {
    for (final item in _c.values) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted)
      setState(() {
        _loading = true;
        _error = null;
      });
    try {
      final result = await _client.rpc('mobile_my_profile');
      final root = result is Map ? result : const <dynamic, dynamic>{};
      final employee = root['employee'];
      if (employee is! Map)
        throw Exception(
            'الحساب غير مرتبط بملف موظف نشط. تواصل مع مسؤول النظام.');
      final org = employee['institutionId'] ?? employee['institution_id'];
      if (org == null || org.toString().isEmpty)
        throw Exception('ملف الموظف لا يتضمن المؤسسة.');
      final permissions = employee['permissions'];
      _organizationId = org.toString();
      _canManage = permissions is List &&
          permissions.map((e) => e.toString()).contains('employee_hr.manage');
      final results = await Future.wait([
        _client
            .from('organization_memberships')
            .select('id,display_name,employee_no')
            .eq('organization_id', _organizationId!)
            .eq('is_active', true)
            .order('display_name')
            .limit(500),
        _client
            .from('employee_contracts')
            .select(
                'id,membership_id,contract_no,contract_type,status,start_date,end_date,base_salary,salary_currency,pay_frequency,duties')
            .eq('organization_id', _organizationId!)
            .order('start_date', ascending: false)
            .limit(100),
        _client
            .from('employee_work_schedules')
            .select(
                'id,membership_id,name,timezone,work_days,start_time,end_time,break_minutes,effective_from,effective_to,is_active')
            .eq('organization_id', _organizationId!)
            .order('effective_from', ascending: false)
            .limit(100),
        _client
            .from('employee_attendance_records')
            .select(
                'id,membership_id,work_date,status,check_in_at,check_out_at,note')
            .eq('organization_id', _organizationId!)
            .order('work_date', ascending: false)
            .limit(100),
        _client
            .from('employee_payroll_periods')
            .select('id,period_start,period_end,status')
            .eq('organization_id', _organizationId!)
            .order('period_start', ascending: false)
            .limit(50),
      ]);
      _members = _mapRows(results[0]);
      _contracts = _mapRows(results[1]);
      _schedules = _mapRows(results[2]);
      _attendance = _mapRows(results[3]);
      _periods = _mapRows(results[4]);
      final ids = _periods.map((p) => p['id'].toString()).toList();
      if (ids.isNotEmpty) {
        final entries = await _client
            .from('employee_payroll_entries')
            .select(
                'period_id,membership_id,base_amount,additions,deductions,net_amount,currency')
            .inFilter('period_id', ids)
            .limit(500);
        for (final p in _periods) {
          p['entries'] = _mapRows(entries)
              .where((e) => e['period_id'] == p['id'])
              .toList();
        }
      } else {
        for (final p in _periods) {
          p['entries'] = [];
        }
      }
      if (_memberId == null || !_members.any((m) => m['id'] == _memberId))
        _memberId = _members.isEmpty ? null : _members.first['id'].toString();
      if (_periodId != null &&
          !_periods.any((p) => p['id'].toString() == _periodId))
        _periodId = null;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _mapRows(dynamic value) =>
      (value as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  String _value(dynamic value) =>
      value == null || value.toString().isEmpty ? '—' : value.toString();
  String _memberName(dynamic id) {
    for (final m in _members) {
      if (m['id'] == id) return _value(m['display_name']);
    }
    return 'موظف غير محدد';
  }

  String _text(String key) => _c[key]!.text.trim();
  double? _number(String key) {
    final v = _text(key);
    return v.isEmpty ? null : double.tryParse(v);
  }

  bool _validDate(String s) {
    final d = DateTime.tryParse(s);
    return d != null && d.toIso8601String().substring(0, 10) == s;
  }

  Future<void> _run(String success, Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
      if (mounted) {
        setState(() => _notice = success);
      }
      await _load();
    } catch (e) {
      if (mounted)
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _contract() async {
    final id = _memberId;
    final start = _text('startDate');
    final end = _text('endDate');
    final salary = _number('salary');
    if (id == null ||
        _text('contractNo').isEmpty ||
        !_validDate(start) ||
        (end.isNotEmpty && (!_validDate(end) || end.compareTo(start) < 0)) ||
        (_text('salary').isNotEmpty && (salary == null || salary < 0))) {
      setState(() => _error = 'تحقق من الموظف ورقم العقد والتواريخ والراتب.');
      return;
    }
    await _run('تم حفظ عقد الموظف.', () async {
      await _client.rpc('create_employee_contract', params: {
        'p_organization_id': _organizationId,
        'p_membership_id': id,
        'p_contract_no': _text('contractNo'),
        'p_contract_type': _text('contractType'),
        'p_start_date': start,
        'p_end_date': end.isEmpty ? null : end,
        'p_base_salary': salary,
        'p_currency': 'SAR',
        'p_pay_frequency': 'monthly',
        'p_duties': _text('duties')
            .split('\n')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList()
      });
    });
  }

  Future<void> _schedule() async {
    final id = _memberId;
    final start = _text('startDate');
    final end = _text('endDate');
    final mins = int.tryParse(_text('breakMinutes'));
    if (id == null ||
        _text('scheduleName').isEmpty ||
        !_validDate(start) ||
        (end.isNotEmpty && (!_validDate(end) || end.compareTo(start) < 0)) ||
        mins == null ||
        mins < 0 ||
        mins > 720 ||
        !_time(_text('startTime')) ||
        !_time(_text('endTime')) ||
        _timeMinutes(_text('endTime'))! <= _timeMinutes(_text('startTime'))!) {
      setState(() =>
          _error = 'تحقق من اسم الجدول والتواريخ والأوقات ودقائق الاستراحة.');
      return;
    }
    await _run('تم حفظ جدول الدوام.', () async {
      await _client.rpc('create_employee_work_schedule', params: {
        'p_organization_id': _organizationId,
        'p_membership_id': id,
        'p_name': _text('scheduleName'),
        'p_timezone': 'Asia/Aden',
        'p_work_days': [6, 0, 1, 2, 3, 4],
        'p_start_time': _text('startTime'),
        'p_end_time': _text('endTime'),
        'p_break_minutes': mins,
        'p_effective_from': start,
        'p_effective_to': end.isEmpty ? null : end
      });
    });
  }

  bool _time(String v) => RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(v);
  int? _timeMinutes(String v) {
    if (!_time(v)) return null;
    final parts = v.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }
  Future<void> _recordAttendance() async {
    final id = _memberId;
    final date = _text('workDate');
    final status = _text('attendanceStatus');
    final ci = _text('checkIn'), co = _text('checkOut');
    if (id == null ||
        !_validDate(date) ||
        !['present', 'absent', 'late', 'leave', 'holiday', 'incomplete'].contains(status) ||
        (ci.isNotEmpty && !_time(ci)) ||
        (co.isNotEmpty && !_time(co)) ||
        (ci.isNotEmpty && co.isNotEmpty &&
            _timeMinutes(co)! < _timeMinutes(ci)!) ) {
      setState(() => _error =
          'تحقق من التاريخ والحالة (present/absent/late/leave/holiday/incomplete) والأوقات.');
      return;
    }
    await _run('تم تسجيل الحضور.', () async {
      await _client.rpc('record_employee_attendance', params: {
        'p_organization_id': _organizationId,
        'p_membership_id': id,
        'p_work_date': date,
        'p_status': status,
        'p_check_in_at': ci.isEmpty
            ? null
            : DateTime.parse('${date}T$ci:00').toUtc().toIso8601String(),
        'p_check_out_at': co.isEmpty
            ? null
            : DateTime.parse('${date}T$co:00').toUtc().toIso8601String(),
        'p_note': _text('note')
      });
    });
  }

  Future<void> _period() async {
    final start = _text('periodStart'), end = _text('periodEnd');
    if (!_validDate(start) || !_validDate(end) || start.compareTo(end) > 0) {
      setState(() => _error = 'أدخل تاريخي بداية ونهاية صحيحين للفترة.');
      return;
    }
    await _run('تم إنشاء فترة الرواتب.', () async {
      await _client.rpc('create_employee_payroll_period', params: {
        'p_organization_id': _organizationId,
        'p_period_start': start,
        'p_period_end': end
      });
    });
  }

  Future<void> _payrollEntry() async {
    final id = _memberId;
    final period = _periodId;
    final base = _number('base'),
        additions = _number('additions'),
        deductions = _number('deductions');
    if (id == null ||
        period == null ||
        base == null ||
        additions == null ||
        deductions == null ||
        base < 0 ||
        additions < 0 ||
        deductions < 0) {
      setState(() => _error = 'اختر فترة وموظفًا وأدخل مبالغ صحيحة غير سالبة.');
      return;
    }
    await _run('تم حفظ قيد الراتب.', () async {
      await _client.rpc('upsert_employee_payroll_entry', params: {
        'p_organization_id': _organizationId,
        'p_period_id': period,
        'p_membership_id': id,
        'p_base_amount': base,
        'p_additions': additions,
        'p_deductions': deductions,
        'p_currency': 'SAR',
        'p_note': _text('note')
      });
    });
  }

  Widget _field(String key, String label,
          {String? hint, TextInputType? type, int lines = 1}) =>
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: TextField(
              controller: field(key, ''),
              keyboardType: type,
              maxLines: lines,
              textDirection: TextDirection.rtl,
              decoration: InputDecoration(
                  labelText: label,
                  hintText: hint,
                  border: const OutlineInputBorder(),
                  isDense: true)));
  Widget _action(String label, VoidCallback onTap) => SizedBox(
      width: double.infinity,
      child: FilledButton(
          onPressed: _busy ? null : onTap,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(label)));
  Widget _memberPicker() => DropdownButtonFormField<String>(
      value: _memberId,
      isExpanded: true,
      decoration: const InputDecoration(
          labelText: 'الموظف', border: OutlineInputBorder()),
      items: _members
          .map((m) => DropdownMenuItem(
              value: m['id'].toString(),
              child: Text(
                  '${_value(m['display_name'])}${m['employee_no'] == null ? '' : ' · ${m['employee_no']}'}',
                  textDirection: TextDirection.rtl)))
          .toList(),
      onChanged: _busy ? null : (v) => setState(() => _memberId = v));
  Widget _card(String title, List<Widget> children) => Card(
      child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title,
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navy)),
            const SizedBox(height: 10),
            ...children
          ])));
  Widget _entry(String title, String detail) => Card(
      child: ListTile(
          title: Text(title, textAlign: TextAlign.right),
          subtitle: Text(detail,
              textAlign: TextAlign.right, textDirection: TextDirection.rtl)));
  Widget _form() {
    if (!_canManage)
      return _card('عرض فقط', [
        const Text(
            'لا تملك صلاحية employee_hr.manage. يمكنك الاطلاع على السجلات التي تسمح بها سياسات الوصول.',
            textAlign: TextAlign.right)
      ]);
    if (_members.isEmpty)
      return _card('لا يوجد موظفون نشطون', [
        const Text('تعذر تقديم نماذج الموارد البشرية دون عضو نشط في المؤسسة.',
            textAlign: TextAlign.right)
      ]);
    if (_tab == 0)
      return _card('إضافة عقد موظف', [
        _memberPicker(),
        _field('contractNo', 'رقم العقد'),
        _field('contractType', 'نوع العقد', hint: 'employment'),
        _field('startDate', 'تاريخ البداية', hint: 'YYYY-MM-DD'),
        _field('endDate', 'تاريخ النهاية (اختياري)', hint: 'YYYY-MM-DD'),
        _field('salary', 'الراتب الأساسي (SAR)',
            type: const TextInputType.numberWithOptions(decimal: true)),
        _field('duties', 'المهام والمسؤوليات (كل مسؤولية في سطر)', lines: 3),
        _action('حفظ العقد', _contract)
      ]);
    if (_tab == 1)
      return _card('جدول الدوام', [
        _memberPicker(),
        _field('scheduleName', 'اسم الجدول'),
        _field('startDate', 'تاريخ السريان', hint: 'YYYY-MM-DD'),
        _field('endDate', 'نهاية السريان (اختياري)', hint: 'YYYY-MM-DD'),
        _field('startTime', 'بداية الدوام', hint: '08:00'),
        _field('endTime', 'نهاية الدوام', hint: '17:00'),
        _field('breakMinutes', 'دقائق الاستراحة', type: TextInputType.number),
        _action('حفظ جدول الدوام', _schedule)
      ]);
    if (_tab == 2)
      return _card('تسجيل حضور أو انصراف', [
        _memberPicker(),
        _field('workDate', 'تاريخ الدوام', hint: 'YYYY-MM-DD'),
        _field('attendanceStatus', 'الحالة',
            hint: 'present / absent / late / leave / holiday'),
        _field('checkIn', 'وقت الدخول (اختياري)', hint: '08:00'),
        _field('checkOut', 'وقت الخروج (اختياري)', hint: '17:00'),
        _field('note', 'ملاحظة', lines: 2),
        _action('حفظ سجل الحضور', _recordAttendance)
      ]);
    return _card('إدارة الرواتب', [
      _field('periodStart', 'بداية الفترة', hint: 'YYYY-MM-DD'),
      _field('periodEnd', 'نهاية الفترة', hint: 'YYYY-MM-DD'),
      _action('إنشاء فترة الرواتب', _period),
      const Divider(),
      DropdownButtonFormField<String>(
          value: _periodId,
          decoration: const InputDecoration(
              labelText: 'فترة الرواتب', border: OutlineInputBorder()),
          items: _periods
              .map((p) => DropdownMenuItem(
                  value: p['id'].toString(),
                  child: Text(
                      '${_value(p['period_start'])} إلى ${_value(p['period_end'])} · ${_value(p['status'])}',
                      textDirection: TextDirection.rtl)))
              .toList(),
          onChanged: (v) => setState(() => _periodId = v)),
      const SizedBox(height: 8),
      _memberPicker(),
      _field('base', 'الراتب الأساسي (SAR)',
          type: const TextInputType.numberWithOptions(decimal: true)),
      _field('additions', 'الإضافات',
          type: const TextInputType.numberWithOptions(decimal: true)),
      _field('deductions', 'الاستقطاعات',
          type: const TextInputType.numberWithOptions(decimal: true)),
      _field('note', 'ملاحظة', lines: 2),
      _action('حفظ قيد الراتب', _payrollEntry)
    ]);
  }

  List<Widget> _list() {
    if (_tab == 0)
      return _contracts
          .map((r) => _entry(
              '${_value(r['contract_no'])} — ${_memberName(r['membership_id'])}',
              '${_value(r['start_date'])} إلى ${_value(r['end_date'])} · ${_value(r['status'])} · ${_value(r['base_salary'])} ${_value(r['salary_currency'])}'))
          .toList();
    if (_tab == 1)
      return _schedules
          .map((r) => _entry(
              '${_value(r['name'])} — ${_memberName(r['membership_id'])}',
              '${_value(r['start_time'])} إلى ${_value(r['end_time'])} · استراحة ${_value(r['break_minutes'])} دقيقة · ${_value(r['effective_from'])}'))
          .toList();
    if (_tab == 2)
      return _attendance
          .map((r) => _entry(
              '${_value(r['work_date'])} — ${_memberName(r['membership_id'])}',
              '${_value(r['status'])} · دخول ${_value(r['check_in_at'])} · خروج ${_value(r['check_out_at'])} · ${_value(r['note'])}'))
          .toList();
    return _periods.map((r) {
      final entries = (r['entries'] as List? ?? []);
      return Card(
          child: ExpansionTile(
              title: Text(
                  '${_value(r['period_start'])} إلى ${_value(r['period_end'])} · ${_value(r['status'])}',
                  textAlign: TextAlign.right),
              subtitle: Text('اضغط لاختيار الفترة · ${entries.length} قيود',
                  textAlign: TextAlign.right),
              onExpansionChanged: (_) =>
                  setState(() => _periodId = r['id'].toString()),
              children: entries
                  .map<Widget>((e) => ListTile(
                      title: Text(_memberName(e['membership_id']),
                          textAlign: TextAlign.right),
                      subtitle: Text(
                          'صافي ${_value(e['net_amount'])} ${_value(e['currency'])}',
                          textAlign: TextAlign.right)))
                  .toList()));
    }).toList();
  }

  @override
  Widget build(BuildContext context) => AppShell(
      title: 'الموارد البشرية',
      subtitle: 'العقود والدوام والرواتب',
      child: Directionality(
          textDirection: TextDirection.rtl,
          child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(padding: const EdgeInsets.all(12), children: [
                      SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                              children: List.generate(
                                  _tabs.length,
                                  (i) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 3),
                                      child: ChoiceChip(
                                          label: Text(_tabs[i]),
                                          selected: _tab == i,
                                          onSelected: (_) =>
                                              setState(() => _tab = i)))))),
                      if (_error != null)
                        _card('تعذر إتمام العملية', [
                          Text(_error!, textAlign: TextAlign.right),
                          TextButton(
                              onPressed: _load,
                              child: const Text('إعادة المحاولة'))
                        ]),
                      if (_notice != null)
                        _card('تمت العملية',
                            [Text(_notice!, textAlign: TextAlign.right)]),
                      _form(),
                      if (_list().isEmpty)
                        _card('لا توجد سجلات', [
                          Text('لا توجد سجلات في قسم ${_tabs[_tab]}',
                              textAlign: TextAlign.right)
                        ])
                      else
                        ..._list()
                    ]))));
}
