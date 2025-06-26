import 'dart:io';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:provider/provider.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/settings_provider.dart';
import '../../../../services/gemini_chat_service.dart';
import '../../../../services/firestore_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vibration/vibration.dart';

class BlindAIChatScreen extends StatefulWidget {
  const BlindAIChatScreen({super.key});

  @override
  State<BlindAIChatScreen> createState() => _BlindAIChatScreenState();
}

class _BlindAIChatScreenState extends State<BlindAIChatScreen>
    with WidgetsBindingObserver {
  final GeminiChatService _geminiChatService = GeminiChatService();
  final FirestoreService _firestoreService = FirestoreService();
  final FlutterTts _flutterTts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  final ImagePicker _imagePicker = ImagePicker();

  bool _isListening = false;
  bool _isSending = false;
  bool _isInitialized = false;
  String _currentLanguage = 'en-US';
  bool _isProcessingImage = false;

  @override
  void initState() {
    super.initState();
    _initializeTTS();
    _initializeSpeech();
    _loadChatHistory();
    WidgetsBinding.instance.addObserver(this);

    // Send analytics data and provide orientation when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sendAnalyticsData();
      // Speak orientation guidance after a delay
      Future.delayed(const Duration(milliseconds: 1500), () {
        _speakOrientationGuidance();
      });
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _flutterTts.stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Stop listening if app goes to background
    if (state == AppLifecycleState.paused) {
      if (_isListening) {
        _speech.stop();
        setState(() => _isListening = false);
      }
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();

    // Wait for the UI to settle after orientation change
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        final orientation = MediaQuery.of(context).orientation;
        final isPortrait = orientation == Orientation.portrait;

        String orientationMessage = isPortrait
            ? 'switched_to_portrait'.tr()
            : 'switched_to_landscape'.tr();

        _speak(orientationMessage);

        // Provide detailed guidance after orientation change
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            _speakOrientationGuidance();
          }
        });
      }
    });
  }

  Future<void> _initializeTTS() async {
    await _flutterTts.setLanguage(_currentLanguage);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);

    setState(() {
      _isInitialized = true;
    });
  }

  Future<void> _initializeSpeech() async {
    try {
      bool available = await _speech.initialize(
        onStatus: _onSpeechStatus,
        onError: _onSpeechError,
      );

      debugPrint('Speech recognition initialization result: $available');

      if (available) {
        // Get available locales and try to match with current app locale
        var locales = await _speech.locales();
        var currentLocale = context.locale.languageCode;

        // Try to find a matching locale
        var matchingLocale = locales.firstWhere(
          (locale) => locale.localeId.startsWith(currentLocale),
          orElse: () => locales.first,
        );

        setState(() {
          _currentLanguage = matchingLocale.localeId;
        });

        debugPrint('Speech recognition set to locale: $_currentLanguage');
      } else {
        debugPrint('Speech recognition not available on this device');
        _addSystemMessage('speech_not_available'.tr());
      }
    } catch (e) {
      debugPrint('Error initializing speech recognition: $e');
      _addSystemMessage('speech_init_error'.tr());
    }
  }

  Future<void> _loadChatHistory() async {
    setState(() {
      _messages.add(
        ChatMessage(
          text: 'clarity_assistant_welcome'.tr(),
          isUser: false,
          timestamp: DateTime.now(),
        ),
      );
    });

    await _speak('clarity_assistant_welcome'.tr());
  }

  Future<void> _sendAnalyticsData() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.currentUserId;

      if (userId != null) {
        final data = {
          'service': 'ai_chat',
          'timestamp': FieldValue.serverTimestamp(),
          'screen': 'BlindAIChatScreen',
        };

        await _firestoreService.addUserData(userId, 'service_usage', data);
        debugPrint('✅ Analytics data sent for AI chat screen');
      }
    } catch (e) {
      debugPrint('❌ Error sending analytics data: $e');
    }
  }

  Future<void> _speak(String text) async {
    if (!_isInitialized) return;

    // Stop any ongoing speech and listening
    await _flutterTts.stop();
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
    }

    await _flutterTts.speak(text);
  }

  // Provide orientation guidance for blind users
  Future<void> _speakOrientationGuidance() async {
    final orientation = MediaQuery.of(context).orientation;
    final isPortrait = orientation == Orientation.portrait;

    String guidanceMessage = isPortrait
        ? 'blind_chat_orientation_portrait'.tr()
        : 'blind_chat_orientation_landscape'.tr();

    await _speak(guidanceMessage);
  }

  Future<void> _processVoiceInput(String input) async {
    if (input.isEmpty) return;

    // Add the user's spoken text to the chat
    setState(() {
      _messages.add(
        ChatMessage(
          text: input,
          isUser: true,
          timestamp: DateTime.now(),
        ),
      );
      _textController.clear(); // Clear the text controller
    });

    // Auto-scroll to bottom
    _scrollToBottom();

    // Process the input with AI
    await _processAIRequest(input);
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final settingsProvider = Provider.of<SettingsProvider>(context);

    // Get screen dimensions for responsive sizing
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 360;
    final padding = isSmallScreen ? 8.0 : 16.0;
    // ignore: unused_local_variable
    final iconSize = isSmallScreen ? 20.0 : 24.0;

    // Check if we're in landscape mode
    final isLandscape = screenSize.width > screenSize.height;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: isDarkMode ? Colors.grey.shade900 : Colors.blue,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDarkMode
                  ? [Colors.grey.shade900, Colors.grey.shade800]
                  : [Colors.blue.shade600, Colors.blue.shade800],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              backgroundColor: Colors.blue.shade700,
              child: Image.asset(
                'assets/images/whiteLogo.png',
                width: 30,
                height: 30,
              ),
            ),
            SizedBox(width: 8),
            Text(
              'clarity_assistant'.tr(),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 20,
                color: Colors.white,
              ),
            ),
          ],
        ),
          ),
      body: SafeArea(
        child: isLandscape
            ? _buildLandscapeLayout(isDarkMode, settingsProvider, screenSize,
                isSmallScreen, padding)
            : _buildPortraitLayout(isDarkMode, settingsProvider, screenSize,
                isSmallScreen, padding),
      ),
    );
  }

  Widget _buildPortraitLayout(
      bool isDarkMode,
      SettingsProvider settingsProvider,
      Size screenSize,
      bool isSmallScreen,
      double padding) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: EdgeInsets.all(padding),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final message = _messages[index];
              return _buildMessageBubble(
                message,
                isDarkMode,
                settingsProvider,
                isSmallScreen,
                screenSize,
              );
            },
          ),
        ),
        if (_isSending)
          Padding(
            padding: EdgeInsets.symmetric(vertical: padding * 0.5),
            child: const Center(child: CircularProgressIndicator()),
          ),
        _buildInputArea(isDarkMode, isSmallScreen, screenSize),
      ],
    );
  }

  Widget _buildLandscapeLayout(
      bool isDarkMode,
      SettingsProvider settingsProvider,
      Size screenSize,
      bool isSmallScreen,
      double padding) {
    // Use larger sizing for better blind accessibility
    final buttonSize = isSmallScreen ? 60.0 : 80.0;
    final iconSize = isSmallScreen ? 30.0 : 40.0;

    return Row(
      children: [
        // Messages take up more space on the left
        Expanded(
          flex: 2,
          child: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: EdgeInsets.all(padding),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[index];
                    return _buildMessageBubble(
                      message,
                      isDarkMode,
                      settingsProvider,
                      isSmallScreen,
                      screenSize,
                    );
                  },
                ),
              ),
              if (_isSending)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: padding * 0.5),
                  child: const Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),

        // Input area on the right - made larger and more accessible
        Expanded(
          flex: 1,
          child: Container(
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.grey[900] : Colors.grey[100],
              border: Border(
                left: BorderSide(
                  color: isDarkMode ? Colors.grey[800]! : Colors.grey[300]!,
                  width: 1,
                ),
              ),
            ),
            padding: EdgeInsets.all(padding),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Large microphone button centered for easy access
                _buildMicrophoneButton(isDarkMode, isSmallScreen, padding,
                    buttonSize: buttonSize * 1.4),

                SizedBox(height: padding * 2),

                // Text input with larger fonts
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _textController,
                    decoration: InputDecoration(
                      hintText: 'type_message'.tr(),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      fillColor: isDarkMode ? Colors.grey[800] : Colors.white,
                      filled: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: padding + 4,
                        vertical: 16,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(Icons.send,
                            size: iconSize * 0.6, color: Colors.blue.shade700),
                        onPressed: _sendMessage,
                      ),
                    ),
                    style: TextStyle(
                      fontSize: 18.0,
                    ),
                    maxLines: 3,
                    minLines: 1,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),

                SizedBox(height: padding * 2),

                // Larger camera button for better accessibility
                Semantics(
                  label: 'take_picture'.tr(),
                  button: true,
                  child: Container(
                    height: buttonSize * 0.8,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.green.shade400, Colors.green.shade700],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: () => _captureImage(ImageSource.camera),
                      icon: Icon(Icons.camera_alt, size: iconSize * 0.8),
                      label: Padding(
                        padding: EdgeInsets.all(padding),
                        child: Text(
                          'take_picture'.tr(),
                          style: TextStyle(
                            fontSize: 18.0,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        shadowColor: Colors.transparent,
                        padding:
                            EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ),

                SizedBox(height: padding),

                // Larger gallery button
                Semantics(
                  label: 'select_from_gallery'.tr(),
                  button: true,
                  child: Container(
                    height: buttonSize * 0.8,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.amber.shade400, Colors.amber.shade700],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.amber.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: () => _captureImage(ImageSource.gallery),
                      icon: Icon(Icons.photo_library, size: iconSize * 0.8),
                      label: Padding(
                        padding: EdgeInsets.all(padding),
                        child: Text(
                          'select_from_gallery'.tr(),
                          style: TextStyle(
                            fontSize: 18.0,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        shadowColor: Colors.transparent,
                        padding:
                            EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMessageBubble(
    ChatMessage message,
    bool isDarkMode,
    SettingsProvider settingsProvider,
    bool isSmallScreen,
    Size screenSize,
  ) {
    final textScaleFactor = settingsProvider.textScaleFactor;
    final padding = isSmallScreen ? 8.0 : 16.0;
    final avatarSize = isSmallScreen ? 32.0 : 40.0;
    final horizontalPadding = isSmallScreen ? 12.0 : 16.0;
    final verticalPadding = isSmallScreen ? 8.0 : 12.0;

    // Use different style for system messages
    if (message.isSystemMessage) {
      return Semantics(
        label: 'system_message'.tr(),
        value: message.text,
        child: Padding(
          padding: EdgeInsets.symmetric(
              vertical: padding * 0.5, horizontal: padding),
          child: Container(
            padding: EdgeInsets.all(padding * 0.8),
            decoration: BoxDecoration(
              color: isDarkMode
                  ? Colors.grey.shade800.withOpacity(0.5)
                  : Colors.grey.shade200.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDarkMode ? Colors.grey.shade700 : Colors.grey.shade300,
                width: 1,
              ),
            ),
            child: Text(
              message.text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize:
                    isSmallScreen ? 13 * textScaleFactor : 14 * textScaleFactor,
                color: isDarkMode ? Colors.grey.shade300 : Colors.grey.shade800,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      label: message.isUser ? 'your_message'.tr() : 'ai_response'.tr(),
      value: message.text,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: padding * 0.5),
        child: Row(
          mainAxisAlignment:
              message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!message.isUser)
              Container(
                margin: EdgeInsets.only(top: 4),
                child: SizedBox(
                  width: avatarSize,
                  height: avatarSize,
                  child: CircleAvatar(
                    backgroundColor: Colors.blue.shade600,
                    child: Container(
                      padding: EdgeInsets.all(6),
                      child: Image.asset(
                        'assets/images/whiteLogo.png',
                        width: avatarSize * 0.8,
                        height: avatarSize * 0.8,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            SizedBox(width: padding * 0.7),
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: screenSize.width * 0.75,
                ),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: verticalPadding,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: message.isUser
                          ? [Colors.blue.shade400, Colors.blue.shade700]
                          : isDarkMode
                              ? [Colors.grey.shade800, Colors.grey.shade900]
                              : [Colors.grey.shade200, Colors.grey.shade300],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: (message.isUser ? Colors.blue : Colors.grey)
                            .withOpacity(0.2),
                        blurRadius: 5,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (message.imageFile != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            decoration: BoxDecoration(
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Image.file(
                              message.imageFile!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                            ),
                          ),
                        ),
                        SizedBox(height: padding * 0.7),
                      ],
                      Text(
                        message.text,
                        style: TextStyle(
                          fontSize: isSmallScreen
                              ? 14 * textScaleFactor
                              : 16 * textScaleFactor,
                          color: message.isUser
                              ? Colors.white
                              : isDarkMode
                                  ? Colors.white
                                  : Colors.black,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: padding * 0.4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            _formatTimestamp(message.timestamp),
                            style: TextStyle(
                              fontSize: isSmallScreen
                                  ? 10 * textScaleFactor
                                  : 12 * textScaleFactor,
                              color: message.isUser
                                  ? Colors.white.withOpacity(0.8)
                                  : isDarkMode
                                      ? Colors.white.withOpacity(0.6)
                                      : Colors.black.withOpacity(0.6),
                            ),
                          ),
                          if (message.isUser)
                            Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Icon(
                                Icons.check_circle,
                                size: isSmallScreen ? 12 : 14,
                                color: Colors.white.withOpacity(0.8),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(width: padding * 0.7),
            if (message.isUser)
              Container(
                margin: EdgeInsets.only(top: 4),
                child: SizedBox(
                  width: avatarSize,
                  height: avatarSize,
                  child: CircleAvatar(
                    backgroundColor: Colors.green.shade600,
                    child: Container(
                      padding: EdgeInsets.all(isSmallScreen ? 2 : 4),
                      child: Icon(
                        Icons.person,
                        color: Colors.white,
                        size: avatarSize * 0.7,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea(bool isDarkMode, bool isSmallScreen, Size screenSize) {
    final padding = isSmallScreen ? 8.0 : 12.0;
    // Make buttons significantly larger for blind users
    final buttonSize = isSmallScreen ? 60.0 : 80.0;
    final iconSize = isSmallScreen ? 30.0 : 40.0;

    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[900] : Colors.grey[100],
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 2,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: Column(
        children: [
          // Add microphone button at the top of the input area
          _buildMicrophoneButton(isDarkMode, isSmallScreen, padding,
              buttonSize: buttonSize),

          SizedBox(height: padding),

          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _textController,
                    decoration: InputDecoration(
                      hintText: 'type_message'.tr(),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      fillColor: isDarkMode ? Colors.grey[800] : Colors.white,
                      filled: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: padding + 4,
                        vertical: isSmallScreen ? 8 : 12,
                      ),
                      isDense: isSmallScreen,
                      suffixIcon: IconButton(
                        icon: Icon(Icons.send, color: Colors.blue.shade700),
                        onPressed: _sendMessage,
                      ),
                    ),
                    style: TextStyle(
                      fontSize: isSmallScreen ? 14.0 : 16.0,
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: padding * 1.5),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: buttonSize * 0.7,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.green.shade400, Colors.green.shade700],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: () => _captureImage(ImageSource.camera),
                    icon: Icon(Icons.camera_alt, size: iconSize * 0.6),
                    label: Text(
                      'take_picture'.tr(),
                      style: TextStyle(
                        fontSize: isSmallScreen ? 16.0 : 18.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shadowColor: Colors.transparent,
                      padding: EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: padding),
              Expanded(
                child: Container(
                  height: buttonSize * 0.7,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.amber.shade400, Colors.amber.shade700],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.amber.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: () => _captureImage(ImageSource.gallery),
                    icon: Icon(Icons.photo_library, size: iconSize * 0.6),
                    label: Text(
                      'gallery'.tr(),
                      style: TextStyle(
                        fontSize: isSmallScreen ? 16.0 : 18.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shadowColor: Colors.transparent,
                      padding: EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    return '${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _processAIRequest(String input) async {
    setState(() {
      _isSending = true;
    });

    try {
      // Get language from context
      final language = context.locale.languageCode;

      // Get AI response
      final response =
          await _geminiChatService.sendMessage(input, language: language);

      if (mounted) {
        setState(() {
          _messages.add(
            ChatMessage(
              text: response,
              isUser: false,
              timestamp: DateTime.now(),
            ),
          );
          _isSending = false;
        });

        // Auto-scroll to bottom
        _scrollToBottom();

        // Read response aloud
        await _speak(response);
      }
    } catch (e) {
      debugPrint('Error getting AI response: $e');
      if (mounted) {
        setState(() {
          _isSending = false;
          _messages.add(
            ChatMessage(
              text: 'ai_error_message'.tr(),
              isUser: false,
              timestamp: DateTime.now(),
            ),
          );
        });

        // Read error message aloud
        await _speak('ai_error_message'.tr());
      }
    }
  }

  Future<void> _sendMessage() async {
    if (_textController.text.trim().isEmpty) return;

    final messageText = _textController.text.trim();
    _textController.clear();

    // Add user message to chat
    setState(() {
      _messages.add(
        ChatMessage(
          text: messageText,
          isUser: true,
          timestamp: DateTime.now(),
        ),
      );
    });

    // Process the message with AI
    await _processAIRequest(messageText);
  }

  Future<void> _captureImage(ImageSource source) async {
    if (_isProcessingImage) return;

    // Check camera permission if needed
    if (source == ImageSource.camera) {
      final status = await Permission.camera.request();
      if (status != PermissionStatus.granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('camera_permission_required'.tr())),
          );
        }
        return;
      }
    }

    // Stop listening while capturing image
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
    }

    // Provide audio feedback
    if (source == ImageSource.camera) {
      await _speak('taking_picture'.tr());
    } else {
      await _speak('selecting_image'.tr());
    }

    try {
      setState(() => _isProcessingImage = true);

      // Pick image
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 85,
      );

      if (pickedFile == null) {
        if (mounted) {
          await _speak('image_not_selected'.tr());
          setState(() => _isProcessingImage = false);
        }
        return;
      }

      // Provide haptic feedback
      if (await Vibration.hasVibrator()) {
        Vibration.vibrate(duration: 100);
      }

      // Add image message to chat
      final File imageFile = File(pickedFile.path);

      setState(() {
        _messages.add(
          ChatMessage(
            text: 'image_sent'.tr(),
            isUser: true,
            timestamp: DateTime.now(),
            imageFile: imageFile,
          ),
        );
        _isSending = true;
      });

      // Auto-scroll to bottom
      _scrollToBottom();

      // Provide audio feedback
      await _speak('processing_image'.tr());

      // Get language from context
      final language = context.locale.languageCode;

      // Process image with Gemini
      final response = await _geminiChatService.processImage(
        imageFile,
        language: language,
      );

      if (mounted) {
        setState(() {
          _messages.add(
            ChatMessage(
              text: response,
              isUser: false,
              timestamp: DateTime.now(),
            ),
          );
          _isSending = false;
          _isProcessingImage = false;
        });

        // Auto-scroll to bottom
        _scrollToBottom();

        // Read response aloud
        await _speak(response);
      }
    } catch (e) {
      debugPrint('Error capturing or processing image: $e');
      if (mounted) {
        setState(() {
          _isSending = false;
          _isProcessingImage = false;
          _messages.add(
            ChatMessage(
              text: 'image_processing_error'.tr(),
              isUser: false,
              timestamp: DateTime.now(),
            ),
          );
        });

        await _speak('image_processing_error'.tr());
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }


  Future<void> _listen() async {
    if (_speech.isListening) {
      debugPrint('Already listening, skipping listen call');
      return;
    }

    // Stop any ongoing TTS before listening
    await _flutterTts.stop();

    // Provide haptic feedback if available
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(duration: 100);
    }

    // Give audio feedback that we're listening
    await _speak('voice_listening_started'.tr());

    setState(() => _isListening = true);

    try {
      bool available = await _speech.initialize(
        onStatus: _onSpeechStatus,
        onError: _onSpeechError,
      );

      if (available) {
        // Use tts.stop() instead of speak to avoid interrupting the user
        await _flutterTts.stop();

        await _speech.listen(
          onResult: (result) {
            setState(() {
              _textController.text = result.recognizedWords;
              if (result.finalResult) {
                _isListening = false;
                if (_textController.text.isNotEmpty) {
                  // Provide haptic feedback to indicate recognition completed
                  // ignore: unnecessary_null_comparison
                  if (Vibration.hasVibrator() != null) {
                    Vibration.vibrate(duration: 200);
                  }

                  // Process input and respond immediately
                  final recognizedText = _textController.text;
                  _processVoiceInput(recognizedText);
                } else {
                  // If no text was recognized, inform the user
                  _speak('did_not_understand'.tr());
                  _addSystemMessage('did_not_understand'.tr());
                }
              }
            });
          },
          listenFor: const Duration(seconds: 10), // Give more time to speak
          pauseFor: const Duration(seconds: 2),
          localeId: _currentLanguage,
          listenMode: stt.ListenMode.confirmation,
          cancelOnError: false,
          partialResults: true, // Show interim results
        );
      } else {
        setState(() => _isListening = false);
        // Provide audio feedback about error
        await _speak('speech_not_available'.tr());
      }
    } catch (e) {
      debugPrint('Error starting speech recognition: $e');
      setState(() => _isListening = false);
      // Provide audio feedback about error
      await _speak('voice_error'.tr());
    }
  }

  // Callback for speech status changes
  void _onSpeechStatus(String status) {
    debugPrint('Speech status: $status');
    if ((status == stt.SpeechToText.doneStatus ||
            status == stt.SpeechToText.notListeningStatus) &&
        mounted) {
      setState(() {
        _isListening = false;
      });

      // Provide audio feedback when listening stops
      if (status == stt.SpeechToText.doneStatus &&
          _textController.text.isEmpty) {
        // Only announce if nothing was recognized
        // _speak('no_speech_detected'.tr());
        // _addSystemMessage('no_speech_detected'.tr());
      }
    }
  }

  // Callback for speech errors
  void _onSpeechError(dynamic error) {
    debugPrint('Speech error: $error');
    if (mounted) {
      setState(() {
        _isListening = false;
      });

      // Provide audio feedback about error
      _speak('voice_error'.tr());
    }
  }

  // Helper to add system messages to the chat
  void _addSystemMessage(String text) {
    setState(() {
      _messages.add(
        ChatMessage(
          text: text,
          isUser: false,
          timestamp: DateTime.now(),
          isSystemMessage: true,
        ),
      );
    });
    _scrollToBottom();
  }

  // microphone button
  Widget _buildMicrophoneButton(
      bool isDarkMode, bool isSmallScreen, double padding,
      {required double buttonSize}) {
    final iconSize = isSmallScreen ? 30.0 : 40.0;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: padding),
      decoration: BoxDecoration(
        color: isDarkMode
            ? Colors.grey.shade900
            : Colors.grey.shade100,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: Semantics(
          label: _isListening ? 'stop_listening'.tr() : 'start_listening'.tr(),
          button: true,
          enabled: true,
          excludeSemantics: true,
          child: GestureDetector(
            onTap: _isListening ? _speech.stop : _listen,
            child: Container(
              width: buttonSize * 1.2,
              height: buttonSize * 1.2,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _isListening
                      ? [Colors.redAccent, Colors.red.shade800]
                      : [Colors.blue.shade400, Colors.blue.shade800],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _isListening
                        ? Colors.red.withOpacity(0.4)
                        : Colors.blue.withOpacity(0.4),
                    blurRadius: 12,
                    spreadRadius: 2,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: _isListening
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          Icons.mic,
                          color: Colors.white,
                          size: iconSize * 1.2,
                        ),
                        SizedBox(
                          width: buttonSize * 1,
                          height: buttonSize * 1,
                          child: CircularProgressIndicator(
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                            strokeWidth: 4,
                          ),
                        ),
                        // Sound wave animation effect
                        AnimatedOpacity(
                          opacity: _isListening ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 300),
                          child: Container(
                            width: buttonSize * .5,
                            height: buttonSize * .5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withOpacity(0.5),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: buttonSize * 0.9,
                          height: buttonSize * 0.9,
                          decoration: BoxDecoration(
                            color: Colors.blue.shade300.withOpacity(0.3),
                            shape: BoxShape.circle,
                          ),
                        ),
                        Icon(
                          Icons.mic,
                          color: Colors.white,
                          size: iconSize * 1.2,
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final File? imageFile;
  final bool isSystemMessage;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.imageFile,
    this.isSystemMessage = false,
  });
}
