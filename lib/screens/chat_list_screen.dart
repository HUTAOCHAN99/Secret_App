import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/supabase_service.dart';
import 'chat_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  List<dynamic> _chats = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();
  final _supabaseService = SupabaseService();

  @override
  void initState() {
    super.initState();
    _loadChats();
  }

  Future<void> _loadChats() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final chats = await _supabaseService.getUserChats(authProvider.userId!);
      
      if (mounted) {
        setState(() {
          _chats = chats;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load chats: $e')),
        );
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _searchAndStartChat() async {
    final pin = _searchController.text.trim();
    if (pin.isEmpty) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    try {
      final user = await _supabaseService.searchUserByPin(pin);
      
      if (user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User not found')),
          );
        }
        return;
      }

      if (user['id'] == authProvider.userId) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cannot start chat with yourself')),
          );
        }
        return;
      }

      final chatId = await _supabaseService.startChat(
        authProvider.userId!,
        user['id'],
      );
      
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              chatId: chatId,
              otherUserName: user['display_name'],
              otherUserPin: user['user_pin'],
            ),
          ),
        ).then((_) => _loadChats()); // Reload chats setelah kembali
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start chat: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              Navigator.pushNamed(context, '/profile');
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadChats,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Enter user PIN to start chat',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _searchAndStartChat,
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _chats.isEmpty
                    ? const Center(child: Text('No chats yet. Search for users by PIN to start chatting.'))
                    : ListView.builder(
                        itemCount: _chats.length,
                        itemBuilder: (context, index) {
                          final chat = _chats[index];
                          return ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.person),
                            ),
                            title: Text(chat['other_user_name'] ?? 'Unknown User'),
                            subtitle: Text('PIN: ${chat['other_user_pin'] ?? 'Unknown'}'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ChatScreen(
                                    chatId: chat['chat_id'],
                                    otherUserName: chat['other_user_name'] ?? 'Unknown User',
                                    otherUserPin: chat['other_user_pin'] ?? 'Unknown',
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}