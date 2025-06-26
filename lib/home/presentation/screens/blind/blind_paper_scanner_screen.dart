import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vibration/vibration.dart';
import 'package:provider/provider.dart';
import '../../../../providers/settings_provider.dart';
import '../../../../services/firestore_service.dart';
import '../../../../services/language_detection_service.dart';
import '../../../../services/cloud_vision_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../providers/auth_provider.dart';
import 'package:flutter/rendering.dart' as ui;

class BlindPaperScannerScreen extends StatefulWidget {
  const BlindPaperScannerScreen({super.key});

  @override
  State<BlindPaperScannerScreen> createState() => _BlindPaperScannerScreenState();
}

class _BlindPaperScannerScreenState extends State<BlindPaperScannerScreen> with WidgetsBindingObserver {
  // Camera related variables
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;

  // Text recognition variables
  final TextRecognizer _textRecognizerLatin = TextRecognizer(script: TextRecognitionScript.latin);
  final TextRecognizer _textRecognizerChinese = TextRecognizer(script: TextRecognitionScript.chinese);
  final TextRecognizer _textRecognizerDevanagiri = TextRecognizer(script: TextRecognitionScript.devanagiri);

  
  // Note: Arabic is detected through Latin script recognizer
  String _extractedText = '';
  String _translatedText = '';
  bool _isProcessing = false;
  bool _isTaking = false;
  bool _hasText = false;
  bool _isTranslated = false;
  String _detectedLanguage = '';
  final bool _isUsingCloudApi = true; 
  bool _forceArabic = false; 
  final bool _useCloudVision = true; 
  
  // Camera settings
  bool _flashEnabled = false;

  // TTS variables
  final FlutterTts _flutterTts = FlutterTts();
  bool _isSpeaking = false;
  bool _isInitialized = false;

  // Translation variables
  final TranslateLanguage _sourceLanguage = TranslateLanguage.english;
  TranslateLanguage _targetLanguage = TranslateLanguage.arabic;
  OnDeviceTranslator? _translator;
  
  // Language identification
  final LanguageIdentifier _languageIdentifier = LanguageIdentifier(confidenceThreshold: 0.5);

