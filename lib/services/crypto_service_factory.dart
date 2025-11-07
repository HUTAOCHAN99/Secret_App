// lib/services/crypto_service_factory.dart
import 'package:flutter/foundation.dart';
import 'crypto_auth.dart';
import 'crypto_auth_ffi.dart';

/// Factory untuk memilih crypto service berdasarkan platform
class CryptoServiceFactory {
  static dynamic getCryptoService() {
    try {
      if (kIsWeb) {
        if (kDebugMode) {
          print('🌐 Web platform - Using Dart CryptoAuthService');
        }
        return CryptoAuthService();
      } else {
        // Coba load FFI service dulu
        try {
          final ffiService = CryptoAuthFFI();
          if (ffiService.isAvailable) {
            if (kDebugMode) {
              print('🚀 Native platform - Using Argon2id + SHA3-512 (FFI)');
            }
            return ffiService;
          } else {
            if (kDebugMode) {
              print('⚠️ FFI not available, using Dart fallback');
            }
            return CryptoAuthService();
          }
        } catch (e) {
          if (kDebugMode) {
            print('❌ FFI failed, using Dart fallback: $e');
          }
          return CryptoAuthService();
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Crypto service error, using fallback: $e');
      }
      return CryptoAuthService();
    }
  }
  
  static bool get isWeb => kIsWeb;
  
  /// Check if Argon2id + SHA3-512 is available
  static bool get isArgon2Available {
    if (kIsWeb) return false;
    try {
      final service = CryptoAuthFFI();
      return service.isAvailable;
    } catch (e) {
      return false;
    }
  }

  /// Get crypto engine info
  static Map<String, dynamic> getCryptoEngineInfo() {
    try {
      if (kIsWeb) {
        return {
          'engine': 'dart_fallback',
          'algorithm': 'PBKDF2-like + SHA-256-like',
          'security_level': 'medium',
          'platform': 'web'
        };
      } else {
        try {
          final service = CryptoAuthFFI();
          if (service.isAvailable) {
            return {
              'engine': 'argon2id_sha3_512',
              'algorithm': 'Argon2id + SHA3-512',
              'security_level': 'high',
              'platform': 'native'
            };
          }
        } catch (e) {
          // Fall through to Dart service
        }
        return {
          'engine': 'dart_fallback',
          'algorithm': 'PBKDF2-like + SHA-256-like',
          'security_level': 'medium',
          'platform': 'native'
        };
      }
    } catch (e) {
      return {
        'engine': 'dart_fallback',
        'algorithm': 'PBKDF2-like + SHA-256-like',
        'security_level': 'medium',
        'platform': 'fallback'
      };
    }
  }

  /// Test all available crypto services
  static Future<Map<String, dynamic>> testAllServices() async {
    final results = <String, dynamic>{};
    
    try {
      // Test Dart service
      final dartService = CryptoAuthService();
      final dartTest = await dartService.hashPassword('test');
      results['dart_service'] = {
        'available': true,
        'hash_length': dartTest.hash.length,
        'algorithm': 'PBKDF2-like'
      };
    } catch (e) {
      results['dart_service'] = {
        'available': false,
        'error': e.toString()
      };
    }

    // Test FFI service jika bukan web
    if (!kIsWeb) {
      try {
        final ffiService = CryptoAuthFFI();
        if (ffiService.isAvailable) {
          final ffiTest = await ffiService.hashPasswordArgon2id('test');
          results['ffi_service'] = {
            'available': true,
            'hash_length': ffiTest.hash.length,
            'algorithm': 'Argon2id'
          };
        } else {
          results['ffi_service'] = {
            'available': false,
            'error': 'FFI not initialized'
          };
        }
      } catch (e) {
        results['ffi_service'] = {
          'available': false,
          'error': e.toString()
        };
      }
    }

    return results;
  }
}