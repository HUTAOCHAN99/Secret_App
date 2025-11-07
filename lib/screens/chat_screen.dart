// secret_app/lib/screens/chat_screen.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/auth_provider.dart';
import '../services/supabase_service.dart';
import '../services/encryption_service.dart';
import '../services/file_encryption_service.dart';
import 'file_location_modal.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String otherUserName;
  final String otherUserPin;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.otherUserName,
    required this.otherUserPin,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _fileMessages = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _isUploading = false;
  late String _encryptionKey;
  Stream<List<Map<String, dynamic>>>? _messagesStream;
  Stream<List<Map<String, dynamic>>>? _fileMessagesStream;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      debugPrint('💬 ChatScreen initialized for chat: ${widget.chatId}');
      debugPrint('   👤 Other user: ${widget.otherUserName}');
      debugPrint('   📌 Other PIN: ${widget.otherUserPin}');
    }
    
    _initializeChat();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom(instant: true);
    });
  }

  Future<void> _initializeChat() async {
    try {
      _generateEncryptionKey();
      await _loadMessages();
      await _loadFileMessages();
      _setupRealtimeSubscription();
      _setupFileMessagesSubscription();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error initializing chat: $e');
      }
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _generateEncryptionKey() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _encryptionKey = EncryptionService.generateChatKey(
      authProvider.userPin!,
      widget.otherUserPin,
    );
    if (kDebugMode) {
      debugPrint('🔑 Chat encryption key generated');
    }
  }

  Future<void> _loadMessages() async {
    try {
      if (kDebugMode) {
        debugPrint('📥 Loading messages for chat: ${widget.chatId}');
      }
      
      final supabaseService = SupabaseService();
      final encryptedMessages = await supabaseService.getEncryptedMessages(widget.chatId);
      
      if (kDebugMode) {
        debugPrint('🔓 Decrypting ${encryptedMessages.length} messages...');
      }
      
      final List<Map<String, dynamic>> decryptedMessages = [];
      int successCount = 0;
      int failCount = 0;
      
      final encryptionService = EncryptionService();
      
      for (final msg in encryptedMessages) {
        try {
          final decryptedContent = await encryptionService.decryptMessage(
            msg['encrypted_message'] as String,
            msg['iv'] as String,
            _encryptionKey,
          );
          
          decryptedMessages.add({
            'id': msg['id'],
            'sender_id': msg['sender_id'],
            'message': decryptedContent,
            'created_at': msg['created_at'],
          });
          successCount++;
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ Failed to decrypt message ${msg['id']}: $e');
          }
          failCount++;
        }
      }
      
      if (mounted) {
        setState(() {
          _messages = decryptedMessages;
        });
      }
      
      if (kDebugMode) {
        debugPrint('✅ Loaded $successCount messages (failed: $failCount)');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to load messages: $e');
      }
      throw e;
    }
  }

  Future<void> _loadFileMessages() async {
    try {
      if (kDebugMode) {
        debugPrint('📁 Loading file messages for chat: ${widget.chatId}');
      }
      
      final supabaseService = SupabaseService();
      final fileMessages = await supabaseService.getFileMessages(widget.chatId);
      
      if (mounted) {
        setState(() {
          _fileMessages = fileMessages;
          _isLoading = false;
          _hasError = false;
        });
        
        _scrollToBottom(instant: true);
      }
      
      if (kDebugMode) {
        debugPrint('✅ Loaded ${fileMessages.length} file messages');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to load file messages: $e');
      }
      throw e;
    }
  }

  void _setupRealtimeSubscription() {
    try {
      if (kDebugMode) {
        debugPrint('📡 Setting up real-time message subscription...');
      }
      
      final supabaseService = SupabaseService();
      _messagesStream = supabaseService.subscribeToMessages(widget.chatId);
      
      _messagesStream?.listen((List<Map<String, dynamic>> newMessages) {
        if (kDebugMode) {
          debugPrint('🔄 Real-time update: ${newMessages.length} messages in stream');
        }
        
        if (newMessages.isNotEmpty && mounted) {
          _handleRealtimeUpdate(newMessages);
        }
      }, onError: (error) {
        if (kDebugMode) {
          debugPrint('❌ Real-time subscription error: $error');
        }
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error setting up real-time subscription: $e');
      }
    }
  }

  void _setupFileMessagesSubscription() {
    try {
      if (kDebugMode) {
        debugPrint('📁 Setting up file messages subscription...');
      }
      
      final supabaseService = SupabaseService();
      _fileMessagesStream = supabaseService.subscribeToFileMessages(widget.chatId);
      
      _fileMessagesStream?.listen((List<Map<String, dynamic>> newFileMessages) {
        if (kDebugMode) {
          debugPrint('🔄 File messages update: ${newFileMessages.length} files');
        }
        
        if (newFileMessages.isNotEmpty && mounted) {
          _handleFileMessagesUpdate(newFileMessages);
        }
      }, onError: (error) {
        if (kDebugMode) {
          debugPrint('❌ File messages subscription error: $error');
        }
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error setting up file messages subscription: $e');
      }
    }
  }

  Future<void> _handleRealtimeUpdate(List<Map<String, dynamic>> encryptedMessages) async {
    try {
      if (kDebugMode) {
        debugPrint('🔄 Processing real-time update with ${encryptedMessages.length} messages');
      }
      
      final List<Map<String, dynamic>> newDecryptedMessages = [];
      final encryptionService = EncryptionService();
      
      for (final msg in encryptedMessages) {
        if (!_messages.any((existing) => existing['id'] == msg['id'])) {
          try {
            final decryptedContent = await encryptionService.decryptMessage(
              msg['encrypted_message'] as String,
              msg['iv'] as String,
              _encryptionKey,
            );
            
            newDecryptedMessages.add({
              'id': msg['id'],
              'sender_id': msg['sender_id'],
              'message': decryptedContent,
              'created_at': msg['created_at'],
            });
          } catch (e) {
            if (kDebugMode) {
              debugPrint('⚠️ Failed to decrypt real-time message ${msg['id']}: $e');
            }
          }
        }
      }
      
      if (newDecryptedMessages.isNotEmpty && mounted) {
        setState(() {
          _messages.addAll(newDecryptedMessages);
          _messages.sort((a, b) => (a['created_at'] as String).compareTo(b['created_at'] as String));
        });
        
        _scrollToBottom();
        if (kDebugMode) {
          debugPrint('✅ Added ${newDecryptedMessages.length} new messages via real-time');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error handling real-time update: $e');
      }
    }
  }

  void _handleFileMessagesUpdate(List<Map<String, dynamic>> newFileMessages) {
    if (mounted) {
      setState(() {
        for (final fileMsg in newFileMessages) {
          if (!_fileMessages.any((existing) => existing['id'] == fileMsg['id'])) {
            _fileMessages.add(fileMsg);
          }
        }
        _fileMessages.sort((a, b) => (a['created_at'] as String).compareTo(b['created_at'] as String));
      });
      
      _scrollToBottom();
      if (kDebugMode) {
        debugPrint('✅ Added ${newFileMessages.length} new file messages via real-time');
      }
    }
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _isSending) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    try {
      if (kDebugMode) {
        debugPrint('📤 Sending message: "$message"');
      }
      
      setState(() {
        _isSending = true;
      });

      final encryptionService = EncryptionService();
      final encryptionResult = await encryptionService.encryptMessage(message, _encryptionKey);
      
      final supabaseService = SupabaseService();
      await supabaseService.sendEncryptedMessage(
        chatId: widget.chatId,
        senderId: authProvider.user!.id,
        encryptedMessage: encryptionResult['encrypted_message'] as String,
        iv: encryptionResult['iv'] as String,
      );
      
      _messageController.clear();
      
      if (kDebugMode) {
        debugPrint('✅ Message sent and encrypted successfully');
      }
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to send message: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  // ===============================
  // ENHANCED FILE UPLOAD WITH COMPRESSION
  // ===============================

  /// Enhanced file upload dengan compression dan processing
  Future<void> _uploadFileWithCompression() async {
    try {
      final supabaseService = SupabaseService();
      
      // Tampilkan modal pilih lokasi
      final selectedLocation = await showDialog<String>(
        context: context,
        builder: (context) => FileLocationModal(
          fileName: 'file',
          isUpload: true,
        ),
      );

      if (selectedLocation == null) return;

      // Pick file dari device
      final fileResult = await supabaseService.pickFileWithLocation();
      if (fileResult == null || fileResult.files.isEmpty) return;

      final platformFile = fileResult.files.first;
      final fileName = platformFile.name;
      
      // Get file data
      Uint8List? fileData = platformFile.bytes;
      
      // Jika bytes null, coba baca dari path
      if (fileData == null && platformFile.path != null) {
        try {
          final file = File(platformFile.path!);
          fileData = await file.readAsBytes();
        } catch (e) {
          if (kDebugMode) {
            debugPrint('❌ Error reading file from path: $e');
          }
        }
      }

      if (fileData == null) {
        throw Exception('Tidak bisa membaca file data');
      }

      // Get MIME type
      final mimeType = _getMimeType(fileName);

      if (kDebugMode) {
        debugPrint('📁 File selected: $fileName');
        debugPrint('   Type: $mimeType');
        debugPrint('   Size: ${fileData.length} bytes');
      }

      // Check file size limit (100MB)
      if (fileData.length > 100 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('File size terlalu besar. Maksimal 100MB.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      setState(() {
        _isUploading = true;
      });

      // Show processing dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Processing File'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  'Memproses $fileName...',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      }

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final fileEncryption = FileEncryptionService();

      // Process file (compression, resize, dll)
      final processedFile = await supabaseService.processFile(
        fileData: fileData,
        fileName: fileName,
        mimeType: mimeType,
      );

      // Close processing dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (kDebugMode) {
        debugPrint('🔐 Encrypting file: $fileName');
        if (processedFile.isCompressed) {
          debugPrint('   Compression: ${processedFile.compressionInfo}');
          debugPrint('   Size reduction: ${processedFile.compressionRatio.toStringAsFixed(1)}%');
        }
      }

      // Simpan file sementara untuk encryption
      final tempFile = await supabaseService.saveFileToLocation(
        data: processedFile.data,
        fileName: 'temp_$fileName',
        locationType: 'temp',
      );

      // Encrypt file
      final encryptionResult = await fileEncryption.encryptFile(
        file: tempFile,
        encryptionKey: _encryptionKey,
        chatId: widget.chatId,
        fileName: fileName,
      );

      if (kDebugMode) {
        debugPrint('📤 Uploading encrypted file...');
      }

      // Upload ke Supabase
      final uploadedFilePath = await supabaseService.uploadEncryptedFile(
        fileData: encryptionResult.encryptedData,
        fileName: fileName,
        chatId: widget.chatId,
        mimeType: processedFile.mimeType,
      );

      if (kDebugMode) {
        debugPrint('💾 Saving file message to database...');
      }

      // Get file info untuk display
      final fileInfo = supabaseService.getFileInfo(
        fileName, 
        processedFile.data.length, 
        processedFile.mimeType
      );

      // Save file message ke database
      await supabaseService.sendFileMessage(
        chatId: widget.chatId,
        senderId: authProvider.user!.id,
        filePath: uploadedFilePath,
        fileName: fileName,
        fileSize: processedFile.data.length,
        mimeType: processedFile.mimeType,
        nonce: base64.encode(encryptionResult.nonce),
        authTag: base64.encode(encryptionResult.authTag),
      );

      // Hapus file temp
      await tempFile.delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('File "$fileName" berhasil diupload'),
                if (processedFile.isCompressed)
                  Text(
                    '✅ ${processedFile.compressionInfo}',
                    style: const TextStyle(fontSize: 12),
                  ),
              ],
            ),
            backgroundColor: Colors.green,
          ),
        );
      }

    } catch (e) {
      // Close processing dialog jika ada error
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      
      if (kDebugMode) {
        debugPrint('❌ File upload error: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal upload file: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  /// Upload multiple files sebagai ZIP
  Future<void> _uploadMultipleFiles() async {
    try {
      final supabaseService = SupabaseService();
      
      // Pick multiple files
      final fileResult = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: true,
        withData: true,
      );

      if (fileResult == null || fileResult.files.isEmpty) return;

      // Check total size
      final totalSize = fileResult.files.fold<int>(0, (sum, file) => sum + (file.size ?? 0));
      if (totalSize > 50 * 1024 * 1024) { // 50MB limit untuk multiple files
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Total file size terlalu besar. Maksimal 50MB.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      setState(() {
        _isUploading = true;
      });

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final fileEncryption = FileEncryptionService();

      // Process semua files
      final filesToZip = <String, Uint8List>{};
      
      for (final platformFile in fileResult.files) {
        if (platformFile.bytes != null) {
          final processedFile = await supabaseService.processFile(
            fileData: platformFile.bytes!,
            fileName: platformFile.name,
            mimeType: _getMimeType(platformFile.name),
          );
          filesToZip[platformFile.name] = processedFile.data;
        }
      }

      if (filesToZip.isEmpty) {
        throw Exception('Tidak ada file yang bisa diproses');
      }

      // Create ZIP archive
      final zipData = await supabaseService.createZipArchive(filesToZip);
      final zipFileName = 'files_${DateTime.now().millisecondsSinceEpoch}.zip';

      // Simpan ZIP temporary
      final tempFile = await supabaseService.saveFileToLocation(
        data: zipData,
        fileName: zipFileName,
        locationType: 'temp',
      );

      // Encrypt ZIP file
      final encryptionResult = await fileEncryption.encryptFile(
        file: tempFile,
        encryptionKey: _encryptionKey,
        chatId: widget.chatId,
        fileName: zipFileName,
      );

      // Upload ZIP
      final uploadedFilePath = await supabaseService.uploadEncryptedFile(
        fileData: encryptionResult.encryptedData,
        fileName: zipFileName,
        chatId: widget.chatId,
        mimeType: 'application/zip',
      );

      // Save to database
      await supabaseService.sendFileMessage(
        chatId: widget.chatId,
        senderId: authProvider.user!.id,
        filePath: uploadedFilePath,
        fileName: zipFileName,
        fileSize: zipData.length,
        mimeType: 'application/zip',
        nonce: base64.encode(encryptionResult.nonce),
        authTag: base64.encode(encryptionResult.authTag),
      );

      // Cleanup
      await tempFile.delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${filesToZip.length} files berhasil diupload sebagai ZIP'),
            backgroundColor: Colors.green,
          ),
        );
      }

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Multiple files upload error: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal upload multiple files: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  /// Upload file demo
  Future<void> _uploadDemoFile() async {
    try {
      // Untuk demo, buat file temporary
      final tempDir = Directory.systemTemp;
      final demoFile = File('${tempDir.path}/demo_file_${DateTime.now().millisecondsSinceEpoch}.txt');
      await demoFile.writeAsString('This is a demo encrypted file content. Created at: ${DateTime.now()}\n\n'
          'Chat: ${widget.chatId}\n'
          'With: ${widget.otherUserName}\n'
          'Encrypted with: ChaCha20-Poly1305 + HMAC-SHA512');

      final fileName = 'demo_file.txt';
      final fileSize = await demoFile.length();

      // Check file size limit (50MB)
      if (fileSize > 50 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('File size too large. Maximum 50MB.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      setState(() {
        _isUploading = true;
      });

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final supabaseService = SupabaseService();
      final fileEncryption = FileEncryptionService();

      if (kDebugMode) {
        debugPrint('🔐 Starting file encryption...');
      }

      // Encrypt file
      final encryptionResult = await fileEncryption.encryptFile(
        file: demoFile,
        encryptionKey: _encryptionKey,
        chatId: widget.chatId,
        fileName: fileName,
      );

      if (kDebugMode) {
        debugPrint('📤 Uploading encrypted file...');
      }

      // Upload encrypted file
      final uploadedFilePath = await supabaseService.uploadEncryptedFile(
        fileData: encryptionResult.encryptedData,
        fileName: fileName,
        chatId: widget.chatId,
        mimeType: encryptionResult.mimeType,
      );

      if (kDebugMode) {
        debugPrint('💾 Saving file message to database...');
      }

      // Save file message ke database
      await supabaseService.sendFileMessage(
        chatId: widget.chatId,
        senderId: authProvider.user!.id,
        filePath: uploadedFilePath,
        fileName: fileName,
        fileSize: fileSize,
        mimeType: encryptionResult.mimeType,
        nonce: base64.encode(encryptionResult.nonce),
        authTag: base64.encode(encryptionResult.authTag),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File uploaded successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ File upload error: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload file: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  /// Download file dengan pilih lokasi simpan
  Future<void> _downloadFileWithLocation(Map<String, dynamic> fileMessage) async {
    try {
      final supabaseService = SupabaseService();
      final fileName = fileMessage['file_name'] as String;

      // Tampilkan modal pilih lokasi simpan
      final selectedLocation = await showDialog<String>(
        context: context,
        builder: (context) => FileLocationModal(
          fileName: fileName,
          isUpload: false,
        ),
      );

      if (selectedLocation == null) return;

      setState(() {
        _isUploading = true;
      });

      // Download dan simpan file
      final savedFile = await supabaseService.downloadAndSaveFile(
        filePath: fileMessage['file_path'] as String,
        fileName: fileName,
        locationType: selectedLocation,
      );

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('File Downloaded'),
            content: Text(
              'File "$fileName" berhasil disimpan di:\n${savedFile.path}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
              TextButton(
                onPressed: () {
                  // TODO: Buka file location di file manager
                  Navigator.pop(context);
                },
                child: const Text('Buka Lokasi'),
              ),
            ],
          ),
        );
      }

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ File download error: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal download file: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  /// Upload file method
  Future<void> _uploadFile() async {
    try {
      await _uploadFileWithCompression();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Upload error: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Download file method
  Future<void> _downloadFile(Map<String, dynamic> fileMessage) async {
    try {
      await _downloadFileWithLocation(fileMessage);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Download error: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ===============================
  // ENHANCED FILE MESSAGE BUBBLE
  // ===============================

  /// Enhanced file message bubble dengan file info
  Widget _buildEnhancedFileMessage(Map<String, dynamic> fileMessage, bool isMe) {
    final fileName = fileMessage['file_name'] as String;
    final fileSize = fileMessage['file_size'] as int;
    final mimeType = fileMessage['mime_type'] as String;

    final supabaseService = SupabaseService();
    final fileInfo = supabaseService.getFileInfo(fileName, fileSize, mimeType);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 16.0),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe) ...[
            Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.only(right: 8.0),
              decoration: BoxDecoration(
                color: Colors.grey[400],
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person, color: Colors.white, size: 18),
            ),
          ],
          Flexible(
            child: GestureDetector(
              onTap: () => _downloadFile(fileMessage),
              child: Container(
                padding: const EdgeInsets.all(12.0),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                decoration: BoxDecoration(
                  color: isMe ? Theme.of(context).colorScheme.primary : Colors.grey[100],
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16.0),
                    topRight: const Radius.circular(16.0),
                    bottomLeft: isMe ? const Radius.circular(16.0) : const Radius.circular(4.0),
                    bottomRight: isMe ? const Radius.circular(4.0) : const Radius.circular(16.0),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4.0,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        color: fileInfo['color'].withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(fileInfo['icon'], color: fileInfo['color'], size: 20),
                    ),
                    const SizedBox(width: 12.0),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fileName,
                            style: TextStyle(
                              color: isMe ? Colors.white : Colors.grey[800],
                              fontWeight: FontWeight.w600,
                              fontSize: 14.0,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4.0),
                          Row(
                            children: [
                              Text(
                                fileInfo['category'],
                                style: TextStyle(
                                  color: isMe ? Colors.white70 : Colors.grey[600],
                                  fontSize: 12.0,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '•',
                                style: TextStyle(
                                  color: isMe ? Colors.white70 : Colors.grey[500],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                fileInfo['size_formatted'],
                                style: TextStyle(
                                  color: isMe ? Colors.white70 : Colors.grey[600],
                                  fontSize: 12.0,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4.0),
                          Row(
                            children: [
                              Icon(
                                Icons.lock_outline,
                                size: 12,
                                color: isMe ? Colors.white70 : Colors.grey[500],
                              ),
                              const SizedBox(width: 4.0),
                              Text(
                                'Encrypted • ${fileInfo['extension']} • Tap to download',
                                style: TextStyle(
                                  color: isMe ? Colors.white70 : Colors.grey[500],
                                  fontSize: 10.0,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (isMe) ...[
            Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.only(left: 8.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person, color: Colors.white, size: 18),
            ),
          ],
        ],
      ),
    );
  }

  // ===============================
  // MESSAGE BUBBLE WIDGETS
  // ===============================

  Widget _buildMessageBubble(Map<String, dynamic> message, bool isMe) {
    final messageText = message['message'] as String;
    final time = _formatTime(message['created_at'] as String);
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 16.0),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.only(right: 8.0),
              decoration: BoxDecoration(
                color: Colors.grey[400],
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person,
                color: Colors.white,
                size: 18,
              ),
            ),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12.0),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              decoration: BoxDecoration(
                color: isMe 
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey[100],
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16.0),
                  topRight: const Radius.circular(16.0),
                  bottomLeft: isMe ? const Radius.circular(16.0) : const Radius.circular(4.0),
                  bottomRight: isMe ? const Radius.circular(4.0) : const Radius.circular(16.0),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4.0,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    messageText,
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.grey[800],
                      fontSize: 16.0,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4.0),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        time,
                        style: TextStyle(
                          color: isMe ? Colors.white70 : Colors.grey[500],
                          fontSize: 11.0,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 4.0),
                        Icon(
                          Icons.done_all,
                          size: 12,
                          color: Colors.white70,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (isMe) ...[
            Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.only(left: 8.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person,
                color: Colors.white,
                size: 18,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ===============================
  // HELPER METHODS
  // ===============================

  String _formatTime(String dateTimeString) {
    try {
      final dateTime = DateTime.parse(dateTimeString).toLocal();
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '--:--';
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB"];
    final i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  // Helper method untuk get MIME type
  String _getMimeType(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    
    final mimeTypes = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'bmp': 'image/bmp',
      'webp': 'image/webp',
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'txt': 'text/plain',
      'mp4': 'video/mp4',
      'avi': 'video/x-msvideo',
      'mov': 'video/quicktime',
      'mp3': 'audio/mpeg',
      'wav': 'audio/wav',
      'zip': 'application/zip',
      'rar': 'application/x-rar-compressed',
    };
    
    return mimeTypes[extension] ?? 'application/octet-stream';
  }

  Widget _buildInputArea() {
    return Padding(
      padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 8.0, bottom: 16.0),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(color: Colors.grey[300]!, width: 1.0),
          ),
        ),
        child: Column(
          children: [
            if (_isUploading)
              LinearProgressIndicator(
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.attach_file,
                    color: _isUploading ? Colors.grey[400] : Colors.grey[600],
                  ),
                  onSelected: (value) {
                    if (value == 'single_file') {
                      _uploadFileWithCompression();
                    } else if (value == 'multiple_files') {
                      _uploadMultipleFiles();
                    } else if (value == 'demo_file') {
                      _uploadDemoFile();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'single_file',
                      child: Row(
                        children: [
                          Icon(Icons.file_upload, size: 20),
                          SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Upload File'),
                              Text(
                                'Image, PDF, Text, dll',
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'multiple_files',
                      child: Row(
                        children: [
                          Icon(Icons.folder_zip, size: 20),
                          SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Upload Multiple Files'),
                              Text(
                                'Akan dikompresi menjadi ZIP',
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'demo_file',
                      child: Row(
                        children: [
                          Icon(Icons.code, size: 20),
                          SizedBox(width: 8),
                          Text('Upload File Demo'),
                        ],
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: Icon(
                    Icons.emoji_emotions_outlined,
                    color: Colors.grey[600],
                  ),
                  onPressed: () {
                    _showEmojiPicker();
                  },
                ),
                const SizedBox(width: 4.0),
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 100.0),
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: 'Type a secure message...',
                        hintStyle: TextStyle(color: Colors.grey[600]),
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24.0),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 12.0,
                        ),
                        suffixIcon: _isSending
                            ? const Padding(
                                padding: EdgeInsets.all(12.0),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : null,
                      ),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                ),
                const SizedBox(width: 8.0),
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _messageController.text.trim().isEmpty || _isSending
                        ? Colors.grey[300]
                        : Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: _isSending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Icon(
                            Icons.send_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                    onPressed: _messageController.text.trim().isEmpty || _isSending 
                        ? null 
                        : _sendMessage,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showEmojiPicker() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Emoji picker coming soon!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.chat_bubble_outline,
                  size: 48,
                  color: Colors.grey[400],
                ),
              ),
              const SizedBox(height: 24.0),
              Text(
                'No messages yet',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 12.0),
              Text(
                'Start a secure conversation with ${widget.otherUserName}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[500],
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24.0),
              Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(12.0),
                  border: Border.all(color: Colors.blue[100]!),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.lock_outline,
                      color: Colors.blue[600],
                      size: 20,
                    ),
                    const SizedBox(width: 12.0),
                    Expanded(
                      child: Text(
                        'All messages are end-to-end encrypted',
                        style: TextStyle(
                          color: Colors.blue[800],
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageList() {
    final authProvider = Provider.of<AuthProvider>(context);
    final allMessages = [..._messages, ..._fileMessages];
    
    allMessages.sort((a, b) {
      final timeA = DateTime.parse(a['created_at'] ?? '2000-01-01');
      final timeB = DateTime.parse(b['created_at'] ?? '2000-01-01');
      return timeA.compareTo(timeB);
    });

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
      itemCount: allMessages.length,
      itemBuilder: (context, index) {
        final message = allMessages[index];
        
        if (message.containsKey('file_path')) {
          final isMe = message['sender_id'] == authProvider.user!.id;
          return _buildEnhancedFileMessage(message, isMe);
        } else {
          final isMe = message['sender_id'] == authProvider.user!.id;
          return _buildMessageBubble(message, isMe);
        }
      },
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16.0),
          Text(
            'Loading secure messages...',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: Colors.grey[700]),
            ),
          ),
        ],
      ),
    );
  }

  void _scrollToBottom({bool instant = false}) {
    if (_scrollController.hasClients) {
      if (instant) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      } else {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.otherUserName,
              style: const TextStyle(
                fontSize: 16.0,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              'PIN: ${widget.otherUserPin}',
              style: TextStyle(
                fontSize: 12.0,
                fontWeight: FontWeight.normal,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.security,
              color: Theme.of(context).colorScheme.primary,
            ),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Row(
                    children: [
                      Icon(Icons.security, size: 20),
                      SizedBox(width: 8),
                      Text('Chat Security Info'),
                    ],
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoRow('Chat ID', widget.chatId),
                      _buildInfoRow('Other User', widget.otherUserName),
                      _buildInfoRow('Other PIN', widget.otherUserPin),
                      _buildInfoRow('My PIN', authProvider.userPin ?? 'Unknown'),
                      _buildInfoRow('Total Messages', _messages.length.toString()),
                      _buildInfoRow('Total Files', _fileMessages.length.toString()),
                      _buildInfoRow('Text Encryption', 'AES-256-CBC'),
                      _buildInfoRow('File Encryption', 'ChaCha20-Poly1305 + HMAC-SHA512'),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.verified, color: Colors.green, size: 16),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'End-to-end encrypted',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        bottom: true,
        child: Column(
          children: [
            if (_hasError)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12.0),
                color: Colors.red[50],
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 8.0),
                    Expanded(
                      child: Text(
                        _errorMessage,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.red),
                      onPressed: _initializeChat,
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _isLoading
                  ? _buildLoading()
                  : _messages.isEmpty && _fileMessages.isEmpty
                      ? _buildEmptyState()
                      : _buildMessageList(),
            ),
            _buildInputArea(),
          ],
        ),
      ),
    );
  }
}