// secret_app/lib/services/supabase_service.dart
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import 'encryption_service.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  final EncryptionService _encryption = EncryptionService();

  bool get isAvailable =>
      SupabaseConfig.isConfigured && SupabaseConfig.isInitialized;

  SupabaseClient get client => SupabaseConfig.client;

  Future<void> initialize() async {
    try {
      await SupabaseConfig.initialize();
      if (kDebugMode) {
        SupabaseConfig.printConfig();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error initializing Supabase Service: $e');
      }
      rethrow;
    }
  }

  // ===============================
  // REAL OTP VERIFICATION METHODS
  // ===============================

  /// Verify OTP code yang dikirim Supabase via email
  Future<bool> verifyEmailOtp(String email, String otpCode) async {
    if (!isAvailable) {
      throw Exception('Supabase not available');
    }

    try {
      if (kDebugMode) {
        debugPrint('🔍 Verifying OTP: $email -> $otpCode');
      }

      // Verify OTP menggunakan Supabase Auth
      final response = await client.auth.verifyOTP(
        email: email,
        token: otpCode,
        type: OtpType.signup,
      );

      if (response.user != null) {
        // Update user sebagai verified di database kita
        await client.from('users').update({
          'is_verified': true,
          'verified_at': DateTime.now().toIso8601String(),
        }).eq('email', email);

        if (kDebugMode) {
          debugPrint('✅ OTP verification successful');
        }
        return true;
      }

      return false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ OTP verification error: $e');
      }
      return false;
    }
  }

  /// Resend OTP verification email - FIXED VERSION
  Future<void> resendVerificationEmail(String email) async {
    if (!isAvailable) {
      throw Exception('Supabase not available');
    }

    try {
      if (kDebugMode) {
        debugPrint('📧 Resending verification email to: $email');
      }

      // FIX: Gunakan method yang lebih sederhana untuk resend email verification
      // Cara 1: Panggil signUp lagi dengan email yang sama (Supabase akan resend OTP)
      await client.auth.signUp(
        email: email, password: '',
        // Tidak perlu password untuk resend verification
      );

      // Atau Cara 2: Jika cara di atas tidak work, gunakan resetPasswordForEmail
      // await client.auth.resetPasswordForEmail(email);

      if (kDebugMode) {
        debugPrint('✅ Verification email resent');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error resending verification email: $e');
      }
      
      // Handle rate limit error
      if (e.toString().contains('over_email_send_rate_limit')) {
        throw Exception('Email rate limit exceeded. Please wait 1 minute before trying again.');
      }
      
      rethrow;
    }
  }

  /// Check if user email is verified
  Future<bool> isEmailVerified(String email) async {
    if (!isAvailable) {
      throw Exception('Supabase not available');
    }

    try {
      final response = await client
          .from('users')
          .select('is_verified')
          .eq('email', email)
          .single();

      return response['is_verified'] == true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error checking email verification: $e');
      }
      return false;
    }
  }

  // ===============================
  // AUTH METHODS
  // ===============================

  /// Get user authentication data including password hash and salt
  Future<Map<String, dynamic>?> getUserAuthData(String email) async {
    if (!isAvailable) {
      if (kDebugMode) {
        debugPrint('Supabase not available for getting user auth data');
      }
      return null;
    }

    try {
      final response = await client
          .from('users')
          .select('id, email, password_hash, salt, user_pin, display_name, is_verified')
          .eq('email', email)
          .single();

      return Map<String, dynamic>.from(response);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error getting user auth data: $e');
      }
      return null;
    }
  }

  /// Sign in user dengan email dan password
  Future<AuthResponse> signIn(String email, String password) async {
    if (!isAvailable) {
      throw Exception('Supabase not configured');
    }

    try {
      final response = await client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      
      if (kDebugMode) {
        debugPrint('✅ Sign in successful for: $email');
      }
      
      return response;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Sign in error: $e');
      }
      rethrow;
    }
  }

  /// Sign out user
  Future<void> signOut() async {
    if (!isAvailable) {
      if (kDebugMode) {
        debugPrint('Supabase not available for sign out');
      }
      return;
    }

    try {
      await client.auth.signOut();
      if (kDebugMode) {
        debugPrint('✅ Sign out successful');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Sign out error: $e');
      }
      rethrow;
    }
  }

  /// Get current user
  User? get currentUser {
    if (!isAvailable) {
      return null;
    }
    return client.auth.currentUser;
  }

  /// Get current user ID
  String? get currentUserId {
    return currentUser?.id;
  }

  /// Get current user email
  String? get currentUserEmail {
    return currentUser?.email;
  }

  /// Check if user is signed in
  bool get isSignedIn {
    if (!isAvailable) {
      return false;
    }
    return currentUser != null;
  }

  // ===============================
  // REGISTRATION METHODS
  // ===============================

  /// SignUp method dengan auto OTP sending
  Future<Map<String, dynamic>> signUpWithCrypto({
    required String email,
    required String password,
    required String displayName,
    required String passwordHash,
    required String salt,
  }) async {
    if (!isAvailable) {
      throw Exception('Supabase not configured. Check your .env file');
    }

    try {
      if (kDebugMode) {
        debugPrint('🔐 Starting Supabase registration with crypto...');
      }

      // 1. Daftar user di Supabase Auth - akan otomatis kirim OTP email
      final authResponse = await client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'display_name': displayName.trim()},
      );

      if (authResponse.user == null) {
        throw Exception('Registration failed - no user created in Auth');
      }

      final userId = authResponse.user!.id;
      if (userId.isEmpty) {
        throw Exception('Registration failed - user ID is empty');
      }

      // 2. Buat profile di tabel users
      final userPin = _generateUserPin();
      final userData = {
        'id': userId,
        'email': email.trim(),
        'display_name': displayName.trim(),
        'user_pin': userPin,
        'password_hash': passwordHash,
        'salt': salt,
        'is_verified': false, // Default false, akan diupdate setelah OTP verification
        'created_at': DateTime.now().toIso8601String(),
      };

      if (kDebugMode) {
        debugPrint('   💾 Creating user profile with crypto data');
        debugPrint('   📌 Generated PIN: $userPin');
        debugPrint('   🔐 Password Hash: ${passwordHash.substring(0, 20)}...');
        debugPrint('   🧂 Salt: ${salt.substring(0, 16)}...');
        debugPrint('   📧 OTP email sent to: $email');
      }

      final profileResult = await client
          .from('users')
          .insert(userData)
          .select()
          .single();

      if (profileResult == null) {
        throw Exception('Failed to create user profile in database');
      }

      final result = {
        'success': true,
        'user_id': userId,
        'email': email.trim(),
        'display_name': displayName.trim(),
        'user_pin': userPin,
      };

      if (kDebugMode) {
        debugPrint('✅ Registration successful! OTP email sent.');
        debugPrint('   👤 User ID: $userId');
        debugPrint('   📌 User PIN: $userPin');
        debugPrint('   🔐 Security: Hybrid Hash System');
      }
      return result;

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Sign up with crypto error: $e');
      }
      
      // Handle rate limit error
      if (e.toString().contains('over_email_send_rate_limit')) {
        throw Exception('Email rate limit exceeded. Please wait 1 minute or use a different email address.');
      }
      
      rethrow;
    }
  }

  // ===============================
  // DATABASE METHODS
  // ===============================

  Future<List<Map<String, dynamic>>> fetchData(
    String tableName, {
    Map<String, dynamic>? filters,
    int? limit,
  }) async {
    if (!isAvailable) {
      if (kDebugMode) {
        debugPrint('Supabase not available for fetching data');
      }
      return [];
    }

    try {
      dynamic query = client.from(tableName).select();

      if (filters != null) {
        for (final entry in filters.entries) {
          query = query.eq(entry.key, entry.value);
        }
      }

      if (limit != null) {
        query = query.limit(limit);
      }

      final response = await query;
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error fetching data from $tableName: $e');
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> insertData(
    String tableName,
    Map<String, dynamic> data,
  ) async {
    if (!isAvailable) {
      if (kDebugMode) {
        debugPrint('Supabase not available for inserting data');
      }
      return null;
    }

    try {
      final response = await client.from(tableName).insert(data).select();

      if (response is List && response.isNotEmpty) {
        return Map<String, dynamic>.from(response.first);
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error inserting data to $tableName: $e');
      }
      rethrow;
    }
  }

  Future<void> updateData(
    String tableName,
    Map<String, dynamic> data,
    String column,
    dynamic value,
  ) async {
    if (!isAvailable) {
      if (kDebugMode) {
        debugPrint('Supabase not available for updating data');
      }
      return;
    }

    try {
      await client.from(tableName).update(data).eq(column, value);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error updating data in $tableName: $e');
      }
      rethrow;
    }
  }

  Future<void> deleteData(
    String tableName,
    String column,
    dynamic value,
  ) async {
    if (!isAvailable) {
      if (kDebugMode) {
        debugPrint('Supabase not available for deleting data');
      }
      return;
    }

    try {
      await client.from(tableName).delete().eq(column, value);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error deleting data from $tableName: $e');
      }
      rethrow;
    }
  }

  // ===============================
  // REAL-TIME SUBSCRIPTIONS
  // ===============================

  Stream<List<Map<String, dynamic>>> subscribeToTable(String tableName) {
    if (!isAvailable) {
      if (kDebugMode) {
        debugPrint('Supabase not available for subscriptions');
      }
      return const Stream.empty();
    }

    try {
      return client.from(tableName).stream(primaryKey: ['id']).map((event) {
        return event.map((item) => Map<String, dynamic>.from(item)).toList();
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error subscribing to $tableName: $e');
      }
      return const Stream.empty();
    }
  }

  // ===============================
  // USER PROFILE METHODS
  // ===============================

  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final response = await client.from('users').select().eq('id', userId);

      if (response is List && response.isNotEmpty) {
        return Map<String, dynamic>.from(response.first);
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error getting user profile: $e');
      }
      return null;
    }
  }

  // ===============================
  // SECURE DATABASE ENCRYPTION METHODS
  // ===============================

  /// Store encrypted user sensitive data
  Future<void> storeEncryptedUserData({
    required String userId,
    required Map<String, dynamic> sensitiveData,
    required String masterKey,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('🔐 Storing encrypted user data...');
      }

      final encryptedData = await _encryption.encryptUserProfile(
        sensitiveData,
        masterKey: masterKey,
      );

      await client.from('user_encrypted_data').upsert({
        'user_id': userId,
        'encrypted_data': encryptedData['encrypted_data'],
        'iv': encryptedData['iv'],
        'algorithm': encryptedData['algorithm'],
        'updated_at': DateTime.now().toIso8601String(),
      });

      if (kDebugMode) {
        debugPrint('✅ Encrypted user data stored successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error storing encrypted user data: $e');
      }
      rethrow;
    }
  }

  /// Retrieve and decrypt user sensitive data
  Future<Map<String, dynamic>?> getEncryptedUserData({
    required String userId,
    required String masterKey,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('🔐 Retrieving encrypted user data...');
      }

      final response = await client
          .from('user_encrypted_data')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (response == null) return null;

      final encryptedProfile = {
        'encrypted_data': response['encrypted_data'],
        'iv': response['iv'],
      };

      final decryptedData = await _encryption.decryptUserProfile(
        encryptedProfile,
        masterKey: masterKey,
      );

      if (kDebugMode) {
        debugPrint('✅ Encrypted user data retrieved and decrypted');
      }

      return decryptedData;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error retrieving encrypted user data: $e');
      }
      return null;
    }
  }

  /// Store application settings dengan encryption
  Future<void> storeEncryptedSettings({
    required String settingsKey,
    required dynamic settingsValue,
    required String masterKey,
  }) async {
    try {
      final encrypted = await _encryption.encryptDatabaseData(
        json.encode(settingsValue),
        masterKey: masterKey,
      );

      await client.from('encrypted_settings').upsert({
        'settings_key': settingsKey,
        'encrypted_value': encrypted['encrypted_data'],
        'iv': encrypted['iv'],
        'algorithm': encrypted['algorithm'],
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error storing encrypted settings: $e');
      }
      rethrow;
    }
  }

  /// Retrieve application settings dengan decryption
  Future<dynamic> getEncryptedSettings({
    required String settingsKey,
    required String masterKey,
  }) async {
    try {
      final response = await client
          .from('encrypted_settings')
          .select()
          .eq('settings_key', settingsKey)
          .maybeSingle();

      if (response == null) return null;

      final decrypted = await _encryption.decryptDatabaseData(
        response['encrypted_value'] as String,
        masterKey: masterKey,
        iv: response['iv'] as String,
      );

      return json.decode(decrypted);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error retrieving encrypted settings: $e');
      }
      return null;
    }
  }

  // ===============================
  // DATABASE SCHEMA CREATION
  // ===============================

  /// Initialize encrypted tables (untuk development)
  Future<void> initializeEncryptedTables() async {
    try {
      if (kDebugMode) {
        debugPrint('🗃️ Initializing encrypted database tables...');
      }

      // Table untuk encrypted user data
      await client.rpc('create_encrypted_tables_if_not_exists');

      if (kDebugMode) {
        debugPrint('✅ Encrypted tables initialized');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error initializing encrypted tables: $e');
        debugPrint('💡 Create tables manually in Supabase:');
        debugPrint('''
          -- Encrypted User Data Table
          CREATE TABLE IF NOT EXISTS user_encrypted_data (
            user_id UUID PRIMARY KEY REFERENCES auth.users(id),
            encrypted_data TEXT NOT NULL,
            iv TEXT NOT NULL,
            algorithm TEXT NOT NULL,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
            updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
          );

          -- Encrypted Settings Table
          CREATE TABLE IF NOT EXISTS encrypted_settings (
            settings_key TEXT PRIMARY KEY,
            encrypted_value TEXT NOT NULL,
            iv TEXT NOT NULL,
            algorithm TEXT NOT NULL,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
            updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
          );
        ''');
      }
    }
  }

  // ===============================
  // CHAT METHODS
  // ===============================

  Future<List<Map<String, dynamic>>> getUserChats(String userId) async {
    if (!isAvailable) {
      if (kDebugMode) {
        debugPrint('Supabase not available for getting user chats');
      }
      return [];
    }

    try {
      // Query untuk mendapatkan chat user
      final response = await client
          .from('chats')
          .select('''
            *,
            user1:users!chats_user1_id_fkey(display_name, user_pin),
            user2:users!chats_user2_id_fkey(display_name, user_pin)
          ''')
          .or('user1_id.eq.$userId,user2_id.eq.$userId');

      final List<Map<String, dynamic>> chats = [];
      
      for (final chat in response) {
        final isUser1 = chat['user1_id'] == userId;
        final otherUser = isUser1 ? chat['user2'] : chat['user1'];
        
        chats.add({
          'chat_id': chat['id'],
          'other_user_name': otherUser['display_name'] ?? 'Unknown User',
          'other_user_pin': otherUser['user_pin'] ?? 'Unknown',
        });
      }
      
      return chats;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error getting user chats: $e');
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> searchUserByPin(String pin) async {
    if (!isAvailable) {
      if (kDebugMode) {
        debugPrint('Supabase not available for user search');
      }
      return null;
    }

    try {
      final response = await client
          .from('users')
          .select()
          .eq('user_pin', pin)
          .single();

      return Map<String, dynamic>.from(response);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error searching user by PIN: $e');
      }
      return null;
    }
  }

  Future<String> startChat(String user1Id, String user2Id) async {
    if (!isAvailable) {
      if (kDebugMode) {
        debugPrint('Supabase not available for starting chat');
      }
      throw Exception('Supabase not available');
    }

    try {
      // Cek apakah chat sudah ada
      final existingChat = await client
          .from('chats')
          .select()
          .or('and(user1_id.eq.$user1Id,user2_id.eq.$user2Id),and(user1_id.eq.$user2Id,user2_id.eq.$user1Id)')
          .maybeSingle();

      if (existingChat != null) {
        return existingChat['id'];
      }

      // Buat chat baru
      final response = await client
          .from('chats')
          .insert({
            'user1_id': user1Id,
            'user2_id': user2Id,
            'created_at': DateTime.now().toIso8601String(),
          })
          .select()
          .single();

      return response['id'];
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error starting chat: $e');
      }
      rethrow;
    }
  }

  // ===============================
  // MESSAGE METHODS
  // ===============================

  Future<List<Map<String, dynamic>>> getEncryptedMessages(String chatId) async {
    return await fetchData('messages', filters: {'chat_id': chatId});
  }

  Stream<List<Map<String, dynamic>>> subscribeToMessages(String chatId) {
    if (!isAvailable) {
      return const Stream.empty();
    }

    return client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('chat_id', chatId)
        .map(
          (event) =>
              event.map((item) => Map<String, dynamic>.from(item)).toList(),
        );
  }

  Future<Map<String, dynamic>?> sendEncryptedMessage({
    required String chatId,
    required String senderId,
    required String encryptedMessage,
    required String iv,
  }) async {
    return await insertData('messages', {
      'chat_id': chatId,
      'sender_id': senderId,
      'encrypted_message': encryptedMessage,
      'iv': iv,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  // ===============================
  // HELPER METHODS
  // ===============================

  String _generateUserPin() {
    try {
      final random = Random.secure();
      final pin = (random.nextInt(900000) + 100000).toString(); // 100000-999999

      if (pin.length != 6) {
        throw Exception('Generated PIN length is not 6: $pin');
      }

      if (kDebugMode) {
        debugPrint('🎰 Generated PIN: $pin');
      }
      return pin;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error generating PIN: $e');
      }
      return '123456'; // Fallback PIN
    }
  }

  // ===============================
  // TEST CONNECTION
  // ===============================

  Future<bool> testConnection() async {
    if (!isAvailable) {
      return false;
    }

    try {
      await SupabaseConfig.testConnection();
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Connection test failed: $e');
      }
      return false;
    }
  }

  void printDebugInfo() {
    if (kDebugMode) {
      debugPrint('=== Supabase Service Debug Info ===');
      debugPrint('Available: $isAvailable');
      debugPrint('Signed In: $isSignedIn');
      debugPrint('User ID: ${currentUserId ?? 'None'}');
      debugPrint('User Email: ${currentUserEmail ?? 'None'}');
      debugPrint('OTP System: Real Supabase OTP');
      debugPrint('Encryption: Camellia-256 + XOR');
      debugPrint('==================================');
    }
  }

}