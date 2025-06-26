import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import '../../../../models/images.dart';
import '../../../../providers/auth_provider.dart';
import 'signin_screen.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../routes/app_router.dart';
import 'package:go_router/go_router.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  SignupScreenState createState() => SignupScreenState();
}

class SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _acceptTerms = false;
  String? _errorMessage;

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_getLocalizedText('google_sign_in_success')),
            backgroundColor: Colors.green,
          ),
        );
        // Navigate to home screen
        if (authProvider.isBlindUser) {
          context.go(AppRouter.home);
        } else {
          context.go(AppRouter.helperHome);
        }
      } else {
        final errorMessage = authProvider.errorMessage ?? _getLocalizedText('google_sign_in_failed');
        setState(() => _errorMessage = errorMessage);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_getLocalizedText(errorMessage)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'google_sign_in_failed');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_getLocalizedText('google_sign_in_failed')),
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
    
    setState(() => _isLoading = true);
    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();
      final name = _nameController.text.trim();
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final success = await authProvider.register(email, password, name);
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_getLocalizedText('sign_up_success')),
            backgroundColor: Colors.green,
          ),
        );
        // Navigate to home screen
        if (authProvider.isBlindUser) {
          context.go(AppRouter.home);
        } else {
          context.go(AppRouter.helperHome);
        }
      } else {
        final errorMessage = authProvider.errorMessage ?? _getLocalizedText('sign_up_failed');
        setState(() => _errorMessage = errorMessage);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_getLocalizedText(errorMessage)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = _getLocalizedText('sign_up_failed');
        });
      }
    }
  }

  String _getLocalizedText(String key) => key.tr();

  @override
  Widget build(BuildContext context) {
    // Define a clean, simple color scheme
    final Color primaryColor = Colors.blue.shade700;
    final Color backgroundColor = Colors.white;
    final Color cardColor = Colors.white;
    final Color textColor = Colors.black87;
    
    return Scaffold(
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
                            _getLocalizedText('sign_up'),
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
                              labelText: _getLocalizedText('full_name'),
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
                              ? _getLocalizedText('please_enter_name')
                              : null,
                            ),
                            const SizedBox(height: 16),
                          
                          // Email field
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: InputDecoration(
                                labelText: _getLocalizedText('email'),
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
                            validator: (value) => value == null || !value.contains('@')
                              ? _getLocalizedText('please_enter_valid_email')
                              : null,
                            ),
                            const SizedBox(height: 16),
                          
                          // Password field
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              labelText: _getLocalizedText('password'),
                              prefixIcon: Icon(Icons.lock_outline, color: primaryColor),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                  color: Colors.grey,
                                ),
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
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
                              validator: (value) => value == null || value.length < 6
                                ? _getLocalizedText('please_enter_valid_password')
                                : null,
                          ),
                          const SizedBox(height: 16),
                          
                          // Confirm Password field
                          TextFormField(
                            controller: _confirmPasswordController,
                            obscureText: _obscureConfirmPassword,
                              decoration: InputDecoration(
                              labelText: _getLocalizedText('confirm_password'),
                              prefixIcon: Icon(Icons.lock_outline, color: primaryColor),
                                suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureConfirmPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                  color: Colors.grey,
                                ),
                                onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
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
                            validator: (value) => value == null || value.isEmpty
                              ? _getLocalizedText('please_confirm_password')
                              : value != _passwordController.text
                                ? _getLocalizedText('passwords_dont_match')
                                : null,
                          ),
                          const SizedBox(height: 12),
                          
                          // Terms & Conditions checkbox
                          Row(
                            children: [
                              SizedBox(
                                height: 24,
                                width: 24,
                                child: Checkbox(
                                  value: _acceptTerms,
                                  onChanged: (value) => setState(() => _acceptTerms = value ?? false),
                                  activeColor: primaryColor,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _getLocalizedText('accept_terms'),
                                  style: TextStyle(fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                          
                            // Error message
                            if (_errorMessage != null)
                            Container(
                              margin: const EdgeInsets.only(top: 16),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.red.shade200),
                                  ),
                                  child: Row(
                                    children: [
                                  Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                      _errorMessage!,
                                      style: TextStyle(color: Colors.red.shade700, fontSize: 14),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                          
                          const SizedBox(height: 20),
                          
                          // Sign up button
                            SizedBox(
                              width: double.infinity,
                            height: 50,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _signUp,
                                style: ElevatedButton.styleFrom(
                                backgroundColor: primaryColor,
                                  foregroundColor: Colors.white,
                                elevation: 2,
                                  shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _isLoading
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    _getLocalizedText('sign_up'),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                            ),
                          ),
                          
                            const SizedBox(height: 16),
                          
                          // Or divider
                            Row(
                              children: [
                              Expanded(child: Divider(color: Colors.grey.shade300)),
                                Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Text(
                                  _getLocalizedText('or_continue_with'),
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                                ),
                              ),
                              Expanded(child: Divider(color: Colors.grey.shade300)),
                            ],
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Google sign up button
                            SizedBox(
                              width: double.infinity,
                            height: 50,
                              child: OutlinedButton.icon(
                              onPressed: _isGoogleLoading ? null : _signInWithGoogle,
                              icon: _isGoogleLoading
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: primaryColor,
                                    ),
                                  )
                                : Image.asset(Appimages.googleLogo, width: 20, height: 20),
                              label: Text(_getLocalizedText('continue_with_google')),
                                style: OutlinedButton.styleFrom(
                                foregroundColor: textColor,
                                side: BorderSide(color: Colors.grey.shade300),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                
                // Already have account
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(_getLocalizedText('already_have_account')),
                                TextButton(
                                  onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const SigninScreen()),
                          );
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: primaryColor,
                          minimumSize: const Size(10, 10),
                          padding: const EdgeInsets.only(left: 4),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          _getLocalizedText('sign_in'),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
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