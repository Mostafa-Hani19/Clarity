import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../routes/app_router.dart';
import 'dart:async';
import '../presentation/screens/video_call_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/notification_service.dart';

class VideoCallService {
  static final VideoCallService _instance = VideoCallService._internal();

  factory VideoCallService() => _instance;

  VideoCallService._internal();

  final CollectionReference _callsCollection =
      FirebaseFirestore.instance.collection('calls');
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Create a call room and initiate a call
  Future<void> initiateCall(
    BuildContext context,
    String currentUserID,
    String receiverID,
    String receiverName,
  ) async {
    try {
      final String callID = const Uuid().v4();
      final String callerName =
          FirebaseAuth.instance.currentUser?.displayName ?? 'User';

      debugPrint('📞 Initiating call from $currentUserID to $receiverID with call ID: $callID');
      debugPrint('📞 Caller name: $callerName, Receiver name: $receiverName');
      
      // Verify the receiver exists in Firestore
      bool receiverExists = false;
      
      try {
        // Check in helpers collection
        final helperDoc = await _firestore.collection('helpers').doc(receiverID).get();
        if (helperDoc.exists) {
          receiverExists = true;
          debugPrint('📞 Receiver found in helpers collection');
        } else {
          // Check in users collection
          final userDoc = await _firestore.collection('users').doc(receiverID).get();
          if (userDoc.exists) {
            receiverExists = true;
            debugPrint('📞 Receiver found in users collection');
          }
        }
      } catch (e) {
        debugPrint('⚠️ Error verifying receiver: $e');
        // Continue anyway as this is just a verification step
      }
      
      if (!receiverExists) {
        debugPrint('⚠️ Receiver ID not found in Firestore, but will try to proceed with call anyway');
      }
      
      // Create call document in Firestore
      await _callsCollection.doc(callID).set({
        'callerId': currentUserID,
        'callerName': callerName,
        'receiverId': receiverID,
        'receiverName': receiverName, 
        'status':'ringing', 
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'endedAt': null,
        'security': {
          'authorized': [currentUserID, receiverID],
        }
      });
      debugPrint('📞 Call document created/updated in Firestore: $callID with receiver: $receiverID, status: ringing');

      // --- FCM Notification Logic for Video Call ---
      String? receiverFcmToken;
      
      // Check if the receiver is a helper or a blind user
      try {
        // First check in the users collection (for blind users)
        var receiverDoc = await _firestore.collection('users').doc(receiverID).get();
        
        if (receiverDoc.exists && receiverDoc.data() != null) {
          final userData = receiverDoc.data()!;
          receiverFcmToken = userData['fcmToken'] as String?;
          debugPrint('📱 Found receiver as blind user, FCM Token: ${receiverFcmToken ?? "NULL"}');
          
          // Check if we have the token in a different field
          if (receiverFcmToken == null) {
            receiverFcmToken = userData['notificationToken'] as String?;
            debugPrint('📱 Trying alternative token field for blind user: ${receiverFcmToken ?? "NULL"}');
          }
        } else {
          // If not found in users, check in helpers collection
          receiverDoc = await _firestore.collection('helpers').doc(receiverID).get();
          if (receiverDoc.exists && receiverDoc.data() != null) {
            final helperData = receiverDoc.data()!;
            receiverFcmToken = helperData['fcmToken'] as String?;
            debugPrint('📱 Found receiver as helper, FCM Token: ${receiverFcmToken ?? "NULL"}');
            
            // Check if we have the token in a different field
            if (receiverFcmToken == null) {
              receiverFcmToken = helperData['notificationToken'] as String?;
              debugPrint('📱 Trying alternative token field for helper: ${receiverFcmToken ?? "NULL"}');
            }
          }
        }
        
        if (receiverFcmToken == null) {
          debugPrint('⚠️ Could not find FCM token for receiver: $receiverID');
          debugPrint('⚠️ Will try to proceed with call anyway, but notification may not be delivered');
        }
      } catch (e) {
        debugPrint('❌ Error fetching receiver FCM token: $e');
      }

      if (receiverFcmToken != null && receiverFcmToken.isNotEmpty) {
        await NotificationService().sendPushNotification(
          recipientToken: receiverFcmToken,
          title: 'Incoming Video Call',
          body: '$callerName is calling you for assistance.',
          channelId: 'video_call_channel',
          sound: 'incoming_call',
          data: {
            'type': 'video_call',
            'callID': callID,
            'callerID': currentUserID,
            'callerName': callerName,
          },
        );
        debugPrint('📱 Sent push notification to recipient with token: $receiverFcmToken');
      } else {
        debugPrint('⚠️ No FCM token available for receiver, notification not sent');
      }
      // --- End FCM Notification Logic ---

      // Navigate to call screen (outgoing)
      _navigateToCallScreen(context, callID, receiverID, receiverName, true);
    } catch (e) {
      _handleError(context, 'Failed to start video call', e);
    }
  }

