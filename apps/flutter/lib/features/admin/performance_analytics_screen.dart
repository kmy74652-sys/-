import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../shared/app_shell.dart';

class PerformanceAnalyticsScreen extends StatefulWidget {
  const PerformanceAnalyticsScreen({super.key});

  @override
  State<PerformanceAnalyticsScreen> createState() =>
      _PerformanceAnalyticsScreenState();
}

class _PerformanceAnalyticsScreenState
    extends State<PerformanceAnalyticsScreen> {
  bool _loading = true;
  String? _error;
  String _search = '';
  String _sort = 'completion';
  String _taskSource = 'unified';
  String? _employeeFilter;
  DateTime? _fromDate, _toDate;
  Map<String, String> _employeeOptions = {};
  List<_Employee> _employees = [];
  List<_Branch> _branches = [];
  _Delivery _delivery = _Delivery();
  Map<String, int> _reportStatusCounts = {};

  static const _roleNames = <String, String>{
    'owner': 'صاحب المؤسسة',
    'admin_followup': 'المدير التنفيذي',
    'accountant': 'المحاسب',
    'warehouse_keeper': 'أمين المخازن',
    'warehouse_worker': 'عمال التحميل',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> _rows(dynamic value) => value is List
      ? value
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList()
      : <Map<String, dynamic>>[];

  String _str(dynamic value, [String fallback = '']) =>
      value == null ? fallback : value.toString();

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = Supabase.instance.client;
      // Each query is independently subject to the user's PostgREST RLS policies.
      final results = await Future.wait<dynamic>([
        db
            .from('tasks')
            .select(
              'id,title,description,assigned_to,position_code,branch_id,priority,status,due_at,assigned_at,received_at,opened_at',
            )
            .isFilter('deleted_at', null)
            .order('due_at')
            .limit(2000),
        db
            .from('organization_memberships')
            .select('id,user_id,display_name,is_active')
            .eq('is_active', true)
            .order('display_name')
            .limit(500),
        db
            .from('role_assignments')
            .select('membership_id,role_code,branch_id')
            .limit(1000),
        db
            .from('branches')
            .select('id,name')
            .eq('is_active', true)
            .order('name')
            .limit(200),
        db
            .from('task_reports')
            .select('id,task_id,submitted_by,status')
            .limit(2000),
        db
            .from('employee_role_reports')
            .select('id,employee_user_id,status')
            .limit(2000),
      ]);
      final tasks = _rows(results[0]);
      final members = _rows(results[1]);
      final assignments = _rows(results[2]);
      final branchRows = _rows(results[3]);
      final taskReports = _rows(results[4]);
      final roleReports = _rows(results[5]);
      final unifiedTaskIds = tasks
          .where(_isUnifiedTask)
          .map((task) => _str(task['id']))
          .where((id) => id.isNotEmpty)
          .toSet();
      final evaluationTasks = _taskSource == 'unified'
          ? tasks.where(_isUnifiedTask).toList()
          : tasks;
      final branchNames = <String, String>{
        for (final branch in branchRows)
          if (branch['id'] != null)
            _str(branch['id']): _str(branch['name'], 'فرع غير محدد'),
      };
      final membersById = <String, Map<String, dynamic>>{
        for (final member in members)
          if (member['id'] != null) _str(member['id']): member,
      };
      final primary = <String, Map<String, dynamic>>{};
      for (final assignment in assignments) {
        final member = membersById[_str(assignment['membership_id'])];
        if (member == null || member['user_id'] == null) continue;
        primary.putIfAbsent(_str(member['user_id']), () => assignment);
      }
      final reportCounts = <String, int>{};
      final reportStatusCounts = <String, int>{};
      for (final row in taskReports) {
        if (_taskSource == 'unified' &&
            !unifiedTaskIds.contains(_str(row['task_id']))) {
          continue;
        }
        if (row['status'] != null && _str(row['submitted_by']).isNotEmpty) {
          final id = _str(row['submitted_by']);
          reportCounts[id] = (reportCounts[id] ?? 0) + 1;
        }
        final status = _str(row['status']);
        if (status.isNotEmpty) reportStatusCounts[status] = (reportStatusCounts[status] ?? 0) + 1;
      }
      for (final row in _taskSource == 'unified'
          ? const <Map<String, dynamic>>[]
          : roleReports) {
        if (row['status'] != null && _str(row['employee_user_id']).isNotEmpty) {
          final id = _str(row['employee_user_id']);
          reportCounts[id] = (reportCounts[id] ?? 0) + 1;
        }
        final status = _str(row['status']);
        if (status.isNotEmpty) reportStatusCounts[status] = (reportStatusCounts[status] ?? 0) + 1;
      }
      final byUser = <String, _Employee>{};
      final employeeOptions = <String, String>{};
      for (final member in members) {
        final userId = _str(member['user_id']);
        if (userId.isEmpty) continue;
        employeeOptions[userId] = _str(member['display_name'], 'موظف');
        final assignment = primary[userId];
        final role = _str(assignment?['role_code'], 'accountant');
        final branchId = _str(assignment?['branch_id']);
        byUser[userId] = _Employee(
          id: _str(member['id'], userId),
          userId: userId,
          name: _str(member['display_name'], 'موظف'),
          roleCode: role,
          roleName: _roleNames[role] ?? role,
          branchName: branchId.isEmpty
              ? 'كل الفروع'
              : (branchNames[branchId] ?? 'فرع غير محدد'),
          reports: reportCounts[userId] ?? 0,
        );
      }
      final overallDelivery = _Delivery();
      for (final task in evaluationTasks) {
        final assignedTo = _str(task['assigned_to']);
        final dueDate = DateTime.tryParse(_str(task['due_at']))?.toLocal();
        final taskDay = dueDate == null
            ? null
            : DateTime(dueDate.year, dueDate.month, dueDate.day);
        final from = _fromDate == null
            ? null
            : DateTime(_fromDate!.year, _fromDate!.month, _fromDate!.day);
        final to = _toDate == null
            ? null
            : DateTime(_toDate!.year, _toDate!.month, _toDate!.day);
        if (_employeeFilter != null && assignedTo != _employeeFilter) continue;
        if ((from != null || to != null) && taskDay == null) continue;
        if (taskDay != null &&
            ((from != null && taskDay.isBefore(from)) ||
                (to != null && taskDay.isAfter(to)))) continue;
        final employee = byUser[_str(task['assigned_to'])];
        if (employee == null) continue;
        final status = _str(task['status']);
        final priority = _str(task['priority'], 'normal');
        final bucket = ['low', 'normal', 'high', 'urgent'].contains(priority)
            ? priority
            : 'normal';
        final isDone = _isDone(status);
        employee.required[bucket] = (employee.required[bucket] ?? 0) + 1;
        if (isDone) employee.done[bucket] = (employee.done[bucket] ?? 0) + 1;
        final due = DateTime.tryParse(_str(task['due_at']));
        if (!isDone &&
            status != 'cancelled' &&
            due != null &&
            due.isBefore(DateTime.now()))
          employee.delayed++;
        final item = _Task(
          id: _str(task['id']),
          title: _str(task['title'], 'مهمة بلا عنوان'),
          priority: priority,
          status: status,
          dueAt: _str(task['due_at']),
          isDone: isDone,
        );
        employee.tasks.add(item);
        employee.delivery.add(
          task['assigned_at'],
          task['received_at'],
          task['opened_at'],
        );
        overallDelivery.add(
          task['assigned_at'],
          task['received_at'],
          task['opened_at'],
        );
      }
      final employees = byUser.values
          .where((e) => e.tasks.isNotEmpty || e.reports > 0)
          .toList();
      final branchMap = <String, _Branch>{};
      for (final employee in employees) {
        final branch = branchMap.putIfAbsent(
          employee.branchName,
          () => _Branch(employee.branchName),
        );
        branch.staff++;
        branch.required += employee.totalRequired;
        branch.done += employee.totalDone;
        branch.highRequired += employee.highRequired;
        branch.highDone += employee.highDone;
      }
      if (!mounted) return;
      setState(() {
        _employees = employees;
        _branches = branchMap.values.toList()
          ..sort((a, b) => b.rate.compareTo(a.rate));
        _delivery = overallDelivery;
        _reportStatusCounts = reportStatusCounts;
        _employeeOptions = employeeOptions;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _errorMessage(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '');
    return 'تعذر تحميل مؤشرات الأداء. قد تكون بعض البيانات غير متاحة وفق صلاحيات الحساب (RLS).\n$text';
  }

  bool _isUnifiedTask(Map<String, dynamic> task) {
    final description = _str(task['description']);
    return description.contains('الجدول الموحد:') ||
        _str(task['title']).startsWith('الجدول الموحد -');
  }

  bool _isDone(String status) =>
      status == 'completed_approved' || status == 'approved';

  List<_Employee> get _visibleEmployees {
    final query = _search.trim().toLowerCase();
    final list = _employees
        .where(
          (e) =>
              query.isEmpty ||
              e.name.toLowerCase().contains(query) ||
              e.branchName.toLowerCase().contains(query) ||
              e.roleName.toLowerCase().contains(query),
        )
        .toList();
    switch (_sort) {
      case 'high':
        list.sort((a, b) => b.highRate.compareTo(a.highRate));
        break;
      case 'delayed':
        list.sort((a, b) => b.delayed.compareTo(a.delayed));
        break;
      case 'reports':
        list.sort((a, b) => b.reports.compareTo(a.reports));
        break;
      default:
        list.sort((a, b) => b.rate.compareTo(a.rate));
    }
    return list;
  }

  int get _required => _employees.fold(0, (sum, e) => sum + e.totalRequired);
  int get _done => _employees.fold(0, (sum, e) => sum + e.totalDone);
  int get _delayed => _employees.fold(0, (sum, e) => sum + e.delayed);
  int get _reports => _employees.fold(0, (sum, e) => sum + e.reports);
  double get _rate => _required == 0 ? 0 : _done * 100 / _required;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: AppShell(
      title: 'تحليلات الأداء',
      subtitle: 'مؤشرات الموظفين والفروع وفق البيانات المتاحة',
      child: RefreshIndicator(
        onRefresh: _load,
        child: _loading && _employees.isEmpty
            ? ListView(
                children: [
                  SizedBox(height: 220),
                  Center(child: CircularProgressIndicator()),
                  SizedBox(height: 16),
                  Center(child: Text('جارٍ تحميل مؤشرات الأداء…')),
                ],
              )
            : _error != null && _employees.isEmpty
            ? ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SectionCard(
                    title: 'تعذر تحميل التحليلات',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(_error!, textAlign: TextAlign.right),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh),
                            label: const Text('إعادة المحاولة'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  if (_loading) const LinearProgressIndicator(),
                  if (_error != null)
                    _messageCard(
                      'حدثت مشكلة أثناء التحديث',
                      _error!,
                      onRetry: _load,
                    ),
                  _ledgerFilters(),
                  const SizedBox(height: 10),
                  _overviewCard(),
                  const SizedBox(height: 10),
                  _reportStatusCard(),
                  const SizedBox(height: 10),
                  _deliveryCard(),
                  const SizedBox(height: 10),
                  _branchCards(),
                  const SizedBox(height: 10),
                  _employeeSection(),
                ],
              ),
      ),
    ),
  );

  Widget _ledgerFilters() => SectionCard(
    title: 'كشف المهام حسب الموظف والفترة',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'اختر موظفًا وفترة زمنية لقراءة ما أُنجز وما لم يُنجز.',
          textAlign: TextAlign.right,
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: _taskSource,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'مصدر التقييم',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(
              value: 'unified',
              child: Text('الجدول الموحد للمهام'),
            ),
            DropdownMenuItem(
              value: 'all',
              child: Text('كل المهام'),
            ),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => _taskSource = value);
            _load();
          },
        ),
        const SizedBox(height: 6),
        Text(
          _taskSource == 'unified'
              ? 'يتم احتساب الإنجاز والتأخير والتقارير المرتبطة بمهام الجدول الموحد فقط.'
              : 'يتم احتساب جميع المهام المتاحة لصلاحيات الحساب.',
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: _employeeOptions.containsKey(_employeeFilter)
              ? _employeeFilter
              : null,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'الموظف',
            hintText: 'كل الموظفين',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<String>(
              value: null,
              child: Text('كل الموظفين'),
            ),
            ..._employeeOptions.entries.map(
              (entry) => DropdownMenuItem<String>(
                value: entry.key,
                child: Text(entry.value),
              ),
            ),
          ],
          onChanged: (value) {
            setState(() => _employeeFilter = value);
            _load();
          },
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _dateButton('من تاريخ', _fromDate, true)),
            const SizedBox(width: 8),
            Expanded(child: _dateButton('إلى تاريخ', _toDate, false)),
          ],
        ),
        if (_fromDate != null || _toDate != null || _employeeFilter != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                setState(() {
                  _fromDate = null;
                  _toDate = null;
                  _employeeFilter = null;
                });
                _load();
              },
              icon: const Icon(Icons.clear),
              label: const Text('مسح كشف الفترة والموظف'),
            ),
          ),
      ],
    ),
  );

  Widget _dateButton(String label, DateTime? value, bool isFrom) =>
      OutlinedButton.icon(
        onPressed: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: value ?? DateTime.now(),
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
            helpText: label,
            cancelText: 'إلغاء',
            confirmText: 'اختيار',
          );
          if (picked == null || !mounted) return;
          setState(() {
            if (isFrom) {
              _fromDate = picked;
            } else {
              _toDate = picked;
            }
          });
          _load();
        },
        icon: const Icon(Icons.calendar_today_outlined, size: 18),
        label: Text(
          value == null ? label : '$label: ${_dateOnly(value)}',
          overflow: TextOverflow.ellipsis,
        ),
      );

  String _dateOnly(DateTime value) =>
      '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';

  Widget _overviewCard() => SectionCard(
    title: 'المؤشرات العامة',
    child: Wrap(
      spacing: 9,
      runSpacing: 9,
      children: [
        _metric(
          'معدل إنجاز المهام',
          '${_rate.toStringAsFixed(1)}%',
          '$_done من $_required مهمة',
          Icons.task_alt,
        ),
        _metric(
          'المهام المتأخرة',
          '$_delayed',
          'غير منجزة ومستحقة قبل الآن',
          Icons.schedule,
        ),
        _metric(
          'غير مكتملة',
          '${_required - _done}',
          'المهام المتبقية ضمن الفترة المحددة',
          Icons.pending_actions_outlined,
        ),
        _metric(
          'الموظفون النشطون',
          '${_employees.length}',
          'لديهم مهام أو تقارير',
          Icons.people_alt_outlined,
        ),
        _metric(
          'التقارير المقدمة',
          '$_reports',
          'تقارير مهام وأدوار',
          Icons.assessment_outlined,
        ),
        _metric(
          'بانتظار المراجعة',
          '${_reportStatusCounts['submitted'] ?? 0}',
          'تحتاج قرار المدير',
          Icons.pending_actions_outlined,
        ),
        _metric(
          'تقارير معتمدة',
          '${_reportStatusCounts['approved'] ?? 0}',
          'تقارير مكتملة ومعتمدة',
          Icons.verified_outlined,
        ),
        _metric(
          'تقارير معادة',
          '${_reportStatusCounts['returned'] ?? 0}',
          'تحتاج تعديل الموظف',
          Icons.replay_outlined,
        ),
      ],
    ),
  );

  Widget _reportStatusCard() {
    final items = <(String, String, Color)>[
      ('submitted', 'بانتظار المراجعة', Colors.orange),
      ('approved', 'معتمدة', Colors.green),
      ('returned', 'معادة للتعديل', Colors.red),
    ];
    final total = items.fold<int>(0, (sum, item) => sum + (_reportStatusCounts[item.$1] ?? 0));
    return SectionCard(
      title: 'حالة التقارير',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in items) _reportBar(item.$2, _reportStatusCounts[item.$1] ?? 0, total, item.$3),
          if (total == 0) const Text('لا توجد تقارير مرسلة حتى الآن.', textAlign: TextAlign.right),
        ],
      ),
    );
  }

  Widget _reportBar(String label, int count, int total, Color color) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, textAlign: TextAlign.right)),
            Text('$count', style: TextStyle(fontWeight: FontWeight.w800, color: color)),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: total == 0 ? 0 : count / total,
          minHeight: 7,
          color: color,
          backgroundColor: const Color(0xFFE6ECEA),
        ),
      ],
    ),
  );

  Widget _metric(String title, String value, String caption, IconData icon) =>
      SizedBox(
        width: 155,
        child: Card(
          color: const Color(0xFFF7FAF9),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Icon(icon, color: AppColors.green),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                    color: AppColors.navy,
                  ),
                ),
                Text(
                  title,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  caption,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _deliveryCard() => SectionCard(
    title: 'سرعة الاستلام والبدء',
    child: Row(
      children: [
        Expanded(
          child: _latency(
            'من الإسناد إلى الاستلام',
            _delivery.receivedAverage,
            _delivery.receivedSamples,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _latency(
            'من الاستلام إلى الفتح',
            _delivery.openedAverage,
            _delivery.openedSamples,
          ),
        ),
      ],
    ),
  );

  Widget _latency(String title, int? milliseconds, int samples) {
    final label = milliseconds == null
        ? 'لا توجد بيانات'
        : _duration(milliseconds);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAF9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            title,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppColors.green,
            ),
          ),
          Text(
            '$samples عينة',
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  String _duration(int ms) {
    final mins = ms ~/ 60000;
    if (mins < 60) return '$mins دقيقة';
    final hours = mins ~/ 60;
    if (hours < 48) return '$hours ساعة ${mins % 60} د';
    return '${hours ~/ 24} يوم ${hours % 24} س';
  }

  Widget _branchCards() => SectionCard(
    title: 'الأداء حسب الفرع',
    child: _branches.isEmpty
        ? const Text(
            'لا توجد بيانات فروع مرتبطة بالموظفين ذوي النشاط.',
            textAlign: TextAlign.right,
          )
        : Column(
            children: _branches
                .map(
                  (branch) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7FAF9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  branch.name,
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.navy,
                                  ),
                                ),
                              ),
                              Text(
                                '${branch.rate.toStringAsFixed(0)}%',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.green,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          LinearProgressIndicator(
                            value: branch.rate / 100,
                            minHeight: 6,
                            color: AppColors.green,
                            backgroundColor: const Color(0xFFDDE8E4),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${branch.staff} موظف · ${branch.done}/${branch.required} مهمة مكتملة · أولوية عالية ${branch.highDone}/${branch.highRequired}',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
  );

  Widget _employeeSection() => SectionCard(
    title: 'ترتيب الموظفين',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          textDirection: TextDirection.rtl,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'ابحث بالاسم أو الفرع أو الدور',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => setState(() => _search = value),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _sort,
          decoration: const InputDecoration(
            labelText: 'ترتيب حسب',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(
              value: 'completion',
              child: Text('معدل الإنجاز العام'),
            ),
            DropdownMenuItem(
              value: 'high',
                child: Text('إنجاز المهام العالية والعاجلة'),
            ),
            DropdownMenuItem(
              value: 'delayed',
              child: Text('عدد المهام المتأخرة'),
            ),
            DropdownMenuItem(
              value: 'reports',
              child: Text('عدد التقارير المقدمة'),
            ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _sort = value);
          },
        ),
        const SizedBox(height: 8),
        if (_visibleEmployees.isEmpty)
          const Padding(
            padding: EdgeInsets.all(14),
            child: Text(
              'لا يوجد موظفون مطابقون للبحث.',
              textAlign: TextAlign.right,
            ),
          )
        else
          ..._visibleEmployees.asMap().entries.map(
            (entry) => _employeeTile(entry.key + 1, entry.value),
          ),
      ],
    ),
  );

  Widget _employeeTile(int rank, _Employee employee) => Card(
    margin: const EdgeInsets.only(bottom: 7),
    child: ListTile(
      onTap: () => _showEmployee(employee),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: const Color(0xFFE7F2ED),
        child: Text(
          '$rank',
          style: const TextStyle(
            color: AppColors.navy,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      title: Text(
        employee.name,
        textAlign: TextAlign.right,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        '${employee.roleName} · ${employee.branchName}\nإنجاز ${employee.rate.toStringAsFixed(0)}% · أولوية عالية ${employee.highRate.toStringAsFixed(0)}% · متأخرة ${employee.delayed} · تقارير ${employee.reports}',
        textAlign: TextAlign.right,
        style: const TextStyle(height: 1.5),
      ),
      trailing: const Icon(Icons.chevron_left),
      isThreeLine: true,
    ),
  );

  void _showEmployee(_Employee employee) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: .8,
          minChildSize: .45,
          builder: (context, scrollController) => ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Text(
                employee.name,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy,
                ),
              ),
              Text(
                '${employee.roleName} · ${employee.branchName}',
                textAlign: TextAlign.right,
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _detailStat(
                    'الإنجاز العام',
                    '${employee.rate.toStringAsFixed(1)}%',
                  ),
                  _detailStat(
                    'إنجاز العالية والعاجلة',
                    '${employee.highRate.toStringAsFixed(1)}%',
                  ),
                  _detailStat('المتأخرة', '${employee.delayed}'),
                  _detailStat('التقارير', '${employee.reports}'),
                ],
              ),
              const SizedBox(height: 10),
              SectionCard(
                title: 'إحصاءات الأولوية',
                child: Column(
                  children: ['urgent', 'high', 'normal', 'low']
                      .map(
                        (priority) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            _priorityName(priority),
                            textAlign: TextAlign.right,
                          ),
                          subtitle: Text(
                            '${employee.done[priority] ?? 0} من ${employee.required[priority] ?? 0} مكتملة',
                            textAlign: TextAlign.right,
                          ),
                          trailing: Text(
                            '${employee.priorityRate(priority).toStringAsFixed(0)}%',
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 8),
              SectionCard(
                title: 'زمن التسليم والاستلام',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'الإسناد ← الاستلام: ${employee.delivery.receivedAverage == null ? 'لا توجد بيانات' : _duration(employee.delivery.receivedAverage!)} (${employee.delivery.receivedSamples} عينة)',
                      textAlign: TextAlign.right,
                    ),
                    Text(
                      'الاستلام ← الفتح: ${employee.delivery.openedAverage == null ? 'لا توجد بيانات' : _duration(employee.delivery.openedAverage!)} (${employee.delivery.openedSamples} عينة)',
                      textAlign: TextAlign.right,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SectionCard(
                title: 'المهام (${employee.tasks.length})',
                child: employee.tasks.isEmpty
                    ? const Text(
                        'لا توجد مهام مسندة.',
                        textAlign: TextAlign.right,
                      )
                    : Column(children: employee.tasks.map(_taskRow).toList()),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _detailStat(String title, String value) => SizedBox(
    width: 145,
    child: Card(
      color: const Color(0xFFF7FAF9),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: AppColors.green,
              ),
            ),
            Text(title, textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );

  Widget _taskRow(_Task task) => ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    leading: Icon(
      task.isDone ? Icons.check_circle_outline : Icons.assignment_outlined,
      color: task.isDone ? AppColors.green : AppColors.muted,
    ),
    title: Text(task.title, textAlign: TextAlign.right),
    subtitle: Text(
      '${_priorityName(task.priority)} · ${_statusName(task.status)}${task.dueAt.isEmpty ? '' : ' · الاستحقاق ${_date(task.dueAt)}'}',
      textAlign: TextAlign.right,
      style: TextStyle(
        color: task.status != 'cancelled' && !task.isDone && _isLate(task.dueAt)
            ? Colors.red.shade700
            : AppColors.muted,
      ),
    ),
  );

  bool _isLate(String due) {
    final value = DateTime.tryParse(due);
    return value != null && value.isBefore(DateTime.now());
  }

  String _date(String raw) {
    final value = DateTime.tryParse(raw)?.toLocal();
    return value == null
        ? 'غير محدد'
        : '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';
  }

  String _priorityName(String priority) =>
      const {
        'urgent': 'عاجلة',
        'high': 'عالية',
        'normal': 'عادية',
        'low': 'منخفضة',
      }[priority] ??
      priority;
  String _statusName(String status) =>
      const {
        'completed_approved': 'مكتملة ومعتمدة',
        'approved': 'معتمدة',
        'cancelled': 'ملغاة',
        'report_submitted': 'التقرير مقدم',
        'submitted': 'مرسل للمراجعة',
        'pending': 'لم يبدأ',
        'needs_revision': 'يحتاج تعديل',
        'returned': 'معاد للتعديل',
        'late': 'متأخرة',
        'in_progress': 'قيد التنفيذ',
        'received': 'تم الاستلام',
        'new': 'جديدة',
        'on_hold': 'معلقة',
      }[status] ??
      (status.isEmpty ? 'غير محددة' : status);

  Widget _messageCard(
    String title,
    String text, {
    required VoidCallback onRetry,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: SectionCard(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(text, textAlign: TextAlign.right),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Task {
  const _Task({
    required this.id,
    required this.title,
    required this.priority,
    required this.status,
    required this.dueAt,
    required this.isDone,
  });
  final String id, title, priority, status, dueAt;
  final bool isDone;
}

class _Delivery {
  int receivedTotalMs = 0,
      receivedSamples = 0,
      openedTotalMs = 0,
      openedSamples = 0;
  int? get receivedAverage =>
      receivedSamples == 0 ? null : receivedTotalMs ~/ receivedSamples;
  int? get openedAverage =>
      openedSamples == 0 ? null : openedTotalMs ~/ openedSamples;
  void add(dynamic assignedRaw, dynamic receivedRaw, dynamic openedRaw) {
    final assigned = DateTime.tryParse(assignedRaw?.toString() ?? '');
    final received = DateTime.tryParse(receivedRaw?.toString() ?? '');
    final opened = DateTime.tryParse(openedRaw?.toString() ?? '');
    if (assigned != null && received != null && !received.isBefore(assigned)) {
      receivedTotalMs += received.difference(assigned).inMilliseconds;
      receivedSamples++;
    }
    if (received != null && opened != null && !opened.isBefore(received)) {
      openedTotalMs += opened.difference(received).inMilliseconds;
      openedSamples++;
    }
  }
}

class _Employee {
  _Employee({
    required this.id,
    required this.userId,
    required this.name,
    required this.roleCode,
    required this.roleName,
    required this.branchName,
    required this.reports,
  });
  final String id, userId, name, roleCode, roleName, branchName;
  final int reports;
  int delayed = 0;
  final Map<String, int> required = {
    'urgent': 0,
    'high': 0,
    'normal': 0,
    'low': 0,
  };
  final Map<String, int> done = {
    'urgent': 0,
    'high': 0,
    'normal': 0,
    'low': 0,
  };
  final List<_Task> tasks = [];
  final _Delivery delivery = _Delivery();
  int get totalRequired => required.values.fold(0, (a, b) => a + b);
  int get totalDone => done.values.fold(0, (a, b) => a + b);
  int get highRequired =>
      (required['high'] ?? 0) + (required['urgent'] ?? 0);
  int get highDone => (done['high'] ?? 0) + (done['urgent'] ?? 0);
  double get rate => totalRequired == 0 ? 0 : totalDone * 100 / totalRequired;
  double get highRate =>
      highRequired == 0 ? 100 : highDone * 100 / highRequired;
  double priorityRate(String key) =>
      (required[key] ?? 0) == 0 ? 0 : (done[key] ?? 0) * 100 / required[key]!;
}

class _Branch {
  _Branch(this.name);
  final String name;
  int staff = 0, required = 0, done = 0, highRequired = 0, highDone = 0;
  double get rate => required == 0 ? 0 : done * 100 / required;
}
