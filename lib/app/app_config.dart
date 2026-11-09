/// Build-time configuration, passed with --dart-define so nothing environment
/// specific (and no secret) lives in source control:
///
///   flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=<publishable anon key>
///
/// The anon key is designed to be public: data is protected by row-level
/// security. NEVER put the service-role key, the AamarPay signature key or the
/// Cloudinary API secret here.
class AppConfig {
  AppConfig._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Opt-in demo mode with in-memory sample data: --dart-define=USE_MOCK_DATA=true
  static const bool useMockData = bool.fromEnvironment('USE_MOCK_DATA');

  static bool get isBackendConfigured =>
      supabaseUrl.startsWith('https://') && supabaseAnonKey.isNotEmpty;
}
