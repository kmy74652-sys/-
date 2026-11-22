import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../shared/widgets/app_card.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'مرحبًا بك في إدارة الشاعري',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          'ملخص العمل اليومي والمهام والتقارير في مكان واحد.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: const [
            _SummaryCard(
              label: 'المهام الجديدة',
              value: '—',
              icon: Icons.assignment_late_outlined,
              color: Color(0xFFB9823B),
            ),
            _SummaryCard(
              label: 'قيد التنفيذ',
              value: '—',
              icon: Icons.timelapse_outlined,
              color: Color(0xFF287A8A),
            ),
            _SummaryCard(
              label: 'بانتظار المراجعة',
              value: '—',
              icon: Icons.rate_review_outlined,
              color: Color(0xFF6C4F9D),
            ),
            _SummaryCard(
              label: 'تقارير معتمدة',
              value: '—',
              icon: Icons.verified_outlined,
              color: Color(0xFF2E7D4F),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text('الوصول السريع', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            children: [
              _QuickAction(
                icon: Icons.assignment_outlined,
                title: 'متابعة المهام',
                subtitle: 'عرض المهام المسندة وحالات التنفيذ',
                onTap: () => context.go('/tasks'),
              ),
              const Divider(height: 24),
              _QuickAction(
                icon: Icons.description_outlined,
                title: 'إعداد التقارير',
                subtitle: 'متابعة المسودات والتقارير المرسلة',
                onTap: () => context.go('/reports'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const EmptyState(
          icon: Icons.cloud_sync_outlined,
          title: 'البيانات ستظهر هنا',
          message: 'سيتم ربط لوحة الملخص مباشرة بـ Supabase في مرحلة ربط البيانات، مع احترام الصلاحيات الحالية.',
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 14),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(child: Icon(icon)),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_left),
      onTap: onTap,
    );
  }
}
