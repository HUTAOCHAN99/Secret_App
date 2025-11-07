// secret_app/lib/config/app_constants.dart
import 'env_loader.dart';

class AppConstants {
  static String get supabaseUrl {
    final url = EnvLoader.get('SUPABASE_URL', fallback: '');
    if (url.isEmpty && EnvLoader.isLoaded) {
      throw Exception('SUPABASE_URL is not set in .env file');
    }
    return url;
  }

  static String get supabaseAnonKey {
    final key = EnvLoader.get('SUPABASE_ANON_KEY', fallback: '');
    if (key.isEmpty && EnvLoader.isLoaded) {
      throw Exception('SUPABASE_ANON_KEY is not set in .env file');
    }
    return key;
  }

  static const String appName = 'Secret Chat';
  static const String appVersion = '1.0.0';

  // Helper method untuk debug info
  static Map<String, dynamic> get debugInfo {
    return {
      'app_name': appName,
      'app_version': appVersion,
      'supabase_url_set': supabaseUrl.isNotEmpty,
      'supabase_key_set': supabaseAnonKey.isNotEmpty,
      'environment_loaded': EnvLoader.isLoaded,
    };
  }
}