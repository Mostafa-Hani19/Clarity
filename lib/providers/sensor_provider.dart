import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/sensor_data.dart';

class SensorProvider extends ChangeNotifier {
  static const String dbUrl = 'https://clarity-app-1d42c-default-rtdb.europe-west1.firebasedatabase.app';
  late final DatabaseReference _database;
  // Store the broadcast stream
  late final Stream<DatabaseEvent> _onValueStream;
  bool _isInitialized = false;
  DateTime? _lastUpdated;
  SensorData? _currentData;

  // Getters
  bool get isInitialized => _isInitialized;
  DateTime? get lastUpdated => _lastUpdated;
  SensorData? get currentData => _currentData;

  SensorProvider() {
    _initializeFirebase();
  }

  Future<void> _initializeFirebase() async {
    try {
      _database = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: dbUrl,
      ).ref('smart_glasses');

      // Create a broadcast stream to allow multiple listeners
      _onValueStream = _database.onValue.asBroadcastStream();

      _onValueStream.listen((event) {
        if (event.snapshot.value != null) {
          final data = event.snapshot.value as Map<dynamic, dynamic>;
          _lastUpdated = DateTime.now();
          
          // Convert Map<dynamic, dynamic> to Map<String, dynamic> properly
          final Map<String, dynamic> sensorData = {};
          data.forEach((key, value) {
            if (key is String) {
              // Handle nested maps - 'gyro' and 'accel' need special treatment
              if (value is Map) {
                final nestedMap = <String, dynamic>{};
                value.forEach((nestedKey, nestedValue) {
                  if (nestedKey is String) {
                    nestedMap[nestedKey] = nestedValue;
                  }
                });
                sensorData[key] = nestedMap;
              } else {
                sensorData[key] = value;
              }
            }
          });
          
          _currentData = SensorData.fromMap(sensorData);
          _isInitialized = true;
          notifyListeners();
        }
      }, onError: (error) {
        debugPrint('Firebase Error: $error');
        _isInitialized = false;
        notifyListeners();
      });
    } catch (e) {
      debugPrint('Error initializing Firebase: $e');
      _isInitialized = false;
      notifyListeners();
    }
  }

  void refresh() {
    _initializeFirebase();
  }
} 