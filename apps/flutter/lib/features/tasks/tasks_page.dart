import 'package:material_ui/material_ui.dart';

import '../../shared/widgets/app_card.dart';

class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  String _filter = 'الكل';
  final _filters = const [
    'الكل',
    'جديدة',
    'قيد التنفيذ',
    'بانتظار المراجعة',
    'معتمدة',
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('المهام', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        const Text(
          'متابعة المهام المسندة إليك أو المهام التي تملك صلاحية مراجعتها.',
        ),
        const SizedBox(height: 16),
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'البحث في المهام',
          ),
          onChanged: (_) {},
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _filters.map((filter) {
              return Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  label: Text(filter),
                  selected: _filter == filter,
                  onSelected: (_) => setState(() => _filter = filter),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 20),
        AppCard(
          child: Row(
            children: [
              Icon(
                Icons.security_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'سيتم عرض المهام حسب صلاحيات المستخدم وحالة الإسناد من Supabase.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const EmptyState(
          icon: Icons.assignment_outlined,
          title: 'لا توجد مهام محملة بعد',
          message: 'واجهة المهام جاهزة للتوصيل بطبقة البيانات. ستدعم التنفيذ والمراجعة مع فصل صلاحيات tasks.execute وtasks.review.',
        ),
      ],
    );
  }
}
