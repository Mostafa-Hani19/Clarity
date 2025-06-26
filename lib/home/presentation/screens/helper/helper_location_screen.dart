import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../services/location_service.dart';

class HelperLocationScreen extends StatefulWidget {
  final String blindUserId;
  final String blindUserName;

  const HelperLocationScreen({
    super.key,
    required this.blindUserId,
    required this.blindUserName,
  });

  @override
  State<HelperLocationScreen> createState() => _HelperLocationScreenState();
}

class _HelperLocationScreenState extends State<HelperLocationScreen> {
  // ignore: unused_field
  final LocationService _locationService = LocationService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Key for scaffold messenger
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  
  // Map controller
  final Completer<GoogleMapController> _mapController = Completer<GoogleMapController>();
  
  // Markers
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  
  // Location data
  LatLng? _blindUserLocation;
  LatLng? _selectedLocation;
  String? _blindUserAddress;
  String? _selectedAddress;
  
  // Live tracking data
  bool _isLiveTracking = false;
  StreamSubscription? _liveLocationSubscription;
  final List<LatLng> _locationHistory = [];
  LatLng? _predictedLocation;
  DateTime? _lastUpdate;
  
  // Blind user details
  double? _heading;
  double? _speed;
  bool _isNavigating = false;
  
  // Status
  bool _isLoading = true;
  bool _isSelectingLocation = false;
  // ignore: unused_field
  final bool _isSendingLocation = false;
  bool _isNavigationActive = false;
  
  // UI related
  bool _autoFollow = true;
  Timer? _refreshTimer;
  String? _errorMessage;
  
  // Favorite locations management
  List<Map<String, dynamic>> _blindUserFavorites = [];
  StreamSubscription? _favoritesSubscription;
  bool _isManagingFavorites = false;
  