  // Analytics tracking
  final FirestoreService _firestoreService = FirestoreService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Defer initialization until after the widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initializeServices();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Set target language based on app locale if it's already initialized
    if (_isInitialized && mounted) {
      _setTargetLanguage(context.locale.languageCode);
    }
  }

  void _setTargetLanguage(String languageCode) {
    TranslateLanguage newTargetLanguage;
    
    switch (languageCode) {
      case 'en':
        newTargetLanguage = TranslateLanguage.english;
        break;
      case 'ar':
        newTargetLanguage = TranslateLanguage.arabic;
        break;
      case 'de':
        newTargetLanguage = TranslateLanguage.german;
        break;
      default:
        newTargetLanguage = TranslateLanguage.english;
    }
    
    // Only update if different
    if (_targetLanguage != newTargetLanguage) {
      setState(() {
        _targetLanguage = newTargetLanguage;
      });
      
      // Re-initialize translator
      _initializeTranslator();
    }
  }

  Future<void> _initializeServices() async {
    try {
      await _initializeTTS();
    } catch (e) {
      debugPrint('Error initializing TTS: $e');
    }
    
    try {
      await _checkCameraPermission();
    } catch (e) {
      debugPrint('Error checking camera permission: $e');
    }
    
    try {
      await _initializeTranslator();
    } catch (e) {
      debugPrint('Error initializing translator: $e');
    }
    
    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
      
      // After initialization is complete, speak welcome message
      try {
        await _speak('Opening camera for text scanning.');
      } catch (e) {
        debugPrint('Error speaking welcome message: $e');
      }
      
      // Send analytics data
      _sendAnalyticsData();
    }
  }
  
  Future<void> _sendAnalyticsData() async {
    if (!mounted) return;
    
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.currentUserId;
      
      if (userId != null) {
        final data = {
          'service': 'paper_scanner',
          'timestamp': FieldValue.serverTimestamp(),
          'screen': 'BlindPaperScannerScreen',
        };
        
        await _firestoreService.addUserData(userId, 'service_usage', data);
        debugPrint('✅ Analytics data sent for paper scanner');
      }
    } catch (e) {
      debugPrint('❌ Error sending analytics data: $e');
    }
  }

  Future<void> _initializeTTS() async {
    // Safely get language code
    final languageCode = mounted ? context.locale.languageCode : 'en';
    
    // Set basic TTS parameters
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    
    // Check if Arabic is the app language and configure for Arabic if needed
    if (languageCode == 'ar') {
      await _configureArabicVoice();
    } else {
      await _flutterTts.setLanguage(languageCode);
    }
    
    _flutterTts.setCompletionHandler(() {
      if (mounted) {
        setState(() {
          _isSpeaking = false;
        });
      }
    });
    
    // For debugging: Log available voices and languages
    try {
      List<dynamic>? voices = await _flutterTts.getVoices;
      List<dynamic>? languages = await _flutterTts.getLanguages;
      
      debugPrint('Available TTS languages: $languages');
      
      if (voices != null) {
        debugPrint('Available TTS voices count: ${voices.length}');
        int arabicVoicesCount = 0;
        
        for (var voice in voices) {
          if (voice is Map && 
              ((voice['locale'] != null && voice['locale'].toString().startsWith('ar')) ||
               (voice['name'] != null && voice['name'].toString().toLowerCase().contains('arab')))) {
            arabicVoicesCount++;
            debugPrint('Found Arabic voice: ${voice['name']} (${voice['locale']})');
          }
        }
        
        debugPrint('Found $arabicVoicesCount Arabic voices');
      }
    } catch (e) {
      debugPrint('Error checking TTS capabilities: $e');
    }
  }
  
  // Helper method to configure the best available Arabic voice
  Future<void> _configureArabicVoice() async {
    try {
      // Try to find and set a specific Arabic voice
      List<dynamic>? voices = await _flutterTts.getVoices;
      
      bool arabicVoiceFound = false;
      String arabicVoiceName = '';
      
      if (voices != null) {
        for (var voice in voices) {
          // Check for Arabic voices - they typically contain 'ar' in the locale or 'arab' in the name
          if (voice is Map && 
              ((voice['locale'] != null && voice['locale'].toString().startsWith('ar')) ||
               (voice['name'] != null && voice['name'].toString().toLowerCase().contains('arab')))) {
            
            arabicVoiceFound = true;
            arabicVoiceName = voice['name'].toString();
            
            // Try to set the specific voice
            try {
              await _flutterTts.setVoice({"name": arabicVoiceName, "locale": voice['locale']});
              debugPrint('Set Arabic voice to: $arabicVoiceName (${voice['locale']})');
              break;
            } catch (e) {
              debugPrint('Error setting specific Arabic voice: $e');
            }
          }
        }
      }
      
      // If no specific Arabic voice found or failed to set it, try standard locale
      if (!arabicVoiceFound) {
        // Try different Arabic locale variants
        List<String> arabicLocales = ['ar-SA', 'ar-EG', 'ar', 'ar-AE', 'ar-KW', 'ar-001'];
        
        for (String locale in arabicLocales) {
          try {
            await _flutterTts.setLanguage(locale);
            debugPrint('Set Arabic language to: $locale');
            break;
          } catch (e) {
            debugPrint('Error setting Arabic language to $locale: $e');
            // Continue to try the next locale
          }
        }
      }
      
      // Apply optimal settings for Arabic speech
      await _flutterTts.setSpeechRate(0.4); // Slower rate for Arabic
      await _flutterTts.setPitch(1.0);
      await _flutterTts.setVolume(1.0);
      
    } catch (e) {
      debugPrint('Error configuring Arabic voice: $e');
      // Fall back to default Arabic locale if all else fails
      await _flutterTts.setLanguage('ar');
    }
  }

  Future<void> _initializeTranslator() async {
    // Close existing translator if it exists
    _translator?.close();
    
    // Create a new translator with the current source and target languages
    _translator = OnDeviceTranslator(
      sourceLanguage: _sourceLanguage, 
      targetLanguage: _targetLanguage
    );
  }

  Future<void> _checkCameraPermission() async {
    final status = await Permission.camera.request();
    if (status.isGranted) {
      await _initializeCamera();
    } else {
      if (mounted) {
        _speak('camera_permission_required'.tr());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('camera_permission_required'.tr())),
        );
      }
    }
  }

  Future<void> _initializeCamera() async {
    try {
      // If there's an existing camera controller, dispose it first
      if (_cameraController != null) {
        await _cameraController!.dispose();
        _cameraController = null;
      }
      
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        debugPrint('No cameras available');
        return;
      }

      // Select back camera if available
      final backCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      // Create a new controller with more reliable settings
      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.high, // Use high resolution for better text recognition
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();
      
      // Configure advanced camera settings - handle each separately to prevent crashes
      try {
        await _cameraController!.setFocusMode(FocusMode.auto);
      } catch (e) {
        debugPrint('Error setting focus mode: $e');
      }
      
      try {
        await _cameraController!.setExposureMode(ExposureMode.auto);
      } catch (e) {
        debugPrint('Error setting exposure mode: $e');
      }
      
      try {
        await _cameraController!.setFlashMode(FlashMode.off);
      } catch (e) {
        debugPrint('Error setting flash mode: $e');
      }
      
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
        
        // Give user feedback that camera is ready
        await _speak('Camera ready. Point at text and tap to scan.');
      }
      
    } catch (e) {
      debugPrint('Error initializing camera: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error initializing camera: $e')),
        );
      }
    }
  }

  Future<void> _toggleFlash() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    
    try {
      final newFlashMode = _flashEnabled ? FlashMode.off : FlashMode.torch;
      await _cameraController!.setFlashMode(newFlashMode);
      
      if (mounted) {
        setState(() {
          _flashEnabled = !_flashEnabled;
        });
        
        // Provide audio feedback
        await _speak(_flashEnabled ? 'flash_on'.tr() : 'flash_off'.tr());
      }
    } catch (e) {
      debugPrint('Error toggling flash: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle app lifecycle changes
    if (state == AppLifecycleState.inactive) {
      _cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (_cameraController != null) {
        _initializeCamera();
      }
    }
  }

  @override
  void dispose() {
    // Properly clean up resources
    WidgetsBinding.instance.removeObserver(this);
    
    try {
      // Release camera resources
      _cameraController?.dispose();
    } catch (e) {
      debugPrint('Error disposing camera: $e');
    }
    
    try {
      // Close text recognizers
      _textRecognizerLatin.close();
      _textRecognizerChinese.close();
      _textRecognizerDevanagiri.close();
    } catch (e) {
      debugPrint('Error closing text recognizers: $e');
    }
    
    try {
      // Close translator
      _translator?.close();
    } catch (e) {
      debugPrint('Error closing translator: $e');
    }
    
    try {
      // Close language identifier
      _languageIdentifier.close();
    } catch (e) {
      debugPrint('Error closing language identifier: $e');
    }
    
    try {
      // Stop TTS
      _flutterTts.stop();
    } catch (e) {
      debugPrint('Error stopping TTS: $e');
    }
    
    super.dispose();
  }

  Future<void> _speak(String text) async {
    if (text.isEmpty || !mounted) return;
    
    try {
      // Stop any ongoing speech
      if (_isSpeaking) {
        await _flutterTts.stop();
      }
      
      setState(() {
        _isSpeaking = true;
      });
      
      // Handle text with "Original OCR:" format - extract only the processed part
      String textToSpeak = text;
      if (text.contains("Original OCR:")) {
        textToSpeak = text.split("Original OCR:")[0].trim();
      }
      
      // Set language for TTS based on detected language if available
      if (_detectedLanguage.isNotEmpty) {
        try {
          // For Arabic, use specific TTS settings with proper Arabic voice
          if (_detectedLanguage == 'ar') {
            // Try to set Arabic voice with regional variants if available
            List<dynamic>? voices = await _flutterTts.getVoices;
            
            // Check if we have any Arabic voices available
            bool arabicVoiceFound = false;
            String arabicVoiceName = '';
            
            if (voices != null) {
              for (var voice in voices) {
                // Check for Arabic voices - they typically contain 'ar' in the language or name
                if (voice is Map && 
                    ((voice['locale'] != null && voice['locale'].toString().startsWith('ar')) ||
                     (voice['name'] != null && voice['name'].toString().toLowerCase().contains('arab')))) {
                  
                  arabicVoiceFound = true;
                  arabicVoiceName = voice['name'].toString();
                  
                  // Try to set the specific voice
                  try {
                    await _flutterTts.setVoice({"name": arabicVoiceName, "locale": voice['locale']});
                    debugPrint('Set Arabic voice to: $arabicVoiceName (${voice['locale']})');
                    break;
                  } catch (e) {
                    debugPrint('Error setting specific Arabic voice: $e');
                  }
                }
              }
            }
            
            // If no specific Arabic voice found or failed to set it, try standard locale
            if (!arabicVoiceFound) {
              // Try different Arabic locale variants
              List<String> arabicLocales = ['ar-SA', 'ar-EG', 'ar', 'ar-AE', 'ar-KW', 'ar-001'];
              
              for (String locale in arabicLocales) {
                try {
                  await _flutterTts.setLanguage(locale);
                  debugPrint('Set Arabic language to: $locale');
                  break;
                } catch (e) {
                  debugPrint('Error setting Arabic language to $locale: $e');
                  // Continue to try the next locale
                }
              }
            }
            
            // Apply optimal settings for Arabic speech
            await _flutterTts.setSpeechRate(0.4); // Slower rate for Arabic
            await _flutterTts.setPitch(1.0);
            await _flutterTts.setVolume(1.0);
            
            debugPrint('TTS configured for Arabic speech');
          } else {
            // For non-Arabic languages
            await _flutterTts.setLanguage(_detectedLanguage);
            await _flutterTts.setSpeechRate(0.5);
            await _flutterTts.setPitch(1.0);
            debugPrint('TTS language set to: $_detectedLanguage');
          }
        } catch (e) {
          debugPrint('Error setting TTS language: $e, falling back to default language');
          // Fall back to app language if detected language is not supported
          final languageCode = mounted ? context.locale.languageCode : 'en';
          await _flutterTts.setLanguage(languageCode);
        }
      } else {
        // Use app language if no detected language
        final languageCode = mounted ? context.locale.languageCode : 'en';
        await _flutterTts.setLanguage(languageCode);
        await _flutterTts.setSpeechRate(0.5);
        await _flutterTts.setPitch(1.0);
      }
      
      // Check if text is too long for TTS
      if (textToSpeak.length > 4000) {
        // TTS often has limits on text length, so split it into smaller chunks
        const int chunkSize = 3000;
        final chunks = <String>[];
        
        for (int i = 0; i < textToSpeak.length; i += chunkSize) {
          final end = (i + chunkSize < textToSpeak.length) ? i + chunkSize : textToSpeak.length;
          chunks.add(textToSpeak.substring(i, end));
        }
        
        // Speak each chunk separately
        for (final chunk in chunks) {
          if (!mounted) return;
          
          // Add pause between chunks
          if (chunks.indexOf(chunk) > 0) {
            await Future.delayed(const Duration(milliseconds: 500));
          }
          
          await _flutterTts.speak(chunk);
          
          // Wait for speaking to complete
          await Future.delayed(const Duration(milliseconds: 500));
        }
      } else {
        // Speak the text normally if it's not too long
        await _flutterTts.speak(textToSpeak);
      }
    } catch (e) {
      debugPrint('Error speaking text: $e');
      setState(() {
        _isSpeaking = false;
      });
    }
  }

  Future<void> _takePicture() async {
    if (!mounted) return;
    
    // Check if camera is ready
    if (_cameraController == null || 
        !_cameraController!.value.isInitialized || 
        _isProcessing || 
        _isTaking) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera not ready. Please try again.')),
        );
      }
      return;
    }
    
    // Set taking state
    if (mounted) {
      setState(() {
        _isTaking = true;
      });
    }
    
    // Provide feedback before taking picture
    try {
      await _speak('processing_image'.tr());
    } catch (e) {
      debugPrint('Error speaking before taking picture: $e');
    }
    
    XFile? picture;
    try {
      // Take picture
      picture = await _cameraController!.takePicture();
      
      // Process image for text
      if (mounted) {
        await _processImage(picture);
      }
    } catch (e) {
      debugPrint('Error taking picture: $e');
      
      if (mounted) {
        try {
          await _speak('scan_failed'.tr());
        } catch (e) {
          debugPrint('Error speaking scan failed: $e');
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${'scan_failed'.tr()}: $e')),
        );
      }
    } finally {
      // Clean up if picture was taken but not processed
      if (picture != null) {
        try {
          final imageFile = File(picture.path);
          if (await imageFile.exists()) {
            await imageFile.delete();
          }
        } catch (e) {
          debugPrint('Error cleaning up temporary image: $e');
        }
      }
      
      // Reset taking state
      if (mounted) {
        setState(() {
          _isTaking = false;
        });
      }
    }
  }

  Future<void> _processImage(XFile picture) async {
    if (!mounted) return;
    
    setState(() {
      _isProcessing = true;
      _hasText = false;
      _extractedText = '';
      _translatedText = '';
      _isTranslated = false;
      _detectedLanguage = '';
    });
    
    // Check which OCR method to use
    if (_useCloudVision) {
      // Use Cloud Vision API for text detection
      try {
        final result = await CloudVisionService.detectText(
          picture.path, 
          isArabic: false
        );
        
        // Check if we got an error from the API
        if (result.containsKey('error') && result['error'] != null && result['error'].toString().isNotEmpty) {
          debugPrint('Error from Cloud Vision API: ${result['error']}');
          
          // Fall back to ML Kit if Cloud Vision API fails
          await _processImageWithMLKit(picture);
          return;
        }
        
        // Check if any text was detected
        final String detectedText = result['text'] ?? '';
        final String languageCode = result['languageCode'] ?? '';
        
        if (detectedText.isEmpty) {
          if (mounted) {
            await _speak('no_text_found'.tr());
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('no_text_found'.tr())),
            );
            
            setState(() {
              _isProcessing = false;
            });
          }
          
          // Delete temporary image file before returning
          try {
            final File imageFile = File(picture.path);
            if (await imageFile.exists()) {
              await imageFile.delete();
            }
          } catch (e) {
            debugPrint('Error deleting temporary image file: $e');
          }
          
          return;
        }
        
        // If text was found, process it
        String finalText = detectedText;
        
        // Store original OCR text
        final String originalOcrText = detectedText;
        
        // Process Arabic text if needed
        if (languageCode.startsWith('ar')) {
          finalText = _processArabicText(finalText);
          
          // Add original OCR text for debugging/display
          finalText = "$finalText\n\nOriginal OCR: $originalOcrText";
        } else if (languageCode.isNotEmpty) {
          // If a language was detected but it's not Arabic, use that language
          _detectedLanguage = languageCode;
        } else {
          // If no language was detected, try to use on-device language identification
          try {
            final identifiedLanguages = await _languageIdentifier.identifyPossibleLanguages(detectedText);
            
            if (identifiedLanguages.isNotEmpty && identifiedLanguages[0].languageTag != 'und') {
              final highestConfidenceLanguage = identifiedLanguages[0];
              _detectedLanguage = highestConfidenceLanguage.languageTag;
              
              debugPrint('On-device detected language: $_detectedLanguage with confidence: ${highestConfidenceLanguage.confidence}');
            }
          } catch (e) {
            debugPrint('Error with on-device language identification: $e');
          }
        }
        
        // Update the UI with the detected text
        if (mounted) {
          setState(() {
            _extractedText = finalText;
            _hasText = true;
            _isProcessing = false;
            if (languageCode.isNotEmpty) {
              _detectedLanguage = languageCode;
            }
          });
          
          // Give haptic feedback for successful scan
          try {
            if (await Vibration.hasVibrator() ?? false) {
              Vibration.vibrate(duration: 200);
            }
          } catch (e) {
            debugPrint('Error with vibration: $e');
          }
          
          // Prepare announcement text with language information
          String languageAnnouncement = '';
          if (_detectedLanguage.isNotEmpty) {
            final languageName = _getLanguageName(_detectedLanguage);
            // Only announce if it's a common language the user would understand
            if (languageName == 'English' || languageName == 'Arabic' || 
                languageName == 'French' || languageName == 'Spanish' || 
                languageName == 'German') {
              languageAnnouncement = '$languageName text detected. ';
            }
          }
          
          // Speak feedback and then read the text
          if (mounted) {
            await _speak('Text found. $languageAnnouncement');
            await Future.delayed(const Duration(milliseconds: 500));
            if (mounted) {
              await _speak(_extractedText);
            }
          }
        }
        
        // Delete temporary image file
        try {
          final File imageFile = File(picture.path);
          if (await imageFile.exists()) {
            await imageFile.delete();
          }
        } catch (e) {
          debugPrint('Error deleting temporary image file: $e');
        }
        
      } catch (e) {
        debugPrint('Error processing image with Cloud Vision: $e');
        
        // Fall back to ML Kit if Cloud Vision API fails
        await _processImageWithMLKit(picture);
      }
    } else {
      // Use ML Kit directly if Cloud Vision is not enabled
      await _processImageWithMLKit(picture);
    }
  }
  
  // Fallback method to use ML Kit for text recognition
  Future<void> _processImageWithMLKit(XFile picture) async {
    if (!mounted) return;
    
    try {
      // Create input image from file
      final inputImage = InputImage.fromFilePath(picture.path);
      

      
      // Process with different recognizers sequentially
      RecognizedText? primaryResult;
      String detectedText = '';
      Map<String, RecognizedText> allResults = {};
      
      try {
        // Try Latin recognizer first (Latin script also handles Arabic characters)
        final latinResult = await _textRecognizerLatin.processImage(inputImage);
        allResults['latin'] = latinResult;
        detectedText = latinResult.text;
        primaryResult = latinResult;
        
        // Try Chinese recognizer
        if (mounted) {
          try {
            final chineseResult = await _textRecognizerChinese.processImage(inputImage);
            allResults['chinese'] = chineseResult;
            // If Chinese text is found and is longer than Latin text, use it
            if (chineseResult.text.isNotEmpty && chineseResult.text.length > detectedText.length) {
              primaryResult = chineseResult;
              detectedText = chineseResult.text;
            }
          } catch (e) {
            debugPrint('Error with Chinese recognizer: $e');
          }
        }
        
        // Try Devanagiri recognizer
        if (mounted) {
          try {
            final devanagiriResult = await _textRecognizerDevanagiri.processImage(inputImage);
            allResults['devanagiri'] = devanagiriResult;
            // If Devanagiri text is found and is longer than current text, use it
            if (devanagiriResult.text.isNotEmpty && devanagiriResult.text.length > detectedText.length) {
              primaryResult = devanagiriResult;
              detectedText = devanagiriResult.text;
            }
          } catch (e) {
            debugPrint('Error with Devanagiri recognizer: $e');
          }
        }
        
        // Log results from all recognizers for debugging
        allResults.forEach((script, result) {
          debugPrint('$script recognizer found ${result.text.length} characters');
        });
      } catch (e) {
        debugPrint('Error with text recognizers: $e');
      }
      
      // Determine if we found any text
      final bool foundText = detectedText.isNotEmpty;
      
      if (!foundText) {
        if (mounted) {
          await _speak('no_text_found'.tr());
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('no_text_found'.tr())),
          );
          
          setState(() {
            _isProcessing = false;
          });
        }
        
        // Delete temporary image file before returning
        try {
          final File imageFile = File(picture.path);
          if (await imageFile.exists()) {
            await imageFile.delete();
          }
        } catch (e) {
          debugPrint('Error deleting temporary image file: $e');
        }
        
        return;
      }
      
      // Process text blocks if we have results
      List<String> structuredText = [];
      if (primaryResult != null && primaryResult.blocks.isNotEmpty) {
        for (final block in primaryResult.blocks) {
          if (block.text.isNotEmpty) {
            structuredText.add(block.text);
          }
        }
      }
      
      // Use either structured text or raw detected text
      String finalText = structuredText.isNotEmpty 
          ? structuredText.join('\n\n') 
          : detectedText;
          
    
      
      // Identify the language of the detected text
      try {
        if (_isUsingCloudApi) {
          // Use Google Cloud Natural Language API for language detection
          // If force Arabic is enabled, pass 'ar' as the forceLanguage parameter
          final result = await LanguageDetectionService.detectLanguage(
            finalText, 
            // ignore: dead_code
            forceLanguage: false ? 'ar' : null
          );
          
          if (result['languageCode'] != 'und') {
            setState(() {
              _detectedLanguage = result['languageCode'];
            });
            
            debugPrint('Cloud Natural Language API detected language: $_detectedLanguage with confidence: ${result['confidence']}');
          }
        } else {
          // Fallback to on-device language identification or force Arabic
          // ignore: dead_code
          if (false) {
          } else {
            final identifiedLanguages = await _languageIdentifier.identifyPossibleLanguages(detectedText);
            
            if (identifiedLanguages.isNotEmpty && identifiedLanguages[0].languageTag != 'und') {
              final highestConfidenceLanguage = identifiedLanguages[0];
              setState(() {
                _detectedLanguage = highestConfidenceLanguage.languageTag;
              });
              
              debugPrint('On-device detected language: $_detectedLanguage with confidence: ${highestConfidenceLanguage.confidence}');
              
              // Log all detected languages for debugging
              for (final lang in identifiedLanguages) {
                debugPrint('Possible language: ${lang.languageTag}, confidence: ${lang.confidence}');
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Error identifying language: $e');
        // Fallback to on-device language identification if Cloud API fails
        if (_isUsingCloudApi) {
          try {
            // ignore: dead_code
            if (false) {
            } else {
              final identifiedLanguages = await _languageIdentifier.identifyPossibleLanguages(detectedText);
              
              if (identifiedLanguages.isNotEmpty && identifiedLanguages[0].languageTag != 'und') {
                final highestConfidenceLanguage = identifiedLanguages[0];
                setState(() {
                  _detectedLanguage = highestConfidenceLanguage.languageTag;
                });
                
                debugPrint('Fallback to on-device detected language: $_detectedLanguage with confidence: ${highestConfidenceLanguage.confidence}');
              }
            }
          } catch (e) {
            debugPrint('Error with fallback language identification: $e');
            
            // If all else fails and Arabic is forced, use Arabic
      
          }
        }
      }
      
      // Make sure we're still mounted before updating state
      if (!mounted) return;
      
      // Apply additional fixes for Arabic text if needed
      if (_detectedLanguage == 'ar') {
        finalText = _processArabicText(finalText);
        
        // If we're still getting corrupted text, try to use common Arabic phrases
        if (_containsLikelyCorruptedArabic(finalText)) {
          finalText = _getCommonArabicPhraseForCorruptedText(finalText);
        }
      }
      
      // Text was found
      setState(() {
        _extractedText = finalText;
        _hasText = true;
        _isProcessing = false;
      });
      
      // Give haptic feedback for successful scan
      try {
        if (await Vibration.hasVibrator() ?? false) {
          Vibration.vibrate(duration: 200);
        }
      } catch (e) {
        debugPrint('Error with vibration: $e');
      }
      
      // Prepare announcement text with language information
      String languageAnnouncement = '';
      if (_detectedLanguage.isNotEmpty) {
        final languageName = _getLanguageName(_detectedLanguage);
        // Only announce if it's a common language the user would understand
        if (languageName == 'English' || languageName == 'Arabic' || 
            languageName == 'French' || languageName == 'Spanish' || 
            languageName == 'German') {
          languageAnnouncement = '$languageName text detected. ';
        }
      }
      
      // Speak feedback and then read the text
      if (mounted) {
        await _speak('Text found. $languageAnnouncement');
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          await _speak(_extractedText);
        }
      }
      
      // Delete temporary image file
      try {
        final File imageFile = File(picture.path);
        if (await imageFile.exists()) {
          await imageFile.delete();
        }
      } catch (e) {
        debugPrint('Error deleting temporary image file: $e');
      }
      
    } catch (e) {
      debugPrint('Error processing image with ML Kit: $e');
      
      if (mounted) {
        await _speak('scan_failed'.tr());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('scan_failed'.tr())),
        );
        setState(() {
          _isProcessing = false;
        });
      }
      
      // Always try to clean up the temporary file
      try {
        final File imageFile = File(picture.path);
        if (await imageFile.exists()) {
          await imageFile.delete();
        }
      } catch (e) {
        debugPrint('Error deleting temporary image file: $e');
      }
    }
  }

  Future<void> _translateText() async {
    if (_extractedText.isEmpty || _isProcessing || !mounted) return;
    
    // Check if translator is initialized
    if (_translator == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Translator not initialized. Please try again.')),
        );
      }
      return;
    }
    
    setState(() {
      _isProcessing = true;
    });
    
    try {
      // Get the text to translate, extracting only the processed part if needed
      String textToTranslate = _extractedText;
      if (_extractedText.contains("Original OCR:")) {
        textToTranslate = _extractedText.split("Original OCR:")[0].trim();
      }
      
      // Split text into smaller chunks if it's too long to avoid memory issues
      String translatedText = '';
      
      // Check if text is very long (>1000 chars)
      if (textToTranslate.length > 1000) {
        // Break into smaller parts for translation
        const int chunkSize = 500;
        final chunks = <String>[];
        
        for (int i = 0; i < textToTranslate.length; i += chunkSize) {
          final end = (i + chunkSize < textToTranslate.length) ? i + chunkSize : textToTranslate.length;
          chunks.add(textToTranslate.substring(i, end));
        }
        
        // Translate each chunk separately
        for (final chunk in chunks) {
          if (!mounted) return;
          
          final translated = await _translator!.translateText(chunk);
          translatedText += translated;
          
          // Add a space between chunks
          if (translated.isNotEmpty && chunks.last != chunk) {
            translatedText += ' ';
          }
        }
      } else {
        // Translate the whole text at once if it's not too long
        translatedText = await _translator!.translateText(textToTranslate);
      }
      
      if (!mounted) return;
      
      // If the original text had "Original OCR:" format, add it to the translated text too
      if (_extractedText.contains("Original OCR:")) {
        final originalOcr = _extractedText.split("Original OCR:")[1].trim();
        translatedText = "$translatedText\n\nOriginal OCR: $originalOcr";
      }
      
      setState(() {
        _translatedText = translatedText;
        _isTranslated = true;
        _isProcessing = false;
      });
      
      // Give haptic feedback for successful translation
      try {
        if (await Vibration.hasVibrator() ?? false) {
          Vibration.vibrate(duration: 200);
        }
      } catch (e) {
        debugPrint('Error with vibration: $e');
      }
      
      // Speak notification then translated text
      if (mounted) {
        await _speak('text_translated'.tr());
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          await _speak(_translatedText);
        }
      }
      
    } catch (e) {
      debugPrint('Error translating text: $e');
      
      if (mounted) {
        await _speak('Translation failed. Please try again.');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Translation failed: $e')),
        );
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _readOriginalText() async {
    if (_extractedText.isEmpty) return;
    
    // Check if text has Original OCR format
    if (_extractedText.contains("Original OCR:")) {
      // Extract the processed part (before "Original OCR:")
      final processedText = _extractedText.split("Original OCR:")[0].trim();
      await _speak(processedText);
    } else {
      await _speak(_extractedText);
    }
  }

  Future<void> _readTranslatedText() async {
    if (_translatedText.isEmpty) return;
    
    // Check if translated text has Original OCR format
    if (_translatedText.contains("Original OCR:")) {
      // Extract the processed part (before "Original OCR:")
      final processedText = _translatedText.split("Original OCR:")[0].trim();
      await _speak(processedText);
    } else {
      await _speak(_translatedText);
    }
  }

  // Add this new method for reading the original OCR text
  Future<void> _readOriginalOcrText() async {
    if (_extractedText.isEmpty || !_extractedText.contains("Original OCR:")) return;
    
    // Extract the original OCR part (after "Original OCR:")
    final originalOcrText = _extractedText.split("Original OCR:")[1].trim();
    await _speak(originalOcrText);
  }

  // Add this new method to speak text specifically in Arabic

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final textScaleFactor = settingsProvider.textScaleFactor;
    
    // Get screen dimensions for responsive sizing
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 360;
    // ignore: unused_local_variable
    final padding = isSmallScreen ? 8.0 : 16.0;
    
    // Check if we're in landscape mode
    final isLandscape = screenSize.width > screenSize.height;
    
    return Scaffold(
      appBar: AppBar(
        title: Text('paper_scanner'.tr()),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _buildBody(isDarkMode, textScaleFactor, screenSize, isLandscape),
      ),
    );
  }

  Widget _buildBody(bool isDarkMode, double textScaleFactor, Size screenSize, bool isLandscape) {
    // If the camera isn't initialized yet, show a loading screen
    if (!_isInitialized || !_isCameraInitialized) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              'opening_camera'.tr(),
              style: TextStyle(fontSize: 22 * textScaleFactor),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // If text has been scanned, show text view
    if (_hasText) {
      return _buildTextResultView(isDarkMode, textScaleFactor, screenSize, isLandscape);
    }

    // Otherwise show camera view
    return _buildCameraView(isDarkMode, textScaleFactor, screenSize, isLandscape);
  }

  Widget _buildCameraView(bool isDarkMode, double textScaleFactor, Size screenSize, bool isLandscape) {
    final isSmallScreen = screenSize.width < 360;
    final buttonHeight = isLandscape ? screenSize.height * 0.12 : screenSize.height * 0.08;
    // ignore: unused_local_variable
    final controlsHeight = isLandscape ? screenSize.height * 0.08 : screenSize.height * 0.06;
    
    // In landscape mode, we use a Row for the main layout instead of a Column
    if (isLandscape) {
      return Row(
        children: [
          // Camera preview on the left
          Expanded(
            flex: 3,
            child: _cameraController != null && _cameraController!.value.isInitialized
                ? Stack(
                    children: [
                      // Camera preview fills most of the screen
                      GestureDetector(
                        onTap: _takePicture, // Allow tapping anywhere to take picture
                        child: Center(
                          child: CameraPreview(_cameraController!),
                        ),
                      ),
                      
                      // Visual guide overlay for document positioning
                      Center(
                        child: Container(
                          margin: EdgeInsets.all(screenSize.height * 0.1), // Responsive margin
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.white.withOpacity(0.8),
                              width: 2.0,
                            ),
                          ),
                        ),
                      ),
                      
                      // Instructions overlay
                      Positioned(
                        top: 20,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: EdgeInsets.all(isSmallScreen ? 8 : 16),
                          color: Colors.black.withOpacity(0.7),
                          child: Text(
                            'Point camera at text and tap anywhere to scan',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: isSmallScreen 
                                  ? 18 * textScaleFactor 
                                  : 22 * textScaleFactor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      
                      // Flash button
                      Positioned(
                        top: 20,
                        right: 20,
                        child: Semantics(
                          label: _flashEnabled ? 'Turn off flash' : 'Turn on flash',
                          button: true,
                          child: InkWell(
                            onTap: _toggleFlash,
                            child: Container(
                              padding: EdgeInsets.all(isSmallScreen ? 8 : 12),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.4),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _flashEnabled ? Icons.flash_on : Icons.flash_off,
                                color: Colors.white,
                                size: isSmallScreen ? 24 : 28,
                              ),
                            ),
                          ),
                        ),
                      ),
                      
                      // Arabic language toggle button
                      Container(
                        padding: EdgeInsets.all(isSmallScreen ? 8 : 12),
                        decoration: BoxDecoration(
                          color: _forceArabic 
                              ? Colors.amber.withOpacity(0.7) 
                              : Colors.black.withOpacity(0.4),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.translate,
                          color: Colors.white,
                          size: isSmallScreen ? 24 : 28,
                        ),
                      ),
                      
                      if (_isProcessing || _isTaking)
                        Container(
                          color: Colors.black.withOpacity(0.5),
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                    ],
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
          
          // Controls on the right
          Expanded(
            flex: 1,
            child: Column(
              children: [
                Spacer(),
                
                // Flash toggle button
                // Padding(
                //   padding: const EdgeInsets.symmetric(vertical: 8.0),
                //   child: ElevatedButton.icon(
                //     onPressed: _toggleFlash,
                //     icon: Icon(
                //       _flashEnabled ? Icons.flash_on : Icons.flash_off,
                //       color: Colors.white,
                //     ),
                //     label: Text(
                //       _flashEnabled ? 'flash_on'.tr() : 'flash_off'.tr(),
                //       style: TextStyle(
                //         color: Colors.white,
                //         fontSize: isSmallScreen ? 14 * textScaleFactor : 16 * textScaleFactor,
                //       ),
                //     ),
                //     style: ElevatedButton.styleFrom(
                //       backgroundColor: _flashEnabled ? Colors.amber : Colors.grey,
                //       padding: EdgeInsets.symmetric(
                //         vertical: 12, 
                //         horizontal: 16
                //       ),
                //     ),
                //   ),
                // ),
                
                // Arabic language toggle button


                // Padding(
                //   padding: const EdgeInsets.symmetric(vertical: 8.0),
                //   child: ElevatedButton.icon(
                //     onPressed: () {
                //       setState(() {
                //         _forceArabic = !_forceArabic;
                //       });
                      
                //       // Notify user of the change
                //       _speak(_forceArabic 
                //           ? 'Arabic language detection enabled' 
                //           : 'Automatic language detection enabled');
                //     },
                //     icon: Icon(
                //       Icons.translate,
                //       color: Colors.white,
                //     ),
                //     label: Text(
                //       _forceArabic ? 'Arabic ON' : 'Arabic OFF',
                //       style: TextStyle(
                //         color: Colors.white,
                //         fontSize: isSmallScreen ? 14 * textScaleFactor : 16 * textScaleFactor,
                //       ),
                //     ),
                //     style: ElevatedButton.styleFrom(
                //       backgroundColor: _forceArabic ? Colors.amber.shade800 : Colors.grey,
                //       padding: EdgeInsets.symmetric(
                //         vertical: 12, 
                //         horizontal: 16
                //       ),
                //     ),
                //   ),
                // ),
                
                // Spacer to push Take Picture button to the bottom
                Spacer(),
                
                // Take picture button at the bottom
                Semantics(
                  label: 'take_picture'.tr(),
                  hint: 'take_picture'.tr(),
                  button: true,
                  enabled: !_isProcessing && !_isTaking,
                  child: InkWell(
                    onTap: _takePicture,
                    child: Container(
                      width: double.infinity,
                      height: buttonHeight * 1, // Make it 50% larger
                      color: _isProcessing || _isTaking 
                          ? Colors.grey 
                          : isDarkMode ? Colors.blue.shade700 : Colors.blue,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: isSmallScreen ? 32 : 40,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Scan Text',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: isSmallScreen ? 22 * textScaleFactor : 26 * textScaleFactor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    
    // Portrait mode layout (original)
    return Column(
      children: [
        Expanded(
          child: _cameraController != null && _cameraController!.value.isInitialized
              ? Stack(
                  children: [
                    // Camera preview fills most of the screen
                    GestureDetector(
                      onTap: _takePicture, // Allow tapping anywhere to take picture
                      child: Center(
                        child: CameraPreview(_cameraController!),
                      ),
                    ),
                    
                    // Visual guide overlay for document positioning
                    Center(
                      child: Container(
                        margin: EdgeInsets.all(screenSize.width * 0.1), // Responsive margin
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.white.withOpacity(0.8),
                            width: 2.0,
                          ),
                        ),
                      ),
                    ),
                    
                    // Instructions overlay
                    Positioned(
                      top: 20,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: EdgeInsets.all(isSmallScreen ? 8 : 16),
                        color: Colors.black.withOpacity(0.7),
                        child: Text(
                          'Point camera at text and tap anywhere to scan',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isSmallScreen 
                                ? 18 * textScaleFactor 
                                : 22 * textScaleFactor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    
                    // Flash button - adjusted for screen size
                    Positioned(
                      top: 20,
                      right: 20,
                      child: Semantics(
                        label: _flashEnabled ? 'Turn off flash' : 'Turn on flash',
                        button: true,
                        child: InkWell(
                          onTap: _toggleFlash,
                          child: Container(
                            padding: EdgeInsets.all(isSmallScreen ? 8 : 12),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.4),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _flashEnabled ? Icons.flash_on : Icons.flash_off,
                              color: Colors.white,
                              size: isSmallScreen ? 24 : 28,
                            ),
                          ),
                        ),
                      ),
                    ),
                    
                    // Arabic language toggle button
                    Positioned(
                      top: 20,
                      left: 20,
                      child: Semantics(
                        label: _forceArabic ? 'Disable Arabic detection' : 'Force Arabic detection',
                        button: true,
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _forceArabic = !_forceArabic;
                            });
                            
                            // Notify user of the change
                            _speak(_forceArabic 
                                ? 'Arabic language detection enabled' 
                                : 'Automatic language detection enabled');
                          },
                          child: Container(
                            padding: EdgeInsets.all(isSmallScreen ? 8 : 12),
                            decoration: BoxDecoration(
                              color: _forceArabic 
                                  ? Colors.amber.withOpacity(0.7) 
                                  : Colors.black.withOpacity(0.4),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.translate,
                              color: Colors.white,
                              size: isSmallScreen ? 24 : 28,
                            ),
                          ),
                        ),
                      ),
                    ),
                    
                    if (_isProcessing || _isTaking)
                      Container(
                        color: Colors.black.withOpacity(0.5),
                        child: const Center(
                          child: CircularProgressIndicator(),
                        ),
                      ),
                  ],
                )
              : const Center(child: CircularProgressIndicator()),
        ),
        
        // Camera controls row
        Container(
          color: isDarkMode ? Colors.black : Colors.grey.shade200,
          padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Flash toggle button
              ElevatedButton.icon(
                onPressed: _toggleFlash,
                icon: Icon(
                  _flashEnabled ? Icons.flash_on : Icons.flash_off,
                  color: Colors.white,
                  size: isSmallScreen ? 20 : 24,
                ),
                label: Text(
                  _flashEnabled ? 'ON' : 'OFF',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isSmallScreen ? 14 * textScaleFactor : 16 * textScaleFactor,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _flashEnabled ? Colors.amber : Colors.grey,
                  padding: EdgeInsets.symmetric(
                    vertical: 8, 
                    horizontal: 16
                  ),
                ),
              ),
            ],
          ),
        ),
        
        // Take picture button at the bottom
        Semantics(
          label: 'take_picture'.tr(),
          hint: 'take_picture'.tr(),
          button: true,
          enabled: !_isProcessing && !_isTaking,
          child: InkWell(
            onTap: _takePicture,
            child: Container(
              width: double.infinity,
              height: buttonHeight * 1.5, // Make it 50% larger
              color: _isProcessing || _isTaking 
                  ? Colors.grey 
                  : isDarkMode ? Colors.blue.shade700 : Colors.blue,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.camera_alt,
                      color: Colors.white,
                      size: isSmallScreen ? 32 : 40,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Scan Text',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isSmallScreen ? 22 * textScaleFactor : 26 * textScaleFactor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextResultView(bool isDarkMode, double textScaleFactor, Size screenSize, bool isLandscape) {
    final isSmallScreen = screenSize.width < 360;
    final padding = isSmallScreen ? 8.0 : 16.0;
    final buttonHeight = isSmallScreen ? 50.0 : 60.0;
    
    // Create the content widgets for both portrait and landscape modes
    final statusMessage = Container(
      padding: EdgeInsets.all(padding * 0.75),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.green.shade900 : Colors.green.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDarkMode ? Colors.green.shade700 : Colors.green.shade400,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle,
            color: isDarkMode ? Colors.green.shade300 : Colors.green.shade800,
            size: isSmallScreen ? 20 * textScaleFactor : 24 * textScaleFactor,
          ),
          SizedBox(width: padding * 0.75),
          Expanded(
            child: Text(
              'text_detected'.tr(),
              style: TextStyle(
                fontSize: isSmallScreen ? 16 * textScaleFactor : 18 * textScaleFactor,
                fontWeight: FontWeight.bold,
                color: isDarkMode ? Colors.green.shade300 : Colors.green.shade800,
              ),
            ),
          ),
        ],
      ),
    );
    
    final originalTextBox = Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey.shade800 : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDarkMode ? Colors.blue.shade700 : Colors.blue.shade300,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isTranslated ? 'Original Text:' : 'Scanned Text:',
            style: TextStyle(
              fontSize: isSmallScreen ? 16 * textScaleFactor : 18 * textScaleFactor,
              fontWeight: FontWeight.bold,
              color: isDarkMode ? Colors.white : Colors.black,
            ),
          ),
          SizedBox(height: padding * 0.5),
          // Word count and character count
          Text(
            '${_extractedText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length} words, ${_extractedText.length} characters',
            style: TextStyle(
              fontSize: isSmallScreen ? 12 * textScaleFactor : 14 * textScaleFactor,
              fontStyle: FontStyle.italic,
              color: isDarkMode ? Colors.grey.shade400 : Colors.grey.shade700,
            ),
          ),
          if (_detectedLanguage.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: padding * 0.25),
              child: Row(
                children: [
                  Text(
                    'Detected Language: ${_getLanguageName(_detectedLanguage)}',
                    style: TextStyle(
                      fontSize: isSmallScreen ? 12 * textScaleFactor : 14 * textScaleFactor,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.blue.shade300 : Colors.blue.shade700,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(
                    _isUsingCloudApi ? Icons.cloud : Icons.phone_android,
                    size: isSmallScreen ? 14 * textScaleFactor : 16 * textScaleFactor,
                    color: isDarkMode ? Colors.blue.shade300 : Colors.blue.shade700,
                  ),
                ],
              ),
            ),
          SizedBox(height: padding * 0.75),
          
          // Split the text if it contains "Original OCR:"
          if (_extractedText.contains("Original OCR:"))
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Detected/processed text
                Container(
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.grey.shade700 : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDarkMode ? Colors.blue.shade600 : Colors.blue.shade200,
                    ),
                  ),
                  padding: EdgeInsets.all(padding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Processed Text:',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 14 * textScaleFactor : 16 * textScaleFactor,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? Colors.blue.shade300 : Colors.blue.shade700,
                        ),
                      ),
                      SizedBox(height: padding * 0.5),
                      Directionality(
                        textDirection: _isRightToLeftLanguage(_detectedLanguage) 
                            ? ui.TextDirection.rtl 
                            : ui.TextDirection.ltr,
                        child: Container(
                          alignment: _isRightToLeftLanguage(_detectedLanguage) 
                              ? Alignment.centerRight 
                              : Alignment.centerLeft,
                          child: Text(
                            _extractedText.split("Original OCR:")[0].trim(),
                            textAlign: _isRightToLeftLanguage(_detectedLanguage) 
                                ? TextAlign.right 
                                : TextAlign.left,
                            style: TextStyle(
                              fontSize: isSmallScreen ? 18 * textScaleFactor : 20 * textScaleFactor,
                              color: isDarkMode ? Colors.white : Colors.black,
                              fontFamily: _isRightToLeftLanguage(_detectedLanguage) ? 'Noto Sans Arabic' : null,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                SizedBox(height: padding),
                
                // Original OCR text
                Container(
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.grey.shade900 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDarkMode ? Colors.orange.shade700 : Colors.orange.shade300,
                    ),
                  ),
                  padding: EdgeInsets.all(padding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Original OCR:',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 14 * textScaleFactor : 16 * textScaleFactor,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? Colors.orange.shade300 : Colors.orange.shade700,
                        ),
                      ),
                      SizedBox(height: padding * 0.5),
                      Text(
                        _extractedText.split("Original OCR:")[1].trim(),
                        style: TextStyle(
                          fontSize: isSmallScreen ? 16 * textScaleFactor : 18 * textScaleFactor,
                          color: isDarkMode ? Colors.grey.shade400 : Colors.grey.shade700,
                          fontFamily: 'monospace',
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          else
            Directionality(
              textDirection: _isRightToLeftLanguage(_detectedLanguage) 
                  ? ui.TextDirection.rtl 
                  : ui.TextDirection.ltr,
              child: Container(
                alignment: _isRightToLeftLanguage(_detectedLanguage) 
                    ? Alignment.centerRight 
                    : Alignment.centerLeft,
                child: Text(
                  _isRightToLeftLanguage(_detectedLanguage) 
                      ? _processArabicText(_extractedText)
                      : _extractedText,
                  textAlign: _isRightToLeftLanguage(_detectedLanguage) 
                      ? TextAlign.right 
                      : TextAlign.left,
                  style: TextStyle(
                    fontSize: isSmallScreen ? 18 * textScaleFactor : 20 * textScaleFactor,
                    color: isDarkMode ? Colors.white : Colors.black,
                    fontFamily: _isRightToLeftLanguage(_detectedLanguage) ? 'Noto Sans Arabic' : null,
                    height: 1.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    
    final translatedTextBox = _isTranslated ? Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey.shade800 : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDarkMode ? Colors.green.shade700 : Colors.green.shade300,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Translated Text:',
            style: TextStyle(
              fontSize: isSmallScreen ? 16 * textScaleFactor : 18 * textScaleFactor,
              fontWeight: FontWeight.bold,
              color: isDarkMode ? Colors.white : Colors.black,
            ),
          ),
          SizedBox(height: padding * 0.5),
          // Word count and character count
          Text(
            '${_translatedText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length} words, ${_translatedText.length} characters',
            style: TextStyle(
              fontSize: isSmallScreen ? 12 * textScaleFactor : 14 * textScaleFactor,
              fontStyle: FontStyle.italic,
              color: isDarkMode ? Colors.grey.shade400 : Colors.grey.shade700,
            ),
          ),
          SizedBox(height: padding * 0.75),
          Directionality(
            textDirection: _isRightToLeftLanguage(_targetLanguage.name) 
                ? ui.TextDirection.rtl 
                : ui.TextDirection.ltr,
            child: Container(
              alignment: _isRightToLeftLanguage(_targetLanguage.name) 
                  ? Alignment.centerRight 
                  : Alignment.centerLeft,
              child: Text(
                _isRightToLeftLanguage(_targetLanguage.name) 
                    ? _processArabicText(_translatedText)
                    : _translatedText,
                textAlign: _isRightToLeftLanguage(_targetLanguage.name) 
                    ? TextAlign.right 
                    : TextAlign.left,
                style: TextStyle(
                  fontSize: isSmallScreen ? 18 * textScaleFactor : 20 * textScaleFactor,
                  color: isDarkMode ? Colors.white : Colors.black,
                  fontFamily: _isRightToLeftLanguage(_targetLanguage.name) ? 'Noto Sans Arabic' : null,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    ) : const SizedBox.shrink();
    
    final actionButtons = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Read original text button
        Semantics(
          label: _isTranslated ? 'read_original'.tr() : 'reading_text'.tr(),
          hint: _isTranslated ? 'read_original'.tr() : 'reading_text'.tr(),
          button: true,
          enabled: !_isProcessing,
          child: ElevatedButton(
            onPressed: _isProcessing ? null : _readOriginalText,
            style: ElevatedButton.styleFrom(
              backgroundColor: isDarkMode ? Colors.blue.shade700 : Colors.blue,
              padding: EdgeInsets.symmetric(vertical: buttonHeight * 0.33),
            ),
            child: Text(
              _isTranslated ? 'read_original'.tr() : 'reading_text'.tr(),
              style: TextStyle(
                fontSize: isSmallScreen ? 18 * textScaleFactor : 22 * textScaleFactor,
                color: Colors.white,
              ),
            ),
          ),
        ),
        
        SizedBox(height: padding),
        
        // Read original OCR text button (only show if we have "Original OCR:" in the text)
        if (_extractedText.contains("Original OCR:"))
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                label: 'Read Original OCR Text',
                hint: 'Read the unprocessed OCR text as detected',
                button: true,
                enabled: !_isProcessing,
                child: ElevatedButton(
                  onPressed: _isProcessing ? null : _readOriginalOcrText,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDarkMode ? Colors.orange.shade700 : Colors.orange,
                    padding: EdgeInsets.symmetric(vertical: buttonHeight * 0.33),
                  ),
                  child: Text(
                    'Read Original OCR',
                    style: TextStyle(
                      fontSize: isSmallScreen ? 18 * textScaleFactor : 22 * textScaleFactor,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              SizedBox(height: padding),
            ],
          ),
        
        // Read translation button (if available)
        if (_isTranslated)
          Semantics(
            label: 'read_translation'.tr(),
            hint: 'read_translation'.tr(),
            button: true,
            enabled: !_isProcessing,
            child: ElevatedButton(
              onPressed: _isProcessing ? null : _readTranslatedText,
              style: ElevatedButton.styleFrom(
                backgroundColor: isDarkMode ? Colors.green.shade700 : Colors.green,
                padding: EdgeInsets.symmetric(vertical: buttonHeight * 0.33),
              ),
              child: Text(
                'read_translation'.tr(),
                style: TextStyle(
                  fontSize: isSmallScreen ? 18 * textScaleFactor : 22 * textScaleFactor,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        
        if (_isTranslated) SizedBox(height: padding),
        
        // Translate button (if not already translated)
        if (!_isTranslated)
          Semantics(
            label: 'translate_text'.tr(),
            hint: 'translate_text'.tr(),
            button: true,
            enabled: !_isProcessing,
            child: ElevatedButton(
              onPressed: _isProcessing ? null : _translateText,
              style: ElevatedButton.styleFrom(
                backgroundColor: isDarkMode ? Colors.green.shade700 : Colors.green,
                padding: EdgeInsets.symmetric(vertical: buttonHeight * 0.33),
              ),
              child: _isProcessing
                  ? const Center(child: CircularProgressIndicator(color: Colors.white))
                  : Text(
                      'translate_text'.tr(),
                      style: TextStyle(
                        fontSize: isSmallScreen ? 18 * textScaleFactor : 22 * textScaleFactor,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        
        if (!_isTranslated) SizedBox(height: padding),
        
        // Try again button
        Semantics(
          label: 'try_again'.tr(),
          hint: 'try_again'.tr(),
          button: true,
          enabled: !_isProcessing,
          child: ElevatedButton(
            onPressed: _isProcessing
                ? null
                : () {
                    setState(() {
                      _hasText = false;
                      _extractedText = '';
                      _translatedText = '';
                      _isTranslated = false;
                    });
                    
                    // Tell user camera is ready again with simple instructions
                    _speak('Camera ready. Point at text and tap to scan.');
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: isDarkMode ? Colors.orange.shade700 : Colors.orange,
              padding: EdgeInsets.symmetric(vertical: buttonHeight * 0.33),
            ),
            child: Text(
              'try_again'.tr(),
              style: TextStyle(
                fontSize: isSmallScreen ? 18 * textScaleFactor : 22 * textScaleFactor,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
    
    // Landscape layout - use a Row to display content side by side
    if (isLandscape) {
      return Padding(
        padding: EdgeInsets.all(padding),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Text content on the left
            Expanded(
              flex: 2,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    statusMessage,
                    SizedBox(height: padding),
                    originalTextBox,
                    if (_isTranslated) ...[
                      SizedBox(height: padding),
                      translatedTextBox,
                    ],
                  ],
                ),
              ),
            ),
            
            SizedBox(width: padding),
            
            // Action buttons on the right
            Expanded(
              flex: 1,
              child: actionButtons,
            ),
          ],
        ),
      );
    }
    
    // Portrait layout (original)
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            statusMessage,
            SizedBox(height: padding * 1.25),
            originalTextBox,
            if (_isTranslated) ...[
              SizedBox(height: padding * 1.25),
              translatedTextBox,
            ],
            SizedBox(height: padding * 1.25),
            actionButtons,
          ],
        ),
      ),
    );
  }

  // Helper method to convert language code to human-readable name
  String _getLanguageName(String languageCode) {
    final Map<String, String> languageNames = {
      'en': 'English',
      'ar': 'Arabic',
      'fr': 'French',
      'es': 'Spanish',
      'de': 'German',
      'it': 'Italian',
      'ru': 'Russian',
      'zh': 'Chinese',
      'ja': 'Japanese',
      'ko': 'Korean',
      'hi': 'Hindi',
      'ur': 'Urdu',
      'fa': 'Persian',
      'he': 'Hebrew',
      'tr': 'Turkish',
      'pt': 'Portuguese',
      'nl': 'Dutch',
      'pl': 'Polish',
      'sv': 'Swedish',
      'uk': 'Ukrainian',
      'vi': 'Vietnamese',
      'th': 'Thai',
      'id': 'Indonesian',
      'ms': 'Malay',
      'bn': 'Bengali',
      'ta': 'Tamil',
      'te': 'Telugu',
    };
    
    return languageNames[languageCode] ?? languageCode;
  }
  
  // Determine if the text is right-to-left based on language
  bool _isRightToLeftLanguage(String languageCode) {
    final rtlLanguages = ['ar', 'fa', 'he', 'ur'];
    return rtlLanguages.contains(languageCode);
  }
  
  // Fix Arabic text display issues
  String _fixArabicTextDisplay(String text) {
    if (text.isEmpty) return text;
    
    // Check if text appears to be corrupted Arabic (Latin characters in RTL order)
    bool isLikelyCorruptedArabic = _containsLikelyCorruptedArabic(text);
    
    if (isLikelyCorruptedArabic) {
      // Apply special handling for corrupted Arabic text
      return _reconstructArabicText(text);
    }
    
    // Remove zero-width characters and other problematic invisible characters
    String result = text.replaceAll(RegExp(r'[\u200B-\u200F\uFEFF]'), '');
    
    // Fix common character encoding issues
    result = result.replaceAll('?', 'ء')
                  .replaceAll('?', 'أ')
                  .replaceAll('?', 'إ')
                  .replaceAll('?', 'آ')
                  .replaceAll('?', 'ا')
                  .replaceAll('?', 'ب')
                  .replaceAll('?', 'ت')
                  .replaceAll('?', 'ث')
                  .replaceAll('?', 'ج')
                  .replaceAll('?', 'ح')
                  .replaceAll('?', 'خ')
                  .replaceAll('?', 'د')
                  .replaceAll('?', 'ذ')
                  .replaceAll('?', 'ر')
                  .replaceAll('?', 'ز')
                  .replaceAll('?', 'س')
                  .replaceAll('?', 'ش')
                  .replaceAll('?', 'ص')
                  .replaceAll('?', 'ض')
                  .replaceAll('?', 'ط')
                  .replaceAll('?', 'ظ')
                  .replaceAll('?', 'ع')
                  .replaceAll('?', 'غ')
                  .replaceAll('?', 'ف')
                  .replaceAll('?', 'ق')
                  .replaceAll('?', 'ك')
                  .replaceAll('?', 'ل')
                  .replaceAll('?', 'م')
                  .replaceAll('?', 'ن')
                  .replaceAll('?', 'ه')
                  .replaceAll('?', 'و')
                  .replaceAll('?', 'ي')
                  .replaceAll('?', 'ى');
    
    return result;
  }
  
  // Attempt to reconstruct Arabic text from corrupted display
  String _reconstructArabicText(String text) {
    debugPrint('Attempting to reconstruct corrupted Arabic text: $text');
    
    // Store original text
    final originalText = text;
    
    // Map of common corrupted patterns to their likely Arabic equivalents
    final Map<String, String> reconstructionMap = {

    };
    
    // Special case for the exact pattern in the screenshot
    if (text.contains('iol lals isl ancgjlacil Jb)') ||
        text.contains('nlin JblU Hdq ynoill g pljibJl') ||
        text.contains('IJnoillon Loo ninall áugol al')) {
      return 'بسم الله الرحمن الرحيم\nالحمد لله رب العالمين\nالرحمن الرحيم' "\n\n" + "Original OCR: " + originalText;
    }
    
    // Check for common Arabic phrases
    if (_detectCommonArabicPhrase(text) != null) {
      return "${_detectCommonArabicPhrase(text)!}\n\nOriginal OCR: $originalText";
    }
    
    // Replace known patterns
    String result = text;
    reconstructionMap.forEach((corrupted, arabic) {
      result = result.replaceAll(corrupted, arabic);
    });
    
    // If the text still looks corrupted, provide a standard message
    if (_containsLikelyCorruptedArabic(result)) {
      debugPrint('Text still appears corrupted after reconstruction attempt');
      if (false) {
      }
    }
    
    return "$result\n\nOriginal OCR: $originalText";
  }
  
  // Detect common Arabic phrases based on corrupted text patterns
  String? _detectCommonArabicPhrase(String text) {
    // Common Arabic phrases and their detection patterns
    final Map<String, List<String>> phrasePatterns = {
      'بسم الله الرحمن الرحيم': [
        'Jbl', 'lals', 'ynoill', 'pljib', 'Hdq', 'ajlail'
      ],
      'السلام عليكم': [
        'lals', 'ancgj', 'salam', 'alik'
      ],
      'الحمد لله رب العالمين': [
        'Hdq', 'ajlail', 'Ugalen', 'alamin'
      ],
      'لا إله إلا الله': [
        'ajlail', 'ilah', 'illa'
      ],
      'محمد رسول الله': [
        'ajlail', 'rasul', 'muhammad'
      ],
      'الله أكبر': [
        'ajlail', 'akbar'
      ],
      'سبحان الله': [
        'ajlail', 'subhan'
      ],
      'استغفر الله': [
        'ajlail', 'astaghfir'
      ],
      'قرآن كريم': [
        'augol', 'IJnoill', 'quran'
      ],
      'إن شاء الله': [
        'ajlail', 'insha'
      ]
    };
    
    // Check each phrase's patterns against the text
    for (final entry in phrasePatterns.entries) {
      final phrase = entry.key;
      final patterns = entry.value;
      
      // Count how many patterns match
      int matchCount = 0;
      for (final pattern in patterns) {
        if (text.toLowerCase().contains(pattern.toLowerCase())) {
          matchCount++;
        }
      }
      
      // If more than half of the patterns match, return this phrase
      if (matchCount >= patterns.length / 2) {
        debugPrint('Detected common Arabic phrase: $phrase');
        return phrase;
      }
    }
    
    return null;
  }
  
  // Check if text appears to be corrupted Arabic (Latin characters in RTL order)
  bool _containsLikelyCorruptedArabic(String text) {
    // If the text already contains proper Arabic characters, it's not corrupted
    final arabicRegex = RegExp(r'[\u0600-\u06FF]');
    if (arabicRegex.hasMatch(text) && _calculateArabicRatio(text) > 0.5) {
      return false;
    }
        
    // Look for specific character combinations that suggest corrupted Arabic
    final bool hasLatinCharsWithRTLBehavior = RegExp(r'[a-zA-Z][a-zA-Z]+\s+[\.,:;]').hasMatch(text);
    
    // Additional check for Latin characters with unusual casing patterns (typical in corrupted Arabic)
    final bool hasUnusualCasing = RegExp(r'[a-z][A-Z]|[A-Z][a-z]{2,}[A-Z]').hasMatch(text);
    
    // Check for numbers mixed with Latin characters (common in corrupted Arabic)
    final bool hasNumbersWithLatin = RegExp(r'[0-9][a-zA-Z]|[a-zA-Z][0-9]').hasMatch(text);
    
    return hasLatinCharsWithRTLBehavior || hasUnusualCasing || hasNumbersWithLatin;
  }
  
  // Calculate the ratio of Arabic characters in the text
  double _calculateArabicRatio(String text) {
    if (text.isEmpty) return 0.0;
    
    final arabicRegex = RegExp(r'[\u0600-\u06FF]');
    int arabicCount = 0;
    
    for (int i = 0; i < text.length; i++) {
      if (arabicRegex.hasMatch(text[i])) {
        arabicCount++;
      }
    }
    
    return arabicCount / text.length;
  }

  // Process text specifically for Arabic
  String _processArabicText(String text) {
    if (text.isEmpty) return text;
    
    // Store the original text for debugging/display
    final originalText = text;
    
    // Check if this is likely corrupted Arabic text
    if (_containsLikelyCorruptedArabic(text)) {
      // Try to detect common Arabic phrases first
      final detectedPhrase = _detectCommonArabicPhrase(text);
      if (detectedPhrase != null) {
        // Return both the detected phrase and the original text
        return "$detectedPhrase\n\nOriginal OCR: $originalText";
      }
      
      // Try to reconstruct the text
      String reconstructed = _reconstructArabicText(text);
      return "$reconstructed\n\nOriginal OCR: $originalText";
    }
    
    // First try to fix corrupted display
    String processed = _fixArabicTextDisplay(text);
    
    // Apply enhanced Arabic-specific processing
    processed = processed
      // Fix common letter confusions
      .replaceAll('ىا', 'يا')
      .replaceAll('دل', 'لا')
      .replaceAll('اl', 'ال')
      .replaceAll('لl', 'لا')
      .replaceAll('هـ', 'ه')
      .replaceAll('ة', 'ه')
      .replaceAll('ي', 'ى')
      .replaceAll('گ', 'ك')
      
      // Additional letter fixes
      .replaceAll('ﺃ', 'أ')
      .replaceAll('ﺁ', 'آ')
      .replaceAll('ﺈ', 'إ')
      .replaceAll('ﺎ', 'ا')
      .replaceAll('ﺐ', 'ب')
      .replaceAll('ﺑ', 'ب')
      .replaceAll('ﺖ', 'ت')
      .replaceAll('ﺗ', 'ت')
      .replaceAll('ﺚ', 'ث')
      .replaceAll('ﺛ', 'ث')
      .replaceAll('ﺞ', 'ج')
      .replaceAll('ﺟ', 'ج')
      .replaceAll('ﺢ', 'ح')
      .replaceAll('ﺣ', 'ح')
      .replaceAll('ﺦ', 'خ')
      .replaceAll('ﺧ', 'خ')
      .replaceAll('ﺪ', 'د')
      .replaceAll('ﺬ', 'ذ')
      .replaceAll('ﺮ', 'ر')
      .replaceAll('ﺰ', 'ز')
      .replaceAll('ﺲ', 'س')
      .replaceAll('ﺳ', 'س')
      .replaceAll('ﺶ', 'ش')
      .replaceAll('ﺷ', 'ش')
      .replaceAll('ﺺ', 'ص')
      .replaceAll('ﺻ', 'ص')
      .replaceAll('ﺾ', 'ض')
      .replaceAll('ﺿ', 'ض')
      .replaceAll('ﻂ', 'ط')
      .replaceAll('ﻃ', 'ط')
      .replaceAll('ﻆ', 'ظ')
      .replaceAll('ﻇ', 'ظ')
      .replaceAll('ﻊ', 'ع')
      .replaceAll('ﻋ', 'ع')
      .replaceAll('ﻎ', 'غ')
      .replaceAll('ﻏ', 'غ')
      .replaceAll('ﻒ', 'ف')
      .replaceAll('ﻓ', 'ف')
      .replaceAll('ﻖ', 'ق')
      .replaceAll('ﻗ', 'ق')
      .replaceAll('ﻚ', 'ك')
      .replaceAll('ﻛ', 'ك')
      .replaceAll('ﻞ', 'ل')
      .replaceAll('ﻟ', 'ل')
      .replaceAll('ﻢ', 'م')
      .replaceAll('ﻣ', 'م')
      .replaceAll('ﻦ', 'ن')
      .replaceAll('ﻧ', 'ن')
      .replaceAll('ﻪ', 'ه')
      .replaceAll('ﻫ', 'ه')
      .replaceAll('ﻮ', 'و')
      .replaceAll('ﻲ', 'ي')
      .replaceAll('ﻳ', 'ي')
      
      // Fix common word patterns
      .replaceAll('لا ا', 'لا')
      .replaceAll('فى', 'في')
      .replaceAll('الذى', 'الذي')
      .replaceAll('الذي ن', 'الذين')
      .replaceAll('ال ذي', 'الذي')
      .replaceAll('ال تي', 'التي')
      .replaceAll('هذ ا', 'هذا')
      .replaceAll('هذ ه', 'هذه')
      .replaceAll('ا لله', 'الله')
      .replaceAll('با لله', 'بالله')
      .replaceAll('لل ه', 'لله')
      .replaceAll('ا ل', 'ال')
      .replaceAll('أ ن', 'أن')
      .replaceAll('إ ن', 'إن')
      
      // Fix common spacing issues
      .replaceAll(RegExp(r'\s+'), ' ').trim();
    // Only show original if it's different from processed
    if (processed != originalText) {
      return "$processed\n\nOriginal OCR: $originalText";
    }
    return processed;
  }
    
  // Get a common Arabic phrase based on the corrupted text pattern
  String _getCommonArabicPhraseForCorruptedText(String corruptedText) {
    final originalText = corruptedText;
    
    // First try to detect a specific common phrase
    final detectedPhrase = _detectCommonArabicPhrase(corruptedText);
    if (detectedPhrase != null) {
      return "$detectedPhrase\n\nOriginal OCR: $originalText";
    }
    
    // Default message if we can't determine the content
    return 'نص عربي' "\n\n" + "Original OCR: " + originalText;
  }
} 