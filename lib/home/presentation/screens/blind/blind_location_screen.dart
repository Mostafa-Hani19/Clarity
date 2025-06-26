import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../services/location_service.dart';
import '../../../../services/language_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:http/http.dart' as http;
import 'dart:math' as math;
import 'package:geocoding/geocoding.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

class LocationSenderScreen extends StatefulWidget {
  const LocationSenderScreen({super.key});

  @override
  State<LocationSenderScreen> createState() => _LocationSenderScreenState();
}

class _LocationSenderScreenState extends State<LocationSenderScreen> {
  // Services
  final LocationService _locationService = LocationService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FlutterTts _flutterTts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final AudioPlayer _audioPlayer = AudioPlayer();

  // Map controller
  final Completer<GoogleMapController> _mapController =
      Completer<GoogleMapController>();

  // Markers
  final Set<Marker> _markers = {};

  // Location data
  LatLng? _myLocation;
  String? _myAddress;
  LatLng? _destinationLocation;
  String? _destinationAddress;

  // State management
  bool _isLoading = true;
  bool _isNavigating = false;
  String _navigationStatus = '';
  String _distanceToDestination = '';
  String _estimatedTime = '';

  // User related information
  String? _pairedHelperId;
  String? _pairedHelperName;
  bool _isBlindUser = false;

  // Stream subscriptions
  StreamSubscription? _locationStreamSubscription;
  StreamSubscription? _addressStreamSubscription;
  StreamSubscription<Position>? _liveLocationSubscription;

  // Firebase location references
  late DocumentReference _userLocationRef;
  late DocumentReference _sharedLocationRef;
  late CollectionReference _locationHistoryRef;

  // Periodic location update timer
  Timer? _locationUpdateTimer;

  // Location update status
  // ignore: unused_field
  bool _lastUpdateSuccessful = false;
  // ignore: unused_field
  String _lastUpdateError = '';
  int _updateAttempts = 0;

  // Live location tracking state
  bool _isLiveTracking = false;
  int _liveUpdateCount = 0;

  // Favorite locations
  List<Map<String, dynamic>> _favoriteLocations = [];
  StreamSubscription? _favoritesSubscription;

  // Polylines
  final Set<Polyline> _polylines = {};

  // Store navigation instructions and route information
  // ignore: unused_field
  List<String> _routeInstructions = [];
  bool _hasShownRouteInfo = false;

  Timer? _navigationSoundTimer;
  bool _isPlayingDirectionalSound = false;
  
