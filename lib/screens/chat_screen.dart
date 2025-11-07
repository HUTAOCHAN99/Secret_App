// secret_app/lib/screens/chat_screen.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/supabase_service.dart';
import '../services/encryption_service.dart';

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
  bool _isLoading = true;
  bool _isSending = false;
  late String _encryptionKey;
  Stream<List<Map<String, dynamic>>>? _messagesStream;
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
      _setupRealtimeSubscription();
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
          _isLoading = false;
          _hasError = false;
        });
        
        _scrollToBottom(instant: true);
      }
      
      if (kDebugMode) {
        debugPrint('✅ Loaded $successCount messages (failed: $failCount)');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to load messages: $e');
      }
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Failed to load messages: $e';
          _isLoading = false;
        });
      }
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

  void _scrollToBottom({bool instant = false}) {
    if (_scrollController.hasClients && _messages.isNotEmpty) {
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
              child: Icon(
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
              child: Icon(
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

  String _formatTime(String dateTimeString) {
    try {
      final dateTime = DateTime.parse(dateTimeString).toLocal();
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '--:--';
    }
  }

  Widget _buildInputArea() {
    return Padding(
      padding: EdgeInsets.only(
        left: 16.0,
        right: 16.0,
        top: 8.0,
        bottom: 16.0, // TAMBAHAN: Jarak dari dasar layar
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(
              color: Colors.grey[300]!,
              width: 1.0,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
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
                constraints: const BoxConstraints(
                  maxHeight: 100.0,
                ),
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
    
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(
        top: 8.0,
        bottom: 8.0,
      ),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final isMe = message['sender_id'] == authProvider.user!.id;
        
        return _buildMessageBubble(message, isMe);
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
                      _buildInfoRow('Encryption', 'AES-256-CBC'),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.verified, color: Colors.green[600], size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'End-to-end encrypted',
                                style: TextStyle(
                                  color: Colors.green[800],
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
        bottom: true, // Pastikan ada safe area di bottom
        child: Column(
          children: [
            if (_hasError)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12.0),
                color: Colors.red[50],
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red[600]),
                    const SizedBox(width: 8.0),
                    Expanded(
                      child: Text(
                        _errorMessage,
                        style: TextStyle(color: Colors.red[800]),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.refresh, color: Colors.red[600]),
                      onPressed: _initializeChat,
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _isLoading
                  ? _buildLoading()
                  : _messages.isEmpty
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