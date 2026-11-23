import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/deep_link_controller.dart';
import '../../core/theme.dart';
import '../../shared/organization_branding.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _employee = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  OrganizationBranding _branding = OrganizationBranding.fallback;
  Timer? _brandingTimer;

  void _queueBranding(String value) {
    _brandingTimer?.cancel();
    _brandingTimer = Timer(const Duration(milliseconds: 350), () async {
      final branding = await OrganizationBrandingStore.instance
          .forEmployeeNumber(value);
      if (mounted && value == _employee.text.trim()) {
        setState(() => _branding = branding);
      }
    });
  }
  Future<void> _login() async {
    final employeeNo = _employee.text.trim();
    final code = _code.text;
    if (employeeNo.isEmpty || code.isEmpty) {
      setState(() => _error = 'أدخل اسم الموظف ورمز الدخول.');
      return;
    }
    if (!RegExp(r'^\S{3,30}$').hasMatch(code)) {
      setState(
        () =>
            _error = 'يجب أن يتكون رمز الدخول من 3 إلى 30 محرفًا دون مسافات.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'employee-code-auth',
        body: {'action': 'login', 'employeeNo': employeeNo, 'code': code},
      );
      final data = response.data;
      if (response.status == 429)
        throw const _LoginFailure(
          'محاولات كثيرة. انتظر 15 دقيقة ثم حاول مجددًا.',
        );
      if (response.status == 401)
        throw const _LoginFailure('اسم الموظف أو رمز الدخول غير صحيح.');
      if (response.status == 404 || response.status == 503)
        throw const _LoginFailure(
          'خدمة الدخول بالرمز أو تحديث قاعدة البيانات غير جاهز في Supabase بعد.',
        );
      if (data is! Map ||
          data['access_token'] is! String ||
          data['refresh_token'] is! String)
        throw const _LoginFailure(
          'لم تُرجع خدمة الدخول جلسة صالحة. تحقق من إعداد Supabase.',
        );
      final client = Supabase.instance.client;
      await client.auth.setSession(data['refresh_token'] as String);
      final profile = await client.rpc('mobile_my_profile');
      final employee = profile is Map ? profile['employee'] : null;
      if (employee is! Map || employee['status']?.toString() != 'active') {
        await client.auth.signOut();
        throw const _LoginFailure('الحساب غير مرتبط بملف موظف نشط.');
      }
      final pending = await DeepLinkController().consumePending();
      if (mounted) context.go(pending ?? '/');
    } on FunctionException catch (e) {
      setState(
        () => _error = switch (e.status) {
          429 => 'محاولات كثيرة. انتظر 15 دقيقة ثم حاول مجددًا.',
          401 => 'اسم الموظف أو رمز الدخول غير صحيح.',
          404 || 503 => 'خدمة الدخول بالرمز أو تحديث قاعدة البيانات غير جاهز في Supabase بعد.',
          _ =>
            'تعذر الاتصال بخدمة تسجيل الدخول. تحقق من الإنترنت وحاول مجددًا.',
        },
      );
    } catch (e) {
      setState(
        () => _error = e is _LoginFailure ? e.message : 'تعذر إكمال تسجيل الدخول بسبب انقطاع الاتصال. تحقق من الإنترنت وحاول مجددًا.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _brandingTimer?.cancel();
    _employee.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _LoginBrandLogo(branding: _branding),
                    const SizedBox(height: 8),
                    const Text(
                      'بوابة العمل والتواصل الإداري',
                      textAlign: TextAlign.right,
                      style: TextStyle(color: AppColors.muted),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'مانجمنت',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'سجّل دخولك للوصول إلى مهامك، تقاريرك، وتنبيهات العمل في مكان واحد.',
                      textAlign: TextAlign.right,
                      style: TextStyle(color: AppColors.muted, height: 1.6),
                    ),
                    const SizedBox(height: 16),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    TextField(
                      controller: _employee,
                      enabled: !_busy,
                      textAlign: TextAlign.right,
                      textInputAction: TextInputAction.next,
                      onChanged: _queueBranding,
                      decoration: const InputDecoration(
                        labelText: 'الرقم الوظيفي',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _code,
                      enabled: !_busy,
                      obscureText: true,
                      textAlign: TextAlign.right,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _login(),
                      decoration: const InputDecoration(
                        labelText: 'كلمة المرور',
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _busy ? null : _login,
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.lock_open),
                      label: Text(_busy ? 'جارٍ تسجيل الدخول…' : 'دخول آمن'),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'نسيت الرمز أو لم يُعيّن لك بعد؟ تواصل مع الإدارة.',
                      textAlign: TextAlign.right,
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _LoginFailure implements Exception {
  const _LoginFailure(this.message);
  final String message;
}

class _LoginBrandLogo extends StatelessWidget {
  const _LoginBrandLogo({required this.branding});
  final OrganizationBranding branding;

  @override
  Widget build(BuildContext context) {
    final fallback = Image.asset(
      'assets/images/alshaeri-official-logo.png',
      height: 110,
      fit: BoxFit.contain,
    );
    final url = branding.logoUrl;
    if (url == null) return fallback;
    return Image.network(
      url,
      height: 110,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}
