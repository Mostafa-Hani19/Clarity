import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cloudinary_sdk/cloudinary_sdk.dart';

class CloudinaryService {
  static final CloudinaryService _instance = CloudinaryService._internal();
  factory CloudinaryService() => _instance;

  // These should be your Cloudinary credentials
  // For production, these should be stored securely and loaded from environment variables
  final String _cloudName = "";
  final String _apiKey = "";
  final String _apiSecret = "";
  
  late final Cloudinary _cloudinary;
  
  CloudinaryService._internal() {
    _cloudinary = Cloudinary.full(
      apiKey: _apiKey,
      apiSecret: _apiSecret,
      cloudName: _cloudName,
    );
  }
  
  /// Upload an image file to Cloudinary
  /// Returns the URL of the uploaded image if successful, null otherwise
  Future<String?> uploadImage(File imageFile, {String? folder}) async {
    try {
      return uploadFile(
        file: imageFile,
        resourceType: CloudinaryResourceType.image,
        folder: folder ?? 'chat_images',
        filePrefix: 'img',
      );
    } catch (e) {
      debugPrint('❌ CloudinaryService - Error uploading image: $e');
      return null;
    }
  }
  
  /// Upload an audio file to Cloudinary
  /// Returns the URL of the uploaded audio if successful, null otherwise
  Future<String?> uploadAudio(File audioFile, {String? folder}) async {
    try {
      return uploadFile(
        file: audioFile,
        resourceType: CloudinaryResourceType.auto,
        folder: folder ?? 'chat_audio',
        filePrefix: 'audio',
      );
    } catch (e) {
      debugPrint('❌ CloudinaryService - Error uploading audio: $e');
      return null;
    }
  }
  
  /// General file upload method
  /// Returns the URL of the uploaded file if successful, null otherwise
  Future<String?> uploadFile({
    required File file,
    required CloudinaryResourceType resourceType,
    required String folder,
    required String filePrefix,
  }) async {
    try {
      debugPrint('🔍 CloudinaryService - Starting file upload to Cloudinary');
      
      if (!await file.exists()) {
        debugPrint('❌ CloudinaryService - File does not exist: ${file.path}');
        return null;
      }
      
      // Get file size for debugging
      final fileSize = await file.length();
      debugPrint('✅ CloudinaryService - File size: $fileSize bytes');
      
      if (fileSize == 0) {
        debugPrint('❌ CloudinaryService - File is empty (0 bytes)');
        return null;
      }
      
      debugPrint('🔍 CloudinaryService - Creating upload resource');
      final uploadResource = CloudinaryUploadResource(
        filePath: file.path,
        resourceType: resourceType,
        folder: folder,
        fileName: '${filePrefix}_${DateTime.now().millisecondsSinceEpoch}',
      );
      
      debugPrint('🔍 CloudinaryService - Starting Cloudinary upload');
      final response = await _cloudinary.uploadResource(uploadResource);
      
      if (response.isSuccessful && response.secureUrl != null) {
        debugPrint('✅ CloudinaryService - File uploaded successfully: ${response.secureUrl}');
        return response.secureUrl;
      } else {
        debugPrint('❌ CloudinaryService - Failed to upload file: ${response.error ?? "Unknown error"}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ CloudinaryService - Error in uploadFile: $e');
      // Try to print more debug info
      try {
        if (e is Exception) {
          debugPrint('❌ CloudinaryService - Exception details: ${e.toString()}');
        }
      } catch (_) {}
      
      return null;
    }
  }
} 