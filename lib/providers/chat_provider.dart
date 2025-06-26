import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../services/notification_service.dart';

class ChatProvider with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isLoading = false;
  String? _error;

  bool get isLoading => _isLoading;
  String? get error => _error;

  Stream<List<Map<String, dynamic>>> getChatMessagesStream(String chatRoomId) {
    return _firestore
        .collection('chats')
        .doc(chatRoomId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              return {
                'id': doc.id,
                ...doc.data(),
                'timestamp': doc['timestamp'] is Timestamp
                    ? (doc['timestamp'] as Timestamp).toDate()
                    : DateTime.now(),
              };
            }).toList());
  }

  Future<void> sendTextMessage({
    required String chatRoomId,
    required String text,
    required String senderId,
    bool isPending = false,
  }) async {
    try {
      // Send the message through the regular channel
    await _sendMessage(
      chatRoomId: chatRoomId,
      senderId: senderId,
      content: {'text': text},
      type: 'text',
        notificationTitle: 'New Message',
      notificationBody: text,
      isPending: isPending,
    );
    } catch (e) {
      debugPrint('❌ Error sending text message: $e');
      rethrow;
    }
  }

  Future<void> sendImageMessage({
    required String chatRoomId,
    required String senderId,
    required String imageUrl,
  }) async {
    await _sendMessage(
      chatRoomId: chatRoomId,
      senderId: senderId,
      content: {'imageUrl': imageUrl},
      type: 'image',
      notificationTitle: 'New Image Message',
      notificationBody: 'A blind user sent you an image.',
    );
  }

  Future<void> sendAudioMessage({
    required String chatRoomId,
    required String senderId,
    required String audioUrl,
    int? durationMs,
  }) async {
    final Map<String, dynamic> content = {
      'audioUrl': audioUrl,
      if (durationMs != null) 'durationMs': durationMs,
    };
    await _sendMessage(
      chatRoomId: chatRoomId,
      senderId: senderId,
      content: content,
      type: 'audio',
      notificationTitle: 'New Voice Message',
      notificationBody: 'A blind user sent you a voice message.',
    );
  }

  Future<void> sendLocationMessage({
    required String chatRoomId,
    required String senderId,
    required double latitude,
    required double longitude,
    String? address,
    bool isPending = false,
  }) async {
    final content = {
      'latitude': latitude,
      'longitude': longitude,
      if (address != null) 'address': address,
    };
    await _sendMessage(
      chatRoomId: chatRoomId,
      senderId: senderId,
      content: content,
      type: 'location',
      notificationTitle: 'Location Shared',
      notificationBody: 'A location was shared with you.',
      isPending: isPending,
    );
  }

  Future<void> _sendMessage({
    required String chatRoomId,
    required String senderId,
    required Map<String, dynamic> content,
    required String type,
    required String notificationTitle,
    required String notificationBody,
    bool isPending = false,
  }) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      debugPrint('🔍 NOTIFICATION DEBUG: Starting _sendMessage method');
      debugPrint('🔍 NOTIFICATION DEBUG: Chat Room ID: $chatRoomId, Sender ID: $senderId');

      final messageId = const Uuid().v4();
      final timestamp = FieldValue.serverTimestamp();

      // Extract participants and verify we have the correct recipient
      List<String> participantIds = _extractParticipants(chatRoomId, senderId);
      debugPrint('🔍 NOTIFICATION DEBUG: Extracted participants: $participantIds');
      
      Map<String, bool> participantsMap = {
        for (var id in participantIds) id: true
      };

      await _firestore.collection('chats').doc(chatRoomId).set({
        'lastMessage': type == 'text'
            ? content['text']
            : type == 'image'
                ? 'Image shared'
                : type == 'audio'
                    ? 'Voice message'
                    : type == 'location'
                        ? 'Location shared'
                        : 'New message',
        'lastMessageTime': timestamp,
        'lastSenderId': senderId,
        'participants': participantsMap,
        'lastUpdated': timestamp,
      }, SetOptions(merge: true));

      await _firestore
          .collection('chats')
          .doc(chatRoomId)
          .collection('messages')
          .doc(messageId)
          .set({
        'id': messageId,
        'senderId': senderId,
        'type': type,
        'timestamp': timestamp,
        'isDelivered': false,
        'isRead': false,
        'isPending': isPending,
        ...content,
      });

      debugPrint('🔍 NOTIFICATION DEBUG: Message saved to Firestore successfully');
      
      // Find recipient(s) and send notification
      if (participantIds.length < 2) {
        debugPrint('⚠️ Not enough participants to send notification: $participantIds');
        _isLoading = false;
        notifyListeners();
        return;
      }
      
      // The recipient is the user who is NOT the sender
      final recipientId = participantIds.firstWhere((id) => id != senderId);
      debugPrint('📱 NOTIFICATION DEBUG: Sending notification to recipient ID: $recipientId');
      
      // Get sender data for notification
      final senderDoc = await _firestore.collection('users').doc(senderId).get();
      final senderData = senderDoc.data();
      final senderName = senderData?['displayName'] ?? 'User';
      final isBlindUser = senderData?['isBlindUser'] ?? false;
      
      debugPrint('🔍 NOTIFICATION DEBUG: Sender is${isBlindUser ? '' : ' not'} a blind user');
      
      // Get recipient data to find their FCM tokens
      final recipientDoc = await _firestore.collection('users').doc(recipientId).get();
      final recipientData = recipientDoc.data();
      
      if (recipientData == null) {
        debugPrint('❌ NOTIFICATION DEBUG: Recipient data not found for ID: $recipientId');
        _isLoading = false;
        notifyListeners();
        return;
      }
      
      // Check if recipient has FCM token
      final recipientToken = recipientData['fcmToken'] as String?;
      final hasTokenArray = recipientData['fcmTokens'] is List && (recipientData['fcmTokens'] as List).isNotEmpty;
      
      debugPrint('🔍 NOTIFICATION DEBUG: Recipient has FCM token: ${recipientToken != null}');
      debugPrint('🔍 NOTIFICATION DEBUG: Recipient has FCM token array: $hasTokenArray');
      
      // Customize notification based on sender type
      final customTitle = isBlindUser ? 
          'New Message from : $senderName' : 
          'New Message from : $senderName';
      
      // Prepare notification data with additional info
      final notificationData = {
            'chatRoomId': chatRoomId,
            'senderId': senderId,
        'recipientId': recipientId,
        'messageId': messageId,
            'type': '${type}_message',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'senderName': senderName,
        'isBlindUser': isBlindUser,
        'priority': 'high',
        'click_action': 'FLUTTER_NOTIFICATION_CLICK',
            ...content,
      };
      
      // Store notification in Firestore for reliable delivery
      try {
        await _firestore.collection('notifications').add({
          'recipientId': recipientId, // IMPORTANT: This is the recipient, not the sender
          'title': customTitle,
          'body': notificationBody,
          'data': notificationData,
          'channelId': 'messages_channel',
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
        });
        debugPrint('✅ NOTIFICATION DEBUG: Notification stored in Firestore successfully');
      } catch (e) {
        debugPrint('❌ NOTIFICATION DEBUG: Failed to store notification in Firestore: $e');
      }
      
      // Try to send via FCM if tokens are available
      bool notificationSent = false;
      
      // Try single token first
      if (recipientToken != null && recipientToken.isNotEmpty) {
        try {
          debugPrint('🔍 NOTIFICATION DEBUG: Attempting to send FCM with token: ${recipientToken.substring(0, 10)}...');
          await NotificationService().sendPushNotification(
            recipientToken: recipientToken,
            title: customTitle,
            body: notificationBody,
            channelId: 'messages_channel',
            data: notificationData,
          );
          notificationSent = true;
          debugPrint('✅ NOTIFICATION DEBUG: FCM sent successfully with recipient token');
        } catch (e) {
          debugPrint('❌ NOTIFICATION DEBUG: Error sending FCM with recipient token: $e');
        }
      } else {
        debugPrint('⚠️ NOTIFICATION DEBUG: No valid recipient token found');
      }
      
      // If single token didn't work, try token array
      if (!notificationSent && recipientData['fcmTokens'] is List) {
        final tokenList = List<String>.from(recipientData['fcmTokens']);
        if (tokenList.isEmpty) {
          debugPrint('⚠️ NOTIFICATION DEBUG: FCM tokens array is empty');
        }
        
        for (final token in tokenList) {
          if (token.isNotEmpty) {
            try {
              debugPrint('🔍 NOTIFICATION DEBUG: Attempting to send FCM with array token: ${token.substring(0, 10)}...');
              await NotificationService().sendPushNotification(
                recipientToken: token,
                title: customTitle,
                body: notificationBody,
                channelId: 'messages_channel',
                data: notificationData,
              );
              notificationSent = true;
              debugPrint('✅ NOTIFICATION DEBUG: FCM sent successfully with token from array');
              break; // Stop after first successful send
            } catch (e) {
              debugPrint('❌ NOTIFICATION DEBUG: Error sending FCM with token from array: $e');
            }
          } else {
            debugPrint('⚠️ NOTIFICATION DEBUG: Empty token in FCM tokens array');
          }
        }
      }
      
      if (!notificationSent) {
        debugPrint('⚠️ NOTIFICATION DEBUG: Failed to send push notification via FCM, but notification stored in Firestore');
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      debugPrint('❌ NOTIFICATION DEBUG: Unexpected error in _sendMessage: $e');
      _isLoading = false;
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> addSystemMessage({
    required String chatRoomId,
    required String text,
  }) async {
    final messageId = const Uuid().v4();
    final timestamp = FieldValue.serverTimestamp();
    await _firestore.collection('chats').doc(chatRoomId).collection('messages').doc(messageId).set({
      'id': messageId,
      'senderId': 'system',
      'text': text,
      'type': 'text',
      'timestamp': timestamp,
    });
    await _firestore.collection('chats').doc(chatRoomId).update({
      'lastUpdated': timestamp,
    });
  }

  Future<String> createChatRoom(List<String> userIds) async {
    try {
      userIds.sort();
      final chatRoomId = 'chat_${userIds.join('_')}';
      await _firestore.collection('chats').doc(chatRoomId).set({
        'participants': {for (var id in userIds) id: true},
        'createdAt': FieldValue.serverTimestamp(),
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return chatRoomId;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> markMessagesAsReadAndDelivered({
    required String chatRoomId,
    required String currentUserId,
    required String otherUserId,
  }) async {
    try {
      final messagesQuery = await _firestore
          .collection('chats')
          .doc(chatRoomId)
          .collection('messages')
          .where('senderId', isEqualTo: otherUserId)
          .where('isRead', isEqualTo: false)
          .get();

      if (messagesQuery.docs.isEmpty) return;

      final batch = _firestore.batch();
      for (final doc in messagesQuery.docs) {
        batch.update(doc.reference, {
          'isDelivered': true,
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    } catch (e) {
      debugPrint('❌ Error marking messages as read: $e');
    }
  }

  Future<bool> clearChat(String chatRoomId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final messagesQuery = await _firestore
          .collection('chats')
          .doc(chatRoomId)
          .collection('messages')
          .get();

      if (messagesQuery.docs.isEmpty) {
        _isLoading = false;
        notifyListeners();
        return true;
      }

      const int batchSize = 400;
      for (int i = 0; i < messagesQuery.docs.length; i += batchSize) {
        final batch = _firestore.batch();
        final end = (i + batchSize < messagesQuery.docs.length)
            ? i + batchSize
            : messagesQuery.docs.length;
        for (int j = i; j < end; j++) {
          batch.delete(messagesQuery.docs[j].reference);
        }
        await batch.commit();
      }

      await addSystemMessage(
        chatRoomId: chatRoomId,
        text: 'Chat history cleared',
      );

      await _firestore.collection('chats').doc(chatRoomId).update({
        'lastMessage': 'Chat history cleared',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastSenderId': 'system',
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  List<String> _extractParticipants(String chatRoomId, String senderId) {
    if (chatRoomId.startsWith('chat_')) {
      return chatRoomId.substring(5).split('_');
    } else {
      return [senderId];
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
