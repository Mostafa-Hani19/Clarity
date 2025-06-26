import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class GeminiChatService {
  // Use the existing Gemini API key
  static const String _apiKey = '';
  static const String _baseUrl = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro:generateContent';
  
  // Store chat history for context
  final List<Map<String, String>> _chatHistory = [];
  
  // Get the chat history
  List<Map<String, String>> get chatHistory => List.unmodifiable(_chatHistory);
  
  // Clear chat history
  void clearChatHistory() {
    _chatHistory.clear();
  }
  
  // Build a conversation for Gemini from chat history
  String _buildPromptFromHistory(String message, String language) {
    String systemPrompt = "You are a helpful assistant for a blind user. Keep your responses clear, concise, and informative. " "When describing things, be detailed but efficient. " +
                         "The user's preferred language is ${language == 'ar' ? 'Arabic' : language == 'de' ? 'German' : 'English'}.\n\n";
                         
    // Add chat history context
    String conversationHistory = "";
    for (var entry in _chatHistory) {
      String role = entry["role"] ?? "user";
      String content = entry["content"] ?? "";
      
      if (role == "user") {
        conversationHistory += "User: $content\n";
      } else if (role == "assistant") {
        conversationHistory += "Assistant: $content\n";
      }
    }
    
    // Add current message
    conversationHistory += "User: $message\n";
    conversationHistory += "Assistant: ";
    
    return systemPrompt + conversationHistory;
  }
  
  // Send a message to Gemini and get a response
  Future<String> sendMessage(String message, {String language = 'en'}) async {
    try {
      // Add user message to history
      _chatHistory.add({"role": "user", "content": message});
      
      // Build prompt from chat history
      final prompt = _buildPromptFromHistory(message, language);
      
      // Create the request body
      final Map<String, dynamic> requestBody = {
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
      };
      
      // Send the request
      final response = await http.post(
        Uri.parse('$_baseUrl?key=$_apiKey'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );
      
      // Check if the request was successful
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final responseText = data['candidates'][0]['content']['parts'][0]['text'] as String;
        
        // Add assistant response to history
        _chatHistory.add({"role": "assistant", "content": responseText});
        
        return responseText;
      } else {
        debugPrint('Gemini API error: ${response.statusCode} - ${response.body}');
        return language == 'ar' 
            ? "عذراً، حدث خطأ في الاتصال بخدمة الذكاء الاصطناعي."
            : language == 'de'
                ? "Entschuldigung, bei der Verbindung zum KI-Dienst ist ein Fehler aufgetreten."
                : "Sorry, there was an error connecting to the AI service.";
      }
    } catch (e) {
      debugPrint('Error calling Gemini API: $e');
      return language == 'ar'
          ? "واجهت مشكلة في معالجة طلبك."
          : language == 'de'
              ? "Bei der Bearbeitung Ihrer Anfrage ist ein Problem aufgetreten."
              : "I encountered an issue processing your request.";
    }
  }
  
  // Generate a response for image description
  Future<String> describeImage(String prompt, {String language = 'en'}) async {
    try {
      final specialPrompt = "Describe this image in detail for a blind person: $prompt";
      return await sendMessage(specialPrompt, language: language);
    } catch (e) {
      debugPrint('Error describing image: $e');
      return language == 'ar'
          ? "لم أتمكن من وصف الصورة."
          : language == 'de'
              ? "Ich konnte das Bild nicht beschreiben."
              : "I couldn't describe the image.";
    }
  }
  
  // Process an image and get a description
  Future<String> processImage(File imageFile, {String prompt = '', String language = 'en'}) async {
    try {
      // Read the image file as bytes
      final List<int> imageBytes = await imageFile.readAsBytes();
      
      // Convert image to base64
      final String base64Image = base64Encode(imageBytes);
      
      // Set the default prompt if none is provided
      final String imagePrompt = prompt.isEmpty 
          ? "Please describe this image in detail for a blind person. Include all important visual information."
          : prompt;
      
      // Create the request body with image
      final Map<String, dynamic> requestBody = {
        'contents': [{
          'parts': [
            {
              'text': imagePrompt
            },
            {
              'inline_data': {
                'mime_type': 'image/jpeg',
                'data': base64Image
              }
            }
          ]
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
      };
      
      // Send the request
      final response = await http.post(
        Uri.parse('$_baseUrl?key=$_apiKey'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );
      
      // Check if the request was successful
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final responseText = data['candidates'][0]['content']['parts'][0]['text'] as String;
        
        // Add interaction to chat history
        _chatHistory.add({"role": "user", "content": "[Sent an image with prompt: $imagePrompt]"});
        _chatHistory.add({"role": "assistant", "content": responseText});
        
        return responseText;
      } else {
        debugPrint('Gemini API error: ${response.statusCode} - ${response.body}');
        return language == 'ar' 
            ? "عذراً، حدث خطأ في معالجة الصورة."
            : language == 'de'
                ? "Entschuldigung, bei der Verarbeitung des Bildes ist ein Fehler aufgetreten."
                : "Sorry, there was an error processing the image.";
      }
    } catch (e) {
      debugPrint('Error processing image with Gemini: $e');
      return language == 'ar'
          ? "واجهت مشكلة في معالجة الصورة."
          : language == 'de'
              ? "Bei der Verarbeitung des Bildes ist ein Problem aufgetreten."
              : "I encountered an issue processing the image.";
    }
  }
} 