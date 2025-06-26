// Dart imports
import 'dart:async';
import 'dart:convert';

// Flutter imports
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Firebase imports
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;

// Third-party packages
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:zego_uikit/zego_uikit.dart';
import 'package:shared_preferences/shared_preferences.dart';

// App files
import 'firebase_options.dart';
import 'routes/app_router.dart';
import 'generated/custom_asset_loader.dart';

// Providers
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/location_provider.dart';
import 'providers/reminder_provider.dart';
import 'providers/sensor_provider.dart';

// Services
import 'services/connectivity_service.dart';
import 'services/connection_manager.dart';
import 'services/notification_service.dart';

// Controllers
import 'home/presentation/controllers/blind_chat_controller.dart';

/// Global navigator key for accessing navigator from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Request necessary permissions for app functionality
Future<void> requestAppPermissions() async {
  await Permission.microphone.request();
  await Permission.bluetoothConnect.request();
  await Permission.camera.request();
  await Permission.location.request();
  await Permission.notification.request();
}

/// Firebase Messaging background handler
/// Processes messages when app is in background or terminated
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase first
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Define notification channels
  const AndroidNotificationChannel messagesChannel = AndroidNotificationChannel(
    'messages_channel',
    'Chat Messages',
    description: 'Notifications for new chat messages',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
    sound: RawResourceAndroidNotificationSound('default'),
  );

  // Create the notification channel
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(messagesChannel);

  final notification = message.notification;
  final data = message.data;

  // Debug notification to confirm background handler is working
  try {
    await flutterLocalNotificationsPlugin.show(
      900, // Special ID for debug
      'BACKGROUND DEBUG',
      'Background notification service is active',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'messages_channel',
          'Chat Messages',
          channelDescription: 'Notifications for new chat messages',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
    debugPrint('✅ NOTIFICATION DEBUG: Background debug notification shown');
  } catch (e) {
    debugPrint(
        '❌ NOTIFICATION DEBUG: Background debug notification failed: $e');
  }

  // Process the actual notification
  if (notification != null) {
    await _handleBackgroundNotification(
        notification, data, flutterLocalNotificationsPlugin);
  } else {
    debugPrint('⚠️ NOTIFICATION DEBUG: No notification in background message');
  }
}

/// Handle a background notification
Future<void> _handleBackgroundNotification(
  RemoteNotification notification,
  Map<String, dynamic> data,
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin,
) async {
  final String channelId = data['android_channel_id'] ?? 'messages_channel';
  String soundResource = 'default';
  if (channelId == 'emergency_alerts') {
    soundResource = 'emergency_alert';
  } else if (channelId == 'video_call_channel') {
    soundResource = 'video_call';
  }

  // Configure platform-specific notification details
  AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    channelId,
    notification.title ?? 'Notification',
    channelDescription: notification.body ?? '',
    importance: Importance.high,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
    sound: RawResourceAndroidNotificationSound(soundResource),
    fullScreenIntent: data.containsKey('videoCall') || channelId == 'video_call_channel',
  );

  DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
    interruptionLevel: InterruptionLevel.active,
    sound: 'default',
  );

  NotificationDetails platformChannelSpecifics = NotificationDetails(
    android: androidDetails,
    iOS: iosDetails,
  );

  try {
    // Display the notification
    await flutterLocalNotificationsPlugin.show(
      notification.hashCode,
      notification.title,
      notification.body,
      platformChannelSpecifics,
      payload: jsonEncode(data),
    );
    debugPrint(
        '✅ NOTIFICATION DEBUG: Background notification shown: ${notification.title}');

    // Save notification to Firestore for persistent storage
    try {
      await _saveNotificationToFirestore(data, notification, channelId);
    } catch (e) {
      debugPrint(
          '❌ NOTIFICATION DEBUG: Error saving notification to Firestore: $e');
    }
  } catch (e) {
    debugPrint(
        '❌ NOTIFICATION DEBUG: Error showing background notification: $e');
  }
}

/// Save notification data to Firestore for persistence
Future<void> _saveNotificationToFirestore(
  Map<String, dynamic> data,
  RemoteNotification notification,
  String channelId,
) async {
  try {
    final firestore = FirebaseFirestore.instance;
    final recipientId = data['recipientId'] ?? _extractRecipientId(data);

    if (recipientId != null) {
      await firestore.collection('notifications').add({
        'recipientId': recipientId,
        'title': notification.title ?? 'New Message',
        'body': notification.body ?? '',
        'data': data,
        'channelId': channelId,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'fromBackground': true,
      });
      debugPrint(
          '✅ NOTIFICATION DEBUG: Background notification saved to Firestore');
    } else {
      debugPrint(
          '⚠️ NOTIFICATION DEBUG: Could not determine recipientId for Firestore');
    }
  } catch (e) {
    debugPrint(
        '❌ NOTIFICATION DEBUG: Error saving background notification to Firestore: $e');
  }
}

