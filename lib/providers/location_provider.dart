import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;

/// LocationProvider: Provider لإدارة ومتابعة الموقع الحالي للمستخدم والتزامن مع Firestore
class LocationProvider with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final firebase_auth.FirebaseAuth _auth = firebase_auth.FirebaseAuth.instance;

  Position? _currentPosition;
  bool _isLoading = false;
  String? _error;
  bool _isTracking = false;
  StreamSubscription<Position>? _positionStreamSubscription;
  DateTime? _lastFirestoreUpdate;

  /// Getter للموقع الحالي
  Position? get currentPosition => _currentPosition;

  /// هل جاري تحميل الموقع الحالي؟
  bool get isLoading => _isLoading;

  /// رسالة الخطأ الحالية (إن وجدت)
  String? get error => _error;

  /// هل تتبع الموقع شغّال؟
  bool get isTracking => _isTracking;

  /// جلب الموقع الحالي مرة واحدة
  Future<void> getCurrentLocation() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled.');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions are denied');
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions are permanently denied');
      }

      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _error = 'Error getting location: ${e is Exception ? e.toString() : "Unknown error"}';
      notifyListeners();
    }
  }

  /// البدء في تتبع الموقع بشكل حي (Stream)
  Future<void> startLocationTracking() async {
    if (_isTracking) return;

    try {
      _isTracking = true;
      _error = null;
      notifyListeners();

      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((Position position) async {
        _currentPosition = position;
        final user = _auth.currentUser;
        final now = DateTime.now();

        // كتابة على فايربيز كل 10 ثواني فقط
        if (user != null && (_lastFirestoreUpdate == null ||
            now.difference(_lastFirestoreUpdate!) > const Duration(seconds: 10))) {
          _lastFirestoreUpdate = now;
          await _firestore.collection('user_locations').doc(user.uid).set({
            'latitude': position.latitude,
            'longitude': position.longitude,
            'timestamp': FieldValue.serverTimestamp(),
            'accuracy': position.accuracy,
            'altitude': position.altitude,
            'speed': position.speed,
            'speedAccuracy': position.speedAccuracy,
          }, SetOptions(merge: true));
        }
        notifyListeners();
      });
    } catch (e) {
      _isTracking = false;
      _error = 'Error starting tracking: ${e is Exception ? e.toString() : "Unknown error"}';
      notifyListeners();
    }
  }

  /// إيقاف تتبع الموقع
  void stopLocationTracking() {
    _isTracking = false;
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    notifyListeners();
  }

  /// حذف رسالة الخطأ الحالية
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// تنظيف الموارد عند التخلص من الـProvider
  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    super.dispose();
  }
}