  // Route deviation detection
  List<LatLng> _routePoints = [];
  bool _isOnRoute = true;
  int _consecutiveOffRouteUpdates = 0;
  int _consecutiveOnRouteUpdates = 0;
  Timer? _routeCheckTimer;

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _setupFirebaseReferences();
    // Get location quickly with a progressive approach
    _getInitialLocationFast();
    // Initialize favorites listener
    _loadFavoriteLocations();
  }

  // Initialize necessary services
  Future<void> _initializeServices() async {
    try {
      // Get current app language
      final languageService = LanguageService();
      final currentLanguage = await languageService.getCurrentLanguage();
      await _updateTTSLanguage(currentLanguage.code);

      // Initialize Text-to-Speech with the appropriate language
      await _updateTTSLanguage(currentLanguage.code);
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      // Initialize Speech Recognition
      await _speech.initialize(
        onStatus: (status) => debugPrint('Speech recognition status: $status'),
        onError: (error) => debugPrint('Speech recognition error: $error'),
      );

      // Check user accessibility preferences
      await _checkUserType();

      // Load audio guidance sounds
      await _preloadNavigationSounds();

      // Announce that the app is ready
      _speak('Location screen ready. Your location is being tracked.');
    } catch (e) {
      debugPrint('Error initializing services: $e');
    }
  }
  // Preload navigation sounds
  Future<void> _preloadNavigationSounds() async {
    try {
      await _audioPlayer
          .setSourceAsset('assets/sounds/beep-02.mp3');
          // .setSourceUrl('https://www.soundjay.com/buttons/beep-1.mp3');

    } catch (e) {
      debugPrint('Error preloading navigation sounds: $e');
    }
  }

  // Set up Firebase references for location
  void _setupFirebaseReferences() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // User's own location document
      _userLocationRef = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('location')
          .doc('current');

      // Public shared location document (easier for helpers to access)
      _sharedLocationRef =
          _firestore.collection('shared_locations').doc(user.uid);

      // Location history collection for this user
      _locationHistoryRef = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('location_history');

      // Get paired helper information
      _getPairedHelper();

      // Create live location stream document
      _firestore.collection('live_locations').doc(user.uid).set({
        'isActive': true,
        'userId': user.uid,
        'userType': 'blind',
        'startedAt': FieldValue.serverTimestamp(),
        'lastSeenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  // Fast initial location detection with progressive accuracy
  Future<void> _getInitialLocationFast() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      // First check permissions
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final requestedPermission = await Geolocator.requestPermission();
        if (requestedPermission == LocationPermission.denied ||
            requestedPermission == LocationPermission.deniedForever) {
          if (mounted) {
            setState(() => _isLoading = false);
            _showLocationPermissionError();
          }
          return;
        }
      }

      // Check if location services are enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() => _isLoading = false);
          _showLocationServicesDisabledError();
        }
        return;
      }

      // Try to get last known position first (fastest)
      try {
        final Position? lastPosition = await Geolocator.getLastKnownPosition();
        if (lastPosition != null && mounted) {
          setState(() {
            _myLocation = LatLng(lastPosition.latitude, lastPosition.longitude);
            _updateMarkers();
            // Don't set _isLoading to false yet, we'll still try to get a more accurate position
          });

          // Move camera to this position immediately
          if (_mapController.isCompleted && mounted) {
            final controller = await _mapController.future;
            controller
                .animateCamera(CameraUpdate.newLatLngZoom(_myLocation!, 15));
          }

          // Get address for this position
          _getAddressFromPosition(_myLocation!).then((address) {
            if (mounted && address != null) {
              setState(() => _myAddress = address);
              _updateFirebaseLocation(forceUpdate: true);
            }
          });
        }
      } catch (e) {
        debugPrint('Error getting last known position: $e');
      }

      // Then try to get a quick but less accurate position (faster than high accuracy)
      try {
        final Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.reduced,
          timeLimit: const Duration(seconds: 5),
        );

        if (mounted) {
          setState(() {
            _myLocation = LatLng(position.latitude, position.longitude);
            _updateMarkers();
          });

          // Move camera to this position
          if (_mapController.isCompleted && mounted) {
            final controller = await _mapController.future;
            controller
                .animateCamera(CameraUpdate.newLatLngZoom(_myLocation!, 15));
          }

          // Get address for this position
          _getAddressFromPosition(_myLocation!).then((address) {
            if (mounted && address != null) {
              setState(() => _myAddress = address);
              _updateFirebaseLocation(forceUpdate: true);
            }
          });
        }
      } catch (e) {
        debugPrint('Error getting quick position: $e');
      }

      // Finally start the full location tracking system
      if (mounted) {
        _startLocationUpdates();
      }

      // Start live location tracking with more resilient settings
      if (mounted) {
        _startLiveLocationTrackingWithRetry();
      }
    } catch (e) {
      debugPrint('Error in fast location detection: $e');
      // Fall back to standard location updates
      if (mounted) {
        _startLocationUpdates();
      }
    }
  }

  // Start location updates
  void _startLocationUpdates() async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    // Check location permissions first
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      final requestedPermission = await Geolocator.requestPermission();
      if (requestedPermission == LocationPermission.denied ||
          requestedPermission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _isLoading = false);
          _showLocationPermissionError();
        }
        return;
      }
    }

    // Check if location services are enabled
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showLocationServicesDisabledError();
      }
      return;
    }

    // Get last known position
    try {
      final Position? lastPosition = await Geolocator.getLastKnownPosition();
      if (lastPosition != null && mounted) {
        setState(() {
          _myLocation = LatLng(lastPosition.latitude, lastPosition.longitude);
          _updateMarkers();
        });

        // Get address for this position
        _getAddressFromPosition(_myLocation!).then((address) {
          if (mounted && address != null) {
            setState(() => _myAddress = address);
            // Immediately send initial location to Firebase
            _updateFirebaseLocation(forceUpdate: true);
          }
        });
      }
    } catch (e) {
      debugPrint('Error getting last known position: $e');
    }

    // Start location tracking
    final success = await _locationService.startTracking();

    if (success) {
      // Subscribe to location updates
      _locationStreamSubscription =
          _locationService.locationStream.listen((location) {
        if (mounted && location != null) {
          setState(() {
            _myLocation = location;
            _updateMarkers();
          });

          // Move camera to follow location if not navigating
          if (_mapController.isCompleted && !_isNavigating && mounted) {
            _animateToPosition(location);
          }

          // Update Firebase with current location
          _updateFirebaseLocation();
        }
      });

      // Subscribe to address updates
      _addressStreamSubscription =
          _locationService.addressStream.listen((address) {
        if (mounted) {
          setState(() => _myAddress = address);
          // Update Firebase when address changes
          _updateFirebaseLocation();
        }
      });

      // Set up periodic location updates to Firebase
      _locationUpdateTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        if (mounted) {
          _updateFirebaseLocation();
        }
      });
    } else {
      // Show permission error
      if (mounted) {
        setState(() => _isLoading = false);
        _showLocationPermissionError();
      }
      return;
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  // Show location permission error
  void _showLocationPermissionError() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Location permission denied. Navigation features will not work.'
                .tr()),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Settings'.tr(),
          onPressed: () async {
            await Geolocator.openAppSettings();
          },
        ),
      ),
    );
  }

  // Show location services disabled error
  void _showLocationServicesDisabledError() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('location_services_disabled'.tr()),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'settings'.tr(),
          onPressed: () async {
            await Geolocator.openLocationSettings();
          },
        ),
      ),
    );
  }

  // Check if user is blind or sighted
  Future<void> _checkUserType() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists && userDoc.data() != null) {
        final userData = userDoc.data()!;
        setState(() {
          _isBlindUser = userData['accessibilityNeeds'] == 'blind' ||
              userData['userType'] == 'blind' ||
              userData['isBlindUser'] == true;
        });

        // Also update this in user document to ensure consistency
        if (_isBlindUser) {
          await _firestore.collection('users').doc(user.uid).update({
            'userType': 'blind',
            'isBlindUser': true,
          });
        }
      }
    } catch (e) {
      debugPrint('Error checking user type: $e');
    }
  }

  // Get paired helper information
  Future<void> _getPairedHelper() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Try to get helper from linked user in user document first
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists && userDoc.data() != null) {
        final userData = userDoc.data()!;
        if (userData.containsKey('linkedUserId')) {
          _pairedHelperId = userData['linkedUserId'];

          // Get helper name if available
          if (_pairedHelperId != null) {
            final helperDoc =
                await _firestore.collection('users').doc(_pairedHelperId).get();
            if (helperDoc.exists && helperDoc.data() != null) {
              _pairedHelperName = helperDoc.data()!['displayName'];

              // Update in state
              if (mounted) {
                setState(() {});
              }
            }
          }
          return;
        }
      }

      // If not found in user document, check connections collection
      final connectionsRef = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('connections');
      final activeConnections =
          await connectionsRef.where('status', isEqualTo: 'active').get();

      if (activeConnections.docs.isNotEmpty) {
        final connection = activeConnections.docs.first;
        final helperId = connection.data()['helperId'] as String?;
        final helperName = connection.data()['helperName'] as String?;

        // Update in state
        if (mounted) {
          setState(() {
            _pairedHelperId = helperId;
            _pairedHelperName = helperName;
          });
        }

        // Also update in user document for easier access
        if (helperId != null) {
          await _firestore.collection('users').doc(user.uid).update({
            'linkedUserId': helperId,
            'linkedUserName': helperName,
          });
        }
      }
    } catch (e) {
      debugPrint('Error getting paired helper: $e');
    }
  }

  // Start live location tracking with retry mechanism
  Future<void> _startLiveLocationTrackingWithRetry() async {
    if (!mounted) return;

    // Cancel any existing subscription
    await _liveLocationSubscription?.cancel();

    // Set tracking state
    _isLiveTracking = true;

    try {
      // Use a more balanced approach to location settings
      final locationSettings = const LocationSettings(
        accuracy: LocationAccuracy
            .medium, // Use medium instead of high for better reliability
        distanceFilter: 5, // Update if moved 5 meters
        timeLimit: Duration(seconds: 30),
      );

      // Subscribe to position stream with error handling
      _liveLocationSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position position) {
          // Update location in state
          if (mounted) {
            setState(() {
              _myLocation = LatLng(position.latitude, position.longitude);
              _updateMarkers();
              _liveUpdateCount++;

              // If we're still showing loading, hide it now that we have a position
              if (_isLoading) {
                _isLoading = false;
              }
            });

            // Always update the live location document directly
            _updateLiveLocation(position);

            // Only sometimes update the main location document (to prevent write overload)
            if (_liveUpdateCount % 3 == 0) {
              _updateFirebaseLocation(forceUpdate: false);
            }
          }
        },
        onError: (e) async {
          debugPrint('❌ Error in position stream: $e');

          // Handle timeout errors specifically
          if (e.toString().contains('TimeoutException')) {
            // Don't stop tracking, just try to get the current position once
            try {
              debugPrint(
                  'Attempting to recover from timeout by getting current position');
              final position = await Geolocator.getCurrentPosition(
                desiredAccuracy: LocationAccuracy
                    .reduced, // Use reduced accuracy for faster response
                timeLimit: const Duration(seconds: 5), // Short timeout
              );

              if (!mounted) return;

              setState(() {
                _myLocation = LatLng(position.latitude, position.longitude);
                _updateMarkers();

                // If we're still showing loading, hide it now
                if (_isLoading) {
                  _isLoading = false;
                }
              });

              // Update Firebase
              _updateLiveLocation(position);

              // Restart location tracking after a short pause with different settings
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) {
                  _restartLocationTrackingWithLowerAccuracy();
                }
              });
            } catch (recoverError) {
              debugPrint('❌ Failed to recover from timeout: $recoverError');

              // If we're still showing loading, hide it now
              if (mounted && _isLoading) {
                setState(() {
                  _isLoading = false;
                });
              }

              // Try again after a longer delay with lower accuracy
              Future.delayed(const Duration(seconds: 5), () {
                if (mounted) {
                  _restartLocationTrackingWithLowerAccuracy();
                }
              });
            }
          } else {
            // For other errors, try to restart tracking after a delay
            Future.delayed(const Duration(seconds: 5), () {
              if (mounted) {
                _restartLocationTrackingWithLowerAccuracy();
              }
            });

            // If we're still showing loading, hide it now
            if (mounted && _isLoading) {
              setState(() {
                _isLoading = false;
              });
            }
          }
        },
      );

      debugPrint('✅ Live location tracking started');
    } catch (e) {
      debugPrint('❌ Error starting live location tracking: $e');
      _isLiveTracking = false;

      // If we're still showing loading, hide it now
      if (mounted && _isLoading) {
        setState(() {
          _isLoading = false;
        });
      }

      // Try to restart tracking after a delay with lower accuracy
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) {
          _restartLocationTrackingWithLowerAccuracy();
        }
      });
    }
  }

  // Restart location tracking with lower accuracy settings
  void _restartLocationTrackingWithLowerAccuracy() {
    // Cancel existing subscription
    _liveLocationSubscription?.cancel();

    try {
      // Use lowest accuracy settings for better reliability
      final locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.lowest,
        distanceFilter: 10, // Larger distance filter
        timeLimit: Duration(seconds: 60), // Longer timeout
      );

      // Subscribe to position stream
      _liveLocationSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position position) {
          // Update location in state
          if (mounted) {
            setState(() {
              _myLocation = LatLng(position.latitude, position.longitude);
              _updateMarkers();
              _liveUpdateCount++;
            });

            // Update Firebase
            _updateLiveLocation(position);
          }
        },
        onError: (e) {
          debugPrint('❌ Error in low accuracy position stream: $e');
          // At this point, we've tried everything - just keep the last known position
        },
      );

      debugPrint('✅ Low accuracy location tracking started');
    } catch (e) {
      debugPrint('❌ Failed to start low accuracy tracking: $e');
    }
  }

  // Update live location - separate from main location document
  Future<void> _updateLiveLocation(Position position) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Create minimal location data for frequent updates
      final locationData = {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'heading': position.heading,
        'speed': position.speed,
        'accuracy': position.accuracy,
        'lastSeenAt': FieldValue.serverTimestamp(),
        'isActive': true,
        'isNavigating': _isNavigating,
      };

      // Create movement prediction data
      if (position.speed > 0.5) {
        // If moving, add prediction for 5 seconds ahead based on current speed and heading
        final double metersPerSecond = position.speed;
        final double headingRadians =
            position.heading * (math.pi / 180); // Convert to radians

        // Calculate predicted position
        final double predictedLatitude = position.latitude +
            (metersPerSecond * 5 * math.sin(headingRadians)) / 111111;
        final double predictedLongitude = position.longitude +
            (metersPerSecond * 5 * math.cos(headingRadians)) /
                (111111 * math.cos(position.latitude * (math.pi / 180)));

        locationData['predicted'] = {
          'latitude': predictedLatitude,
          'longitude': predictedLongitude,
          'validUntil': DateTime.now()
              .add(const Duration(seconds: 5))
              .millisecondsSinceEpoch,
        };
      }

      // Update live location document
      await _firestore
          .collection('live_locations')
          .doc(user.uid)
          .set(locationData, SetOptions(merge: true));

      // Also update helper's real-time tracking document if paired
      if (_pairedHelperId != null) {
        await _firestore
            .collection('users')
            .doc(_pairedHelperId)
            .collection('tracked_users')
            .doc(user.uid)
            .set({
          ...locationData,
          'userName': user.displayName ?? 'Blind User',
          'photoURL': user.photoURL,
          'deviceInfo': 'Mobile App',
          'batteryLevel':
              100, // In a real app, this would be actual battery level
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('❌ Error updating live location: $e');
    }
  }

  // Update location to Firebase with enhanced error handling and retries
  Future<void> _updateFirebaseLocation({bool forceUpdate = false}) async {
    if (_myLocation == null) return;

    // Don't update too frequently unless forced
    if (!forceUpdate &&
        DateTime.now().difference(_lastUpdateTime).inSeconds < 10) {
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Mark the update time
      _lastUpdateTime = DateTime.now();
      _updateAttempts++;

      // Get more accurate position data if available
      Position? currentPosition;
      try {
        currentPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
      } catch (e) {
        // If we can't get current position, use the last known one
        debugPrint('Could not get current position: $e');
      }

      // Use the most accurate location data available
      final latitude = currentPosition?.latitude ?? _myLocation!.latitude;
      final longitude = currentPosition?.longitude ?? _myLocation!.longitude;

      // Create location data
      final locationData = {
        'latitude': latitude,
        'longitude': longitude,
        'address': _myAddress ?? 'Unknown location',
        'timestamp': FieldValue.serverTimestamp(),
        'accuracy': currentPosition?.accuracy ?? 10,
        'deviceInfo': 'Mobile App',
        'speed': currentPosition?.speed ?? 0,
        'altitude': currentPosition?.altitude ?? 0,
        'heading': currentPosition?.heading ?? 0,
        'battery':
            100, // Battery level would come from device in a real implementation
        'isNavigating': _isNavigating,
        'userId': user.uid,
        'userType': 'blind',
        'userName': user.displayName ?? 'Blind User',
        'photoURL': user.photoURL,
        'isAvailable': true, // Critical field to show availability status
        'lastUpdateTime': DateTime.now().millisecondsSinceEpoch,
        'isLiveTracking': _isLiveTracking,
      };

      // Add destination information if navigating
      if (_isNavigating && _destinationLocation != null) {
        locationData['destination'] = {
          'latitude': _destinationLocation!.latitude,
          'longitude': _destinationLocation!.longitude,
          'address': _destinationAddress ?? 'Unknown destination',
        };
      }

      // 1. Update user's own current location document
      await _userLocationRef.set(locationData);

      // 2. Update the shared location document for easier access by helpers
      await _sharedLocationRef.set({
        ...locationData,
        'helperIds': _pairedHelperId != null ? [_pairedHelperId] : [],
      });

      // 3. If paired with a helper, also send directly to helper's collection
      if (_pairedHelperId != null) {
        await _firestore
            .collection('users')
            .doc(_pairedHelperId)
            .collection('blind_user_locations')
            .doc(user.uid)
            .set(locationData);

        // Also update the helper's map_markers collection for quick access
        await _firestore
            .collection('users')
            .doc(_pairedHelperId)
            .collection('map_markers')
            .doc(user.uid)
            .set({
          'type': 'blind_user',
          'latitude': latitude,
          'longitude': longitude,
          'name': user.displayName ?? 'Blind User',
          'lastUpdate': FieldValue.serverTimestamp(),
          'isActive': true,
          'isLiveTracking': _isLiveTracking,
        });

        // Create a helper notification if this is a forced update (manual 'Send Location')
        if (forceUpdate) {
          await _firestore
              .collection('users')
              .doc(_pairedHelperId)
              .collection('notifications')
              .add({
            'type': 'location_update',
            'title': 'Location Update',
            'message':
                '${user.displayName ?? "Blind user"} has shared their location with you',
            'timestamp': FieldValue.serverTimestamp(),
            'isRead': false,
            'senderId': user.uid,
            'data': {
              'latitude': latitude,
              'longitude': longitude,
              'address': _myAddress,
            }
          });
        }
      }

      // 4. Add to location history (just once every minute to avoid too many docs)
      if (_updateAttempts % 4 == 0 || forceUpdate) {
        await _locationHistoryRef.add(locationData);
      }

      // Update status
      _lastUpdateSuccessful = true;
      _lastUpdateError = '';
      _updateAttempts = 0;

      debugPrint('✅ Location successfully updated to Firebase');
    } catch (e) {
      // Update status
      _lastUpdateSuccessful = false;
      _lastUpdateError = e.toString();

      debugPrint('❌ Error updating location to Firebase: $e');

      // Retry once after a short delay if this was the first failure
      if (_updateAttempts <= 1) {
        Future.delayed(const Duration(seconds: 3), () {
          _updateFirebaseLocation(forceUpdate: true);
        });
      }
    }
  }

  // Store the last update time
  DateTime _lastUpdateTime =
      DateTime.now().subtract(const Duration(minutes: 1));

  // Update map markers
  void _updateMarkers() {
    if (_myLocation == null) return;

    setState(() {
      // Clear existing markers and add the current location marker
      _markers.clear();

      // Add current location marker
      _markers.add(
        Marker(
          markerId: const MarkerId('my_location'),
          position: _myLocation!,
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(
            title: 'My Location'.tr(),
            snippet: _myAddress ?? 'Loading address...'.tr(),
          ),
        ),
      );

      // Add destination marker if exists
      if (_destinationLocation != null) {
        _markers.add(
          Marker(
            markerId: const MarkerId('destination'),
            position: _destinationLocation!,
            icon:
                BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: InfoWindow(
              title: 'Destination'.tr(),
              snippet: _destinationAddress ?? 'Unknown destination'.tr(),
            ),
          ),
        );
      }
    });
  }

  // Set navigation destination
  // ignore: unused_element
  void _setDestination(LatLng position, String address) {
    setState(() {
      _destinationLocation = position;
      _destinationAddress = address;
      _updateMarkers();
    });

    // If appropriate, start navigation
    _showNavigationConfirmation();
  }

  // Show navigation confirmation
  void _showNavigationConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start Navigation'),
        content: Text('Navigate to $_destinationAddress?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _startNavigation();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
            ),
            child: Text('Start'.tr()),
          ),
        ],
      ),
    );
  }

  // Start navigation
  void _startNavigation() {
    if (_destinationLocation == null) return;

    setState(() {
      _isNavigating = true;
      _navigationStatus = 'Navigating to $_destinationAddress';
      _isOnRoute = true;
      _consecutiveOffRouteUpdates = 0;
      _consecutiveOnRouteUpdates = 0;

      // Calculate simple distance and time
      if (_myLocation != null) {
        double distanceInMeters = Geolocator.distanceBetween(
          _myLocation!.latitude,
          _myLocation!.longitude,
          _destinationLocation!.latitude,
          _destinationLocation!.longitude,
        );

        _distanceToDestination = distanceInMeters >= 1000
            ? '${(distanceInMeters / 1000).toStringAsFixed(1)} km'
            : '${distanceInMeters.toStringAsFixed(0)} m';

        // Assuming walking speed of 5 km/h
        double timeInHours = distanceInMeters / 1000 / 5;

        if (timeInHours >= 1) {
          int hours = timeInHours.floor();
          int minutes = ((timeInHours - hours) * 60).round();
          _estimatedTime = '$hours h ${minutes > 0 ? '$minutes min' : ''}';
        } else {
          int minutes = (timeInHours * 60).round();
          _estimatedTime = '$minutes min';
        }
      }
    });

    // Calculate route with Google Directions API
    _calculateRoute();

    // Update Firebase with navigation status immediately
    _updateFirebaseLocation(forceUpdate: true);

    // Start directional sound guidance for blind users
    if (_isBlindUser) {
      _speak(
          'Navigation started to $_destinationAddress. $_distanceToDestination away, estimated time $_estimatedTime.');
      _startDirectionalSoundGuidance();
    }
  }

  // Stop navigation
  void _stopNavigation() {
    // Stop the directional sound guidance
    _navigationSoundTimer?.cancel();
    _isPlayingDirectionalSound = false;
    _audioPlayer.stop();
    
    // Stop route deviation detection
    _routeCheckTimer?.cancel();

    setState(() {
      _isNavigating = false;
      _destinationLocation = null;
      _destinationAddress = null;
      _navigationStatus = '';
      _distanceToDestination = '';
      _estimatedTime = '';
      _polylines.clear();
      _routePoints = [];
      _isOnRoute = true;
      _consecutiveOffRouteUpdates = 0;
      _consecutiveOnRouteUpdates = 0;
      _updateMarkers();
    });

    _speak('Navigation stopped');
  }

  // Speak text using TTS
  Future<void> _speak(String text) async {
    try {
      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint('TTS error: $e');
    }
  }

  // Get address from position
  Future<String?> _getAddressFromPosition(LatLng position) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks.first;
        return "${place.name ?? ''}, ${place.locality ?? ''}, ${place.administrativeArea ?? ''}"
            .trim();
      }
    } catch (e) {
      debugPrint('Error getting address: $e');
    }
    return null;
  }

  // Animate map to position
  Future<void> _animateToPosition(LatLng position) async {
    final GoogleMapController controller = await _mapController.future;
    controller.animateCamera(CameraUpdate.newLatLngZoom(position, 15));
  }

  // Handle map tap for setting destination
  void _onMapTap(LatLng position) {
    _getAddressFromPosition(position).then((address) {
      if (address != null && mounted) {
        setState(() {
          _destinationLocation = position;
          _destinationAddress = address;
          _updateMarkers();
        });

        // Announce the selected location
        _speak('Destination selected: $address');

        // Show destination options
        _showDestinationOptionsDialog();
      }
    });
  }

  // Load favorite locations
  void _loadFavoriteLocations() {
    // Make sure we clear the existing subscription if it exists
    _favoritesSubscription?.cancel();

    // Initialize the favorites listener in the location service
    _locationService.initFavoritesListener();

    // Start by getting all favorites
    _locationService.getFavorites().then((favorites) {
      if (mounted) {
        setState(() {
          _favoriteLocations = favorites;
          debugPrint('Loaded ${_favoriteLocations.length} favorite locations');
        });
      }
    });

    // Subscribe to favorites stream for live updates
    _favoritesSubscription =
        _locationService.favoritesStream().listen((favorites) {
      if (mounted) {
        setState(() {
          _favoriteLocations = favorites;
          debugPrint(
              'Updated to ${_favoriteLocations.length} favorite locations');
        });
      }
    }, onError: (e) {
      debugPrint('Error in favorites stream: $e');
    });
  }

  // Add current location as favorite
  void _addCurrentLocationAsFavorite() async {
    if (_myLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Current location not available'.tr())),
      );
      return;
    }

    // Show dialog to get favorite name
    final result = await _showAddFavoriteDialog();

    if (result != null && result.isNotEmpty) {
      final success = await _locationService.addFavorite(
        _myLocation!,
        result,
        address: _myAddress,
      );

      if (success) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Location added to favorites'.tr())),
        );
        _speak('Location added to favorites: $result');
      } else {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add location to favorites'.tr())),
        );
      }
    }
  }

  // Add the selected destination as favorite
  void _addDestinationAsFavorite() async {
    if (_destinationLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No destination selected'.tr())),
      );
      return;
    }

    // Show dialog to get favorite name
    final result = await _showAddFavoriteDialog();

    if (result != null && result.isNotEmpty) {
      final success = await _locationService.addFavorite(
        _destinationLocation!,
        result,
        address: _destinationAddress,
      );

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Destination added to favorites'.tr())),
        );
        _speak('Destination added to favorites: $result');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to add destination to favorites'.tr())),
        );
      }
    }
  }

  // Show dialog to get favorite name
  Future<String?> _showAddFavoriteDialog() async {
    final TextEditingController nameController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('add_to_favorites'.tr()),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: 'location_name'.tr(),
            hintText: 'enter_location_name'.tr(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text),
            child: Text('save'.tr()),
          ),
        ],
      ),
    );
  }

  // Navigate to a favorite location
  void _navigateToFavorite(Map<String, dynamic> favorite) {
    setState(() {
      _destinationLocation = LatLng(
        favorite['latitude'] as double,
        favorite['longitude'] as double,
      );
      _destinationAddress =
          favorite['address'] as String? ?? favorite['name'] as String;
      _updateMarkers();
    });

    // Center map on the route
    if (_myLocation != null && _mapController.isCompleted) {
      final bounds = LatLngBounds(
        southwest: LatLng(
          math.min(_myLocation!.latitude, _destinationLocation!.latitude),
          math.min(_myLocation!.longitude, _destinationLocation!.longitude),
        ),
        northeast: LatLng(
          math.max(_myLocation!.latitude, _destinationLocation!.latitude),
          math.max(_myLocation!.longitude, _destinationLocation!.longitude),
        ),
      );

      _mapController.future.then((controller) {
        controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
      });
    }

    // Announce the selected destination
    _speak('Navigating to favorite location: ${favorite['name']}');

    // Show navigation options
    _showDestinationOptionsDialog();
  }

  // Show a dialog with destination options
  void _showDestinationOptionsDialog() {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Destination Options'.tr()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_destinationAddress != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(_destinationAddress!),
                ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.navigation),
                title: Text('Start Navigation'.tr()),
                onTap: () {
                  Navigator.pop(context);
                  _startNavigation();
                },
              ),
              ListTile(
                leading: const Icon(Icons.favorite_border),
                title: Text('Add to Favorites'.tr()),
                onTap: () {
                  Navigator.pop(context);
                  _addDestinationAsFavorite();
                },
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Cancel'.tr()),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Get screen dimensions for responsive sizing
    final screenSize = MediaQuery.of(context).size;
    final bool isSmallScreen = screenSize.width < 360;
    final double baseSize = isSmallScreen ? 1.0 : 1.2; // Scale factor
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'My Location'.tr(),
          style: TextStyle(
            fontSize: 22 * baseSize,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.blue.shade700,
        elevation: 4,
        actions: [
          // Language button
          IconButton(
            icon: Icon(Icons.settings, size: 30 * baseSize),
            tooltip: 'settings'.tr(),
            onPressed: () {
              _speak('Settings opened');
              _showSettingsBottomSheet();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // Map
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _myLocation ?? const LatLng(0, 0),
              zoom: 15,
              tilt: 45, // Add tilt for 3D effect
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            compassEnabled: true,
            buildingsEnabled: true,
            tiltGesturesEnabled: true,
            mapType: MapType.normal,
            markers: _markers,
            polylines: _polylines,
            onMapCreated: (GoogleMapController controller) {
              _mapController.complete(controller);
              // Move to current location once map is ready
              if (_myLocation != null) {
                _animateToPosition(_myLocation!);
              }
            },
            onTap: _onMapTap,
          ),

          // Loading indicator
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.7),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      strokeWidth: 5,
                    ),
                    SizedBox(height: 16 * baseSize),
                    Text(
                      'Loading your location...'.tr(),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18 * baseSize,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Bottom panel with information
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Column(
              children: [
                // Current Location Info Panel
                Container(
                  padding: EdgeInsets.all(16 * baseSize),
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.grey.shade900 : Colors.white,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Current Location with larger text
                      Row(
                        children: [
                          Icon(
                            Icons.my_location,
                            color: Colors.blue.shade700,
                            size: 30 * baseSize,
                          ),
                          SizedBox(width: 16 * baseSize),
                          Expanded(
                            child: Text(
                              _myAddress ?? 'Getting your location...'.tr(),
                              style: TextStyle(
                                fontSize: 18 * baseSize,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 16 * baseSize),

                      // Destination information if navigating
                      if (_isNavigating && _destinationAddress != null) ...[
                        Container(
                          padding: EdgeInsets.all(12 * baseSize),
                          decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.blue.shade200)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.place,
                                      color: Colors.red, size: 30 * baseSize),
                                  SizedBox(width: 10 * baseSize),
                                  Expanded(
                                    child: Text(
                                      _destinationAddress!,
                                      style: TextStyle(
                                        fontSize: 18 * baseSize,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 12 * baseSize),
                              Text(
                                _navigationStatus,
                                style: TextStyle(
                                  fontSize: 16 * baseSize,
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              SizedBox(height: 12 * baseSize),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _distanceToDestination,
                                    style: TextStyle(
                                      fontSize: 16 * baseSize,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    _estimatedTime,
                                    style: TextStyle(
                                      fontSize: 16 * baseSize,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 16 * baseSize),
                        SizedBox(
                          width: double.infinity,
                          height: 60 * baseSize,
                          child: ElevatedButton.icon(
                            icon: Icon(Icons.stop_circle, size: 30 * baseSize),
                            label: Text(
                              'Stop Navigation'.tr(),
                              style: TextStyle(
                                fontSize: 18 * baseSize,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding:
                                  EdgeInsets.symmetric(vertical: 12 * baseSize),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                            ),
                            onPressed: () {
                              _speak('Stopping navigation');
                              _stopNavigation();
                            },
                          ),
                        ),
                      ],

                      if (!_isNavigating) ...[
                        // Helper connection status
                        if (_pairedHelperName != null) ...[
                          SizedBox(height: 16 * baseSize),
                          Container(
                            padding: EdgeInsets.all(12 * baseSize),
                            decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border:
                                    Border.all(color: Colors.green.shade200)),
                            child: Row(
                              children: [
                                Icon(Icons.people,
                                    color: Colors.green, size: 24 * baseSize),
                                SizedBox(width: 10 * baseSize),
                                Expanded(
                                  child: Text(
                                    'Connected to: $_pairedHelperName'.tr(),
                                    style: TextStyle(
                                      fontSize: 16 * baseSize,
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // Quick action buttons for common tasks
                        SizedBox(height: 16 * baseSize),
                        Text(
                          'Quick Actions'.tr(),
                          style: TextStyle(
                            fontSize: 16 * baseSize,
                            fontWeight: FontWeight.bold,
                            color: isDarkMode ? Colors.white : Colors.black,
                          ),
                        ),
                        SizedBox(height: 8 * baseSize),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Expanded(
                              child: _buildQuickActionButton(
                                icon: Icons.home,
                                label: 'Go Home'.tr(),
                                color: Colors.green,
                                onPressed: () {
                                  _speak('Setting home as destination');
                                  _navigateToHomeIfAvailable();
                                },
                                baseSize: baseSize,
                              ),
                            ),
                            SizedBox(width: 10 * baseSize),
                            Expanded(
                              child: _buildQuickActionButton(
                                icon: Icons.favorite,
                                label: 'Favorites'.tr(),
                                color: Colors.green,
                                onPressed: () {
                                  _speak('Opening favorites menu');
                                  _showFavoritesBottomSheet();
                                },
                                baseSize: baseSize,
                              ),
                            ),
                          ],
                        ),
                        // Add the Set Destination button here
                        SizedBox(height: 10 * baseSize),
                        SizedBox(
                          width: double.infinity,
                          height: 50 * baseSize,
                          child: ElevatedButton.icon(
                            icon: Icon(
                              Icons.place,
                              size: 24 * baseSize,
                            ),
                            label: Text(
                              'Set Destination'.tr(),
                              style: TextStyle(
                                fontSize: 16 * baseSize,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              foregroundColor: Colors.white,
                              padding:
                                  EdgeInsets.symmetric(vertical: 8 * baseSize),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                            ),
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      'Tap on the map to set a destination'
                                          .tr()),
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                              _speak('Tap on the map to set a destination');
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Voice feedback indicator
          if (_speech.isListening)
            Positioned(
              top: 16 * baseSize,
              right: 16 * baseSize,
              child: Container(
                padding: EdgeInsets.all(8 * baseSize),
                decoration: BoxDecoration(
                  color: Colors.blue.shade700,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Helper method to build quick action buttons
  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
    required double baseSize,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: EdgeInsets.all(12 * baseSize),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3), width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 25 * baseSize,
              color: color,
            ),
            SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 12 * baseSize,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Add the missing home navigation method
  void _navigateToHomeIfAvailable() {
    final homeLocation = _favoriteLocations.firstWhere(
      (fav) => (fav['name'] as String).toLowerCase().contains('home'),
      orElse: () => {},
    );

    if (homeLocation.isNotEmpty) {
      _navigateToFavorite(homeLocation);
    } else {
      _speak('No home location found in your favorites');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('No home location found in your favorites'.tr())),
      );
    }
  }

  // Add a share location method
  void _shareCurrentLocation() {
    if (_myLocation == null) {
      _speak('Location not available yet');
      return;
    }

    if (_pairedHelperId != null) {
      _speak('Sharing your current location with your helper');

      // Add to Firebase to share with helper
      _firestore
          .collection('users')
          .doc(_pairedHelperId)
          .collection('shared_locations')
          .add({
        'latitude': _myLocation!.latitude,
        'longitude': _myLocation!.longitude,
        'address': _myAddress ?? 'Unknown location',
        'sharedAt': FieldValue.serverTimestamp(),
        'sharedBy':
            FirebaseAuth.instance.currentUser?.displayName ?? 'Blind User',
        'userId': FirebaseAuth.instance.currentUser?.uid,
      }).then((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Location shared with helper'.tr())),
        );
      }).catchError((error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to share location'.tr())),
        );
      });
    } else {
      _speak('No helper paired to share location with');
    }
  }

  // Add a voice recognition method for accessibility
  // ignore: unused_element
  Future<void> _startVoiceRecognition() async {
    try {
      bool available = await _speech.initialize(
        onStatus: (status) => debugPrint('Speech recognition status: $status'),
        onError: (error) => debugPrint('Speech recognition error: $error'),
      );

      if (available) {
        _speak('Listening for commands');
        await _speech.listen(
          onResult: (result) {
            if (result.finalResult) {
              _processVoiceCommand(result.recognizedWords);
            }
          },
          listenFor: const Duration(seconds: 5),
        );
      } else {
        _speak('Speech recognition not available');
      }
    } catch (e) {
      debugPrint('Error starting voice recognition: $e');
      _speak('Error starting voice recognition');
    }
  }

  // Process voice commands
  void _processVoiceCommand(String command) {
    final lowerCommand = command.toLowerCase();

    if (lowerCommand.contains('navigate') || lowerCommand.contains('go to')) {
      if (_isNavigating) {
        _speak('Already navigating. Please stop current navigation first.');
        return;
      }

      // Check for home navigation specifically
      if (lowerCommand.contains('home')) {
        _speak('Navigating to home');
        _navigateToHomeIfAvailable();
        return;
      }

      // Extract destination from command
      String destination = '';
      if (lowerCommand.contains('navigate to ')) {
        destination = command
            .substring(command.indexOf('navigate to ') + 'navigate to '.length);
      } else if (lowerCommand.contains('go to ')) {
        destination =
            command.substring(command.indexOf('go to ') + 'go to '.length);
      }

      if (destination.isNotEmpty) {
        _speak('Looking for $destination');
        // Find in favorites
        final matchingFavorite = _favoriteLocations.firstWhere(
          (fav) => (fav['name'] as String)
              .toLowerCase()
              .contains(destination.toLowerCase()),
          orElse: () => {},
        );

        if (matchingFavorite.isNotEmpty) {
          _speak('Found $destination in your favorites');
          _navigateToFavorite(matchingFavorite);
        } else {
          _speak('Could not find $destination in your favorites');
        }
      } else {
        _speak('Please specify where you want to navigate to');
      }
    } else if (lowerCommand.contains('stop') ||
        lowerCommand.contains('cancel')) {
      if (_isNavigating) {
        _speak('Stopping navigation');
        _stopNavigation();
      } else {
        _speak('No active navigation to stop');
      }
    } else if (lowerCommand.contains('where am i') ||
        lowerCommand.contains('my location')) {
      _speak('Your current location is $_myAddress');
    } else if (lowerCommand.contains('favorites') ||
        lowerCommand.contains('favourite')) {
      _speak('Opening favorites');
      _showFavoritesBottomSheet();
    } else if (lowerCommand.contains('refresh') ||
        lowerCommand.contains('update')) {
      _speak('Refreshing your location');
      _refreshLocation();
    } else if (lowerCommand.contains('home')) {
      _speak('Setting home as destination');
      _navigateToHomeIfAvailable();
    } else if (lowerCommand.contains('share')) {
      _speak('Sharing your location');
      _shareCurrentLocation();
    } else if (lowerCommand.contains('help')) {
      _speak('Opening help menu');
      _showHelpDialog();
    } else if (lowerCommand.contains('language') ||
        lowerCommand.contains('change language')) {
      _speak('Opening language settings');
      _showLanguageSelectionDialog(LanguageService());
    } else if (lowerCommand.contains('english')) {
      _speak('Changing language to English');
      LanguageService().setLanguage(context, 'en');
      _updateTTSLanguage('en');
    } else if (lowerCommand.contains('arabic')) {
      _speak('Changing language to Arabic');
      LanguageService().setLanguage(context, 'ar');
      _updateTTSLanguage('ar');
    } else if (lowerCommand.contains('german')) {
      _speak('Changing language to German');
      LanguageService().setLanguage(context, 'de');
      _updateTTSLanguage('de');
    } else {
      _speak(
          'Command not recognized. Try saying navigate to, where am I, or open favorites');
    }
  }

  // Method to show favorites in a bottom sheet - enhance accessibility
  void _showFavoritesBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Favorite Places'.tr(),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _favoriteLocations.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Text(
                          'No favorite places yet.\nTap the + button to add your current location.'
                              .tr(),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ),
                    )
                  : Expanded(
                      child: ListView.builder(
                        itemCount: _favoriteLocations.length,
                        itemBuilder: (context, index) {
                          final favorite = _favoriteLocations[index];
                          return Dismissible(
                            key: Key(
                                favorite['id'] as String? ?? index.toString()),
                            background: Container(
                              color: Colors.red,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              child: const Icon(
                                Icons.delete,
                                color: Colors.white,
                              ),
                            ),
                            direction: DismissDirection.endToStart,
                            confirmDismiss: (direction) async {
                              return await showDialog(
                                context: context,
                                builder: (BuildContext context) {
                                  return AlertDialog(
                                    title: Text('Delete Favorite'.tr()),
                                    content: Text(
                                        'Are you sure you want to delete ${favorite['name']}?'
                                            .tr()),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(false),
                                        child: Text('Cancel'.tr()),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(true),
                                        child: Text('Delete'.tr(),
                                            style: const TextStyle(
                                                color: Colors.red)),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                            onDismissed: (direction) {
                              _speak(
                                  'Deleted ${favorite['name']} from favorites');
                              _locationService
                                  .deleteFavorite(favorite['id'] as String);
                            },
                            child: ListTile(
                              leading: const Icon(Icons.place,
                                  color: Colors.red, size: 32),
                              title: Text(
                                favorite['name'] as String,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                favorite['address'] as String? ??
                                    'No address available'.tr(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 8.0,
                                horizontal: 16.0,
                              ),
                              onTap: () {
                                Navigator.pop(context);
                                _speak('Navigating to ${favorite['name']}');
                                _navigateToFavorite(favorite);
                              },
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      Icons.delete,
                                      color: Colors.red,
                                      size: 24,
                                    ),
                                    onPressed: () async {
                                      bool confirm = await showDialog(
                                        context: context,
                                        builder: (BuildContext context) {
                                          return AlertDialog(
                                            title: Text('Delete Favorite'.tr()),
                                            content: Text(
                                                'Are you sure you want to delete ${favorite['name']}?'
                                                    .tr()),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.of(context)
                                                        .pop(false),
                                                child: Text('Cancel'.tr()),
                                              ),
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.of(context)
                                                        .pop(true),
                                                child: Text('Delete'.tr(),
                                                    style: const TextStyle(
                                                        color: Colors.red)),
                                              ),
                                            ],
                                          );
                                        },
                                      );

                                      if (confirm) {
                                        _speak(
                                            'Deleted ${favorite['name']} from favorites');
                                        _locationService.deleteFavorite(
                                            favorite['id'] as String);
                                      }
                                    },
                                    tooltip: 'Delete favorite',
                                  ),
                                  SizedBox(width: 8),
                                  Icon(
                                    Icons.arrow_forward_ios,
                                    color: Colors.blue.shade700,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.add_location),
                  label: Text('Add Current Location'.tr()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    _addCurrentLocationAsFavorite();
                  },
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  child: Text('Close'.tr()),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Method to show settings
  void _showSettingsBottomSheet() {
    // Create instance of LanguageService
    final languageService = LanguageService();

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'settings'.tr(),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.refresh),
                title: Text('refresh_location'.tr()),
                subtitle: Text('update_current_location'.tr()),
                onTap: () {
                  Navigator.pop(context);
                  _refreshLocation();
                },
              ),
              ListTile(
                leading: const Icon(Icons.map),
                title: Text('recenter_map'.tr()),
                subtitle: Text('center_map_on_location'.tr()),
                onTap: () {
                  Navigator.pop(context);
                  if (_myLocation != null) {
                    _animateToPosition(_myLocation!);
                  }
                },
              ),
              if (_isBlindUser) ...[
                ListTile(
                  leading: const Icon(Icons.volume_up),
                  title: Text('test_voice'.tr()),
                  subtitle: Text('test_text_to_speech'.tr()),
                  onTap: () {
                    Navigator.pop(context);
                    _speak('${'voice_guidance_working'.tr()} $_myAddress.');
                  },
                ),
              ],
              // Language selector
              ListTile(
                leading: const Icon(Icons.language),
                title: Text('language'.tr()),
                subtitle: Text('select_preferred_language'.tr()),
                trailing: languageService.buildLanguageDropdown(context),
                onTap: () {
                  // Show language selection dialog
                  _showLanguageSelectionDialog(languageService);
                },
              ),
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: Text('Help'.tr()),
                subtitle: Text('How to use this screen'.tr()),
                onTap: () {
                  Navigator.pop(context);
                  _showHelpDialog();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // Refresh location
  void _refreshLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (!mounted) return;

      setState(() {
        _myLocation = LatLng(position.latitude, position.longitude);
        _updateMarkers();
      });

      // Move camera to current location
      _animateToPosition(_myLocation!);

      // Update address
      _getAddressFromPosition(_myLocation!).then((address) {
        if (mounted && address != null) {
          setState(() => _myAddress = address);
          // Force update to Firebase
          _updateFirebaseLocation(forceUpdate: true);
        }
      });

      _speak('Location refreshed');
    } catch (e) {
      debugPrint('Error refreshing location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error refreshing location'.tr())),
        );
      }
    }
  }

  // Show help dialog
  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('How to Use'.tr()),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('• Tap on the map to set a destination'.tr()),
              const SizedBox(height: 8),
              Text('• Use the Set Destination button to enable destination mode'
                  .tr()),
              const SizedBox(height: 8),
              Text('• Save favorite places for quick access'.tr()),
              const SizedBox(height: 8),
              Text('• The app will guide you with voice instructions'.tr()),
              const SizedBox(height: 8),
              Text('• Your location is automatically shared with your helper'
                  .tr()),
              const SizedBox(height: 8),
              Text('• Swipe left on a favorite to delete it'.tr()),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Got it'.tr()),
          ),
        ],
      ),
    );
  }

  // Calculate route between current location and destination
  Future<void> _calculateRoute() async {
    if (_myLocation == null || _destinationLocation == null) return;

    try {
      if (mounted) {
        setState(() {
          _polylines.clear();
          _navigationStatus = 'Calculating route...'.tr();
          _routePoints = []; // Clear previous route points
          _isOnRoute = true; // Reset route status
          _consecutiveOffRouteUpdates = 0;
          _consecutiveOnRouteUpdates = 0;
        });
      }

      final apiKey = '';

      // Origin and destination for API requests
      final origin = '${_myLocation!.latitude},${_myLocation!.longitude}';
      final destination =
          '${_destinationLocation!.latitude},${_destinationLocation!.longitude}';

      // Calculate straight-line distance immediately for quick feedback
      final straightLineDistance = Geolocator.distanceBetween(
        _myLocation!.latitude,
        _myLocation!.longitude,
        _destinationLocation!.latitude,
        _destinationLocation!.longitude,
      );

      final straightLineDistanceText = straightLineDistance >= 1000
          ? '${(straightLineDistance / 1000).toStringAsFixed(1)} km'
          : '${straightLineDistance.toStringAsFixed(0)} m';

      // Update UI with straight-line distance while API call is in progress
      if (mounted) {
        setState(() {
          _distanceToDestination = 'Direct distance: $straightLineDistanceText';
          _navigationStatus = 'Calculating best route...';

          // Add a straight line temporarily
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('direct_line'),
              points: [_myLocation!, _destinationLocation!],
              color: Colors.grey.withOpacity(0.7),
              width: 3,
              patterns: [PatternItem.dash(5), PatternItem.gap(5)],
            ),
          );
        });
      }

      // Create an instance of PolylinePoints
      PolylinePoints polylinePoints = PolylinePoints();

      // Get route using Google Directions API for detailed info
      final response = await http.get(
        Uri.parse(
            'https://maps.googleapis.com/maps/api/directions/json?origin=$origin&destination=$destination&mode=walking&alternatives=true&key=$apiKey'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'OK') {
          // Extract route information
          final routes = data['routes'] as List;
          if (routes.isNotEmpty) {
            // Clear temporary straight line
            if (mounted) {
              setState(() {
                _polylines.clear();
              });
            }

            // Process primary route
            final primaryRoute = routes[0];
            final leg = primaryRoute['legs'][0];

            // Get distance and duration
            final distance = leg['distance']['text'];
            final duration = leg['duration']['text'];
            final distanceValue =
                leg['distance']['value']; // Distance in meters

            // Decode primary route and add to map
            final primaryPoints =
                primaryRoute['overview_polyline']['points'] as String;
            final decodedPrimaryPoints =
                polylinePoints.decodePolyline(primaryPoints);
            final primaryCoordinates = decodedPrimaryPoints
                .map((point) => LatLng(point.latitude, point.longitude))
                .toList();
                
            // Store route points for deviation detection
            _routePoints = primaryCoordinates;

            // Add detailed step instructions
            List<String> stepInstructions = [];
            for (var step in leg['steps']) {
              final instruction = step['html_instructions'] as String;
              // Remove HTML tags for clean text
              final cleanInstruction =
                  instruction.replaceAll(RegExp(r'<[^>]*>'), ' ');
              final distance = step['distance']['text'];
              stepInstructions.add('$cleanInstruction ($distance)');
            }

            // Create combined polyline
            if (mounted) {
              setState(() {
                // White outline first (drawn underneath)
                _polylines.add(
                  Polyline(
                    polylineId: const PolylineId('route_outline'),
                    points: primaryCoordinates,
                    color: Colors.white,
                    width: 10,
                    zIndex: 1,
                    geodesic: true,
                  ),
                );

                // Main route on top
                _polylines.add(
                  Polyline(
                    polylineId: const PolylineId('route'),
                    points: primaryCoordinates,
                    color: Colors.blue.shade700,
                    width: 6,
                    patterns: [
                      PatternItem.dash(30),
                      PatternItem.gap(15),
                    ],
                    startCap: Cap.roundCap,
                    endCap: Cap.roundCap,
                    geodesic: true,
                    zIndex: 2,
                  ),
                );

                // Add distance markers at regular intervals
                _addDistanceMarkers(primaryCoordinates, distanceValue);

                _distanceToDestination = 'Distance: $distance';
                _estimatedTime = 'ETA: $duration';
                _navigationStatus = 'Follow the blue line on the map';
              });
            }

            // Process alternative routes if available
            if (routes.length > 1) {
              for (int i = 1; i < math.min(routes.length, 3); i++) {
                // Limit to 2 alternatives
                final altRoute = routes[i];
                final altLeg = altRoute['legs'][0];
                final altDistance = altLeg['distance']['text'];
                final altDuration = altLeg['duration']['text'];

                // Decode alternative route
                final altPoints =
                    altRoute['overview_polyline']['points'] as String;
                final decodedAltPoints =
                    polylinePoints.decodePolyline(altPoints);
                final altCoordinates = decodedAltPoints
                    .map((point) => LatLng(point.latitude, point.longitude))
                    .toList();

                // Add alternative route with different styling
                if (mounted) {
                  setState(() {
                    _polylines.add(
                      Polyline(
                        polylineId: PolylineId('route_alt_$i'),
                        points: altCoordinates,
                        color: i == 1
                            ? Colors.green.shade600
                            : Colors.orange.shade600,
                        width: 4,
                        patterns: [
                          PatternItem.dash(10),
                          PatternItem.gap(10),
                        ],
                        geodesic: true,
                        zIndex: 1, // Below main route
                      ),
                    );
                  });
                }

                // Announce alternative
                debugPrint('Alternative route $i: $altDistance, $altDuration');
              }
            }

            // Fit map to show the entire route
            if (_mapController.isCompleted) {
              final bounds = LatLngBounds(
                southwest: LatLng(
                  primaryRoute['bounds']['southwest']['lat'],
                  primaryRoute['bounds']['southwest']['lng'],
                ),
                northeast: LatLng(
                  primaryRoute['bounds']['northeast']['lat'],
                  primaryRoute['bounds']['northeast']['lng'],
                ),
              );

              final controller = await _mapController.future;
              controller
                  .animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));

              // Store step instructions for TTS navigation
              _routeInstructions = stepInstructions;

              // Announce route details
              final routeInfo =
                  'Route calculated. Distance: $distance. Estimated time: $duration. ${routes.length > 1 ? 'Alternative routes available.' : ''} Follow the blue line on the map.';
              _speak(routeInfo);
              
              // Start route deviation detection
              _startRouteDeviationDetection();

              // Show extra information dialog if first time navigating
              if (!_hasShownRouteInfo) {
                _showRouteInformationDialog(
                    distance, duration, stepInstructions);
                _hasShownRouteInfo = true;
              }

              // Give more detailed voice guidance about the first few steps
              if (stepInstructions.isNotEmpty) {
                final firstStepGuidance = 'First step: ${stepInstructions[0]}';
                final secondStepGuidance = stepInstructions.length > 1
                    ? 'Then: ${stepInstructions[1]}'
                    : '';

                // Announce first two steps after a short delay to allow the main route info to be heard
                Future.delayed(Duration(seconds: 5), () {
                  if (mounted && _isNavigating) {
                    _speak('$firstStepGuidance. $secondStepGuidance');
                  }
                });
              }
            }
          }
        } else {
          setState(() {
            _navigationStatus = 'Could not calculate route: ${data['status']}';
          });
          _speak('Could not calculate route. Please try again.');
        }
      } else {
        setState(() {
          _navigationStatus = 'Error calculating route';
        });
        _speak('Error calculating route. Please try again later.');
      }
    } catch (e) {
      debugPrint('Error calculating route: $e');
      setState(() {
        _navigationStatus = 'Error calculating route';
      });
      _speak('Error calculating route. Please try again later.');
    }
  }

  // Add distance markers along the route
  void _addDistanceMarkers(List<LatLng> routePoints, int totalDistanceMeters) {
    if (routePoints.length < 10) return; // Not enough points

    // Calculate how many markers to show (roughly every 200 meters)
    int markerCount = (totalDistanceMeters / 200).round();
    if (markerCount < 1) markerCount = 1;
    if (markerCount > 10) markerCount = 10; // Limit to 10 markers

    // Create evenly spaced markers along the route
    for (int i = 1; i <= markerCount; i++) {
      // Calculate the position along the path
      int index = ((i * routePoints.length) / (markerCount + 1)).round();
      if (index >= routePoints.length) index = routePoints.length - 1;

      // Add a custom marker with distance information
      final position = routePoints[index];
      final distance = ((i * totalDistanceMeters) / (markerCount + 1)).round();
      final distanceText = distance >= 1000
          ? '${(distance / 1000).toStringAsFixed(1)} km'
          : '$distance m';

      setState(() {
        _markers.add(
          Marker(
            markerId: MarkerId('distance_$i'),
            position: position,
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueYellow),
            infoWindow: InfoWindow(
              title: distanceText,
              snippet: 'from start',
            ),
            visible: false, // Start invisible to avoid clutter
          ),
        );
      });
    }
  }

  // Show detailed route information dialog
  void _showRouteInformationDialog(
      String distance, String duration, List<String> steps) {
    if (steps.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Route Information'.tr(),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Distance: $distance',
                      style: const TextStyle(fontSize: 16)),
                  Text('Duration: $duration',
                      style: const TextStyle(fontSize: 16)),
                ],
              ),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Navigation Steps'.tr(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: steps.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: Colors.blue,
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              steps[index],
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text('Close'.tr()),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ignore: unused_element
  Future<bool> _addFavoriteByAssistant(
      LatLng location, String name, String address) async {
    try {
      final success = await _locationService.addFavorite(
        location,
        name,
        address: address,
      );

      if (success) {
        _speak(
            'Your assistant added a new favorite location: $name at $address');
        return true;
      } else {
        _speak('Failed to add favorite location');
        return false;
      }
    } catch (e) {
      debugPrint('Error adding favorite by assistant: $e');
      _speak('Error adding favorite location');
      return false;
    }
  }

  // Add this method for assistant to delete a favorite location
  // ignore: unused_element
  Future<bool> _deleteFavoriteByAssistant(
      String favoriteId, String favoriteName) async {
    try {
      final success = await _locationService.deleteFavorite(favoriteId);

      if (success) {
        _speak('Your assistant removed the favorite location: $favoriteName');
        return true;
      } else {
        _speak('Failed to remove favorite location');
        return false;
      }
    } catch (e) {
      debugPrint('Error deleting favorite by assistant: $e');
      _speak('Error removing favorite location');
      return false;
    }
  }

  // Add this method to start directional sound guidance
  void _startDirectionalSoundGuidance() {
    // Cancel any existing timer
    _navigationSoundTimer?.cancel();

    // Start a new timer that plays directional sounds
    _navigationSoundTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_myLocation != null &&
          _destinationLocation != null &&
          _isNavigating) {
        _playDirectionalSound();
      }
    });

    // Play the first sound immediately
    _playDirectionalSound();
  }

  // Add this method to play directional sounds based on bearing
  Future<void> _playDirectionalSound() async {
    if (_myLocation == null || _destinationLocation == null) return;

    try {
      // Calculate bearing to destination
      double bearing = Geolocator.bearingBetween(
          _myLocation!.latitude,
          _myLocation!.longitude,
          _destinationLocation!.latitude,
          _destinationLocation!.longitude);

      // Calculate distance to destination
      double distance = Geolocator.distanceBetween(
          _myLocation!.latitude,
          _myLocation!.longitude,
          _destinationLocation!.latitude,
          _destinationLocation!.longitude);

      // Determine interval based on distance
      // Closer = more frequent sounds
      int intervalMs = distance < 50
          ? 1000
          : distance < 200
              ? 2000
              : distance < 500
                  ? 3000
                  : 5000;

      // Get direction from bearing
      String direction = _getDirectionFromBearing(bearing);

      // If we're getting very close, announce it
      if (distance < 20) {
        _speak(
            'You are approaching your destination. About ${distance.round()} meters remaining.');
      }
      // Otherwise provide periodic guidance
      else if (distance < 100 && _liveUpdateCount % 4 == 0) {
        _speak(
            'Continue $direction. About ${distance.round()} meters remaining.');
      }

      // Play directional sound if not already playing
      if (!_isPlayingDirectionalSound) {
        _isPlayingDirectionalSound = true;

        // Play directional sound (normally you would have different sounds for different directions)
        await _audioPlayer
            .play(UrlSource('https://www.soundjay.com/buttons/beep-1.mp3'));

        // Wait for sound to finish
        await Future.delayed(Duration(milliseconds: 500));
        _isPlayingDirectionalSound = false;

        // Schedule next sound
        Future.delayed(Duration(milliseconds: intervalMs - 500), () {
          if (_isNavigating && mounted) {
            _playDirectionalSound();
          }
        });
      }
    } catch (e) {
      debugPrint('Error playing directional sound: $e');
      _isPlayingDirectionalSound = false;
    }
  }

  // Add helper method to get direction from bearing
  String _getDirectionFromBearing(double bearing) {
    const directions = [
      'north',
      'northeast',
      'east',
      'southeast',
      'south',
      'southwest',
      'west',
      'northwest',
      'north'
    ];
    return directions[(((bearing + 22.5) % 360) / 45).floor()];
  }

  // Start route deviation detection
  void _startRouteDeviationDetection() {
    // Cancel any existing timer
    _routeCheckTimer?.cancel();
    
    // Start a timer to check if user is on route
    _routeCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_myLocation != null && _isNavigating && _routePoints.isNotEmpty) {
        _checkIfOnRoute();
      }
    });
  }
  
  // Provide guidance when user is off route
  void _provideOffRouteGuidance(double distanceFromRoute) {
    // Vibrate the phone to alert the user - triple vibration pattern for "wrong way"
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 300), () {
      HapticFeedback.heavyImpact();
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      HapticFeedback.heavyImpact();
    });
    
    // Simplify distance for speech
    // ignore: unused_local_variable
    final String distanceText = distanceFromRoute < 100 
        ? '${distanceFromRoute.round()} meters'
        : '${(distanceFromRoute / 100).round() / 10} kilometers';
    
    // Calculate direction to get back to route
    if (_routePoints.isNotEmpty && _myLocation != null) {
      // Find the closest point on the route
      LatLng closestPoint = _routePoints[0];
      double minDistance = double.infinity;
      
      for (final point in _routePoints) {
        final distance = Geolocator.distanceBetween(
          _myLocation!.latitude,
          _myLocation!.longitude,
          point.latitude,
          point.longitude,
        );
        
        if (distance < minDistance) {
          minDistance = distance;
          closestPoint = point;
        }
      }
      
      // Calculate bearing to closest point
      final bearing = Geolocator.bearingBetween(
        _myLocation!.latitude,
        _myLocation!.longitude,
        closestPoint.latitude,
        closestPoint.longitude,
      );
      
      // Convert bearing to direction - use simpler directions
      final direction = _getSimpleDirection(bearing);
      
      // Provide simple audio guidance
      _speak('Wrong road. Turn $direction to get back on track.');
    } else {
      // Even simpler guidance
      _speak('Wrong road. Please stop and wait for assistance.');
    }
  }
  
  // Provide guidance when user returns to route
  void _provideOnRouteGuidance() {
    // Single gentle vibration for positive feedback
    HapticFeedback.mediumImpact();
    
    // Provide simple audio guidance
    _speak('Good. You are on the correct road now. Continue walking.');
  }

  // Simpler direction helper that only uses 4 cardinal directions
  String _getSimpleDirection(double bearing) {
    if (bearing >= 315 || bearing < 45) {
      return 'right';
    } else if (bearing >= 45 && bearing < 135) {
      return 'around';
    } else if (bearing >= 135 && bearing < 225) {
      return 'left';
    } else {
      return 'around';
    }
  }

  // Check if user is on the route - simplified version
  void _checkIfOnRoute() {
    if (_myLocation == null || _routePoints.isEmpty) return;
    
    // Find the closest point on the route
    double minDistance = double.infinity;
    for (final point in _routePoints) {
      final distance = Geolocator.distanceBetween(
        _myLocation!.latitude,
        _myLocation!.longitude,
        point.latitude,
        point.longitude,
      );
      
      if (distance < minDistance) {
        minDistance = distance;
      }
    }
    
    // Define threshold for being "on route" (25 meters - slightly more lenient)
    const double onRouteThreshold = 25.0;
    final bool wasOnRoute = _isOnRoute;
    
    // Check if user is on route based on distance
    if (minDistance <= onRouteThreshold) {
      _consecutiveOnRouteUpdates++;
      _consecutiveOffRouteUpdates = 0;
      
      // Only update status and provide feedback after consecutive confirmations
      if (_consecutiveOnRouteUpdates >= 2) {
        _isOnRoute = true;
        
        // If user was previously off route, provide feedback
        if (!wasOnRoute) {
          _provideOnRouteGuidance();
        } else if (_consecutiveOnRouteUpdates % 10 == 0) {
          // Less frequent confirmations (every ~50 seconds)
          _speak('You are on the right road. Keep going.');
        }
      }
    } else {
      _consecutiveOffRouteUpdates++;
      _consecutiveOnRouteUpdates = 0;
      
      // Only update status after consecutive off-route detections
      if (_consecutiveOffRouteUpdates >= 2) {
        _isOnRoute = false;
        
        // Provide feedback about deviation
        if (wasOnRoute || _consecutiveOffRouteUpdates % 3 == 0) {
          _provideOffRouteGuidance(minDistance);
        }
      }
    }
  }

  @override
  void dispose() {
    _locationStreamSubscription?.cancel();
    _addressStreamSubscription?.cancel();
    _liveLocationSubscription?.cancel();
    _locationUpdateTimer?.cancel();
    _favoritesSubscription?.cancel();
    _navigationSoundTimer?.cancel();
    _routeCheckTimer?.cancel();
    _flutterTts.stop();
    _audioPlayer.dispose();

    // Set tracking as inactive
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _firestore.collection('live_locations').doc(user.uid).update({
        'isActive': false,
        'lastSeenAt': FieldValue.serverTimestamp(),
      }).catchError(
          (e) => debugPrint('Error updating live tracking status: $e'));
    }

    super.dispose();
  }

  // Show language selection dialog
  void _showLanguageSelectionDialog(LanguageService languageService) {

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('language'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: languageService.getAvailableLanguages().map((language) {
            return ListTile(
              leading: Text(
                language.flag,
                style: const TextStyle(fontSize: 24),
              ),
              title: Text(language.name),
              subtitle: Text(language.localName),
              trailing: context.locale.languageCode == language.code
                  ? Icon(
                      Icons.check_circle,
                      color: Colors.green,
                    )
                  : null,
              onTap: () async {
                await languageService.setLanguage(context, language.code);
                // Update TTS language to match app language
                await _updateTTSLanguage(language.code);
                // Announce language change
                _speak('Language changed to ${language.name}');
                if (mounted) Navigator.pop(context);
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('cancel'.tr()),
          ),
        ],
      ),
    );
  }

  // Update TTS language based on app language
  Future<void> _updateTTSLanguage(String languageCode) async {
    String ttsLanguage;

    // Map app language codes to TTS language codes
    switch (languageCode) {
      case 'en':
        ttsLanguage = 'en-US';
        break;
      case 'ar':
        ttsLanguage = 'ar-EG';
        break;
      case 'de':
        ttsLanguage = 'de-DE';
        break;
      default:
        ttsLanguage = 'en-US';
    }

    try {
      await _flutterTts.setLanguage(ttsLanguage);
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setPitch(1.0);
      debugPrint('TTS language updated to: $ttsLanguage');
    } catch (e) {
      debugPrint('Error setting TTS language: $e');
    }
  }
}
