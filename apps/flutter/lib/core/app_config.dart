class AppConfig {
  AppConfig._();

  // هذه قيم Staging العامة للتطبيق فقط. لا تضع service_role هنا أو داخل APK.
  // يمكن تجاوزها وقت البناء عبر --dart-define.
  static const _defaultSupabaseUrl = 'https://qoeruidmtsasvhxejyga.supabase.co';
  static const _defaultSupabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFvZXJ1aWRtdHNhc3ZoeGVqeWdhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQ3NjgzMzAsImV4cCI6MjExMDM0NDMzMH0.kgLkaOA89KR8k0gMJxgedqEYf_mP9JNXQU2QlCdP1Js';

  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: _defaultSupabaseUrl,
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: _defaultSupabaseAnonKey,
  );
  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
