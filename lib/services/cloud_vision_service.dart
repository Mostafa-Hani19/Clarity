import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// A service to interact with Google Cloud Vision API for OCR (text recognition)
class CloudVisionService {
  /// The API key for accessing Google Cloud Vision API
  static const String _apiKey = '';
  
  /// The base URL for Google Cloud Vision API
  static const String _apiUrl = 'https://vision.googleapis.com/v1/images:annotate';
  
  /// Detects text in an image using Google Cloud Vision API
  /// 
  /// [imagePath] is the path to the image file
  /// [isArabic] forces Arabic text detection if true
  /// Returns a map with detected text and language information
  static Future<Map<String, dynamic>> detectText(String imagePath, {bool isArabic = false}) async {
    try {
      // Read the image file as bytes
      final File imageFile = File(imagePath);
      if (!await imageFile.exists()) {
        return {'error': 'Image file does not exist', 'text': ''};
      }

      final List<int> imageBytes = await imageFile.readAsBytes();
      final String base64Image = base64Encode(imageBytes);

      // Create the API request body
      final Map<String, dynamic> requestBody = {
        'requests': [
          {
            'image': {
              'content': base64Image,
            },
            'features': [
              {
                'type': 'TEXT_DETECTION',
                'maxResults': 10,
              },
            ],
            'imageContext': {
              'languageHints': isArabic ? ['ar'] : [],
            }
          },
        ],
      };

      // Send the request to the Cloud Vision API
      final response = await http.post(
        Uri.parse('$_apiUrl?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        // Process the response
        final Map<String, dynamic> data = jsonDecode(response.body);
        
        // Extract the full text from the response
        String fullText = '';
        String languageCode = '';
        
        if (data['responses'] != null && 
            data['responses'].isNotEmpty &&
            data['responses'][0]['textAnnotations'] != null &&
            data['responses'][0]['textAnnotations'].isNotEmpty) {
          
          // Get the full text (first entry contains all text)
          fullText = data['responses'][0]['textAnnotations'][0]['description'] ?? '';
          
          // Get detected language if available
          languageCode = data['responses'][0]['textAnnotations'][0]['locale'] ?? '';
          
          // If Arabic was forced, override the detected language
          if (isArabic) {
            languageCode = 'ar';
          }
          
          // Handle Arabic text direction and encoding issues if needed
          if (isArabic || languageCode.startsWith('ar')) {
            fullText = _processArabicText(fullText);
          }
          
          // Get detailed annotations (each word/block)
          final List<dynamic> annotations = data['responses'][0]['textAnnotations'];
          List<String> textBlocks = [];
          
          // Skip the first annotation (it's the full text)
          for (int i = 1; i < annotations.length; i++) {
            final String text = annotations[i]['description'] ?? '';
            if (text.isNotEmpty) {
              textBlocks.add(text);
            }
          }
          
          return {
            'text': fullText,
            'blocks': textBlocks,
            'languageCode': languageCode,
            'confidence': 0.9, // Cloud Vision doesn't provide confidence scores for text detection
            'originalJson': data, // Include the full JSON response for debugging
          };
        }
        
        return {
          'text': '',
          'blocks': [],
          'languageCode': '',
          'confidence': 0.0,
          'error': 'No text detected',
        };
      } else {
        // Handle API error
        return {
          'error': 'API Error: ${response.statusCode} - ${response.body}',
          'text': '',
        };
      }
    } catch (e) {
      debugPrint('Error in Cloud Vision text detection: $e');
      return {
        'error': 'Exception: $e',
        'text': '',
      };
    }
  }
  
  /// Process Arabic text to fix common OCR issues with Arabic text
  static String _processArabicText(String text) {
    if (text.isEmpty) return text;
    
    // Fix common OCR errors in Arabic
    String processed = text
      // Fix common letter confusions
      .replaceAll('ىا', 'يا')
      .replaceAll('دل', 'لا')
      .replaceAll('اl', 'ال')
      .replaceAll('لl', 'لا')
      .replaceAll('هـ', 'ه')
      .replaceAll('ة', 'ه')
      .replaceAll('ي', 'ى')
      .replaceAll('گ', 'ك')
      
      // Additional letter fixes for presentation forms
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
      
    return processed;
  }
} 