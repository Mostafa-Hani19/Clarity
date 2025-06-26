// import 'dart:convert';
// import 'package:flutter/foundation.dart';
// import 'package:http/http.dart' as http;

// class GeminiService {
//   static const String _apiKey = '';
//   static const String _baseUrl =
//       'https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent';

//   Future<String> generateResponse(String prompt, {Map<String, dynamic>? context}) async {
//     try {
//       final requestBody = {
//         'contents': [
//           {
//             'parts': [
//               {'text': _buildPromptWithContext(prompt, context)},
//             ],
//           },
//         ],
//         'generationConfig': {
//           'temperature': 0.4,
//           'topK': 32,
//           'topP': 0.95,
//           'maxOutputTokens': 1024,
//         },
//       };

//       final response = await http.post(
//         Uri.parse('$_baseUrl?key=$_apiKey'),
//         headers: {'Content-Type': 'application/json'},
//         body: jsonEncode(requestBody),
//       );

//       if (response.statusCode == 200) {
//         final data = jsonDecode(response.body);
//         final parts = data['candidates']?[0]?['content']?['parts'];
//         if (parts != null && parts.isNotEmpty && parts[0]['text'] != null) {
//           return parts[0]['text'];
//         }
//         return "I couldn't process that request.";
//       } else {
//         debugPrint('Gemini API error: ${response.statusCode} - ${response.body}');
//         return "I'm having trouble connecting to AI services.";
//       }
//     } catch (e) {
//       debugPrint('Error calling Gemini API: $e');
//       return "I encountered an issue processing your request.";
//     }
//   }

//   String _buildPromptWithContext(String userPrompt, Map<String, dynamic>? context) {
//     final contextString = context != null
//         ? '''
// Current screen: ${context['currentScreen'] ?? 'unknown'}
// Available actions: ${context['availableActions']?.join(', ') ?? 'unknown'}
// User is connected to helper: ${context['isConnected'] ? 'Yes' : 'No'}
// Sensor data available: ${context['hasSensorData'] ? 'Yes' : 'No'}
// '''
//         : '';

//     return '''
// You are Clarity, a voice assistant for blind users in a mobile app that connects blind users with sighted helpers.

// CONTEXT INFORMATION:
// $contextString

// The user said: "$userPrompt"

// FORMAT YOUR RESPONSE as one of these formats:
// 1. If this is a navigation request, respond with: ACTION:NAVIGATE:screen_name
// 2. If this is a call request, respond with: ACTION:CALL
// 3. If this is a message request, respond with: ACTION:MESSAGE:message_content
// 4. If this is a sensor data request, respond with: ACTION:SENSOR:sensor_name
// 5. If this is an emergency request, respond with: ACTION:EMERGENCY
// 6. If this is a settings request, respond with: ACTION:SETTINGS:setting_name
// 7. If this is a help request, respond with: ACTION:HELP
// 8. For any other general question, start with: RESPONSE: followed by a brief, helpful response.

// Keep your responses under 2 sentences and focused on helping the blind user.
// ''';
//   }
// }
