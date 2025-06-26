import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/sensor_data_model.dart';

class FirebaseService {
  // Singleton instance
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  // Firestore references
  late final FirebaseFirestore _firestore;
  late final CollectionReference _sensorCollection;
  late final CollectionReference _latestCollection;
  late final CollectionReference _usersCollection;

  // State
  bool _isInitialized = false;
  String _lastError = '';

  // Getters
  bool get isInitialized => _isInitialized;
  String get lastError => _lastError;

  // Initialization
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    try {
      await Firebase.initializeApp();
      _firestore = FirebaseFirestore.instance;
      _sensorCollection = _firestore.collection('sensor_data');
      _latestCollection = _firestore.collection('latest_readings');
      _usersCollection = _firestore.collection('users');
      _isInitialized = true;
      return true;
    } catch (e) {
      _lastError = 'Failed to initialize Firebase: $e';
      debugPrint(_lastError);
      return false;
    }
  }

  // Send notification (FireStore only)
  Future<bool> sendNotificationToUser(
    String userID,
    String title,
    String body,
    Map<String, dynamic> data,
  ) async {
    if (!_isInitialized) {
      final initSuccess = await initialize();
      if (!initSuccess) return false;
    }
    try {
      final userDoc = await _usersCollection.doc(userID).get();
      if (!userDoc.exists) {
        _lastError = 'User not found';
        return false;
      }
      final userData = userDoc.data() as Map<String, dynamic>?;
      final fcmToken = userData?['fcmToken'] as String?;
      if (fcmToken == null || fcmToken.isEmpty) {
        _lastError = 'User does not have a valid FCM token';
        return false;
      }
      // Save notification for user (as a record)
      await _firestore.collection('notifications').add({
        'userID': userID,
        'title': title,
        'body': body,
        'data': data,
        'read': false,
        'timestamp': FieldValue.serverTimestamp(),
      });
      await _usersCollection.doc(userID).collection('notifications').add({
        'title': title,
        'body': body,
        'data': data,
        'read': false,
        'timestamp': FieldValue.serverTimestamp(),
      });
      // Actual push requires Cloud Function or FCM logic (not included here)
      return true;
    } catch (e) {
      _lastError = 'Failed to send notification: $e';
      debugPrint(_lastError);
      return false;
    }
  }

  // Add sensor data
  Future<bool> addSensorData(SensorData data) async {
    if (!_isInitialized) {
      final initSuccess = await initialize();
      if (!initSuccess) return false;
    }
    try {
      await _sensorCollection.add(data.toFirestore());
      await _latestCollection.doc('smart_glasses').set({
        ...data.toFirestore(),
        'last_updated': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      _lastError = 'Failed to add sensor data: $e';
      debugPrint(_lastError);
      return false;
    }
  }

  // Get available assistants
  Future<List<Map<String, dynamic>>> getAvailableAssistants() async {
    if (!_isInitialized) {
      final initSuccess = await initialize();
      if (!initSuccess) return [];
    }
    try {
      final snapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'assistant')
          .where('isAvailable', isEqualTo: true)
          .get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['displayName'] ?? 'Assistant',
          'email': data['email'] ?? '',
          'photoURL': data['photoURL'] ?? '',
          'lastActive': data['lastActive'],
        };
      }).toList();
    } catch (e) {
      _lastError = 'Failed to get available assistants: $e';
      debugPrint(_lastError);
      return [];
    }
  }

  // Link blind user with assistant
  Future<bool> linkUserWithAssistant(
      String blindUserID, String assistantID) async {
    if (!_isInitialized) {
      final initSuccess = await initialize();
      if (!initSuccess) return false;
    }
    try {
      await _usersCollection.doc(blindUserID).update({
        'linkedAssistants': FieldValue.arrayUnion([assistantID]),
      });
      await _usersCollection.doc(assistantID).update({
        'linkedUsers': FieldValue.arrayUnion([blindUserID]),
      });
      await _firestore.collection('connections').add({
        'blindUserID': blindUserID,
        'assistantID': assistantID,
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      _lastError = 'Failed to link user with assistant: $e';
      debugPrint(_lastError);
      return false;
    }
  }

  // Get linked assistants for user
  Future<List<Map<String, dynamic>>> getLinkedAssistants(String userID) async {
    if (!_isInitialized) {
      final initSuccess = await initialize();
      if (!initSuccess) return [];
    }
    try {
      final userDoc = await _usersCollection.doc(userID).get();
      if (!userDoc.exists) return [];
      final userData = userDoc.data() as Map<String, dynamic>;
      final linkedAssistants =
          List<String>.from(userData['linkedAssistants'] ?? []);
      if (linkedAssistants.isEmpty) return [];
      final assistantsData = <Map<String, dynamic>>[];
      for (final assistantID in linkedAssistants) {
        final assistantDoc = await _usersCollection.doc(assistantID).get();
        if (assistantDoc.exists) {
          final data = assistantDoc.data() as Map<String, dynamic>;
          assistantsData.add({
            'id': assistantDoc.id,
            'name': data['displayName'] ?? 'Assistant',
            'email': data['email'] ?? '',
            'photoURL': data['photoURL'] ?? '',
            'lastActive': data['lastActive'],
            'isAvailable': data['isAvailable'] ?? false,
          });
        }
      }
      return assistantsData;
    } catch (e) {
      _lastError = 'Failed to get linked assistants: $e';
      debugPrint(_lastError);
      return [];
    }
  }

  // Latest sensor data as stream
  Stream<DocumentSnapshot> getLatestDataStream() {
    if (!_isInitialized) {
      initialize();
    }
    return _latestCollection.doc('smart_glasses').snapshots();
  }

  // Get recent data
  Future<List<SensorData>> getRecentData({int limit = 20}) async {
    if (!_isInitialized) {
      final initSuccess = await initialize();
      if (!initSuccess) return [];
    }
    try {
      final snapshot = await _sensorCollection
          .orderBy('created_at', descending: true)
          .limit(limit)
          .get();
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        // Safely parse timestamp
        DateTime time;
        if (data['created_at'] is Timestamp) {
          time = (data['created_at'] as Timestamp).toDate();
        } else if (data['created_at'] is int) {
          time = DateTime.fromMillisecondsSinceEpoch(data['created_at']);
        } else {
          time = DateTime.now();
        }
        return SensorData(
          temperature: (data['temperature'] as num).toDouble(),
          humidity: (data['humidity'] as num).toDouble(),
          distance: (data['distance'] as num).toDouble(),
          motionDetected: data['motion_detected'] as bool,
          gyroX: (data['gyro_x'] as num).toDouble(),
          gyroY: (data['gyro_y'] as num).toDouble(),
          gyroZ: (data['gyro_z'] as num).toDouble(),
          accelX: (data['accel_x'] as num).toDouble(),
          accelY: (data['accel_y'] as num).toDouble(),
          accelZ: (data['accel_z'] as num).toDouble(),
          timestamp: time,
        );
      }).toList();
    } catch (e) {
      _lastError = 'Failed to get recent data: $e';
      debugPrint(_lastError);
      return [];
    }
  }

  // Delete old sensor data
  Future<bool> deleteOldData({int olderThanDays = 30}) async {
    if (!_isInitialized) {
      final initSuccess = await initialize();
      if (!initSuccess) return false;
    }
    try {
      final timestamp = DateTime.now()
          .subtract(Duration(days: olderThanDays))
          .millisecondsSinceEpoch;
      final snapshot = await _sensorCollection
          .where('created_at', isLessThan: timestamp)
          .get();
      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      return true;
    } catch (e) {
      _lastError = 'Failed to delete old data: $e';
      debugPrint(_lastError);
      return false;
    }
  }
}
