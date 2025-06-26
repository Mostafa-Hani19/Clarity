import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class GeminiApi {
  static const String _apiKey = '';
  // static const String _baseUrl = 'https://generativelanguage.googleapis.com/v1beta';
  static const String _baseUrl = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro:generateContent';

  static Future<String> ask(String prompt, {String language = 'en'}) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/models/gemini-pro:generateContent?key=$_apiKey'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'contents': [{
            'parts': [{
              'text': prompt
            }]
          }],
          'generationConfig': {
            'temperature': 0.7,
            'topK': 40,
            'topP': 0.95,
            'maxOutputTokens': 1024,
          },
          'safetySettings': [
            {
              'category': 'HARM_CATEGORY_HARASSMENT',
              'threshold': 'BLOCK_MEDIUM_AND_ABOVE'
            },
            {
              'category': 'HARM_CATEGORY_HATE_SPEECH',
              'threshold': 'BLOCK_MEDIUM_AND_ABOVE'
            },
            {
              'category': 'HARM_CATEGORY_SEXUALLY_EXPLICIT',
              'threshold': 'BLOCK_MEDIUM_AND_ABOVE'
            },
            {
              'category': 'HARM_CATEGORY_DANGEROUS_CONTENT',
              'threshold': 'BLOCK_MEDIUM_AND_ABOVE'
            }
          ]
        }),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        return data['candidates'][0]['content']['parts'][0]['text'] as String;
      } else {
        throw Exception('Failed to get AI response: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error communicating with AI: $e');
    }
  }

  static Future<Map<String, dynamic>?> analyzeIntent(String prompt, {String language = 'en'}) async {
    try {
      final response = await http.post(
        Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent?key=$_apiKey',
        ),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'contents': [
            {
              'parts': [
                {
                  'text': '''
Analyze the following user's request and reply ONLY with a JSON object containing:
- "intent": (ex: add_reminder, change_theme, navigate, emergency, change_language, etc.)
- "parameters": {extract any parameters like "time", "date", "reminder_title", "page", "language", etc.}
- "answer": (short reply in ${language == 'ar' ? 'Arabic' : 'English'} that should be spoken back to the user)

User said: "$prompt"
Remember: I am a blind user using a voice assistant.
Return JSON ONLY, nothing else.
'''
                }
              ]
            }
          ],
          'generationConfig': {
            'temperature': 0.3,
            'topK': 40,
            'topP': 0.9,
            'maxOutputTokens': 512,
          },
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final text = data['candidates']?[0]['content']['parts'][0]['text'];
        // تأكد أن الناتج JSON صالح
        try {
          return json.decode(text ?? '');
        } catch (e) {
          debugPrint('Parsing error: $e\nResponse: $text');
          return null;
        }
      } else {
        debugPrint('Gemini API error: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Error calling Gemini API: $e');
      return null;
    }
  }
}