  /// For the incoming user, join the call when accepted
  Future<void> joinCall(
    BuildContext context,
    String callID,
    String partnerID,
    String partnerName,
  ) async {
    try {
      // Update call status in Firestore
      await _callsCollection.doc(callID).update({
        'status': 'accepted',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _navigateToCallScreen(context, callID, partnerID, partnerName, false);
    } catch (e) {
      _handleError(context, 'Failed to join video call', e);
    }
  }

  /// End the call
  Future<void> endCall(String callID) async {
    try {
      await _callsCollection.doc(callID).update({
        'status': 'ended',
        'isActive': false,
        'endedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // اختياري: احذف المستند بعد فترة قصيرة
      Future.delayed(const Duration(seconds: 5), () async {
        await _callsCollection.doc(callID).delete();
      });
    } catch (e) {
      debugPrint('❌ Error ending call: $e');
    }
  }

  /// Main navigation logic to call screen
  void _navigateToCallScreen(
    BuildContext context,
    String callID,
    String targetUserID,
    String targetUserName,
    bool isOutgoing,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;

      try {
        AppRouter.navigateToVideoCall(
          context,
          callID: callID,
          targetUserID: targetUserID,
          targetUserName: targetUserName,
          isOutgoing: isOutgoing,
        );
      } catch (e) {
        try {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => VideoCallScreen(
                callID: callID,
                targetUserID: targetUserID,
                targetUserName: targetUserName,
                isOutgoing: isOutgoing,
              ),
            ),
          );
        } catch (e) {
          debugPrint('❌ Error with navigation: $e');
        }
      }
    });
  }

  /// Show a waiting screen while waiting for call acceptance (for outgoing calls)
  void showWaitingScreen(
      BuildContext context, String callID, String targetUserName) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            title: const Text('Calling...'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Waiting for $targetUserName to accept the call'),
                const SizedBox(height: 20),
                const CircularProgressIndicator(),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  endActiveCall(callID);
                },
                child: const Text('Cancel Call'),
              ),
            ],
          ),
        ),
      );
    });
  }

  /// Functions for accepting/rejecting
  Future<void> acceptCall(String callID) async {
    await _callsCollection.doc(callID).update({
      'status': 'accepted',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> rejectCall(String callID) async {
    await _callsCollection.doc(callID).update({
      'status': 'rejected',
      'isActive': false,
      'endedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    // اختياري: حذف المستند
    Future.delayed(const Duration(seconds: 5), () async {
      await _callsCollection.doc(callID).delete();
    });
  }

  Future<void> endActiveCall(String callID) async {
    await endCall(callID);
  }

  /// Stream for incoming calls for user (for notifications)
  Stream<Map<String, dynamic>?> getIncomingCallsStream(String userId) {
    debugPrint('👂 Listening for incoming calls for user: $userId');
    
    // Log initial debug information
    _callsCollection
        .where('receiverId', isEqualTo: userId)
        .where('isActive', isEqualTo: true)
        .where('status', isEqualTo: 'ringing')
        .get()
        .then((snapshot) {
          debugPrint('📞 Initial call check found ${snapshot.docs.length} ringing calls for user: $userId');
          for (var doc in snapshot.docs) {
            debugPrint('📞 Found call: ${doc.id}');
          }
        });
    
    return _callsCollection
        .where('receiverId', isEqualTo: userId)
        .where('isActive', isEqualTo: true)
        .where('status', isEqualTo: 'ringing')
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        final callDoc = snapshot.docs.first;
        final callData = callDoc.data() as Map<String, dynamic>;
        debugPrint('🔔 Incoming call detected! Call ID: ${callDoc.id}, Caller: ${callData['callerName']}');
        return {
          'callId': callDoc.id,
          'callerId': callData['callerId'],
          ...callData,
        };
      }
      // Don't log "no calls found" on every empty snapshot as it's noisy
      return null;
    });
  }

  /// Handle errors
  void _handleError(BuildContext context, String message, dynamic error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$message: ${error.toString()}'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
  }
}
