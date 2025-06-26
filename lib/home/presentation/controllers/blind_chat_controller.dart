import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../../../providers/auth_provider.dart';
import '../../../providers/chat_provider.dart';
import '../../../services/location_service.dart';
import '../../../services/video_call_service.dart';
import '../../../services/connectivity_service.dart';
import '../../../services/cloudinary_service.dart';
import '../../../services/audio_service.dart';

class BlindChatController with ChangeNotifier {
  final AuthProvider _authProvider;
  final ChatProvider _chatProvider;
  final LocationService _locationService = LocationService();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  final VideoCallService _videoCallService = VideoCallService();
  // ignore: unused_field
  final ConnectivityService _connectivityService;

  String? _currentUserId;
  String? get currentUserId => _currentUserId;

  String? _linkedUserId;
  String? get linkedUserId => _linkedUserId;

  String? _linkedUserName = "Assistant"; // Default or fetch
  String? get linkedUserName => _linkedUserName;

  String? _chatRoomId;
  String? get chatRoomId => _chatRoomId;

  bool _isConnecting = false;
  bool get isConnecting => _isConnecting;

  bool _isConnectionFailed = false;
  bool get isConnectionFailed => _isConnectionFailed;

  bool _isListening = false; // For STT
  bool get isListening => _isListening;
  
  Timer? _chatRefreshTimer;

  // TTS settings
  bool _ttsInitialized = false;

  String? _lastError;
  String? get lastError => _lastError;

  // Audio recording service
  final AudioService _audioService = AudioService();
  
  // Is audio recording in progress
  bool get isRecordingAudio => _audioService.isRecording;
  
  // Is audio playing
  bool get isPlayingAudio => _audioService.isPlaying;
  
  // Get recording duration stream
  Stream<Duration>? get recordingDurationStream {
    // Only return the stream if we're actually recording
    if (!_audioService.isRecording) return null;
    return _audioService.durationStream;
  }

  BlindChatController({
    required AuthProvider authProvider,
    required ChatProvider chatProvider,
    required ConnectivityService connectivityService,
  })  : _authProvider = authProvider,
        _chatProvider = chatProvider,
        _connectivityService = connectivityService {
    _initChatImmediately();
    _initTTS();
  }

  @override
  void dispose() {
    _chatRefreshTimer?.cancel();
    _flutterTts.stop();
    _audioService.dispose();
    // _speech.stop(); // If STT is active
    // _speech.cancel(); // If STT is active
    super.dispose();
  }

  Future<void> _initTTS() async {
    if (_ttsInitialized) return;
    try {
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setPitch(1.0);
      await _flutterTts.setSpeechRate(0.5);
      // Handle TTS speaking completion and errors if needed
      _flutterTts.setCompletionHandler(() {
        // Potentially update state or log
      });
      _flutterTts.setErrorHandler((msg) {
        debugPrint("TTS Error: $msg");
        // Potentially update state or show error
      });
      _ttsInitialized = true;
      debugPrint("✅ TTS Initialized");
    } catch (e) {
      debugPrint("❌ TTS Initialization Error: $e");
    }
  }

  Future<void> speak(String text) async {
    if (!_ttsInitialized) await _initTTS();
    try {
      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint("❌ TTS Speak Error: $e");
    }
  }

  void _initChatImmediately() {
    _currentUserId = _authProvider.currentUserId;
    _linkedUserId = _authProvider.linkedUserId;

    if (_currentUserId != null && _linkedUserId != null) {
      final List<String> userIds = [_currentUserId!, _linkedUserId!];
      userIds.sort();
      _chatRoomId = 'chat_${userIds.join('_')}';
      debugPrint('✅ Chat room ID created immediately by controller: $_chatRoomId');
      notifyListeners(); // Notify UI that basic IDs are set
      initChatInBackground();
    } else {
      initChatInBackground(); // Will handle linking issues
    }
  }

