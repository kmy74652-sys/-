import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/app_shell.dart';
import '../../core/theme.dart';

class AgreementsScreen extends StatefulWidget {
  const AgreementsScreen({super.key});
  @override
  State<AgreementsScreen> createState() => _AgreementsScreenState();
}

class _AgreementsScreenState extends State<AgreementsScreen> {
  final _db = Supabase.instance.client;
  bool _busy = true;
  bool _saving = false;
  String? _error;
  String? _notice;
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _members = [];
  final Map<String, TextEditingController> _notes = {};
  final _formKey = GlobalKey<FormState>();
  final _no = TextEditingController();
  final _title = TextEditingController(text: 'اتفاقية عمل موظف');
  final _from = TextEditingController(
    text: DateTime.now().toIso8601String().substring(0, 10),
  );
  final _to = TextEditingController();
  final _terms = TextEditingController();
  final _duties = TextEditingController();
  String? _membershipId;
  bool _showCreate = false;

  bool _has(String permission) =>
      ((_profile?['permissions'] as List?) ?? []).contains(permission);
  String? _value(Map map, String camel, String snake) =>
      (map[camel] ?? map[snake])?.toString();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _notes.values) {
      controller.dispose();
    }
    _no.dispose();
    _title.dispose();
    _from.dispose();
    _to.dispose();
    _terms.dispose();
    _duties.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted)
      setState(() {
        _busy = true;
        _error = null;
      });
    try {
      final result = await _db.rpc('mobile_my_profile');
      final root = result is Map
          ? Map<String, dynamic>.from(result)
          : <String, dynamic>{};
      final p = root['employee'] is Map
          ? Map<String, dynamic>.from(root['employee'])
          : null;
      if (p == null || (p['status']?.toString() != 'active'))
        throw Exception('employee_not_active');
      final org = _value(p, 'institutionId', 'institution_id');
      final memberId = p['id']?.toString();
      if (org == null || memberId == null)
        throw Exception('employee_not_active');
      final rowsResponse = await _db
          .from('employee_agreements')
          .select(
            'id,membership_id,agreement_no,title,status,effective_from,effective_to,current_version_id,current_version_no',
          )
          .eq('organization_id', org)
          .order('updated_at', ascending: false)
          .limit(100);
      final rows = List<Map<String, dynamic>>.from(rowsResponse);
      final ids = rows.map((e) => e['id'].toString()).toList();
      final versionIds = rows
          .map((e) => e['current_version_id'])
          .whereType<String>()
          .toList();
      List<Map<String, dynamic>> versions = [], responses = [], approvals = [];
      if (versionIds.isNotEmpty) {
        versions = List<Map<String, dynamic>>.from(
          await _db
              .from('employee_agreement_versions')
              .select(
                'id,agreement_id,version_no,title,terms,responsibilities,content_hash,status,published_at',
              )
              .inFilter('id', versionIds)
              .limit(100),
        );
      }
      if (ids.isNotEmpty) {
        responses = List<Map<String, dynamic>>.from(
          await _db
              .from('employee_agreement_responses')
              .select('agreement_id,version_id,response,note,responded_at')
              .inFilter('agreement_id', ids)
              .eq('membership_id', memberId)
              .limit(100),
        );
        approvals = List<Map<String, dynamic>>.from(
          await _db
              .from('employee_agreement_approvals')
              .select(
                'agreement_id,version_id,employee_status,manager_status,employee_note,manager_note,employee_approved_at,manager_approved_at',
              )
              .inFilter('agreement_id', ids)
              .limit(100),
        );
      }
      final byVersion = {for (final v in versions) v['id'].toString(): v};
      final responseByVersion = {
        for (final r in responses) r['version_id'].toString(): r,
      };
      final approvalByVersion = {
        for (final a in approvals) a['version_id'].toString(): a,
      };
      for (final row in rows) {
        final v = byVersion[row['current_version_id']];
        row['version'] = v;
        row['response'] = v == null
            ? null
            : responseByVersion[v['id'].toString()];
        row['approval'] = v == null
            ? null
            : approvalByVersion[v['id'].toString()];
      }
      List<Map<String, dynamic>> members = [];
      if ((p['permissions'] as List? ?? []).contains(
        'employee_agreements.manage',
      )) {
        members = List<Map<String, dynamic>>.from(
          await _db
              .from('organization_memberships')
              .select('id,display_name,employee_no')
              .eq('organization_id', org)
              .eq('is_active', true)
              .order('display_name')
              .limit(500),
        );
      }
      if (!mounted) return;
      setState(() {
        _profile = p;
        _rows = rows;
        _members = members;
        if (_membershipId == null ||
            !members.any((m) => m['id'].toString() == _membershipId)) {
          _membershipId = members.isEmpty
              ? null
              : members.first['id'].toString();
        }
      });
    } catch (e) {
      if (mounted)
        setState(
          () => _error = e.toString().contains('employee_not_active')
              ? 'هذا الحساب غير مرتبط بملف موظف نشط.'
              : 'تعذر تحميل اتفاقيات العمل. تحقق من الصلاحية والاتصال.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _action(String success, Future<void> Function() task) async {
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      await task();
      if (mounted) setState(() => _notice = success);
      await _load();
    } catch (_) {
      if (mounted)
        setState(
          () => _error = 'تعذر تنفيذ العملية. تحقق من الصلاحية والاتصال.',
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate() ||
        _membershipId == null ||
        _profile == null)
      return;
    final clauses = _terms.text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final responsibilities = _duties.text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    await _action(
      'تم إنشاء مسودة الاتفاقية. أرسلها للاعتماد ثم انشرها.',
      () async {
        await _db.rpc(
          'create_employee_agreement',
          params: {
            'p_organization_id': _value(
              _profile!,
              'institutionId',
              'institution_id',
            ),
            'p_membership_id': _membershipId,
            'p_agreement_no': _no.text.trim(),
            'p_title': _title.text.trim(),
            'p_terms': {
              'clauses': clauses,
              'responsibilities': responsibilities,
            },
            'p_effective_from': _from.text.trim(),
            'p_effective_to': _to.text.trim().isEmpty ? null : _to.text.trim(),
          },
        );
        _no.clear();
        _terms.clear();
        _duties.clear();
        if (mounted) setState(() => _showCreate = false);
      },
    );
  }

  Future<void> _managerDecision(String id, String decision) async {
    final note = _notes.putIfAbsent(id, TextEditingController.new).text;
    await _action(
      decision == 'approved'
          ? 'تم اعتماد الاتفاقية من المدير.'
          : 'تم رفض الاتفاقية من المدير.',
      () async {
        await _db.rpc(
          'approve_employee_agreement',
          params: {
            'p_agreement_id': id,
            'p_decision': decision,
            'p_note': note.isEmpty ? null : note,
          },
        );
      },
    );
  }

  Future<void> _employeeResponse(
    String versionId,
    String decision,
    String id,
  ) async {
    final note = _notes.putIfAbsent(id, TextEditingController.new).text;
    await _action(
      decision == 'accepted'
          ? 'تم قبول الاتفاقية وتسجيل القبول.'
          : 'تم تسجيل رفض الاتفاقية وإبلاغ الإدارة.',
      () async {
        await _db.rpc(
          'approve_employee_agreement',
          params: {
            'p_agreement_id': id,
            'p_decision': decision == 'accepted' ? 'approved' : 'rejected',
            'p_note': note.isEmpty ? null : note,
          },
        );
      },
    );
  }

  String _status(String s) =>
      const {
        'draft': 'مسودة',
        'pending_approval': 'بانتظار اعتماد المالك',
        'published': 'بانتظار قبول الموظف',
        'accepted': 'مقبولة',
        'rejected': 'مرفوضة',
        'superseded': 'مستبدلة',
        'expired': 'منتهية',
        'revoked': 'مسحوبة',
      }[s] ??
      s;
  String _date(dynamic raw) {
    if (raw == null) return 'غير محدد';
    try {
      final d = DateTime.parse(raw.toString());
      return '${d.year}/${d.month}/${d.day}';
    } catch (_) {
      return raw.toString();
    }
  }

  String? _dateFieldValidator(String? value, {String? after}) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return after == null ? 'أدخل التاريخ' : null;
    final parsed = DateTime.tryParse(text);
    if (parsed == null || parsed.toIso8601String().substring(0, 10) != text) {
      return 'استخدم الصيغة YYYY-MM-DD';
    }
    if (after != null && text.compareTo(after) < 0) {
      return 'لا يمكن أن يسبق تاريخ النهاية تاريخ البداية';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: AppShell(
      title: 'اتفاقية العمل',
      subtitle: 'اتفاقيات الموظفين',
      child: RefreshIndicator(
        onRefresh: _load,
        child: _busy
            ? ListView(
                children: [
                  SizedBox(height: 220),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Card(
                    color: const Color(0xffe8f0f8),
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'مستندات العمل',
                            style: TextStyle(color: Colors.blueGrey),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'اتفاقيات الموظفين',
                            style: TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.bold,
                              color: AppColors.navy,
                            ),
                          ),
                          Text(
                            'تعرض النسخة الحالية وبنودها وحالتها. تُسجّل استجابة الموظف واعتمادات الإدارة في قاعدة البيانات.',
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_error != null) _message(_error!, Colors.red),
                  if (_notice != null) _message(_notice!, Colors.green),
                  if (_has('employee_agreements.manage'))
                    OutlinedButton(
                      onPressed: () =>
                          setState(() => _showCreate = !_showCreate),
                      child: Text(
                        _showCreate
                            ? 'إغلاق إنشاء اتفاقية'
                            : '+ إنشاء اتفاقية عمل',
                      ),
                    ),
                  if (_showCreate && _has('employee_agreements.manage'))
                    _createForm(),
                  if (_rows.where((e) => e['status'] != 'superseded').isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text(
                          'لا توجد اتفاقية عمل',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ..._rows
                      .where((e) => e['status'] != 'superseded')
                      .map(_agreementCard),
                ],
              ),
      ),
    ),
  );

  Widget _message(String text, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(
      text,
      textAlign: TextAlign.right,
      style: TextStyle(color: color),
    ),
  );
  Widget _createForm() => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            const Text(
              'مسودة اتفاقية جديدة',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            DropdownButtonFormField<String>(
              value: _membershipId,
              decoration: const InputDecoration(labelText: 'الموظف'),
              items: _members
                  .map(
                    (m) => DropdownMenuItem(
                      value: m['id'].toString(),
                      child: Text(
                        '${m['display_name']}${m['employee_no'] == null ? '' : ' · ${m['employee_no']}'}',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _membershipId = v),
            ),
            _field(_no, 'رقم الاتفاقية', required: true),
            _field(_title, 'عنوان الاتفاقية', required: true),
            _field(
              _from,
              'تاريخ السريان (YYYY-MM-DD)',
              required: true,
              validator: (v) => _dateFieldValidator(v),
            ),
            _field(
              _to,
              'تاريخ النهاية (اختياري)',
              validator: (v) => _dateFieldValidator(v, after: _from.text),
            ),
            _field(
              _duties,
              'المهام والمسؤوليات، كل مسؤولية في سطر',
              maxLines: 4,
            ),
            _field(
              _terms,
              'بنود الاتفاقية، كل بند في سطر',
              required: true,
              minLength: 10,
              maxLines: 5,
            ),
            FilledButton(
              onPressed: _saving ? null : _create,
              child: const Text('حفظ كمسودة'),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _field(
    TextEditingController c,
    String label, {
    bool required = false,
    int minLength = 2,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: TextFormField(
      controller: c,
      maxLines: maxLines,
      textAlign: TextAlign.right,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator:
          validator ??
          (s) => required && (s == null || s.trim().length < minLength)
              ? 'أدخل بيانات صحيحة'
              : null,
    ),
  );

  Widget _agreementCard(Map<String, dynamic> a) {
    final id = a['id'].toString(), status = a['status'].toString();
    final version = a['version'] is Map
        ? Map<String, dynamic>.from(a['version'])
        : null;
    final approval = a['approval'] is Map
        ? Map<String, dynamic>.from(a['approval'])
        : null;
    final own = a['membership_id']?.toString() == _profile?['id']?.toString();
    final terms = version?['terms'] is Map
        ? Map<String, dynamic>.from(version!['terms'])
        : <String, dynamic>{};
    final clauses = terms['clauses'] is List
        ? (terms['clauses'] as List).map((e) => e.toString()).toList()
        : <String>[];
    final duties = version?['responsibilities'] is List
        ? (version!['responsibilities'] as List)
              .map((e) => e.toString())
              .toList()
        : <String>[];
    final note = _notes.putIfAbsent(id, TextEditingController.new);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              a['title']?.toString() ?? 'اتفاقية',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.navy,
              ),
            ),
            Text(
              'الحالة: ${_status(status)} · رقم الاتفاقية: ${a['agreement_no']} · الإصدار ${a['current_version_no']}',
              textAlign: TextAlign.right,
            ),
            Text(
              'سارية من ${_date(a['effective_from'])}${a['effective_to'] == null ? '' : ' إلى ${_date(a['effective_to'])}'}',
              textAlign: TextAlign.right,
            ),
            if (version != null) ...[
              if (duties.isNotEmpty)
                const Text(
                  'المهام والمسؤوليات',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ...duties.asMap().entries.map(
                (e) => Text(
                  '${e.key + 1}. ${e.value}',
                  textAlign: TextAlign.right,
                ),
              ),
              const Text(
                'بنود الاتفاقية',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              if (clauses.isEmpty)
                const Text('لا توجد بنود معروضة.')
              else
                ...clauses.asMap().entries.map(
                  (e) => Text(
                    '${e.key + 1}. ${e.value}',
                    textAlign: TextAlign.right,
                  ),
                ),
            ],
            if (approval != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'اعتماد الموظف: ${_status(approval['employee_status']?.toString() ?? 'pending')} · اعتماد المدير: ${_status(approval['manager_status']?.toString() ?? 'pending')}',
                    textAlign: TextAlign.right,
                  ),
                  if (approval['employee_note'] != null)
                    Text(
                      'ملاحظة الموظف: ${approval['employee_note']}',
                      textAlign: TextAlign.right,
                    ),
                  if (approval['manager_note'] != null)
                    Text(
                      'ملاحظة المدير: ${approval['manager_note']}',
                      textAlign: TextAlign.right,
                    ),
                  if (approval['employee_approved_at'] != null)
                    Text(
                      'وقت قرار الموظف: ${_date(approval['employee_approved_at'])}',
                      textAlign: TextAlign.right,
                    ),
                  if (approval['manager_approved_at'] != null)
                    Text(
                      'وقت قرار المدير: ${_date(approval['manager_approved_at'])}',
                      textAlign: TextAlign.right,
                    ),
                ],
              ),
            if (own &&
                status == 'published' &&
                version != null &&
                approval?['employee_status'] == 'pending') ...[
              _field(note, 'ملاحظة اختيارية عند الرفض'),
              FilledButton(
                onPressed: _saving
                    ? null
                    : () => _employeeResponse(
                        version['id'].toString(),
                        'accepted',
                        id,
                      ),
                child: const Text('أوافق على الاتفاقية'),
              ),
              OutlinedButton(
                onPressed: _saving
                    ? null
                    : () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: const Text('رفض الاتفاقية'),
                            content: const Text(
                              'سيتم تسجيل رفضك مع الملاحظة المدخلة. هل تريد المتابعة؟',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(c, false),
                                child: const Text('إلغاء'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(c, true),
                                child: const Text('تأكيد الرفض'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true)
                          await _employeeResponse(
                            version['id'].toString(),
                            'rejected',
                            id,
                          );
                      },
                child: const Text('رفض مع ملاحظة'),
              ),
            ],
            if (_has('employee_agreements.manage') && status == 'draft')
              OutlinedButton(
                onPressed: _saving
                    ? null
                    : () => _action('تم إرسال الاتفاقية للاعتماد.', () async {
                        await _db.rpc(
                          'submit_employee_agreement_for_approval',
                          params: {'p_agreement_id': id},
                        );
                      }),
                child: const Text('إرسال للاعتماد'),
              ),
            if (_has('employee_agreements.publish') &&
                status == 'pending_approval')
              FilledButton(
                onPressed: _saving
                    ? null
                    : () => _action('تم نشر الاتفاقية للموظف.', () async {
                        await _db.rpc(
                          'publish_employee_agreement',
                          params: {'p_agreement_id': id},
                        );
                      }),
                child: const Text('نشر الاتفاقية'),
              ),
            if (_has('employee_agreements.approve') &&
                status == 'published' &&
                approval?['manager_status'] == 'pending') ...[
              _field(note, 'ملاحظة اعتماد المدير (اختياري)'),
              FilledButton(
                onPressed: _saving
                    ? null
                    : () => _managerDecision(id, 'approved'),
                child: const Text('اعتماد المدير'),
              ),
              OutlinedButton(
                onPressed: _saving
                    ? null
                    : () => _managerDecision(id, 'rejected'),
                child: const Text('رفض الاتفاقية'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (final c in _notes.values) {
      c.dispose();
    }
    _no.dispose();
    _title.dispose();
    _from.dispose();
    _to.dispose();
    _terms.dispose();
    _duties.dispose();
    super.dispose();
  }
}
