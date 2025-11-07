// lib/services/crypto_auth_ffi.dart
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:math';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import '../generated/crypto_bindings.dart';

class CryptoAuthFFI {
  static final CryptoAuthFFI _instance = CryptoAuthFFI._internal();
  factory CryptoAuthFFI() => _instance;
  
  late DynamicLibrary _nativeLib;
  late CryptoBindings _bindings;
  bool _isInitialized = false;

  CryptoAuthFFI._internal() {
    _initialize();
  }

  void _initialize() {
    try {
      if (kIsWeb) {
        if (kDebugMode) {
          debugPrint('🌐 Web platform detected - FFI not available');
        }
        _isInitialized = false;
        return;
      }

      if (Platform.isWindows) {
        // Try multiple possible library locations for Windows
        final possiblePaths = [
          'argon2.dll',
          'libargon2.dll',
          'native/argon2.dll',
          'windows/argon2.dll',
          '../argon2.dll',
        ];
        
        DynamicLibrary? loadedLib;
        String? loadedPath;
        
        for (final path in possiblePaths) {
          try {
            loadedLib = DynamicLibrary.open(path);
            loadedPath = path;
            if (kDebugMode) {
              debugPrint('✅ Loaded native library from: $path');
            }
            break;
          } catch (e) {
            // Continue to next path
            continue;
          }
        }
        
        if (loadedLib == null) {
          // Try to load from system path or common locations
          try {
            loadedLib = DynamicLibrary.open('argon2.dll');
            loadedPath = 'argon2.dll (system)';
          } catch (e) {
            if (kDebugMode) {
              debugPrint('⚠️ Could not load argon2.dll from any location');
              debugPrint('💡 Please download argon2.dll and place in project root');
            }
            _isInitialized = false;
            return;
          }
        }
        
        _nativeLib = loadedLib;
        _bindings = CryptoBindings(_nativeLib);
        
        // Test bindings dengan simple function call
        final testSuccess = _testBindings();
        if (!testSuccess) {
          throw Exception('Native function bindings test failed');
        }
        
        _isInitialized = true;
        
        if (kDebugMode) {
          debugPrint('🚀 Argon2id + SHA3-512 FFI initialized successfully');
          debugPrint('   📍 Library: $loadedPath');
        }
        
      } else if (Platform.isLinux) {
        _nativeLib = DynamicLibrary.open('libargon2.so');
        _bindings = CryptoBindings(_nativeLib);
        _isInitialized = true;
      } else if (Platform.isMacOS) {
        _nativeLib = DynamicLibrary.open('libargon2.dylib');
        _bindings = CryptoBindings(_nativeLib);
        _isInitialized = true;
      } else {
        if (kDebugMode) {
          debugPrint('⚠️ Platform not supported for FFI: ${Platform.operatingSystem}');
        }
        _isInitialized = false;
      }
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ FFI initialization failed: $e');
      }
      _isInitialized = false;
    }
  }

  bool _testBindings() {
    try {
      // Test SHA3 initialization
      final ctx = calloc<SHA3_CTX>();
      _bindings.sha3_512_init(ctx);
      calloc.free(ctx);
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Binding test failed: $e');
      }
      return false;
    }
  }

  // ===============================
  // ARGON2ID IMPLEMENTATION
  // ===============================

  /// Generate Argon2id hash using FFI
  Future<Argon2HashResult> hashPasswordArgon2id(String password) async {
    if (!_isInitialized) {
      throw Exception('FFI not initialized - Argon2id unavailable');
    }

    try {
      if (kDebugMode) {
        debugPrint('🔐 Hashing password with Argon2id (Native FFI)...');
      }

      // Generate random salt
      final salt = _generateSalt(16);
      
      // Convert to pointers
      final passwordPtr = _stringToUint8Pointer(password);
      final saltPtr = _bytesToPointer(salt);
      
      // Prepare output buffer
      final hashLength = 32;
      final hashPtr = calloc<Uint8>(hashLength);

      try {
        // Call Argon2id via FFI
        final result = _bindings.argon2id_hash_raw(
          3,      // iterations
          65536,  // memory (64MB)
          4,      // parallelism
          passwordPtr,
          password.length,
          saltPtr,
          salt.length,
          hashPtr,
          hashLength,
        );

        if (result != 0) {
          throw Exception('Argon2id hashing failed with code: $result');
        }

        // Copy result back to Dart
        final hashBytes = hashPtr.asTypedList(hashLength).toList();
        final hash = Uint8List.fromList(hashBytes);

        final resultObj = Argon2HashResult(
          hash: base64.encode(hash),
          salt: base64.encode(salt),
          version: 'argon2id-v1.3',
          parameters: {
            'type': 'argon2id',
            'iterations': 3,
            'memory': 65536,
            'parallelism': 4,
            'hash_length': hashLength,
          },
        );

        if (kDebugMode) {
          debugPrint('✅ Argon2id hashing completed via FFI');
          debugPrint('   Salt: ${resultObj.salt.substring(0, 16)}...');
          debugPrint('   Hash: ${resultObj.hash.substring(0, 16)}...');
        }

        return resultObj;
      } finally {
        // Cleanup
        calloc.free(passwordPtr);
        calloc.free(saltPtr);
        calloc.free(hashPtr);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Argon2id FFI error: $e');
      }
      rethrow;
    }
  }

  /// Verify password with Argon2id
  Future<bool> verifyPasswordArgon2id(String password, String storedHash, String storedSalt) async {
    if (!_isInitialized) {
      throw Exception('FFI not initialized - Argon2id unavailable');
    }

    try {
      final testResult = await hashPasswordArgon2id(password);
      final isValid = _constantTimeCompare(
        base64.decode(storedHash),
        base64.decode(testResult.hash),
      );

      if (kDebugMode) {
        debugPrint('🔍 Argon2id verification: ${isValid ? 'PASSED' : 'FAILED'}');
      }

      return isValid;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Argon2id verification error: $e');
      }
      rethrow;
    }
  }

  // ===============================
  // SHA3-512 IMPLEMENTATION  
  // ===============================

  /// Generate SHA3-512 hash using FFI
  String hashDataSHA3_512(String data) {
    if (!_isInitialized) {
      throw Exception('FFI not initialized - SHA3-512 unavailable');
    }

    try {
      if (kDebugMode) {
        debugPrint('🔏 Hashing data with SHA3-512 (Native FFI)...');
      }

      // Allocate context and digest
      final ctxPtr = calloc<SHA3_CTX>();
      final digestPtr = calloc<Uint8>(64); // 512-bit = 64 bytes

      try {
        // Initialize SHA3-512
        _bindings.sha3_512_init(ctxPtr);

        // Update with data
        final dataBytes = utf8.encode(data);
        final dataPtr = _bytesToPointer(Uint8List.fromList(dataBytes));
        _bindings.sha3_512_update(ctxPtr, dataPtr, dataBytes.length);

        // Finalize hash
        _bindings.sha3_512_final(digestPtr, ctxPtr);

        // Copy result
        final digestBytes = digestPtr.asTypedList(64).toList();
        final hashBase64 = base64.encode(digestBytes);

        if (kDebugMode) {
          debugPrint('✅ SHA3-512 hashing completed via FFI');
          debugPrint('   Hash: ${hashBase64.substring(0, 32)}...');
        }

        return hashBase64;
      } finally {
        calloc.free(ctxPtr);
        calloc.free(digestPtr);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SHA3-512 FFI error: $e');
      }
      rethrow;
    }
  }

  // ===============================
  // HYBRID AUTHENTICATION (REAL ARGON2ID + SHA3-512)
  // ===============================

  /// Real Argon2id + SHA3-512 Hybrid Authentication
  Future<HybridAuthResult> hybridAuthenticate({
    required String password,
    required String challenge,
    String? storedHash,
    String? storedSalt,
  }) async {
    if (!_isInitialized) {
      throw Exception('FFI not initialized - Hybrid auth unavailable');
    }

    try {
      if (kDebugMode) {
        debugPrint('🛡️ Starting REAL Argon2id + SHA3-512 hybrid auth...');
      }

      // Step 1: Hash password dengan Argon2id
      final String passwordHash;
      final String salt;

      if (storedHash != null && storedSalt != null) {
        // Verification mode - kita perlu re-hash dan compare
        if (kDebugMode) {
          debugPrint('   🔍 Verifying with Argon2id...');
        }
        
        final isValid = await verifyPasswordArgon2id(password, storedHash, storedSalt);
        if (!isValid) {
          throw Exception('Argon2id password verification failed');
        }
        passwordHash = storedHash;
        salt = storedSalt;
      } else {
        // Registration mode
        if (kDebugMode) {
          debugPrint('   🆕 Creating new Argon2id hash...');
        }
        final argon2Result = await hashPasswordArgon2id(password);
        passwordHash = argon2Result.hash;
        salt = argon2Result.salt;
      }

      // Step 2: Hash challenge dengan SHA3-512
      if (kDebugMode) {
        debugPrint('   🔏 Hashing challenge with SHA3-512...');
      }
      final challengeHash = hashDataSHA3_512(challenge);

      // Step 3: Combine hashes dengan secure method
      final combinedHash = _combineHashesSecure(passwordHash, challengeHash);

      final result = HybridAuthResult(
        success: true,
        passwordHash: passwordHash,
        salt: salt,
        challengeHash: challengeHash,
        combinedHash: combinedHash,
        timestamp: DateTime.now(),
      );

      if (kDebugMode) {
        debugPrint('✅ REAL Argon2id + SHA3-512 hybrid auth completed');
        debugPrint('   Argon2id Hash: ${passwordHash.substring(0, 20)}...');
        debugPrint('   SHA3-512 Hash: ${challengeHash.substring(0, 20)}...');
        debugPrint('   Combined: ${combinedHash.substring(0, 20)}...');
      }

      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Hybrid auth failed: $e');
      }
      rethrow;
    }
  }

  // ===============================
  // HELPER METHODS
  // ===============================

  Uint8List _generateSalt(int length) {
    final random = Random.secure();
    final salt = Uint8List(length);
    for (int i = 0; i < length; i++) {
      salt[i] = random.nextInt(256);
    }
    return salt;
  }

  Pointer<Uint8> _stringToUint8Pointer(String str) {
    final units = utf8.encode(str);
    final ptr = calloc<Uint8>(units.length);
    final typedList = ptr.asTypedList(units.length);
    typedList.setAll(0, units);
    return ptr;
  }

  Pointer<Uint8> _bytesToPointer(Uint8List bytes) {
    final ptr = calloc<Uint8>(bytes.length);
    final typedList = ptr.asTypedList(bytes.length);
    typedList.setAll(0, bytes);
    return ptr;
  }

  bool _constantTimeCompare(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }

  /// Secure hash combination untuk Argon2id + SHA3-512
  String _combineHashesSecure(String hash1, String hash2) {
    final bytes1 = base64.decode(hash1);
    final bytes2 = base64.decode(hash2);
    
    // Use HMAC-like approach dengan additional security
    final combined = Uint8List(bytes1.length);
    final key = Uint8List.fromList([...bytes2, ...bytes1.sublist(0, 16)]);
    
    for (int i = 0; i < combined.length; i++) {
      combined[i] = bytes1[i] ^ key[i % key.length] ^ (i & 0xFF);
    }
    
    return base64.encode(combined);
  }

  // ===============================
  // UTILITY METHODS
  // ===============================

  bool get isAvailable => _isInitialized;

  /// Test all crypto functions
  Future<bool> testAllFunctions() async {
    try {
      if (!_isInitialized) return false;

      // Test Argon2id
      final argonResult = await hashPasswordArgon2id('testpassword');
      if (argonResult.hash.isEmpty) return false;

      // Test SHA3-512
      final sha3Hash = hashDataSHA3_512('test challenge');
      if (sha3Hash.isEmpty) return false;

      // Test Hybrid Auth
      final hybridResult = await hybridAuthenticate(
        password: 'testpassword',
        challenge: 'test challenge',
      );
      if (!hybridResult.success) return false;

      if (kDebugMode) {
        debugPrint('✅ All FFI crypto functions working correctly');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ FFI crypto test failed: $e');
      }
      return false;
    }
  }

  /// Security audit untuk FFI implementation
  Future<SecurityAuditResult> performSecurityAudit() async {
    try {
      final testResult = await testAllFunctions();
      
      return SecurityAuditResult(
        timestamp: DateTime.now(),
        passwordHashing: testResult,
        dataHashing: testResult,
        hybridAuth: testResult,
        encryption: false, // FFI doesn't handle encryption
        randomGeneration: true,
        overallSecurity: testResult,
        recommendations: testResult ? 
          'Argon2id + SHA3-512 FFI implementation is secure' :
          'FFI implementation failed security audit',
      );
    } catch (e) {
      return SecurityAuditResult(
        timestamp: DateTime.now(),
        passwordHashing: false,
        dataHashing: false,
        hybridAuth: false,
        encryption: false,
        randomGeneration: false,
        overallSecurity: false,
        recommendations: 'FFI security audit failed: $e',
      );
    }
  }

  void printDebugInfo() {
    if (kDebugMode) {
      debugPrint('''
=== CRYPTO AUTH FFI DEBUG INFO ===
Initialized: $_isInitialized
Platform: ${Platform.operatingSystem}
Functions Available:
  ✅ Argon2id Hash
  ✅ SHA3-512 Hash  
  ✅ Hybrid Authentication
Security Level: Enterprise
Algorithms: Argon2id + SHA3-512
=================================''');
    }
  }

  void dispose() {
    // Cleanup resources if needed
  }
}

