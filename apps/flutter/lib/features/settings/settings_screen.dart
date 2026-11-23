import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../shared/app_shell.dart';
import '../../shared/organization_branding.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _db = Supabase.instance.client;
  bool _busy = true, _allowed = false, _owner = false;
  bool _brandBusy = false;
  String? _error;
  String _organizationId = '';
  String? _logoUrl;
  Uint8List? _pendingLogoBytes;
  String? _pendingLogoMime;
  List<Map<String, dynamic>> _people = [], _branches = [];
  final Map<String, List<Map<String, dynamic>>> _audit = {};
  final Map<String, TextEditingController> _loginCodes = {};
  String? _busyEmployeeId;
  final Set<String> _expandedEmployees = {};
  final _name = TextEditingController(),
      _number = TextEditingController(),
      _code = TextEditingController();
  final _brandName = TextEditingController(),
      _tagline = TextEditingController();
  String _role = 'warehouse_worker', _branchId = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _number.dispose();
    _code.dispose();
    _brandName.dispose();
    _tagline.dispose();
    for (final controller in _loginCodes.values) {
      controller.clear();
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted)
      setState(() {
        _busy = true;
        _error = null;
      });
    try {
      final result = await _db.rpc('mobile_my_profile');
      final root = Map<String, dynamic>.from(result as Map);
      final employee = Map<String, dynamic>.from(
        root['employee'] as Map? ?? {},
      );
      final roles = (employee['roles'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final permissions = (employee['permissions'] as List? ?? [])
          .map((e) => e.toString())
          .toSet();
      _owner = roles.any((r) => r['code'] == 'owner');
      // العقد الإداري يمنح هذه الوظائف للمالك والمدير التنفيذي المخوّل؛
      // لا نحصر الواجهة بالمالك ما دام الـBackend أعاد الصلاحية صراحة.
      _allowed = permissions.contains('employees.manage');
      _organizationId = '${employee['institutionId'] ?? ''}';
      if (!_allowed) {
        _people = [];
        return;
      }
      final response = await _db.functions.invoke(
        'employee-code-auth',
        body: {'action': 'list'},
      );
      if (response.data is! Map) throw Exception('تعذر قراءة قائمة الموظفين.');
      final data = Map<String, dynamic>.from(response.data as Map);
      _people = (data['employees'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      _branches = (data['branches'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((e) => e['is_active'] == true)
          .toList();
      final brand = await _db
          .from('organizations')
          .select('name,settings')
          .eq('id', _organizationId)
          .maybeSingle();
      _brandName.text = '${brand?['name'] ?? ''}';
      final settings = Map<String, dynamic>.from(
        brand?['settings'] as Map? ?? {},
      );
      final branding = Map<String, dynamic>.from(
        settings['branding'] as Map? ?? {},
      );
      _tagline.text = '${branding['tagline'] ?? ''}';
      _logoUrl = branding['logo_url'] as String?;
    } catch (_) {
      _error = 'تعذر تحميل الإعدادات. تحقق من الصلاحيات والاتصال.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    if (_name.text.trim().length < 2 ||
        !RegExp(r'^\d{1,32}$').hasMatch(_number.text.trim()) ||
        !RegExp(r'^\S{8,64}$').hasMatch(_code.text) ||
        (_role != 'owner' && _branchId.isEmpty)) {
      setState(
        () => _error =
            'أدخل الاسم والرقم الوظيفي ورمزًا من 8 إلى 64 محرفًا واختر الفرع.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _db.functions.invoke(
        'employee-code-auth',
        body: {
          'action': 'create_employee',
          'employeeNo': _number.text.trim(),
          'fullName': _name.text.trim(),
          'code': _code.text,
          'roleCode': _role,
          'branchId': _role == 'owner' ? null : _branchId,
        },
      );
      _name.clear();
      _number.clear();
      _code.clear();
      await _load();
    } catch (_) {
      if (mounted)
        setState(() {
          _busy = false;
          _error = 'تعذر إنشاء الحساب؛ راجع صلاحياتك ومدخلاتك.';
        });
    }
  }

  Future<void> _edit(Map<String, dynamic> person) async {
    final name = TextEditingController(text: '${person['fullName'] ?? ''}');
    final number = TextEditingController(text: '${person['employeeNo'] ?? ''}');
    var role = '${person['roleCode'] ?? 'warehouse_worker'}';
    var branch = '${person['branchId'] ?? ''}';
    var status = person['status'] == 'active' ? 'active' : 'suspended';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('تعديل بيانات الموظف', textAlign: TextAlign.right),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'الاسم'),
                ),
                TextField(
                  controller: number,
                  decoration: const InputDecoration(labelText: 'الرقم الوظيفي'),
                ),
                DropdownButtonFormField<String>(
                  value: role,
                  decoration: const InputDecoration(labelText: 'الدور'),
                  items: [
                    const DropdownMenuItem(
                      value: 'admin_followup',
                      child: Text('المدير التنفيذي'),
                    ),
                    const DropdownMenuItem(
                      value: 'accountant',
                      child: Text('المحاسب'),
                    ),
                    const DropdownMenuItem(
                      value: 'warehouse_keeper',
                      child: Text('أمين المخازن'),
                    ),
                    const DropdownMenuItem(
                      value: 'warehouse_worker',
                      child: Text('عامل تحميل'),
                    ),
                    if (_owner)
                      const DropdownMenuItem(
                        value: 'owner',
                        child: Text('صاحب المؤسسة'),
                      ),
                  ],
                  onChanged: (v) => refresh(() => role = v ?? role),
                ),
                if (role != 'owner')
                  DropdownButtonFormField<String>(
                    value: _branches.any((b) => b['id'] == branch)
                        ? branch
                        : null,
                    decoration: const InputDecoration(labelText: 'الفرع'),
                    items: _branches
                        .map(
                          (b) => DropdownMenuItem(
                            value: '${b['id']}',
                            child: Text('${b['name']}'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => refresh(() => branch = v ?? ''),
                  ),
                SwitchListTile(
                  title: const Text('الحساب نشط'),
                  value: status == 'active',
                  onChanged: (v) =>
                      refresh(() => status = v ? 'active' : 'suspended'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                if (status !=
                    (person['status'] == 'active' ? 'active' : 'suspended')) {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('تأكيد تغيير الحالة'),
                      content: const Text(
                        'سيؤثر هذا الإجراء على قدرة الموظف على استخدام حسابه. متابعة؟',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('رجوع'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('تأكيد'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                }
                try {
                  await _db.functions.invoke(
                    'employee-code-auth',
                    body: {
                      'action': 'update_employee',
                      'employeeId': person['id'],
                      'employeeNo': number.text.trim(),
                      'fullName': name.text.trim(),
                      'roleCode': role,
                      'branchId': role == 'owner' ? null : branch,
                      'status': status,
                    },
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  await _load();
                } catch (_) {
                  if (mounted) setState(() => _error = 'تعذر تحديث الموظف.');
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    number.dispose();
  }

  Future<void> _revoke(Map<String, dynamic> person) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('إلغاء رمز الدخول'),
        content: Text(
          'سيُمنع ${person['fullName'] ?? 'الموظف'} من تسجيل دخول جديد بهذا الرمز، ولن تُنهى الجلسات الحالية فورًا. متابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('تأكيد الإلغاء'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _db.functions.invoke(
        'employee-code-auth',
        body: {'action': 'revoke_code', 'employeeId': person['id']},
      );
      await _load();
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر إلغاء رمز الدخول.');
    }
  }

  TextEditingController _loginCodeController(String id) =>
      _loginCodes.putIfAbsent(id, TextEditingController.new);

  Future<void> _setEmployeeCode(Map<String, dynamic> person) async {
    final id = '${person['id'] ?? ''}';
    final controller = _loginCodeController(id);
    final code = controller.text;
    if (!_allowed ||
        person['status'] != 'active' ||
        person['hasAuthAccount'] != true)
      return;
    if (!RegExp(r'^\S{8,64}$').hasMatch(code)) {
      setState(() => _error = 'اكتب رمزًا من 8 إلى 64 محرفًا دون مسافات.');
      return;
    }
    setState(() {
      _busyEmployeeId = id;
      _error = null;
    });
    try {
      await _db.functions.invoke(
        'employee-code-auth',
        body: {'action': 'set_code', 'employeeId': id, 'code': code},
      );
      controller.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم تحديث رمز دخول ${person['fullName'] ?? 'الموظف'}؛ لن يظهر الرمز المحفوظ.',
            ),
          ),
        );
        await _load();
      }
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'تعذر حفظ الرمز. تحقق من الاتصال والصلاحية ثم حاول مجددًا.',
        );
    } finally {
      if (mounted) setState(() => _busyEmployeeId = null);
    }
  }

  Future<void> _loadAudit(Map<String, dynamic> person) async {
    final id = '${person['id'] ?? ''}';
    if (!_allowed) return;
    setState(() {
      _busyEmployeeId = id;
      _error = null;
    });
    try {
      final response = await _db.functions.invoke(
        'employee-code-auth',
        body: {'action': 'audit', 'employeeId': id},
      );
      final data = Map<String, dynamic>.from(response.data as Map);
      final rows = (data['audit'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (mounted) setState(() => _audit[id] = rows);
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر تحميل سجل التعديلات.');
    } finally {
      if (mounted) setState(() => _busyEmployeeId = null);
    }
  }

  Future<void> _deleteEmployee(Map<String, dynamic> person) async {
    if (!_allowed || person['roleCode'] == 'owner') return;
    final name = '${person['fullName'] ?? 'الموظف'}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('حذف حساب الموظف نهائيًا'),
        content: Text(
          'سيُحذف حساب $name وملف الموظف ورمز الدخول نهائيًا. هذا الإجراء تدميري ولا يمكن التراجع عنه. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('حذف نهائي'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final id = '${person['id'] ?? ''}';
    setState(() {
      _busyEmployeeId = id;
      _error = null;
    });
    try {
      await _db.rpc(
        'admin_delete_employee_record',
        params: {
          'p_organization_id': _organizationId,
          'p_membership_id': person['id'],
        },
      );
      _loginCodes.remove(id)?.dispose();
      _audit.remove(id);
      await _load();
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تم حذف حساب $name نهائيًا.')));
    } catch (_) {
      if (mounted)
        setState(
          () => _error = 'تعذر حذف حساب الموظف. تحقق من الصلاحية والاتصال.',
        );
    } finally {
      if (mounted) setState(() => _busyEmployeeId = null);
    }
  }

  Future<void> _saveBrand() async {
    if (!_owner || _organizationId.isEmpty || _brandBusy) return;
    setState(() {
      _brandBusy = true;
      _error = null;
    });
    var uploadingLogo = false;
    try {
      var logoUrl = _logoUrl;
      if (_pendingLogoBytes != null) {
        final mimeType = _pendingLogoMime;
        if (mimeType == null ||
            !const {
              'image/jpeg',
              'image/png',
              'image/webp',
            }.contains(mimeType)) {
          throw Exception('نوع صورة الشعار غير مدعوم.');
        }
        // مسار جديد لكل نسخة يمنع عرض الصورة القديمة من CDN
        // ولا يعتمد على صلاحية update في Storage عند الاستبدال.
        final path =
            '$_organizationId/logo_${DateTime.now().microsecondsSinceEpoch}';
        uploadingLogo = true;
        await _db.storage
            .from('organization-branding')
            .uploadBinary(
              path,
              _pendingLogoBytes!,
              fileOptions: FileOptions(
                contentType: mimeType,
                cacheControl: 'no-cache',
                upsert: false,
              ),
            );
        uploadingLogo = false;
        final publicUrl = _db.storage
            .from('organization-branding')
            .getPublicUrl(path);
        logoUrl = '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';
      }
      if (!mounted) return;
      await _db.rpc(
        'save_organization_branding',
        params: {
          'p_organization_id': _organizationId,
          'p_name': _brandName.text.trim(),
          'p_tagline': _tagline.text.trim(),
          'p_logo_url': logoUrl,
        },
      );
      OrganizationBrandingStore.instance.invalidate();
      if (mounted) {
        setState(() {
          _logoUrl = logoUrl;
          _pendingLogoBytes = null;
          _pendingLogoMime = null;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم حفظ بيانات الهوية.')));
      }
    } catch (_) {
      if (mounted)
        setState(
          () => _error = uploadingLogo
              ? 'تعذر رفع الشعار. تحقق من الاتصال وصلاحية التخزين ثم أعد المحاولة.'
              : 'تعذر حفظ الهوية؛ تأكد من تطبيق تحديث قاعدة البيانات.',
        );
    } finally {
      if (mounted) setState(() => _brandBusy = false);
    }
  }

  Future<void> _pickLogo() async {
    if (!_owner || _brandBusy) return;
    try {
      final image = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (image == null || !mounted) return;
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      if (bytes.isEmpty) {
        setState(() => _error = 'تعذرت قراءة صورة الشعار.');
        return;
      }
      if (bytes.length > 5 * 1024 * 1024) {
        setState(() => _error = 'حجم الشعار يجب ألا يتجاوز 5 ميجابايت.');
        return;
      }
      var mimeType = image.mimeType?.toLowerCase();
      if (mimeType == null || mimeType.isEmpty) {
        final filename = image.name.toLowerCase();
        mimeType = filename.endsWith('.jpg') || filename.endsWith('.jpeg')
            ? 'image/jpeg'
            : filename.endsWith('.png')
            ? 'image/png'
            : filename.endsWith('.webp')
            ? 'image/webp'
            : null;
      }
      if (!const {'image/jpeg', 'image/png', 'image/webp'}.contains(mimeType)) {
        setState(() => _error = 'اختر صورة بصيغة JPEG أو PNG أو WebP.');
        return;
      }
      setState(() {
        _pendingLogoBytes = bytes;
        _pendingLogoMime = mimeType;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر اختيار صورة الشعار.');
    }
  }

  @override
  Widget build(BuildContext context) => AppShell(
    title: 'الموظفون والإعدادات',
    subtitle: 'إدارة وفق الصلاحيات الممنوحة',
    child: _busy
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                if (!_allowed)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'قائمة الموظفين والإعدادات الإدارية متاحة لصاحب المؤسسة أو المدير التنفيذي المخوّل فقط.',
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ),
                if (_allowed && _owner)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'هوية المؤسسة',
                            textAlign: TextAlign.right,
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            height: 150,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.canvas,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: _pendingLogoBytes != null
                                ? Image.memory(
                                    _pendingLogoBytes!,
                                    fit: BoxFit.contain,
                                  )
                                : (_logoUrl != null && _logoUrl!.isNotEmpty
                                      ? Image.network(
                                          _logoUrl!,
                                          fit: BoxFit.contain,
                                          errorBuilder: (_, __, ___) => const Icon(
                                            Icons.business_outlined,
                                            size: 64,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.business_outlined,
                                          size: 64,
                                        )),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _brandName,
                            decoration: const InputDecoration(
                              labelText: 'اسم المؤسسة',
                            ),
                          ),
                          TextField(
                            controller: _tagline,
                            decoration: const InputDecoration(
                              labelText: 'العبارة التعريفية',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _brandBusy ? null : _pickLogo,
                            icon: const Icon(Icons.image_outlined),
                            label: const Text(
                              'اختيار شعار (JPEG أو PNG أو WebP، حتى 5 ميجابايت)',
                            ),
                          ),
                          if (_brandBusy) const LinearProgressIndicator(),
                          FilledButton(
                            onPressed: _brandBusy ? null : _saveBrand,
                            child: Text(
                              _brandBusy
                                  ? 'جارٍ رفع الشعار وحفظ الهوية…'
                                  : 'حفظ الهوية',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_allowed && _owner)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.dashboard_customize_outlined),
                      title: const Text(
                        'مصمم الواجهات والتخصيص الشامل',
                        textAlign: TextAlign.right,
                      ),
                      subtitle: const Text(
                        'تعديل التسميات والترتيب والألوان والنسخ الاحتياطي',
                        textAlign: TextAlign.right,
                      ),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => context.push('/admin/customizer'),
                    ),
                  ),
                if (_allowed)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'إنشاء حساب موظف',
                            textAlign: TextAlign.right,
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextField(
                            controller: _name,
                            decoration: const InputDecoration(
                              labelText: 'الاسم',
                            ),
                          ),
                          TextField(
                            controller: _number,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'الرقم الوظيفي',
                            ),
                          ),
                          TextField(
                            controller: _code,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'رمز الدخول الأولي (8–64 محرفًا)',
                            ),
                          ),
                          DropdownButtonFormField<String>(
                            value: _role,
                            decoration: const InputDecoration(
                              labelText: 'الدور',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'admin_followup',
                                child: Text('المدير التنفيذي'),
                              ),
                              DropdownMenuItem(
                                value: 'accountant',
                                child: Text('المحاسب'),
                              ),
                              DropdownMenuItem(
                                value: 'warehouse_keeper',
                                child: Text('أمين المخازن'),
                              ),
                              DropdownMenuItem(
                                value: 'warehouse_worker',
                                child: Text('عامل تحميل'),
                              ),
                            ],
                            onChanged: (v) =>
                                setState(() => _role = v ?? _role),
                          ),
                          DropdownButtonFormField<String>(
                            value: _branches.any((b) => b['id'] == _branchId)
                                ? _branchId
                                : null,
                            decoration: const InputDecoration(
                              labelText: 'الفرع',
                            ),
                            items: _branches
                                .map(
                                  (b) => DropdownMenuItem(
                                    value: '${b['id']}',
                                    child: Text('${b['name']}'),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _branchId = v ?? ''),
                          ),
                          FilledButton(
                            onPressed: _create,
                            child: const Text('إنشاء الحساب'),
                          ),
                        ],
                      ),
                    ),
                  ),
                for (final person in _people) ...[
                  Card(
                    child: ListTile(
                      leading: Icon(
                        person['status'] == 'active'
                            ? Icons.verified_user_outlined
                            : Icons.person_off_outlined,
                        color: AppColors.green,
                      ),
                      title: Text(
                        '${person['fullName'] ?? 'موظف'}',
                        textAlign: TextAlign.right,
                      ),
                      subtitle: Text(
                        '${person['employeeNo'] ?? 'بدون رقم'} · ${person['status'] == 'active' ? 'نشط' : 'غير نشط'} · ${person['roleCode'] ?? 'دون دور'}',
                        textAlign: TextAlign.right,
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'edit') _edit(person);
                          if (v == 'revoke') _revoke(person);
                          if (v == 'code') _setEmployeeCode(person);
                          if (v == 'audit') _loadAudit(person);
                          if (v == 'delete') _deleteEmployee(person);
                          if (v == 'expand')
                            setState(() {
                              final id = '${person['id']}';
                              if (!_expandedEmployees.add(id))
                                _expandedEmployees.remove(id);
                            });
                        },
                        itemBuilder: (_) => [
                          if (_owner || person['roleCode'] != 'owner')
                            const PopupMenuItem(
                              value: 'edit',
                              child: Text('تعديل'),
                            ),
                          PopupMenuItem(
                            value: 'expand',
                            child: Text(
                              _expandedEmployees.contains('${person['id']}')
                                  ? 'إغلاق إدارة الحساب'
                                  : 'إدارة الحساب والرمز',
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'audit',
                            child: Text('تحميل سجل التعديلات'),
                          ),
                          if (person['codeSetAt'] != null)
                            const PopupMenuItem(
                              value: 'revoke',
                              child: Text('إلغاء رمز الدخول'),
                            ),
                          if (person['roleCode'] != 'owner')
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('حذف الحساب نهائيًا'),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (_expandedEmployees.contains('${person['id']}')) ...[
                    if (_busyEmployeeId == '${person['id']}')
                      const LinearProgressIndicator(),
                    if (person['status'] == 'active' &&
                        person['hasAuthAccount'] == true)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _loginCodeController(
                                '${person['id']}',
                              ),
                              obscureText: true,
                              maxLength: 64,
                              enabled: _busyEmployeeId == null,
                              decoration: InputDecoration(
                                labelText: person['codeSetAt'] != null
                                    ? 'أدخل رمزًا جديدًا للتغيير'
                                    : 'أنشئ رمز دخول لهذا الموظف',
                              ),
                            ),
                            FilledButton(
                              onPressed: _busyEmployeeId == null
                                  ? () => _setEmployeeCode(person)
                                  : null,
                              child: Text(
                                person['codeSetAt'] != null
                                    ? 'تغيير الرمز'
                                    : 'تعيين الرمز',
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (person['status'] == 'active' &&
                        person['hasAuthAccount'] != true)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'لا يوجد حساب مصادقة مرتبط؛ لا يمكن تعيين رمز دخول حتى يربطه مسؤول النظام.',
                          textAlign: TextAlign.right,
                        ),
                      ),
                    for (final entry
                        in _audit['${person['id']}'] ??
                            const <Map<String, dynamic>>[])
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: Text(
                          '${entry['action'] ?? 'إجراء'} · ${DateTime.tryParse('${entry['created_at'] ?? ''}')?.toLocal().toString() ?? entry['created_at'] ?? ''}',
                          textAlign: TextAlign.right,
                        ),
                      ),
                  ],
                ],
              ],
            ),
          ),
  );
}
