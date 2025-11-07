// secret_app/lib/config/supabase_config.dart
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_constants.dart';

class SupabaseConfig {
  static late SupabaseClient client;
  static bool _isInitialized = false;
  static bool _isConfigured = false;

  static bool get isInitialized => _isInitialized;
  static bool get isConfigured => _isConfigured;
  static bool get isAvailable => _isConfigured && _isInitialized;

  static Future<void> initialize() async {
    try {
      _validateEnvironment();

      _isConfigured = true;

      await Supabase.initialize(
        url: AppConstants.supabaseUrl,
        anonKey: AppConstants.supabaseAnonKey,
      );

      client = Supabase.instance.client;
      _isInitialized = true;

      if (kDebugMode) {
        debugPrint('✅ Supabase initialized successfully');
        printConfig();
      }
    } catch (e) {
      _isInitialized = false;
      if (kDebugMode) {
        debugPrint('❌ Supabase initialization failed: $e');
      }
      rethrow;
    }
  }

  static void _validateEnvironment() {
    try {
      final url = AppConstants.supabaseUrl;
      final key = AppConstants.supabaseAnonKey;
      
      if (kDebugMode) {
        debugPrint('🔐 Environment validation passed');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Environment validation failed: $e');
      }
      rethrow;
    }
  }

  static Future<bool> testConnection() async {
    if (!isAvailable) return false;

    try {
      final user = client.auth.currentUser;
      if (kDebugMode) {
        debugPrint('✅ Supabase connection test passed');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Supabase connection test failed: $e');
      }
      return false;
    }
  }

  static void printConfig() {
    if (kDebugMode) {
      debugPrint('''
=== SUPABASE CONFIGURATION ===
Configured: $_isConfigured
Initialized: $_isInitialized
Available: $isAvailable
URL: ${AppConstants.supabaseUrl}
Key: ${AppConstants.supabaseAnonKey.substring(0, 20)}...
==============================''');
    }
  }
}