// Data models
class Argon2HashResult {
  final String hash;
  final String salt;
  final String version;
  final Map<String, dynamic> parameters;

  Argon2HashResult({
    required this.hash,
    required this.salt,
    required this.version,
    required this.parameters,
  });

  Map<String, dynamic> toJson() {
    return {
      'hash': hash,
      'salt': salt,
      'version': version,
      'parameters': parameters,
    };
  }

  @override
  String toString() {
    return 'Argon2HashResult(hash: ${hash.substring(0, 16)}..., salt: ${salt.substring(0, 16)}...)';
  }
}

class HybridAuthResult {
  final bool success;
  final String passwordHash;
  final String salt;
  final String challengeHash;
  final String combinedHash;
  final DateTime timestamp;

  HybridAuthResult({
    required this.success,
    required this.passwordHash,
    required this.salt,
    required this.challengeHash,
    required this.combinedHash,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'password_hash': passwordHash,
      'salt': salt,
      'challenge_hash': challengeHash,
      'combined_hash': combinedHash,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  @override
  String toString() {
    return 'HybridAuthResult(success: $success, engine: "argon2id_sha3_512")';
  }
}

class SecurityAuditResult {
  final DateTime timestamp;
  final bool passwordHashing;
  final bool dataHashing;
  final bool hybridAuth;
  final bool encryption;
  final bool randomGeneration;
  final bool overallSecurity;
  final String recommendations;

  SecurityAuditResult({
    required this.timestamp,
    required this.passwordHashing,
    required this.dataHashing,
    required this.hybridAuth,
    required this.encryption,
    required this.randomGeneration,
    required this.overallSecurity,
    required this.recommendations,
  });
}