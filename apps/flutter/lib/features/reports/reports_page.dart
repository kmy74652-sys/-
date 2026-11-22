import 'package:material_ui/material_ui.dart';

import '../../shared/widgets/app_card.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  ReportStatus _status = ReportStatus.all;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('التقارير', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        const Text('إدارة مسودات التقارير ومتابعة دورة المراجعة والاعتماد.'),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ReportStatus.values.map((status) {
            return ChoiceChip(
              label: Text(status.label),
              selected: _status == status,
              onSelected: (_) => setState(() => _status = status),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        AppCard(
          child: Row(
            children: [
              Icon(
                Icons.fact_check_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'تتوافق الحالات مع قاعدة البيانات: draft ← submitted ← reviewed ← approved، مع دعم returned.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        EmptyState(
          icon: Icons.description_outlined,
          title: 'لا توجد تقارير في حالة «${_status.label}»',
          message: 'ستظهر النماذج والتقارير المرتبطة بالمهام بعد ربط مصدر Supabase الآمن.',
        ),
      ],
    );
  }
}

enum ReportStatus { all, draft, submitted, reviewed, approved, returned }

extension on ReportStatus {
  String get label {
    switch (this) {
      case ReportStatus.all:
        return 'الكل';
      case ReportStatus.draft:
        return 'مسودة';
      case ReportStatus.submitted:
        return 'مرسل';
      case ReportStatus.reviewed:
        return 'تمت مراجعته';
      case ReportStatus.approved:
        return 'معتمد';
      case ReportStatus.returned:
        return 'معاد للتعديل';
    }
  }
}
