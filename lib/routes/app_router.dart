import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../auth/presentation/screens/blind/signin_screen.dart';
import '../auth/presentation/screens/blind/signup_screen.dart';
import '../auth/presentation/screens/welcome_screen.dart';
import '../auth/presentation/screens/forget_password_screen.dart';
import '../home/presentation/screens/blind/blind_user_profile_screen.dart';
import '../auth/presentation/screens/helper/helper_signin_screen.dart';
import '../auth/presentation/screens/helper/helper_signup_screen.dart';
import '../home/presentation/screens/helper/helper_setting_screen.dart';
import '../home/presentation/screens/blind/blind_home_screen.dart';
import '../home/presentation/screens/helper/helper_home_screen.dart';
import '../home/presentation/screens/blind/connect_with_blind_screen.dart';
import '../auth/presentation/screens/splash_screen.dart';
import '../home/presentation/screens/blind/blind_settings_screen.dart';
import '../home/presentation/screens/blind/blind_chat_screen.dart';
import '../home/presentation/screens/helper/helper_chat_screen.dart';
import '../home/presentation/screens/blind/blind_emergency_screen.dart';
import '../home/presentation/screens/blind/blind_location_screen.dart';
import '../presentation/screens/video_call_screen.dart';
import '../home/presentation/screens/blind/blind_connection_screen.dart';
import '../home/presentation/screens/helper/helper_connect_screen.dart';
import '../home/presentation/screens/helper/helper_emergency_screen.dart';
import '../presentation/screens/esp32_cam_screen.dart';

class AppRouter {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static const String splash = '/';
  static const String welcome = '/welcome';
  static const String signin = '/signin';
  static const String signup = '/signup';
  static const String home = '/home';
  static const String helperHome = '/helper-home';
  static const String forgotPassword = '/forgot-password';
  static const String connectWithBlind = '/connect-with-blind';
  static const String blindUserProfile = '/blind-user-profile';
  static const String sensorDashboard = '/sensor-dashboard';
  static const String settingsRoute = '/settings';
  static const String chatRoute = '/chat';
  static const String emergencyRoute = '/emergency';
  static const String locationRoute = '/location';
  static const String cameraRoute = '/camera';
  static const String sightedSignin = '/sighted-signin';
  static const String sightedSignup = '/sighted-signup';
  static const String esp32Setup = '/esp32-setup';
  static const String videoCall = '/video_call';
  static const String blindConnectionRoute = '/blind-connection';
  static const String helperConnectRoute = '/helper-connect';
  static const String helperChatRoute = '/helper-chat';
  static const String helperProfileRoute = '/helper-profile';
  static const String helperEmergencyRoute = '/helper-emergency';
  static const String esp32CamRoute = '/esp32-cam';

  static final GoRouter router = GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: splash,
    errorBuilder: (context, state) => Scaffold(
            body: Center(
        child: Text('No route defined for ${state.uri.path}'),
      ),
    ),
    routes: [
      GoRoute(
        path: splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: welcome,
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: signin,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final isBlindUser = extra?['isBlindUser'] as bool? ?? false;
          return SigninScreen(isBlindUser: isBlindUser);
        },
            ),
      GoRoute(
        path: signup,
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: sightedSignin,
        builder: (context, state) => const SightedUserSigninScreen(),
      ),
      GoRoute(
        path: sightedSignup,
        builder: (context, state) => const SightedUserSignupScreen(),
      ),
      GoRoute(
        path: home,
        builder: (context, state) => const BlindHomeScreen(),
      ),
      GoRoute(
        path: helperHome,
        builder: (context, state) => const HelperHomeScreen(),
      ),
      GoRoute(
        path: forgotPassword,
        builder: (context, state) => const ForgetPasswordScreen(),
      ),
      GoRoute(
        path: connectWithBlind,
        builder: (context, state) => const ConnectWithBlindScreen(),
      ),
      GoRoute(
        path: blindUserProfile,
        builder: (context, state) => const BlindUserProfileScreen(),
      ),
      GoRoute(
        path: settingsRoute,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: chatRoute,
        builder: (context, state) => const BlindChatScreen(),
      ),
      GoRoute(
        path: emergencyRoute,
        builder: (context, state) => const EmergencyScreen(),
      ),
      GoRoute(
        path: locationRoute,
        builder: (context, state) => const LocationSenderScreen(),
      ),
  
