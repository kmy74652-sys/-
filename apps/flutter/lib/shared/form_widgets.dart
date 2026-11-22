
class ChoiceChipsField<T> extends StatelessWidget {
  const ChoiceChipsField({super.key, required this.label, required this.value, required this.options, required this.onChanged});
  final String label;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12.5, fontWeight: FontWeight.w700)),
    const SizedBox(height: 6),
    Wrap(spacing: 8, children: [for (final option in options) ChoiceChip(label: Text(option.$2), selected: option.$1 == value, onSelected: (_) => onChanged(option.$1))]),
  ]);
}
