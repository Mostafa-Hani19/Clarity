import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/cloudinary_service.dart';

class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  
  final _audioRecorder = AudioRecorder();
  final _audioPlayer = AudioPlayer();
  
  bool _isRecording = false;
  bool _isPlaying = false;
  String? _currentRecordingPath;
  
  bool get isRecording => _isRecording;
  bool get isPlaying => _isPlaying;
  
  Duration _recordingDuration = Duration.zero;
  Duration get recordingDuration => _recordingDuration;
  
  Stream<Duration>? _durationStream;
  Stream<Duration>? get durationStream => _durationStream;
  
  AudioService._internal();
  
  /// Open Windows microphone privacy settings
  Future<bool> openWindowsMicrophoneSettings() async {
    if (!Platform.isWindows) return false;
    
    try {
      debugPrint('🔍 AudioService - Opening Windows microphone privacy settings');
      // This URI opens the Windows Settings app directly to the microphone privacy settings
      final Uri url = Uri.parse('ms-settings:privacy-microphone');
      final bool launched = await launchUrl(url);
      
      if (launched) {
        debugPrint('✅ AudioService - Windows microphone settings opened successfully');
      } else {
        debugPrint('❌ AudioService - Failed to open Windows microphone settings');
      }
      
      return launched;
    } catch (e) {
      debugPrint('❌ AudioService - Error opening Windows microphone settings: $e');
      return false;
    }
  }
  
  /// Start recording audio
  Future<bool> startRecording() async {
    try {
      // Check if already recording
      if (_isRecording) {
        debugPrint('❌ AudioService - Already recording');
        return false;
      }
      
      // Request permission
      debugPrint('🔍 AudioService - Checking recording permission');
      final hasPermission = await _audioRecorder.hasPermission();
      debugPrint('🔍 AudioService - Permission status: $hasPermission');
      
      if (!hasPermission) {
        debugPrint('❌ AudioService - Recording permission not granted');
        // Print platform-specific information
        if (Platform.isWindows) {
          debugPrint('⚠️ AudioService - On Windows, check microphone privacy settings');
        } else if (Platform.isIOS) {
          debugPrint('⚠️ AudioService - On iOS, check Info.plist for NSMicrophoneUsageDescription');
        } else if (Platform.isAndroid) {
          debugPrint('⚠️ AudioService - On Android, check AndroidManifest.xml for RECORD_AUDIO permission');
        }
        return false;
      }
      
      // Prepare recording path
      debugPrint('🔍 AudioService - Preparing recording path');
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String filePath = '${appDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
      debugPrint('✅ AudioService - Will record to: $filePath');
      
      // Reset duration tracking
      _recordingDuration = Duration.zero;
      final recordingStartTime = DateTime.now();
      
      // Configure audio recording with more detailed logging
      debugPrint('🔍 AudioService - Starting recorder with platform: ${Platform.operatingSystem}');
      try {
        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 128000,
            sampleRate: 44100,
          ),
          path: filePath,
        );
        debugPrint('✅ AudioService - Recorder started successfully');
      } catch (recorderError) {
        debugPrint('❌ AudioService - Error starting recorder: $recorderError');
        if (recorderError.toString().contains('permission')) {
          debugPrint('❌ AudioService - This appears to be a permission error');
        }
        rethrow;
      }
      
      _currentRecordingPath = filePath;
      _isRecording = true;
      
      // Track recording duration with more precision
      _durationStream = Stream.periodic(
        const Duration(milliseconds: 100),
        (_) => DateTime.now().difference(recordingStartTime),
      ).asBroadcastStream();
      
      // Update the recording duration based on the stream
      _durationStream?.listen((duration) {
        _recordingDuration = duration;
      });
      
      debugPrint('✅ AudioService - Recording started at: $filePath');
      return true;
    } catch (e) {
      debugPrint('❌ AudioService - Error starting recording: $e');
      
      // Try to print more debug info
      try {
        if (e is Exception) {
          debugPrint('❌ AudioService - Exception details: ${e.toString()}');
        }
      } catch (_) {}
      
      // Reset state
      _isRecording = false;
      _currentRecordingPath = null;
      return false;
    }
  }
  
  /// Stop recording audio
  /// Returns the path to the recorded audio file
  Future<String?> stopRecording() async {
    if (!_isRecording) return null;
    
    try {
      // Calculate final duration more accurately
      final finalDuration = _recordingDuration;
      debugPrint('✅ AudioService - Recording duration: ${finalDuration.inMilliseconds}ms');
      
      // Stop the recording
      final String? path = await _audioRecorder.stop();
      _isRecording = false;
      _currentRecordingPath = path;
      
      // Clear the duration stream
      _durationStream = null;
      
      // Log the results
      if (path != null) {
        debugPrint('✅ AudioService - Recording stopped successfully: $path');
        
        // Check the file
        try {
          final file = File(path);
          if (await file.exists()) {
            final size = await file.length();
            debugPrint('✅ AudioService - Recording file exists, size: $size bytes');
          } else {
            debugPrint('❌ AudioService - Warning: Recording file does not exist: $path');
          }
        } catch (e) {
          debugPrint('❌ AudioService - Error checking recording file: $e');
        }
      } else {
        debugPrint('❌ AudioService - Recording stopped but path is null');
      }
      
      return path;
    } catch (e) {
      debugPrint('❌ AudioService - Error stopping recording: $e');
      return null;
    }
  }
  
  /// Cancel current recording
  Future<void> cancelRecording() async {
    if (!_isRecording) return;
    
    try {
      await _audioRecorder.cancel();
      _isRecording = false;
      _currentRecordingPath = null;
      
      // Clear the duration stream
      _durationStream = null;
      
      debugPrint('✅ AudioService - Recording canceled');
    } catch (e) {
      debugPrint('❌ AudioService - Error canceling recording: $e');
    }
  }
  
  /// Play an audio file from a URL
  Future<bool> playAudio(String url) async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.setUrl(url);
      await _audioPlayer.play();
      _isPlaying = true;
      
      // Listen for playback completion
      _audioPlayer.playerStateStream.listen((state) {
        // Just update the state flag without doing any UI operations
        if (state.processingState == ProcessingState.completed) {
          _isPlaying = false;
        }
      });
      
      debugPrint('✅ AudioService - Playing audio: $url');
      return true;
    } catch (e) {
      debugPrint('❌ AudioService - Error playing audio: $e');
      return false;
    }
  }
  
  /// Play the current recorded audio file
  Future<bool> playRecording() async {
    if (_currentRecordingPath == null) return false;
    
    try {
      return await playAudio('file://$_currentRecordingPath');
    } catch (e) {
      debugPrint('❌ AudioService - Error playing recording: $e');
      return false;
    }
  }
  
  /// Stop audio playback
  Future<void> stopAudio() async {
    try {
      await _audioPlayer.stop();
      _isPlaying = false;
      debugPrint('✅ AudioService - Audio playback stopped');
    } catch (e) {
      debugPrint('❌ AudioService - Error stopping audio: $e');
    }
  }
  
  /// Upload audio file to Cloudinary
  Future<String?> uploadAudio(String filePath) async {
    try {
      debugPrint('🔍 AudioService - Starting audio upload to Cloudinary');
      final file = File(filePath);
      
      if (!await file.exists()) {
        debugPrint('❌ AudioService - Audio file does not exist: $filePath');
        return null;
      }
      
      // Get file size for debugging
      final fileSize = await file.length();
      debugPrint('✅ AudioService - Audio file size: $fileSize bytes');
      
      if (fileSize == 0) {
        debugPrint('❌ AudioService - Audio file is empty (0 bytes)');
        return null;
      }
      
      // Use CloudinaryService to upload the file
      debugPrint('🔍 AudioService - Using CloudinaryService to upload audio');
      final cloudinaryService = CloudinaryService();
      final audioUrl = await cloudinaryService.uploadAudio(file);
      
      if (audioUrl != null) {
        debugPrint('✅ AudioService - Audio uploaded successfully: $audioUrl');
        return audioUrl;
      } else {
        debugPrint('❌ AudioService - CloudinaryService failed to upload audio');
        return null;
      }
    } catch (e) {
      debugPrint('❌ AudioService - Error uploading audio: $e');
      // Try to print more debug info
      try {
        if (e is Exception) {
          debugPrint('❌ AudioService - Exception details: ${e.toString()}');
        }
      } catch (_) {}
      
      return null;
    }
  }
  
  /// Upload the current recording to Cloudinary
  Future<String?> uploadCurrentRecording() async {
    if (_currentRecordingPath == null) return null;
    return uploadAudio(_currentRecordingPath!);
  }
  
  /// Dispose resources
  void dispose() {
    _audioRecorder.dispose();
    _audioPlayer.dispose();
  }
} 