      GoRoute(
        path: videoCall,
        builder: (context, state) {
          final Map<String, dynamic> callParams = state.extra as Map<String, dynamic>;
          return VideoCallScreen(
            callID: callParams['callID'],
            targetUserID: callParams['targetUserID'],
            targetUserName: callParams['targetUserName'],
            isOutgoing: callParams['isOutgoing'],
          );
        },
      ),
      GoRoute(
        path: blindConnectionRoute,
        builder: (context, state) => const BlindConnectionScreen(),
      ),
      GoRoute(
        path: helperConnectRoute,
        builder: (context, state) => const HelperConnectScreen(),
      ),
      GoRoute(
        path: helperChatRoute,
        builder: (context, state) => const HelperChatScreen(),
      ),
      GoRoute(
        path: helperProfileRoute,
        builder: (context, state) => const HelperSettingScreen(),
      ),
      GoRoute(
        path: helperEmergencyRoute,
        builder: (context, state) {
          final emergencyAlertId = state.extra as String;
          return HelperEmergencyScreen(emergencyAlertId: emergencyAlertId);
        },
      ),
      GoRoute(
        path: esp32CamRoute,
        builder: (context, state) => const ESP32CamScreen(),
      ),
    ],
  );

  // Navigation helper functions
  static void navigateToHome(BuildContext context) {
    context.go(home);
  }

  static void navigateToSettings(BuildContext context) {
    context.go(settingsRoute);
  }

  static void navigateToEmergency(BuildContext context) {
    context.go(emergencyRoute);
  }

  static void navigateToChat(BuildContext context) {
    context.go(chatRoute);
  }

  static void navigateToCamera(BuildContext context) {
    context.go(cameraRoute);
  }

  static void navigateToLocationSender(BuildContext context) {
    context.go(locationRoute);
  }

  static void navigateToSensorDashboard(BuildContext context) {
    context.go(sensorDashboard);
  }

  static void navigateToConnection(BuildContext context) {
    context.go(blindUserProfile);
  }

  static void navigateToSightedSignin(BuildContext context) {
    context.go(sightedSignin);
  }

  static void navigateToSightedSignup(BuildContext context) {
    context.go(sightedSignup);
  }
  
  static void navigateToESP32Setup(BuildContext context) {
    context.go(esp32Setup);
  }

  static void navigateToESP32Cam(BuildContext context) {
    context.go(esp32CamRoute);
  }
  
  static void navigateToHelperEmergency(BuildContext context, {required String emergencyAlertId}) {
    context.push(helperEmergencyRoute, extra: emergencyAlertId);
  }

  static void navigateToHelperConnect(BuildContext context) {
    context.go(helperConnectRoute);
  }

  static void navigateToHelperChat(BuildContext context) {
    context.go(helperChatRoute);
  }

  static void navigateToHelperProfile(BuildContext context) {
    try {
      context.go(helperProfileRoute);
    } catch (e) {
      debugPrint('Navigation error to helper profile: $e');
      try {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const HelperSettingScreen())
        );
      } catch (e) {
        debugPrint('Fallback navigation also failed: $e');
      }
    }
  }

  static void navigateToVideoCall(
    BuildContext context, {
    required String callID,
    required String targetUserID,
    required String targetUserName,
    required bool isOutgoing,
  }) {
    context.push(
      videoCall,
      extra: {
        'callID': callID,
        'targetUserID': targetUserID,
        'targetUserName': targetUserName,
        'isOutgoing': isOutgoing,
      },
    );
  }

  static void navigateAndReplaceToHelperHome(BuildContext context) {
    context.go(helperHome);
  }
} 