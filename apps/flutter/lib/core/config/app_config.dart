class AppConfig {
  const AppConfig({required this.supabaseUrl, required this.supabaseAnonKey});

  static const productionUrl = 'https://fjmryqhdwxsocdzswnkq.supabase.co';
  static const productionPublishableKey =
      'sb_publishable_vRWbeJO5I_KJwJjqVDSZLA_pEHABsPk';

  final String supabaseUrl;
  final String supabaseAnonKey;

  bool get hasSupabaseConfig =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  factory AppConfig.fromEnvironment() {
    return const AppConfig(
      supabaseUrl: String.fromEnvironment(
        'SUPABASE_URL',
        defaultValue: productionUrl,
      ),
      supabaseAnonKey: String.fromEnvironment(
        'SUPABASE_ANON_KEY',
        defaultValue: productionPublishableKey,
      ),
    );
  }
}
