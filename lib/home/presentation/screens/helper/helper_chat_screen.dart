// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// ignore: depend_on_referenced_packages
import 'package:intl/intl.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/chat_provider.dart';
import 'dart:async'; // Keep this import for Timer
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:just_audio/just_audio.dart';

class HelperChatScreen extends StatefulWidget {
  const HelperChatScreen({super.key});

  @override
  State<HelperChatScreen> createState() => _HelperChatScreenState();
}

class _HelperChatScreenState extends State<HelperChatScreen> {
  final TextEditingController _messageController = TextEditingController();

  String? _currentUserId;
  String? _linkedUserId;
  String? _chatRoomId;
  bool _isConnecting = false;
  bool _isConnectionFailed = false;
  Timer? _chatRefreshTimer;

  // Helper-specific UI variables
  final Color _mainColor = Colors.green; // Green theme for helper users
  String? _blindUserName;
  final Color _sentBubbleColor = Color(0xFFDCF8C6); //  sent message color
  final Color _receivedBubbleColor = Colors.white; //  received message color
  final double _fontSize = 16.0; // Font size for messages

  // Format duration as mm:ss for audio messages
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  // Audio player functionality
  final _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  String? _currentlyPlayingUrl;

  @override
  void initState() {
    super.initState();
    // Initialize chat immediately
    _initChatImmediately();

    // Set up a timer to periodically retry connection if failed
    _chatRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_isConnectionFailed && mounted) {
        debugPrint('🔄 Periodic chat refresh triggered');
        _initChatInBackground();
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _chatRefreshTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  // Initialize chat immediately to show UI, then continue connection in background
  void _initChatImmediately() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    // Get current user ID
    _currentUserId = authProvider.currentUserId;

    // Get linked user ID
    _linkedUserId = authProvider.linkedUserId;

    if (_currentUserId != null && _linkedUserId != null) {
      // Generate chat room ID immediately without waiting for network
      // Sort IDs to ensure consistent ordering
      final List<String> userIds = [_currentUserId!, _linkedUserId!];
      userIds.sort();
      _chatRoomId = 'chat_${userIds.join('_')}';
      debugPrint('✅ Chat room ID created immediately: $_chatRoomId');

      // Force UI update to show chat immediately
      setState(() {});

      // Continue connection in background
      _initChatInBackground();
    } else {
      // Continue with normal initialization to handle linking issues
      _initChatInBackground();
    }
  }

