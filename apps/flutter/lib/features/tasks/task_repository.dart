import 'package:supabase_flutter/supabase_flutter.dart';

import 'task_model.dart';

class TaskRepository {
  TaskRepository({this.client});

  final SupabaseClient? client;

  SupabaseClient get dbClient {
    if (client != null) {
      return client!;
    }
    try {
      return Supabase.instance.client;
    } on Object {
      throw const TaskDataException('supabase_not_configured');
    }
  }

  Future<TaskProfile> loadProfile() async {
    final auth = await dbClient.auth.getUser();
    final user = auth.user;
    if (user == null) throw const TaskDataException('not_authenticated');

    final response = await dbClient.rpc('mobile_my_profile');
    final root = _map(response);
    final employee = _map(root['employee']);
    if (employee.isEmpty) throw const TaskDataException('employee_not_active');

    return TaskProfile(
      userId: user.id,
      institutionId: _string(
        employee['institutionId'] ?? employee['institution_id'],
      ),
      employeeId: _string(employee['id']),
      fullName:
          _string(employee['fullName'] ?? employee['full_name']) ?? 'المستخدم',
      permissions: _stringList(employee['permissions']),
    );
  }

  Future<List<TaskItem>> listTasks({TaskProfile? profile}) async {
    final current = profile ?? await loadProfile();
    final canViewAll =
        current.permissions.contains('tasks.manage') ||
        current.permissions.contains('tasks.review');

    dynamic query = dbClient
        .from('tasks')
        .select(
          'id,title,description,assigned_to,branch_id,priority,status,assigned_at,received_at,opened_at,created_at,starts_at,due_at,report_flow,task_instructions,proof_required,proof_instructions',
        )
        .isFilter('deleted_at', null)
        .order('due_at', ascending: true)
        .order('id', ascending: true);

    if (current.institutionId != null) {
      query = query.eq('organization_id', current.institutionId!);
    }
    if (!canViewAll) {
      query = query.eq('assigned_to', current.userId);
    }

    final rows = await _readPages(query);
    final branchIds = rows
        .map((row) => _string(row['branch_id']))
        .whereType<String>()
        .toSet()
        .toList();
    final branches = await _readBranches(branchIds);

    return rows
        .map(
          (row) => TaskItem.fromRow(
            row,
            branch: branches[_string(row['branch_id'])],
          ),
        )
        .toList();
  }

  Future<List<Map<String, dynamic>>> _readPages(dynamic query) async {
    final rows = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += 500) {
      final page = await query.range(offset, offset + 499);
      final values = (page as List<dynamic>).map(_map).toList();
      rows.addAll(values);
      if (values.length < 500) return rows;
    }
  }

  Future<Map<String, Map<String, dynamic>>> _readBranches(
    List<String> ids,
  ) async {
    if (ids.isEmpty) return {};
    final response = await dbClient
        .from('branches')
        .select('id,name,branch_level')
        .inFilter('id', ids);
    final result = <String, Map<String, dynamic>>{};
    for (final row in response as List<dynamic>) {
      final mapped = _map(row);
      final id = _string(mapped['id']);
      if (id != null) result[id] = mapped;
    }
    return result;
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  static String? _string(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value.map(_string).whereType<String>().toList();
  }
}

class TaskProfile {
  const TaskProfile({
    required this.userId,
    required this.institutionId,
    required this.employeeId,
    required this.fullName,
    required this.permissions,
  });

  final String userId;
  final String? institutionId;
  final String? employeeId;
  final String fullName;
  final List<String> permissions;
}

class TaskDataException implements Exception {
  const TaskDataException(this.code);

  final String code;

  @override
  String toString() => code;
}
