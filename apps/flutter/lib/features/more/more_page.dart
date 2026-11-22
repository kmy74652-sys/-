import 'package:material_ui/material_ui.dart';

import '../../shared/widgets/app_card.dart';

class MorePage extends StatelessWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('المزيد', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        const AppCard(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(child: Icon(Icons.person_outline)),
            title: Text('حساب الموظف'),
            subtitle: Text('سيتم ربط الملف والصلاحيات من Supabase'),
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            children: const [
              ListTile(
                leading: Icon(Icons.settings_outlined),
                title: Text('الإعدادات'),
                trailing: Icon(Icons.chevron_left),
              ),
              Divider(height: 1),
              ListTile(
                leading: Icon(Icons.help_outline),
                title: Text('المساعدة والدعم'),
                trailing: Icon(Icons.chevron_left),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
