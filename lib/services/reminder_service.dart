import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';
import '../models/reminder.dart';
import 'notification_service.dart';
import 'package:intl/intl.dart';
import 'package:flutter_tts/flutter_tts.dart';

class ReminderService {
  static final ReminderService _instance = ReminderService._internal();
  
  factory ReminderService() {
    return _instance;
  }
  
  ReminderService._internal();
  
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  final StreamController<Reminder> _reminderController = StreamController<Reminder>.broadcast();
  final Map<String, Timer> _reminderTimers = {};
  // ignore: unused_field
  final NotificationService _notificationService = NotificationService();
  
  // Get stream of reminders
  Stream<Reminder> get onReminderTriggered => _reminderController.stream;
  
  // Initialize the service
  Future<void> initialize() async {
    await _createNotificationChannel();
    await _loadUpcomingReminders();
  }
  
  // Create dedicated notification channel for reminders
  Future<void> _createNotificationChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'reminders_channel',
      'Reminders',
      description: 'Notifications for scheduled reminders',
      importance: Importance.high,
      enableVibration: true,
      enableLights: true,
      ledColor: Colors.blue,
      playSound: true,
    );
    
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    
    // Initialize notification settings
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@drawable/notification_icon');
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings();
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );
    
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
    
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }
  
  // Load upcoming reminders for the current user
  Future<void> _loadUpcomingReminders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      
      if (userId == null) {
        debugPrint('⚠️ User not logged in, cannot load reminders');
        return;
      }
      
      // Get reminders for today and future dates
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      
      // Use simple query and filter in memory
      final snapshot = await _firestore
          .collection('reminders')
          .where('userId', isEqualTo: userId)
          .get();
          
      for (final doc in snapshot.docs) {
        final reminder = Reminder.fromMap(doc.data(), doc.id);
        if (!reminder.isCompleted && reminder.dateTime.isAfter(startOfDay)) {
          _scheduleReminder(reminder);
        }
      }
      debugPrint('✅ Loaded upcoming reminders');
    } catch (e) {
      debugPrint('❌ Error loading reminders: $e');
    }
  }
  
  // Schedule a reminder with timer
  void _scheduleReminder(Reminder reminder) {
    final now = DateTime.now();
    
    // Calculate time until reminder
    final timeUntilReminder = reminder.dateTime.difference(now);
    
    // Only schedule if the reminder is in the future
    if (timeUntilReminder.isNegative) {
      debugPrint('⏱️ Reminder "${reminder.title}" is in the past, skipping');
      return;
    }
    
    // Cancel existing timer if there is one
    _reminderTimers[reminder.id]?.cancel();
    
    // Create a new timer
    _reminderTimers[reminder.id] = Timer(timeUntilReminder, () {
      _triggerReminder(reminder);
    });
    
    debugPrint('⏱️ Scheduled reminder "${reminder.title}" for ${reminder.dateTime}');
  }
  
  // Trigger a reminder
  Future<void> _triggerReminder(Reminder reminder) async {
    try {
      debugPrint('🔔 Triggering reminder: "${reminder.title}" at ${reminder.dateTime}');
      
      final message = '${reminder.title}, ${DateFormat('h:mm a').format(reminder.dateTime)}';
      
      // Repeat the alert 3 times for emphasis
      for (int i = 0; i < 3; i++) {
        // Vibrate in a pattern to indicate reminder
        if (await Vibration.hasVibrator()) {
          // Pattern: wait 100ms, vibrate 800ms
          Vibration.vibrate(pattern: [100, 800]);
        }
        
        // Use text-to-speech to announce the reminder
        await _announceReminder(message);
        
        // Wait a bit between repetitions if not the last one
        if (i < 2) {
          await Future.delayed(const Duration(seconds: 1));
        }
      }
      
      // Show notification
      await _showReminderNotification(reminder);
      
      // Add to stream
      _reminderController.add(reminder);
      
      // Handle recurring reminders
      if (reminder.recurrenceType != RecurrenceType.none) {
        await _scheduleNextRecurrence(reminder);
      }
      
      // If not recurring, mark as completed
      if (reminder.recurrenceType == RecurrenceType.none) {
        await markReminderAsCompleted(reminder.id);
      }
    } catch (e) {
      debugPrint('❌ Error triggering reminder: $e');
    }
  }
  
  // Announce reminder using text-to-speech
  Future<void> _announceReminder(String message) async {
    try {
      // Initialize TTS if not already done
      if (!_isTtsInitialized) {
        await _initializeTts();
      }
      
      // Speak the message
      await _flutterTts.speak(message);
      
      // Wait for speech to complete
      await Future.delayed(const Duration(seconds: 2));
    } catch (e) {
      debugPrint('❌ Error announcing reminder: $e');
    }
  }
  
  // Initialize text-to-speech
  bool _isTtsInitialized = false;
  final FlutterTts _flutterTts = FlutterTts();
  
  Future<void> _initializeTts() async {
    try {
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      _isTtsInitialized = true;
    } catch (e) {
      debugPrint('❌ Error initializing TTS: $e');
    }
  }
  
  // Show notification for reminder
  Future<void> _showReminderNotification(Reminder reminder) async {
    AndroidNotificationDetails androidDetails = const AndroidNotificationDetails(
      'reminders_channel',
      'Reminders',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      enableLights: true,
      ledColor: Colors.blue,
      ledOnMs: 1000, // LED on for 1 second
      ledOffMs: 500, // LED off for 0.5 seconds
    );
    
    DarwinNotificationDetails iosDetails = const DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    
    NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    await _localNotifications.show(
      reminder.hashCode,
      'Reminder',
      reminder.title,
      details,
      payload: reminder.id,
    );
  }
  
  // Schedule next recurrence for recurring reminder
  Future<void> _scheduleNextRecurrence(Reminder reminder) async {
    DateTime nextDateTime;
    
    if (reminder.recurrenceType == RecurrenceType.daily) {
      nextDateTime = reminder.dateTime.add(const Duration(days: 1));
    } else if (reminder.recurrenceType == RecurrenceType.weekly) {
      nextDateTime = reminder.dateTime.add(const Duration(days: 7));
    } else {
      return; // Not a recurring reminder
    }
    
    // Create new reminder with next date
    final nextReminder = reminder.copyWith(
      id: const Uuid().v4(),
      dateTime: nextDateTime,
      isCompleted: false,
    );
    
    // Save to database
    await addReminder(
      title: nextReminder.title,
      dateTime: nextReminder.dateTime,
      userId: nextReminder.userId,
      recurrenceType: nextReminder.recurrenceType,
    );
    
    debugPrint('🔄 Scheduled next recurrence for "${reminder.title}" on $nextDateTime');
  }
  
  // Add a new reminder
  Future<Reminder?> addReminder({
    required String title,
    required DateTime dateTime,
    required String userId,
    RecurrenceType recurrenceType = RecurrenceType.none,
    bool syncWithGoogleCalendar = false,
  }) async {
    try {
      if (userId.isEmpty) {
        debugPrint('⚠️ Cannot add reminder: Invalid user ID');
        return null;
      }
      
      // Create reminder
      final reminder = Reminder(
        id: const Uuid().v4(),
        title: title,
        dateTime: dateTime,
        recurrenceType: recurrenceType,
        userId: userId,
        isSynced: syncWithGoogleCalendar,
      );
      
      // Save to Firestore
      await _firestore
          .collection('reminders')
          .doc(reminder.id)
          .set(reminder.toMap());
      
      // Schedule the reminder
      _scheduleReminder(reminder);
      
      debugPrint('✅ Added reminder "$title" for $dateTime');
      return reminder;
    } catch (e) {
      debugPrint('❌ Error adding reminder: $e');
      return null;
    }
  }
  
  // Update an existing reminder
  Future<bool> updateReminder({
    required String id,
    String? title,
    DateTime? dateTime,
    RecurrenceType? recurrenceType,
    bool? isCompleted,
    bool syncWithGoogleCalendar = false,
  }) async {
    try {
      final reminderDoc = await _firestore.collection('reminders').doc(id).get();
      
      if (!reminderDoc.exists) {
        debugPrint('⚠️ Reminder not found: $id');
        return false;
      }
      
      final currentReminder = Reminder.fromMap(reminderDoc.data()!, id);
      
      // Create updated reminder
      final updatedReminder = currentReminder.copyWith(
        title: title,
        dateTime: dateTime,
        recurrenceType: recurrenceType,
        isCompleted: isCompleted,
        isSynced: syncWithGoogleCalendar ? true : currentReminder.isSynced,
      );
      
      // Update in Firestore
      await _firestore
          .collection('reminders')
          .doc(id)
          .update(updatedReminder.toMap());
      
      // Cancel existing timer if time changed
      if (dateTime != null && dateTime != currentReminder.dateTime) {
        _reminderTimers[id]?.cancel();
        _scheduleReminder(updatedReminder);
      }
      
      debugPrint('✅ Updated reminder "$id"');
      return true;
    } catch (e) {
      debugPrint('❌ Error updating reminder: $e');
      return false;
    }
  }
  
  // Delete a reminder
  Future<bool> deleteReminder(String id) async {
    try {
      final reminderDoc = await _firestore.collection('reminders').doc(id).get();
      
      if (!reminderDoc.exists) {
        debugPrint('⚠️ Reminder not found: $id');
        return false;
      }
      
      // Delete from Firestore
      await _firestore.collection('reminders').doc(id).delete();
      
      // Cancel timer
      _reminderTimers[id]?.cancel();
      _reminderTimers.remove(id);
      
      debugPrint('✅ Deleted reminder "$id"');
      return true;
    } catch (e) {
      debugPrint('❌ Error deleting reminder: $e');
      return false;
    }
  }
  
  // Mark a reminder as completed
  Future<bool> markReminderAsCompleted(String id) async {
    try {
      return await updateReminder(id: id, isCompleted: true);
    } catch (e) {
      debugPrint('❌ Error marking reminder as completed: $e');
      return false;
    }
  }
  
  // Get all reminders for current user
  Future<List<Reminder>> getAllReminders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Try multiple keys for user ID - this helps with compatibility
      String? userId = prefs.getString('user_id');
      
      if (userId == null || userId.isEmpty) {
        debugPrint('⚠️ Trying alternative user ID keys in SharedPreferences');
        // Try other keys that might be used by AuthProvider
        userId = prefs.getString('userEmailKey');
      }
      
      if (userId == null || userId.isEmpty) {
        debugPrint('⚠️ User not logged in, cannot get reminders');
        return [];
      }
      
      debugPrint('📱 Getting reminders for user ID: $userId');
      
      // Use simple query and sort in memory
      final snapshot = await _firestore
          .collection('reminders')
          .where('userId', isEqualTo: userId)
          .get();
      
      final reminders = snapshot.docs
          .map((doc) => Reminder.fromMap(doc.data(), doc.id))
          .toList()
        ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
        
      debugPrint('📱 Retrieved ${reminders.length} reminders');
      return reminders;
    } catch (e) {
      debugPrint('❌ Error getting reminders: $e');
      return [];
    }
  }
  
  // Get all reminders for a specific user and optionally a helper
  Future<List<Reminder>> getAllRemindersForUser(String userId, String? helperId) async {
    try {
      final query = _firestore.collection('reminders');
      QuerySnapshot snapshot;

      if (helperId != null && helperId.isNotEmpty) {
        snapshot = await query.where('userId', whereIn: [userId, helperId]).get();
      } else {
        snapshot = await query.where('userId', isEqualTo: userId).get();
      }
      
      return snapshot.docs
          .map((doc) => Reminder.fromMap(doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    } catch (e) {
      debugPrint('❌ Error getting all reminders for user: $e');
      return [];
    }
  }
  
  // Get upcoming reminders (not completed and in the future)
  Future<List<Reminder>> getUpcomingReminders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Try multiple keys for user ID - this helps with compatibility
      String? userId = prefs.getString('user_id');
      
      if (userId == null || userId.isEmpty) {
        debugPrint('⚠️ Trying alternative user ID keys in SharedPreferences');
        // Try other keys that might be used by AuthProvider
        userId = prefs.getString('userEmailKey');
      }
      
      if (userId == null || userId.isEmpty) {
        debugPrint('⚠️ User not logged in, cannot get reminders');
        return [];
      }
      
      debugPrint('📱 Getting upcoming reminders for user ID: $userId');
      
      final now = DateTime.now();
      
      // Use simple query and filter in memory
      final snapshot = await _firestore
          .collection('reminders')
          .where('userId', isEqualTo: userId)
          .get();
          
      final reminders = snapshot.docs
          .map((doc) => Reminder.fromMap(doc.data(), doc.id))
          .where((reminder) => 
            !reminder.isCompleted && 
            reminder.dateTime.isAfter(now))
          .toList()
        ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
        
      debugPrint('📱 Retrieved ${reminders.length} upcoming reminders');
      return reminders;
    } catch (e) {
      debugPrint('❌ Error getting upcoming reminders: $e');
      return [];
    }
  }
  
  // Dispose
  void dispose() {
    // Cancel all timers
    for (final timer in _reminderTimers.values) {
      timer.cancel();
    }
    _reminderTimers.clear();
    
    // Close stream
    _reminderController.close();
  }
} 