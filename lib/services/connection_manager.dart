import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import 'connectivity_service.dart';
import 'package:uuid/uuid.dart';

class ConnectionManager with ChangeNotifier {
  static final ConnectionManager _instance = ConnectionManager._internal();
  factory ConnectionManager() => _instance;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  AuthProvider? _authProvider;
  ChatProvider? _chatProvider;
  ConnectivityService? _connectivityService;

  String? _currentUserId;
  String? _connectedUserId;
  bool _isConnected = false;
  String? _chatRoomId;
  bool _isInitialized = false;
  
  // Shared Preferences keys
  static const String _connectedUserKey = "connected_user_id";
  static const String _chatRoomIdKey = "chat_room_id";
  static const String _blindUserCodeKey = "blind_user_code";

  ConnectionManager._internal();

  // Initialize with required providers
  void initialize({
    required AuthProvider authProvider,
    required ChatProvider chatProvider,
    required ConnectivityService connectivityService,
  }) {
    if (_isInitialized) return;
    
    _authProvider = authProvider;
    _chatProvider = chatProvider;
    _connectivityService = connectivityService;
    
    // Listen for connectivity changes
    _connectivityService!.connectivityStream.listen((status) {
      if (status != ConnectivityResult.none && _chatRoomId != null) {
        _syncPendingMessages();
      }
    });
    
    _isInitialized = true;
    
    // Load persisted connection first, then check Firestore
    _loadPersistedConnection().then((_) {
      checkConnectionStatus().then((_) {
        // If no connection found, create a temporary chat for blind user
        if (!_isConnected && _authProvider != null && _authProvider!.currentUserId != null) {
          createTemporaryChat();
        }
      });
    });
  }
  
  // Load persisted connection from SharedPreferences
  Future<void> _loadPersistedConnection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _connectedUserId = prefs.getString(_connectedUserKey);
      _chatRoomId = prefs.getString(_chatRoomIdKey);
      
