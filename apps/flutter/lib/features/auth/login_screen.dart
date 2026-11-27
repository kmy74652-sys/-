import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    final employeeNumber = value.trim();
    if (employeeNumber.length < 3 || employeeNumber.length > 30) {
      if (mounted && _branding != OrganizationBranding.fallback) {
        setState(() => _branding = OrganizationBranding.fallback);
      }
      return;
    }
    _brandingTimer = Timer(const Duration(milliseconds: 350), () async {
      final branding = await OrganizationBrandingStore.instance
          .forEmployeeNumber(employeeNumber);
      if (mounted && employeeNumber == _employee.text.trim()) {
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
      if (!mounted) return;
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
      if (!mounted) return;
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
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      backgroundColor: const Color(0xFFF2F6FB),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                margin: EdgeInsets.zero,
                elevation: 7,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                  side: const BorderSide(color: Color(0xFFD5E1EC)),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _LoginBrandLogo(branding: _branding),
                    const SizedBox(height: 10),
                    const Text(
                      'بوابة العمل والتواصل الإداري',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'NEXORA',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        color: AppColors.navy,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Smart Business Management',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFFD9A441),
                        fontWeight: FontWeight.w700,
                        letterSpacing: .3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'سجّل دخولك للوصول إلى مهامك، تقاريرك، وتنبيهات العمل في مكان واحد.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted, height: 1.5),
                    ),
                    const SizedBox(height: 20),
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
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textInputAction: TextInputAction.next,
                      onChanged: _queueBranding,
                      decoration: const InputDecoration(
                        labelText: 'الرقم الوظيفي',
                        hintText: 'أدخل الرقم الوظيفي',
                        prefixIcon: Icon(Icons.badge_outlined),
                        filled: true,
                        fillColor: Color(0xFFF8FAFD),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(16)),
                        ),
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
                        labelText: 'رمز الدخول',
                        prefixIcon: Icon(Icons.lock_outline),
                        filled: true,
                        fillColor: Color(0xFFF8FAFD),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(16)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 54,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _login,
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.login_rounded),
                        label: Text(_busy ? 'جارٍ تسجيل الدخول…' : 'دخول آمن'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'نسيت رمز الدخول أو لم يُعيّن لك بعد؟ تواصل مع الإدارة.',
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
    final url = branding.logoUrl;
    if (url == null || url.trim().isEmpty) {
      return Container(
        height: 78,
        width: 78,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFFEAF1F8),
          border: Border.all(color: const Color(0xFFD9A441), width: 2),
        ),
        child: const Icon(
          Icons.business_center_outlined,
          size: 38,
          color: AppColors.navy,
        ),
      );
    }
    return Image.network(
      url,
      height: 78,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const Icon(
        Icons.business_center_outlined,
        size: 46,
        color: AppColors.navy,
      ),
    );
  }
}
