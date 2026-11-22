class AppConfig {
  AppConfig._();

  // هذه قيم Production العامة للتطبيق فقط. لا تضع service_role هنا أو داخل APK.
  // يمكن تجاوزها وقت البناء عبر --dart-define.
  static const _defaultSupabaseUrl = 'https://fjmryqhdwxsocdzswnkq.supabase.co';
  static const _defaultSupabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZqbXJ5cWhkd3hzb2NkenN3bmtxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQyNDM0NjAsImV4cCI6MjEwOTgxOTQ2MH0.YYa5iJaAep-Vhvz9RcuuO2Uyyp9Ii7nCXjuNu_OBAes';

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
