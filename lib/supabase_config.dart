// Public build-time configuration, never a database password or secret key.
// --dart-define=SUPABASE_URL=https://PROJECT_REF.supabase.co
// --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
class SupabaseConfig {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static bool get configured =>
      Uri.tryParse(url)?.scheme == 'https' &&
      publishableKey.startsWith('sb_publishable_');
}