  // Initialize chat connection in background
  Future<void> _initChatInBackground() async {
    setState(() => _isConnecting = true);

    try {
      debugPrint('🔄 Initializing chat in background');
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);

      // Reset state to default values
      _isConnectionFailed = false;

      // Get current user ID
      _currentUserId = authProvider.currentUserId;

      if (_currentUserId == null) {
        debugPrint('❌ Current user ID is null');
        throw Exception('User not logged in');
      }

      // Get linked user ID from auth provider
      _linkedUserId = authProvider.linkedUserId;

      if (_linkedUserId == null) {
        debugPrint('❌ Linked user ID is null');
        throw Exception('Not connected to a blind user');
      }

      debugPrint('🔄 Current user: $_currentUserId');
      debugPrint('🔄 Linked user: $_linkedUserId');

      // Create chat room ID
      final List<String> userIds = [_currentUserId!, _linkedUserId!];
      userIds.sort();
      _chatRoomId = 'chat_${userIds.join('_')}';
      debugPrint('✅ Using chat room ID: $_chatRoomId');

      // Get blind user name if it's not already set
      if (_blindUserName == null) {
        try {
          final blindUserDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(_linkedUserId!)
              .get();

          if (blindUserDoc.exists) {
            final userData = blindUserDoc.data();
            if (userData != null && userData.containsKey('displayName')) {
              _blindUserName = userData['displayName'] as String?;
              debugPrint('✅ Got blind user name: $_blindUserName');
            }
          }
        } catch (e) {
          debugPrint('❌ Error getting blind user name: $e');
        }
      }

      // Ensure chat room exists
      try {
        // Create or update the chat room using ChatProvider
        await chatProvider.createChatRoom(userIds);

        // Check if there are messages
        final messagesQuery = await FirebaseFirestore.instance
            .collection('chats')
            .doc(_chatRoomId)
            .collection('messages')
            .limit(1)
            .get();

        if (messagesQuery.docs.isEmpty) {
          // Add welcome message
          await chatProvider.addSystemMessage(
            chatRoomId: _chatRoomId!,
            text: 'Chat started. You can now communicate with the blind user.',
          );
          debugPrint('✅ Added welcome message to new chat');
        }

        // Start periodic read receipt updates
        _startPeriodicReadReceipts();

        setState(() {
          _isConnecting = false;
          _isConnectionFailed = false;
        });
      } catch (e) {
        debugPrint('❌ Error ensuring chat room exists: $e');
        setState(() {
          _isConnecting = false;
          _isConnectionFailed = true;
        });
      }
    } catch (e) {
      debugPrint('❌ Error initializing chat: $e');
      setState(() {
        _isConnecting = false;
        _isConnectionFailed = true;
      });
    }
  }

  // Send text message with offline support
  Future<void> _sendTextMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) {
      return;
    }

    // Check network connectivity first
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        _showErrorSnackBar(
            'No internet connection. Message will be saved and sent when you\'re online');
        // Still continue to try sending - Firebase will handle offline persistence
      }
    } catch (e) {
      debugPrint('⚠️ Could not check connectivity: $e');
    }

    // Ensure we have the required IDs for sending
    if (_currentUserId == null) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      _currentUserId = authProvider.currentUserId;
    }

    // Generate chat room ID immediately if it's not available yet
    if (_chatRoomId == null &&
        _currentUserId != null &&
        _linkedUserId != null) {
      List<String> userIds = [_currentUserId!, _linkedUserId!];
      userIds.sort();
      _chatRoomId = 'chat_${userIds.join('_')}';
    }

    // If we still don't have a chat room ID, create a temporary one based on current user
    if (_chatRoomId == null && _currentUserId != null) {
      _chatRoomId = 'chat_${_currentUserId!}_temp';
      debugPrint('⚠️ Using temporary chat room ID: $_chatRoomId');
    }

    // If we still can't create a chat room ID, show error
    if (_chatRoomId == null || _currentUserId == null) {
      _showErrorSnackBar('Cannot send message: not connected to chat');
      return;
    }

    setState(() => _isConnecting = true);

    try {
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);

      // Send the message using ChatProvider
      await chatProvider.sendTextMessage(
        chatRoomId: _chatRoomId!,
        text: text,
        senderId: _currentUserId!,
      );

      // Clear the input field
      _messageController.clear();

      setState(() => _isConnecting = false);

      // Optional: show a confirmation
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Message sent'),
          duration: const Duration(seconds: 2),
          backgroundColor: _mainColor,
        ),
      );
    } catch (e) {
      debugPrint('❌ Failed to send message: $e');
      _showErrorSnackBar(
          'Failed to send message. Will retry when connection is available.');
      setState(() => _isConnecting = false);
    }
  }

  // Show error message
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Retry',
          textColor: Colors.white,
          onPressed: () {
            // Re-initialize the chat
            _initChatInBackground();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: Container(
        decoration: BoxDecoration(
          //  chat background
          color: const Color(0xFFECE5DD), // Light beige background
        ),
        child: Column(
          children: [
            // Connection status indicator
            if (_isConnectionFailed)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                color: Colors.red.shade800,
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Connection failed. Messages will be sent when online.',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _initChatInBackground,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(60, 30),
                      ),
                      child:
                          const Text('Retry', style: TextStyle(fontSize: 14)),
                    ),
                  ],
                ),
              ),

            // Chat view
            Expanded(
              child: _chatRoomId == null
                  ? _buildNotConnectedView()
                  : _buildChatMessages(),
            ),

            // Message input
            if (_chatRoomId != null) _buildMessageInput(),
          ],
        ),
      ),
    );
  }

  // Build the app bar with improved design
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF075E54), // WhatsApp primary color
      leadingWidth: 40,
      titleSpacing: 0, // Reduced to accommodate the back button

      title: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.grey[300],
            child: Icon(
              Icons.person_outline,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _blindUserName != null ? _blindUserName! : 'Blind User',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _linkedUserId == null ? 'Not connected' : 'Online',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFFB3DEDC),
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      elevation: 0,
      actions: [
        // Connection indicator
        if (_isConnecting)
          Container(
            width: 40,
            padding: const EdgeInsets.all(10),
            child: const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              strokeWidth: 2,
            ),
          ),
        // Menu button
        PopupMenuButton(
          icon: const Icon(Icons.more_vert),
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'clear',
              child: Row(
                children: [
                  Icon(Icons.delete_sweep, color: Colors.grey),
                  SizedBox(width: 10),
                  Text('Clear chat'),
                ],
              ),
            ),
          ],
          onSelected: (value) {
            if (value == 'clear') {
              _showClearChatConfirmation();
            }
          },
        ),
      ],
    );
  }

  // View when not connected with a blind user
  Widget _buildNotConnectedView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.person_search,
            size: 80,
            color: Colors.grey,
          ),
          const SizedBox(height: 16),
          const Text(
            'Not connected with a blind user',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'You need to connect with a blind user before you can chat.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              // Navigate to connect screen
              Navigator.pushNamed(context, '/connect-with-blind');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _mainColor,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
            child: const Text('Connect with Blind User'),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _initChatInBackground,
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  // Improved chat messages stream builder
  Widget _buildChatMessages() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _chatRoomId != null
          ? Provider.of<ChatProvider>(context)
              .getChatMessagesStream(_chatRoomId!)
          : null,
      builder: (context, snapshot) {
        if (_isConnecting &&
            (!snapshot.hasData ||
                snapshot.data == null ||
                snapshot.data!.isEmpty)) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Colors.grey[400]!),
                    strokeWidth: 3,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Loading messages...',
                  style: TextStyle(
                      fontSize: _fontSize - 2, color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                const SizedBox(height: 16),
                Text(
                  'Error loading messages',
                  style: TextStyle(fontSize: _fontSize - 2, color: Colors.red),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _initChatInBackground,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _mainColor,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        if (_chatRoomId == null ||
            !snapshot.hasData ||
            snapshot.data == null ||
            snapshot.data!.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chat_bubble_outline,
                    size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No messages yet',
                  style: TextStyle(
                      fontSize: _fontSize - 2, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Text(
                  'Start the conversation by sending a message to the blind user',
                  style: TextStyle(
                      fontSize: _fontSize - 4, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.message),
                      label: const Text('Send a Message'),
                      onPressed: () {
                        _messageController.text =
                            'Hello, I\'m here to help you. What do you need assistance with?';
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _mainColor,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        final messages = snapshot.data!;

        // Mark messages as read
        if (_linkedUserId != null &&
            _currentUserId != null &&
            _chatRoomId != null) {
          Provider.of<ChatProvider>(context, listen: false)
              .markMessagesAsReadAndDelivered(
            chatRoomId: _chatRoomId!,
            currentUserId: _currentUserId!,
            otherUserId: _linkedUserId!,
          );
        }

        return ListView.builder(
          reverse: true, // Show newest at the bottom
          itemCount: messages.length,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          itemBuilder: (context, index) {
            final message = messages[messages.length - 1 - index];
            final isMe = message['senderId'] == _currentUserId;
            final isSystem = message['senderId'] == 'system';

            // Check if the date changed from the previous message
            final bool showDateSeparator =
                _shouldShowDateSeparator(messages, messages.length - 1 - index);

            return Column(
              children: [
                if (showDateSeparator) _buildDateSeparator(message),
                isSystem
                    ? _buildSystemMessage(message)
                    : _buildMessageBubble(message, isMe),
              ],
            );
          },
        );
      },
    );
  }

  // Show date separator if needed
  bool _shouldShowDateSeparator(
      List<Map<String, dynamic>> messages, int index) {
    if (index == messages.length - 1) {
      return true; // Always show for the first message
    }

    final currentMessage = messages[index];
    final previousMessage = messages[index + 1];

    final currentTimestamp = currentMessage['timestamp'] is DateTime
        ? (currentMessage['timestamp'] as DateTime)
        : DateTime.now();

    final previousTimestamp = previousMessage['timestamp'] is DateTime
        ? (previousMessage['timestamp'] as DateTime)
        : DateTime.now();

    return !_isSameDay(currentTimestamp, previousTimestamp);
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  Widget _buildDateSeparator(Map<String, dynamic> message) {
    final timestamp = message['timestamp'] is DateTime
        ? (message['timestamp'] as DateTime)
        : DateTime.now();

    final date = DateFormat('MMMM d, yyyy').format(timestamp);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Divider(color: Colors.grey[400], endIndent: 10),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              date,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[800],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Divider(color: Colors.grey[400], indent: 10),
          ),
        ],
      ),
    );
  }

  // Build message input with WhatsApp style
  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      color: const Color(0xFFF0F0F0), // Light gray background
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      spreadRadius: 1,
                      blurRadius: 1,
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
                          hintStyle: TextStyle(
                              color: Colors.grey[500], fontSize: _fontSize - 2),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          border: InputBorder.none,
                        ),
                        style: TextStyle(fontSize: _fontSize),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendTextMessage(),
                        keyboardType: TextInputType.multiline,
                        maxLines: null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Send button
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFF075E54),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.send),
                color: Colors.white,
                onPressed: _sendTextMessage,
                splashRadius: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Build a system message (info message)
  Widget _buildSystemMessage(Map<String, dynamic> message) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFE2F3F5),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    spreadRadius: 1,
                    blurRadius: 1,
                  ),
                ],
              ),
              child: Text(
                message['text'] as String,
                style: TextStyle(
                  fontSize: _fontSize - 2,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey[800],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Build a message bubble with WhatsApp style
  Widget _buildMessageBubble(Map<String, dynamic> message, bool isMe) {
    final messageType = message['type'] as String? ?? 'text';
    final timestamp = message['timestamp'] is DateTime
        ? (message['timestamp'] as DateTime)
        : DateTime.now();
    final time = DateFormat('HH:mm').format(timestamp);

    final bool isRead = message['isRead'] == true;
    final bool isDelivered = message['isDelivered'] == true;

    return Container(
      margin: EdgeInsets.only(
        left: isMe ? 250 : 10, // Increased left margin for better appearance
        right: isMe ? 10 : 250, // Increased right margin for better appearance
        top: 4,
        bottom: 4,
      ),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: isMe ? _sentBubbleColor : _receivedBubbleColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft:
                    isMe ? const Radius.circular(16) : const Radius.circular(0),
                bottomRight:
                    isMe ? const Radius.circular(0) : const Radius.circular(16),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  spreadRadius: 1,
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Message content
                _getMessageContent(message, messageType),

                // Add space between content and timestamp
                const SizedBox(height: 2),

                // Time and status
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      time,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 3),
                      Icon(
                        isRead
                            ? Icons.done_all
                            : (isDelivered ? Icons.done : Icons.access_time),
                        size: 12,
                        color:
                            isRead ? const Color(0xFF4FC3F7) : Colors.grey[600],
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Get message content based on type with improved styling
  Widget _getMessageContent(Map<String, dynamic> message, String messageType) {
    switch (messageType) {
      case 'text':
        return Text(
          message['text'] as String,
          style: TextStyle(
            fontSize: _fontSize - 1,
            color: Colors.black87,
            height: 1.3, // Improved line height for better readability
          ),
        );
      case 'audio':
        // Format duration
        final int durationMs = message['durationMs'] as int? ?? 0;
        final Duration duration = Duration(milliseconds: durationMs);
        final String durationText = _formatDuration(duration);
        final String? audioUrl = message['audioUrl'] as String?;
        final bool isThisPlaying =
            _isPlaying && _currentlyPlayingUrl == audioUrl;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(16),
          ),
          constraints:
              BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              // Play/Pause button
              GestureDetector(
                onTap: () => _playAudioMessage(audioUrl),
                child: Icon(
                  isThisPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_fill,
                  color: _mainColor,
                  size: 36,
                ),
              ),
              const SizedBox(width: 8),
              // Audio info
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Voice Message',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      durationText,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      case 'location':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.location_on, color: Colors.red[700], size: 24),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Location shared',
                          style: TextStyle(
                            fontSize: _fontSize - 2,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                          ),
                        ),
                        if (message['address'] != null)
                          Text(
                            message['address'] as String,
                            style: TextStyle(
                              fontSize: _fontSize - 3,
                              color: Colors.grey[700],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          )
                        else
                          Text(
                            'View on map',
                            style: TextStyle(
                              fontSize: _fontSize - 3,
                              color: Colors.blue[700],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      case 'image':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => _openImageFullScreen(message['imageUrl'] as String),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  message['imageUrl'] as String,
                  width: 250,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      width: 250,
                      height: 200,
                      color: Colors.grey[200],
                      child: Center(
                        child: CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded /
                                  loadingProgress.expectedTotalBytes!
                              : null,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.grey[400]!),
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 250,
                      height: 100,
                      color: Colors.grey[200],
                      child: const Center(
                        child: Icon(Icons.error, color: Colors.red),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      default:
        return Text(
          'Unsupported message type',
          style: TextStyle(
            fontSize: _fontSize - 2,
            fontStyle: FontStyle.italic,
            color: Colors.grey[700],
          ),
        );
    }
  }

  // Start periodic read receipt updates
  void _startPeriodicReadReceipts() {
    // Cancel any existing timer
    _chatRefreshTimer?.cancel();

    // Create a new timer that marks messages as read every 5 seconds
    _chatRefreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_chatRoomId != null &&
          _currentUserId != null &&
          _linkedUserId != null) {
        final chatProvider = Provider.of<ChatProvider>(context, listen: false);
        chatProvider.markMessagesAsReadAndDelivered(
          chatRoomId: _chatRoomId!,
          currentUserId: _currentUserId!,
          otherUserId: _linkedUserId!,
        );
        debugPrint('🔄 Periodic read receipt update');
      }
    });
    debugPrint('✅ Started periodic read receipt updates');
  }

  // Play audio message
  Future<void> _playAudioMessage(String? audioUrl) async {
    if (audioUrl == null) {
      _showErrorSnackBar('Audio URL is missing');
      return;
    }

    try {
      if (_isPlaying && _currentlyPlayingUrl == audioUrl) {
        // Stop if the same audio is already playing
        await _audioPlayer.stop();
        setState(() {
          _isPlaying = false;
          _currentlyPlayingUrl = null;
        });
      } else {
        // Stop any currently playing audio
        if (_isPlaying) {
          await _audioPlayer.stop();
        }

        // Play the new audio
        await _audioPlayer.setUrl(audioUrl);
        await _audioPlayer.play();

        setState(() {
          _isPlaying = true;
          _currentlyPlayingUrl = audioUrl;
        });

        // Listen for playback completion
        _audioPlayer.playerStateStream.listen((state) {
          if (state.processingState == ProcessingState.completed && mounted) {
            setState(() {
              _isPlaying = false;
              _currentlyPlayingUrl = null;
            });
          }
        });
      }
    } catch (e) {
      _showErrorSnackBar('Failed to play audio: ${e.toString()}');
    }
  }

  // Show clear chat confirmation dialog
  void _showClearChatConfirmation() {
    if (_chatRoomId == null) {
      _showErrorSnackBar('Cannot clear chat: Chat not initialized');
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Chat History'),
        content: const Text(
          'Are you sure you want to clear all messages in this chat? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close the dialog
            },
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop(); // Close the dialog
              await _clearChat();
            },
            child: const Text('CLEAR', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // Clear chat implementation
  Future<void> _clearChat() async {
    if (_chatRoomId == null) {
      _showErrorSnackBar('Cannot clear chat: Chat not initialized');
      return;
    }

    setState(() => _isConnecting = true);

    try {
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      final success = await chatProvider.clearChat(_chatRoomId!);

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Chat history cleared'),
            backgroundColor: _mainColor,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        _showErrorSnackBar('Failed to clear chat. Please try again.');
      }
    } catch (e) {
      debugPrint('❌ Error clearing chat: $e');
      _showErrorSnackBar('Failed to clear chat: ${e.toString()}');
    } finally {
      setState(() => _isConnecting = false);
    }
  }

  // Open image in full screen with zoom capability
  void _openImageFullScreen(String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ImageFullScreenViewer(imageUrl: imageUrl),
      ),
    );
  }
}

// Full screen image viewer with zoom capabilities
class ImageFullScreenViewer extends StatefulWidget {
  final String imageUrl;

  const ImageFullScreenViewer({
    super.key,
    required this.imageUrl,
  });

  @override
  State<ImageFullScreenViewer> createState() => _ImageFullScreenViewerState();
}

class _ImageFullScreenViewerState extends State<ImageFullScreenViewer> {
  final TransformationController _transformationController =
      TransformationController();
  TapDownDetails? _doubleTapDetails;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapDetails = details;
  }

  void _handleDoubleTap() {
    if (_transformationController.value != Matrix4.identity()) {
      // If zoomed in, zoom out
      _transformationController.value = Matrix4.identity();
    } else {
      // If zoomed out, zoom in to double tap position
      final position = _doubleTapDetails!.localPosition;
      // Zoom to 2.5x at the position of the double tap
      final newTransform = Matrix4.identity()
        ..translate(-position.dx * 1.5, -position.dy * 1.5)
        ..scale(2.5);
      _transformationController.value = newTransform;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: GestureDetector(
          onDoubleTapDown: _handleDoubleTapDown,
          onDoubleTap: _handleDoubleTap,
          child: InteractiveViewer(
            transformationController: _transformationController,
            minScale: 0.5,
            maxScale: 4.0,
            child: Image.network(
              widget.imageUrl,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Center(
                  child: CircularProgressIndicator(
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                        : null,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.white54),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, color: Colors.red, size: 48),
                      SizedBox(height: 16),
                      Text(
                        'Failed to load image',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
