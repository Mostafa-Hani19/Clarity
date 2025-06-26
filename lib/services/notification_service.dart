import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter_tts/flutter_tts.dart';

// Handle background messages when app is closed
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // This ensures messages are processed even when the app is closed
  debugPrint("Handling a background message: ${message.messageId}");
  
  // You can't show UI notifications from the background handler
  // Firebase will automatically create a notification on Android
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  
  factory NotificationService() => _instance;
  NotificationService._internal();
  
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FlutterTts _tts = FlutterTts();
  
  bool _smartTalkingEnabled = true;
  
  final StreamController<Map<String, dynamic>> _emergencyAlertController = 
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get emergencyAlerts => _emergencyAlertController.stream;
  
  // Create a stream for new message notifications
  final StreamController<Map<String, dynamic>> _newMessageController = 
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get newMessages => _newMessageController.stream;
  
  // This is a Firebase Server Key format 
  static const String _firebaseServerKey = 'AAAA7_R1jEs:APA91bGwgOSZgfYV0UQ57_aHZKoFRoifhPc0XlzGZMZz1RYJXfTf__8-YaEAQsUaEJm_5_Y93XOZtCl8vAGMBBcl7vXkrA_5fhagOFCgxaZXeGl8tSsAFKwT4jL6SGkLuWxQCqNWbW5Q';

  GlobalKey<NavigatorState>? _navigatorKey;

  void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  Future<void> initialize() async {
    try {
      // Set the background message handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      
      // Request permissions with high priority
      await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        criticalAlert: true,
        provisional: false,
      );

      const androidSettings = AndroidInitializationSettings('@drawable/notification_icon');
      const iosSettings = DarwinInitializationSettings(
            requestAlertPermission: true,
            requestBadgePermission: true,
            requestSoundPermission: true,
        requestCriticalPermission: true,
      );

      await _local.initialize(
        const InitializationSettings(android: androidSettings, iOS: iosSettings),
        onDidReceiveNotificationResponse: (response) => _handleNotificationTap(response.payload),
      );

      await _createChannels();
      await _initializeTts();
      await _loadSmartTalkingPreference();
      
      // Force token refresh and save
      await _fcm.deleteToken(); // Force refresh by deleting existing token
      await Future.delayed(const Duration(seconds: 1)); // Brief delay
      await _saveFcmToken(); // Get and save new token
      
      _setupEmergencyListener();
      _setupNotificationListener();
      
 
      
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        if (message.data.isNotEmpty) _handleNotificationTap(jsonEncode(message.data));
      });

      debugPrint('✅ NotificationService initialized');
    } catch (e) {
      debugPrint('❌ NotificationService init error: $e');
    }
  }

  Future<void> _initializeTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  Future<void> _loadSmartTalkingPreference() async {
    final prefs = await SharedPreferences.getInstance();
    _smartTalkingEnabled = prefs.getBool('smart_talking_enabled') ?? true;
  }

  Future<void> setSmartTalkingEnabled(bool enabled) async {
    _smartTalkingEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('smart_talking_enabled', enabled);
  }

  bool get isSmartTalkingEnabled => _smartTalkingEnabled;

  Future<void> speakNotification(String text) async {
    if (!_smartTalkingEnabled) return;
    
    try {
      await _tts.speak(text);
    } catch (e) {
      debugPrint('❌ TTS error: $e');
    }
  }

  Future<void> _createChannels() async {
    const emergencyChannel = AndroidNotificationChannel(
        'emergency_alerts',
        'Emergency Alerts',
      description: 'High priority emergency notifications',
        importance: Importance.high,
        sound: RawResourceAndroidNotificationSound('emergency_alert'),
      );
      
    const messagesChannel = AndroidNotificationChannel(
      'messages_channel',
      'Messages',
      description: 'Notifications for new messages',
      importance: Importance.high,
      enableVibration: true,
      );
      
    final videoCallChannel = AndroidNotificationChannel(
      'video_call_channel',
      'Video Calls',
      description: 'High priority notifications for incoming video calls',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000, 500, 1000]),
      sound: RawResourceAndroidNotificationSound('video_call'),
      );
      
    await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(emergencyChannel);
          
    await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(messagesChannel);
          
    await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(videoCallChannel);
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    final data = message.data;
    
    if (notification != null && data.containsKey('emergencyAlert')) {
        await _handleEmergencyAlert(data);
    } else if (notification != null && data.containsKey('chatRoomId')) {
        // This is a chat message notification
        await _handleChatMessage(data, notification.title ?? 'New Message', notification.body ?? '');
        // Stream the message data to any listeners
        _newMessageController.add(_sanitizeDataForJson(data));
    } else if (notification != null && data.containsKey('videoCall')) {
        // Handle video call notification
        await _handleVideoCall(data, notification.title ?? 'Video Call', notification.body ?? '');
    } else if (notification != null) {
      await showLocalNotification(
          id: notification.hashCode,
        title: notification.title ?? 'New Message',
          body: notification.body ?? '',
        payload: jsonEncode(_sanitizeDataForJson(data)),
        channelId: 'default_channel',
      );
    }
  }

  Future<void> _handleNotificationTap(String? payload) async {
    if (payload == null || _navigatorKey == null) return;

    try {
      final data = jsonDecode(payload);

      if (data['emergencyAlert'] == true) {
        _emergencyAlertController.add(data);
      }

      if (data.containsKey('chatRoomId')) {
        _navigatorKey!.currentState?.pushNamed(
          '/chat',
          arguments: {'chatRoomId': data['chatRoomId']},
        );
      }
      
      if (data.containsKey('videoCall')) {
        // For video calls, navigate to the call screen directly
        _navigatorKey!.currentState?.pushNamed(
          '/video_call',
          arguments: {
            'callId': data['callId'],
            'callerId': data['callerId'],
            'callerName': data['callerName'],
            'isIncoming': true,
          },
        );
        
        // For blind users, auto-announce the video call
        final prefs = await SharedPreferences.getInstance();
        final isBlindUser = prefs.getBool('is_blind_user') ?? false;
        if (isBlindUser) {
          final callerName = data['callerName'] ?? 'Someone';
          await speakNotification('Answering video call from $callerName');
        }
      }

    } catch (e) {
      debugPrint('❌ Error parsing notification payload: $e');
    }
  }

  Future<void> _handleEmergencyAlert(Map<String, dynamic> data) async {
    // Sanitize data before adding to stream
    final sanitizedData = _sanitizeDataForJson(data);
    _emergencyAlertController.add(sanitizedData);
    
    await showLocalNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: 'EMERGENCY ALERT',
      body: 'A user needs help. Tap to view.',
      payload: jsonEncode(sanitizedData),
      channelId: 'emergency_alerts',
      importance: Importance.high,
      priority: Priority.high,
      fullScreen: true,
      criticalIOS: true,
    );
    
    // Speak emergency alert
    await speakNotification('Emergency alert! A user needs help.');
  }

  Future<void> _handleChatMessage(Map<String, dynamic> data, String title, String body) async {
    // Sanitize data before encoding
    final sanitizedData = _sanitizeDataForJson(data);
    await showLocalNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      payload: jsonEncode(sanitizedData),
      channelId: 'messages_channel',
      importance: Importance.high,
      priority: Priority.high,
    );
    
    // Speak message notification with sender's name
    String senderName = data['senderName'] ?? 'Someone';
    await speakNotification('New message from $senderName');
  }
  
  Future<void> _handleVideoCall(Map<String, dynamic> data, String title, String body) async {
    // Sanitize data before encoding
    final sanitizedData = _sanitizeDataForJson(data);
    
    // Check if the user is blind to provide enhanced feedback
    final prefs = await SharedPreferences.getInstance();
    final isBlindUser = prefs.getBool('is_blind_user') ?? false;
    
    await showLocalNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      payload: jsonEncode(sanitizedData),
      channelId: 'video_call_channel',
      importance: Importance.high,
      priority: Priority.high,
      fullScreen: true,
      criticalIOS: true,
    );
    
    // Speak video call notification with caller's name
    String callerName = data['callerName'] ?? 'Someone';
    
    if (isBlindUser) {
      // For blind users, provide more detailed and repeated announcements
      await speakNotification('Incoming video call from $callerName. Tap to answer.');
      
      // Schedule repeated announcements for blind users
      Timer(const Duration(seconds: 5), () {
        if (data['callStatus'] != 'answered' && data['callStatus'] != 'declined') {
          speakNotification('You have an incoming video call from $callerName. Double tap anywhere to answer.');
        }
      });
      
      Timer(const Duration(seconds: 10), () {
        if (data['callStatus'] != 'answered' && data['callStatus'] != 'declined') {
          speakNotification('Video call from $callerName is still waiting. Please tap to answer.');
        }
      });
    } else {
      // For sighted users, just a single announcement
      await speakNotification('Incoming video call from $callerName');
    }
  }
  
  Future<void> showLocalNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
    String channelId = 'default_channel',
    Importance importance = Importance.defaultImportance,
    Priority priority = Priority.defaultPriority,
    bool fullScreen = false,
    bool criticalIOS = false,
  }) async {
    final android = AndroidNotificationDetails(
        channelId,
        channelId == 'emergency_alerts' ? 'Emergency Alerts' : 'Notifications',
        importance: importance,
        priority: priority,
      playSound: true,
        enableVibration: true,
      fullScreenIntent: fullScreen,
        sound: channelId == 'emergency_alerts' 
            ? const RawResourceAndroidNotificationSound('emergency_alert')
            : null,
      );
      
    final ios = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      interruptionLevel: criticalIOS ? InterruptionLevel.critical : InterruptionLevel.active,
    );

    await _local.show(
        id,
        title,
        body,
      NotificationDetails(android: android, iOS: ios),
        payload: payload,
      );
    
    // Speak notification content based on channel type
    if (channelId == 'emergency_alerts') {
      await speakNotification('Emergency alert! $body');
    } else if (channelId == 'messages_channel') {
      // For messages, the sender's name should be in the title
      await speakNotification('New message from $title');
    } else {
      // For general notifications
      await speakNotification('$title. $body');
    }
  }

  Future<void> _saveFcmToken() async {
    final token = await _fcm.getToken();
    if (token == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fcm_token', token);

    final userId = prefs.getString('user_id');
    if (userId != null) {
      await _firestore.collection('users').doc(userId).update({
        'fcmTokens': FieldValue.arrayUnion([token]),
        'lastTokenUpdate': FieldValue.serverTimestamp(),
      });
    }

    debugPrint('📲 FCM token saved: $token');
  }

  void _setupEmergencyListener() async {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      
      if (userId != null) {
        _firestore
            .collection('emergencyAlerts')
            .where('linkedUserId', isEqualTo: userId)
            .where('status', isEqualTo: 'active')
            .snapshots()
            .listen((snapshot) async {
          for (final doc in snapshot.docs) {
            final data = doc.data();
          data['alertId'] = doc.id;
            data['receivedAt'] = DateTime.now().millisecondsSinceEpoch;
            
            // Handle the emergency alert with the sanitized data
            try {
          await _handleEmergencyAlert(data);

            await doc.reference.update({
              'notifiedHelper': true,
              'notifiedAt': FieldValue.serverTimestamp(),
            });
            } catch (e) {
              debugPrint('❌ NOTIFICATION DEBUG: Error handling emergency alert: $e');
            }
          }
      });
    }
  }

  Future<void> sendPushNotification({
    required String recipientToken,
    required String title,
    required String body,
    required Map<String, dynamic> data,
    String channelId = 'default_channel',
    String? sound,
    bool fullScreenIntent = false,
  }) async {
    debugPrint('🔍 NOTIFICATION DEBUG: Starting sendPushNotification method');
    
    // Add notification metadata to the data payload so we always have it
    final Map<String, dynamic> enhancedData = {
      ...data,
      'title': title, // Store in data payload too for backup
      'body': body,
      'channel_id': channelId,
      'notification_id': DateTime.now().millisecondsSinceEpoch,
    };
    
    // Try direct notification first (will only work if app is in foreground)
    try {
      debugPrint('🔍 NOTIFICATION DEBUG: Trying direct local notification first');
      await showLocalNotification(
        id: enhancedData['notification_id'],
        title: title,
        body: body,
        payload: jsonEncode(_sanitizeDataForJson(enhancedData)),
        channelId: channelId,
        importance: Importance.high,
        priority: Priority.high,
      );
      debugPrint('✅ NOTIFICATION DEBUG: Direct local notification shown');
    } catch (e) {
      debugPrint('⚠️ NOTIFICATION DEBUG: Direct local notification failed: $e');
    }
    
    // Always store in Firestore for reliable delivery
    try {
      if (enhancedData.containsKey('recipientId')) {
        final recipientId = enhancedData['recipientId'];
        await _firestore.collection('notifications').add({
          'recipientId': recipientId,
          'title': title,
          'body': body,
          'data': _sanitizeDataForJson(enhancedData),
          'channelId': channelId,
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
          'fromDirect': true,
        });
        debugPrint('✅ NOTIFICATION DEBUG: Notification stored in Firestore for recipient: $recipientId');
      }
    } catch (e) {
      debugPrint('❌ NOTIFICATION DEBUG: Failed to store notification in Firestore: $e');
    }
    
    // Method 1: Legacy FCM HTTP v1
    final legacyPayload = {
      'to': recipientToken,
      'priority': 'high',
      'notification': {
        'title': title,
        'body': body,
        'android_channel_id': channelId,
        if (sound != null) 'sound': sound,
        if (fullScreenIntent) 'fullScreenIntent': true,
        'tag': 'clarity-${enhancedData['notification_id']}',
        'click_action': 'FLUTTER_NOTIFICATION_CLICK',
      },
      'data': _sanitizeDataForJson(enhancedData),
      'content_available': true,
      'mutable_content': true,
    };

    debugPrint('➡️ NOTIFICATION DEBUG: Sending FCM payload');

    try {
      final res = await http.post(
        Uri.parse('https://fcm.googleapis.com/fcm/send'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'key=$_firebaseServerKey',
        },
        body: jsonEncode(legacyPayload),
      );

      debugPrint('🔍 NOTIFICATION DEBUG: FCM HTTP Status: ${res.statusCode}');

      if (res.statusCode == 200) {
        final responseData = json.decode(res.body);
        debugPrint('✅ NOTIFICATION DEBUG: FCM HTTP Response: ${res.body}');
        final success = responseData['success'] ?? 0;
        
        if (success > 0) {
          debugPrint('✅ NOTIFICATION DEBUG: FCM sent successfully');
          return; // Successfully sent
        } else {
          final results = responseData['results'] as List?;
          final errorMsg = results != null && results.isNotEmpty ? results[0]['error'] : 'Unknown error';
          debugPrint('⚠️ NOTIFICATION DEBUG: FCM Error: $errorMsg');
        }
      } else {
        debugPrint('❌ NOTIFICATION DEBUG: FCM HTTP error: ${res.statusCode}, ${res.body}');
      }
    } catch (e) {
      debugPrint('❌ NOTIFICATION DEBUG: FCM error: $e');
    }
  }
  
  // Helper method to sanitize data for JSON serialization
  Map<String, dynamic> _sanitizeDataForJson(Map<String, dynamic> data) {
    final result = <String, dynamic>{};
    
    data.forEach((key, value) {
      if (value == null) {
        result[key] = null;
      } else if (value is Map) {
        result[key] = _sanitizeDataForJson(Map<String, dynamic>.from(value));
      } else if (value is List) {
        result[key] = _sanitizeListForJson(value);
      } else if (value is GeoPoint) {
        // Convert GeoPoint to a simple map with lat and lng
        result[key] = {
          'latitude': value.latitude,
          'longitude': value.longitude,
          '_isGeoPoint': true,
        };
      } else if (value is DateTime) {
        result[key] = value.millisecondsSinceEpoch;
      } else if (value is Timestamp) {
        result[key] = value.millisecondsSinceEpoch;
      } else if (_isPrimitiveType(value)) {
        result[key] = value;
      } else {
        // For other non-primitive types, convert to string
        result[key] = value.toString();
      }
    });
    
    return result;
  }
  
  List _sanitizeListForJson(List list) {
    return list.map((item) {
      if (item == null) {
        return null;
      } else if (item is Map) {
        return _sanitizeDataForJson(Map<String, dynamic>.from(item));
      } else if (item is List) {
        return _sanitizeListForJson(item);
      } else if (item is GeoPoint) {
        return {
          'latitude': item.latitude,
          'longitude': item.longitude,
          '_isGeoPoint': true,
        };
      } else if (item is DateTime) {
        return item.millisecondsSinceEpoch;
      } else if (item is Timestamp) {
        return item.millisecondsSinceEpoch;
      } else if (_isPrimitiveType(item)) {
        return item;
      } else {
        return item.toString();
      }
    }).toList();
  }
  
  bool _isPrimitiveType(dynamic value) {
    return value is String || value is num || value is bool;
  }
  
  // Intentionally leaving this comment as a marker for where the methods were removed
  // The _sendNotificationDirectlyToDevice and _extractRecipientFromChatRoom methods have been removed
  // as they're no longer needed with our new direct notification approach
  
  void dispose() {
    _emergencyAlertController.close();
    _newMessageController.close();
    _tts.stop();
  }

  // Listen for new notifications in Firestore
  void _setupNotificationListener() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    
    debugPrint('🔍 NOTIFICATION DEBUG: Setting up notification listener');
    debugPrint('🔍 NOTIFICATION DEBUG: User ID from SharedPreferences: $userId');

    // Check if user is blind to configure enhanced notifications
    final bool isBlindUser = prefs.getBool('is_blind_user') ?? false;
    if (isBlindUser) {
      debugPrint('👁️ NOTIFICATION DEBUG: Enhanced notifications enabled for blind user');
      // Set smart talking to true for blind users
      await setSmartTalkingEnabled(true);
      // Set longer TTS delay for blind users to ensure they can hear messages
      await _tts.setSpeechRate(0.45);  // Slightly slower speech rate
      await _tts.setVolume(1.0);       // Maximum volume
      // We'll ensure vibration is enabled for all notifications
    }
    
    if (userId == null) {
      // Try getting the current Firebase user ID
      final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
      if (firebaseUser != null) {
        await prefs.setString('user_id', firebaseUser.uid);
        debugPrint('✅ NOTIFICATION DEBUG: Updated user_id in SharedPreferences to: ${firebaseUser.uid}');
      } else {
        debugPrint('⚠️ NOTIFICATION DEBUG: No user ID available for notification listener');
        return;
      }
    }
    
    final currentUserId = userId ?? firebase_auth.FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) {
      debugPrint('⚠️ NOTIFICATION DEBUG: Could not determine current user ID for notification listener');
      return;
    }
    
    debugPrint('🔔 NOTIFICATION DEBUG: Setting up notification listener for user: $currentUserId');
    
    // Listen for new notifications for this user
    _firestore
        .collection('notifications')
        .where('recipientId', isEqualTo: currentUserId) // Only notifications for this user
        .where('isRead', isEqualTo: false)
        .snapshots()
        .listen((snapshot) async {
          debugPrint('🔍 NOTIFICATION DEBUG: Received notification snapshot with ${snapshot.docs.length} documents');
          
          // Process any new notifications
          for (final doc in snapshot.docs) {
            final data = doc.data();
            
            // Verify this notification is actually meant for this user
            final recipientId = data['recipientId'] as String?;
            if (recipientId != currentUserId) {
              debugPrint('⚠️ NOTIFICATION DEBUG: Skipping notification not meant for this user');
              continue;
            }
            
            debugPrint('📬 NOTIFICATION DEBUG: Processing notification: ${data['title']}');
            
            // Show local notification
            try {
              await showLocalNotification(
                id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                title: data['title'] as String? ?? 'New Message',
                body: data['body'] as String? ?? '',
                payload: jsonEncode(_sanitizeDataForJson(data['data'] as Map<String, dynamic>)),
                channelId: data['channelId'] as String? ?? 'messages_channel',
                importance: Importance.high,
                priority: Priority.high,
              );
              debugPrint('✅ NOTIFICATION DEBUG: Local notification shown for: ${data['title']}');
            } catch (e) {
              debugPrint('❌ NOTIFICATION DEBUG: Failed to show local notification: $e');
            }
            
            // Mark as read
            try {
              await doc.reference.update({'isRead': true});
              debugPrint('✅ NOTIFICATION DEBUG: Notification marked as read in Firestore');
            } catch (e) {
              debugPrint('❌ NOTIFICATION DEBUG: Failed to mark notification as read: $e');
            }
            
            // Forward to stream
            if (data['data'] != null && (data['data'] as Map).containsKey('chatRoomId')) {
              _newMessageController.add(data['data'] as Map<String, dynamic>);
              debugPrint('✅ NOTIFICATION DEBUG: Notification data added to stream');
            }
          }
        });
        
    debugPrint('✅ NOTIFICATION DEBUG: Firestore notification listener set up for user: $currentUserId');
  }
}
