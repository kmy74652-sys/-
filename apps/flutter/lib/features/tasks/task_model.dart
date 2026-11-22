enum TaskStatus {
  pending,
  inProgress,
  submitted,
  approved,
  rejected,
  cancelled,
  late,
  unknown,
}

class TaskItem {
  const TaskItem({
    required this.id,
    required this.title,
    required this.description,
    required this.assigneeId,
    required this.branchId,
    required this.branchName,
    required this.branchLevel,
    required this.startsAt,
    required this.dueAt,
    required this.priority,
    required this.status,
    required this.proofRequired,
    required this.proofInstructions,
    required this.reportFlow,
    required this.deliveryStatus,
  });

  final String id;
  final String title;
  final String? description;
  final String? assigneeId;
  final String? branchId;
  final String? branchName;
  final int? branchLevel;
  final DateTime? startsAt;
  final DateTime? dueAt;
  final String priority;
  final TaskStatus status;
  final bool proofRequired;
  final String? proofInstructions;
  final String reportFlow;
  final String deliveryStatus;

  factory TaskItem.fromRow(
    Map<String, dynamic> row, {
    Map<String, dynamic>? branch,
  }) {
    final rawStatus = row['status']?.toString() ?? '';
    return TaskItem(
      id: _string(row['id']) ?? '',
      title: _string(row['title']) ?? 'مهمة دون عنوان',
      description: _string(row['description']),
      assigneeId:
          _string(row['assigned_to']) ?? _string(row['assignee_employee_id']),
      branchId: _string(row['branch_id']),
      branchName: _string(branch?['name']),
      branchLevel: _int(branch?['branch_level']),
      startsAt: _date(
        row['starts_at'] ?? row['assigned_at'] ?? row['created_at'],
      ),
      dueAt: _date(row['due_at']),
      priority: _string(row['priority']) ?? 'normal',
      status: TaskStatusParser.fromDatabase(rawStatus),
      proofRequired: row['proof_required'] == true,
      proofInstructions: _string(row['proof_instructions']),
      reportFlow: _string(row['report_flow']) ?? 'legacy',
      deliveryStatus: row['opened_at'] != null
          ? 'opened'
          : (row['received_at'] != null || rawStatus != 'new'
                ? 'received'
                : 'sent'),
    );
  }

  static String? _string(Object? value) =>
      value?.toString().trim().isEmpty == true ? null : value?.toString();

  static int? _int(Object? value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '');

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.tryParse(value.toString());
}

abstract final class TaskStatusParser {
  static TaskStatus fromDatabase(String value) {
    switch (value) {
      case 'new':
      case 'received':
      case 'pending':
        return TaskStatus.pending;
      case 'on_hold':
      case 'in_progress':
        return TaskStatus.inProgress;
      case 'report_submitted':
      case 'submitted':
        return TaskStatus.submitted;
      case 'completed_approved':
      case 'approved':
        return TaskStatus.approved;
      case 'needs_revision':
      case 'rejected':
        return TaskStatus.rejected;
      case 'cancelled':
        return TaskStatus.cancelled;
      case 'late':
        return TaskStatus.late;
      default:
        return TaskStatus.unknown;
    }
  }

  static String label(TaskStatus status) {
    switch (status) {
      case TaskStatus.pending:
        return 'جديدة';
      case TaskStatus.inProgress:
        return 'قيد التنفيذ';
      case TaskStatus.submitted:
        return 'بانتظار المراجعة';
      case TaskStatus.approved:
        return 'معتمدة';
      case TaskStatus.rejected:
        return 'تحتاج استكمالًا';
      case TaskStatus.cancelled:
        return 'ملغاة';
      case TaskStatus.late:
        return 'متأخرة';
      case TaskStatus.unknown:
        return 'غير محددة';
    }
  }
}
