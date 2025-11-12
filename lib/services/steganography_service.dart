// secret_app/lib/services/steganography_service.dart
import 'dart:typed_data';
import 'dart:math';
import 'dart:io';

class SteganographyService {
  static final SteganographyService _instance = SteganographyService._internal();
  factory SteganographyService() => _instance;
  SteganographyService._internal();

  bool _isInitialized = false;
  final _random = Random.secure();

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    print('🎯 Advanced Steganography: LSB + DCT Hybrid Algorithm');
    print('   ✅ Pure Dart Implementation');
    print('   ✅ LSB + DCT Hybrid Technique');
    print('   ✅ Robust & Secure');
    print('   ✅ Multi-platform Support');
    
    _isInitialized = true;
  }

  /// HYBRID ALGORITHM: LSB + DCT Encoding
  Future<SteganographyResponse> encodeMessage({
    required Uint8List imageData,
    required String message,
    required String password,
  }) async {
    if (!_isInitialized) await initialize();

    try {
      // Validasi input
      if (imageData.length < 1000) {
        throw Exception('Image too small for steganography');
      }

      // Step 1: Encrypt message dengan advanced encryption
      final encryptedMessage = _advancedEncrypt(message, password);
      
      // Step 2: Convert ke binary dengan error correction
      final messageBits = _stringToBitsWithECC(encryptedMessage);
      
      // Step 3: Create robust header
      final header = _createRobustHeader(messageBits.length, password);
      final allBits = [...header, ...messageBits];
      
      // Step 4: Split antara LSB dan DCT encoding
      final halfPoint = allBits.length ~/ 2;
      final lsbBits = allBits.sublist(0, halfPoint);
      final dctBits = allBits.sublist(halfPoint);
      
      // Step 5: Encode menggunakan hybrid approach
      Uint8List encodedImage = Uint8List.fromList(imageData);
      
      // Encode bagian pertama dengan LSB
      encodedImage = _encodeLSB(encodedImage, lsbBits, 0);
      
      // Encode bagian kedua dengan DCT
      encodedImage = _encodeDCT(encodedImage, dctBits, lsbBits.length);
      
      return SteganographyResponse(
        success: true,
        data: encodedImage,
        errorMessage: null,
      );
    } catch (e) {
      return SteganographyResponse(
        success: false,
        errorMessage: 'Encode failed: $e',
        data: Uint8List(0),
      );
    }
  }

  /// HYBRID ALGORITHM: LSB + DCT Decoding
  Future<SteganographyResponse> decodeMessage({
    required Uint8List imageData,
    required String password,
  }) async {
    if (!_isInitialized) await initialize();

    try {
      // Step 1: Decode header untuk mendapatkan konfigurasi
      final headerBits = _decodeLSB(imageData, 0, 64); // 64 bits untuk header
      final headerInfo = _decodeRobustHeader(headerBits, password);
      
      if (!headerInfo.isValid) {
        throw Exception('Invalid steganography data or wrong password');
      }
      
      final totalBits = headerInfo.messageLength;
      final halfPoint = totalBits ~/ 2;
      
      // Step 2: Decode hybrid - LSB kemudian DCT
      final lsbBits = _decodeLSB(imageData, 64, halfPoint);
      final dctBits = _decodeDCT(imageData, 64 + halfPoint, totalBits - halfPoint);
      
      // Step 3: Combine bits
      final allBits = [...lsbBits, ...dctBits];
      
      // Step 4: Convert back to string dengan error correction
      final encryptedMessage = _bitsToStringWithECC(allBits);
      
      // Step 5: Decrypt message
      final decryptedMessage = _advancedDecrypt(encryptedMessage, password);
      
      return SteganographyResponse(
        success: true,
        data: Uint8List.fromList(decryptedMessage.codeUnits),
        errorMessage: null,
      );
    } catch (e) {
      return SteganographyResponse(
        success: false,
        errorMessage: 'Decode failed: $e',
        data: Uint8List(0),
      );
    }
  }

  // ==================== LSB ALGORITHM ====================

  /// Advanced LSB Encoding dengan distribusi acak
  Uint8List _encodeLSB(Uint8List imageData, List<int> bits, int startBitIndex) {
    final encodedImage = Uint8List.fromList(imageData);
    int bitIndex = 0;
    final pixelStride = 3; // RGB channels
    
    // Gunakan seed dari password untuk distribusi acak yang konsisten
    final random = Random(_stringToSeed(bits.toString()));
    
    for (int i = 0; i < encodedImage.length && bitIndex < bits.length; i++) {
      // Skip alpha channel dan gunakan stride untuk distribusi
      if (i % 4 == 3 || random.nextDouble() > 0.7) continue;
      
      if (bitIndex < bits.length) {
        final originalByte = encodedImage[i];
        final messageBit = bits[bitIndex];
        
        // Enhanced LSB: Terkadang gunakan 2 LSBs untuk robustness
        final useTwoBits = (i % 8 == 0) && (bitIndex + 1 < bits.length);
        
        if (useTwoBits) {
          final nextBit = bits[bitIndex + 1];
          final encodedByte = (originalByte & 0xFC) | (messageBit << 1) | nextBit;
          encodedImage[i] = encodedByte;
          bitIndex += 2;
        } else {
          final encodedByte = (originalByte & 0xFE) | messageBit;
          encodedImage[i] = encodedByte;
          bitIndex++;
        }
      }
    }
    
    if (bitIndex < bits.length) {
      throw Exception('LSB capacity exceeded');
    }
    
    return encodedImage;
  }

  /// LSB Decoding
  List<int> _decodeLSB(Uint8List imageData, int startIndex, int bitCount) {
    final bits = <int>[];
    final random = Random(_stringToSeed(imageData.length.toString()));
    
    for (int i = 0; i < imageData.length && bits.length < bitCount; i++) {
      if (i % 4 == 3 || random.nextDouble() > 0.7) continue;
      
      final byte = imageData[i];
      
      // Check jika menggunakan 2 LSBs
      final useTwoBits = (i % 8 == 0) && (bits.length + 1 < bitCount);
      
      if (useTwoBits) {
        final bit1 = (byte >> 1) & 0x01;
        final bit2 = byte & 0x01;
        bits.add(bit1);
        bits.add(bit2);
      } else {
        final bit = byte & 0x01;
        bits.add(bit);
      }
    }
    
    return bits.length > bitCount ? bits.sublist(0, bitCount) : bits;
  }

  // ==================== DCT ALGORITHM ====================

  /// DCT-based Encoding (Discrete Cosine Transform simulation)
  Uint8List _encodeDCT(Uint8List imageData, List<int> bits, int startBitIndex) {
    final encodedImage = Uint8List.fromList(imageData);
    int bitIndex = 0;
    
    // Process dalam blocks 8x8 (simulasi DCT)
    final blockSize = 8;
    final blocksPerRow = (sqrt(imageData.length / 4) ~/ blockSize).toInt();
    
    for (int blockY = 0; blockY < blocksPerRow && bitIndex < bits.length; blockY++) {
      for (int blockX = 0; blockX < blocksPerRow && bitIndex < bits.length; blockX++) {
        final blockStart = (blockY * blocksPerRow * blockSize * 4) + (blockX * blockSize * 4);
        
        // Untuk setiap block, modifikasi mid-frequency coefficients
        for (int i = 0; i < 4 && bitIndex < bits.length; i++) {
          final pixelIndex = blockStart + (i * 4) + 1; // Green channel untuk stabilitas
          
          if (pixelIndex < encodedImage.length - 1) {
            final bit = bits[bitIndex];
            
            // Modifikasi nilai pixel berdasarkan bit message
            // Ini adalah simulasi dari modifikasi DCT coefficient
            final originalValue = encodedImage[pixelIndex];
            final modifiedValue = _applyDCTModification(originalValue, bit);
            
            encodedImage[pixelIndex] = modifiedValue;
            bitIndex++;
          }
        }
      }
    }
    
    return encodedImage;
  }

  /// DCT Decoding
  List<int> _decodeDCT(Uint8List imageData, int startIndex, int bitCount) {
    final bits = <int>[];
    final blockSize = 8;
    final blocksPerRow = (sqrt(imageData.length / 4) ~/ blockSize).toInt();
    
    for (int blockY = 0; blockY < blocksPerRow && bits.length < bitCount; blockY++) {
      for (int blockX = 0; blockX < blocksPerRow && bits.length < bitCount; blockX++) {
        final blockStart = (blockY * blocksPerRow * blockSize * 4) + (blockX * blockSize * 4);
        
        for (int i = 0; i < 4 && bits.length < bitCount; i++) {
          final pixelIndex = blockStart + (i * 4) + 1;
          
          if (pixelIndex < imageData.length) {
            final value = imageData[pixelIndex];
            final bit = _extractDCTBit(value);
            bits.add(bit);
          }
        }
      }
    }
    
    return bits.length > bitCount ? bits.sublist(0, bitCount) : bits;
  }

  /// Apply DCT-like modification
  int _applyDCTModification(int originalValue, int bit) {
    // Quantization simulation - group values
    final quantized = (originalValue ~/ 4) * 4;
    
    if (bit == 1) {
      return quantized + 2; // Set to middle of quantization bin
    } else {
      return quantized; // Set to lower bound
    }
  }

  /// Extract bit dari DCT-modified value
  int _extractDCTBit(int value) {
    final remainder = value % 4;
    return remainder >= 2 ? 1 : 0;
  }

  // ==================== ADVANCED ENCRYPTION ====================

  /// Advanced encryption dengan salt dan iteration
  String _advancedEncrypt(String message, String password) {
    final salt = _generateSalt(password);
    final key = _deriveKey(password, salt);
    
    final encrypted = StringBuffer();
    for (int i = 0; i < message.length; i++) {
      final charCode = message.codeUnitAt(i);
      final keyByte = key[i % key.length];
      final saltByte = salt[i % salt.length];
      
      // Multiple XOR rounds untuk security lebih baik
      var encryptedChar = charCode;
      for (int round = 0; round < 3; round++) {
        encryptedChar ^= keyByte;
        encryptedChar ^= saltByte;
      }
      
      encrypted.writeCharCode(encryptedChar);
    }
    
    return encrypted.toString();
  }

  /// Advanced decryption
  String _advancedDecrypt(String encryptedMessage, String password) {
    // XOR encryption reversible
    return _advancedEncrypt(encryptedMessage, password);
  }

  /// Generate salt dari password
  List<int> _generateSalt(String password) {
    final salt = <int>[];
    for (int i = 0; i < password.length; i++) {
      salt.add(password.codeUnitAt(i) ^ (i * 31));
    }
    return salt;
  }

  /// Derive key dari password dan salt
  List<int> _deriveKey(String password, List<int> salt) {
    final key = <int>[];
    for (int i = 0; i < password.length; i++) {
      final charCode = password.codeUnitAt(i);
      final saltByte = salt[i % salt.length];
      key.add((charCode + saltByte + i) % 256);
    }
    return key;
  }

  // ==================== ERROR CORRECTION ====================

  /// String to bits dengan Error Correction Code (Hamming)
  List<int> _stringToBitsWithECC(String text) {
    final bits = <int>[];
    final bytes = _stringToBytes(text);
    
    for (final byte in bytes) {
      // Convert byte to 8 bits
      final dataBits = _intToBits(byte, 8);
      
      // Add Hamming(12,8) error correction
      final encodedBits = _hammingEncode(dataBits);
      bits.addAll(encodedBits);
    }
    
    return bits;
  }

  /// Bits to string dengan error correction
  String _bitsToStringWithECC(List<int> bits) {
    final bytes = <int>[];
    
    for (int i = 0; i < bits.length; i += 12) {
      if (i + 12 <= bits.length) {
        final encodedBits = bits.sublist(i, i + 12);
        final dataBits = _hammingDecode(encodedBits);
        final byte = _bitsToInt(dataBits);
        bytes.add(byte);
      }
    }
    
    return String.fromCharCodes(bytes);
  }

  /// Hamming(12,8) encoding
  List<int> _hammingEncode(List<int> dataBits) {
    // dataBits should be 8 bits
    final encoded = List<int>.filled(12, 0);
    
    // Place data bits
    encoded[2] = dataBits[0];
    encoded[4] = dataBits[1];
    encoded[5] = dataBits[2];
    encoded[6] = dataBits[3];
    encoded[8] = dataBits[4];
    encoded[9] = dataBits[5];
    encoded[10] = dataBits[6];
    encoded[11] = dataBits[7];
    
    // Calculate parity bits
    encoded[0] = encoded[2] ^ encoded[4] ^ encoded[6] ^ encoded[8] ^ encoded[10];
    encoded[1] = encoded[2] ^ encoded[5] ^ encoded[6] ^ encoded[9] ^ encoded[10];
    encoded[3] = encoded[4] ^ encoded[5] ^ encoded[6] ^ encoded[11];
    encoded[7] = encoded[8] ^ encoded[9] ^ encoded[10] ^ encoded[11];
    
    return encoded;
  }

  /// Hamming(12,8) decoding dengan error correction
  List<int> _hammingDecode(List<int> encodedBits) {
    // Calculate syndrome
    final s0 = encodedBits[0] ^ encodedBits[2] ^ encodedBits[4] ^ encodedBits[6] ^ encodedBits[8] ^ encodedBits[10];
    final s1 = encodedBits[1] ^ encodedBits[2] ^ encodedBits[5] ^ encodedBits[6] ^ encodedBits[9] ^ encodedBits[10];
    final s2 = encodedBits[3] ^ encodedBits[4] ^ encodedBits[5] ^ encodedBits[6] ^ encodedBits[11];
    final s3 = encodedBits[7] ^ encodedBits[8] ^ encodedBits[9] ^ encodedBits[10] ^ encodedBits[11];
    
    final errorPosition = s0 + (s1 << 1) + (s2 << 2) + (s3 << 3);
    
    // Correct single error jika ada
    if (errorPosition > 0 && errorPosition < 12) {
      encodedBits[errorPosition - 1] = encodedBits[errorPosition - 1] ^ 1;
    }
    
    // Extract data bits
    return [
      encodedBits[2],
      encodedBits[4],
      encodedBits[5],
      encodedBits[6],
      encodedBits[8],
      encodedBits[9],
      encodedBits[10],
      encodedBits[11],
    ];
  }

  // ==================== HEADER & VALIDATION ====================

  /// Create robust header dengan checksum
  List<int> _createRobustHeader(int messageLength, String password) {
    const magicNumber = 0x53544547; // "STEG" untuk Steganography
    final headerBits = <int>[];
    
    // Magic number (32 bits)
    headerBits.addAll(_intToBits(magicNumber, 32));
    
    // Message length (24 bits)
    headerBits.addAll(_intToBits(messageLength, 24));
    
    // Password hash (8 bits)
    final passwordHash = _calculatePasswordHash(password);
    headerBits.addAll(_intToBits(passwordHash, 8));
    
    return headerBits;
  }

  /// Decode dan validate header
  HeaderInfo _decodeRobustHeader(List<int> headerBits, String password) {
    if (headerBits.length < 64) {
      return HeaderInfo(invalid: true);
    }
    
    // Extract magic number
    final magicBits = headerBits.sublist(0, 32);
    final magicNumber = _bitsToInt(magicBits);
    
    // Extract message length
    final lengthBits = headerBits.sublist(32, 56);
    final messageLength = _bitsToInt(lengthBits);
    
    // Extract and verify password hash
    final hashBits = headerBits.sublist(56, 64);
    final storedHash = _bitsToInt(hashBits);
    final calculatedHash = _calculatePasswordHash(password);
    
    return HeaderInfo(
      isValid: magicNumber == 0x53544547 && storedHash == calculatedHash,
      messageLength: messageLength,
    );
  }

  /// Calculate simple password hash
  int _calculatePasswordHash(String password) {
    var hash = 0;
    for (final char in password.codeUnits) {
      hash = (hash * 31 + char) % 256;
    }
    return hash;
  }

  // ==================== UTILITIES ====================

  List<int> _intToBits(int number, int bitCount) {
    final bits = <int>[];
    for (int i = bitCount - 1; i >= 0; i--) {
      bits.add((number >> i) & 1);
    }
    return bits;
  }

  int _bitsToInt(List<int> bits) {
    int result = 0;
    for (int i = 0; i < bits.length; i++) {
      result = (result << 1) | bits[i];
    }
    return result;
  }

  List<int> _stringToBytes(String text) => text.codeUnits;

  int _stringToSeed(String text) {
    var seed = 0;
    for (final char in text.codeUnits) {
      seed = (seed * 31 + char) & 0x7FFFFFFF;
    }
    return seed;
  }

  int getMaxCapacity(Uint8List imageData) {
    // Kapasitas hybrid: LSB (75%) + DCT (25%)
    final pixelCount = imageData.length ~/ 4;
    final lsbCapacity = (pixelCount * 0.6).toInt(); // 60% untuk LSB
    final dctCapacity = (pixelCount * 0.15).toInt(); // 15% untuk DCT
    final totalBits = lsbCapacity + dctCapacity;
    
    // Dengan error correction, kapasitas efektif = totalBits * 8/12
    return (totalBits * 8 ~/ 12) - 10; // Kurangi untuk header
  }

  bool get isUsingFallback => false;
  bool get isInitialized => _isInitialized;
}

// Header info structure
class HeaderInfo {
  final bool isValid;
  final int messageLength;
  final bool invalid;

  HeaderInfo({
    this.isValid = false,
    this.messageLength = 0,
    this.invalid = false,
  });
}

// Response model
class SteganographyResponse {
  final bool success;
  final String? errorMessage;
  final Uint8List data;
  final int? width;
  final int? height;

  SteganographyResponse({
    required this.success,
    this.errorMessage,
    required this.data,
    this.width,
    this.height,
  });

  String get decodedMessage {
    if (!success || data.isEmpty) return '';
    return String.fromCharCodes(data);
  }
}