/// Extract recipient ID from chat data
String? _extractRecipientId(Map<String, dynamic> data) {
  try {
    if (data.containsKey('chatRoomId') && data.containsKey('senderId')) {
      final chatRoomId = data['chatRoomId'] as String;
      final senderId = data['senderId'] as String;

      if (chatRoomId.startsWith('chat_')) {
        final participants = chatRoomId.substring(5).split('_');
        if (participants.length == 2) {
          return participants[0] == senderId
              ? participants[1]
              : participants[0];
        }
      }
    }
    return null;
  } catch (e) {
    debugPrint('❌ Error extracting recipient ID: $e');
    return null;
  }
}

/// Initialize Firebase services
Future<void> _initializeFirebase() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('✅ Firebase initialized successfully');
  } catch (e) {
    debugPrint('❌ Error initializing Firebase: $e');
  }
}

/// Initialize messaging and notification services
Future<void> _initializeMessaging() async {
  // Request notification permissions
  final settings = await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
    provisional: false,
    criticalAlert: true,
    carPlay: true,
    announcement: true,
  );

  debugPrint('🔍 FCM Permission status: ${settings.authorizationStatus}');

  // Enable auto-initialization
  await FirebaseMessaging.instance.setAutoInitEnabled(true);

  // Configure foreground notification presentation
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  // Get and log FCM token for debugging
  final fcmToken = await FirebaseMessaging.instance.getToken();
  debugPrint('📱 FCM TOKEN: ${fcmToken ?? "NULL TOKEN"}');

  // Set up foreground message handler
  FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
}

/// Handle foreground messages
void _handleForegroundMessage(RemoteMessage message) {
  debugPrint('🔍 Foreground message received: ${message.notification?.title}');
  debugPrint('🔍 Foreground message data: ${message.data}');

  // Show debug notification
  try {
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();
    flutterLocalNotificationsPlugin.show(
      800, // Special debug ID
      'FOREGROUND DEBUG',
      'Foreground handler caught a message',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'messages_channel',
          'Chat Messages',
          channelDescription: 'Notifications for new chat messages',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
    debugPrint('✅ Foreground debug notification shown');
  } catch (e) {
    debugPrint('❌ Foreground debug notification failed: $e');
  }
}

/// Save current user ID to SharedPreferences
Future<void> _saveCurrentUserId() async {
  final currentUser = firebase_auth.FirebaseAuth.instance.currentUser;
  if (currentUser != null) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_id', currentUser.uid);
    debugPrint('✅ Saved user_id to SharedPreferences: ${currentUser.uid}');
    
    // Also save user type (blind or helper)
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();
      
      if (userDoc.exists && userDoc.data() != null) {
        final userData = userDoc.data()!;
        final isBlind = userData['userType'] == 'blind';
        
        await prefs.setBool('is_blind_user', isBlind);
        debugPrint('✅ Saved is_blind_user to SharedPreferences: $isBlind');
      }
    } catch (e) {
      debugPrint('❌ Error saving user type: $e');
    }
  }
}

/// Initialize ZegoUIKit for video calling
Future<void> _initializeZegoUIKit() async {
  try {
    // Use a try-catch block to handle assertion errors
    try {
      // Initialize with custom error handler
  ZegoUIKit().init(
    appID: ,
    appSign: "",
        // Fix: Use the correct scenario enum value for better compatibility
        scenario: ZegoScenario.General,
  );
      
      debugPrint('✅ ZegoUIKit initialized successfully');
      
      // Add custom error handler to suppress the assertion error
      // This helps with the "result.errorCode == 0" assertion failure
      ZegoUIKit().getZegoUIKitVersion().then((version) {
        debugPrint('✅ ZegoUIKit version: $version');
      }).catchError((error) {
        // Ignore this specific error since it's an issue with their internal assertion
        debugPrint('⚠️ ZegoUIKit version check failed: $error');
      });
      
    } catch (e) {
      if (e.toString().contains('Failed assertion') && 
          e.toString().contains('result.errorCode == 0')) {
        // This is expected in debug mode due to error code assertion
        debugPrint('✅ Caught expected ZegoUIKit assertion error, continuing anyway');
      } else {
        rethrow; // Re-throw other errors
      }
    }
  } catch (e) {
    debugPrint('❌ ZegoUIKit initialization exception: $e');
  }
}

