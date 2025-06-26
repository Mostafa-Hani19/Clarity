import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:easy_localization/easy_localization.dart';

class CurrencyDetectionService {
  static const int inputSize = 224;
  static const double threshold = 0.5;
  static const double noCurrencyThreshold =
      0.3; // Threshold to determine if no currency is present

  Interpreter? _interpreter;
  List<String>? _labels;
  bool _isInitializing = false;
  bool _isInitialized = false;
  String? _initError;

  // Singleton pattern
  static final CurrencyDetectionService _instance =
      CurrencyDetectionService._internal();
  factory CurrencyDetectionService() => _instance;
  CurrencyDetectionService._internal();

  Future<void> initialize() async {
    // Prevent multiple simultaneous initialization attempts
    if (_isInitializing) {
      debugPrint('Currency detection service is already initializing');
      return;
    }

    // Skip if already initialized successfully
    if (_isInitialized && _initError == null) {
      debugPrint('Currency detection service is already initialized');
      return;
    }

    _isInitializing = true;
    _initError = null;

    try {
      // Load labels from assets
      try {
        final labelsData =
            await rootBundle.loadString('assets/assets/labels.txt');
        _labels =
            labelsData.split('\n').where((label) => label.isNotEmpty).toList();
        debugPrint('Labels loaded successfully: ${_labels?.join(', ')}');
      } catch (e) {
        debugPrint('Error loading labels: $e');
        throw Exception('Failed to load currency labels: $e');
      }

      // Load TFLite model
      try {
        _interpreter =
            await Interpreter.fromAsset('assets/assets/currency_model.tflite');
        debugPrint('TFLite model loaded successfully');
      } catch (e) {
        debugPrint('Error loading TFLite model: $e');
        throw Exception('Failed to load currency detection model: $e');
      }

      _isInitialized = true;
      debugPrint('Currency detection service initialized successfully');
    } catch (e) {
      _initError = e.toString();
      debugPrint('Error initializing currency detection service: $e');
      _isInitialized = false;
      throw Exception('Failed to initialize currency detection service: $e');
    } finally {
      _isInitializing = false;
    }
  }

  Future<Map<String, dynamic>> detectCurrency(File imageFile) async {
    // Try to initialize if not already initialized
    if (!_isInitialized || _interpreter == null || _labels == null) {
      try {
        await initialize();
      } catch (e) {
        return {
          'success': false,
          'message': 'Service initialization failed: ${_initError ?? e}'
        };
      }
    }

    // Double-check initialization status
    if (!_isInitialized || _interpreter == null || _labels == null) {
      return {
        'success': false,
        'message': 'Currency detection service is not initialized'
      };
    }

    img.Image? image;
    try {
      // Step 1: Read and decode the image
      final imageBytes = await imageFile.readAsBytes();
      image = img.decodeImage(imageBytes);

      if (image == null) {
        return {'success': false, 'message': 'Failed to decode image'};
      }
    } catch (e) {
      debugPrint('Error decoding image: $e');
      return {'success': false, 'message': 'Failed to decode image: $e'};
    }

    try {
      // Step 2: Prepare input data for the model
      final input = _prepareInput(image);

      // Step 3: Prepare output container
      final output =
          List.filled(_labels!.length, 0.0).reshape([1, _labels!.length]);

      // Step 4: Run inference
      _interpreter!.run(input, output);

      // Step 5: Process results
      final scores = List<double>.from(output[0]);
      final maxScore = scores.reduce((a, b) => a > b ? a : b);
      final maxIndex = scores.indexOf(maxScore);
      final confidence = output[0][maxIndex];

      debugPrint('Detection result: index=$maxIndex, confidence=$confidence');

      // Check if confidence is too low (no currency)
      if (confidence < noCurrencyThreshold) {
        // No currency detected
        return {
          'success': true,
          'label': "no_currency",
          'confidence': confidence,
          'message': 'no_currency_detected'.tr(),
          'isCurrency': false
        };
      }

      // Check if confidence is above threshold for currency detection
      if (confidence >= threshold) {
        final label = _labels![maxIndex];

        return {
          'success': true,
          'label': label,
          'confidence': confidence,
          'message': 'Currency detected: $label',
          'isCurrency': true
        };
      } else {
        // Low confidence currency detection
        final label = _labels![maxIndex];

        return {
          'success': true,
          'label': label,
          'confidence': confidence,
          'message': 'Currency possibly detected: $label (low confidence)',
          'isCurrency': true,
          'lowConfidence': true
        };
      }
    } catch (e) {
      debugPrint('Error during TFLite inference: $e');
      return {'success': false, 'message': 'Error processing image: $e'};
    }
  }

  ByteBuffer _prepareInput(img.Image image) {
    // Resize image to model input size
    final resizedImage = img.copyResize(
      image,
      width: inputSize,
      height: inputSize,
    );

    // Create input tensor (1, 224, 224, 3)
    final inputValues = Float32List(1 * inputSize * inputSize * 3);
    var index = 0;

    // Process each pixel
    for (var y = 0; y < inputSize; y++) {
      for (var x = 0; x < inputSize; x++) {
        // Get pixel color
        final pixel = resizedImage.getPixel(x, y);

        // Extract RGB values (ABGR format in image package)
        final r = pixel.r.toDouble();
        final g = pixel.g.toDouble();
        final b = pixel.b.toDouble();

        // Normalize to [0, 1]
        inputValues[index++] = r / 255.0;
        inputValues[index++] = g / 255.0;
        inputValues[index++] = b / 255.0;
      }
    }

    return inputValues.buffer;
  }
}
