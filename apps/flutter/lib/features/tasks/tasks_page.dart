import 'package:material_ui/material_ui.dart';

import '../../shared/widgets/app_card.dart';
import 'task_model.dart';
import 'task_repository.dart';

class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  final _repository = TaskRepository();
  final _searchController = TextEditingController();
  final _filters = const <String>[
    'الكل',
    'جديدة',
    'قيد التنفيذ',
    'بانتظار المراجعة',
    'معتمدة',
  ];

  List<TaskItem> _tasks = const [];
  TaskProfile? _profile;
  String _filter = 'الكل';
  String _search = '';
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTasks() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await _repository.loadProfile();
      final tasks = await _repository.listTasks(profile: profile);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _tasks = tasks;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = _friendlyError(error);
      });
    }
  }

  String _friendlyError(Object error) {
    final code = error is TaskDataException ? error.code : error.toString();
    if (code.contains('supabase_not_configured')) {
      return 'لم يتم إعداد مفاتيح Supabase لهذا التشغيل.';
    }
    if (code.contains('not_authenticated')) {
      return 'انتهت الجلسة. سجّل الدخول ثم حاول مرة أخرى.';
    }
    if (code.contains('employee_not_active')) {
      return 'لا يوجد ملف موظف نشط مرتبط بهذا الحساب.';
    }
    if (code.contains('PGRST202') || code.contains('mobile_my_profile')) {
      return 'دالة ملف الموظف غير متاحة في قاعدة البيانات الحالية.';
    }
    if (code.contains('PGRST205') || code.contains('42P01')) {
      return 'جدول المهام غير متاح في مخطط Supabase الحالي.';
    }
    return 'تعذر تحميل المهام من Supabase. تحقق من الاتصال والصلاحيات.';
  }

  List<TaskItem> get _visibleTasks {
    final query = _search.trim().toLowerCase();
    return _tasks.where((task) {
      final statusMatches =
          _filter == 'الكل' || TaskStatusParser.label(task.status) == _filter;
      final searchMatches =
          query.isEmpty ||
          '${task.title} ${task.description ?? ''} ${task.branchName ?? ''}'
              .toLowerCase()
              .contains(query);
      return statusMatches && searchMatches;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadTasks,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'المهام',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _profile == null
                          ? 'المهام المسندة وإجراءات المراجعة'
                          : 'مرحبًا ${_profile!.fullName}، هذه مهامك الحالية.',
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _loadTasks,
                tooltip: 'تحديث',
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'البحث في المهام',
            ),
            onChanged: (value) => setState(() => _search = value),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _filters
                  .map(
                    (filter) => Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        label: Text(filter),
                        selected: _filter == filter,
                        onSelected: (_) => setState(() => _filter = filter),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 20),
          if (_loading) const _LoadingState(),
          if (!_loading && _error != null)
            _ErrorState(message: _error!, onRetry: _loadTasks),
          if (!_loading && _error == null && _tasks.isNotEmpty)
            _TaskSummary(tasks: _tasks),
          if (!_loading && _error == null && _visibleTasks.isEmpty)
            const EmptyState(
              icon: Icons.assignment_outlined,
              title: 'لا توجد مهام مطابقة',
              message: 'لم تُرجع قاعدة البيانات مهامًا تطابق البحث أو الفلتر الحالي.',
            ),
          if (!_loading && _error == null)
            ..._visibleTasks.map(
              (task) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _TaskCard(task: task),
              ),
            ),
        ],
      ),
    );
  }
}

class _TaskSummary extends StatelessWidget {
  const _TaskSummary({required this.tasks});

  final List<TaskItem> tasks;

  @override
  Widget build(BuildContext context) {
    final active = tasks
        .where((task) => task.status == TaskStatus.inProgress)
        .length;
    final submitted = tasks
        .where((task) => task.status == TaskStatus.submitted)
        .length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(
            child: _SummaryValue(
              label: 'الإجمالي',
              value: tasks.length.toString(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _SummaryValue(
              label: 'قيد التنفيذ',
              value: active.toString(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _SummaryValue(
              label: 'للمراجعة',
              value: submitted.toString(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Column(
        children: [
          Text(value, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(label, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task});

  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(task.status);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  task.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              StatusPill(
                label: TaskStatusParser.label(task.status),
                color: color,
              ),
            ],
          ),
          if (task.description != null) ...[
            const SizedBox(height: 8),
            Text(
              task.description!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              if (task.branchName != null)
                _MetaItem(
                  icon: Icons.account_tree_outlined,
                  text: task.branchName!,
                ),
              _MetaItem(
                icon: Icons.flag_outlined,
                text: _priorityLabel(task.priority),
              ),
              if (task.dueAt != null)
                _MetaItem(
                  icon: Icons.event_outlined,
                  text: _formatDate(task.dueAt!),
                ),
            ],
          ),
          if (task.proofRequired || task.reportFlow == 'multi_form') ...[
            const Divider(height: 24),
            Text(
              task.proofRequired
                  ? 'تتطلب المهمة دليل إنجاز.'
                  : 'مرتبطة بنماذج تقرير متعددة.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  static Color _statusColor(TaskStatus status) {
    switch (status) {
      case TaskStatus.approved:
        return const Color(0xFF2E7D4F);
      case TaskStatus.submitted:
        return const Color(0xFF6C4F9D);
      case TaskStatus.inProgress:
        return const Color(0xFF287A8A);
      case TaskStatus.rejected:
      case TaskStatus.late:
        return const Color(0xFFB65C3A);
      default:
        return const Color(0xFFB9823B);
    }
  }

  static String _priorityLabel(String value) {
    const labels = {
      'normal': 'عادية',
      'important': 'مهمة',
      'urgent': 'عاجلة',
      'critical': 'حرجة',
    };
    return labels[value] ?? value;
  }

  static String _formatDate(DateTime value) =>
      '${value.day}/${value.month}/${value.year}';
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, size: 16), const SizedBox(width: 4), Text(text)],
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(32),
    child: Center(child: CircularProgressIndicator()),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          const Icon(Icons.cloud_off_outlined, size: 44),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }
}
