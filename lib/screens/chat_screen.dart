// secret_app/lib/screens/chat_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/auth_provider.dart';
import '../services/supabase_service.dart';
import '../services/encryption_service.dart';
import '../services/file_encryption_service.dart';
import 'file_location_modal.dart';
import 'file_decryption_modal.dart';
import 'steganography_modal.dart';

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
  StreamSubscription<List<Map<String, dynamic>>>? _messageSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _fileMessageSubscription;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      debugPrint('💬 ChatScreen initialized for chat: ${widget.chatId}');
      debugPrint('   👤 Other user: ${widget.otherUserName}');
      debugPrint('   📌 Other PIN: ${widget.otherUserPin}');
    }

    _initializeChat();

    // Delay scroll untuk memastikan data sudah loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _scrollToBottom(instant: true);
        }
      });
    });
  }

  Future<void> _initializeChat() async {
    try {
      _generateEncryptionKey();
      await _loadMessages();
      await _loadFileMessages();
      _setupRealtimeSubscription();
      _setupFileMessagesSubscription();

      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = false;
        });
      }
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
      debugPrint('   My PIN: ${authProvider.userPin}');
      debugPrint('   Other PIN: ${widget.otherUserPin}');
      debugPrint('   Generated Key: $_encryptionKey');
      debugPrint('   Key length: ${_encryptionKey.length}');
    }
  }

  Future<void> _loadMessages() async {
    try {
      if (kDebugMode) {
        debugPrint('📥 Loading messages for chat: ${widget.chatId}');
      }

      final supabaseService = SupabaseService();
      final encryptedMessages =
          await supabaseService.getEncryptedMessages(widget.chatId);

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
      rethrow;
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
        });
      }

      if (kDebugMode) {
        debugPrint('✅ Loaded ${fileMessages.length} file messages');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to load file messages: $e');
      }
      rethrow;
    }
  }

  void _setupRealtimeSubscription() {
    try {
      if (kDebugMode) {
        debugPrint('📡 Setting up real-time message subscription...');
      }

      final supabaseService = SupabaseService();
      _messagesStream = supabaseService.subscribeToMessages(widget.chatId);

      // Cancel existing subscription jika ada
      _messageSubscription?.cancel();

      _messageSubscription =
          _messagesStream?.listen((List<Map<String, dynamic>> newMessages) {
        if (kDebugMode) {
          debugPrint('🔄 Real-time update: ${newMessages.length} new messages');
        }

        if (mounted) {
          // Paksa rebuild dengan setState
          setState(() {
            _handleRealtimeUpdate(newMessages);
          });
        }
      }, onError: (error) {
        if (kDebugMode) {
          debugPrint('❌ Real-time subscription error: $error');
        }
        // Coba setup ulang subscription
        _retrySubscription();
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error setting up real-time subscription: $e');
      }
      _retrySubscription();
    }
  }

  // Method untuk retry subscription
  void _retrySubscription() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        if (kDebugMode) {
          debugPrint('🔄 Retrying real-time subscription...');
        }
        _setupRealtimeSubscription();
      }
    });
  }

  void _setupFileMessagesSubscription() {
    try {
      if (kDebugMode) {
        debugPrint('📁 Setting up file messages subscription...');
      }

      final supabaseService = SupabaseService();
      _fileMessagesStream =
          supabaseService.subscribeToFileMessages(widget.chatId);

      // Cancel existing subscription jika ada
      _fileMessageSubscription?.cancel();

      _fileMessageSubscription = _fileMessagesStream?.listen(
          (List<Map<String, dynamic>> newFileMessages) {
        if (kDebugMode) {
          debugPrint(
              '🔄 File messages update: ${newFileMessages.length} files');
        }

        if (mounted) {
          setState(() {
            _handleFileMessagesUpdate(newFileMessages);
          });
        }
      }, onError: (error) {
        if (kDebugMode) {
          debugPrint('❌ File messages subscription error: $error');
        }
        _retryFileSubscription();
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error setting up file messages subscription: $e');
      }
      _retryFileSubscription();
    }
  }

  void _retryFileSubscription() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        _setupFileMessagesSubscription();
      }
    });
  }

  Future<void> _handleRealtimeUpdate(
      List<Map<String, dynamic>> encryptedMessages) async {
    try {
      if (kDebugMode) {
        debugPrint(
            '🔄 Processing ${encryptedMessages.length} real-time messages');
      }

      final List<Map<String, dynamic>> newDecryptedMessages = [];
      final encryptionService = EncryptionService();
      bool hasNewMessages = false;

      for (final msg in encryptedMessages) {
        // Cek apakah message sudah ada
        final messageExists =
            _messages.any((existing) => existing['id'] == msg['id']);

        if (!messageExists) {
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
            hasNewMessages = true;

            if (kDebugMode) {
              debugPrint('✅ Decrypted new message: ${msg['id']}');
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('⚠️ Failed to decrypt message ${msg['id']}: $e');
            }
          }
        }
      }

      if (hasNewMessages && mounted) {
        setState(() {
          _messages.addAll(newDecryptedMessages);
          _messages.sort((a, b) =>
              (a['created_at'] as String).compareTo(b['created_at'] as String));
        });

        _scrollToBottom();

        if (kDebugMode) {
          debugPrint('✅ Added ${newDecryptedMessages.length} new messages');
          debugPrint('📊 Total messages now: ${_messages.length}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error handling real-time update: $e');
      }
    }
  }

  void _handleFileMessagesUpdate(List<Map<String, dynamic>> newFileMessages) {
    try {
      bool hasNewFiles = false;

      for (final fileMsg in newFileMessages) {
        if (!_fileMessages.any((existing) => existing['id'] == fileMsg['id'])) {
          _fileMessages.add(fileMsg);
          hasNewFiles = true;

          if (kDebugMode) {
            debugPrint('✅ Added new file message: ${fileMsg['id']}');
          }
        }
      }

      if (hasNewFiles && mounted) {
        setState(() {
          _fileMessages.sort((a, b) =>
              (a['created_at'] as String).compareTo(b['created_at'] as String));
        });

        _scrollToBottom();

        if (kDebugMode) {
          debugPrint('✅ Added ${newFileMessages.length} new file messages');
          debugPrint('📊 Total file messages now: ${_fileMessages.length}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error handling file messages update: $e');
      }
    }
  }

  // Tambahkan method untuk manual refresh
  Future<void> _manualRefresh() async {
    try {
      if (kDebugMode) {
        debugPrint('🔄 Manual refresh triggered');
      }

      setState(() {
        _isLoading = true;
      });

      await _loadMessages();
      await _loadFileMessages();

      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = false;
        });
      }

      if (kDebugMode) {
        debugPrint('✅ Manual refresh completed');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = 'Refresh failed: ${e.toString()}';
        });
      }
    }
  }

  // ===============================
  // STEGANOGRAPHY FEATURE
  // ===============================

  void _showSteganographyModal() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SteganographyModal(
          chatId: widget.chatId,
          encryptionKey: _encryptionKey,
        ),
      ),
    );
  }

  // ===============================
  // COPY MESSAGE FEATURES
  // ===============================

  /// Copy message text to clipboard
  void _copyMessageToClipboard(String messageText) {
    try {
      Clipboard.setData(ClipboardData(text: messageText));

      // Show success feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Pesan disalin ke clipboard'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
            ),
          ),
        );
      }

      if (kDebugMode) {
        debugPrint('📋 Message copied to clipboard: "$messageText"');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error copying message: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menyalin pesan: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Copy file info to clipboard
  void _copyFileInfoToClipboard(Map<String, dynamic> fileMessage) {
    try {
      final fileName = fileMessage['file_name'] as String;
      final fileSize = fileMessage['file_size'] as int;
      final mimeType = fileMessage['mime_type'] as String;
      final createdAt = fileMessage['created_at'] as String;

      final supabaseService = SupabaseService();
      final fileInfo =
          supabaseService.getFileInfo(fileName, fileSize, mimeType);

      final fileInfoText = '''
File Information:
📄 Name: $fileName
📁 Type: ${fileInfo['category']}
🔤 Extension: ${fileInfo['extension']}
📊 Size: ${fileInfo['size_formatted']}
🎯 MIME: $mimeType
🕒 Created: ${_formatDateTime(createdAt)}
''';

      Clipboard.setData(ClipboardData(text: fileInfoText));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Info file disalin ke clipboard'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      if (kDebugMode) {
        debugPrint('📋 File info copied to clipboard');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error copying file info: $e');
      }
    }
  }

  /// Show context menu for text messages
  void _showMessageContextMenu(Map<String, dynamic> message, bool isMe) {
    final messageText = message['message'] as String;

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.content_copy, color: Colors.blue),
              title: const Text('Salin Pesan'),
              subtitle: Text(
                messageText.length > 50
                    ? '${messageText.substring(0, 50)}...'
                    : messageText,
                style: const TextStyle(fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(context);
                _copyMessageToClipboard(messageText);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share, color: Colors.green),
              title: const Text('Bagikan Pesan'),
              onTap: () {
                Navigator.pop(context);
                _shareMessage(messageText);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info, color: Colors.grey),
              title: const Text('Info Pesan'),
              onTap: () {
                Navigator.pop(context);
                _showMessageInfo(message);
              },
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Batal'),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// Show context menu for file messages
  void _showFileContextMenu(Map<String, dynamic> fileMessage, bool isMe) {
    final fileName = fileMessage['file_name'] as String;

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.content_copy, color: Colors.blue),
              title: const Text('Salin Info File'),
              subtitle: const Text('Salin detail informasi file'),
              onTap: () {
                Navigator.pop(context);
                _copyFileInfoToClipboard(fileMessage);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download, color: Colors.green),
              title: const Text('Download File (Terenkripsi)'),
              subtitle: const Text('Simpan file dalam bentuk terenkripsi'),
              onTap: () {
                Navigator.pop(context);
                _downloadEncryptedFile(fileMessage); // METHOD YANG DIPERBAIKI
              },
            ),
            ListTile(
              leading: Icon(
                isMe ? Icons.verified_user : Icons.lock_open,
                color: isMe ? Colors.green : Colors.blue,
              ),
              title: Text(
                  isMe ? 'Dekripsi (Owner Access)' : 'Dekripsi (Manual Key)'),
              onTap: () {
                Navigator.pop(context);
                _decryptFile(fileMessage);
              },
            ),
            if (isMe)
              ListTile(
                leading: const Icon(Icons.vpn_key, color: Colors.orange),
                title: const Text('Lihat & Bagikan Kunci'),
                onTap: () {
                  Navigator.pop(context);
                  _showDecryptionKey(fileMessage);
                },
              ),
            if (!isMe)
              ListTile(
                leading: const Icon(Icons.vpn_key, color: Colors.orange),
                title: const Text('Minta Kunci Dekripsi'),
                onTap: () {
                  Navigator.pop(context);
                  _requestDecryptionKey(fileMessage);
                },
              ),
            ListTile(
              leading: const Icon(Icons.info, color: Colors.grey),
              title: const Text('Info File Lengkap'),
              onTap: () {
                Navigator.pop(context);
                _showFileInfo(fileMessage);
              },
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Batal'),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// Share message using native share dialog
  void _shareMessage(String messageText) {
    try {
      // For web, we'll use a fallback since Share plugin might not work
      if (kIsWeb) {
        _copyMessageToClipboard(messageText);
        return;
      }

      // For mobile, use the share functionality
      // You might want to add the share_plus package for this
      // Add to pubspec.yaml: share_plus: ^7.0.1
      // import 'package:share_plus/share_plus.dart';

      // For now, we'll use copy to clipboard as fallback
      _copyMessageToClipboard(messageText);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pesan disalin untuk dibagikan'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error sharing message: $e');
      }
      _copyMessageToClipboard(messageText);
    }
  }

  /// Show detailed message info
  void _showMessageInfo(Map<String, dynamic> message) {
    final messageText = message['message'] as String;
    final messageId = message['id'] as String;
    final senderId = message['sender_id'] as String;
    final createdAt = message['created_at'] as String;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final isMe = senderId == authProvider.user!.id;

    final messageLength = messageText.length;
    final wordCount = messageText.split(' ').length;
    final lineCount = messageText.split('\n').length;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Info Pesan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('ID Pesan', messageId),
            _buildInfoRow('Pengirim', isMe ? 'Anda' : widget.otherUserName),
            _buildInfoRow('Waktu', _formatDateTime(createdAt)),
            _buildInfoRow('Panjang Teks', '$messageLength karakter'),
            _buildInfoRow('Jumlah Kata', '$wordCount kata'),
            _buildInfoRow('Jumlah Baris', '$lineCount baris'),
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
                      'Pesan terenkripsi end-to-end',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 12,
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
            child: const Text('Tutup'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _copyMessageToClipboard(messageText);
            },
            child: const Text('Salin Pesan'),
          ),
        ],
      ),
    );
  }

  // ===============================
  // DOWNLOAD ENCRYPTED FILE - METHOD YANG DIPERBAIKI
  // ===============================

  /// Download file terenkripsi dengan pilihan lokasi - METHOD BARU
  Future<void> _downloadEncryptedFile(Map<String, dynamic> fileMessage) async {
    try {
      final fileName = fileMessage['file_name'] as String;
      final filePath = fileMessage['file_path'] as String;

      if (kDebugMode) {
        debugPrint('📥 Starting encrypted file download...');
        debugPrint('   File: $fileName');
        debugPrint('   Path: $filePath');
      }

      setState(() {
        _isUploading = true;
      });

      // Tampilkan dialog pemilihan lokasi - PERBAIKAN: Gunakan await yang benar
      final selectedLocation = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => FileLocationModal(
          fileName: fileName,
          isUpload: false,
        ),
      );

      // Debug: Print selected location
      if (kDebugMode) {
        debugPrint('   Selected location: $selectedLocation');
      }

      if (selectedLocation == null) {
        if (kDebugMode) {
          debugPrint('   User cancelled location selection');
        }
        setState(() {
          _isUploading = false;
        });
        return;
      }

      final locationType = selectedLocation['type'] as String? ?? 'downloads';
      final locationName =
          selectedLocation['name'] as String? ?? 'Unknown Location';

      if (kDebugMode) {
        debugPrint('   Selected location type: $locationType');
        debugPrint('   Selected location name: $locationName');
      }

      final supabaseService = SupabaseService();

      // Download dan simpan file terenkripsi
      if (kDebugMode) {
        debugPrint('   Starting file download process...');
      }

      final savedFile = await supabaseService.downloadEncryptedFileToStorage(
        filePath: filePath,
        fileName: fileName,
        locationType: locationType,
      );

      if (kDebugMode) {
        debugPrint('   File saved successfully: ${savedFile.path}');
        debugPrint('   File exists: ${await savedFile.exists()}');
      }

      if (mounted) {
        setState(() {
          _isUploading = false;
        });

        // Tampilkan konfirmasi sukses
        _showDownloadSuccessDialog(savedFile, fileName, locationName);
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ Encrypted file download error: $e');
        debugPrint('Stack trace: $stackTrace');
      }

      if (mounted) {
        setState(() {
          _isUploading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal download file: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  /// Tampilkan dialog sukses download - METHOD BARU
  void _showDownloadSuccessDialog(
      File? savedFile, String fileName, String locationName) {
    // Cek jika file null
    if (savedFile == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('File berhasil didownload tetapi path tidak tersedia'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.download_done, color: Colors.green),
            SizedBox(width: 8),
            Text('File Downloaded'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'File "$fileName" berhasil disimpan di:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '📍 $locationName',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    savedFile.path,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'Monospace',
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.security, size: 16, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'File masih dalam bentuk terenkripsi. Gunakan fitur dekripsi untuk membuka file.',
                      style: TextStyle(fontSize: 12),
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
            child: const Text('Tutup'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _copyFileInfoToClipboard({
                'file_name': fileName,
                'file_path': savedFile.path,
                'file_size': savedFile.lengthSync(),
                'mime_type': 'application/octet-stream',
                'created_at': DateTime.now().toIso8601String(),
              });
            },
            child: const Text('Salin Info'),
          ),
        ],
      ),
    );
  }

  // ===============================
  // FILE DECRYPTION METHODS
  // ===============================

  /// Decrypt file dengan akses berbeda untuk owner dan receiver
  Future<void> _decryptFile(Map<String, dynamic> fileMessage) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final isOwner = fileMessage['sender_id'] == authProvider.user!.id;

      final fileName = fileMessage['file_name'] as String;
      final filePath = fileMessage['file_path'] as String;

      if (kDebugMode) {
        debugPrint('🔓 Starting file decryption process...');
        debugPrint('   File: $fileName');
        debugPrint('   Path: $filePath');
        debugPrint('   Chat ID: ${widget.chatId}');
        debugPrint('   Is Owner: $isOwner');
      }

      // Download file terenkripsi
      final supabaseService = SupabaseService();
      final encryptedData =
          await supabaseService.downloadEncryptedFile(filePath);

      if (encryptedData.isEmpty) {
        throw Exception('Tidak dapat mengunduh file atau file kosong');
      }

      if (kDebugMode) {
        debugPrint(
            '   Downloaded encrypted data: ${encryptedData.length} bytes');
      }

      // Tampilkan modal dengan konfigurasi yang sesuai
      if (mounted) {
        final result = await showDialog(
          context: context,
          builder: (context) => FileDecryptionModal(
            fileName: fileName,
            encryptedData: encryptedData,
            defaultKey:
                isOwner ? _encryptionKey : '', // Berikan kunci untuk owner
            nonce: base64.decode(fileMessage['nonce'] as String),
            authTag: base64.decode(fileMessage['auth_tag'] as String),
            chatId: widget.chatId,
            requireManualKey: !isOwner, // Hanya receiver yang butuh manual key
            isOwner: isOwner, // Tandai apakah user adalah owner
          ),
        );

        if (result == true && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isOwner
                  ? 'File berhasil didekripsi menggunakan kunci Anda'
                  : 'File berhasil didekripsi menggunakan kunci manual'),
              backgroundColor: Colors.green,
            ),
          );
        } else if (result == false && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isOwner
                  ? 'Dekripsi dibatalkan'
                  : 'Dekripsi dibatalkan atau kunci salah'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ File decryption error: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mendekripsi file: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Method untuk meminta kunci dekripsi dari pengirim
  void _requestDecryptionKey(Map<String, dynamic> fileMessage) {
    final fileName = fileMessage['file_name'] as String;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.vpn_key, color: Colors.orange),
            SizedBox(width: 8),
            Text('Minta Kunci Dekripsi'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.vpn_key, size: 48, color: Colors.orange),
            const SizedBox(height: 16),
            Text(
              'Minta kunci dekripsi untuk file:',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              fileName,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Kirim pesan ke pengirim file untuk meminta kunci dekripsi. '
                'Kunci harus diberikan secara manual melalui chat.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              // Auto-generate pesan untuk meminta kunci
              final requestMessage =
                  '🔐 Hi! Could you please share the decryption key for file: "$fileName"?';
              _messageController.text = requestMessage;
              Navigator.pop(context);
              // Auto-focus ke text field
              FocusScope.of(context).requestFocus(FocusNode());
              Future.delayed(const Duration(milliseconds: 300), () {
                FocusScope.of(context).requestFocus(FocusNode());
                _scrollToBottom();
              });
            },
            child: const Text('Buat Pesan'),
          ),
        ],
      ),
    );
  }

  /// Method untuk menampilkan kunci dekripsi (hanya untuk owner)
  void _showDecryptionKey(Map<String, dynamic> fileMessage) {
    final fileName = fileMessage['file_name'] as String;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.vpn_key, color: Colors.orange),
            SizedBox(width: 8),
            Text('Kunci Dekripsi File'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.verified_user, size: 48, color: Colors.green),
            const SizedBox(height: 16),
            const Text(
              'Anda adalah Pemilik File',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              fileName,
              style: const TextStyle(fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green),
              ),
              child: Column(
                children: [
                  const Text(
                    'Kunci Dekripsi:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    _encryptionKey,
                    style: const TextStyle(
                      fontFamily: 'Monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Bagikan kunci ini secara aman kepada penerima yang dipercaya.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
          FilledButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _encryptionKey));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Kunci dekripsi disalin ke clipboard'),
                  backgroundColor: Colors.green,
                ),
              );
              Navigator.pop(context);
            },
            child: const Text('Salin Kunci'),
          ),
        ],
      ),
    );
  }

  /// Show file options dengan akses berbeda untuk owner dan receiver
  void _showFileOptions(Map<String, dynamic> fileMessage) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final isOwner = fileMessage['sender_id'] == authProvider.user!.id;

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download, color: Colors.blue),
              title: const Text('Download File (Tetap Terenkripsi)'),
              subtitle: const Text('Simpan file dalam bentuk terenkripsi'),
              onTap: () {
                Navigator.pop(context);
                _downloadEncryptedFile(fileMessage); // METHOD YANG DIPERBAIKI
              },
            ),
            ListTile(
              leading: Icon(
                isOwner ? Icons.verified_user : Icons.lock_open,
                color: isOwner ? Colors.green : Colors.blue,
              ),
              title: Text(isOwner
                  ? 'Dekripsi (Owner Access)'
                  : 'Dekripsi (Manual Key)'),
              subtitle: Text(isOwner
                  ? 'Dekripsi file dengan kunci akses penuh'
                  : 'Dekripsi file dengan kunci manual'),
              onTap: () {
                Navigator.pop(context);
                _decryptFile(fileMessage);
              },
            ),
            if (isOwner)
              ListTile(
                leading: const Icon(Icons.vpn_key, color: Colors.orange),
                title: const Text('Lihat & Bagikan Kunci'),
                subtitle:
                    const Text('Lihat kunci dekripsi dan bagikan secara aman'),
                onTap: () {
                  Navigator.pop(context);
                  _showDecryptionKey(fileMessage);
                },
              ),
            if (!isOwner)
              ListTile(
                leading: const Icon(Icons.vpn_key, color: Colors.orange),
                title: const Text('Minta Kunci Dekripsi'),
                subtitle: const Text('Minta kunci rahasia dari pengirim'),
                onTap: () {
                  Navigator.pop(context);
                  _requestDecryptionKey(fileMessage);
                },
              ),
            ListTile(
              leading: const Icon(Icons.info, color: Colors.grey),
              title: const Text('Info File'),
              subtitle: const Text('Lihat informasi detail file'),
              onTap: () {
                Navigator.pop(context);
                _showFileInfo(fileMessage);
              },
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Batal'),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
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
      final encryptionResult =
          await encryptionService.encryptMessage(message, _encryptionKey);

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

  Future<void> _uploadFileWithCompression() async {
    try {
      final supabaseService = SupabaseService();

      final selectedLocation = await showDialog<String>(
        context: context,
        builder: (context) => FileLocationModal(
          fileName: 'file',
          isUpload: true,
        ),
      );

      if (selectedLocation == null) return;

      final fileResult = await supabaseService.pickFileWithLocation();
      if (fileResult == null || fileResult.files.isEmpty) return;

      final platformFile = fileResult.files.first;
      final fileName = platformFile.name;

      Uint8List? fileData = platformFile.bytes;

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

      final mimeType = _getMimeType(fileName);

      if (kDebugMode) {
        debugPrint('📁 File selected: $fileName');
        debugPrint('   Type: $mimeType');
        debugPrint('   Size: ${fileData.length} bytes');
      }

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

      final processedFile = await supabaseService.processFile(
        fileData: fileData,
        fileName: fileName,
        mimeType: mimeType,
      );

      if (mounted) {
        Navigator.of(context).pop();
      }

      if (kDebugMode) {
        debugPrint('🔐 Encrypting file: $fileName');
        if (processedFile.isCompressed) {
          debugPrint('   Compression: ${processedFile.compressionInfo}');
          debugPrint(
              '   Size reduction: ${processedFile.compressionRatio.toStringAsFixed(1)}%');
        }
      }

      final tempFile = await supabaseService.saveFileToLocation(
        data: processedFile.data,
        fileName: 'temp_$fileName',
        locationType: 'temp',
      );

      final encryptionResult = await fileEncryption.encryptFile(
        file: tempFile,
        encryptionKey: _encryptionKey,
        chatId: widget.chatId,
        fileName: fileName,
      );

      if (kDebugMode) {
        debugPrint('📤 Uploading encrypted file...');
      }

      final uploadedFilePath = await supabaseService.uploadEncryptedFile(
        fileData: encryptionResult.encryptedData,
        fileName: fileName,
        chatId: widget.chatId,
        mimeType: processedFile.mimeType,
      );

      if (kDebugMode) {
        debugPrint('💾 Saving file message to database...');
      }

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

  Future<void> _uploadMultipleFiles() async {
    try {
      final supabaseService = SupabaseService();

      final fileResult = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: true,
        withData: true,
      );

      if (fileResult == null || fileResult.files.isEmpty) return;

      final totalSize =
          fileResult.files.fold<int>(0, (sum, file) => sum + (file.size ?? 0));
      if (totalSize > 50 * 1024 * 1024) {
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

      final zipData = await supabaseService.createZipArchive(filesToZip);
      final zipFileName = 'files_${DateTime.now().millisecondsSinceEpoch}.zip';

      final tempFile = await supabaseService.saveFileToLocation(
        data: zipData,
        fileName: zipFileName,
        locationType: 'temp',
      );

      final encryptionResult = await fileEncryption.encryptFile(
        file: tempFile,
        encryptionKey: _encryptionKey,
        chatId: widget.chatId,
        fileName: zipFileName,
      );

      final uploadedFilePath = await supabaseService.uploadEncryptedFile(
        fileData: encryptionResult.encryptedData,
        fileName: zipFileName,
        chatId: widget.chatId,
        mimeType: 'application/zip',
      );

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

      await tempFile.delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${filesToZip.length} files berhasil diupload sebagai ZIP'),
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

  Future<void> _uploadDemoFile() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final demoFile = File(
          '${tempDir.path}/demo_file_${DateTime.now().millisecondsSinceEpoch}.txt');
      await demoFile.writeAsString(
          'This is a demo encrypted file content. Created at: ${DateTime.now()}\n\n'
          'Chat: ${widget.chatId}\n'
          'With: ${widget.otherUserName}\n'
          'Encryption Key: $_encryptionKey\n'
          'Encrypted with: ChaCha20-Poly1305 + HMAC-SHA512');

      final fileName = 'demo_file.txt';
      final fileSize = await demoFile.length();

      if (kDebugMode) {
        debugPrint('🔐 Starting file encryption with key: $_encryptionKey');
        debugPrint('   Chat ID: ${widget.chatId}');
        debugPrint('   File size: $fileSize bytes');
      }

      setState(() {
        _isUploading = true;
      });

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final supabaseService = SupabaseService();
      final fileEncryption = FileEncryptionService();

      // Encrypt file
      final encryptionResult = await fileEncryption.encryptFile(
        file: demoFile,
        encryptionKey: _encryptionKey,
        chatId: widget.chatId,
        fileName: fileName,
      );

      if (kDebugMode) {
        debugPrint('✅ File encrypted successfully');
        debugPrint('   Nonce: ${base64.encode(encryptionResult.nonce)}');
        debugPrint('   Auth Tag: ${base64.encode(encryptionResult.authTag)}');
      }

      // Upload encrypted file
      final uploadedFilePath = await supabaseService.uploadEncryptedFile(
        fileData: encryptionResult.encryptedData,
        fileName: fileName,
        chatId: widget.chatId,
        mimeType: encryptionResult.mimeType,
      );

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

      // Cleanup
      await demoFile.delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('File demo berhasil diupload'),
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

  /// Show file info
  void _showFileInfo(Map<String, dynamic> fileMessage) {
    final fileName = fileMessage['file_name'] as String;
    final fileSize = fileMessage['file_size'] as int;
    final mimeType = fileMessage['mime_type'] as String;
    final createdAt = fileMessage['created_at'] as String;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final isOwner = fileMessage['sender_id'] == authProvider.user!.id;

    final supabaseService = SupabaseService();
    final fileInfo = supabaseService.getFileInfo(fileName, fileSize, mimeType);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Info File'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Nama File', fileName),
            _buildInfoRow('Tipe File', fileInfo['category']),
            _buildInfoRow('Ekstensi', fileInfo['extension']),
            _buildInfoRow('Ukuran', fileInfo['size_formatted']),
            _buildInfoRow('MIME Type', mimeType),
            _buildInfoRow('Dibuat', _formatDateTime(createdAt)),
            _buildInfoRow(
                'Status',
                isOwner
                    ? 'Owner - Full Access'
                    : 'Receiver - Manual Key Required'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isOwner ? Colors.green[50] : Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    isOwner ? Icons.verified_user : Icons.vpn_key,
                    size: 16,
                    color: isOwner ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isOwner
                          ? 'Anda adalah pemilik file. Kunci dekripsi tersedia otomatis.'
                          : 'Anda adalah penerima. Butuh kunci manual dari pengirim.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isOwner ? Colors.green : Colors.orange,
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
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(String dateTimeString) {
    try {
      final dateTime = DateTime.parse(dateTimeString).toLocal();
      return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateTimeString;
    }
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  // ===============================
  // ENHANCED MESSAGE BUBBLE WITH COPY FEATURES
  // ===============================

  /// Enhanced message bubble with copy functionality
  Widget _buildMessageBubble(Map<String, dynamic> message, bool isMe) {
    final messageText = message['message'] as String;
    final time = _formatTime(message['created_at'] as String);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 16.0),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
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
            child: GestureDetector(
              onTap: () {
                // Single tap - show quick copy option
                _copyMessageToClipboard(messageText);
              },
              onLongPress: () {
                // Long press - show context menu
                _showMessageContextMenu(message, isMe);
              },
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
                    bottomLeft: isMe
                        ? const Radius.circular(16.0)
                        : const Radius.circular(4.0),
                    bottomRight: isMe
                        ? const Radius.circular(4.0)
                        : const Radius.circular(16.0),
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

  /// Enhanced file message bubble dengan copy functionality
  Widget _buildEnhancedFileMessage(
      Map<String, dynamic> fileMessage, bool isMe) {
    final fileName = fileMessage['file_name'] as String;
    final fileSize = fileMessage['file_size'] as int;
    final mimeType = fileMessage['mime_type'] as String;

    final supabaseService = SupabaseService();
    final fileInfo = supabaseService.getFileInfo(fileName, fileSize, mimeType);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 16.0),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
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
              onTap: () {
                // Single tap - show file options
                _showFileOptions(fileMessage);
              },
              onLongPress: () {
                // Long press - show context menu dengan copy options
                _showFileContextMenu(fileMessage, isMe);
              },
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
                    bottomLeft: isMe
                        ? const Radius.circular(16.0)
                        : const Radius.circular(4.0),
                    bottomRight: isMe
                        ? const Radius.circular(4.0)
                        : const Radius.circular(16.0),
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
                        color: (fileInfo['color'] as Color).withAlpha(51),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(fileInfo['icon'] as IconData,
                          color: fileInfo['color'] as Color, size: 20),
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
                                fileInfo['category'] as String,
                                style: TextStyle(
                                  color:
                                      isMe ? Colors.white70 : Colors.grey[600],
                                  fontSize: 12.0,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '•',
                                style: TextStyle(
                                  color:
                                      isMe ? Colors.white70 : Colors.grey[500],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                fileInfo['size_formatted'] as String,
                                style: TextStyle(
                                  color:
                                      isMe ? Colors.white70 : Colors.grey[600],
                                  fontSize: 12.0,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4.0),
                          Row(
                            children: [
                              Icon(
                                isMe ? Icons.verified_user : Icons.vpn_key,
                                size: 12,
                                color: isMe ? Colors.green : Colors.orange,
                              ),
                              const SizedBox(width: 4.0),
                              Text(
                                isMe
                                    ? 'Owner • Full Access • Tap untuk opsi'
                                    : 'Receiver • Manual Key Required • Tap untuk opsi',
                                style: TextStyle(
                                  color: isMe ? Colors.green : Colors.orange,
                                  fontSize: 10.0,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.more_vert,
                      size: 16,
                      color: isMe ? Colors.white70 : Colors.grey[500],
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
      'docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
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
      padding: const EdgeInsets.only(
          left: 16.0, right: 16.0, top: 8.0, bottom: 16.0),
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
                valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary),
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
                    } else if (value == 'steganography') {
                      _showSteganographyModal();
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
                                style:
                                    TextStyle(fontSize: 12, color: Colors.grey),
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
                                style:
                                    TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'steganography',
                      child: Row(
                        children: [
                          Icon(Icons.visibility_off,
                              size: 20, color: Colors.purple),
                          SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Hide Secret in Image'),
                              Text(
                                'Steganography LSB+DCT',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.purple),
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
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
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
                    onPressed:
                        _messageController.text.trim().isEmpty || _isSending
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
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Emoji picker coming soon!'),
          duration: Duration(seconds: 2),
        ),
      );
    }
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

    return RefreshIndicator(
      onRefresh: _manualRefresh,
      child: ListView.builder(
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
      ),
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
    _messageSubscription?.cancel();
    _fileMessageSubscription?.cancel();
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
            if (kDebugMode)
              Text(
                'Messages: ${_messages.length} | Files: ${_fileMessages.length}',
                style: const TextStyle(
                  fontSize: 10.0,
                  fontWeight: FontWeight.normal,
                  color: Colors.grey,
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
                      _buildInfoRow(
                          'My PIN', authProvider.userPin ?? 'Unknown'),
                      _buildInfoRow(
                          'Total Messages', _messages.length.toString()),
                      _buildInfoRow(
                          'Total Files', _fileMessages.length.toString()),
                      _buildInfoRow('Text Encryption', 'AES-256-CBC'),
                      _buildInfoRow(
                          'File Encryption', 'ChaCha20-Poly1305 + HMAC-SHA512'),
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
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _manualRefresh,
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
                      onPressed: _manualRefresh,
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