      if (_connectedUserId != null && _chatRoomId != null) {
        debugPrint('✅ ConnectionManager - Loaded persisted connection: $_connectedUserId');
        debugPrint('✅ ConnectionManager - Loaded persisted chat room: $_chatRoomId');
        _isConnected = true;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('❌ ConnectionManager - Error loading persisted connection: $e');
    }
  }
  
  // Save connection to SharedPreferences for persistence
  Future<void> _saveConnectionToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_connectedUserId != null) {
        await prefs.setString(_connectedUserKey, _connectedUserId!);
      }
      if (_chatRoomId != null) {
        await prefs.setString(_chatRoomIdKey, _chatRoomId!);
      }
      debugPrint('✅ ConnectionManager - Saved connection to SharedPreferences');
    } catch (e) {
      debugPrint('❌ ConnectionManager - Error saving connection to SharedPreferences: $e');
    }
  }
  
  // Connect using blind person's code
  Future<bool> connectUsingBlindCode(String blindCode) async {
    try {
      debugPrint('🔍 ConnectionManager - Connecting using blind code: $blindCode');
      
      // Find the blind user with this code
      final querySnapshot = await _firestore
          .collection('users')
          .where('userCode', isEqualTo: blindCode)
          .where('isBlindUser', isEqualTo: true)
          .limit(1)
          .get();
      
      if (querySnapshot.docs.isEmpty) {
        debugPrint('❌ ConnectionManager - No blind user found with code: $blindCode');
        return false;
      }
      
      final blindUserDoc = querySnapshot.docs.first;
      final blindUserId = blindUserDoc.id;
      
      // Connect to this user
      await connectToUser(blindUserId);
      
      // Save the blind code
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_blindUserCodeKey, blindCode);
      
      debugPrint('✅ ConnectionManager - Connected to blind user: $blindUserId using code: $blindCode');
      return true;
    } catch (e) {
      debugPrint('❌ ConnectionManager - Error connecting with blind code: $e');
      return false;
    }
  }

  bool get isConnected => _isConnected;
  String? get connectedUserId => _connectedUserId;
  String? get chatRoomId => _chatRoomId;
  bool get isOnline => _connectivityService?.isOnline ?? false;
  
  // Get the saved blind user code if any
  Future<String?> getSavedBlindCode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_blindUserCodeKey);
    } catch (e) {
      debugPrint('❌ ConnectionManager - Error getting saved blind code: $e');
      return null;
    }
  }

  Future<void> connectToUser(String userId) async {
    if (_authProvider == null) throw Exception('ConnectionManager not initialized');
    
    _currentUserId = _authProvider!.currentUserId;
    if (_currentUserId == null) {
      throw Exception('User not logged in');
    }

    // Check if we are transferring from a temporary chat
    String? oldChatRoomId = _chatRoomId;
    bool wasTemporaryChat = oldChatRoomId != null && oldChatRoomId.startsWith('temp_chat_');

    _connectedUserId = userId;
    _isConnected = true;
    
    // Create chat room ID from both user IDs (sorted to ensure consistency)
    final List<String> userIds = [_currentUserId!, _connectedUserId!];
    userIds.sort();
    _chatRoomId = 'chat_${userIds.join('_')}';
    
    // Create the chat room if needed
    if (_chatProvider != null) {
      await _chatProvider!.createChatRoom(userIds);
    }
    
    // Transfer messages from temporary chat if applicable
    if (wasTemporaryChat) {
      await _transferMessagesFromTemporaryChat(oldChatRoomId);
    }
    
    // Save the connection to SharedPreferences for persistence
    await _saveConnectionToPrefs();
    
    notifyListeners();

    // Save connection to Firestore
    await _firestore.collection('connections').doc(_currentUserId).set({
      'connectedUserId': _connectedUserId,
      'chatRoomId': _chatRoomId,
      'timestamp': FieldValue.serverTimestamp(),
      'isPermanent': true, // Mark as permanent connection
      'lastSyncedAt': FieldValue.serverTimestamp(),
    });
    
    // Also update the other user's connection document for two-way connection
    await _firestore.collection('connections').doc(_connectedUserId).set({
      'connectedUserId': _currentUserId,
      'chatRoomId': _chatRoomId,
      'timestamp': FieldValue.serverTimestamp(),
      'isPermanent': true, // Mark as permanent connection
      'lastSyncedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> disconnect({bool logOut = false, bool userInitiated = false}) async {
    // Only allow disconnect if:
    // 1. It's a logout operation (app-controlled)
    // 2. The user explicitly requested it (userInitiated = true)
    if (!logOut && !userInitiated) {
      debugPrint('⚠️ ConnectionManager - Attempted to disconnect without user authorization - PREVENTED');
      return;
    }
    
    _isConnected = false;
    
    // If it's a logout, clear SharedPreferences too
    if (logOut) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_connectedUserKey);
      await prefs.remove(_chatRoomIdKey);
      await prefs.remove(_blindUserCodeKey);
      debugPrint('🧹 ConnectionManager - Cleared all connection data (logout)');
    }
    
    // Keep the connectedUserId for reconnection unless logging out
    if (logOut) {
      _connectedUserId = null;
    }
    _chatRoomId = null;
    notifyListeners();

    // Remove connection from Firestore only if logging out or user initiated
    if (_currentUserId != null && (logOut || userInitiated)) {
      await _firestore.collection('connections').doc(_currentUserId).delete();
      
      // Also clear the other side's connection if it exists and we're logging out or user initiated
      if (_connectedUserId != null) {
        await _firestore.collection('connections').doc(_connectedUserId).delete();
      }
    }
  }

  Future<void> checkConnectionStatus() async {
    if (_authProvider == null) {
      debugPrint('❌ ConnectionManager - AuthProvider is null');
      _tryUsingFirebaseAuth();
      return;
    }
    
    _currentUserId = _authProvider!.currentUserId;
    if (_currentUserId == null) {
      debugPrint('❌ ConnectionManager - Current user ID is null');
      _tryUsingFirebaseAuth();
      return;
    }

    debugPrint('🔍 ConnectionManager - Checking connection for user: $_currentUserId');
    
    try {
      // Get the linked user ID from AuthProvider for verification
      final String? authProviderLinkedUserId = _authProvider!.linkedUserId;
      debugPrint('🔍 ConnectionManager - AuthProvider linked user ID: $authProviderLinkedUserId');
      
      final connectionDoc = await _firestore.collection('connections').doc(_currentUserId).get();
      
      if (connectionDoc.exists) {
        final connectionData = connectionDoc.data();
        _connectedUserId = connectionData?['connectedUserId'];
        _chatRoomId = connectionData?['chatRoomId'];
        
        debugPrint('🔍 ConnectionManager - Found connection in Firestore: $_currentUserId connected to $_connectedUserId');
        
        // Check if there's a mismatch between AuthProvider and ConnectionManager
        if (authProviderLinkedUserId != null && 
            _connectedUserId != null && 
            authProviderLinkedUserId != _connectedUserId) {
          debugPrint('⚠️ ConnectionManager - Mismatch between AuthProvider linked user ($authProviderLinkedUserId) and ConnectionManager connected user ($_connectedUserId)');
          
          // Use the AuthProvider's linked user ID as the source of truth
          _connectedUserId = authProviderLinkedUserId;
          
          // Create chat room ID from both user IDs (sorted to ensure consistency)
          final List<String> userIds = [_currentUserId!, _connectedUserId!];
          userIds.sort();
          _chatRoomId = 'chat_${userIds.join('_')}';
          
          debugPrint('🔄 ConnectionManager - Updated connection to use AuthProvider linked user: $_connectedUserId');
          
          // Update the connection document in Firestore
          await _firestore.collection('connections').doc(_currentUserId).set({
            'connectedUserId': _connectedUserId,
            'chatRoomId': _chatRoomId,
            'timestamp': FieldValue.serverTimestamp(),
            'isPermanent': true,
            'lastSyncedAt': FieldValue.serverTimestamp(),
          });
          
          debugPrint('✅ ConnectionManager - Updated connection document in Firestore');
        } else {
          // Update lastSyncedAt to maintain the connection
          await _firestore.collection('connections').doc(_currentUserId).update({
            'lastSyncedAt': FieldValue.serverTimestamp(),
          });
        }
        
        _isConnected = true;
        debugPrint('✅ ConnectionManager - Using chat room: $_chatRoomId');
        
        // Save the connection to SharedPreferences for local persistence
        await _saveConnectionToPrefs();
        
        // Start monitoring read receipts
        if (_chatRoomId != null && _chatProvider != null) {
          _startReadReceiptMonitoring();
        }
      } else {
        // Try to load from SharedPreferences first before creating a temporary chat
        final prefs = await SharedPreferences.getInstance();
        final savedConnectedUserId = prefs.getString(_connectedUserKey);
        final savedChatRoomId = prefs.getString(_chatRoomIdKey);
        
        if (savedConnectedUserId != null && savedChatRoomId != null) {
          // We have a saved connection, restore it
          _connectedUserId = savedConnectedUserId;
          _chatRoomId = savedChatRoomId;
          _isConnected = true;
          
          debugPrint('🔄 ConnectionManager - Restored connection from local storage');
          
          // Re-establish connection in Firestore
          await _firestore.collection('connections').doc(_currentUserId).set({
            'connectedUserId': _connectedUserId,
            'chatRoomId': _chatRoomId,
            'timestamp': FieldValue.serverTimestamp(),
            'isPermanent': true,
            'lastSyncedAt': FieldValue.serverTimestamp(),
          });
          
          // Also update the other user's connection
          await _firestore.collection('connections').doc(_connectedUserId).set({
            'connectedUserId': _currentUserId,
            'chatRoomId': _chatRoomId,
            'timestamp': FieldValue.serverTimestamp(),
            'isPermanent': true,
            'lastSyncedAt': FieldValue.serverTimestamp(),
          });
        } else {
          debugPrint('ℹ️ ConnectionManager - No connection found for user: $_currentUserId');
          // Create temporary chat even if there's no connection
          createTemporaryChat();
          _isConnected = false;
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('❌ ConnectionManager - Error checking connection: $e');
      _isConnected = false;
      notifyListeners();
    }
  }

  // Try to get user ID directly from Firebase Auth if AuthProvider fails
  void _tryUsingFirebaseAuth() {
    try {
      final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
      if (firebaseUser != null) {
        _currentUserId = firebaseUser.uid;
        debugPrint('✅ ConnectionManager - Got user ID from Firebase Auth: $_currentUserId');
        
        // Try to continue with connection check
        _continueConnectionCheck();
      } else {
        debugPrint('❌ ConnectionManager - No user found in Firebase Auth either');
        _isConnected = false;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('❌ ConnectionManager - Error getting Firebase Auth user: $e');
      _isConnected = false;
      notifyListeners();
    }
  }
  
  // Continue connection check after getting user ID
  Future<void> _continueConnectionCheck() async {
    if (_currentUserId == null) return;
    
    try {
      // Try to get the linked user ID from AuthProvider if available
      String? authProviderLinkedUserId;
      if (_authProvider != null) {
        authProviderLinkedUserId = _authProvider!.linkedUserId;
        debugPrint('🔍 ConnectionManager - AuthProvider linked user ID (fallback): $authProviderLinkedUserId');
      }
      
      final connectionDoc = await _firestore.collection('connections').doc(_currentUserId).get();
      
      if (connectionDoc.exists) {
        final connectionData = connectionDoc.data();
        _connectedUserId = connectionData?['connectedUserId'];
        _chatRoomId = connectionData?['chatRoomId'];
        
        debugPrint('🔍 ConnectionManager - Found connection in fallback: $_currentUserId connected to $_connectedUserId');
        
        // Check if there's a mismatch between AuthProvider and ConnectionManager
        if (authProviderLinkedUserId != null && 
            _connectedUserId != null && 
            authProviderLinkedUserId != _connectedUserId) {
          debugPrint('⚠️ ConnectionManager - Mismatch in fallback between AuthProvider linked user and ConnectionManager connected user');
          
          // Use the AuthProvider's linked user ID as the source of truth
          _connectedUserId = authProviderLinkedUserId;
          
          // Create chat room ID from both user IDs (sorted to ensure consistency)
          final List<String> userIds = [_currentUserId!, _connectedUserId!];
          userIds.sort();
          _chatRoomId = 'chat_${userIds.join('_')}';
          
          debugPrint('🔄 ConnectionManager - Updated connection in fallback to use AuthProvider linked user: $_connectedUserId');
          
          // Update the connection document in Firestore
          await _firestore.collection('connections').doc(_currentUserId).set({
            'connectedUserId': _connectedUserId,
            'chatRoomId': _chatRoomId,
            'timestamp': FieldValue.serverTimestamp(),
            'isPermanent': true,
            'lastSyncedAt': FieldValue.serverTimestamp(),
          });
        } else {
          // Update lastSyncedAt to maintain the connection
          await _firestore.collection('connections').doc(_currentUserId).update({
            'lastSyncedAt': FieldValue.serverTimestamp(),
          });
        }
        
        _isConnected = true;
        
        // Save the connection to SharedPreferences for local persistence
        await _saveConnectionToPrefs();
        
        // Start monitoring read receipts
        if (_chatRoomId != null && _chatProvider != null) {
          _startReadReceiptMonitoring();
        }
      } else {
        // Try to load from SharedPreferences first before creating a temporary chat
        final prefs = await SharedPreferences.getInstance();
        final savedConnectedUserId = prefs.getString(_connectedUserKey);
        final savedChatRoomId = prefs.getString(_chatRoomIdKey);
        
        if (savedConnectedUserId != null && savedChatRoomId != null) {
          // We have a saved connection, restore it
          _connectedUserId = savedConnectedUserId;
          _chatRoomId = savedChatRoomId;
          _isConnected = true;
          
          debugPrint('🔄 ConnectionManager - Restored connection from local storage in fallback');
          
          // Re-establish connection in Firestore
          await _firestore.collection('connections').doc(_currentUserId).set({
            'connectedUserId': _connectedUserId,
            'chatRoomId': _chatRoomId,
            'timestamp': FieldValue.serverTimestamp(),
            'isPermanent': true,
            'lastSyncedAt': FieldValue.serverTimestamp(),
          });
          
          // Also update the other user's connection
          await _firestore.collection('connections').doc(_connectedUserId).set({
            'connectedUserId': _currentUserId,
            'chatRoomId': _chatRoomId,
            'timestamp': FieldValue.serverTimestamp(),
            'isPermanent': true,
            'lastSyncedAt': FieldValue.serverTimestamp(),
          });
        } else {
          debugPrint('ℹ️ ConnectionManager - No connection found for user: $_currentUserId');
          // Create temporary chat even if there's no connection
          createTemporaryChat();
          _isConnected = false;
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('❌ ConnectionManager - Error checking connection: $e');
      _isConnected = false;
      notifyListeners();
    }
  }
  
  // Send a message and handle offline queue
  Future<bool> sendMessage(String text) async {
    if (_chatRoomId == null || _currentUserId == null || _chatProvider == null) {
      return false;
    }
    
    try {
      // If online, send directly
      if (isOnline) {
        await _chatProvider!.sendTextMessage(
          chatRoomId: _chatRoomId!,
          text: text,
          senderId: _currentUserId!,
        );
        return true;
      } else {
        // If offline, queue in local storage and Firestore with pending flag
        await _chatProvider!.sendTextMessage(
          chatRoomId: _chatRoomId!,
          text: text,
          senderId: _currentUserId!,
          isPending: true,
        );
        return true;
      }
    } catch (e) {
      debugPrint('❌ Error sending message: $e');
      return false;
    }
  }
  
  // Send a location message
  Future<bool> sendLocationMessage({
    required double latitude,
    required double longitude,
    String? address,
  }) async {
    if (_chatRoomId == null || _currentUserId == null || _chatProvider == null) {
      return false;
    }

    try {
      await _chatProvider!.sendLocationMessage(
        chatRoomId: _chatRoomId!,
        senderId: _currentUserId!,
        latitude: latitude,
        longitude: longitude,
        address: address,
        isPending: !isOnline,
      );
      return true;
    } catch (e) {
      debugPrint('❌ Error sending location message: $e');
      return false;
    }
  }
  
  // Send an image message
  Future<bool> sendImageMessage(String imageUrl) async {
    if (_chatRoomId == null || _currentUserId == null || _chatProvider == null) {
      return false;
    }
    
    try {
      await _chatProvider!.sendImageMessage(
        chatRoomId: _chatRoomId!,
        senderId: _currentUserId!,
        imageUrl: imageUrl,
      );
      return true;
    } catch (e) {
      debugPrint('❌ Error sending image message: $e');
      return false;
    }
  }
  
  // Send an audio message
  Future<bool> sendAudioMessage(String audioUrl, {int? durationMs}) async {
    if (_chatRoomId == null || _currentUserId == null || _chatProvider == null) {
      return false;
    }
    
    try {
      await _chatProvider!.sendAudioMessage(
        chatRoomId: _chatRoomId!,
        senderId: _currentUserId!,
        audioUrl: audioUrl,
        durationMs: durationMs,
      );
      return true;
    } catch (e) {
      debugPrint('❌ Error sending audio message: $e');
      return false;
    }
  }
  
  // Sync pending messages when coming back online
  Future<void> _syncPendingMessages() async {
    if (_chatRoomId == null || _chatProvider == null) return;
    
    try {
      // Get all pending messages for this chat room
      final pendingMessagesQuery = await _firestore
          .collection('chats')
          .doc(_chatRoomId)
          .collection('messages')
          .where('isPending', isEqualTo: true)
          .where('senderId', isEqualTo: _currentUserId)
          .get();
          
      // Update each pending message
      for (final doc in pendingMessagesQuery.docs) {
        await doc.reference.update({
          'isPending': false,
          'isDelivered': true,
          'deliveredAt': FieldValue.serverTimestamp(),
        });
      }
      
      debugPrint('✅ Synced ${pendingMessagesQuery.docs.length} pending messages');
    } catch (e) {
      debugPrint('❌ Error syncing pending messages: $e');
    }
  }
  
  // Monitor read receipts continuously
  void _startReadReceiptMonitoring() {
    if (_chatRoomId == null || _currentUserId == null || _chatProvider == null) return;
    
    // Set up periodic updates for message status
    Stream.periodic(const Duration(seconds: 5)).listen((_) {
      if (_chatRoomId != null && _currentUserId != null && _connectedUserId != null) {
        _chatProvider!.markMessagesAsReadAndDelivered(
          chatRoomId: _chatRoomId!,
          currentUserId: _currentUserId!,
          otherUserId: _connectedUserId!,
        );
      }
    });
  }
  
  // Get chat message stream
  Stream<List<Map<String, dynamic>>>? getChatMessageStream() {
    if (_chatRoomId == null || _chatProvider == null) {
      // Return empty stream instead of null
      return Stream.value([]);
    }
    return _chatProvider!.getChatMessagesStream(_chatRoomId!);
  }

  // Create a temporary chat for blind user to send messages before connection
  Future<void> createTemporaryChat() async {
    if (_authProvider == null) {
      debugPrint('❌ ConnectionManager - Cannot create temp chat: AuthProvider is null');
      return;
    }
    
    _currentUserId = _authProvider!.currentUserId;
    if (_currentUserId == null) {
      debugPrint('❌ ConnectionManager - Cannot create temp chat: User ID is null');
      return;
    }

    debugPrint('🔄 ConnectionManager - Creating temporary chat for user: $_currentUserId');

    // Create a temporary chat room ID using user ID
    _chatRoomId = 'temp_chat_$_currentUserId';
    
    try {
      // Create the chat room if needed
      if (_chatProvider != null) {
        await _chatProvider!.createChatRoom([_currentUserId!]);
        
        // Add system message
        await _chatProvider!.addSystemMessage(
          chatRoomId: _chatRoomId!,
          text: 'Messages you send will be delivered when a helper connects.',
        );
        
        debugPrint('✅ ConnectionManager - Created temporary chat room: $_chatRoomId');
      } else {
        debugPrint('❌ ConnectionManager - Cannot create temp chat: ChatProvider is null');
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('❌ ConnectionManager - Error creating temporary chat: $e');
    }
  }

  // Transfer messages from temporary chat to permanent chat
  Future<void> _transferMessagesFromTemporaryChat(String? tempChatRoomId) async {
    if (tempChatRoomId == null || !tempChatRoomId.startsWith('temp_chat_') || 
        _chatRoomId == null || _chatProvider == null) {
      return;
    }
    
    try {
      // Get all messages from temporary chat
      final messagesQuery = await _firestore
          .collection('chats')
          .doc(tempChatRoomId)
          .collection('messages')
          .where('senderId', isEqualTo: _currentUserId)
          .orderBy('timestamp')
          .get();
      
      if (messagesQuery.docs.isEmpty) {
        debugPrint('ℹ️ No messages to transfer from temporary chat');
        return;
      }
      
      debugPrint('🔄 Transferring ${messagesQuery.docs.length} messages from temporary chat');
      
      // Copy each message to the new chat room
      for (final doc in messagesQuery.docs) {
        final data = doc.data();
        final messageId = const Uuid().v4();
        
        // Skip system messages
        if (data['senderId'] == 'system') continue;
        
        // Copy the message to the new chat room
        await _firestore
            .collection('chats')
            .doc(_chatRoomId)
            .collection('messages')
            .doc(messageId)
            .set({
          ...data,
          'id': messageId,
          'isDelivered': true,
          'isPending': false,
        });
      }
      
      // Add a transfer notification to the new chat
      await _chatProvider!.addSystemMessage(
        chatRoomId: _chatRoomId!,
        text: 'Previous messages have been transferred from temporary chat',
      );
      
      // Delete the temporary chat (optional)
      // await _firestore.collection('chats').doc(tempChatRoomId).delete();
      
      debugPrint('✅ Messages transferred successfully');
    } catch (e) {
      debugPrint('❌ Error transferring messages: $e');
    }
  }

  // Initiate a video call to the connected user
  Future<bool> initiateVideoCall() async {
    if (_connectedUserId == null || _currentUserId == null) {
      debugPrint('❌ ConnectionManager - Cannot initiate call: No connected user');
      return false;
    }
    
    try {
      // Generate a unique call ID using both user IDs to ensure both sides use the same room
      final List<String> sortedIds = [_currentUserId!, _connectedUserId!];
      sortedIds.sort();
      final String callId = 'call_${sortedIds.join('_')}';
      
      // Save call data to Firestore for the other user to receive
      await _firestore.collection('calls').doc(callId).set({
        'callerId': _currentUserId,
        'receiverId': _connectedUserId,
        'callId': callId,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'pending',
        'isActive': true,
      });
      
      debugPrint('✅ ConnectionManager - Initiated video call with ID: $callId');
      return true;
    } catch (e) {
      debugPrint('❌ ConnectionManager - Error initiating video call: $e');
      return false;
    }
  }
  
  // Get connected user's name 
  Future<String?> getConnectedUserName() async {
    if (_connectedUserId == null) return null;
    
    try {
      final userDoc = await _firestore.collection('users').doc(_connectedUserId).get();
      if (userDoc.exists) {
        final data = userDoc.data();
        return data?['displayName'] ?? 
               data?['name'] ?? 
               data?['email'] ?? 
               'User';
      }
      return null;
    } catch (e) {
      debugPrint('❌ ConnectionManager - Error getting connected user name: $e');
      return null;
    }
  }
  
  // Listen for incoming video calls
  Stream<Map<String, dynamic>?> getIncomingCallsStream() {
    if (_currentUserId == null) {
      return Stream.value(null);
    }
    
    return _firestore
        .collection('calls')
        .where('receiverId', isEqualTo: _currentUserId)
        .where('isActive', isEqualTo: true)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isNotEmpty) {
            final callDoc = snapshot.docs.first;
            return {
              'callId': callDoc.id,
              'callerId': callDoc['callerId'],
              ...callDoc.data(),
            };
          }
          return null;
        });
  }
  
  // End an active call
  Future<void> endCall(String callId) async {
    try {
      await _firestore.collection('calls').doc(callId).update({
        'status': 'ended',
        'isActive': false,
        'endedAt': FieldValue.serverTimestamp(),
      });
      debugPrint('✅ ConnectionManager - Ended call with ID: $callId');
    } catch (e) {
      debugPrint('❌ ConnectionManager - Error ending call: $e');
    }
  }
} 