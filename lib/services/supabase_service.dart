// secret_app/lib/services/supabase_service.dart
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'package:archive/archive.dart';
import '../config/supabase_config.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

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
  // FILE PICKER & STORAGE METHODS
  // ===============================

  /// Pick file dari device
  Future<FilePickerResult?> pickFileWithLocation() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final platformFile = result.files.first;
        if (kDebugMode) {
          debugPrint('📁 File picked: ${platformFile.name}');
          debugPrint('   Size: ${platformFile.size} bytes');
          debugPrint('   Has data: ${platformFile.bytes != null}');
        }
      }

      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ File picker error: $e');
      }
      return null;
    }
  }

  /// Save file ke device
  Future<File> saveFileToLocation({
    required Uint8List data,
    required String fileName,
    required String locationType,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final savePath = '${tempDir.path}/$fileName';
      final file = File(savePath);
      
      await file.writeAsBytes(data);
      
      if (kDebugMode) {
        debugPrint('💾 File saved to: $savePath');
      }
      
      return file;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error saving file: $e');
      }
      final tempFile = File('${await getTemporaryDirectory()}/temp_$fileName');
      await tempFile.writeAsBytes(data);
      return tempFile;
    }
  }

  /// Download file dan simpan
  Future<File> downloadAndSaveFile({
    required String filePath,
    required String fileName,
    required String locationType,
  }) async {
    try {
      final fileData = await downloadEncryptedFile(filePath);
      return await saveFileToLocation(
        data: fileData,
        fileName: fileName,
        locationType: locationType,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error downloading and saving file: $e');
      }
      rethrow;
    }
  }

  // ===============================
  // FILE COMPRESSION & PROCESSING
  // ===============================

  /// Compress image dengan quality adjustment
  Future<Uint8List> compressImage(Uint8List imageData, {int quality = 80}) async {
    try {
      if (kDebugMode) {
        debugPrint('🖼️ Compressing image with quality: $quality%');
      }

      final image = img.decodeImage(imageData);
      if (image == null) {
        throw Exception('Cannot decode image');
      }

      // Resize jika terlalu besar (max width 1200px)
      final resizedImage = image.width > 1200 
          ? img.copyResize(image, width: 1200)
          : image;

      // Encode dengan quality setting
      final compressedData = img.encodeJpg(resizedImage, quality: quality);

      if (kDebugMode) {
        final originalSize = imageData.length;
        final compressedSize = compressedData.length;
        final compressionRatio = ((originalSize - compressedSize) / originalSize * 100).round();
        debugPrint('✅ Image compressed: $originalSize → $compressedSize bytes ($compressionRatio% reduction)');
      }

      return Uint8List.fromList(compressedData);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Image compression error: $e');
      }
      return imageData;
    }
  }

  /// Compress text file dengan gzip
  Future<Uint8List> compressTextFile(Uint8List textData) async {
    try {
      if (kDebugMode) {
        debugPrint('📝 Compressing text file...');
      }

      final compressed = GZipEncoder().encode(textData);
      if (compressed == null) {
        return textData;
      }

      if (kDebugMode) {
        final originalSize = textData.length;
        final compressedSize = compressed.length;
        final compressionRatio = ((originalSize - compressedSize) / originalSize * 100).round();
        debugPrint('✅ Text compressed: $originalSize → $compressedSize bytes ($compressionRatio% reduction)');
      }

      return Uint8List.fromList(compressed);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Text compression error: $e');
      }
      return textData;
    }
  }

  /// Create zip archive dari multiple files
  Future<Uint8List> createZipArchive(Map<String, Uint8List> files) async {
    try {
      if (kDebugMode) {
        debugPrint('🗜️ Creating ZIP archive with ${files.length} files');
      }

      final archive = Archive();
      
      for (final entry in files.entries) {
        final fileName = entry.key;
        final fileData = entry.value;
        
        archive.addFile(ArchiveFile(fileName, fileData.length, fileData));
      }

      final zipData = ZipEncoder().encode(archive);
      if (zipData == null) {
        throw Exception('Failed to create ZIP archive');
      }

      if (kDebugMode) {
        debugPrint('✅ ZIP archive created: ${zipData.length} bytes');
      }

      return Uint8List.fromList(zipData);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ ZIP creation error: $e');
      }
      rethrow;
    }
  }

  /// Process file berdasarkan type (compression, resize, dll)
  Future<FileProcessingResult> processFile({
    required Uint8List fileData,
    required String fileName,
    required String mimeType,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('🔄 Processing file: $fileName ($mimeType)');
      }

      Uint8List processedData = fileData;
      bool isCompressed = false;
      String compressionInfo = '';

      // Process berdasarkan file type
      if (mimeType.startsWith('image/')) {
        // Compress image
        final originalSize = fileData.length;
        processedData = await compressImage(fileData);
        final compressedSize = processedData.length;
        
        if (compressedSize < originalSize) {
          isCompressed = true;
          compressionInfo = 'Image compressed ${(originalSize - compressedSize) ~/ 1024}KB saved';
        }
      }
      else if (mimeType == 'text/plain' || fileName.endsWith('.txt')) {
        // Compress text files
        final originalSize = fileData.length;
        processedData = await compressTextFile(fileData);
        final compressedSize = processedData.length;
        
        if (compressedSize < originalSize) {
          isCompressed = true;
          compressionInfo = 'Text compressed ${(originalSize - compressedSize) ~/ 1024}KB saved';
        }
      }
      else if (mimeType.contains('pdf') || 
               mimeType.contains('document') ||
               fileName.endsWith('.doc') ||
               fileName.endsWith('.docx')) {
        // Documents - no compression (usually already compressed)
        compressionInfo = 'Document file';
      }
      else {
        // Other files - no processing
        compressionInfo = 'Binary file';
      }

      if (kDebugMode) {
        debugPrint('✅ File processing completed: $compressionInfo');
      }

      return FileProcessingResult(
        data: processedData,
        mimeType: mimeType,
        fileName: fileName,
        isCompressed: isCompressed,
        compressionInfo: compressionInfo,
        originalSize: fileData.length,
        processedSize: processedData.length,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ File processing error: $e');
      }
      return FileProcessingResult(
        data: fileData,
        mimeType: mimeType,
        fileName: fileName,
        isCompressed: false,
        compressionInfo: 'Processing failed - using original',
        originalSize: fileData.length,
        processedSize: fileData.length,
      );
    }
  }

  /// Get file info untuk display
  Map<String, dynamic> getFileInfo(String fileName, int fileSize, String mimeType) {
    final fileExtension = fileName.toLowerCase().split('.').last;
    
    // File type categories
    final imageTypes = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'];
    final documentTypes = ['pdf', 'doc', 'docx', 'txt', 'rtf'];
    final videoTypes = ['mp4', 'avi', 'mov', 'wmv', 'flv'];
    final audioTypes = ['mp3', 'wav', 'aac', 'flac'];
    final archiveTypes = ['zip', 'rar', '7z', 'tar', 'gz'];
    
    String fileCategory;
    IconData fileIcon;
    Color fileColor;
    
    if (imageTypes.contains(fileExtension)) {
      fileCategory = 'Image';
      fileIcon = Icons.image;
      fileColor = Colors.green;
    } else if (documentTypes.contains(fileExtension)) {
      fileCategory = 'Document';
      fileIcon = Icons.description;
      fileColor = Colors.blue;
    } else if (videoTypes.contains(fileExtension)) {
      fileCategory = 'Video';
      fileIcon = Icons.videocam;
      fileColor = Colors.red;
    } else if (audioTypes.contains(fileExtension)) {
      fileCategory = 'Audio';
      fileIcon = Icons.audiotrack;
      fileColor = Colors.orange;
    } else if (archiveTypes.contains(fileExtension)) {
      fileCategory = 'Archive';
      fileIcon = Icons.folder_zip;
      fileColor = Colors.purple;
    } else {
      fileCategory = 'File';
      fileIcon = Icons.insert_drive_file;
      fileColor = Colors.grey;
    }
    
    return {
      'category': fileCategory,
      'icon': fileIcon,
      'color': fileColor,
      'extension': fileExtension.toUpperCase(),
      'size_formatted': _formatFileSize(fileSize),
    };
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB"];
    final i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  Future<String> uploadEncryptedFile({
    required Uint8List fileData,
    required String fileName,
    required String chatId,
    required String mimeType,
  }) async {
    if (!isAvailable) {
      throw Exception('Supabase not available');
    }

    try {
      if (kDebugMode) {
        debugPrint('📤 Uploading encrypted file: $fileName');
      }

      final filePath = '${DateTime.now().millisecondsSinceEpoch}_$fileName';
      
      // ✅ Gunakan bucket 'encrypted_files'
      await client.storage
          .from('encrypted_files')
          .uploadBinary(filePath, fileData);

      if (kDebugMode) {
        debugPrint('✅ File uploaded successfully: $filePath');
      }

      return filePath;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ File upload error: $e');
      }
      
      // Fallback ke local storage
      final localFile = await saveFileToLocation(
        data: fileData,
        fileName: fileName,
        locationType: 'temp',
      );
      
      return 'local://${localFile.path}';
    }
  }

  /// Download encrypted file - PERBAIKAN
  Future<Uint8List> downloadEncryptedFile(String filePath) async {
    try {
      if (kDebugMode) {
        debugPrint('📥 Downloading encrypted file: $filePath');
      }

      // Handle local file paths
      if (filePath.startsWith('local://')) {
        final localPath = filePath.replaceFirst('local://', '');
        final file = File(localPath);
        
        if (await file.exists()) {
          final data = await file.readAsBytes();
          if (kDebugMode) {
            debugPrint('✅ Local file downloaded: ${data.length} bytes');
          }
          return data;
        } else {
          if (kDebugMode) {
            debugPrint('❌ Local file not found: $localPath');
          }
          throw Exception('Local file not found: $localPath');
        }
      }

      // Handle Supabase storage paths
      if (!isAvailable) {
        throw Exception('Supabase not available');
      }

      final response = await client.storage
          .from('encrypted_files')
          .download(filePath);

      if (kDebugMode) {
        debugPrint('✅ Supabase file downloaded: ${response.length} bytes');
      }

      return response;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ File download error: $e');
      }
      
      // Return empty bytes instead of throwing to allow debugging
      return Uint8List(0);
    }
  }

  /// Save file message ke database
  Future<Map<String, dynamic>> sendFileMessage({
    required String chatId,
    required String senderId,
    required String filePath,
    required String fileName,
    required int fileSize,
    required String mimeType,
    required String nonce,
    required String authTag,
  }) async {
    final result = await insertData('file_messages', {
      'chat_id': chatId,
      'sender_id': senderId,
      'file_path': filePath,
      'file_name': fileName,
      'file_size': fileSize,
      'mime_type': mimeType,
      'nonce': nonce,
      'auth_tag': authTag,
      'algorithm': 'chacha20-poly1305-hmac-sha512',
      'created_at': DateTime.now().toIso8601String(),
    });

    return result ?? {};
  }

  /// Get file messages untuk chat
  Future<List<Map<String, dynamic>>> getFileMessages(String chatId) async {
    return await fetchData('file_messages', filters: {'chat_id': chatId});
  }

  /// Stream file messages real-time
  Stream<List<Map<String, dynamic>>> subscribeToFileMessages(String chatId) {
    if (!isAvailable) {
      return const Stream.empty();
    }

    return client
        .from('file_messages')
        .stream(primaryKey: ['id'])
        .eq('chat_id', chatId)
        .map(
          (event) => event.map((item) => Map<String, dynamic>.from(item)).toList(),
        );
  }

  /// Delete file message
  Future<void> deleteFileMessage(String messageId, String filePath) async {
    if (!isAvailable) {
      return;
    }

    try {
      await client.from('file_messages').delete().eq('id', messageId);
      
      if (kDebugMode) {
        debugPrint('✅ File message deleted from database: $messageId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error deleting file message: $e');
      }
    }
  }

  // ===============================
  // OTP VERIFICATION METHODS
  // ===============================

  /// Verify OTP code
  Future<bool> verifyEmailOtp(String email, String otpCode) async {
    if (!isAvailable) {
      throw Exception('Supabase not available');
    }

    try {
      if (kDebugMode) {
        debugPrint('🔍 Verifying OTP: $email -> $otpCode');
      }

      final response = await client.auth.verifyOTP(
        email: email,
        token: otpCode,
        type: OtpType.signup,
      );

      if (response.user != null) {
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

  /// Resend OTP verification email
  Future<void> resendVerificationEmail(String email) async {
    if (!isAvailable) {
      throw Exception('Supabase not available');
    }

    try {
      if (kDebugMode) {
        debugPrint('📧 Resending verification email to: $email');
      }

      await client.auth.signUp(
        email: email, 
        password: 'temporary_password_for_resend',
      );

      if (kDebugMode) {
        debugPrint('✅ Verification email resent');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error resending verification email: $e');
      }
      
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

  /// Get user authentication data
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

  /// Sign in user
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

      final userPin = _generateUserPin();
      final userData = {
        'id': userId,
        'email': email.trim(),
        'display_name': displayName.trim(),
        'user_pin': userPin,
        'password_hash': passwordHash,
        'salt': salt,
        'is_verified': false,
        'created_at': DateTime.now().toIso8601String(),
      };

      if (kDebugMode) {
        debugPrint('   💾 Creating user profile with crypto data');
        debugPrint('   📌 Generated PIN: $userPin');
        debugPrint('   📧 OTP email sent to: $email');
      }

      await client
          .from('users')
          .insert(userData)
          .select()
          .single();

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
      }
      return result;

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Sign up with crypto error: $e');
      }
      
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

      if (response.isNotEmpty) {
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

      if (response.isNotEmpty) {
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
      final existingChat = await client
          .from('chats')
          .select()
          .or('and(user1_id.eq.$user1Id,user2_id.eq.$user2Id),and(user1_id.eq.$user2Id,user2_id.eq.$user1Id)')
          .maybeSingle();

      if (existingChat != null) {
        return existingChat['id'];
      }

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
      final pin = (random.nextInt(900000) + 100000).toString();

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
      return '123456';
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
      debugPrint('File Features: Compression + Multiple Types');
      debugPrint('==================================');
    }
  }
}

// Data model untuk file processing result
class FileProcessingResult {
  final Uint8List data;
  final String mimeType;
  final String fileName;
  final bool isCompressed;
  final String compressionInfo;
  final int originalSize;
  final int processedSize;

  FileProcessingResult({
    required this.data,
    required this.mimeType,
    required this.fileName,
    required this.isCompressed,
    required this.compressionInfo,
    required this.originalSize,
    required this.processedSize,
  });

  int get sizeSaved => originalSize - processedSize;
  double get compressionRatio => originalSize > 0 ? (sizeSaved / originalSize * 100) : 0;
}