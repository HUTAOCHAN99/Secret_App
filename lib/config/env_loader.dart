// secret_app/lib/config/env_loader.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

class EnvLoader {
  static Map<String, String> _env = {};
  static bool _isLoaded = false;

  static Future<void> load() async {
    try {
      if (kDebugMode) {
        debugPrint('🔄 Loading environment variables from .env file...');
      }

      final String contents = await rootBundle.loadString('.env');
      _env = _parseEnvContents(contents);
      _isLoaded = true;
      
      if (kDebugMode) {
        debugPrint('✅ Environment file loaded successfully');
        debugPrint('📋 Loaded ${_env.length} environment variables');
        
        // Print keys saja tanpa values untuk security
        debugPrint('🔑 Available keys: ${_env.keys.join(', ')}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error loading .env file: $e');
        debugPrint('💡 Make sure .env file exists in root directory and is included in pubspec.yaml assets');
      }
      _env = {};
      _isLoaded = false;
      // Jangan throw error, biarkan app tetap jalan dengan values kosong
    }
  }

  static Map<String, String> _parseEnvContents(String contents) {
    final Map<String, String> env = {};
    final lines = contents.split('\n');
    
    for (final line in lines) {
      final trimmedLine = line.trim();
      
      // Skip empty lines dan comments
      if (trimmedLine.isEmpty || trimmedLine.startsWith('#')) {
        continue;
      }
      
      final index = trimmedLine.indexOf('=');
      if (index != -1) {
        final key = trimmedLine.substring(0, index).trim();
        String value = trimmedLine.substring(index + 1).trim();
        
        // Remove quotes jika ada
        if ((value.startsWith('"') && value.endsWith('"')) || 
            (value.startsWith("'") && value.endsWith("'"))) {
          value = value.substring(1, value.length - 1);
        }
        
        // Handle escaped characters
        value = value.replaceAll(r'\"', '"').replaceAll(r"\'", "'");
        env[key] = value;
      }
    }
    
    return env;
  }

  static String get(String key, {String fallback = ''}) {
    if (!_isLoaded) {
      if (kDebugMode) {
        debugPrint('⚠️ Environment not loaded yet, calling get($key)');
      }
      return fallback;
    }
    
    final value = _env[key];
    if (value == null && kDebugMode) {
      debugPrint('⚠️ Environment variable $key not found, using fallback');
    }
    return value ?? fallback;
  }

  static bool get hasEnv => _env.isNotEmpty;
  static bool get isLoaded => _isLoaded;
  
  static Map<String, String> getAll() {
    return Map.from(_env);
  }

  static int getInt(String key, {int fallback = 0}) {
    final value = get(key);
    return int.tryParse(value) ?? fallback;
  }

  static bool getBool(String key, {bool fallback = false}) {
    final value = get(key).toLowerCase();
    return value == 'true' || value == '1' ? true : 
           value == 'false' || value == '0' ? false : fallback;
  }

  static void printDebugInfo() {
    if (kDebugMode) {
      debugPrint('''
=== ENV LOADER DEBUG INFO ===
Loaded: $_isLoaded
Variables: ${_env.length}
Keys: ${_env.keys.join(', ')}
===========================''');
    }
  }
}