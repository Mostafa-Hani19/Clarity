// ignore_for_file: unnecessary_overrides, use_super_parameters, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// ignore: depend_on_referenced_packages
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:vibration/vibration.dart';
import 'package:image_picker/image_picker.dart';
import '../../controllers/blind_chat_controller.dart';
import '../../../../services/connection_manager.dart';
import 'package:flutter_tts/flutter_tts.dart';

class BlindChatScreen extends StatefulWidget {
  const BlindChatScreen({super.key});

  @override
  State<BlindChatScreen> createState() => _BlindChatScreenState();
}

class _BlindChatScreenState extends State<BlindChatScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late BlindChatController _chatController;
  late ConnectionManager _connectionManager;
  final FlutterTts _tts = FlutterTts();

  // Blind-specific UI variables (can remain or be moved to controller if they affect its logic)
  final double _fontSize = 18.0;
  final Color _mainColor = Colors.blue;
  final Color _sentBubbleColor = const Color(0xFFDCF8C6);
  final Color _receivedBubbleColor = Colors.white;

  // Flag to track if the component is mounted
  bool _isMounted = false;

  @override
  void initState() {
    super.initState();
    _isMounted = true;
    WidgetsBinding.instance.addObserver(this);

    // Get providers without using BuildContext in initState
    Future.microtask(() {
      if (!_isMounted) return;

      _chatController =
          Provider.of<BlindChatController>(context, listen: false);
      _connectionManager =
          Provider.of<ConnectionManager>(context, listen: false);

      // Initialize TTS
      _initializeTts();

      // Check connection status
      _connectionManager.checkConnectionStatus();

      // Create a temporary chat after a short delay if no connection exists
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!_isMounted) return;
        if (!_connectionManager.isConnected) {
          _connectionManager.createTemporaryChat();
        }
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // This is a safer place to access BuildContext
    if (!_isMounted) return;

    _chatController = Provider.of<BlindChatController>(context, listen: false);
    _connectionManager = Provider.of<ConnectionManager>(context, listen: false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Handle app lifecycle changes
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // Stop any active operations when app is in background
      _tts.stop();
      if (_chatController.isListening) {
        _chatController.toggleListening(context);
      }
    }
  }

  Future<void> _initializeTts() async {
    if (!_isMounted) return;

    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
    } catch (e) {
      debugPrint('TTS initialization error: $e');
    }
  }

  Future<void> _speak(String text) async {
    if (!_isMounted) return;

    try {
      await _tts.speak(text);
    } catch (e) {
      debugPrint('TTS error: $e');
    }
  }

  @override
  void dispose() {
    _isMounted = false;
    _tts.stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Send text message - delegates to controller
  Future<void> _sendTextMessage(String text) async {
    if (text.isEmpty || !_isMounted) return;

    final connectionManager =
        Provider.of<ConnectionManager>(context, listen: false);
    final bool success = await connectionManager.sendMessage(text);

    if (success && _isMounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Message sent'),
          duration: const Duration(seconds: 2),
          backgroundColor: _mainColor,
        ),
      );

      // Give haptic feedback to indicate message sent
      Vibration.vibrate(duration: 100);
      _speak('Message sent');
    } else if (!success && _isMounted) {
      _showErrorSnackBar(connectionManager.isOnline
          ? 'Failed to send message. Will retry.'
          : 'No internet connection. Message will be sent when you\'re online');
    }
  }

  // Send image message - delegates to controller
  Future<void> _sendImageMessage(ImageSource source) async {
    if (!_isMounted) return;

    final controller = Provider.of<BlindChatController>(context, listen: false);

    final success = await controller.sendImageMessage(source);

    if (success && _isMounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Your image has been shared'),
          backgroundColor: _mainColor,
        ),
      );
      // Give haptic feedback to indicate image sent
      Vibration.vibrate(duration: 100);
      _speak('Image shared');
    } else if (!success && _isMounted) {
      _showErrorSnackBar(
          controller.lastError ?? 'Failed to share image. Please try again.');
    }
  }

  // Send audio message - delegates to controller
  Future<void> _handleAudioRecording() async {
    if (!_isMounted) return;

    final controller = Provider.of<BlindChatController>(context, listen: false);

    if (controller.isRecordingAudio) {
      // Stop recording and send
      final success = await controller.stopAudioRecordingAndSend();

      if (success && _isMounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Your voice message has been sent'),
            backgroundColor: _mainColor,
          ),
        );
        // Give haptic feedback to indicate audio sent
        Vibration.vibrate(duration: 100);
        _speak('Voice message sent');
      } else if (!success && _isMounted) {
        _showErrorSnackBar(controller.lastError ??
            'Failed to send voice message. Please try again.');
      }
    } else {
      // Start recording
      final success = await controller.startAudioRecording();

      if (!success && _isMounted) {
        // Check for Windows-specific error codes
        if (controller.lastError == "windows_microphone_permission" ||
            controller.lastError == "windows_microphone_error") {
          // Show Windows-specific permission dialog
          await controller.showWindowsMicrophonePermissionDialog(context);
        } else {
          _showErrorSnackBar(controller.lastError ??
              'Failed to start recording. Please try again.');
        }
      }
    }
  }

  // Play audio message
  // ignore: unused_element
  Future<void> _playAudioMessage(String audioUrl) async {
    if (!_isMounted) return;

    final controller = Provider.of<BlindChatController>(context, listen: false);
    final success = await controller.playAudio(audioUrl);

    if (!success && _isMounted) {
      _showErrorSnackBar('Failed to play audio message');
    }
  }

  // Stop audio playback
  // ignore: unused_element
  void _stopAudioPlayback() {
    if (!_isMounted) return;

    final controller = Provider.of<BlindChatController>(context, listen: false);
    controller.stopAudio();
  }

  void _startListening() {
    if (!_isMounted) return;

    _chatController.toggleListening(context);
  }

  // Show error message
  void _showErrorSnackBar(String message) {
    if (!_isMounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Retry',
          textColor: Colors.white,
          onPressed: () {
            _chatController.retryConnection(); // Call controller's retry
          },
        ),
      ),
    );
    _speak(message);
  }

  // Show clear chat confirmation dialog
  void _showClearChatConfirmation() {
    if (!_isMounted) return;

    final controller = Provider.of<BlindChatController>(context, listen: false);

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

              final success = await controller.clearChat();

              if (success && _isMounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Chat history cleared'),
                    backgroundColor: _mainColor,
                    duration: const Duration(seconds: 2),
                  ),
                );
                // Give haptic feedback to indicate action completed
                Vibration.vibrate(duration: 100);
                _speak('Chat history cleared');
              } else if (!success && _isMounted) {
                _showErrorSnackBar(controller.lastError ??
                    'Failed to clear chat. Please try again.');
              }
            },
            child: const Text('CLEAR', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BlindChatController>(builder: (context, controller, child) {
      return Scaffold(
        appBar: _BlindChatAppBar(
          linkedUserName: _connectionManager.isConnected
              ? controller.linkedUserName
              : "Support Chat",
          linkedUserId: _connectionManager.connectedUserId,
          isConnected: _connectionManager.isConnected,
          onShowHelp: () {
            controller.speak("You are in the assistance chat. "
                "Type a message or tap the microphone to send voice messages. "
                "You can use voice commands for various actions.");
          },
          onClearChat: () {
            _showClearChatConfirmation();
          },
        ),
        body: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFECE5DD),
            image: DecorationImage(
              image: const AssetImage(
                  'assets/images/blue-background-7470781_1280.jpg'),
              repeat: ImageRepeat.repeat,
              opacity: 0.12,
              onError: (exception, stackTrace) {
                debugPrint(
                    'Chat background image not found, using solid color');
              },
            ),
          ),
          child: Column(
            children: [
              if (!_connectionManager.isConnected ||
                  _connectionManager.connectedUserId == null)
                _ConnectionStatusBanner(
                  isConnectionFailed: !_connectionManager.isConnected,
                  onRetry: () {
                    controller.speak(_connectionManager.isConnected
                        ? "Connection failed. Tap to retry connecting to an assistant."
                        : "Not connected to an assistant yet. Tap to connect.");
                    // Try to reconnect
                    _connectionManager.checkConnectionStatus();
                  },
                ),
              if (!_connectionManager.isOnline)
                const _OfflineBanner(), // Add offline banner when not connected to internet
              Expanded(
                child: _ChatMessageList(
                  currentUserId: controller.currentUserId,
                  isConnecting: !_connectionManager.isConnected,
                  fontSize: _fontSize,
                  mainColor: _mainColor,
                  sentBubbleColor: _sentBubbleColor,
                  receivedBubbleColor: _receivedBubbleColor,
                  onRetry: () => _connectionManager.checkConnectionStatus(),
                ),
              ),
              _MessageInputBar(
                onSendTextMessage: _sendTextMessage,
                onSendImageMessage: _sendImageMessage,
                onHandleAudioRecording: _handleAudioRecording,
                onStartListening: _startListening,
                mainColor: _mainColor,
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _BlindChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? linkedUserName;
  final String? linkedUserId;
  final bool isConnected;
  final VoidCallback onShowHelp;
  final VoidCallback onClearChat;

  const _BlindChatAppBar({
    required this.linkedUserName,
    required this.linkedUserId,
    required this.isConnected,
    required this.onShowHelp,
    required this.onClearChat,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: const Color(0xFF075E54),
      leadingWidth: 40,
      titleSpacing: 5,
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
                  linkedUserId == null
                      ? 'Support Chat'
                      : linkedUserName ?? 'Assistant',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  isConnected ? 'Online' : 'Waiting for helper...',
                  style: TextStyle(
                    fontSize: 13,
                    color: isConnected ? const Color(0xFFB3DEDC) : Colors.amber,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
////////////////////////////////////

        if (isConnected && linkedUserId != null)
          IconButton(
            icon: const Icon(Icons.videocam),
            onPressed: () {
              final controller =
                  Provider.of<BlindChatController>(context, listen: false);
              controller.startVideoCall(context);
            },
            tooltip: 'Video Call',
          ),

///////////////////////////////////////////////

        IconButton(
          icon: const Icon(Icons.help_outline),
          onPressed: onShowHelp,
          tooltip: 'Help',
        ),
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
              onClearChat();
            }
          },
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _ConnectionStatusBanner extends StatelessWidget {
  final bool isConnectionFailed;
  final VoidCallback onRetry;

  const _ConnectionStatusBanner({
    Key? key,
    required this.isConnectionFailed,
    required this.onRetry,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onRetry,
      child: Container(
        width: double.infinity,
        color: isConnectionFailed ? Colors.red.shade800 : Colors.amber.shade700,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        child: Row(
          children: [
            Icon(isConnectionFailed ? Icons.error_outline : Icons.info_outline,
                color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isConnectionFailed
                    ? 'Connection failed. Tap to retry.'
                    : 'Your messages will be delivered when a helper connects. Tap to check connection.',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.orange.shade800,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'You\'re offline. Messages will be sent when you\'re back online.',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatMessageList extends StatelessWidget {
  final String? chatRoomId;
  final String? currentUserId;
  final bool isConnecting;
  final double fontSize;
  final Color mainColor;
  final Color sentBubbleColor;
  final Color receivedBubbleColor;
  final VoidCallback onRetry;

  const _ChatMessageList({
    // ignore: unused_element_parameter
    super.key,
    // ignore: unused_element_parameter
    this.chatRoomId,
    required this.currentUserId,
    required this.isConnecting,
    required this.fontSize,
    required this.mainColor,
    required this.sentBubbleColor,
    required this.receivedBubbleColor,
    required this.onRetry,
  });

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

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

  // Play audio message
  Future<void> _playAudioMessage(BuildContext context, String audioUrl) async {
    final controller = Provider.of<BlindChatController>(context, listen: false);
    final success = await controller.playAudio(audioUrl);

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to play audio message'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Stop audio playback
  void _stopAudioPlayback(BuildContext context) {
    final controller = Provider.of<BlindChatController>(context, listen: false);
    controller.stopAudio();
  }

  // Format duration as mm:ss
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  // Open image in full screen with zoom capability
  void _openImageFullScreen(BuildContext context, String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ImageFullScreenViewer(imageUrl: imageUrl),
      ),
    );
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

  Widget _buildSystemMessage(Map<String, dynamic> message) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFE7F3FF),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    spreadRadius: 1,
                    blurRadius: 1,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.info_outline,
                      color: Color(0xFF2196F3),
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      message['text'] as String,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF2C3E50),
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _getMessageContent(
      BuildContext context, Map<String, dynamic> message, String messageType) {
    switch (messageType) {
      case 'text':
        return Text(
          message['text'] as String,
          style: TextStyle(
            fontSize: fontSize,
            color: Colors.black87,
            height: 1.4, // Improved line height for better readability
            letterSpacing: 0.2, // Slight letter spacing for better readability
          ),
          softWrap: true,
          overflow: TextOverflow.visible,
        );
      case 'image':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () {
                // Handle image tap - show full screen image
                _openImageFullScreen(context, message['imageUrl'] as String);
              },
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.6,
                  maxHeight: 200,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    message['imageUrl'] != null
                        ? message['imageUrl'] as String
                        : '',
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        width: 200,
                        height: 200,
                        color: Colors.grey[300],
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
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: 200,
                        height: 200,
                        color: Colors.grey[300],
                        child: const Center(
                          child: Icon(
                            Icons.broken_image,
                            size: 40,
                            color: Colors.red,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      case 'audio':
        // Convert duration milliseconds to formatted time
        final int durationMs = message['durationMs'] as int? ?? 0;
        final Duration duration = Duration(milliseconds: durationMs);
        final String durationText = _formatDuration(duration);

        // Create audio player UI
        return Consumer<BlindChatController>(
          builder: (context, controller, child) {
            final bool isPlaying = controller.isPlayingAudio;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Play/Pause button
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: mainColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(
                        isPlaying ? Icons.pause : Icons.play_arrow,
                        color: mainColor,
                        size: 24,
                      ),
                      onPressed: () {
                        if (isPlaying) {
                          _stopAudioPlayback(context);
                        } else {
                          final audioUrl = message['audioUrl'] as String?;
                          if (audioUrl != null) {
                            _playAudioMessage(context, audioUrl);
                          }
                        }
                      },
                      padding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Audio visualization and duration
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Audio visualization (simplified)
                        SizedBox(
                          height: 24,
                          child: Row(
                            children: List.generate(
                              15,
                              (index) => Container(
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 1),
                                width: 3,
                                height: 4 + (index % 3) * 6.0,
                                decoration: BoxDecoration(
                                  color: mainColor.withOpacity(0.6),
                                  borderRadius: BorderRadius.circular(1),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Duration text
                        Text(
                          durationText,
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      default:
        return Text(
          'Unsupported message type',
          style: TextStyle(
            fontSize: fontSize - 2,
            fontStyle: FontStyle.italic,
            color: Colors.grey[700],
          ),
        );
    }
  }

  Widget _buildMessageBubble(
      BuildContext context, Map<String, dynamic> message, bool isMe) {
    final messageType = message['type'] as String? ?? 'text';
    final timestamp = message['timestamp'] is DateTime
        ? (message['timestamp'] as DateTime)
        : DateTime.now();
    final time = DateFormat('HH:mm').format(timestamp);

    final bool isRead = message['isRead'] == true;
    final bool isDelivered = message['isDelivered'] == true;

    // Use more responsive margins for different screen sizes
    final double screenWidth = MediaQuery.of(context).size.width;
    final double maxWidth = screenWidth *
        (isMe ? 0.7 : 0.75); // Slightly narrower for sent messages

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Card(
          color: Colors.transparent,
          elevation: 0,
          margin: EdgeInsets.only(
            left: isMe ? 0 : 8,
            right: isMe ? 8 : 0,
            top: 4,
            bottom: 4,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
          child: Container(
            decoration: BoxDecoration(
              color: isMe ? sentBubbleColor : receivedBubbleColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft:
                    isMe ? const Radius.circular(18) : const Radius.circular(4),
                bottomRight:
                    isMe ? const Radius.circular(4) : const Radius.circular(18),
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _getMessageContent(context, message, messageType),
                  const SizedBox(
                      height:
                          4), // Increased space between message and timestamp
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
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
                                : (isDelivered
                                    ? Icons.done
                                    : Icons.access_time),
                            size: 12,
                            color: isRead
                                ? const Color(0xFF4FC3F7)
                                : Colors.grey[600],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // First get the ConnectionManager - this avoids the Provider error
    final connectionManager =
        Provider.of<ConnectionManager>(context, listen: false);

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: connectionManager.getChatMessageStream(),
      builder: (context, snapshot) {
        if (isConnecting &&
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
                      fontSize: fontSize - 2, color: Colors.grey[600]),
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
                  'Error loading messages\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: fontSize - 2, color: Colors.red),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: onRetry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: mainColor,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData ||
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
                      fontSize: fontSize - 2, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Text(
                  'Start the conversation by sending a message.\nYour messages will be received when a helper connects.',
                  style: TextStyle(
                      fontSize: fontSize - 4, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        try {
          final messages = snapshot.data!;

          return ListView.builder(
            reverse: true, // Show newest at the bottom
            itemCount: messages.length,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            itemBuilder: (context, index) {
              final message =
                  messages[messages.length - 1 - index]; // Reverse the order
              final isMe = message['senderId'] == currentUserId;
              final isSystem = message['senderId'] == 'system';

              final bool showDateSeparator = _shouldShowDateSeparator(
                  messages, messages.length - 1 - index);

              return Column(
                children: [
                  if (showDateSeparator) _buildDateSeparator(message),
                  isSystem
                      ? _buildSystemMessage(message)
                      : _buildMessageBubble(context, message, isMe),
                ],
              );
            },
          );
        } catch (e) {
          debugPrint('❌ Error parsing message data: $e');
          return Center(
            child: Text(
              'Error displaying messages. Try again.',
              style: TextStyle(fontSize: fontSize - 2, color: Colors.red),
            ),
          );
        }
      },
    );
  }
}

// New Message Input Bar Widget
class _MessageInputBar extends StatefulWidget {
  final Future<void> Function(String text) onSendTextMessage;
  final Future<void> Function(ImageSource source) onSendImageMessage;
  final Future<void> Function() onHandleAudioRecording;
  final VoidCallback onStartListening;
  final Color mainColor;

  const _MessageInputBar({
    Key? key,
    required this.onSendTextMessage,
    required this.onSendImageMessage,
    required this.onHandleAudioRecording,
    required this.onStartListening,
    required this.mainColor,
  }) : super(key: key);

  @override
  State<_MessageInputBar> createState() => _MessageInputBarState();
}

class _MessageInputBarState extends State<_MessageInputBar> {
  final TextEditingController _messageController = TextEditingController();
  bool _isComposing = false;

  @override
  void initState() {
    super.initState();
    _messageController.addListener(() {
      if (mounted) {
        setState(() {
          _isComposing = _messageController.text.isNotEmpty;
        });
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _handleSendPressed() {
    if (_messageController.text.trim().isNotEmpty) {
      widget.onSendTextMessage(_messageController.text.trim());
      _messageController.clear();
      FocusScope.of(context).unfocus(); // Hide keyboard
    }
  }

  void _showImageSourceOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(context);
                widget.onSendImageMessage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Select from gallery'),
              onTap: () {
                Navigator.pop(context);
                widget.onSendImageMessage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Access the BlindChatController to check recording state
    final controller = Provider.of<BlindChatController>(context);
    final bool isRecording = controller.isRecordingAudio;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      decoration: BoxDecoration(
        color:
            Theme.of(context).cardColor, // Use theme card color for background
      ),
      child: Row(
        children: <Widget>[
          // If recording, show a recording indicator
          if (isRecording)
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(24.0),
                  border: Border.all(color: Colors.red),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.mic, color: Colors.red),
                    const SizedBox(width: 8),
                    StreamBuilder<Duration>(
                      stream: controller.recordingDurationStream,
                      builder: (context, snapshot) {
                        if (controller.recordingDurationStream == null) {
                          return const Text(
                            'Recording...',
                            style: TextStyle(
                                color: Colors.red, fontWeight: FontWeight.bold),
                          );
                        }

                        final duration = snapshot.data ?? Duration.zero;
                        final minutes =
                            duration.inMinutes.toString().padLeft(2, '0');
                        final seconds = (duration.inSeconds % 60)
                            .toString()
                            .padLeft(2, '0');
                        return Text(
                          'Recording $minutes:$seconds',
                          style: const TextStyle(
                              color: Colors.red, fontWeight: FontWeight.bold),
                        );
                      },
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: () => controller.cancelAudioRecording(),
                      child: const Icon(Icons.close, color: Colors.red),
                    ),
                  ],
                ),
              ),
            )
          // Otherwise show normal input
          else
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[200], // Softer background for text field
                  borderRadius: BorderRadius.circular(24.0),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: TextField(
                          controller: _messageController,
                          decoration: InputDecoration(
                            hintText: 'Type a message...',
                            hintStyle: TextStyle(color: Colors.grey[500]),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (text) => _handleSendPressed(),
                          textCapitalization: TextCapitalization.sentences,
                          minLines: 1,
                          maxLines: 5, // Allow multi-line input
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.mic_outlined, color: Colors.grey[600]),
                      onPressed: widget.onHandleAudioRecording,
                      tooltip: 'Record Voice Message',
                    ),
                    IconButton(
                      icon: Icon(Icons.image_outlined, color: Colors.grey[600]),
                      onPressed: _showImageSourceOptions,
                      tooltip: 'Share Image',
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(width: 8.0),
          FloatingActionButton(
            mini: true,
            backgroundColor: widget.mainColor, // Use themed color
            onPressed: isRecording
                ? widget.onHandleAudioRecording // Stop recording if recording
                : (_isComposing ? _handleSendPressed : widget.onStartListening),
            tooltip: isRecording
                ? 'Send Voice Message'
                : (_isComposing ? 'Send Message' : 'Voice Input'),
            child: Icon(
              isRecording
                  ? Icons.send
                  : (_isComposing ? Icons.send : Icons.mic),
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// Full screen image viewer with zoom capabilities
class ImageFullScreenViewer extends StatefulWidget {
  final String imageUrl;

  const ImageFullScreenViewer({
    Key? key,
    required this.imageUrl,
  }) : super(key: key);

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
