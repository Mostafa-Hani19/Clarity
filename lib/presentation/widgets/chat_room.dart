import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/chat_provider.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:intl/intl.dart';

class ChatRoom extends StatefulWidget {
  final String chatRoomId;
  final String chatRoomName;
  final String? linkedUserId; // ID of the person being chatted with

  const ChatRoom({
    super.key,
    required this.chatRoomId,
    required this.chatRoomName,
    this.linkedUserId,
  });

  @override
  State<ChatRoom> createState() => _ChatRoomState();
}

class _ChatRoomState extends State<ChatRoom> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isConnecting = false;
  String? _lastMessageId;

  @override
  void initState() {
    super.initState();
    // Mark messages as read when opening the chat
    _markMessagesAsRead();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool force = false}) {
    if (_scrollController.hasClients) {
      // Only scroll if user is near bottom, or force=true
      final threshold = 200.0; // px
      if (force ||
          _scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - threshold) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }
  }

  Future<void> _markMessagesAsRead() async {
    if (widget.linkedUserId == null) return;
    final currentUser = firebase_auth.FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    await chatProvider.markMessagesAsReadAndDelivered(
      chatRoomId: widget.chatRoomId,
      currentUserId: currentUser.uid,
      otherUserId: widget.linkedUserId!,
    );
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    setState(() => _isConnecting = true);
    try {
      final currentUser = firebase_auth.FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User not authenticated')),
        );
        return;
      }
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      await chatProvider.sendTextMessage(
        chatRoomId: widget.chatRoomId,
        text: text,
        senderId: currentUser.uid,
      );
      _messageController.clear();
      // Scroll to bottom after sending
      Future.delayed(const Duration(milliseconds: 200), () => _scrollToBottom(force: true));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send message: $e')),
      );
    } finally {
      setState(() => _isConnecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = Provider.of<ChatProvider>(context);
    final currentUser = firebase_auth.FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chatRoomName),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: chatProvider.getChatMessagesStream(widget.chatRoomId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error: ${snapshot.error}'),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = snapshot.data!;

                // Mark as read ONLY if there's a new message, and it's not my message
                if (messages.isNotEmpty) {
                  final lastMessage = messages.last;
                  if (_lastMessageId != lastMessage['id'] &&
                      lastMessage['senderId'] != currentUser?.uid) {
                    _lastMessageId = lastMessage['id'];
                    _markMessagesAsRead();
                  }
                }

                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      'No messages yet. Start a conversation!',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  );
                }

                WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

                return ListView.builder(
                  controller: _scrollController,
                  reverse: false, // Latest at the bottom
                  padding: const EdgeInsets.all(8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isMe = message['senderId'] == currentUser?.uid;
                    final isSystem = message['senderId'] == 'system';
                    if (isSystem) {
                      return _buildSystemMessage(message);
                    }
                    return _buildMessageItem(message, isMe, theme);
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: theme.brightness == Brightness.dark
                          ? Colors.grey.shade800
                          : Colors.grey.shade200,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _isConnecting ? null : _sendMessage,
                  icon: _isConnecting
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.send, color: theme.primaryColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemMessage(Map<String, dynamic> message) {
    final text = message['text'] as String? ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      alignment: Alignment.center,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade700,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageItem(Map<String, dynamic> message, bool isMe, ThemeData theme) {
    final messageType = message['type'] as String? ?? 'text';

    final timestampRaw = message['timestamp'];
    DateTime timestamp;
    if (timestampRaw is DateTime) {
      timestamp = timestampRaw;
    } else if (timestampRaw is int) {
      timestamp = DateTime.fromMillisecondsSinceEpoch(timestampRaw);
    } else if (timestampRaw is String) {
      try {
        timestamp = DateTime.parse(timestampRaw);
      } catch (_) {
        timestamp = DateTime.now();
      }
    } else {
      timestamp = DateTime.now();
    }
    final time = DateFormat('HH:mm').format(timestamp);

    final bool isRead = message['isRead'] == true;
    final bool isDelivered = message['isDelivered'] == true;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe
              ? theme.primaryColor.withOpacity(0.18)
              : (theme.brightness == Brightness.dark
                  ? Colors.grey.shade800
                  : Colors.grey.shade200),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isMe
                ? theme.primaryColor.withOpacity(0.3)
                : (theme.brightness == Brightness.dark
                    ? Colors.grey.shade700
                    : Colors.grey.shade300),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _getMessageContent(message, messageType),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            time,
                            style: TextStyle(
                              fontSize: 10,
                              color: theme.brightness == Brightness.dark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                            ),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 4),
                            Icon(
                              isRead
                                  ? Icons.done_all
                                  : (isDelivered ? Icons.done : Icons.access_time),
                              size: 12,
                              color: isRead ? Colors.blue : Colors.grey[600],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _getMessageContent(Map<String, dynamic> message, String messageType) {
    switch (messageType) {
      case 'text':
        return Text(
          message['text'] as String? ?? '',
          style: const TextStyle(fontSize: 16),
        );
      case 'image':
        if (message['imageUrl'] == null) return const Text('Image not available');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                message['imageUrl'] as String,
                width: 200,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return SizedBox(
                    height: 150,
                    width: 200,
                    child: Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                            : null,
                      ),
                    ),
                  );
                },
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Photo', style: TextStyle(fontStyle: FontStyle.italic)),
            ),
          ],
        );
      case 'location':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.red),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Location shared',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ),
            if (message['address'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  message['address'] as String,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
          ],
        );
      default:
        return const Text(
          'Unsupported message type',
          style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
        );
    }
  }
}
