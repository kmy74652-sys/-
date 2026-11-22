import 'package:flutter/material.dart';
import '../core/theme.dart';

const _months = <String>['يناير','فبراير','مارس','أبريل','مايو','يونيو','يوليو','أغسطس','سبتمبر','أكتوبر','نوفمبر','ديسمبر'];
const _days = <String>['الاثنين','الثلاثاء','الأربعاء','الخميس','الجمعة','السبت','الأحد'];
String formatArabicDate(DateTime d) => '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]} ${d.year}';
String formatArabicTime(DateTime d) => '${d.hour % 12 == 0 ? 12 : d.hour % 12}:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'ص' : 'م'}';
DateTime defaultDueDate() { final d = DateTime.now().add(const Duration(days: 1)); return DateTime(d.year, d.month, d.day, 17); }
String dueToIso(DateTime value) => value.toUtc().toIso8601String();
InputDecoration formDecoration(String label, {String? hint, Widget? suffixIcon}) => InputDecoration(labelText: label, hintText: hint, suffixIcon: suffixIcon, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14));

class FormSection extends StatelessWidget {
  const FormSection({super.key, required this.title, required this.icon, required this.children, this.note});
  final String title; final IconData icon; final List<Widget> children; final String? note;
  @override Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [Icon(icon, size: 20, color: AppColors.green), const SizedBox(width: 8), Expanded(child: Text(title, style: const TextStyle(color: AppColors.navy, fontSize: 15, fontWeight: FontWeight.w900)))]),
      if (note != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(note!, style: const TextStyle(color: AppColors.muted, fontSize: 11.5))),
      const SizedBox(height: 12), for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 12), children[i]],
    ]),
  );
}

class DueDateField extends StatelessWidget {
  const DueDateField({super.key, required this.value, required this.onChanged});
  final DateTime value; final ValueChanged<DateTime> onChanged;
  Future<void> _date(BuildContext c) async { final d = await showDatePicker(context: c, initialDate: value, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 1825)), helpText: 'اختر تاريخ الاستحقاق', confirmText: 'تأكيد', cancelText: 'إلغاء'); if (d != null) onChanged(DateTime(d.year, d.month, d.day, value.hour, value.minute)); }
  Future<void> _time(BuildContext c) async { final t = await showTimePicker(context: c, initialTime: TimeOfDay.fromDateTime(value), helpText: 'اختر وقت الاستحقاق', confirmText: 'تأكيد', cancelText: 'إلغاء'); if (t != null) onChanged(DateTime(value.year, value.month, value.day, t.hour, t.minute)); }
  void _quick(int days) { final d = DateTime.now().add(Duration(days: days)); onChanged(DateTime(d.year, d.month, d.day, value.hour, value.minute)); }
  Widget _picker(String label, String text, IconData icon, VoidCallback tap) => InkWell(onTap: tap, borderRadius: BorderRadius.circular(12), child: InputDecorator(decoration: formDecoration(label, suffixIcon: Icon(icon, size: 19, color: AppColors.navy)), child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w700))));
  @override Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Row(children: [Expanded(child: _picker('التاريخ', formatArabicDate(value), Icons.calendar_month_outlined, () => _date(context))), const SizedBox(width: 10), Expanded(child: _picker('الوقت', formatArabicTime(value), Icons.schedule, () => _time(context)))]),
    const SizedBox(height: 8), Wrap(spacing: 7, children: [ActionChip(label: const Text('اليوم'), onPressed: () => _quick(0)), ActionChip(label: const Text('غدًا'), onPressed: () => _quick(1)), ActionChip(label: const Text('بعد 3 أيام'), onPressed: () => _quick(3)), ActionChip(label: const Text('بعد أسبوع'), onPressed: () => _quick(7))]),
  ]);
}

class ChoiceChipsField<T> extends StatelessWidget {
  const ChoiceChipsField({super.key, required this.label, required this.value, required this.options, required this.onChanged});
  final String label; final T value; final List<(T, String)> options; final ValueChanged<T> onChanged;
  @override Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12.5, fontWeight: FontWeight.w700)), const SizedBox(height: 6), Wrap(spacing: 8, children: [for (final option in options) ChoiceChip(label: Text(option.$2), selected: option.$1 == value, onSelected: (_) => onChanged(option.$1))])]);
}

Future<bool?> showFormSheet(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  required List<Widget> Function(BuildContext, StateSetter) builder,
  required bool Function(StateSetter) onConfirm,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: const Color(0xFFF5F7FD),
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
  builder: (sheet) => Directionality(
    textDirection: TextDirection.rtl,
    child: StatefulBuilder(
      builder: (ctx, set) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: FractionallySizedBox(
          heightFactor: .94,
          child: Column(
            children: [
              Padding(padding: const EdgeInsets.fromLTRB(18, 14, 8, 8), child: Row(children: [Expanded(child: Text(title, style: const TextStyle(color: AppColors.navy, fontSize: 20, fontWeight: FontWeight.w900))), IconButton(onPressed: () => Navigator.pop(sheet, false), icon: const Icon(Icons.close))])),
              const Divider(height: 1),
              Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 8), keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, children: builder(ctx, set))),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.border))),
                child: Row(children: [
                  Expanded(child: OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)), onPressed: () => Navigator.pop(sheet, false), child: const Text('إلغاء'))),
                  const SizedBox(width: 10),
                  Expanded(flex: 2, child: FilledButton(style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)), onPressed: () { if (onConfirm(set)) Navigator.pop(sheet, true); }, child: Text(confirmLabel))),
                ]),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);
