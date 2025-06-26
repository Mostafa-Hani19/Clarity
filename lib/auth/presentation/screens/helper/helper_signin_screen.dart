// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import '../../../../models/images.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../routes/app_router.dart';
import '../../../../services/connection_manager.dart';

class SightedUserSigninScreen extends StatefulWidget {
  const SightedUserSigninScreen({super.key});

  @override
  State<SightedUserSigninScreen> createState() => _SightedUserSigninScreenState();
}

class _SightedUserSigninScreenState extends State<SightedUserSigninScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _blindUserIdController = TextEditingController();
  
  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  String? _errorMessage;
  bool _isBlindUserIdValid = false;
  bool _checkingBlindUserId = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _checkFirebaseConnection();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('email') ?? '';
      final password = prefs.getString('password') ?? '';
      final remember = prefs.getBool('rememberMe') ?? false;

      if (remember) {
        setState(() {
          _emailController.text = email;
          _passwordController.text = password;
          _rememberMe = true;
        });
      }
    } catch (e) {
      debugPrint('Error loading preferences: $e');
    }
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

  Future<void> _submitSignin() async {
    // Clear any previous error messages
    setState(() => _errorMessage = null);

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    // First, set user type to sighted (false)
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.setUserType(false);

    final success = await authProvider.login(email, password);

    if (!mounted) return;

    if (success) {
      if (_rememberMe) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('email', email);
          await prefs.setString('password', password);
          await prefs.setBool('rememberMe', true);
        } catch (e) {
          debugPrint('Error saving preferences: $e');
        }
      }
      
      // Update user data to ensure they're marked as sighted user
      await _updateSightedUserData(authProvider.currentUserId!);
      
      // Link with blind user if ID was provided
      if (_blindUserIdController.text.isNotEmpty) {
        if (_isBlindUserIdValid) {
          await _linkWithBlindUser(authProvider);
        } else {
          await _validateBlindUserId();
          if (_isBlindUserIdValid) {
            await _linkWithBlindUser(authProvider);
          }
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_getLocalizedText('sign_in_success')),
          backgroundColor: Colors.green,
        ),
      );

      // Navigate using Go Router directly
      context.go(AppRouter.helperHome);
    } else {
      final errorMessage =
          authProvider.errorMessage ?? _getLocalizedText('sign_in_failed');
      setState(() => _errorMessage = errorMessage);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_getLocalizedText(errorMessage)),
          backgroundColor: Colors.red,
        ),
      );
    }

    setState(() => _isLoading = false);
  }

  Future<void> _signInWithGoogle() async {
    // Clear any previous error messages
    setState(() {
      _errorMessage = null;
      _isGoogleLoading = true;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    // Set user type to sighted (false) first
    await authProvider.setUserType(false);
    
    final success = await authProvider.signInWithGoogle();

    if (!mounted) return;

    if (success) {
      // Update user data to ensure they're marked as sighted user
      await _updateSightedUserData(authProvider.currentUserId!);
      
      // Link with blind user if ID was provided
      if (_blindUserIdController.text.isNotEmpty) {
        if (_isBlindUserIdValid) {
          await _linkWithBlindUser(authProvider);
        } else {
          await _validateBlindUserId();
          if (_isBlindUserIdValid) {
            await _linkWithBlindUser(authProvider);
          }
        }
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_getLocalizedText('google_sign_in_success')),
          backgroundColor: Colors.green,
        ),
      );

      // Navigate using Go Router directly
      context.go(AppRouter.helperHome);
    } else {
      final errorMessage =
          authProvider.errorMessage ??
          _getLocalizedText('google_sign_in_failed');
      setState(() => _errorMessage = errorMessage);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_getLocalizedText(errorMessage)),
          backgroundColor: Colors.red,
        ),
      );
    }

    setState(() => _isGoogleLoading = false);
  }
  
  Future<void> _updateSightedUserData(String uid) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'userType': 'sighted',
        'type': 'sighted',
        'isBlindUser': false,
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error updating sighted user data: $e');
    }
  }
  
  Future<void> _linkWithBlindUser(AuthProvider authProvider) async {
    final blindUserId = _blindUserIdController.text.trim();
    if (blindUserId.isNotEmpty) {
      try {
        final currentUserId = authProvider.currentUserId;
        if (currentUserId != null) {
          await FirebaseFirestore.instance.collection('users').doc(currentUserId).update({
            'linkedUserId': blindUserId,
            'userType': 'sighted',
          });
          
          // Also update the blind user's document to create bidirectional link
          await FirebaseFirestore.instance.collection('users').doc(blindUserId).update({
            'linkedHelperIds': FieldValue.arrayUnion([currentUserId]),
            'linkedUserId': currentUserId,
          });
          
          // Setup connection records for both users
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
          
          // Force bidirectional connection to ensure both sides are properly linked
          await authProvider.forceBidirectionalConnection();
          
          debugPrint('✅ Successfully linked and connected with blind user: $blindUserId');
          
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
      
      // Get the user document from Firestore
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(blindUserId)
          .get();
      
      if (!userDoc.exists) {
        debugPrint('User document does not exist');
        setState(() {
          _isBlindUserIdValid = false;
          _errorMessage = 'Invalid blind user ID. User not found.';
        });
        return;
      }
      
      // Document exists, check if it's a blind user
      final userData = userDoc.data();
      debugPrint('User data: $userData');
      
      if (userData == null) {
        debugPrint('User data is null');
        setState(() {
          _isBlindUserIdValid = false;
          _errorMessage = 'Invalid user data.';
        });
        return;
      }
      
      // Check if this is a blind user (check multiple fields since data structure could vary)
      final bool userTypeField = userData['userType'] == 'blind';
      final bool typeField = userData['type'] == 'blind';
      final bool isBlindUserField = userData['isBlindUser'] == true;
      
      debugPrint('User type checks: userType=$userTypeField, type=$typeField, isBlindUser=$isBlindUserField');
      
      final bool isBlind = userTypeField || typeField || isBlindUserField;
      
      if (!isBlind) {
        debugPrint('User is not a blind user');
        setState(() {
          _isBlindUserIdValid = false;
          _errorMessage = 'The ID you entered is not for a blind user.';
        });
        return;
      }
      
      // If we get here, we have a blind user. Now check if the emails match
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
      
      // If we get here, validation passed
      debugPrint('Validation passed. Valid blind user ID');
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
      setState(() => _checkingBlindUserId = false);
    }
  }

  String _getLocalizedText(String key) => key.tr();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _blindUserIdController.dispose();
    super.dispose();
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
        title: Text('Sign in as Assistant'),
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

                // Sign in card
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
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
                            'Sign in as Assistant',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Email field
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              labelText: _getLocalizedText('email'),
                              prefixIcon: Icon(
                                Icons.email_outlined,
                                color: primaryColor,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade300,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade300,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: primaryColor,
                                  width: 2,
                                ),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return _getLocalizedText('please_enter_email');
                              }
                              final bool emailValid = RegExp(
                                r'^[^@]+@[^@]+\.[^@]+',
                              ).hasMatch(value);
                              if (!emailValid) {
                                return _getLocalizedText('please_enter_valid_email');
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
                              labelText: _getLocalizedText('password'),
                              prefixIcon: Icon(
                                Icons.lock_outline,
                                color: primaryColor,
                              ),
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
                                borderSide: BorderSide(
                                  color: Colors.grey.shade300,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade300,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: primaryColor,
                                  width: 2,
                                ),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return _getLocalizedText('please_enter_password');
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

                          // Remember me and Forgot password
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: Checkbox(
                                      value: _rememberMe,
                                      onChanged: (value) {
                                        setState(() {
                                          _rememberMe = value ?? false;
                                        });
                                      },
                                      activeColor: primaryColor,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _getLocalizedText('remember_me'),
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                              TextButton(
                                onPressed: () {
                                  context.go(AppRouter.forgotPassword);
                                },
                                child: Text(
                                  _getLocalizedText('forgot_password'),
                                  style: TextStyle(
                                    color: primaryColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
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
                                      _getLocalizedText(_errorMessage!),
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 16),

                          // Sign in button
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _submitSignin,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryColor,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 2,
                              ),
                              child: _isLoading
                                  ? const CircularProgressIndicator(
                                      color: Colors.white,
                                    )
                                  : Text(
                                      _getLocalizedText('sign_in'),
                                      style: const TextStyle(fontSize: 16),
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
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                  _getLocalizedText('or'),
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
                              onPressed: _isGoogleLoading
                                  ? null
                                  : _signInWithGoogle,
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
                                _getLocalizedText('sign in with google'),
                                style: TextStyle(
                                  color: Colors.grey.shade800,
                                  fontSize: 16,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side:
                                    BorderSide(color: Colors.grey.shade300),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Don't have account
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _getLocalizedText('dont_have_account'),
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                              TextButton(
                                onPressed: () {
                                  context.go(AppRouter.sightedSignup);
                                },
                                child: Text(
                                  _getLocalizedText('sign_up'),
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