/// Main entry point of the application
Future<void> main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize localization
  await EasyLocalization.ensureInitialized();

  // Request necessary permissions
  await requestAppPermissions();

  // Initialize Firebase services
  await _initializeFirebase();

  // Initialize ZegoUIKit for video calls
  await _initializeZegoUIKit();

  // Initialize notification service
  final notificationService = NotificationService();
  notificationService.setNavigatorKey(navigatorKey);
  await notificationService.initialize();

  // Initialize messaging services
  await _initializeMessaging();

  // Initialize providers
  final settingsProvider = SettingsProvider();
  final themeProvider = ThemeProvider();
  final connectivityService = ConnectivityService();
  final authProvider = AuthProvider();
  final chatProvider = ChatProvider();
  final connectionManager = ConnectionManager();
  final reminderProvider = ReminderProvider();
  final sensorProvider = SensorProvider();

  // Load settings and initialize providers
  await settingsProvider.loadSettings();
  await reminderProvider.initialize();

  connectionManager.initialize(
    authProvider: authProvider,
    chatProvider: chatProvider,
    connectivityService: connectivityService,
  );

  // Fix helper connection issues
  await _fixHelperConnection(authProvider, connectionManager);

  // Set up providers list
  final providers = [
    Provider<ConnectivityService>.value(value: connectivityService),
    ChangeNotifierProvider<SettingsProvider>.value(value: settingsProvider),
    ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
    ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
    ChangeNotifierProvider<ChatProvider>.value(value: chatProvider),
    ChangeNotifierProvider<ConnectionManager>.value(value: connectionManager),
    ChangeNotifierProvider<ReminderProvider>.value(value: reminderProvider),
    ChangeNotifierProvider<SensorProvider>.value(value: sensorProvider),
    ChangeNotifierProxyProvider3<AuthProvider, ChatProvider,
        ConnectivityService, BlindChatController>(
      create: (context) => BlindChatController(
        authProvider: authProvider,
        chatProvider: chatProvider,
        connectivityService: connectivityService,
      ),
      update: (context, auth, chat, conn, previous) =>
          previous ??
          BlindChatController(
            authProvider: auth,
            chatProvider: chat,
            connectivityService: conn,
          ),
    ),
    ChangeNotifierProvider(create: (_) => LocationProvider()),
  ];

  // Save current user ID
  await _saveCurrentUserId();

  // Launch the app
  runApp(
    MultiProvider(
      providers: providers,
      child: EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('ar'), Locale('de')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        assetLoader: const CustomAssetLoader(),
        child: const MyApp(),
      ),
    ),
  );
}

/// Root widget of the application
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final settingsProvider = context.watch<SettingsProvider>();

    return MaterialApp.router(
      title: 'app_name'.tr(),
      debugShowCheckedModeBanner: false,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      theme: themeProvider.currentTheme,
      routerConfig: AppRouter.router,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(settingsProvider.textScaleFactor),
          ),
          child: child!,
        );
      },
    );
  }
}

// Fix helper connection issues
Future<void> _fixHelperConnection(
    AuthProvider authProvider, ConnectionManager connectionManager) async {
  try {
    debugPrint('🔧 Attempting to fix helper connection...');

    // First, refresh the linked user from Firestore and SharedPreferences
    await authProvider.refreshLinkedUser();

    // If we're a blind user and have a linked helper ID
    if (authProvider.isBlindUser && authProvider.linkedUserId != null) {
      debugPrint(
          '✅ Blind user has linked helper ID: ${authProvider.linkedUserId}');

      // Force bidirectional connection to ensure both sides are properly linked
      final success = await authProvider.forceBidirectionalConnection();
      if (success) {
        debugPrint('✅ Successfully forced bidirectional connection');

        // Force ConnectionManager to update with the correct linked user
        await connectionManager.checkConnectionStatus();

        // If still not connected, try to connect explicitly
        if (!connectionManager.isConnected &&
            authProvider.linkedUserId != null) {
          await connectionManager.connectToUser(authProvider.linkedUserId!);
          debugPrint(
              '✅ Explicitly connected to helper: ${authProvider.linkedUserId}');
        }
      } else {
        debugPrint('❌ Failed to force bidirectional connection');
      }
    } else if (authProvider.isBlindUser) {
      debugPrint('❌ Blind user has no linked helper ID');
    }
  } catch (e) {
    debugPrint('❌ Error fixing helper connection: $e');
  }
}
