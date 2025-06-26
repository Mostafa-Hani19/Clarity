import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:vibration/vibration.dart';
import '../../../../services/currency_detection_service.dart';

class BlindCurrencyDetectorScreen extends StatefulWidget {
  const BlindCurrencyDetectorScreen({super.key});

  @override
  State<BlindCurrencyDetectorScreen> createState() => _BlindCurrencyDetectorScreenState();
}

class _BlindCurrencyDetectorScreenState extends State<BlindCurrencyDetectorScreen> with WidgetsBindingObserver {
  final CurrencyDetectionService _currencyService = CurrencyDetectionService();
  final FlutterTts _flutterTts = FlutterTts();
  final ImagePicker _imagePicker = ImagePicker();
  
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  String _resultMessage = '';
  bool _isFlashOn = false;
  bool _isCameraPermissionDenied = false;
  String _cameraErrorMessage = '';
  double _currentZoomLevel = 1.0;
  double _minZoomLevel = 1.0;
  double _maxZoomLevel = 1.0;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeServices();
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _flutterTts.stop();
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle app lifecycle changes
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    
    if (state == AppLifecycleState.inactive) {
      _cameraController?.dispose();
      _isCameraInitialized = false;
    } else if (state == AppLifecycleState.resumed) {
      if (!_isCameraInitialized && !_isCameraPermissionDenied) {
        _initializeCamera();
      }
    }
  }
  
  Future<void> _initializeServices() async {
    try {
      // Initialize TTS first as it's needed for feedback
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      
      // Check camera permission
      await _requestCameraPermission();
      
      // Initialize currency detection service in the background
      // This prevents blocking the UI while the model loads
      Future.delayed(Duration.zero, () async {
        try {
          await _currencyService.initialize();
          debugPrint('Currency detection service initialized successfully');
        } catch (e) {
          debugPrint('Error initializing currency detection service: $e');
        }
      });
      
      // Speak welcome message
      _speak('currency_detector_welcome'.tr());
      
    } catch (e) {
      debugPrint('Error initializing services: $e');
      _handleError('Error initializing services: $e');
    }
  }
  
  Future<void> _requestCameraPermission() async {
    try {
      final status = await Permission.camera.request();
      if (status.isGranted) {
        await _initializeCamera();
      } else {
        setState(() {
          _isCameraPermissionDenied = true;
          _cameraErrorMessage = 'camera_permission_denied'.tr();
        });
        _speak('camera_permission_denied'.tr());
      }
    } catch (e) {
      debugPrint('Error requesting camera permission: $e');
      _handleError('Error requesting camera permission: $e');
    }
  }
  
  Future<void> _initializeCamera() async {
    try {
      // Reset error state
      setState(() {
        _cameraErrorMessage = '';
      });
      
      // Get available cameras
      _cameras = await availableCameras();
      
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() {
          _cameraErrorMessage = 'No cameras available on this device';
        });
        _speak('No cameras available on this device');
        return;
      }
      
      // Use the first back camera
      final backCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );
      
      // Initialize with medium resolution for better image quality while maintaining performance
      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      
      // Initialize the controller with a timeout
      bool initialized = false;
      try {
        await _cameraController!.initialize().timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw TimeoutException('Camera initialization timed out');
          },
        );
        initialized = true;
        
        // Configure camera for better quality after initialization
        await _configureCameraForBetterQuality();
      } catch (e) {
        debugPrint('Camera initialization error: $e');
        rethrow;
      }
      
      if (!initialized) {
        throw Exception('Failed to initialize camera controller');
      }
      
      if (!mounted) return;
      
      // Get available zoom levels
      _minZoomLevel = await _cameraController!.getMinZoomLevel();
      _maxZoomLevel = await _cameraController!.getMaxZoomLevel();
      _currentZoomLevel = 1.0;
      
      // Set initial zoom level for better currency detection (slightly zoomed in)
      if (_maxZoomLevel >= 1.5) {
        await _cameraController!.setZoomLevel(1.5);
        _currentZoomLevel = 1.5;
      }
      
      setState(() {
        _isCameraInitialized = true;
      });
      
      debugPrint('Camera initialized successfully with zoom range: $_minZoomLevel to $_maxZoomLevel');
    } catch (e) {
      debugPrint('Error initializing camera: $e');
      if (mounted) {
        setState(() {
          _cameraErrorMessage = 'Error initializing camera: $e';
          _isCameraInitialized = false;
        });
      }
      _speak('Error initializing camera');
    }
  }
  
  Future<void> _configureCameraForBetterQuality() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    
    try {
      // Set auto focus mode for better clarity
      await _cameraController!.setFocusMode(FocusMode.auto);
      
      // Set auto exposure mode for better lighting adaptation
      await _cameraController!.setExposureMode(ExposureMode.auto);
      
      // Set flash mode to auto if available
      await _cameraController!.setFlashMode(_isFlashOn ? FlashMode.torch : FlashMode.off);
      
      debugPrint('Camera configured for better quality');
    } catch (e) {
      debugPrint('Error configuring camera quality: $e');
    }
  }
  
  Future<void> _toggleFlash() async {
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      try {
        if (_isFlashOn) {
          await _cameraController!.setFlashMode(FlashMode.off);
          _speak('flash_off'.tr());
        } else {
          await _cameraController!.setFlashMode(FlashMode.torch);
          _speak('flash_on'.tr());
        }
        
        setState(() {
          _isFlashOn = !_isFlashOn;
        });
      } catch (e) {
        debugPrint('Error toggling flash: $e');
      }
    }
  }
  
  Future<void> _detectCurrency() async {
    if (_isProcessing || !_isCameraInitialized) return;

    setState(() {
      _isProcessing = true;
      _resultMessage = 'processing'.tr();
    });

    try {
      // Capture image
      final XFile imageFile = await _cameraController!.takePicture();
      
      // Process the captured image
      await _processCurrencyImage(File(imageFile.path));
    } catch (e) {
      debugPrint('Error capturing image: $e');
      _handleError('Error capturing image: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }
  
  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );

      if (pickedFile != null) {
        setState(() {
          _isProcessing = true;
          _resultMessage = 'processing'.tr();
        });
        
        await _processCurrencyImage(File(pickedFile.path));
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      _handleError('Error picking image: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }
  
  Future<void> _processCurrencyImage(File imageFile) async {
    try {
      // Process the image with the currency detection service
      final result = await _currencyService.detectCurrency(imageFile);
      
      String message;
      bool isCurrency = false;
      
      if (result['success'] == true) {
        if (result['isCurrency'] == true) {
          final label = result['label'];
          final confidence = result['confidence'] as double;
          final confidencePercent = (confidence * 100).toStringAsFixed(0);
          
          message = 'Currency detected: $label ($confidencePercent%)';
          isCurrency = true;
          
          // Provide feedback
          _speak('Currency detected: $label');
          if (await Vibration.hasVibrator() ?? false) {
            Vibration.vibrate(duration: 200);
          }
        } else {
          message = result['message'] ?? 'No currency detected';
          _speak('No currency detected');
        }
      } else {
        message = result['message'] ?? 'Error detecting currency';
        _speak('Error detecting currency');
      }
      
      if (mounted) {
        setState(() {
          _resultMessage = message;
        });
      }
      
    } catch (e) {
      debugPrint('Error processing image: $e');
      _handleError('Error processing image: $e');
    }
  }
  
  void _handleError(String errorMessage) {
    if (mounted) {
      setState(() {
        _resultMessage = errorMessage;
      });
      _speak(errorMessage);
      Vibration.vibrate(pattern: [0, 300, 100, 300]);
    }
  }
  
  Future<void> _speak(String text) async {
    try {
      await _flutterTts.stop();
      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint('TTS error: $e');
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      appBar: AppBar(
        title: Text('currency_detector'.tr()),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
          tooltip: 'back'.tr(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(20),
              ),
              margin: const EdgeInsets.all(16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: _buildCameraPreview(),
              ),
            ),
          ),
          
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.grey[800] : Colors.grey[200],
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                if (!_isProcessing && _resultMessage.isNotEmpty)
                  _buildResultIcon(_resultMessage),
                Text(
                  _isProcessing ? 'processing'.tr() : _resultMessage,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.white : Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'tap_to_detect'.tr(),
                  style: TextStyle(
                    fontSize: 16,
                    color: isDarkMode ? Colors.white70 : Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildActionButton(
                  icon: _isFlashOn ? Icons.flash_off : Icons.flash_on,
                  label: _isFlashOn ? 'flash_off'.tr() : 'flash_on'.tr(),
                  onPressed: _isCameraInitialized ? _toggleFlash : null,
                  color: Colors.amber,
                ),
                _buildActionButton(
                  icon: Icons.camera,
                  label: 'detect'.tr(),
                  onPressed: _isCameraInitialized ? _detectCurrency : null,
                  color: Colors.green,
                  isLarge: true,
                ),
                _buildActionButton(
                  icon: Icons.photo_library,
                  label: 'gallery'.tr(),
                  onPressed: _pickImageFromGallery,
                  color: Colors.blue,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildCameraPreview() {
    if (_isCameraPermissionDenied) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.no_photography, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _cameraErrorMessage,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _requestCameraPermission,
              child: Text('request_permission'.tr()),
            ),
          ],
        ),
      );
    }
    
    if (_cameraErrorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _cameraErrorMessage,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _initializeCamera,
              child: Text('retry'.tr()),
            ),
          ],
        ),
      );
    }
    
    if (_isCameraInitialized) {
      return Stack(
        alignment: Alignment.center,
        children: [
          // Camera preview
          CameraPreview(_cameraController!),
          
          // Currency alignment guide
          Center(
            child: Container(
              width: 200,
              height: 100,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          
          // Zoom controls
          if (_maxZoomLevel > _minZoomLevel)
            Positioned(
              right: 16,
              top: 0,
              bottom: 0,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.zoom_in, color: Colors.white, size: 32),
                    onPressed: _currentZoomLevel < _maxZoomLevel ? _zoomIn : null,
                    tooltip: 'Zoom in',
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_currentZoomLevel.toStringAsFixed(1)}x',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 8),
                  IconButton(
                    icon: const Icon(Icons.zoom_out, color: Colors.white, size: 32),
                    onPressed: _currentZoomLevel > _minZoomLevel ? _zoomOut : null,
                    tooltip: 'Zoom out',
                  ),
                ],
              ),
            ),
        ],
      );
    }
    
    return const Center(
      child: CircularProgressIndicator(color: Colors.white),
    );
  }
  
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    required Color color,
    bool isLarge = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: isLarge ? 80 : 60,
          height: isLarge ? 80 : 60,
          margin: const EdgeInsets.only(bottom: 8),
          child: ElevatedButton(
            onPressed: _isProcessing ? null : onPressed,
            style: ElevatedButton.styleFrom(
              shape: const CircleBorder(),
              padding: EdgeInsets.zero,
              backgroundColor: onPressed == null ? Colors.grey : color,
              foregroundColor: Colors.white,
            ),
            child: Icon(
              icon,
              size: isLarge ? 40 : 30,
            ),
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 14),
        ),
      ],
    );
  }
  
  Widget _buildResultIcon(String message) {
    if (message.contains('no_currency_detected'.tr()) || 
        message.contains('No currency detected')) {
      // No currency detected
      return Padding(
        padding: const EdgeInsets.only(bottom: 16.0),
        child: Icon(
          Icons.money_off,
          size: 48,
          color: Colors.red.shade400,
        ),
      );
    } else if (message.contains('Currency detected') || 
               message.contains('Pounds') || 
               message.contains('Dollars') || 
               message.contains('Euros')) {
      // Currency detected
      return Padding(
        padding: const EdgeInsets.only(bottom: 16.0),
        child: Icon(
          Icons.check_circle,
          size: 48,
          color: Colors.green.shade400,
        ),
      );
    } else if (message.contains('error') || message.contains('failed')) {
      // Error occurred
      return Padding(
        padding: const EdgeInsets.only(bottom: 16.0),
        child: Icon(
          Icons.error_outline,
          size: 48,
          color: Colors.amber.shade700,
        ),
      );
    }
    
    // Default case (no specific icon)
    return const SizedBox.shrink();
  }
  
  // Zoom control functions
  Future<void> _zoomIn() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    
    try {
      // Calculate new zoom level
      final newZoomLevel = _currentZoomLevel + 0.5;
      
      // Ensure we don't exceed max zoom
      if (newZoomLevel <= _maxZoomLevel) {
        await _cameraController!.setZoomLevel(newZoomLevel);
        setState(() {
          _currentZoomLevel = newZoomLevel;
        });
        
        // Provide feedback
        _speak('Zoomed in to ${newZoomLevel.toStringAsFixed(1)}x');
      } else {
        _speak('Maximum zoom reached');
      }
    } catch (e) {
      debugPrint('Error adjusting zoom: $e');
    }
  }

  Future<void> _zoomOut() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    
    try {
      // Calculate new zoom level
      final newZoomLevel = _currentZoomLevel - 0.5;
      
      // Ensure we don't go below min zoom
      if (newZoomLevel >= _minZoomLevel) {
        await _cameraController!.setZoomLevel(newZoomLevel);
        setState(() {
          _currentZoomLevel = newZoomLevel;
        });
        
        // Provide feedback
        _speak('Zoomed out to ${newZoomLevel.toStringAsFixed(1)}x');
      } else {
        _speak('Minimum zoom reached');
      }
    } catch (e) {
      debugPrint('Error adjusting zoom: $e');
    }
  }
}
