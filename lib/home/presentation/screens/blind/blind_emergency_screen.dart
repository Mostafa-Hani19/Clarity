import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../../services/location_service.dart';
import '../../../../../providers/auth_provider.dart';
import '../../../../../services/notification_service.dart';

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  final LocationService _locationService = LocationService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = false;
  String _emergencyNumber = "911"; 
  
  @override
  void initState() {
    super.initState();
    _loadEmergencyNumber();
  }
  
  // Load saved emergency number
  Future<void> _loadEmergencyNumber() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _emergencyNumber = prefs.getString('emergency_number') ?? "911";
      });
    } catch (e) {
      debugPrint('Error loading emergency number: $e');
    }
  }
  
  // Save emergency number
  Future<void> _saveEmergencyNumber(String number) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('emergency_number', number);
    } catch (e) {
      debugPrint('Error saving emergency number: $e');
    }
  }
  
  // Show dialog to update emergency number
  void _showUpdateNumberDialog() {
    final TextEditingController controller = TextEditingController(text: _emergencyNumber);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('update_emergency_number'.tr()),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: 'emergency_contact_number'.tr(),
            hintText: 'enter_phone_number'.tr(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () async {
              await _saveEmergencyNumber(controller.text);
              setState(() {
                _emergencyNumber = controller.text;
              });
              if (mounted) Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('emergency_number_updated'.tr()))
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('save'.tr()),
          ),
        ],
      ),
    );
  }
  
  // Send emergency alert with location
  Future<void> _sendEmergencyAlert() async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Get current user
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.currentUserId;
      final isBlindUser = authProvider.isBlindUser;
      final linkedUserId = authProvider.linkedUserId;
      
      // If no linked user, show error
      if (linkedUserId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('no_helper_linked'.tr()))
        );
        setState(() {
          _isLoading = false;
        });
        return;
      }
      
      // Get current location
      await _locationService.startTracking();
      final location = _locationService.currentLocation;
      
      if (location == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('failed_to_get_location'.tr()))
        );
        setState(() {
          _isLoading = false;
        });
        return;
      }
      
      // Create emergency alert document in Firestore
      final docRef = await _firestore.collection('emergencyAlerts').add({
        'userId': userId,
        'linkedUserId': linkedUserId,
        'isBlindUser': isBlindUser,
        'location': GeoPoint(location.latitude, location.longitude),
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'active',
      });
      
      // Also update user document with emergency status
      if (userId != null) {
        await _firestore.collection('users').doc(userId).update({
          'emergencyStatus': {
            'isActive': true,
            'location': GeoPoint(location.latitude, location.longitude),
            'timestamp': FieldValue.serverTimestamp(),
            'alertId': docRef.id
          }
        });
      }

      // --- FCM Notification Logic ---
      // 1. Get the helper's FCM token
      String? helperFcmToken;
      try {
        final helperDoc = await _firestore.collection('users').doc(linkedUserId).get();
        if (helperDoc.exists && helperDoc.data() != null) {
          helperFcmToken = helperDoc.data()!['fcmToken'] as String?;
          debugPrint('Helper FCM Token: $helperFcmToken');
        }
      } catch (e) {
        debugPrint('Error fetching helper FCM token: $e');
      }

      // 2. Send FCM notification if token is available
      if (helperFcmToken != null && helperFcmToken.isNotEmpty) {
        await NotificationService().sendPushNotification(
          recipientToken: helperFcmToken,
          title: 'emergency_alert_exclamation'.tr(),
          body: 'blind_user_needs_assistance'.tr(),
          channelId: 'emergency_alerts',
          sound: 'emergency_alert',
          fullScreenIntent: true,
          data: {
            'emergencyAlert': 'true',
            'emergencyAlertId': docRef.id,
            'userId': userId,
            'locationLatitude': location.latitude,
            'locationLongitude': location.longitude,
          },
        );
      }
      // --- End FCM Notification Logic ---
      
      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('emergency_alert_sent'.tr()),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          )
        );
      }
      
      // Add haptic feedback
      HapticFeedback.heavyImpact();
      
    } catch (e) {
      debugPrint('Error sending emergency alert: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${'failed_to_send_alert'.tr()}: ${e.toString()}'))
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  // Make emergency call
  Future<void> _callEmergencyNumber() async {
    final Uri phoneUri = Uri(scheme: 'tel', path: _emergencyNumber);
    
    try {
      // For Android, we need to use launchUrl with the correct mode
      await launchUrl(phoneUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Error launching phone call: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${'could_not_make_call'.tr()}: ${e.toString()}'))
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.red.shade50,
      appBar: AppBar(
        title: Text('emergency'.tr(), style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _showUpdateNumberDialog,
            tooltip: 'edit_emergency_number'.tr(),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Warning icon
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  size: 80,
                  color: Colors.red.shade500,
                ),
              ),
              const SizedBox(height: 24),
              
              // Title
              Text(
                'emergency_contact'.tr(),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 16),
              
              // Description
              Text(
                'emergency_button_description'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 48),
              
              // Emergency alert button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _sendEmergencyAlert,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                    elevation: 5,
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          'send_emergency_alert'.tr(),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 24),
              
              // Call emergency services button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton.icon(
                  onPressed: _callEmergencyNumber,
                  icon: const Icon(Icons.call, color: Colors.red),
                  label: Text(
                    '${'call_emergency_services'.tr()} ($_emergencyNumber)',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red, width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 