import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class LanguageDetectionService {
  static const String _apiKey = '';
  static const String _endpoint = 'https://language.googleapis.com/v1/documents:detectLanguage';

  /// Detects the language of the given text using Google Cloud Natural Language API
  /// Returns a map with detected language code and confidence score
  static Future<Map<String, dynamic>> detectLanguage(String text, {String? forceLanguage}) async {
    try {
      // If a specific language is forced, return it directly
      if (forceLanguage != null) {
        return {
          'languageCode': forceLanguage,
          'confidence': 1.0,
          'forced': true
        };
      }
      
      if (text.isEmpty) {
        return {'languageCode': 'und', 'confidence': 0.0};
      }

      // Check for corrupted Arabic text patterns
      if (_containsCorruptedArabicPatterns(text)) {
        debugPrint('Detected corrupted Arabic text patterns, returning Arabic');
        return {
          'languageCode': 'ar',
          'confidence': 0.95,
          'detected_corrupted': true
        };
      }

      // Normalize Arabic text - fix common encoding issues
      String normalizedText = _normalizeArabicText(text);

      // Check for Arabic characters using regex
      // Arabic Unicode range: \u0600-\u06FF
      final arabicRegex = RegExp(r'[\u0600-\u06FF]');
      final containsArabic = arabicRegex.hasMatch(normalizedText);
      
      // If text contains significant Arabic characters, prioritize Arabic detection
      if (containsArabic && _calculateArabicRatio(normalizedText) > 0.3) {
        debugPrint('Text contains significant Arabic characters, prioritizing Arabic');
        return {
          'languageCode': 'ar',
          'confidence': 0.9,
          'detected_locally': true
        };
      }

      final response = await http.post(
        Uri.parse('$_endpoint?key=$_apiKey'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: json.encode({
          'document': {
            'type': 'PLAIN_TEXT',
            'content': normalizedText,
          },
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('Cloud Natural Language API response: $data');
        
        if (data['languages'] != null && data['languages'].isNotEmpty) {
          final language = data['languages'][0];
          final String languageCode = language['languageCode'] ?? 'und';
          final double confidence = language['confidence'] ?? 0.0;
          
          // Double-check for Arabic - sometimes the API might miss it
          if (containsArabic && _calculateArabicRatio(normalizedText) > 0.4 && languageCode != 'ar') {
            debugPrint('API detected $languageCode but text contains significant Arabic, overriding to Arabic');
            return {
              'languageCode': 'ar',
              'confidence': 0.95,
              'overridden': true
            };
          }
          
          // Check for corrupted Arabic even if API returns another language
          if (_containsCorruptedArabicPatterns(text)) {
            debugPrint('API detected $languageCode but text contains corrupted Arabic patterns, overriding to Arabic');
            return {
              'languageCode': 'ar',
              'confidence': 0.9,
              'overridden_corrupted': true
            };
          }
          
          debugPrint('Cloud Natural Language API detected language: $languageCode with confidence: $confidence');
          return {
            'languageCode': languageCode,
            'confidence': confidence,
          };
        } else {
          return {'languageCode': 'und', 'confidence': 0.0};
        }
      } else {
        debugPrint('Cloud Natural Language API error: ${response.statusCode}, ${response.body}');
        
        // If API fails and text contains Arabic, default to Arabic
        if (containsArabic && _calculateArabicRatio(normalizedText) > 0.3) {
          return {
            'languageCode': 'ar',
            'confidence': 0.8,
            'fallback': true
          };
        }
        
        // If API fails and text contains corrupted Arabic patterns, default to Arabic
        if (_containsCorruptedArabicPatterns(text)) {
          return {
            'languageCode': 'ar',
            'confidence': 0.8,
            'fallback_corrupted': true
          };
        }
        
        return {'languageCode': 'und', 'confidence': 0.0};
      }
    } catch (e) {
      debugPrint('Error detecting language: $e');
      return {'languageCode': 'und', 'confidence': 0.0};
    }
  }
  
  /// Calculate the ratio of Arabic characters in the text
  static double _calculateArabicRatio(String text) {
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
  
  /// Normalize Arabic text to fix common encoding issues
  static String _normalizeArabicText(String text) {
    // Replace common problematic characters
    Map<String, String> replacements = {
      '?': 'ء',
      '?': 'أ',
      '?': 'إ',
      '?': 'آ',
      '?': 'ا',
      '?': 'ب',
      '?': 'ت',
      '?': 'ث',
      '?': 'ج',
      '?': 'ح',
      '?': 'خ',
      '?': 'د',
      '?': 'ذ',
      '?': 'ر',
      '?': 'ز',
      '?': 'س',
      '?': 'ش',
      '?': 'ص',
      '?': 'ض',
      '?': 'ط',
      '?': 'ظ',
      '?': 'ع',
      '?': 'غ',
      '?': 'ف',
      '?': 'ق',
      '?': 'ك',
      '?': 'ل',
      '?': 'م',
      '?': 'ن',
      '?': 'ه',
      '?': 'و',
      '?': 'ي',
      '?': 'ى',
    };
    
    String result = text;
    
    // Apply replacements
    replacements.forEach((key, value) {
      result = result.replaceAll(key, value);
    });
    
    // Remove zero-width characters and other problematic invisible characters
    result = result.replaceAll(RegExp(r'[\u200B-\u200F\uFEFF]'), '');
    
    return result;
  }
  
  /// Check for corrupted Arabic text patterns
  static bool _containsCorruptedArabicPatterns(String text) {
    // Common patterns seen in corrupted Arabic text
    final List<String> corruptedPatterns = [
      'ajlail', 'lals', 'ancgj', 'Jbl', 'Hdq', 'ynoill', 'pljib', 'Ugalen',
      'nlin', 'IJnoill', 'ninall', 'augol', 'Laoio', 'U9j9I', 'iol', 'isl'
    ];
    
    // Check if text contains any of the corrupted patterns
    for (final pattern in corruptedPatterns) {
      if (text.contains(pattern)) {
        return true;
      }
    }
    
    // Look for specific character combinations that suggest corrupted Arabic
    final bool hasLatinCharsWithRTLBehavior = RegExp(r'[a-zA-Z][a-zA-Z]+\s+[\.,:;]').hasMatch(text);
    
    // Additional check for Latin characters with unusual casing patterns (typical in corrupted Arabic)
    final bool hasUnusualCasing = RegExp(r'[a-z][A-Z]|[A-Z][a-z]{2,}[A-Z]').hasMatch(text);
    
    // Check for numbers mixed with Latin characters (common in corrupted Arabic)
    final bool hasNumbersWithLatin = RegExp(r'[0-9][a-zA-Z]|[a-zA-Z][0-9]').hasMatch(text);
    
    return hasLatinCharsWithRTLBehavior || hasUnusualCasing || hasNumbersWithLatin;
  }
} 