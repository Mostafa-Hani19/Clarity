import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';

class FirebaseAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  // Constructor: Initialize persistence for web
  FirebaseAuthService() {
    _setPersistence();
    _logCurrentAuthState();

    // Debugging info
    debugPrint('🔍 FirebaseApp isInitialized: ${_auth.app.isAutomaticDataCollectionEnabled}');
    debugPrint('🔍 FirebaseApp name: ${_auth.app.name}');
    debugPrint('🔍 FirebaseApp projectId: ${_auth.app.options.projectId}');
  }

  // Set persistence to LOCAL (only on web)
  Future<void> _setPersistence() async {
    if (kIsWeb) {
      try {
        await _auth.setPersistence(Persistence.LOCAL);
        debugPrint('✅ Firebase persistence set to LOCAL (Web)');
      } catch (e) {
        debugPrint('⚠️ Cannot set persistence on Web: $e');
      }
    }
  }

  void _logCurrentAuthState() {
    final user = _auth.currentUser;
    if (user != null) {
      debugPrint('🔐 User already signed in: ${user.email} (${user.uid})');
    } else {
      debugPrint('🔓 No user currently signed in');
    }
  }

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // =========================
  // Sign Up with Email/Pass
  // =========================
  Future<UserCredential> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      debugPrint('🔑 Creating user: $email');
      final result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (displayName != null && displayName.isNotEmpty) {
        await result.user?.updateDisplayName(displayName);
        debugPrint('✅ Display name updated: $displayName');
      }
      return result;
    } on FirebaseAuthException catch (e) {
      // Handle common errors
      debugPrint('❌ FirebaseAuthException: [${e.code}] ${e.message}');
      if (e.code == 'email-already-in-use') {
        debugPrint('⚠️ Email already in use: $email');
      }
      rethrow;
    } catch (e) {
      debugPrint('❌ Unexpected error on sign up: $e');
      rethrow;
    }
  }

  // =========================
  // Sign In with Email/Pass
  // =========================
  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    try {
      debugPrint('🔑 Signing in: $email');
      return await _auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      debugPrint('❌ FirebaseAuthException: [${e.code}] ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('❌ Unexpected error on sign in: $e');
      rethrow;
    }
  }

  // =========================
  // Google Sign In
  // =========================
  Future<UserCredential> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        // Web
        final googleProvider = GoogleAuthProvider();
        return await _auth.signInWithPopup(googleProvider);
      } else {
        // Mobile
        final googleUser = await _googleSignIn.signIn();
        if (googleUser == null) {
          throw FirebaseAuthException(
            code: 'sign-in-cancelled',
            message: 'Google sign in cancelled by user',
          );
        }
        final googleAuth = await googleUser.authentication;
        if (googleAuth.accessToken == null || googleAuth.idToken == null) {
          throw FirebaseAuthException(
            code: 'missing-google-auth-token',
            message: 'Missing Google authentication token',
          );
        }
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        return await _auth.signInWithCredential(credential);
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('❌ Google sign in failed: [${e.code}] ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('❌ Google sign in error: $e');
      rethrow;
    }
  }

  // =========================
  // Update User Profile
  // =========================
  Future<void> updateProfile({
    String? displayName,
    String? photoURL,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'No user currently signed in',
      );
    }
    try {
      if (displayName != null) await user.updateDisplayName(displayName);
      if (photoURL != null) await user.updatePhotoURL(photoURL);
      await user.reload();
      debugPrint('✅ User profile updated');
    } catch (e) {
      debugPrint('❌ Update profile error: $e');
      rethrow;
    }
  }

  // =========================
  // Sign Out
  // =========================
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      await _auth.signOut();
      debugPrint('✅ User signed out');
    } catch (e) {
      debugPrint('❌ Sign out error: $e');
      rethrow;
    }
  }

  // =========================
  // Password Reset
  // =========================
  Future<void> resetPassword({required String email}) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      debugPrint('✅ Password reset email sent');
    } catch (e) {
      debugPrint('❌ Password reset error: $e');
      rethrow;
    }
  }

  // =========================
  // Error messages (custom)
  // =========================
  String getErrorMessage(FirebaseAuthException e) {
    debugPrint('🛑 FirebaseAuthException: ${e.code} - ${e.message}');
    switch (e.code) {
      case 'user-not-found':
        return 'user_not_found';
      case 'wrong-password':
        return 'wrong_password';
      case 'invalid-email':
        return 'invalid_email';
      case 'email-already-in-use':
        return 'email_already_in_use';
      case 'weak-password':
        return 'password_weak';
      case 'operation-not-allowed':
        return 'operation_not_allowed';
      case 'too-many-requests':
        return 'too_many_requests';
      case 'sign-in-cancelled':
        return 'sign_in_cancelled';
      case 'account-exists-with-different-credential':
        return 'account_exists_with_different_credential';
      case 'invalid-credential':
        return 'invalid_credential';
      case 'network-request-failed':
        return 'network_request_failed';
      case 'timeout':
        return 'network_timeout';
      case 'null-user':
        return 'null_user_error';
      case 'unknown-error':
        return 'unknown_error';
      case 'user-disabled':
        return 'user_disabled';
      case 'credential-already-in-use':
        return 'credential_already_in_use';
      case 'requires-recent-login':
        return 'requires_recent_login';
      case 'provider-already-linked':
        return 'provider_already_linked';
      case 'missing-google-auth-token':
        return 'missing_google_auth_token';
      case 'platform-exception':
        return 'platform_exception';
      default:
        return 'sign_in_failed';
    }
  }
}
