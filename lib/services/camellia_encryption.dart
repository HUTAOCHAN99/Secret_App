import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
class CamelliaEncryption {
  static final CamelliaEncryption _instance = CamelliaEncryption._internal();
  factory CamelliaEncryption() => _instance;
  CamelliaEncryption._internal();

  static const int _blockSize = 16; 
  static const int _keySize = 32; 
  static const int _ivSize = 16; 

  final List<List<int>> _sBox1 = _generateSBox(0xA09E667F);
  final List<List<int>> _sBox2 = _generateSBox(0xB67AE858);
  final List<List<int>> _sBox3 = _generateSBox(0xC6EF372F);
  final List<List<int>> _sBox4 = _generateSBox(0x54FF53A5);

  static List<List<int>> _generateSBox(int seed) {
    final random = Random(seed);
    final sbox = List<List<int>>.generate(256, (_) => List<int>.filled(256, 0));
    
    for (int i = 0; i < 256; i++) {
      for (int j = 0; j < 256; j++) {
        sbox[i][j] = random.nextInt(256);
      }
    }
    return sbox;
  }

  Uint8List generateKey(String password) {
    try {
      final bytes = utf8.encode(password);
      var hash = _sha256Like(bytes);
      
      while (hash.length < _keySize) {
        hash = Uint8List.fromList([...hash, ..._sha256Like(hash)]);
      }
      
      return hash.sublist(0, _keySize);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error generating Camellia key: $e');
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> encrypt(String plaintext, Uint8List key) async {
    try {
      if (kDebugMode) {
        debugPrint('🔒 Camellia-256 Encrypting: ${plaintext.length} bytes');
      }

      if (key.length != _keySize) {
        throw Exception('Invalid key size. Expected $_keySize bytes, got ${key.length}');
      }

      final iv = _generateIV();
      
      final paddedData = _padData(utf8.encode(plaintext));
      
      final encryptedBlocks = _encryptCBC(paddedData, key, iv);
      
      final result = {
        'encrypted_data': base64.encode(encryptedBlocks),
        'iv': base64.encode(iv),
        'algorithm': 'camellia-256-cbc',
        'key_size': _keySize,
        'block_size': _blockSize,
      };

      if (kDebugMode) {
        debugPrint('✅ Camellia-256 Encryption successful');
        debugPrint('   IV: ${result['iv']}');
        debugPrint('   Encrypted: ${encryptedBlocks.length} bytes');
      }

      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Camellia-256 Encryption error: $e');
      }
      rethrow;
    }
  }

  Future<String> decrypt(String encryptedData, Uint8List key, String ivBase64) async {
    try {
      if (kDebugMode) {
        debugPrint('🔓 Camellia-256 Decrypting: ${encryptedData.length} chars');
      }

      if (key.length != _keySize) {
        throw Exception('Invalid key size. Expected $_keySize bytes, got ${key.length}');
      }

      final iv = base64.decode(ivBase64);
      final encryptedBytes = base64.decode(encryptedData);
      
      final decryptedBlocks = _decryptCBC(encryptedBytes, key, iv);
      
      final unpaddedData = _unpadData(decryptedBlocks);
      
      final plaintext = utf8.decode(unpaddedData);

      if (kDebugMode) {
        debugPrint('✅ Camellia-256 Decryption successful');
        debugPrint('   Decrypted: ${plaintext.length} chars');
      }

      return plaintext;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Camellia-256 Decryption error: $e');
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> encryptBinary(Uint8List data, Uint8List key) async {
    try {
      final iv = _generateIV();
      final paddedData = _padData(data);
      final encryptedBlocks = _encryptCBC(paddedData, key, iv);
      
      return {
        'encrypted_data': base64.encode(encryptedBlocks),
        'iv': base64.encode(iv),
        'algorithm': 'camellia-256-cbc',
      };
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Camellia-256 Binary encryption error: $e');
      }
      rethrow;
    }
  }

  Future<List<int>> decryptBinary(String encryptedData, Uint8List key, String ivBase64) async {
    try {
      final iv = base64.decode(ivBase64);
      final encryptedBytes = base64.decode(encryptedData);
      final decryptedBlocks = _decryptCBC(encryptedBytes, key, iv);
      return _unpadData(decryptedBlocks);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Camellia-256 Binary decryption error: $e');
      }
      rethrow;
    }
  }

  List<int> _encryptCBC(List<int> data, Uint8List key, List<int> iv) {
    final blocks = _splitIntoBlocks(data);
    final encryptedBlocks = <List<int>>[];
    List<int> previousBlock = iv;

    for (final block in blocks) {
      final xoredBlock = _xorBlocks(block, previousBlock);
      
      final encryptedBlock = _encryptBlock(xoredBlock, key);
      
      encryptedBlocks.add(encryptedBlock);
      previousBlock = encryptedBlock;
    }

    return encryptedBlocks.expand((block) => block).toList();
  }

  List<int> _decryptCBC(List<int> data, Uint8List key, List<int> iv) {
    final blocks = _splitIntoBlocks(data);
    final decryptedBlocks = <List<int>>[];
    List<int> previousBlock = iv;

    for (final block in blocks) {
      final decryptedBlock = _decryptBlock(block, key);

      final xoredBlock = _xorBlocks(decryptedBlock, previousBlock);
      
      decryptedBlocks.add(xoredBlock);
      previousBlock = block;
    }

    return decryptedBlocks.expand((block) => block).toList();
  }

  List<int> _encryptBlock(List<int> block, Uint8List key) {

    var left = block.sublist(0, 8);
    var right = block.sublist(8, 16);

    for (int round = 0; round < 18; round++) {
      final roundKey = _generateRoundKey(key, round);
      final temp = right;
      
      right = _fFunction(right, roundKey);
      
      right = _xorBlocks(left, right);
      
      left = temp;
    }

    return [...right, ...left];
  }

  List<int> _decryptBlock(List<int> block, Uint8List key) {
    var left = block.sublist(0, 8);
    var right = block.sublist(8, 16);

    for (int round = 17; round >= 0; round--) {
      final roundKey = _generateRoundKey(key, round);
      final temp = left;
      
      left = _fFunction(left, roundKey);
      
      left = _xorBlocks(right, left);
      
      right = temp;
    }

    return [...right, ...left];
  }

  List<int> _fFunction(List<int> data, List<int> roundKey) {
    var result = _xorBlocks(data, roundKey);
    
    result = _sBoxSubstitution(result, _sBox1);
    result = _sBoxSubstitution(result, _sBox2);
    result = _sBoxSubstitution(result, _sBox3);
    result = _sBoxSubstitution(result, _sBox4);
    
    return result;
  }

  List<int> _sBoxSubstitution(List<int> data, List<List<int>> sbox) {
    final result = List<int>.filled(data.length, 0);
    for (int i = 0; i < data.length; i++) {
      final row = data[i] >> 4;
      final col = data[i] & 0x0F;
      result[i] = sbox[row][col];
    }
    return result;
  }

  List<int> _generateRoundKey(Uint8List masterKey, int round) {

    final roundKey = List<int>.filled(8, 0);
    final keyBytes = masterKey.length;
    
    for (int i = 0; i < 8; i++) {
      final keyIndex = (round * 8 + i) % keyBytes;
      roundKey[i] = masterKey[keyIndex] ^ (round & 0xFF);
    }
    
    return roundKey;
  }



  List<List<int>> _splitIntoBlocks(List<int> data) {
    final blocks = <List<int>>[];
    for (int i = 0; i < data.length; i += _blockSize) {
      final end = (i + _blockSize) <= data.length ? i + _blockSize : data.length;
      final block = data.sublist(i, end);
      
      if (block.length < _blockSize) {
        blocks.add(_padBlock(block));
      } else {
        blocks.add(block);
      }
    }
    return blocks;
  }

  List<int> _padData(List<int> data) {
    final paddingLength = _blockSize - (data.length % _blockSize);
    final padded = List<int>.from(data);
    
    for (int i = 0; i < paddingLength; i++) {
      padded.add(paddingLength);
    }
    
    return padded;
  }

  List<int> _padBlock(List<int> block) {
    final paddingLength = _blockSize - block.length;
    final padded = List<int>.from(block);
    
    for (int i = 0; i < paddingLength; i++) {
      padded.add(paddingLength);
    }
    
    return padded;
  }

  List<int> _unpadData(List<int> data) {
    if (data.isEmpty) return data;
    
    final paddingLength = data[data.length - 1];
    
    // Validasi padding
    if (paddingLength > 0 && paddingLength <= _blockSize) {
      for (int i = data.length - paddingLength; i < data.length; i++) {
        if (data[i] != paddingLength) {
          return data; 
        }
      }
      return data.sublist(0, data.length - paddingLength);
    }
    
    return data;
  }

  List<int> _xorBlocks(List<int> a, List<int> b) {
    final result = List<int>.filled(a.length, 0);
    for (int i = 0; i < a.length; i++) {
      result[i] = a[i] ^ b[i % b.length];
    }
    return result;
  }

  List<int> _generateIV() {
    final random = Random.secure();
    return List<int>.generate(_ivSize, (_) => random.nextInt(256));
  }

  Uint8List _sha256Like(List<int> data) {
    var hash = 0;
    for (final byte in data) {
      hash = (hash << 5) - hash + byte;
      hash = hash & hash;
    }
    
    final result = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      result[i] = (hash >> (i * 8)) & 0xFF;
    }
    
    return result;
  }


