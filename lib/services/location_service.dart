import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  
  factory LocationService() {
    return _instance;
  }
  
  LocationService._internal() {
    // Initialize favorites listener when service is created
    initFavoritesListener();
  }
  
  // Firebase references
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // TTS engine
  final FlutterTts _flutterTts = FlutterTts();
  bool _isTtsInitialized = false;
  
  // Location tracking
  Position? _currentPosition;
  LatLng? _currentLatLng;
  String? _currentAddress;
  StreamSubscription<Position>? _positionStreamSubscription;
  
  // Destination location from sighted user
  LatLng? _destinationLatLng;
  String? _destinationAddress;
  
  // Status
  bool _isTracking = false;
  bool _isNavigating = false;
  bool _hasNewDestination = false;
  String _navigationStatus = '';
  
  // Stream controllers for reactive UI
  final StreamController<LatLng?> _locationStreamController = StreamController<LatLng?>.broadcast();
  final StreamController<String?> _addressStreamController = StreamController<String?>.broadcast();
  final StreamController<bool> _hasNewDestinationStreamController = StreamController<bool>.broadcast();
  final StreamController<LatLng?> _destinationStreamController = StreamController<LatLng?>.broadcast();
  final StreamController<String?> _destinationAddressStreamController = StreamController<String?>.broadcast();
  final StreamController<String> _navigationStatusStreamController = StreamController<String>.broadcast();
  
  // Public streams
  Stream<LatLng?> get locationStream => _locationStreamController.stream;
  Stream<String?> get addressStream => _addressStreamController.stream;
  Stream<bool> get hasNewDestinationStream => _hasNewDestinationStreamController.stream;
  Stream<LatLng?> get destinationStream => _destinationStreamController.stream;
  Stream<String?> get destinationAddressStream => _destinationAddressStreamController.stream;
  Stream<String> get navigationStatusStream => _navigationStatusStreamController.stream;
  
  // Getters
  LatLng? get currentLocation => _currentLatLng;
  String? get currentAddress => _currentAddress;
  LatLng? get destinationLocation => _destinationLatLng;
  String? get destinationAddress => _destinationAddress;
  bool get isTracking => _isTracking;
  bool get isNavigating => _isNavigating;
  bool get hasNewDestination => _hasNewDestination;
  String get navigationStatus => _navigationStatus;
  
  // Initialize TTS
  Future<void> initTTS() async {
    try {
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      
      _isTtsInitialized = true;
    } catch (e) {
      debugPrint('Error initializing TTS: $e');
      _isTtsInitialized = false;
    }
  }
  
  // Speak message using TTS
  Future<void> speak(String message) async {
    if (!_isTtsInitialized) {
      await initTTS();
    }
    
    if (_isTtsInitialized) {
      try {
        await _flutterTts.speak(message);
      } catch (e) {
        debugPrint('Error speaking: $e');
      }
    }
  }
  
  // Check location permissions
  Future<bool> _checkLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;
    
    // Test if location services are enabled
    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // Location services are not enabled, prompt user to enable them
        speak('Location services are disabled. Please enable location services in your device settings.');
        debugPrint('Location services are disabled. Enable location services in settings.');
        return false;
      }
    } catch (e) {
      debugPrint('Error checking location service status: $e');
      speak('Error checking location service status. Please check your device settings.');
      return false;
    }
    
    try {
      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        speak('Location permission is required for navigation.');
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          // Permissions are denied, next time you could try
          // requesting permissions again
          speak('Location permission denied. Navigation features will not work.');
          debugPrint('Location permission denied');
          return false;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        // Permissions are denied forever, handle appropriately.
        speak('Location permission permanently denied. Please enable location in app settings.');
        debugPrint('Location permission permanently denied. Navigate to app settings to enable.');
        return false;
      }
      
      // Permissions are granted
      return true;
    } catch (e) {
      debugPrint('Error requesting location permission: $e');
      speak('Error requesting location permission. Please check your device settings.');
      return false;
    }
  }
  
  // Get a simulated location for testing in emulator
  Future<Position?> _getSimulatedLocation() async {
    try {
      // Attempt to use the last known position as a fallback
      Position? position = await Geolocator.getLastKnownPosition();
      
      if (position != null) {
        debugPrint('Using last known position as fallback');
        return position;
      }
      
      // If no last known position, use a default position (London)
      debugPrint('Using default position for emulator testing');
      return Position(
        latitude: 51.509865,
        longitude: -0.118092,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        heading: 0,
        speed: 0,
        speedAccuracy: 0,
        floor: null,
        isMocked: true,
        altitudeAccuracy: 0,
        headingAccuracy: 0,
      );
    } catch (e) {
      debugPrint('Error getting simulated location: $e');
      return null;
    }
  }
  
  // Initialize location tracking
  Future<bool> startTracking() async {
    if (_isTracking) return true;
    
    // Check permissions
    final hasPermission = await _checkLocationPermission();
    if (!hasPermission) {
      debugPrint('Location permission not granted');
      return false;
    }
    
    // Initialize TTS
    await initTTS();
    
    try {
      // Get initial position with timeout to prevent hanging
      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 15),
      ).catchError((error) async {
        debugPrint('Error getting current position: $error');
        speak('Could not determine your current location. Trying alternative methods.');
        
        // Try to get simulated location as fallback
        final simulatedPosition = await _getSimulatedLocation();
        if (simulatedPosition != null) {
          return simulatedPosition;
        }
        
        throw error;
      });
      
      _currentLatLng = LatLng(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
      );
      
      // Update streams
      _locationStreamController.add(_currentLatLng);
      
      // Get address for current location
      _updateAddressFromCoordinates(_currentLatLng!);
      
      // Start position stream with fallback for emulators
      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10, // Update every 10 meters
        ),
      ).listen(_onPositionUpdate, onError: (e) async {
        debugPrint('Error in position stream: $e');
        speak('Location tracking error. Using simulated location for testing.');
        
        // If stream fails, use simulated location
        final simulatedPosition = await _getSimulatedLocation();
        if (simulatedPosition != null) {
          _onPositionUpdate(simulatedPosition);
        }
      });
      
      // Start listening for destination updates
      _listenForDestinationUpdates();
      
      _isTracking = true;
      return true;
    } catch (e) {
      debugPrint('Error starting location tracking: $e');
      speak('Error starting location tracking. Please try again.');
      return false;
    }
  }
  
  // Stop tracking
  void stopTracking() {
    _positionStreamSubscription?.cancel();
    _isTracking = false;
  }
  
  // Handle position updates
  void _onPositionUpdate(Position position) {
    _currentPosition = position;
    _currentLatLng = LatLng(position.latitude, position.longitude);
    
    // Update streams
    _locationStreamController.add(_currentLatLng);
    
    // Update address occasionally (not on every position update to avoid API rate limits)
    if (_currentAddress == null) {
      _updateAddressFromCoordinates(_currentLatLng!);
    }
    
    // Update Firebase with current location
    _updateFirebaseLocation();
    
    // If navigating, check if we've reached the destination
    if (_isNavigating && _destinationLatLng != null) {
      _updateNavigationStatus();
    }
  }
  
  // Get address from coordinates
  Future<void> _updateAddressFromCoordinates(LatLng coordinates) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        coordinates.latitude,
        coordinates.longitude,
      );
      
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks.first;
        _currentAddress = '${place.street}, ${place.locality}, ${place.country}';
        _addressStreamController.add(_currentAddress);
      }
    } catch (e) {
      debugPrint('Error getting address: $e');
    }
  }
  
  // Update Firebase with current location
  Future<void> _updateFirebaseLocation() async {
    if (_currentLatLng == null || _auth.currentUser == null) return;
    
    try {
      await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .collection('location')
          .doc('current')
          .set({
        'latitude': _currentLatLng!.latitude,
        'longitude': _currentLatLng!.longitude,
        'address': _currentAddress ?? '',
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error updating Firebase location: $e');
    }
  }
  
  // Listen for destination updates from sighted users
  void _listenForDestinationUpdates() {
    if (_auth.currentUser == null) return;
    
    _firestore
        .collection('users')
        .doc(_auth.currentUser!.uid)
        .collection('navigation')
        .doc('destination')
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        final data = snapshot.data()!;
        
        // Check if this is a new destination (has not been acknowledged)
        final bool isAcknowledged = data['acknowledged'] ?? false;
        
        if (!isAcknowledged) {
          _destinationLatLng = LatLng(
            data['latitude'] as double,
            data['longitude'] as double,
          );
          
          _destinationAddress = data['address'] as String? ?? 'Unknown location';
          
          // Update streams
          _destinationStreamController.add(_destinationLatLng);
          _destinationAddressStreamController.add(_destinationAddress);
          
          // Update status
          _hasNewDestination = true;
          _hasNewDestinationStreamController.add(true);
          
          // Notify the user with voice
          speak('A new destination has been received. ${_destinationAddress ?? ''}');
        }
      }
    });
  }
  
  // Accept navigation to destination
  Future<void> acceptNavigation() async {
    if (_destinationLatLng == null || _auth.currentUser == null) return;
    
    try {
      // Mark destination as acknowledged
      await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .collection('navigation')
          .doc('destination')
          .update({
        'acknowledged': true,
        'navigationStarted': true,
        'startTime': FieldValue.serverTimestamp(),
      });
      
      // Start navigation
      _isNavigating = true;
      _hasNewDestination = false;
      _hasNewDestinationStreamController.add(false);
      
      // Initial navigation guidance
      _startNavigation();
    } catch (e) {
      debugPrint('Error accepting navigation: $e');
    }
  }
  
  // Reject navigation request
  Future<void> rejectNavigation() async {
    if (_auth.currentUser == null) return;
    
    try {
      // Mark destination as rejected
      await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .collection('navigation')
          .doc('destination')
          .update({
        'acknowledged': true,
        'navigationStarted': false,
        'rejected': true,
      });
      
      // Reset destination
      _destinationLatLng = null;
      _destinationAddress = null;
      _hasNewDestination = false;
      
      // Update streams
      _destinationStreamController.add(null);
      _destinationAddressStreamController.add(null);
      _hasNewDestinationStreamController.add(false);
      
      speak('Navigation request rejected.');
    } catch (e) {
      debugPrint('Error rejecting navigation: $e');
    }
  }
  
  // Start navigation guidance
  void _startNavigation() {
    if (_currentLatLng == null || _destinationLatLng == null) return;
    
    // Initial guidance
    _updateNavigationStatus();
    
    // Speak initial directions
    speak('Starting navigation to $_destinationAddress. $_navigationStatus');
  }
  
  // Update navigation status (distance, directions, etc.)
  void _updateNavigationStatus() {
    if (_currentLatLng == null || _destinationLatLng == null) return;
    
    // Calculate distance
    final distanceInMeters = Geolocator.distanceBetween(
      _currentLatLng!.latitude,
      _currentLatLng!.longitude,
      _destinationLatLng!.latitude,
      _destinationLatLng!.longitude,
    );
    
    // Calculate bearing
    final bearing = Geolocator.bearingBetween(
      _currentLatLng!.latitude,
      _currentLatLng!.longitude,
      _destinationLatLng!.latitude,
      _destinationLatLng!.longitude,
    );
    
    // Convert bearing to direction
    final direction = _getDirectionFromBearing(bearing);
    
    // Format distance
    final String distanceText = distanceInMeters < 1000
        ? '${distanceInMeters.round()} meters'
        : '${(distanceInMeters / 1000).toStringAsFixed(2)} kilometers';
    
    // Update navigation status
    _navigationStatus = 'Distance: $distanceText. Direction: $direction';
    _navigationStatusStreamController.add(_navigationStatus);
    
    // Check if we've reached the destination (within 20 meters)
    if (distanceInMeters < 20) {
      _isNavigating = false;
      _navigationStatus = 'You have reached your destination!';
      _navigationStatusStreamController.add(_navigationStatus);
      speak('You have reached your destination!');
      
      // Reset destination after arrival
      _clearDestination();
    }
  }
  
  // Convert bearing to cardinal direction
  String _getDirectionFromBearing(double bearing) {
    const directions = ['north', 'northeast', 'east', 'southeast', 'south', 'southwest', 'west', 'northwest', 'north'];
    return directions[(((bearing + 22.5) % 360) / 45).floor()];
  }
  
  // Clear destination after arrival
  Future<void> _clearDestination() async {
    if (_auth.currentUser == null) return;
    
    try {
      // Mark navigation as completed
      await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .collection('navigation')
          .doc('destination')
          .update({
        'completed': true,
        'completionTime': FieldValue.serverTimestamp(),
      });
      
      // Reset destination
      _destinationLatLng = null;
      _destinationAddress = null;
      _isNavigating = false;
      
      // Update streams
      _destinationStreamController.add(null);
      _destinationAddressStreamController.add(null);
    } catch (e) {
      debugPrint('Error clearing destination: $e');
    }
  }
  
  // Stream controller for favorite locations
  final StreamController<List<Map<String, dynamic>>> _favoritesStreamController = StreamController<List<Map<String, dynamic>>>.broadcast();
  
  // Public stream
  Stream<List<Map<String, dynamic>>> favoritesStream() => _favoritesStreamController.stream;
  
  // Add a favorite location
  Future<bool> addFavorite(LatLng location, String name, {String? address, String? notes}) async {
    if (_auth.currentUser == null) return false;
    
    try {
      // Generate a unique ID for the favorite
      final String favoriteId = DateTime.now().millisecondsSinceEpoch.toString();
      
      // Create favorite data
      final Map<String, dynamic> favoriteData = {
        'id': favoriteId,
        'name': name,
        'latitude': location.latitude,
        'longitude': location.longitude,
        'address': address ?? '',
        'notes': notes ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      };
      
      // Save to Firestore
      await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .collection('favorites')
          .doc(favoriteId)
          .set(favoriteData);
      
      // Fetch updated favorites to refresh the stream
      _fetchFavorites();
      
      return true;
    } catch (e) {
      debugPrint('Error adding favorite: $e');
      return false;
    }
  }
  
  // Delete a favorite location
  Future<bool> deleteFavorite(String favoriteId) async {
    if (_auth.currentUser == null) return false;
    
    try {
      // Delete from Firestore
      await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .collection('favorites')
          .doc(favoriteId)
          .delete();
      
      // Fetch updated favorites to refresh the stream
      _fetchFavorites();
      
      return true;
    } catch (e) {
      debugPrint('Error deleting favorite: $e');
      return false;
    }
  }
  
  // Fetch all favorite locations
  Future<List<Map<String, dynamic>>> getFavorites() async {
    if (_auth.currentUser == null) return [];
    
    try {
      final querySnapshot = await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .collection('favorites')
          .orderBy('createdAt', descending: true)
          .get();
      
      final List<Map<String, dynamic>> favorites = [];
      
      for (final doc in querySnapshot.docs) {
        final data = doc.data();
        favorites.add({
          'id': doc.id,
          'name': data['name'] ?? 'Unnamed',
          'latitude': data['latitude'] ?? 0.0,
          'longitude': data['longitude'] ?? 0.0,
          'address': data['address'] ?? '',
          'notes': data['notes'] ?? '',
          'createdAt': data['createdAt'],
        });
      }
      
      // Update the stream
      _favoritesStreamController.add(favorites);
      
      return favorites;
    } catch (e) {
      debugPrint('Error fetching favorites: $e');
      return [];
    }
  }
  
  // Fetch a single favorite location
  Future<Map<String, dynamic>?> getFavorite(String favoriteId) async {
    if (_auth.currentUser == null) return null;
    
    try {
      final docSnapshot = await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .collection('favorites')
          .doc(favoriteId)
          .get();
      
      if (docSnapshot.exists) {
        final data = docSnapshot.data()!;
        return {
          'id': docSnapshot.id,
          'name': data['name'] ?? 'Unnamed',
          'latitude': data['latitude'] ?? 0.0,
          'longitude': data['longitude'] ?? 0.0,
          'address': data['address'] ?? '',
          'notes': data['notes'] ?? '',
          'createdAt': data['createdAt'],
        };
      } else {
        return null;
      }
    } catch (e) {
      debugPrint('Error fetching favorite: $e');
      return null;
    }
  }
  
  // Fetch and listen to favorites
  void _fetchFavorites() {
    if (_auth.currentUser == null) return;
    
    _firestore
        .collection('users')
        .doc(_auth.currentUser!.uid)
        .collection('favorites')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((querySnapshot) {
      final List<Map<String, dynamic>> favorites = [];
      
      for (final doc in querySnapshot.docs) {
        final data = doc.data();
        favorites.add({
          'id': doc.id,
          'name': data['name'] ?? 'Unnamed',
          'latitude': data['latitude'] ?? 0.0,
          'longitude': data['longitude'] ?? 0.0,
          'address': data['address'] ?? '',
          'notes': data['notes'] ?? '',
          'createdAt': data['createdAt'],
        });
      }
      
      // Update the stream
      _favoritesStreamController.add(favorites);
    });
  }
  
  // Initialize favorite locations listener
  void initFavoritesListener() {
    _fetchFavorites();
  }
  
  // Send location from sighted user to blind user
  Future<bool> sendDestinationToBlindUser(String blindUserId, LatLng destination, String address) async {
    try {
      await _firestore
          .collection('users')
          .doc(blindUserId)
          .collection('navigation')
          .doc('destination')
          .set({
        'latitude': destination.latitude,
        'longitude': destination.longitude,
        'address': address,
        'timestamp': FieldValue.serverTimestamp(),
        'senderId': _auth.currentUser?.uid,
        'senderName': _auth.currentUser?.displayName,
        'acknowledged': false,
        'navigationStarted': false,
        'completed': false,
      });
      
      return true;
    } catch (e) {
      debugPrint('Error sending destination: $e');
      return false;
    }
  }
  
  // Dispose resources
  void dispose() {
    _positionStreamSubscription?.cancel();
    _locationStreamController.close();
    _addressStreamController.close();
    _hasNewDestinationStreamController.close();
    _destinationStreamController.close();
    _destinationAddressStreamController.close();
    _navigationStatusStreamController.close();
    _favoritesStreamController.close();
    _flutterTts.stop();
  }
} 