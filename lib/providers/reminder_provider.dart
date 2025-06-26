import 'package:flutter/foundation.dart';
import '../models/reminder.dart';
import '../services/reminder_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ReminderProvider with ChangeNotifier {
  final ReminderService _reminderService = ReminderService();
  
  List<Reminder> _reminders = [];
  List<Reminder> get reminders => _reminders;
  
  List<Reminder> _upcomingReminders = [];
  List<Reminder> get upcomingReminders => _upcomingReminders;
  
  bool _isLoading = false;
  bool get isLoading => _isLoading;
  
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  
  String? _error;
  String? get error => _error;
  
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    _isLoading = true;
    notifyListeners();
    
    try {
      // Initialize the service
      await _reminderService.initialize();
      
      // Set up listeners for reminder triggers
      _setupReminderTriggerListener();
      
      // Load reminders
      await loadReminders();
      
      _isInitialized = true;
      _error = null;
    } catch (e) {
      _error = e.toString();
      debugPrint('❌ Error initializing RemindersProvider: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  void _setupReminderTriggerListener() {
    _reminderService.onReminderTriggered.listen((reminder) {
      debugPrint('📱 Reminder triggered: ${reminder.title}');
      // Refresh reminders after a trigger
      loadReminders();
    });
  }
  
  Future<void> loadReminders() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      // Check if we can access AuthProvider to get the current user ID
      final userId = await _getCurrentUserId();
      
      if (userId != null && userId.isNotEmpty) {
        debugPrint('📱 ReminderProvider - Loading reminders for user ID: $userId');
        
        // Get all reminders directly with the user ID
        final snapshot = await FirebaseFirestore.instance
            .collection('reminders')
            .where('userId', isEqualTo: userId)
            .get();
        
        _reminders = snapshot.docs
            .map((doc) => Reminder.fromMap(doc.data(), doc.id))
            .toList()
          ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
          
        debugPrint('📱 ReminderProvider - Loaded ${_reminders.length} reminders');
        
        // Get upcoming reminders
        final now = DateTime.now();
        _upcomingReminders = _reminders
            .where((reminder) => !reminder.isCompleted && reminder.dateTime.isAfter(now))
            .toList()
          ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
          
        debugPrint('📱 ReminderProvider - Loaded ${_upcomingReminders.length} upcoming reminders');
      } else {
        // Fall back to the service's method
        debugPrint('⚠️ ReminderProvider - No user ID available, falling back to service method');
        
        // Get all reminders
        _reminders = await _reminderService.getAllReminders();
        
        // Get upcoming reminders
        _upcomingReminders = await _reminderService.getUpcomingReminders();
      }
      
      _error = null;
    } catch (e) {
      _error = e.toString();
      debugPrint('❌ Error loading reminders: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Helper method to get current user ID
  Future<String?> _getCurrentUserId() async {
    try {
      // Try to get from SharedPreferences first
      final prefs = await SharedPreferences.getInstance();
      String? userId = prefs.getString('user_id');
      
      if (userId != null && userId.isNotEmpty) {
        return userId;
      }
      
      // If we can't get from SharedPreferences, check if we can get from Firebase Auth
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser != null) {
        // Save to SharedPreferences for future use
        await prefs.setString('user_id', firebaseUser.uid);
        return firebaseUser.uid;
      }
      
      return null;
    } catch (e) {
      debugPrint('❌ Error getting current user ID: $e');
      return null;
    }
  }
  
  Future<Reminder?> addReminder({
    required String title,
    required DateTime dateTime,
    required String userId,
    RecurrenceType recurrenceType = RecurrenceType.none,
  }) async {
    _isLoading = true;
    notifyListeners();
    
    try {
      final reminder = await _reminderService.addReminder(
        title: title,
        dateTime: dateTime,
        userId: userId,
        recurrenceType: recurrenceType,
      );
      
      if (reminder != null) {
        // Refresh reminders
        await loadReminders();
        
        // Announce success
        // No longer using voice announcement
      }
      
      _error = null;
      return reminder;
    } catch (e) {
      _error = e.toString();
      debugPrint('❌ Error adding reminder: $e');
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  Future<bool> updateReminder({
    required String id,
    String? title,
    DateTime? dateTime,
    RecurrenceType? recurrenceType,
    bool? isCompleted,
  }) async {
    _isLoading = true;
    notifyListeners();
    
    try {
      final success = await _reminderService.updateReminder(
        id: id,
        title: title,
        dateTime: dateTime,
        recurrenceType: recurrenceType,
        isCompleted: isCompleted,
      );
      
      if (success) {
        // Refresh reminders
        await loadReminders();
      }
      
      _error = null;
      return success;
    } catch (e) {
      _error = e.toString();
      debugPrint('❌ Error updating reminder: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  Future<bool> deleteReminder(String id) async {
    _isLoading = true;
    notifyListeners();
    
    try {
      final success = await _reminderService.deleteReminder(id);
      
      if (success) {
        // Refresh reminders
        await loadReminders();
      }
      
      _error = null;
      return success;
    } catch (e) {
      _error = e.toString();
      debugPrint('❌ Error deleting reminder: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  Future<bool> markReminderAsCompleted(String id) async {
    try {
      final success = await _reminderService.markReminderAsCompleted(id);
      
      if (success) {
        // Refresh reminders
        await loadReminders();
      }
      
      return success;
    } catch (e) {
      debugPrint('❌ Error marking reminder as completed: $e');
      return false;
    }
  }
  
  Future<List<Reminder>> getUserReminders(String userId, {String? helperId}) async {
    try {
      return await _reminderService.getAllRemindersForUser(userId, helperId);
    } catch (e) {
      debugPrint('❌ Error getting user reminders: $e');
      return [];
    }
  }
  
}
