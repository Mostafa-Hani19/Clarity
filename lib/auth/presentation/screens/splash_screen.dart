// ignore_for_file: use_build_context_synchronously

import 'package:clarity/models/images.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../providers/auth_provider.dart';
import '../../../routes/app_router.dart';
import 'package:go_router/go_router.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool _showLoader = true;

  @override
  void initState() {
    super.initState();

    // Setup animation controller
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    // Create a fade-in animation
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);

    // Start the animation
    _controller.forward();

    // After splash screen delay, check authentication and redirect accordingly
    _checkAuthenticationAndRedirect();
  }

  Future<void> _checkAuthenticationAndRedirect() async {
    // Give the splash screen time to display
    await Future.delayed(const Duration(seconds: 3));

    if (!mounted) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    // Show loading spinner if network is slow (اختياري)
    setState(() => _showLoader = true);

    try {
      // Ensure linked user status is loaded
      await authProvider.refreshLinkedUser();

      if (!mounted) return;

      // Check if user is authenticated through Firebase
      if (authProvider.isAuthenticated) {
        debugPrint(
            'User already authenticated via Firebase: ${authProvider.user?.email}');
        if (authProvider.isBlindUser) {
          context.go(AppRouter.home);
        } else {
          context.go(AppRouter.helperHome);
        }
        return;
      }

      // If not authenticated via Firebase, check SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final isLoggedIn = prefs.getBool(AuthProvider.isLoggedInKey) ?? false;

      if (isLoggedIn) {
        debugPrint('User logged in via SharedPreferences');
        // Load the user type
        final isBlind = prefs.getBool(AuthProvider.userTypeKey) ?? false;
        await authProvider.setUserType(isBlind);

        if (!mounted) return;

        if (authProvider.isBlindUser) {
          context.go(AppRouter.home);
        } else {
          context.go(AppRouter.helperHome);
        }
      } else {
        debugPrint(
            'No authenticated user found, redirecting to welcome screen');
        context.go(AppRouter.welcome);
      }
    } catch (e) {
      debugPrint('Error checking saved authentication: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error checking authentication: $e'),
            backgroundColor: Colors.red,
          ),
        );
        context.go(AppRouter.welcome);
      }
    } finally {
      if (mounted) setState(() => _showLoader = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? Colors.black : Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Semantics(
              label: 'Clarity Logo',
              child: FadeTransition(
                opacity: _animation,
                child: Image.asset(
                  isDarkMode ? Appimages.whiteLogo : Appimages.logo1,
                  width: 200,
                  height: 200,
                ),
              ),
            ),
            if (_showLoader)
              const Padding(
                padding: EdgeInsets.only(top: 32.0),
                child: CircularProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }
}