  Future<void> initChatInBackground() async { // Renamed for clarity, called by UI on retry
    _isConnecting = true;
    _isConnectionFailed = false;
    notifyListeners();

    try {
      debugPrint('🔄 Initializing chat in background by controller');
      _currentUserId = _authProvider.currentUserId;

      if (_currentUserId == null) {
        debugPrint('❌ Current user ID is null (controller)');
        throw Exception('User not logged in');
      }

      _linkedUserId = _authProvider.linkedUserId;
      if (_linkedUserId == null) {
        if (_linkedUserId == null) {
           debugPrint('❌ Not connected to a helper yet (controller) - AuthProvider did not provide linkedUserID');
           throw Exception('Not connected to a helper');
        }
      }
      
      debugPrint('🔄 Current user (controller): $_currentUserId');
      debugPrint('🔄 Linked helper (controller): $_linkedUserId');

      final List<String> userIds = [_currentUserId!, _linkedUserId!];
      userIds.sort();
      _chatRoomId = 'chat_${userIds.join('_')}';
      debugPrint('✅ Using chat room ID (controller): $_chatRoomId');

      // Fetch helper name if not already set or different from default
      if (_linkedUserName == "Assistant" || _linkedUserName == null) {
        try {
          final helperDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(_linkedUserId!)
              .get();
          if (helperDoc.exists) {
            final userData = helperDoc.data();
            if (userData != null && userData.containsKey('displayName')) {
              _linkedUserName = userData['displayName'] as String?;
              debugPrint('✅ Got helper name (controller): $_linkedUserName');
            }
          }
        } catch (e) {
          debugPrint('❌ Error getting helper name (controller): $e');
          // Keep default name or handle error
        }
      }

      await _chatProvider.createChatRoom(userIds);
      
      final messagesQuery = await FirebaseFirestore.instance
          .collection('chats')
          .doc(_chatRoomId)
          .collection('messages')
          .limit(1)
          .get();

      if (messagesQuery.docs.isEmpty) {
        await _chatProvider.addSystemMessage(
          chatRoomId: _chatRoomId!,
          text: 'Welcome to chat. Your helper will assist you.',
        );
        debugPrint('✅ Added welcome message by controller');
      }
      
      _startPeriodicReadReceipts();

      _isConnecting = false;
      _isConnectionFailed = false;
    } catch (e) {
      debugPrint('❌ Error initializing chat (controller): $e');
      _isConnecting = false;
      _isConnectionFailed = true;
    } finally {
      notifyListeners();
    }
  }
  
