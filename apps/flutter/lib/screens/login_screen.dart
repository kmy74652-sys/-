import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.isSupabaseConfigured});

  final bool isSupabaseConfigured;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _employeeNumberController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _employeeNumberController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;

    if (!widget.isSupabaseConfigured) {
      _showMessage('الاتصال بقاعدة البيانات غير مُعدّ بعد.');
      return;
    }
    final code = _passwordController.text;
    if (code.length < 8 || code.length > 64 || code.contains(RegExp(r'\s'))) {
      _showMessage('يجب أن تتكون كلمة المرور من 8 إلى 64 محرفاً دون مسافات.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final client = Supabase.instance.client;
      final result = await client.functions.invoke(
        'employee-code-auth',
        body: {
          'action': 'login',
          'employeeNo': _employeeNumberController.text.trim(),
          'code': code,
        },
      );

      final payload = result.data;
      if (result.status != 200 || payload is! Map ||
          payload['access_token'] is! String || payload['refresh_token'] is! String) {
        _showMessage('لم تُرجع خدمة الدخول جلسة صالحة. تحقق من إعداد Supabase.');
        return;
      }

      await client.auth.setSession(payload['refresh_token'] as String);
      if (!mounted) return;
      _showMessage('تم تسجيل الدخول بنجاح.');
    } on FunctionException catch (error) {
      if (mounted) {
        final status = error.status;
        final details = error.details;
        final message = status == 429
            ? 'محاولات كثيرة. انتظر قليلاً ثم حاول مجدداً.'
            : status == 401
                ? 'رقم الموظف أو كلمة المرور غير صحيحة.'
                : details is Map && details['error'] is String
                    ? _friendlyAuthError(details['error'] as String)
                    : 'تعذر تسجيل الدخول. تحقق من الاتصال وحاول مجدداً.';
        _showMessage(message);
      }
    } on AuthException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('تعذر تسجيل الدخول. تحقق من الاتصال وحاول مجدداً.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _friendlyAuthError(String code) {
    switch (code) {
      case 'invalid_credentials':
        return 'رقم الموظف أو كلمة المرور غير صحيحة.';
      case 'too_many_attempts':
        return 'محاولات كثيرة. انتظر قليلاً ثم حاول مجدداً.';
      case 'database_update_required':
        return 'خدمة الحسابات تحتاج إلى تحديث من الإدارة.';
      default:
        return 'تعذر تسجيل الدخول حالياً. حاول مجدداً.';
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 28),
                      Container(
                        width: 82,
                        height: 82,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppTheme.navy,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: const Text(
                          'MY..M',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      const Text(
                        'الشاعري الإداري',
                        style: TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.navy,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'إدارة المهام ومتابعة أعمال المؤسسة',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.blueGrey.shade600,
                        ),
                      ),
                      const SizedBox(height: 34),
                      const Text(
                        'تسجيل الدخول',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextFormField(
                        controller: _employeeNumberController,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'رقم الموظف',
                          hintText: 'أدخل رقم الموظف',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        validator: (value) => value == null || value.trim().isEmpty
                            ? 'أدخل رقم الموظف'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: !_isPasswordVisible,
                        onFieldSubmitted: (_) => _signIn(),
                        decoration: InputDecoration(
                          labelText: 'كلمة المرور',
                          hintText: 'أدخل كلمة المرور',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            onPressed: () => setState(
                              () => _isPasswordVisible = !_isPasswordVisible,
                            ),
                            icon: Icon(
                              _isPasswordVisible
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                        ),
                        validator: (value) => value == null || value.isEmpty
                            ? 'أدخل كلمة المرور'
                            : null,
                      ),
                      const SizedBox(height: 22),
                      FilledButton(
                        onPressed: _isLoading ? null : _signIn,
                        child: _isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('دخول'),
                      ),
                      const SizedBox(height: 18),
                      if (!widget.isSupabaseConfigured)
                        const Text(
                          'يلزم إعداد اتصال Supabase قبل تفعيل تسجيل الدخول.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.deepOrange,
                            fontSize: 12,
                          ),
                        ),
                      const SizedBox(height: 32),
                      Text(
                        'مؤسسة الشاعري للتجارة العامة',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.blueGrey.shade500,
                          fontSize: 12,
                        ),
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
}
