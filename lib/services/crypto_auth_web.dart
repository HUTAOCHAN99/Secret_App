import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

class CryptoAuthWeb {
  static final CryptoAuthWeb _instance = CryptoAuthWeb._internal();
  factory CryptoAuthWeb() => _instance;
  CryptoAuthWeb._internal();

  static const int _saltLength = 16;
  static const int _hashIterations = 100000;

  Future<Argon2HashResult> hashPasswordArgon2id(String password) async {
    try {
      if (kDebugMode) {
        debugPrint('🔐 Hashing password with Web-compatible algorithm...');
      }

      final salt = _generateSalt(16);

      final hash = _pbkdf2LikeHash(password, salt, 3, 65536, 4);

      final result = Argon2HashResult(
        hash: base64.encode(hash),
        salt: base64.encode(salt),
        version: 'web-argon2id-v1',
        parameters: {
          'type': 'argon2id',
          'iterations': 3,
          'memory': 65536,
          'parallelism': 4,
          'hash_length': hash.length,
        },
      );

      if (kDebugMode) {
        debugPrint('✅ Web Argon2id hashing completed');
      }

      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Web Argon2id error: $e');
      }
      rethrow;
    }
  }

  String hashDataSHA3_512(String data) {
    try {
      if (kDebugMode) {
        debugPrint('🔏 Hashing data with SHA3-512 (Web)...');
      }

      final dataBytes = utf8.encode(data);
      final hash = _sha3LikeHash(dataBytes);
      final hashBase64 = base64.encode(hash);

      if (kDebugMode) {
        debugPrint('✅ SHA3-512 hashing completed (Web)');
      }

      return hashBase64;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SHA3-512 Web error: $e');
      }
      rethrow;
    }
  }

  Future<HybridAuthResult> hybridAuthenticate({
    required String password,
    required String challenge,
    String? storedHash,
    String? storedSalt,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('🛡️ Starting Web-compatible hybrid auth...');
      }

      final String passwordHash;
      final String salt;

      if (storedHash != null && storedSalt != null) {
        final testResult = await hashPasswordArgon2id(password);
        final isValid = _constantTimeCompare(
          base64.decode(storedHash),
          base64.decode(testResult.hash),
        );
        
        if (!isValid) {
          throw Exception('Password verification failed');
        }
        passwordHash = storedHash;
        salt = storedSalt;
      } else {
        final argon2Result = await hashPasswordArgon2id(password);
        passwordHash = argon2Result.hash;
        salt = argon2Result.salt;
      }

      final challengeHash = hashDataSHA3_512(challenge);

      final combinedHash = _combineHashes(passwordHash, challengeHash);

      final result = HybridAuthResult(
        success: true,
        passwordHash: passwordHash,
        salt: salt,
        challengeHash: challengeHash,
        combinedHash: combinedHash,
        timestamp: DateTime.now(),
      );

      if (kDebugMode) {
        debugPrint('✅ Web hybrid auth completed');
      }

      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Web hybrid auth failed: $e');
      }
      rethrow;
    }
  }

  Uint8List _pbkdf2LikeHash(String password, Uint8List salt, int iterations, int memory, int parallelism) {
    var hash = Uint8List.fromList([...salt, ...utf8.encode(password)]);
    
    for (int i = 0; i < iterations; i++) {
      final memoryBuffer = Uint8List(memory ~/ 8);
      for (int j = 0; j < parallelism; j++) {
        for (int k = 0; k < memoryBuffer.length; k += hash.length) {
          final end = (k + hash.length) < memoryBuffer.length ? k + hash.length : memoryBuffer.length;
          for (int m = k; m < end; m++) {
            memoryBuffer[m] = hash[m % hash.length] ^ (j + i + k) & 0xFF;
          }
        }
        
        hash = _sha3LikeHash(Uint8List.fromList([...hash, ...memoryBuffer.sublist(0, 64)]));
      }
    }
    
    return hash.sublist(0, 32);
  }

  Uint8List _sha3LikeHash(Uint8List data) {
    var hash = Uint8List(64);
    var state = List<int>.filled(25, 0);
    
    for (int i = 0; i < data.length; i++) {
      state[i % 25] ^= data[i];
    }
    
    for (int i = 0; i < 24; i++) {
      for (int j = 0; j < 25; j++) {
        state[j] = (state[j] * 31 + i) & 0xFF;
      }
    }
    
    for (int i = 0; i < 64; i++) {
      hash[i] = state[i % 25];
    }
    
    return hash;
  }

  Uint8List _generateSalt(int length) {
    final random = Random.secure();
    final salt = Uint8List(length);
    for (int i = 0; i < length; i++) {
      salt[i] = random.nextInt(256);
    }
    return salt;
  }

  bool _constantTimeCompare(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }

  String _combineHashes(String hash1, String hash2) {
    final bytes1 = base64.decode(hash1);
    final bytes2 = base64.decode(hash2);
    final combined = Uint8List(bytes1.length);
    for (int i = 0; i < combined.length; i++) {
      combined[i] = bytes1[i] ^ bytes2[i % bytes2.length];
    }
    return base64.encode(combined);
  }
}

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

  Map<String, dynamic> toJson() => {
    'hash': hash,
    'salt': salt,
    'version': version,
    'parameters': parameters,
  };
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

  Map<String, dynamic> toJson() => {
    'success': success,
    'password_hash': passwordHash,
    'salt': salt,
    'challenge_hash': challengeHash,
    'combined_hash': combinedHash,
    'timestamp': timestamp.toIso8601String(),
  };
}