  void _startPeriodicReadReceipts() {
    _chatRefreshTimer?.cancel(); // Cancel existing
    _chatRefreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_chatRoomId != null && _currentUserId != null && _linkedUserId != null) {
        _chatProvider.markMessagesAsReadAndDelivered(
          chatRoomId: _chatRoomId!,
          currentUserId: _currentUserId!,
          otherUserId: _linkedUserId!,
        );
        debugPrint('🔄 Periodic read receipt update by controller');
      }
    });
  }

  // Placeholder for _initChatInBackground from original screen, might need to be public for retry
  Future<void> retryConnection() async {
    await initChatInBackground();
  }

  // Method to send a text message
  Future<bool> sendTextMessage(String text) async {
    _lastError = null;
    if (text.isEmpty) {
      _lastError = "Message cannot be empty.";
      notifyListeners();
      return false;
    }
    if (_chatRoomId == null || _currentUserId == null) {
      _lastError = "Chat not properly initialized.";
      notifyListeners();
      return false;
    }

    // Optional: Add connectivity check here using a dedicated service later
    // For now, relying on Firestore offline persistence primarily.

    _isConnecting = true; // Indicate network activity
    notifyListeners();

    try {
      await _chatProvider.sendTextMessage(
        chatRoomId: _chatRoomId!,
        text: text,
        senderId: _currentUserId!,
      );
      _isConnecting = false;
      notifyListeners();
      return true;
    } catch (e) {
      _lastError = "Failed to send message: ${e.toString()}";
      debugPrint("❌ Error sending text message (controller): $e");
      _isConnecting = false;
      notifyListeners();
      return false;
    }
  }

  // Method to send a location message
  Future<bool> sendLocationMessage() async {
    _lastError = null;
    if (_chatRoomId == null || _currentUserId == null) {
      _lastError = "Chat not properly initialized for location sharing.";
      notifyListeners();
      return false;
    }

    _isConnecting = true;
    notifyListeners();

    try {

      await _locationService.startTracking(); // Ensure tracking is active
      final locationData = _locationService.currentLocation; // Or a method like getCurrentLocation()

      if (locationData == null) {
        _lastError = "Failed to retrieve current location.";
        _isConnecting = false;
        notifyListeners();
        return false;
      }

      await _chatProvider.sendLocationMessage(
        chatRoomId: _chatRoomId!,
        senderId: _currentUserId!,
        latitude: locationData.latitude,
        longitude: locationData.longitude,
        // address: await _locationService.getAddress(locationData.latitude, locationData.longitude) // Optional: Get address
      );
      _isConnecting = false;
      notifyListeners();
      speak("Your location has been shared.");
      return true;
    } catch (e) {
      _lastError = "Failed to send location: ${e.toString()}";
      debugPrint("❌ Error sending location message (controller): $e");
      _isConnecting = false;
      notifyListeners();
      return false;
    }
  }
  
  // Method to send an image message
  Future<bool> sendImageMessage(ImageSource source) async {
    _lastError = null;
    if (_chatRoomId == null || _currentUserId == null) {
      _lastError = "Chat not properly initialized for image sharing.";
      notifyListeners();
      return false;
    }

    _isConnecting = true;
    notifyListeners();
    
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source, 
        imageQuality: 70,
        maxWidth: 1024,
      );
      
      if (image == null) {
        _lastError = "No image selected.";
        _isConnecting = false;
        notifyListeners();
        speak("No image was selected.");
        return false;
      }
      
      speak("Uploading your image. Please wait.");
      
      // Upload to Cloudinary
      final cloudinaryService = CloudinaryService();
      final imageUrl = await cloudinaryService.uploadImage(File(image.path));
      
      if (imageUrl == null) {
        _lastError = "Failed to upload image.";
        _isConnecting = false;
        notifyListeners();
        speak("Failed to upload your image. Please try again.");
        return false;
      }
      
      // Send image message
      await _chatProvider.sendImageMessage(
        chatRoomId: _chatRoomId!,
        senderId: _currentUserId!,
        imageUrl: imageUrl,
      );
      
      _isConnecting = false;
      notifyListeners();
      speak("Your image has been shared.");
      return true;
    } catch (e) {
      _lastError = "Failed to send image: ${e.toString()}";
      debugPrint("❌ Error sending image message (controller): $e");
      _isConnecting = false;
      notifyListeners();
      speak("Failed to share your image. Please try again.");
      return false;
    }
  }

  // Start recording audio
  Future<bool> startAudioRecording() async {
    _lastError = null;
    if (_chatRoomId == null || _currentUserId == null) {
      _lastError = "Chat not properly initialized for audio recording.";
      notifyListeners();
      return false;
    }
    
    try {
      debugPrint('🔍 BlindChatController - Starting audio recording');
      
      // Request permission before starting recording
      try {
        // Check if permission is granted using the permission_handler package
        if (!(await _requestMicrophonePermission())) {
          _lastError = "Microphone permission not granted.";
          
          // On Windows, offer to open privacy settings
          if (Platform.isWindows) {
            speak("Microphone access is not available. Please enable it in Windows settings.");
            // Don't show dialog here - it needs a BuildContext
            // We'll handle this in the UI layer
            _lastError = "windows_microphone_permission";
          } else {
            speak("Please grant microphone permission to record audio messages.");
          }
          
          notifyListeners();
          return false;
        }
      } catch (permissionError) {
        debugPrint('❌ BlindChatController - Permission error: $permissionError');
      }
      
      final success = await _audioService.startRecording();
      if (success) {
        notifyListeners();
        speak("Recording started. Tap to stop.");
        return true;
      } else {
        _lastError = "Failed to start recording.";
        
        // Check if this is a Windows platform to provide more specific guidance
        if (Platform.isWindows) {
          speak("Failed to start recording. Please check that your microphone is connected and enabled in Windows settings.");
          // Don't directly open settings here - set an error code for the UI to handle
          _lastError = "windows_microphone_error";
        } else {
          speak("Failed to start recording. Please check microphone permissions.");
        }
        
        notifyListeners();
        return false;
      }
    } catch (e) {
      _lastError = "Failed to start recording: ${e.toString()}";
      debugPrint("❌ BlindChatController - Error starting audio recording: $e");
      speak("Failed to start recording. Please try again.");
      notifyListeners();
      return false;
    }
  }
  
  // Request microphone permission
  Future<bool> _requestMicrophonePermission() async {
    try {
      // Import permission_handler at the top of the file if not already imported
      // import 'package:permission_handler/permission_handler.dart';
      
      debugPrint('🔍 BlindChatController - Requesting microphone permission on ${Platform.operatingSystem}');
      
      // For Windows platform, we need a different approach as permission_handler doesn't fully support Windows
      if (Platform.isWindows) {
        debugPrint('🔍 BlindChatController - On Windows, checking if recorder can access microphone directly');
        try {
          // Try to initialize the recorder directly to check if we have access
          final recorder = AudioRecorder();
          final hasAccess = await recorder.hasPermission();
          debugPrint('🔍 BlindChatController - Windows microphone access: $hasAccess');
          
          if (!hasAccess) {
            debugPrint('⚠️ BlindChatController - Windows microphone access denied. Please check Windows Privacy Settings');
            speak("Please enable microphone access in Windows Privacy Settings, then try again.");
          }
          
          return hasAccess;
        } catch (e) {
          debugPrint('❌ BlindChatController - Windows microphone check error: $e');
          return false;
        }
      }
      
      // For other platforms, use permission_handler
      // Check current permission status
      var status = await Permission.microphone.status;
      debugPrint('🔍 BlindChatController - Current microphone permission status: $status');
      
      if (status.isDenied) {
        // Request permission
        status = await Permission.microphone.request();
        debugPrint('🔍 BlindChatController - Requested microphone permission, result: $status');
      }
      
      return status.isGranted;
    } catch (e) {
      debugPrint('❌ BlindChatController - Error requesting microphone permission: $e');
      return false;
    }
  }
  
  // Stop recording and send the audio message
  Future<bool> stopAudioRecordingAndSend() async {
    if (!_audioService.isRecording) {
      debugPrint('❌ BlindChatController - Not recording, cannot stop');
      return false;
    }
    
    _isConnecting = true;
    notifyListeners();
    
    try {
      debugPrint('🔍 BlindChatController - Stopping audio recording');
      // Stop recording
      final recordingPath = await _audioService.stopRecording();
      
      if (recordingPath == null) {
        _lastError = "Recording failed.";
        debugPrint('❌ BlindChatController - Recording path is null after stopping');
        _isConnecting = false;
        notifyListeners();
        speak("Recording failed. Please try again.");
        return false;
      }
      
      debugPrint('✅ BlindChatController - Recording stopped, path: $recordingPath');
      
      // Check if the file exists
      final file = File(recordingPath);
      if (!await file.exists()) {
        _lastError = "Recording file not found.";
        debugPrint('❌ BlindChatController - Recording file does not exist: $recordingPath');
        _isConnecting = false;
        notifyListeners();
        speak("Recording failed. Please try again.");
        return false;
      }
      
      // Get file size for debugging
      final fileSize = await file.length();
      debugPrint('✅ BlindChatController - Recording file size: $fileSize bytes');
      
      // If recording is too short (less than 0.5 seconds), discard it
      if (_audioService.recordingDuration.inMilliseconds < 500) {
        await _audioService.cancelRecording();
        _lastError = "Recording must be at least 0.5 seconds.";
        debugPrint('❌ BlindChatController - Recording too short: ${_audioService.recordingDuration.inMilliseconds}ms');
        _isConnecting = false;
        notifyListeners();
        speak("Recording must be at least half a second. Please try again.");
        return false;
      }
      
      speak("Uploading your voice message. Please wait.");
      
      // Try to play the recording first to verify it's valid
      try {
        debugPrint('🔍 BlindChatController - Testing audio playback locally');
        final playable = await _audioService.playRecording();
        if (!playable) {
          debugPrint('⚠️ BlindChatController - Audio file not playable locally');
          // Continue anyway, it might still work after upload
        } else {
          // Stop playback since we were just testing
          await _audioService.stopAudio();
          debugPrint('✅ BlindChatController - Audio file is playable locally');
        }
      } catch (e) {
        debugPrint('⚠️ BlindChatController - Error testing audio playback: $e');
        // Continue anyway, it might still work after upload
      }
      
      // Upload directly using CloudinaryService instead of going through AudioService
      debugPrint('🔍 BlindChatController - Uploading audio using CloudinaryService');
      final cloudinaryService = CloudinaryService();
      final audioUrl = await cloudinaryService.uploadAudio(file);
      
      if (audioUrl == null) {
        // Try with AudioService as fallback
        debugPrint('⚠️ BlindChatController - CloudinaryService failed, trying AudioService');
        final backupUrl = await _audioService.uploadAudio(recordingPath);
        
        if (backupUrl == null) {
          _lastError = "Failed to upload audio.";
          debugPrint('❌ BlindChatController - Both upload methods failed');
          _isConnecting = false;
          notifyListeners();
          speak("Failed to upload your voice message. Please try again.");
          return false;
        } else {
          debugPrint('✅ BlindChatController - Backup upload successful: $backupUrl');
          
          // Send audio message
          debugPrint('🔍 BlindChatController - Sending audio message to chat');
          await _chatProvider.sendAudioMessage(
            chatRoomId: _chatRoomId!,
            senderId: _currentUserId!,
            audioUrl: backupUrl,
            durationMs: _audioService.recordingDuration.inMilliseconds,
          );
          
          debugPrint('✅ BlindChatController - Audio message sent successfully');
          _isConnecting = false;
          notifyListeners();
          speak("Your voice message has been sent.");
          return true;
        }
      }
      
      debugPrint('✅ BlindChatController - Audio uploaded, URL: $audioUrl');
      
      // Send audio message
      debugPrint('🔍 BlindChatController - Sending audio message to chat');
      await _chatProvider.sendAudioMessage(
        chatRoomId: _chatRoomId!,
        senderId: _currentUserId!,
        audioUrl: audioUrl,
        durationMs: _audioService.recordingDuration.inMilliseconds,
      );
      
      debugPrint('✅ BlindChatController - Audio message sent successfully');
      _isConnecting = false;
      notifyListeners();
      speak("Your voice message has been sent.");
      return true;
    } catch (e) {
      _lastError = "Failed to send voice message: ${e.toString()}";
      debugPrint("❌ BlindChatController - Error sending audio message: $e");
      _isConnecting = false;
      notifyListeners();
      speak("Failed to send your voice message. Please try again.");
      return false;
    }
  }
  
  // Cancel audio recording
  Future<void> cancelAudioRecording() async {
    if (!_audioService.isRecording) return;
    
    try {
      await _audioService.cancelRecording();
      notifyListeners();
      speak("Recording canceled.");
    } catch (e) {
      _lastError = "Failed to cancel recording: ${e.toString()}";
      debugPrint("❌ Error canceling audio recording (controller): $e");
    }
  }
  
  // Play audio from URL
  Future<bool> playAudio(String url) async {
    try {
      final success = await _audioService.playAudio(url);
      notifyListeners();
      return success;
    } catch (e) {
      _lastError = "Failed to play audio: ${e.toString()}";
      debugPrint("❌ Error playing audio (controller): $e");
      return false;
    }
  }
  
  // Stop audio playback
  Future<void> stopAudio() async {
    try {
      await _audioService.stopAudio();
      notifyListeners();
    } catch (e) {
      _lastError = "Failed to stop audio: ${e.toString()}";
      debugPrint("❌ Error stopping audio (controller): $e");
    }
  }

  // Method to toggle Speech-to-Text listening
  Future<void> toggleListening(BuildContext context) async { // context might be needed for stt.initialize()
    _lastError = null;
    if (!_speech.isAvailable) {
      bool available = await _speech.initialize(
        onStatus: (status) {
          debugPrint('STT Status: $status');
          if (status == stt.SpeechToText.listeningStatus) {
            _isListening = true;
          } else {
            _isListening = false;
          }
          notifyListeners();
        },
        onError: (errorNotification) {
          debugPrint('STT Error: ${errorNotification.errorMsg}');
          _lastError = "Speech recognition error: ${errorNotification.errorMsg}";
          _isListening = false;
          notifyListeners();
          speak("Sorry, I could not understand that. Please try again or type your message.");
        },
        // debugLogging: true, // Optional for more logs
      );
      if (!available) {
         _lastError = "Speech recognition is not available on this device.";
         notifyListeners();
         speak("Speech recognition is not available on this device.");
         return;
      }
    }

    if (_isListening) {
      await _speech.stop();
      _isListening = false;
      speak("Voice input stopped.");
    } else {
      // Clear previous error before starting
      _lastError = null;
      speak("Listening... please speak your message.");
      await _speech.listen(
        onResult: (result) {
          if (result.finalResult && result.recognizedWords.isNotEmpty) {
            sendTextMessage(result.recognizedWords);
            _isListening = false; // Stop listening indicator after final result
            notifyListeners();
          }
        },
        listenFor: const Duration(seconds: 30), // Adjust listening duration
        pauseFor: const Duration(seconds: 5),  // Adjust pause duration
        partialResults: false, // Set to true if you want partial results
        localeId: "en_US", // Set your desired locale
      );
      _isListening = true; // Ensure listening state is true when listen() is called
    }
    notifyListeners();
  }

  // Method to start a video call
  Future<bool> startVideoCall(BuildContext context) async {
    _lastError = null;
    if (_currentUserId == null || _linkedUserId == null || _linkedUserName == null) {
      _lastError = "Cannot start video call. Chat not fully initialized or assistant details missing.";
      notifyListeners();
      return false;
    }
    
    try {
      debugPrint("🔄 Starting video call from blind user $_currentUserId to helper $_linkedUserId");
      
      // Check if the helper exists in the helpers collection
      final helperDoc = await FirebaseFirestore.instance.collection('helpers').doc(_linkedUserId).get();
      if (!helperDoc.exists) {
        _lastError = "Helper account not found. Please try again later.";
        debugPrint("❌ Helper account not found: $_linkedUserId");
        speak("Cannot reach your helper. Please try again later.");
        notifyListeners();
        return false;
      }
      
      // Ensure we have the correct helper name
      String helperName = _linkedUserName!;
      if (helperDoc.data()?['displayName'] != null) {
        helperName = helperDoc.data()!['displayName'];
        debugPrint("📞 Using helper name from Firestore: $helperName");
      }
      
      // Initiate the call
      await _videoCallService.initiateCall(
        context,
        _currentUserId!,
        _linkedUserId!,
        helperName,
      );
      
      speak("Starting video call with your assistant.");
      notifyListeners();
      return true;
    } catch (e) {
      _lastError = "Failed to start video call: ${e.toString()}";
      debugPrint("❌ Error starting video call (controller): $e");
      speak("Failed to start video call. Please try again.");
      notifyListeners();
      return false;
    }
  }

  // Method to clear chat
  Future<bool> clearChat() async {
    _lastError = null;
    if (_chatRoomId == null) {
      _lastError = "Chat not properly initialized.";
      notifyListeners();
      return false;
    }

    _isConnecting = true;
    notifyListeners();

    try {
      // Use ChatProvider to clear the chat
      final success = await _chatProvider.clearChat(_chatRoomId!);
      
      if (success) {
        speak("Chat history has been cleared.");
      } else {
        _lastError = "Failed to clear chat history.";
      }
      
      _isConnecting = false;
      notifyListeners();
      return success;
    } catch (e) {
      _lastError = "Failed to clear chat: ${e.toString()}";
      debugPrint("❌ Error clearing chat (controller): $e");
      _isConnecting = false;
      notifyListeners();
      return false;
    }
  }

  // Show Windows microphone permission dialog
  Future<void> showWindowsMicrophonePermissionDialog(BuildContext context) async {
    if (!Platform.isWindows) return;
    
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Microphone Permission Required'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'This app needs access to your microphone to record audio messages.',
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 16),
              Text(
                'Please follow these steps:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('1. Click "Open Settings" below'),
              Text('2. Enable microphone access for this app'),
              Text('3. Return to the app and try again'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await _audioService.openWindowsMicrophoneSettings();
              },
              child: const Text('OPEN SETTINGS'),
            ),
          ],
        );
      },
    );
  }
} 