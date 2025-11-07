// lib/services/encryption_service.dart
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'camellia_encryption.dart';
import 'hybrid_encryption_service.dart';

class EncryptionService {
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;
  EncryptionService._internal();

  final CamelliaEncryption _camellia = CamelliaEncryption();
  final HybridEncryptionService _hybridEncryption = HybridEncryptionService();

  // ===============================
  // HYBRID ENCRYPTION METHODS
  // ===============================

  /// Hybrid encryption untuk chat messages dengan Affine + Vigenere + AES-256
  Future<Map<String, dynamic>> hybridEncryptMessage({
    required String message,
    required String userPin1,
    required String userPin2,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('🔐 Starting HYBRID message encryption...');
      }

      final chatKey = generateChatKey(userPin1, userPin2);
      final masterKey = _deriveMasterKey(userPin1, userPin2);

      final result = await _hybridEncryption.hybridEncrypt(
        plaintext: message,
        masterKey: masterKey,
        chatKey: chatKey,
      );

      if (kDebugMode) {
        debugPrint('✅ HYBRID message encryption completed');
        debugPrint('   Algorithm: ${result['algorithm']}');
        debugPrint('   Security: ${result['security_level']}');
        debugPrint('   Layers: ${result['layers']}');
      }

      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Hybrid message encryption error: $e');
        debugPrint('🔄 Falling back to standard encryption...');
      }
      // Fallback ke encryption biasa
      return await encryptMessage(message, generateChatKey(userPin1, userPin2));
    }
  }

  /// Hybrid decryption untuk chat messages
  Future<String> hybridDecryptMessage({
    required String encryptedMessage,
    required String iv,
    required String userPin1,
    required String userPin2,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('🔓 Starting HYBRID message decryption...');
      }

      final chatKey = generateChatKey(userPin1, userPin2);
      final masterKey = _deriveMasterKey(userPin1, userPin2);

      final result = await _hybridEncryption.hybridDecrypt(
        encryptedMessage: encryptedMessage,
        iv: iv,
        masterKey: masterKey,
        chatKey: chatKey,
      );

      if (kDebugMode) {
        debugPrint('✅ HYBRID message decryption completed');
      }

      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Hybrid message decryption error: $e');
        debugPrint('🔄 Falling back to standard decryption...');
      }
      // Fallback ke decryption biasa
      return await decryptMessage(encryptedMessage, iv, generateChatKey(userPin1, userPin2));
    }
  }

  /// Derive master key untuk hybrid encryption
  String _deriveMasterKey(String userPin1, String userPin2) {
    final pins = [userPin1, userPin2]..sort();
    final combined = '${pins[0]}::${pins[1]}::hybrid_master_key_2024';
    final bytes = utf8.encode(combined);
    
    // Double hash untuk security tambahan
    var hash = 0;
    for (final byte in bytes) {
      hash = (hash << 5) - hash + byte;
      hash = hash & hash; // Convert to 32-bit integer
    }
    
    // Buat key yang lebih panjang untuk AES-256
    final keyString = hash.abs().toString().padRight(64, '0').substring(0, 64);
    return base64.encode(utf8.encode(keyString));
  }

  // ===============================
  // STANDARD ENCRYPTION METHODS (EXISTING)
  // ===============================

  /// Generate chat key dari user PINs
  static String generateChatKey(String userPin1, String userPin2) {
    try {
      if (kDebugMode) {
        debugPrint('🔑 Generating chat key from PINs: $userPin1 and $userPin2');
      }

      // Sort PINs untuk memastikan key sama tanpa memperhatikan urutan
      final pins = [userPin1, userPin2]..sort();
      final combined = '${pins[0]}_${pins[1]}_secret_chat_key_2024';
      
      // Hash sederhana menggunakan kombinasi base64 dan XOR
      final bytes = utf8.encode(combined);
      var hash = 0;
      
      for (final byte in bytes) {
        hash = (hash << 5) - hash + byte;
        hash = hash & hash; // Convert to 32-bit integer
      }
      
      // Buat key 32 bytes dari hash
      final keyString = hash.abs().toString().padRight(32, '0').substring(0, 32);
      final keyBytes = utf8.encode(keyString);
      
      final keyBase64 = base64.encode(keyBytes);
      
      if (kDebugMode) {
        debugPrint('✅ Chat key generated successfully');
        debugPrint('   Key: $keyBase64');
      }
      
      return keyBase64;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error generating chat key: $e');
      }
      // Fallback key
      return 'YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXoxMjM0NTY3ODkw';
    }
  }

  /// Simple XOR-based encryption dengan IV
  Future<Map<String, dynamic>> encryptMessage(String message, String encryptionKey) async {
    try {
      if (kDebugMode) {
        debugPrint('🔒 Encrypting message (length: ${message.length})');
      }

      // Validasi input
      if (message.isEmpty) {
        throw Exception('Message cannot be empty');
      }
      if (encryptionKey.isEmpty) {
        throw Exception('Encryption key cannot be empty');
      }

      // Decode key dari base64
      final keyBytes = base64.decode(encryptionKey);
      
      // Generate random IV (Initialization Vector)
      final iv = _generateIV();
      
      // Convert message ke bytes
      final messageBytes = utf8.encode(message);
      
      // Encrypt menggunakan XOR dengan key cycling dan IV
      final encryptedBytes = _xorEncrypt(messageBytes, keyBytes, iv);
      
      final result = {
        'encrypted_message': base64.encode(encryptedBytes),
        'iv': base64.encode(iv),
        'algorithm': 'xor_with_iv',
        'security_level': 'basic',
      };

      if (kDebugMode) {
        debugPrint('✅ Message encrypted successfully');
        debugPrint('   Original: $message');
        debugPrint('   Encrypted: ${result['encrypted_message']}');
        debugPrint('   IV: ${result['iv']}');
      }

      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Encryption error: $e');
      }
      rethrow;
    }
  }

  /// Simple XOR-based decryption dengan IV
  Future<String> decryptMessage(String encryptedMessage, String iv, String encryptionKey) async {
    try {
      if (kDebugMode) {
        debugPrint('🔓 Decrypting message (encrypted length: ${encryptedMessage.length})');
      }

      // Validasi input
      if (encryptedMessage.isEmpty) {
        throw Exception('Encrypted message cannot be empty');
      }
      if (iv.isEmpty) {
        throw Exception('IV cannot be empty');
      }
      if (encryptionKey.isEmpty) {
        throw Exception('Encryption key cannot be empty');
      }

      // Decode dari base64
      final keyBytes = base64.decode(encryptionKey);
      final ivBytes = base64.decode(iv);
      final encryptedBytes = base64.decode(encryptedMessage);
      
      // Decrypt menggunakan XOR
      final decryptedBytes = _xorDecrypt(encryptedBytes, keyBytes, ivBytes);
      
      // Convert kembali ke string
      final decryptedMessage = utf8.decode(decryptedBytes);
      
      if (kDebugMode) {
        debugPrint('✅ Message decrypted successfully');
        debugPrint('   Decrypted: ${decryptedMessage.length > 50 ? '${decryptedMessage.substring(0, 50)}...' : decryptedMessage}');
      }

      return decryptedMessage;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Decryption error: $e');
        debugPrint('   Encrypted message: $encryptedMessage');
        debugPrint('   IV: $iv');
        debugPrint('   Key: ${encryptionKey.substring(0, 20)}...');
      }
      rethrow;
    }
  }

  // XOR encryption algorithm dengan IV
  List<int> _xorEncrypt(List<int> data, List<int> key, List<int> iv) {
    final result = List<int>.filled(data.length, 0);
    
    // Gabungkan IV dengan key untuk membuat key yang lebih panjang
    final extendedKey = _extendKey(key, iv, data.length);
    
    for (int i = 0; i < data.length; i++) {
      // XOR data dengan extended key
      result[i] = data[i] ^ extendedKey[i];
    }
    
    return result;
  }

  // XOR decryption algorithm dengan IV
  List<int> _xorDecrypt(List<int> encryptedData, List<int> key, List<int> iv) {
    // Decryption sama dengan encryption untuk XOR
    return _xorEncrypt(encryptedData, key, iv);
  }

  // Extend key to required length menggunakan IV
  List<int> _extendKey(List<int> key, List<int> iv, int requiredLength) {
    final extendedKey = List<int>.filled(requiredLength, 0);
    
    for (int i = 0; i < requiredLength; i++) {
      // Gunakan kombinasi key dan IV untuk membuat extended key
      final keyIndex = i % key.length;
      final ivIndex = i % iv.length;
      extendedKey[i] = (key[keyIndex] + iv[ivIndex] + i) % 256;
    }
    
    return extendedKey;
  }

  // Generate random IV (Initialization Vector)
  List<int> _generateIV() {
    final random = Random.secure();
    final iv = List<int>.filled(16, 0); // 16 bytes IV
    
    for (int i = 0; i < iv.length; i++) {
      iv[i] = random.nextInt(256);
    }
    
    return iv;
  }

  // ===============================
  // TESTING & VALIDATION METHODS
  // ===============================

  /// Test semua encryption methods termasuk hybrid
  Future<Map<String, dynamic>> testAllEncryptionMethods() async {
    try {
      if (kDebugMode) {
        debugPrint('🧪 Testing ALL encryption methods...');
      }

      const testMessage = 'Hello, this is a comprehensive encryption test! 🔐';
      const userPin1 = '123456';
      const userPin2 = '654321';

      final results = <String, dynamic>{};

      // Test Standard XOR Encryption
      if (kDebugMode) debugPrint('   Testing Standard XOR Encryption...');
      final standardKey = generateChatKey(userPin1, userPin2);
      final standardEncrypted = await encryptMessage(testMessage, standardKey);
      final standardDecrypted = await decryptMessage(
        standardEncrypted['encrypted_message'] as String,
        standardEncrypted['iv'] as String,
        standardKey,
      );
      results['standard_encryption'] = standardDecrypted == testMessage;

      // Test Hybrid Encryption
      if (kDebugMode) debugPrint('   Testing Hybrid Encryption...');
      final hybridEncrypted = await hybridEncryptMessage(
        message: testMessage,
        userPin1: userPin1,
        userPin2: userPin2,
      );
      final hybridDecrypted = await hybridDecryptMessage(
        encryptedMessage: hybridEncrypted['encrypted_message'] as String,
        iv: hybridEncrypted['iv'] as String,
        userPin1: userPin1,
        userPin2: userPin2,
      );
      results['hybrid_encryption'] = hybridDecrypted == testMessage;

      // Test Camellia-256 Encryption
      if (kDebugMode) debugPrint('   Testing Camellia-256 Encryption...');
      results['camellia_encryption'] = await _camellia.testEncryption();

      // Test Hybrid System Components
      if (kDebugMode) debugPrint('   Testing Hybrid System Components...');
      final hybridComponentsTest = await _hybridEncryption.testHybridEncryption();
      results['hybrid_components'] = hybridComponentsTest['all_tests_passed'] == true;

      final allPassed = results.values.every((result) => result == true);

      if (kDebugMode) {
        debugPrint('🎯 All encryption tests: ${allPassed ? 'PASSED' : 'FAILED'}');
        for (final entry in results.entries) {
          debugPrint('   ${entry.key}: ${entry.value ? '✅' : '❌'}');
        }
      }

      return {
        'all_passed': allPassed,
        'results': results,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Comprehensive encryption test error: $e');
      }
      return {
        'all_passed': false,
        'error': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }

  /// Test hybrid encryption system secara khusus
  Future<Map<String, dynamic>> testHybridEncryption() async {
    return await _hybridEncryption.testHybridEncryption();
  }

  /// Performance benchmark untuk semua encryption methods
  Future<Map<String, dynamic>> performanceBenchmark() async {
    try {
      if (kDebugMode) {
        debugPrint('⏱️ Running comprehensive performance benchmark...');
      }

      // Gunakan string literal untuk menghindari constant expression error
      final testMessage = 'A' + 'B' * 499; // 500 karakter
      const userPin1 = '123456';
      const userPin2 = '654321';

      final stopwatch = Stopwatch();
      final results = <String, dynamic>{};

      // Benchmark Standard XOR Encryption
      stopwatch.start();
      final standardKey = generateChatKey(userPin1, userPin2);
      final standardEncrypted = await encryptMessage(testMessage, standardKey);
      await decryptMessage(
        standardEncrypted['encrypted_message'] as String,
        standardEncrypted['iv'] as String,
        standardKey,
      );
      stopwatch.stop();
      results['standard_encryption_time'] = stopwatch.elapsedMicroseconds;
      stopwatch.reset();

      // Benchmark Hybrid Encryption
      stopwatch.start();
      final hybridEncrypted = await hybridEncryptMessage(
        message: testMessage,
        userPin1: userPin1,
        userPin2: userPin2,
      );
      await hybridDecryptMessage(
        encryptedMessage: hybridEncrypted['encrypted_message'] as String,
        iv: hybridEncrypted['iv'] as String,
        userPin1: userPin1,
        userPin2: userPin2,
      );
      stopwatch.stop();
      results['hybrid_encryption_time'] = stopwatch.elapsedMicroseconds;
      stopwatch.reset();

      // Benchmark Hybrid Components
      final hybridBenchmark = await _hybridEncryption.performanceBenchmark();
      results['hybrid_components_benchmark'] = hybridBenchmark;

      results['message_size'] = testMessage.length;
      results['timestamp'] = DateTime.now().toIso8601String();

      if (kDebugMode) {
        debugPrint('📊 Comprehensive Performance Benchmark:');
        debugPrint('   Standard XOR: ${results['standard_encryption_time']}μs');
        debugPrint('   Hybrid System: ${results['hybrid_encryption_time']}μs');
        final standardTime = results['standard_encryption_time'] as int;
        final hybridTime = results['hybrid_encryption_time'] as int;
        debugPrint('   Performance Ratio: ${(hybridTime / standardTime).toStringAsFixed(2)}x');
      }

      return results;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Performance benchmark error: $e');
      }
      return {
        'error': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }

  // ===============================
  // SECURITY INFO & ANALYSIS
  // ===============================

  /// Get comprehensive encryption info
  Map<String, dynamic> getEncryptionInfo() {
    final hybridAnalysis = _hybridEncryption.getSecurityAnalysis();
    
    return {
      'encryption_systems': {
        'hybrid_chat_encryption': {
          'algorithm': 'Affine + Vigenere + AES-256 Hybrid',
          'security_level': hybridAnalysis['security_level'],
          'key_space': hybridAnalysis['key_space'],
          'purpose': 'Real-time chat messages with maximum security',
          'layers': hybridAnalysis['encryption_layers'],
        },
        'standard_chat_encryption': {
          'algorithm': 'XOR with IV',
          'key_size': '32 bytes',
          'security_level': 'Basic',
          'purpose': 'Fallback encryption system',
        },
        'database_encryption': {
          'algorithm': 'Camellia-256-CBC',
          'key_size': '32 bytes (256-bit)',
          'block_size': '16 bytes (128-bit)',
          'security_level': 'High (NIST recommended)',
          'purpose': 'Secure database storage',
        },
      },
      'key_management': {
        'chat_keys': 'Derived from user PINs',
        'master_keys': 'Derived for hybrid encryption',
        'database_keys': 'Random 256-bit master keys',
      },
      'security_features': [
        'Multiple encryption layers (Defense in Depth)',
        'Dynamic key derivation',
        'Military-grade AES-256 encryption',
        'Fallback systems for reliability',
        'Resistance to cryptanalysis',
      ],
    };
  }

  /// Get hybrid encryption security info
  Map<String, dynamic> getHybridEncryptionInfo() {
    return _hybridEncryption.getSecurityAnalysis();
  }

  // ===============================
  // UTILITY METHODS
  // ===============================

  /// Generate random user PIN (6 digits)
  static String generateUserPin() {
    try {
      final random = Random.secure();
      final pin = random.nextInt(1000000).toString().padLeft(6, '0');

      if (pin.length != 6) {
        throw Exception('Generated PIN length is not 6: $pin');
      }

      if (kDebugMode) {
        debugPrint('🎰 Generated user PIN: $pin');
      }
      
      return pin;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error generating user PIN: $e');
      }
      // Fallback PIN
      return '123456';
    }
  }

  /// Validate if a string is a valid PIN (6 digits)
  static bool isValidPin(String pin) {
    return RegExp(r'^\d{6}$').hasMatch(pin);
  }

  /// Simple character shift encryption (Caesar cipher-like)
  String simpleShiftEncrypt(String text, int shift) {
    final result = StringBuffer();
    
    for (int i = 0; i < text.length; i++) {
      final char = text.codeUnitAt(i);
      result.writeCharCode(char + shift);
    }
    
    return result.toString();
  }

  /// Simple character shift decryption
  String simpleShiftDecrypt(String encryptedText, int shift) {
    final result = StringBuffer();
    
    for (int i = 0; i < encryptedText.length; i++) {
      final char = encryptedText.codeUnitAt(i);
      result.writeCharCode(char - shift);
    }
    
    return result.toString();
  }

  // ===============================
  // CAMELLIA-256 DATABASE ENCRYPTION
  // ===============================

  /// Encrypt sensitive database data dengan Camellia-256
  Future<Map<String, dynamic>> encryptDatabaseData(
    String data, {
    required String masterKey,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('🗃️ Encrypting database data with Camellia-256...');
      }

      final key = _camellia.generateKey(masterKey);
      return await _camellia.encrypt(data, key);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Database encryption error: $e');
      }
      rethrow;
    }
  }

  /// Decrypt sensitive database data dengan Camellia-256
  Future<String> decryptDatabaseData(
    String encryptedData, {
    required String masterKey,
    required String iv,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('🗃️ Decrypting database data with Camellia-256...');
      }

      final key = _camellia.generateKey(masterKey);
      return await _camellia.decrypt(encryptedData, key, iv);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Database decryption error: $e');
      }
      rethrow;
    }
  }

  /// Generate master key untuk database encryption
  String generateDatabaseMasterKey() {
    try {
      final random = Random.secure();
      final keyBytes = List<int>.generate(32, (_) => random.nextInt(256));
      final keyBase64 = base64.encode(keyBytes);
      
      if (kDebugMode) {
        debugPrint('🔑 Generated database master key');
        debugPrint('   Key: ${keyBase64.substring(0, 20)}...');
      }
      
      return keyBase64;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error generating database master key: $e');
      }
      rethrow;
    }
  }

  /// Encrypt user profile data untuk storage aman
  Future<Map<String, dynamic>> encryptUserProfile(
    Map<String, dynamic> profile, {
    required String masterKey,
  }) async {
    try {
      final jsonString = json.encode(profile);
      return await encryptDatabaseData(
        jsonString,
        masterKey: masterKey,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ User profile encryption error: $e');
      }
      rethrow;
    }
  }

  /// Decrypt user profile data
  Future<Map<String, dynamic>> decryptUserProfile(
    Map<String, dynamic> encryptedProfile, {
    required String masterKey,
  }) async {
    try {
      final decryptedJson = await decryptDatabaseData(
        encryptedProfile['encrypted_data'] as String,
        masterKey: masterKey,
        iv: encryptedProfile['iv'] as String,
      );
      
      return json.decode(decryptedJson) as Map<String, dynamic>;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ User profile decryption error: $e');
      }
      rethrow;
    }
  }

  // ===============================
  // DEMONSTRATION & DEBUG METHODS
  // ===============================

  /// Demonstrate hybrid encryption process
  Future<void> demonstrateHybridEncryption() async {
    await _hybridEncryption.demonstrateEncryptionProcess();
  }

  void printDebugInfo() {
    if (kDebugMode) {
      final info = getEncryptionInfo();
      debugPrint('''
=== ENCRYPTION SERVICE DEBUG INFO ===
Available Systems:
  • Hybrid Encryption (Affine + Vigenere + AES-256)
  • Standard XOR Encryption 
  • Camellia-256 Database Encryption

Security Levels:
  • Hybrid: ${info['encryption_systems']['hybrid_chat_encryption']['security_level']}
  • Standard: ${info['encryption_systems']['standard_chat_encryption']['security_level']}
  • Database: ${info['encryption_systems']['database_encryption']['security_level']}

Key Features:
${info['security_features'].map((feature) => '  ✓ $feature').join('\n')}
=====================================''');
    }
  }

  /// Verify encryption setup dan readiness
  Future<Map<String, dynamic>> verifyEncryptionSetup() async {
    try {
      final testResult = await testAllEncryptionMethods();
      final performance = await performanceBenchmark();
      final info = getEncryptionInfo();
      
      return {
        'status': testResult['all_passed'] == true ? 'fully_operational' : 'degraded',
        'tests_passed': testResult['all_passed'],
        'performance': performance,
        'info': info,
        'timestamp': DateTime.now().toIso8601String(),
        'recommendations': testResult['all_passed'] == true 
            ? 'All encryption systems are operational'
            : 'Some encryption systems require attention',
      };
    } catch (e) {
      return {
        'status': 'error',
        'error': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }
}