  // Helper method to safely show snackbars
  void _showSnackBar(String message, {Color backgroundColor = Colors.blue}) {
    // Don't show SnackBar during build or if not mounted
    if (!mounted) return;
    
    // Store message to show after build is complete
    _errorMessage = message;
    
    // Only attempt to show directly if we're not in initState or build
    try {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _errorMessage != null) {
          final messenger = ScaffoldMessenger.of(context);
          messenger.clearSnackBars();
          messenger.showSnackBar(
            SnackBar(
              content: Text(_errorMessage!),
              backgroundColor: backgroundColor,
            ),
          );
          _errorMessage = null;
        }
      });
    } catch (e) {
      // If we can't show it now, it will be shown in didChangeDependencies
      debugPrint('Deferring SnackBar to didChangeDependencies: $e');
    }
  }
  
  @override
  void initState() {
    super.initState();
    _fetchBlindUserLocation();
    _setupLiveLocationUpdates();
    _fetchBlindUserFavorites();
    
    // Start a timer to refresh UI elements
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // Show error message if exists after build is complete
    if (_errorMessage != null) {
      final errorToShow = _errorMessage;
      _errorMessage = null;
      _showSnackBar(errorToShow!, backgroundColor: Colors.red);
    }
  }
  
  // Fetch the blind user's current location from Firebase
  Future<void> _fetchBlindUserLocation() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Validate blindUserId is not empty before creating the subscription
      if (widget.blindUserId.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Error: blindUserId is empty';
        });
        _showSnackBar('Error: Invalid blind user ID', backgroundColor: Colors.red);
        return;
      }
      
      // Setup a listener for real-time updates of blind user's location
      _firestore
          .collection('users')
          .doc(widget.blindUserId)
          .collection('location')
          .doc('current')
          .snapshots()
          .listen((snapshot) {
        if (snapshot.exists && snapshot.data() != null) {
          final data = snapshot.data()!;
          
          if (mounted) {
            setState(() {
              _blindUserLocation = LatLng(
                data['latitude'] as double,
                data['longitude'] as double,
              );
              
              _blindUserAddress = data['address'] as String? ?? 'Unknown location';
              _heading = data['heading'] as double?;
              _speed = data['speed'] as double?;
              _isNavigating = data['isNavigating'] as bool? ?? false;
              _isLiveTracking = data['isLiveTracking'] as bool? ?? false;
              
              // Update the map marker
              _updateMarkers();
              
              // Add to location history
              if (_blindUserLocation != null) {
                _addToLocationHistory(_blindUserLocation!);
              }
              
              // Move camera to blind user's location if map is ready
              if (_mapController.isCompleted && _blindUserLocation != null && _autoFollow) {
                _animateToPosition(_blindUserLocation!);
              }
            });
          }
        }
      });
      
      // Listen for navigation status
      _firestore
          .collection('users')
          .doc(widget.blindUserId)
          .collection('navigation')
          .doc('destination')
          .snapshots()
          .listen((snapshot) {
        if (snapshot.exists && snapshot.data() != null) {
          final data = snapshot.data()!;
          
          final bool isAcknowledged = data['acknowledged'] ?? false;
          final bool isNavigationStarted = data['navigationStarted'] ?? false;
          final bool isCompleted = data['completed'] ?? false;
          
          if (mounted) {
            setState(() {
              _isNavigationActive = isAcknowledged && isNavigationStarted && !isCompleted;
              
              // If the location was accepted or rejected, update the UI
              if (isAcknowledged) {
              }
            });
          }
        }
      });
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching blind user location: $e');
      
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Error fetching location: $e';
        });
        
        // Directly use the helper method
        _showSnackBar('Error fetching location: $e', backgroundColor: Colors.red);
      }
    }
  }
  
  // Set up live location updates from the dedicated live_locations collection
  void _setupLiveLocationUpdates() {
    // Cancel any existing subscription
    _liveLocationSubscription?.cancel();
    
    // Validate blindUserId is not empty before creating the subscription
    if (widget.blindUserId.isEmpty) {
      debugPrint('❌ Error: blindUserId is empty, cannot setup live location updates');
      return;
    }
    
    _liveLocationSubscription = _firestore
        .collection('live_locations')
        .doc(widget.blindUserId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        final data = snapshot.data()!;
        final bool isActive = data['isActive'] as bool? ?? false;
        
        if (isActive) {
          final double latitude = data['latitude'] as double;
          final double longitude = data['longitude'] as double;
          final LatLng liveLocation = LatLng(latitude, longitude);
          
          // Also get predicted location if available
          LatLng? predicted;
          if (data['predicted'] != null) {
            final predictedData = data['predicted'] as Map<String, dynamic>;
            predicted = LatLng(
              predictedData['latitude'] as double,
              predictedData['longitude'] as double,
            );
          }
          
          // Get additional metadata
          final double? heading = data['heading'] as double?;
          final double? speed = data['speed'] as double?;
          final bool isNavigating = data['isNavigating'] as bool? ?? false;
          final Timestamp? timestamp = data['lastSeenAt'] as Timestamp?;
          
          if (mounted) {
            setState(() {
              _isLiveTracking = true;
              _blindUserLocation = liveLocation;
              _predictedLocation = predicted;
              _heading = heading;
              _speed = speed;
              _isNavigating = isNavigating;
              _lastUpdate = timestamp?.toDate();
              
              // Add to location history
              _addToLocationHistory(liveLocation);
              
              // Update the map
              _updateMarkers();
              
              // Move camera to blind user's location if auto-follow is enabled
              if (_mapController.isCompleted && _autoFollow) {
                _animateToPosition(liveLocation);
              }
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _isLiveTracking = false;
            });
          }
        }
      }
    }, onError: (e) {
      debugPrint('Error listening to live location updates: $e');
    });
  }
  
  // Fetch blind user's favorite locations
  void _fetchBlindUserFavorites() {
    if (widget.blindUserId.isEmpty) {
      debugPrint('❌ Error: blindUserId is empty, cannot fetch favorites');
      return;
    }
    
    try {
      _favoritesSubscription = _firestore
          .collection('users')
          .doc(widget.blindUserId)
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
        
        if (mounted) {
          setState(() {
            _blindUserFavorites = favorites;
          });
        }
      }, onError: (e) {
        debugPrint('Error listening to blind user favorites: $e');
      });
    } catch (e) {
      debugPrint('Error setting up favorites subscription: $e');
    }
  }
  
  // Add a favorite location for the blind user
  Future<bool> _addFavoriteForBlindUser(LatLng location, String name, String address, {String notes = 'Added by helper'}) async {
    try {
      // Create data for the favorite
      final Map<String, dynamic> favoriteData = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'name': name,
        'latitude': location.latitude,
        'longitude': location.longitude,
        'address': address,
        'notes': notes,
        'createdAt': FieldValue.serverTimestamp(),
        'addedByHelper': true,
      };
      
      // Add to Firestore
      await _firestore
          .collection('users')
          .doc(widget.blindUserId)
          .collection('favorites')
          .doc(favoriteData['id'] as String)
          .set(favoriteData);
      
      // Also add notification for blind user
      await _firestore
          .collection('users')
          .doc(widget.blindUserId)
          .collection('notifications')
          .add({
            'type': 'favorite_added',
            'title': 'New Favorite Location',
            'message': 'Your helper added a new favorite location: $name',
            'description': notes,
            'timestamp': FieldValue.serverTimestamp(),
            'isRead': false,
            'data': {
              'latitude': location.latitude,
              'longitude': location.longitude,
              'address': address,
              'name': name,
            }
          });
      
      _showSnackBar('Favorite location added for ${widget.blindUserName}', backgroundColor: Colors.green);
      return true;
    } catch (e) {
      debugPrint('Error adding favorite for blind user: $e');
      _showSnackBar('Failed to add favorite location', backgroundColor: Colors.red);
      return false;
    }
  }
  
  // Delete a favorite location for the blind user
  Future<bool> _deleteFavoriteForBlindUser(String favoriteId, String favoriteName) async {
    try {
      // Delete from Firestore
      await _firestore
          .collection('users')
          .doc(widget.blindUserId)
          .collection('favorites')
          .doc(favoriteId)
          .delete();
      
      // Add notification for blind user
      await _firestore
          .collection('users')
          .doc(widget.blindUserId)
          .collection('notifications')
          .add({
            'type': 'favorite_deleted',
            'title': 'Favorite Location Removed',
            'message': 'Your helper removed a favorite location: $favoriteName',
            'timestamp': FieldValue.serverTimestamp(),
            'isRead': false,
          });
      
      _showSnackBar('Favorite location removed', backgroundColor: Colors.green);
      return true;
    } catch (e) {
      debugPrint('Error deleting favorite for blind user: $e');
      _showSnackBar('Failed to remove favorite location', backgroundColor: Colors.red);
      return false;
    }
  }
  
  // Show dialog to add a favorite location
  Future<void> _showAddFavoriteDialog() async {
    if (_selectedLocation == null) {
      _showSnackBar('Please select a location on the map first', backgroundColor: Colors.orange);
      setState(() {
        _isSelectingLocation = true;
      });
      return;
    }
    
    final TextEditingController nameController = TextEditingController();
    final TextEditingController notesController = TextEditingController();
    notesController.text = 'Added by helper';
    
    // Show the dialog
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Add Favorite for ${widget.blindUserName}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Selected location: $_selectedAddress'),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name for this location',
                    hintText: 'e.g. Home, Work, etc.',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes for blind user',
                    hintText: 'Description or directions',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                const Text(
                  'This favorite place will be added to the blind user\'s list and they will receive a notification.',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a name for this location')),
                  );
                  return;
                }
                
                Navigator.pop(context);
                _addFavoriteForBlindUser(
                  _selectedLocation!,
                  nameController.text,
                  _selectedAddress ?? 'Unknown location',
                  notes: notesController.text,
                );
                
                // Reset selection
                setState(() {
                  _isSelectingLocation = false;
                  _selectedLocation = null;
                  _selectedAddress = null;
                  _updateMarkers();
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('Add Favorite'),
            ),
          ],
        );
      },
    );
  }
  
  // Show favorite locations management bottom sheet
  void _showManageFavoritesBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.blindUserName}\'s Favorite Places',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _blindUserFavorites.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Text(
                          'No favorite places yet.\nTap the + button to add a favorite location.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ),
                    )
                  : Expanded(
                      child: ListView.builder(
                        itemCount: _blindUserFavorites.length,
                        itemBuilder: (context, index) {
                          final favorite = _blindUserFavorites[index];
                          return Dismissible(
                            key: Key(favorite['id'] as String),
                            background: Container(
                              color: Colors.red,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 16),
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
                                    title: const Text('Confirm Deletion'),
                                    content: Text(
                                      'Are you sure you want to remove "${favorite['name']}" from ${widget.blindUserName}\'s favorites?'
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.of(context).pop(false),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.of(context).pop(true),
                                        child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                            onDismissed: (direction) {
                              _deleteFavoriteForBlindUser(
                                favorite['id'] as String,
                                favorite['name'] as String,
                              );
                            },
                            child: ListTile(
                              leading: const Icon(Icons.place, color: Colors.red),
                              title: Text(favorite['name'] as String),
                              subtitle: Text(
                                favorite['address'] as String? ?? 'No address available',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () {
                                // Navigate to this location on the map
                                final LatLng position = LatLng(
                                  favorite['latitude'] as double,
                                  favorite['longitude'] as double,
                                );
                                
                                // Close bottom sheet
                                Navigator.pop(context);
                                
                                // Move map to this position
                                if (_mapController.isCompleted) {
                                  _mapController.future.then((controller) {
                                    controller.animateCamera(
                                      CameraUpdate.newLatLngZoom(position, 17),
                                    );
                                  });
                                }
                                
                                // Show marker
                                setState(() {
                                  _selectedLocation = position;
                                  _selectedAddress = favorite['address'] as String? ?? favorite['name'] as String;
                                  _updateMarkers();
                                });
                              },
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () async {
                                  final bool confirm = await showDialog(
                                    context: context,
                                    builder: (BuildContext context) {
                                      return AlertDialog(
                                        title: const Text('Confirm Deletion'),
                                        content: Text(
                                          'Are you sure you want to remove "${favorite['name']}" from ${widget.blindUserName}\'s favorites?'
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.of(context).pop(false),
                                            child: const Text('Cancel'),
                                          ),
                                          TextButton(
                                            onPressed: () => Navigator.of(context).pop(true),
                                            child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                  
                                  if (confirm) {
                                    _deleteFavoriteForBlindUser(
                                      favorite['id'] as String,
                                      favorite['name'] as String,
                                    );
                                  }
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.add_location),
                      label: const Text('Add New Favorite'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() {
                          _isSelectingLocation = true;
                        });
                        _showSnackBar('Tap on the map to select a location');
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
  
  // Add a location to the history with some filtering
  void _addToLocationHistory(LatLng location) {
    // Only add if it's different enough from the last point
    if (_locationHistory.isEmpty || 
        _calculateDistance(_locationHistory.last, location) > 2) {
      
      _locationHistory.add(location);
      
      // Limit history to prevent excessive memory usage
      if (_locationHistory.length > 100) {
        _locationHistory.removeAt(0);
      }
      
      // Update polyline
      _updatePolylines();
    }
  }
  
  // Calculate distance between two coordinates in meters
  double _calculateDistance(LatLng point1, LatLng point2) {
    // Simple Euclidean distance for performance - not accurate for long distances
    // For a real app, use Haversine formula for more accuracy
    const double earthRadius = 6371000; // meters
    final double latDiff = (point2.latitude - point1.latitude) * (math.pi / 180);
    final double lngDiff = (point2.longitude - point1.longitude) * (math.pi / 180);
    
    final double a = latDiff * latDiff + 
                     lngDiff * lngDiff * 
                     math.cos(point1.latitude * (math.pi / 180));
    return earthRadius * math.sqrt(a);
  }
  
  // Update polylines for tracking history
  void _updatePolylines() {
    if (_locationHistory.length < 2) return;
    
    _polylines.clear();
    _polylines.add(
      Polyline(
        polylineId: const PolylineId('location_history'),
        points: _locationHistory,
        color: Colors.blue.withOpacity(0.7),
        width: 5,
      ),
    );
  }
  
  // Update map markers based on current state
  void _updateMarkers() {
    _markers.clear();
    
    // Add blind user's location marker with heading indicator
    if (_blindUserLocation != null) {
      final BitmapDescriptor markerIcon = _heading != null && _speed != null && _speed! > 0.5
          ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure)
          : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
      
      _markers.add(
        Marker(
          markerId: const MarkerId('blind_user'),
          position: _blindUserLocation!,
          rotation: _heading ?? 0,
          flat: _heading != null,
          infoWindow: InfoWindow(
            title: widget.blindUserName,
            snippet: _blindUserAddress ?? 'Current location',
          ),
          icon: markerIcon,
        ),
      );
      
      // Add a predicted position marker if available
      if (_predictedLocation != null) {
        _markers.add(
          Marker(
            markerId: const MarkerId('predicted_position'),
            position: _predictedLocation!,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
            alpha: 0.6,
            infoWindow: const InfoWindow(
              title: 'Predicted Position',
              snippet: 'Where the user will be in a few seconds',
            ),
          ),
        );
      }
    }
    
    // Add selected location marker
    if (_selectedLocation != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('selected_location'),
          position: _selectedLocation!,
          infoWindow: InfoWindow(
            title: 'Selected Destination',
            snippet: _selectedAddress ?? 'Tap to get address',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );
    }
  }
  
  // Animate map to a position
  Future<void> _animateToPosition(LatLng position) async {
    final controller = await _mapController.future;
    controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: position,
          zoom: 17.0,
        ),
      ),
    );
  }
  
  // Get address from coordinates
  Future<void> _getAddressFromCoordinates(LatLng coordinates) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        coordinates.latitude,
        coordinates.longitude,
      );
      
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks.first;
        setState(() {
          _selectedAddress = '${place.street}, ${place.locality}, ${place.country}';
        });
      }
    } catch (e) {
      debugPrint('Error getting address: $e');
      setState(() {
        _selectedAddress = 'Address unavailable';
      });
    }
  }
  
  // Select location on map tap
  void _selectLocation(LatLng location) async {
    if (!_isSelectingLocation) return;
    
    setState(() {
      _selectedLocation = location;
      _selectedAddress = 'Getting address...';
    });
    
    _updateMarkers();
    
    // Get the address for the selected location
    await _getAddressFromCoordinates(location);
    
    // Show the add favorite dialog if we're managing favorites
    if (_isManagingFavorites) {
      _showAddFavoriteDialog();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Calculate time since last update
    String lastUpdateText = 'No updates yet';
    if (_lastUpdate != null) {
      final difference = DateTime.now().difference(_lastUpdate!);
      if (difference.inSeconds < 60) {
        lastUpdateText = '${difference.inSeconds} seconds ago';
      } else if (difference.inMinutes < 60) {
        lastUpdateText = '${difference.inMinutes} minutes ago';
      } else {
        lastUpdateText = '${difference.inHours} hours ago';
      }
    }
    
    return ScaffoldMessenger(
      key: _scaffoldMessengerKey,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${widget.blindUserName}\'s Location'),
          backgroundColor: Colors.green.shade700,
          actions: [
            // Add favorite locations management button
            IconButton(
              icon: const Icon(Icons.star),
              onPressed: _showManageFavoritesBottomSheet,
              tooltip: 'Manage favorite places',
            ),
            
            // Live indicator
            if (_isLiveTracking)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.green.withOpacity(0.5),
                            blurRadius: 4,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text('LIVE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            
            // Auto-follow toggle
            IconButton(
              icon: Icon(_autoFollow ? Icons.location_searching : Icons.location_disabled),
              onPressed: () {
                setState(() {
                  _autoFollow = !_autoFollow;
                  if (_autoFollow && _blindUserLocation != null && _mapController.isCompleted) {
                    _animateToPosition(_blindUserLocation!);
                  }
                });
              },
              tooltip: _autoFollow ? 'Auto-follow enabled' : 'Auto-follow disabled',
            ),
          ],
        ),
        body: Stack(
          children: [
            // Map
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _blindUserLocation ?? const LatLng(0, 0),
                zoom: _blindUserLocation != null ? 17.0 : 2.0,
              ),
              markers: _markers,
              polylines: _polylines,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              mapToolbarEnabled: false,
              compassEnabled: true,
              onMapCreated: (GoogleMapController controller) {
                _mapController.complete(controller);
                
                // Update markers after map is created
                _updateMarkers();
                
                // Move to blind user's location if available
                if (_blindUserLocation != null) {
                  _animateToPosition(_blindUserLocation!);
                }
              },
              onTap: _isSelectingLocation ? _selectLocation : null,
              onCameraMove: (_) {
                // Disable auto-follow when user manually moves the camera
                if (_autoFollow) {
                  setState(() {
                    _autoFollow = false;
                  });
                }
              },
            ),
            
            // Location info panel at top
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${widget.blindUserName}\'s Location',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          
                          // Live indicator with timestamp
                          if (_isLiveTracking)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: Colors.green,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Live',
                                    style: TextStyle(
                                      fontSize: 12, 
                                      color: Colors.green.shade800,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isLoading
                            ? 'Loading location...'
                            : _blindUserAddress ?? 'Location unavailable',
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      if (_lastUpdate != null)
                        Text(
                          'Last update: $lastUpdateText',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      
                      if (_speed != null && _speed! > 0.5) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Speed: ${(_speed! * 3.6).toStringAsFixed(1)} km/h',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                      
                      if (_isNavigating || _isNavigationActive) ...[
                        const Divider(height: 16),
                        Row(
                          children: [
                            const Icon(
                              Icons.directions_walk,
                              color: Colors.green,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${widget.blindUserName} is navigating to the destination',
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Add favorite FAB
            if (!_isSelectingLocation && !_isNavigationActive)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: FloatingActionButton.extended(
                  heroTag: 'add_favorite',
                  onPressed: () {
                    setState(() {
                      _isSelectingLocation = true;
                      _isManagingFavorites = true;
                    });
                    _showSnackBar('Tap on the map to select a favorite location for ${widget.blindUserName}');
                  },
                  backgroundColor: Colors.amber,
                  icon: const Icon(Icons.star),
                  label: const Text('Add Favorite'),
                ),
              ),
            
            // Show cancel button when in selection mode
            if (_isSelectingLocation)
              FloatingActionButton.extended(
                onPressed: () {
                  setState(() {
                    // If we were adding a favorite and selected a location, show dialog
                    if (_isManagingFavorites && _selectedLocation != null) {
                      _showAddFavoriteDialog();
                      _isManagingFavorites = false;
                    } else {
                      // Otherwise just cancel selection
                      _isSelectingLocation = false;
                      _isManagingFavorites = false;
                      _selectedLocation = null;
                      _selectedAddress = null;
                      _updateMarkers();
                    }
                  });
                },
                backgroundColor: Colors.red,
                icon: const Icon(Icons.close),
                label: Text('Cancel'.tr()),
              ),
          ],
        ),
      ),
    );
  }
  
  @override
  void dispose() {
    _liveLocationSubscription?.cancel();
    _refreshTimer?.cancel();
    _favoritesSubscription?.cancel();
    super.dispose();
  }
} 