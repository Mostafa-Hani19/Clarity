import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Helper class to handle Firebase authentication errors
class FirebaseErrorHandler {
  /// Handles Firebase authentication errors and returns user-friendly messages
  static String handleAuthError(FirebaseAuthException error) {
    debugPrint('Firebase Auth Error: ${error.code} - ${error.message}');
    
    switch (error.code) {
      case 'invalid-email':
        return 'The email address is not valid.';
      case 'user-disabled':
        return 'This user account has been disabled.';
      case 'user-not-found':
        return 'No user found with this email address.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'operation-not-allowed':
        return 'This operation is not allowed. Please contact support.';
      case 'weak-password':
        return 'The password is too weak. Please use a stronger password.';
      case 'network-request-failed':
        return 'Network error. Please check your internet connection.';
      case 'too-many-requests':
        return 'Too many unsuccessful login attempts. Please try again later.';
      case 'quota-exceeded':
        return 'Server quota exceeded. Please try again later.';
      case 'invalid-credential':
        return 'Invalid credentials. Please check your login details.';
      default:
        if (error.message != null && error.message!.contains('API key not valid')) {
          return 'Firebase configuration error: API key is not valid. This is a project setup issue.';
        }
        return error.message ?? 'An unknown error occurred. Please try again.';
    }
  }

  /// Handles general Firebase initialization errors
  static String handleFirebaseError(Object error) {
    debugPrint('Firebase Error: $error');
    
    if (error.toString().contains('API key not valid')) {
      return 'Firebase configuration error: API key is not valid. Check your Firebase setup.';
    }
    
    if (error.toString().contains('network')) {
      return 'Network error. Please check your internet connection.';
    }
    
    return 'A Firebase error occurred: $error';
  }
} 