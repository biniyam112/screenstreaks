/// App configuration, injected at build time via --dart-define so no secrets
/// live in the repo. Example:
///
///   flutter run \
///     --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=eyJhbGci... \
///     --dart-define=GOOGLE_WEB_CLIENT_ID=1234-abc.apps.googleusercontent.com
///
/// When SUPABASE_URL / SUPABASE_ANON_KEY are empty, the app runs against a
/// local in-memory demo backend so it's fully usable without a backend.
class AppConfig {
  AppConfig._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Google OAuth *Web* client ID — used as the serverClientId for
  /// google_sign_in on Android/iOS with Supabase signInWithIdToken.
  static const googleWebClientId =
      String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  /// Google OAuth iOS client ID (needed for google_sign_in on iOS).
  static const googleIosClientId =
      String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  /// True when a real Supabase backend is wired up.
  static bool get hasBackend =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Base for share links, e.g. https://screenstreaks.app/c/ABC123.
  /// (Deep-link handling is optional; codes can always be entered manually.)
  static const shareLinkBase = 'https://screenstreaks.app/c/';
}