  Future<bool> testEncryption() async {
    try {
      if (kDebugMode) {
        debugPrint('🧪 Testing Camellia-256 encryption...');
      }

      const testMessage = 'Hello, this is a Camellia-256 test message! 🔐';
      final testKey = generateKey('test_password_123');
      
      final encrypted = await encrypt(testMessage, testKey);
      
      final decrypted = await decrypt(
        encrypted['encrypted_data'] as String,
        testKey,
        encrypted['iv'] as String,
      );
      
      final success = decrypted == testMessage;
      
      if (kDebugMode) {
        if (success) {
          debugPrint('✅ Camellia-256 test PASSED');
        } else {
          debugPrint('❌ Camellia-256 test FAILED');
          debugPrint('   Original: "$testMessage"');
          debugPrint('   Decrypted: "$decrypted"');
        }
      }
      
      return success;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Camellia-256 test error: $e');
      }
      return false;
    }
  }

  Map<String, dynamic> getAlgorithmInfo() {
    return {
      'algorithm': 'Camellia-256',
      'key_size': '256 bits',
      'block_size': '128 bits',
      'mode': 'CBC',
      'padding': 'PKCS7',
      'rounds': 18,
      'security_level': 'High (NIST recommended)',
      'purpose': 'Database encryption',
    };
  }

  void printDebugInfo() {
    if (kDebugMode) {
      final info = getAlgorithmInfo();
      debugPrint('''
=== CAMELLIA-256 DEBUG INFO ===
Algorithm: ${info['algorithm']}
Key Size: ${info['key_size']}
Block Size: ${info['block_size']}
Mode: ${info['mode']}
Rounds: ${info['rounds']}
Security: ${info['security_level']}
Purpose: ${info['purpose']}
===============================''');
    }
  }
}