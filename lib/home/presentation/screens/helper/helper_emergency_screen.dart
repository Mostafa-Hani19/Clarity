import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../services/location_service.dart';
import '../../../../providers/auth_provider.dart';

class HelperEmergencyScreen extends StatefulWidget {
  final String emergencyAlertId;
  
  const HelperEmergencyScreen({
    super.key,
    required this.emergencyAlertId,
  });

  @override
  State<HelperEmergencyScreen> createState() => _HelperEmergencyScreenState();
}

class _HelperEmergencyScreenState extends State<HelperEmergencyScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LocationService _locationService = LocationService();
  
  bool _isLoading = true;
  bool _isError = false;
  String _errorMessage = '';
  Map<String, dynamic>? _alertData;
  Map<String, dynamic>? _blindUserData;
  
  // ignore: unused_field
  GoogleMapController? _mapController;
  LatLng? _blindUserLocation;
  Set<Marker> _markers = {};
  
  @override
  void initState() {
    super.initState();
    _loadEmergencyData();
    
    // Play vibration pattern for emergency
    HapticFeedback.vibrate();
    Future.delayed(const Duration(milliseconds: 500), () => HapticFeedback.vibrate());
    Future.delayed(const Duration(milliseconds: 1000), () => HapticFeedback.vibrate());
  }
  
  // Load emergency alert data
  Future<void> _loadEmergencyData() async {
    try {
      setState(() {
        _isLoading = true;
        _isError = false;
      });
      
      // Get alert data
      final alertDoc = await _firestore
          .collection('emergencyAlerts')
          .doc(widget.emergencyAlertId)
          .get();
      
      if (!alertDoc.exists) {
        setState(() {
          _isLoading = false;
          _isError = true;
          _errorMessage = 'emergency_alert_not_found'.tr();
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('emergency_alert_not_found'.tr()))
        );
        return;
      }
      
      _alertData = alertDoc.data();
      
      // Get blind user data
      final userId = _alertData?['userId'];
      if (userId != null) {
        final userDoc = await _firestore.collection('users').doc(userId).get();
        if (userDoc.exists) {
          _blindUserData = userDoc.data();
        }
      }
      
      // Get location from alert
      final location = _alertData?['location'] as GeoPoint?;
      if (location != null) {
        _blindUserLocation = LatLng(location.latitude, location.longitude);
        
        // Create marker
        _markers = {
          Marker(
            markerId: const MarkerId('blindUserLocation'),
            position: _blindUserLocation!,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: InfoWindow(
              title: '${'emergency'.tr()}: ${_blindUserData?['displayName'] ?? 'blind_user'.tr()}',
              snippet: 'tap_for_directions'.tr(),
            ),
            onTap: () => _blindUserLocation != null ? _openMapsWithDirections(_blindUserLocation!) : null,
          ),
        };
      }
      
      // Mark as viewed by helper
      await alertDoc.reference.update({
        'viewedByHelper': true,
        'viewedAt': FieldValue.serverTimestamp(),
      });
      
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading emergency data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isError = true;
          _errorMessage = 'failed_to_load_emergency_data'.tr();
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${'error_loading_emergency_data'.tr()}: ${e.toString()}'))
        );
      }
    }
  }
  
  // Open maps app with directions
  Future<void> _openMapsWithDirections(LatLng destination) async {
    try {
      // Get current location
      await _locationService.startTracking();
      final currentLocation = _locationService.currentLocation;
      
      if (currentLocation == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('failed_to_get_location'.tr()))
          );
        }
        return;
      }
      
      // Create maps URL
      final url = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&origin=${currentLocation.latitude},${currentLocation.longitude}&destination=${destination.latitude},${destination.longitude}&travelmode=driving'
      );
      
      // Launch URL with proper mode
      await launchUrl(
        url, 
        mode: LaunchMode.externalApplication
      );
    } catch (e) {
      debugPrint('Error opening maps: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${'could_not_open_maps'.tr()}: ${e.toString()}'))
        );
      }
    }
  }
  
  
  // Mark emergency as resolved
  Future<void> _markAsResolved() async {
    try {
      await _firestore
          .collection('emergencyAlerts')
          .doc(widget.emergencyAlertId)
          .update({
        'status': 'resolved',
        'resolvedAt': FieldValue.serverTimestamp(),
        'resolvedBy': Provider.of<AuthProvider>(context, listen: false).currentUserId,
      });
      
      // Also update blind user's emergency status
      final userId = _alertData?['userId'];
      if (userId != null) {
        await _firestore.collection('users').doc(userId).update({
          'emergencyStatus.isActive': false,
          'emergencyStatus.resolvedAt': FieldValue.serverTimestamp(),
        });
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('emergency_marked_resolved'.tr()),
            backgroundColor: Colors.green,
          )
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Error marking emergency as resolved: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${'error'.tr()}: ${e.toString()}'))
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('emergency_alert'.tr()),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.red))
          : _isError
              ? _buildErrorView()
              : _buildEmergencyView(),
    );
  }
  
  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _errorMessage.isNotEmpty ? _errorMessage : 'failed_to_load_emergency_data'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadEmergencyData,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: Text('try_again'.tr()),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildEmergencyView() {
    return Column(
      children: [
        // Emergency header
        Container(
          width: double.infinity,
          color: Colors.red.shade100,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'emergency_alert_exclamation'.tr(),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${'from'.tr()}: ${_blindUserData?['displayName'] ?? 'blind_user'.tr()}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${'time'.tr()}: ${_formatTimestamp(_alertData?['timestamp'])}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        
        // Map showing location
        if (_blindUserLocation != null)
          Expanded(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _blindUserLocation!,
                zoom: 15,
              ),
              markers: _markers,
              mapType: MapType.normal,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              onMapCreated: (controller) {
                _mapController = controller;
              },
            ),
          )
        else
          Expanded(
            child: Center(
              child: Text(
                'no_location_data'.tr(),
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ),
          
        // Action buttons
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
            
              const SizedBox(height: 12),
              
              // Navigate to location button
              if (_blindUserLocation != null)
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: () => _openMapsWithDirections(_blindUserLocation!),
                    icon: const Icon(Icons.directions, color: Colors.white),
                    label: Text(
                      'navigate_to_location'.tr(),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              
              // Mark as resolved button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton.icon(
                  onPressed: _markAsResolved,
                  icon: const Icon(Icons.check_circle, color: Colors.green),
                  label: Text(
                    'mark_as_resolved'.tr(),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.green, width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  // Format timestamp
  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) {
      return 'just_now'.tr();
    }
    
    if (timestamp is Timestamp) {
      final date = timestamp.toDate();
      return DateFormat('MMM d, yyyy - h:mm a').format(date);
    }
    
    return 'just_now'.tr();
  }
} 