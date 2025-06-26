// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../../../../models/images.dart';
import '../../../../providers/auth_provider.dart';
import 'helper_signin_screen.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../routes/app_router.dart';
import 'package:go_router/go_router.dart';
import '../../../../services/connection_manager.dart';

class SightedUserSignupScreen extends StatefulWidget {
  const SightedUserSignupScreen({super.key});

  @override
  SightedUserSignupScreenState createState() => SightedUserSignupScreenState();
}

class SightedUserSignupScreenState extends State<SightedUserSignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _blindUserIdController = TextEditingController();
  
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _acceptTerms = false;
  String? _errorMessage;
  bool _isBlindUserIdValid = false;
  bool _checkingBlindUserId = false;

  @override
  void initState() {
    super.initState();
    _checkFirebaseConnection();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _blindUserIdController.dispose();
    super.dispose();
  }

  Future<void> _checkFirebaseConnection() async {
    try {
      await FirebaseAuth.instance.authStateChanges().first;
      debugPrint('Firebase connection successful');
    } catch (e) {
      debugPrint('Firebase connection error: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'firebase_connection_error';
        });
      }
    }
  }

  // Sign in with Google
  Future<void> _signInWithGoogle() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    setState(() {
      _errorMessage = null;
      _isGoogleLoading = true;
    });
    
    try {
      final success = await authProvider.signInWithGoogle();
      if (!mounted) return;
      
      if (success) {
        if (_blindUserIdController.text.isNotEmpty) {
          await _linkWithBlindUser(authProvider);
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('google_sign_in_success'.tr()),
            backgroundColor: Colors.green,
          ),
        );
        context.go(AppRouter.helperHome);
      } else {
        final errorMessage = authProvider.errorMessage ?? 'google_sign_in_failed'.tr();
        setState(() => _errorMessage = errorMessage);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'google_sign_in_failed'.tr());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('google_sign_in_failed'.tr()),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGoogleLoading = false);
      }
    }
  }

  Future<void> _signUp() async {
    setState(() => _errorMessage = null);
    
    if (!_formKey.currentState!.validate()) return;
    
    if (!_acceptTerms) {
      setState(() => _errorMessage = 'Please accept the terms & conditions');
      return;
    }
    
    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() => _errorMessage = 'Passwords do not match');
      return;
    }
    
    if (_blindUserIdController.text.isNotEmpty && !_isBlindUserIdValid) {
      await _validateBlindUserId();
      if (!_isBlindUserIdValid) {
        setState(() => _errorMessage = 'Invalid blind user ID. Please verify and try again.');
        return;
      }
    }
    
    setState(() => _isLoading = true);
    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();
      final name = _nameController.text.trim();
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      
      // Set user type to sighted (false)
      await authProvider.setUserType(false);
      
      debugPrint('Attempting to register with email: $email, name: $name');
      final success = await authProvider.register(email, password, name);
      
      if (!mounted) return;
      
      if (success) {
        debugPrint('Registration successful. Adding sighted user data.');
        await _addSightedUserData(authProvider.currentUserId!);
        
        if (_blindUserIdController.text.isNotEmpty) {
          await _linkWithBlindUser(authProvider);
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('sign_up_success'.tr()),
            backgroundColor: Colors.green,
          ),
        );
        context.go(AppRouter.helperHome);
      } else {
        final errorMessage = authProvider.errorMessage;
        debugPrint('Registration failed. Error: $errorMessage');
        
        String displayError;
        if (errorMessage == null || errorMessage == 'unknown_error') {
          displayError = 'Registration failed. Please check your internet connection and try again.';
        } else if (errorMessage.contains('email-already-in-use')) {
          displayError = 'This email is already registered. Please use a different email or sign in.';
        } else if (errorMessage.contains('network')) {
          displayError = 'Network error. Please check your internet connection and try again.';
        } else {
          displayError = errorMessage;
        }
        
        setState(() => _errorMessage = displayError);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(displayError),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('Exception during registration: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Registration failed: ${e.toString()}';
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Registration error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  
  Future<void> _addSightedUserData(String uid) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'type': 'sighted',
        'userType': 'sighted',
        'isBlindUser': false,
        'createdAt': FieldValue.serverTimestamp(),
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error adding sighted user data: $e');
    }
  }
  
  Future<void> _linkWithBlindUser(AuthProvider authProvider) async {
    final blindUserId = _blindUserIdController.text.trim();
    if (blindUserId.isEmpty) return;
    
    try {
      debugPrint('Attempting to link with blind user ID: $blindUserId');
      final currentUserId = authProvider.currentUserId;
      
      if (currentUserId == null) {
        debugPrint('Error: Current user ID is null, cannot link users');
        throw Exception('Current user ID is null. Please try signing in again.');
      }
      
      debugPrint('Current helper user ID: $currentUserId');
      
      // First, update the helper's document
      await FirebaseFirestore.instance.collection('users').doc(currentUserId).update({
        'linkedUserId': blindUserId,
        'userType': 'sighted',
      });
      
      // Also update the blind user's document to create bidirectional link
      await FirebaseFirestore.instance.collection('users').doc(blindUserId).update({
        'linkedHelperIds': FieldValue.arrayUnion([currentUserId]),
        'linkedUserId': currentUserId,
      });
      
      // Setup connection record
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(currentUserId).get();
      final userData = userDoc.data();
      
      if (userData != null) {
        // Create connection records for both users
        final List<String> userIds = [currentUserId, blindUserId];
        userIds.sort();
        final chatRoomId = 'chat_${userIds.join('_')}';
        
        // Create connection record for helper
        await FirebaseFirestore.instance.collection('connections').doc(currentUserId).set({
          'connectedUserId': blindUserId,
          'chatRoomId': chatRoomId,
          'timestamp': FieldValue.serverTimestamp(),
          'isPermanent': true,
          'lastSyncedAt': FieldValue.serverTimestamp(),
        });
        
        // Create connection record for blind user
        await FirebaseFirestore.instance.collection('connections').doc(blindUserId).set({
          'connectedUserId': currentUserId,
          'chatRoomId': chatRoomId,
          'timestamp': FieldValue.serverTimestamp(),
          'isPermanent': true,
          'lastSyncedAt': FieldValue.serverTimestamp(),
        });
        
        // Now use ConnectionManager to establish real-time connection
        final connectionManager = Provider.of<ConnectionManager>(context, listen: false);
        await connectionManager.connectToUser(blindUserId);
        
        debugPrint('✅ Successfully linked and connected with blind user: $blindUserId');
        
        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('successfully_connected'.tr()),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error linking with blind user: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('error_linking_with_blind_user'.tr() + ': $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  Future<void> _validateBlindUserId() async {
    final blindUserId = _blindUserIdController.text.trim();
    if (blindUserId.isEmpty) {
      setState(() => _isBlindUserIdValid = false);
      return;
    }
    
    setState(() {
      _checkingBlindUserId = true;
      _errorMessage = null; // Clear any previous error messages
    });
    
    try {
      debugPrint('Validating blind user ID: $blindUserId');
      
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(blindUserId)
          .get()
          .timeout(const Duration(seconds: 10), onTimeout: () {
            throw TimeoutException('Firestore request timed out while validating blind user ID');
          });
      
      if (!userDoc.exists) {
        debugPrint('User document does not exist for ID: $blindUserId');
        setState(() {
          _isBlindUserIdValid = false;
          _errorMessage = 'Invalid blind user ID. User not found.';
        });
        return;
      }
      
      final userData = userDoc.data();
      debugPrint('User data retrieved: $userData');
      
      if (userData == null) {
        debugPrint('User data is null for ID: $blindUserId');
        setState(() {
          _isBlindUserIdValid = false;
          _errorMessage = 'Invalid user data.';
        });
        return;
      }
      
      // Check if this is a blind user
      final bool userTypeField = userData['userType'] == 'blind';
      final bool typeField = userData['type'] == 'blind';
      final bool isBlindUserField = userData['isBlindUser'] == true;
      
      debugPrint('User type checks: userType=$userTypeField, type=$typeField, isBlindUser=$isBlindUserField');
      
      final bool isBlind = userTypeField || typeField || isBlindUserField;
      
      if (!isBlind) {
        debugPrint('User is not a blind user for ID: $blindUserId');
        setState(() {
          _isBlindUserIdValid = false;
          _errorMessage = 'The ID you entered is not for a blind user.';
        });
        return;
      }
      
      // Check email to prevent linking own account
      final String? blindUserEmail = userData['email'] as String?;
      final String currentEmail = _emailController.text.trim();
      
      debugPrint('Email comparison: blind user=$blindUserEmail, current=$currentEmail');
      
      if (blindUserEmail == currentEmail) {
        debugPrint('Emails match - cannot link with own account');
        setState(() {
          _isBlindUserIdValid = false;
          _errorMessage = 'You cannot link with your own blind user account. Please use a different helper email.';
        });
        return;
      }
      
      // Validation passed
      debugPrint('Validation passed. Valid blind user ID: $blindUserId');
      setState(() {
        _isBlindUserIdValid = true;
        _errorMessage = null;
      });
      
    } catch (e) {
      debugPrint('Error validating blind user ID: $e');
      setState(() {
        _isBlindUserIdValid = false;
        _errorMessage = 'Error validating ID: ${e.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() => _checkingBlindUserId = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Define a clean, simple color scheme
    final Color primaryColor = Colors.green.shade700;
    final Color backgroundColor = Colors.white;
    final Color cardColor = Colors.white;
    final Color textColor = Colors.black87;
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Register as Assistant'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: backgroundColor,
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo or App name
                Image.asset(Appimages.logo1, height: 100),
                const SizedBox(height: 30),
                
                // Sign up card
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  color: cardColor,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Title
                          Text(
                            'Register as Assistant',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 20),
                          
                          // Full name field
                          TextFormField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              labelText: 'Full Name',
                              prefixIcon: Icon(Icons.person_outline, color: primaryColor),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: primaryColor, width: 2),
                              ),
                            ),
                            validator: (value) => value == null || value.isEmpty
                              ? 'Please enter your name'
                              : null,
                          ),
                          const SizedBox(height: 16),
                          
                          // Email field
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.email_outlined, color: primaryColor),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: primaryColor, width: 2),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your email';
                              }
                              // Basic email validation
                              final bool emailValid = RegExp(
                                r'^[^@]+@[^@]+\.[^@]+',
                              ).hasMatch(value);
                              if (!emailValid) {
                                return 'Please enter a valid email';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          
                          // Password field
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: Icon(Icons.lock_outline, color: primaryColor),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                  color: primaryColor,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: primaryColor, width: 2),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter a password';
                              }
                              if (value.length < 6) {
                                return 'Password must be at least 6 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          
                          // Confirm password field
                          TextFormField(
                            controller: _confirmPasswordController,
                            obscureText: _obscureConfirmPassword,
                            decoration: InputDecoration(
                              labelText: 'Confirm Password',
                              prefixIcon: Icon(Icons.lock_outline, color: primaryColor),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureConfirmPassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                  color: primaryColor,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscureConfirmPassword = !_obscureConfirmPassword;
                                  });
                                },
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: primaryColor, width: 2),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please confirm your password';
                              }
                              if (value != _passwordController.text) {
                                return 'Passwords do not match';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          
                          // Blind User ID field
                          TextFormField(
                            controller: _blindUserIdController,
                            decoration: InputDecoration(
                              labelText: 'Blind User ID (Optional)',
                              hintText: 'Link with a blind user',
                              prefixIcon: Icon(Icons.link, color: primaryColor),
                              suffixIcon: _checkingBlindUserId
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: Padding(
                                      padding: EdgeInsets.all(8.0),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : _blindUserIdController.text.isNotEmpty
                                  ? Icon(
                                      _isBlindUserIdValid
                                        ? Icons.check_circle
                                        : Icons.error,
                                      color: _isBlindUserIdValid
                                        ? Colors.green
                                        : Colors.red,
                                    )
                                  : null,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: primaryColor, width: 2),
                              ),
                            ),
                            onChanged: (value) {
                              if (value.isNotEmpty) {
                                _validateBlindUserId();
                              } else {
                                setState(() => _isBlindUserIdValid = false);
                              }
                            },
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Enter the Blind User ID to connect with them directly',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          // Terms and conditions checkbox
                          CheckboxListTile(
                            value: _acceptTerms,
                            onChanged: (value) {
                              setState(() {
                                _acceptTerms = value ?? false;
                              });
                            },
                            title: const Text(
                              'I accept the Terms & Conditions',
                              style: TextStyle(fontSize: 14),
                            ),
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: primaryColor,
                            checkColor: Colors.white,
                            dense: true,
                          ),
                          const SizedBox(height: 8),
                          
                          // Error message
                          if (_errorMessage != null)
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.error_outline, color: Colors.red),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 16),
                          
                          // Register button
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _signUp,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryColor,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 2,
                              ),
                              child: _isLoading
                                ? SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    )
                                  )
                                : const Text(
                                    'Register',
                                    style: TextStyle(fontSize: 16),
                                  ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          // Or divider
                          Row(
                            children: [
                              Expanded(
                                child: Divider(
                                  color: Colors.grey.shade300,
                                  thickness: 1,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                  'OR',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Divider(
                                  color: Colors.grey.shade300,
                                  thickness: 1,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          
                          // Google sign in button
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: OutlinedButton.icon(
                              onPressed: _isGoogleLoading ? null : _signInWithGoogle,
                              icon: _isGoogleLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.blue,
                                    ),
                                  )
                                : Image.asset(
                                   Appimages.googleLogo,
                                    height: 24,
                                  ),
                              label: Text(
                                'Sign up with Google',
                                style: TextStyle(
                                  color: Colors.grey.shade800,
                                  fontSize: 16,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: Colors.grey.shade300),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          // Already have account
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Already have an account?',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const SightedUserSigninScreen(),
                                    ),
                                  );
                                },
                                child: Text(
                                  'Sign In',
                                  style: TextStyle(
                                    color: primaryColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
} 