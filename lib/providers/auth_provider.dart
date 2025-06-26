import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../services/firebase_auth_service.dart';
import '../services/connection_manager.dart';

class AuthProvider with ChangeNotifier {
  final FirebaseAuthService _authService = FirebaseAuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  User? _user;
  bool _isLoading = false;
  String? _errorMessage;
  bool _isBlindUser = false;
  String? _linkedUserId;
  String? _helperName;

  // Collection references
  final CollectionReference<Map<String, dynamic>> _usersCollection = 
      FirebaseFirestore.instance.collection('users');
  final CollectionReference<Map<String, dynamic>> _helperCollection = 
      FirebaseFirestore.instance.collection('helpers');

  // Getters
  bool get isAuthenticated => _user != null;
  User? get user => _user;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isBlindUser => _isBlindUser;
  String? get currentUserId => _user?.uid ?? _helperName?.hashCode.toString();
  String? get linkedUserId => _linkedUserId;
  bool get isLinkedWithUser => _linkedUserId != null;
  String? get helperName => _helperName;

  // Keys for SharedPreferences
  static const String userTypeKey = 'user_type';
  static const String isLoggedInKey = 'is_logged_in';
  static const String userEmailKey = 'user_email';
  static const String linkedUserIdKey = 'linked_user_id';
  static const String helperNameKey = 'helper_name';

  // Constructor - Check if user is already signed in
  AuthProvider() {
    try {
      // Check if there's a user but force sign-out if requested
      _checkForcedSignOut();
      
      _user = _authService.currentUser;
      _loadUserType();
      _loadLinkedUser();
      _loadHelperName();
      debugPrint('🔍 Initial user check: ${_user?.email ?? "No user found"}');
      
      _authService.authStateChanges.listen((User? user) {
        _user = user;
        debugPrint('🔄 Auth state changed: ${user?.email ?? "No user"}');
        
        // When auth state changes, update the stored login status
        if (user != null) {
          _saveAuthStatus(user.email!);
          _loadLinkedUser(); // Reload linked user data
          _saveFCMToken(); // Save FCM token on auth change
        }
        
        notifyListeners();
      });
      debugPrint('✅ AuthProvider initialized successfully');
    } catch (e) {
      debugPrint('❌ Error initializing AuthProvider: $e');
    }
  }
  
  // Load helper name from SharedPreferences
  Future<void> _loadHelperName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _helperName = prefs.getString(helperNameKey);
      debugPrint('🔍 Loaded helper name: $_helperName');
    } catch (e) {
      debugPrint('❌ Error loading helper name: $e');
    }
  }
  
  // Save helper name to SharedPreferences
  Future<void> _saveHelperName() async {
    if (_helperName == null) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(helperNameKey, _helperName!);
      debugPrint('💾 Saved helper name: $_helperName');
    } catch (e) {
      debugPrint('❌ Error saving helper name: $e');
    }
  }
  
  // Set helper name for sighted users (even without authentication)
  Future<void> setHelperName(String name) async {
    _helperName = name;
    await _saveHelperName();
    notifyListeners();
  }
  
  // Load user type from SharedPreferences
  Future<void> _loadUserType() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isBlindUser = prefs.getBool(userTypeKey) ?? false;
      debugPrint('🔍 Loaded user type: ${_isBlindUser ? 'Blind User' : 'Sighted User'}');
    } catch (e) {
      debugPrint('❌ Error loading user type: $e');
    }
  }

  // Save user type to SharedPreferences
  Future<void> _saveUserType() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(userTypeKey, _isBlindUser);
      debugPrint('💾 Saved user type: ${_isBlindUser ? 'Blind User' : 'Sighted User'}');
    } catch (e) {
      debugPrint('❌ Error saving user type: $e');
    }
  }

  // Set user type
  Future<void> setUserType(bool isBlindUser) async {
    _isBlindUser = isBlindUser;
    await _saveUserType();
    
    // Also update user data in Firestore if user is authenticated
    if (_user != null) {
      await _updateUserData({
        'isBlindUser': isBlindUser,
      });
    }
    
    notifyListeners();
  }
  
  // Ensure user data exists in Firestore
  Future<void> _ensureUserInFirestore() async {
    if (_user == null) return;
    
    try {
      final userDoc = await _usersCollection.doc(_user!.uid).get();
      
      if (!userDoc.exists) {
        // Generate a connection code for blind users
        String? userCode;
        if (_isBlindUser) {
          userCode = _generateRandomCode();
          debugPrint('✅ Generated connection code for blind user: $userCode');
        }
        
        // Create new user document
        await _usersCollection.doc(_user!.uid).set({
          'id': _user!.uid,
          'email': _user!.email,
          'displayName': _user!.displayName,
          'isBlindUser': _isBlindUser,
          'userType': _isBlindUser ? 'blind' : 'sighted',
          'type': _isBlindUser ? 'blind' : 'sighted',
          'userCode': _isBlindUser ? userCode : null,
          'createdAt': FieldValue.serverTimestamp(),
          'lastUpdated': FieldValue.serverTimestamp(),
        });
        debugPrint('✅ Created new user document in Firestore');
      } else {
        // Update existing user document
        await _updateUserData({
          'isBlindUser': _isBlindUser,
          'userType': _isBlindUser ? 'blind' : 'sighted',
          'type': _isBlindUser ? 'blind' : 'sighted',
          'lastUpdated': FieldValue.serverTimestamp(),
        });
        
        // Check if blind user has a connection code, if not, generate one
        if (_isBlindUser) {
          final userData = userDoc.data();
          if (userData != null && userData['userCode'] == null) {
            final userCode = _generateRandomCode();
            await _updateUserData({'userCode': userCode});
            debugPrint('✅ Added missing connection code for existing blind user: $userCode');
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Error ensuring user in Firestore: $e');
    }
  }
  
  // Generate a random 6-digit code for blind user connection
  String _generateRandomCode() {
    return (100000 + DateTime.now().millisecondsSinceEpoch % 900000).toString();
  }
  
  // Update user data in Firestore
  Future<void> _updateUserData(Map<String, dynamic> data) async {
    if (_user == null) return;
    
    try {
      await _usersCollection.doc(_user!.uid).update(data);
      debugPrint('✅ Updated user data in Firestore');
    } catch (e) {
      debugPrint('❌ Error updating user data in Firestore: $e');
    }
  }
  
  // Load linked user data
  Future<void> _loadLinkedUser() async {
    try {
      if (_user != null) {
        // For authenticated users
        final userDoc = await _usersCollection.doc(_user!.uid).get();
        if (userDoc.exists) {
          final userData = userDoc.data();
          if (userData != null && userData.containsKey('linkedUserId')) {
            _linkedUserId = userData['linkedUserId'];
            debugPrint('📱 Loaded linked user ID: $_linkedUserId');
            
            // Save to SharedPreferences
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(linkedUserIdKey, _linkedUserId!);
          }
        }
      } else if (_helperName != null) {
        // For unauthenticated helpers, check in helper collection
        final helperId = _helperName!.hashCode.toString();
        final helperDoc = await _helperCollection.doc(helperId).get();
        if (helperDoc.exists) {
          final helperData = helperDoc.data();
          if (helperData != null && helperData.containsKey('linkedUserId')) {
            _linkedUserId = helperData['linkedUserId'];
            debugPrint('📱 Loaded linked user ID for helper: $_linkedUserId');
            
            // Save to SharedPreferences
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(linkedUserIdKey, _linkedUserId!);
          }
        }
      }
      
      // If no linked user found, try SharedPreferences as fallback
      if (_linkedUserId == null) {
        final prefs = await SharedPreferences.getInstance();
        _linkedUserId = prefs.getString(linkedUserIdKey);
        
        // If found in prefs but not in Firestore, update Firestore if authenticated
        if (_linkedUserId != null && _user != null) {
          await _updateUserData({'linkedUserId': _linkedUserId});
        } else if (_linkedUserId != null && _helperName != null) {
          // For unauthenticated helper, update helper collection
          final helperId = _helperName!.hashCode.toString();
          await _helperCollection.doc(helperId).set({
            'name': _helperName,
            'linkedUserId': _linkedUserId,
            'lastUpdated': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }
    } catch (e) {
      debugPrint('❌ Error loading linked user: $e');
      
      // Try to get from SharedPreferences as fallback
      try {
        final prefs = await SharedPreferences.getInstance();
        _linkedUserId = prefs.getString(linkedUserIdKey);
      } catch (e) {
        debugPrint('❌ Error loading linked user from SharedPreferences: $e');
      }
    }
    
    notifyListeners();
  }
  
  // Link with a blind user (for sighted users)
  Future<bool> linkWithBlindUser(String blindUserUid) async {
    try {
      debugPrint('🔗 Attempting to link with blind user ID: $blindUserUid');
      
      // Verify the blind user exists and is actually a blind user
      final blindUserDoc = await _usersCollection.doc(blindUserUid).get();
      if (!blindUserDoc.exists) {
        debugPrint('❌ Blind user document not found in Firestore');
        _errorMessage = 'blind_user_not_found';
        return false;
      }
      
      final blindUserData = blindUserDoc.data();
      if (blindUserData == null || blindUserData['isBlindUser'] != true) {
        debugPrint('❌ ID provided is not for a blind user');
        _errorMessage = 'not_a_blind_user';
        return false;
      }
      
      if (_user != null) {
        debugPrint('👤 Linking as authenticated helper: ${_user!.uid}');
        // For authenticated users
        // Link this sighted user with the blind user
        await _updateUserData({
          'linkedUserId': blindUserUid,
        });
        
        // Also update the blind user to link with this user
        await _usersCollection.doc(blindUserUid).update({
          'linkedUserId': _user!.uid,
        });
      } else if (_helperName != null) {
        debugPrint('👤 Linking as unauthenticated helper: $_helperName');
        final helperId = _helperName!.hashCode.toString();
        
        // Create or update helper document
        await _helperCollection.doc(helperId).set({
          'name': _helperName,
          'linkedUserId': blindUserUid,
          'createdAt': FieldValue.serverTimestamp(),
          'lastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        
        // Also update the blind user to link with this helper
        try {
          await _usersCollection.doc(blindUserUid).update({
            'linkedHelperName': _helperName,
            'linkedHelperId': helperId,
          });
        } catch (updateError) {
          debugPrint('⚠️ Error updating blind user document: $updateError');
          
          // Check if the blind user document still exists
          final checkDoc = await _usersCollection.doc(blindUserUid).get();
          if (!checkDoc.exists) {
            debugPrint('❌ Blind user document no longer exists, connection failed');
            _errorMessage = 'blind_user_not_found';
            return false;
          }
          
          // Try using set with merge instead of update
          await _usersCollection.doc(blindUserUid).set({
            'linkedHelperName': _helperName,
            'linkedHelperId': helperId,
            'lastUpdated': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          
          debugPrint('✅ Successfully linked blind user using set with merge');
        }
      } else {
        debugPrint('❌ No authenticated user or helper name available for linking');
        _errorMessage = 'helper_name_required';
        return false;
      }
      
      // Update local state
      _linkedUserId = blindUserUid;
      
      // Save to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(linkedUserIdKey, blindUserUid);
      
      debugPrint('🔗 Successfully linked with blind user: $blindUserUid');
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('❌ Error linking with blind user: $e');
      _errorMessage = 'link_failed: ${e.toString()}';
      return false;
    }
  }
  
  // Unlink from connected user
  Future<bool> unlinkConnectedUser({bool userInitiated = true}) async {
    if (_linkedUserId == null) return false;
    
    try {
      // First, update the linked blind user to remove the link back
      try {
        await _usersCollection.doc(_linkedUserId).update({
          'linkedUserId': FieldValue.delete(),
          'linkedHelperName': FieldValue.delete(),
          'linkedHelperId': FieldValue.delete(),
        });
      } catch (e) {
        debugPrint('⚠️ Could not update linked blind user, may have been deleted: $e');
      }
      
      if (_user != null) {
        // For authenticated users
        // Update this user to remove the link
        await _updateUserData({
          'linkedUserId': FieldValue.delete(),
        });
      } else if (_helperName != null) {
        // For unauthenticated helpers
        final helperId = _helperName!.hashCode.toString();
        
        // Remove link from helper document
        await _helperCollection.doc(helperId).update({
          'linkedUserId': FieldValue.delete(),
        });
      }
      
      // Update local state
      _linkedUserId = null;
      
      // Remove from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(linkedUserIdKey);
      
      // Also notify ConnectionManager of the disconnection
      try {
        final connectionManager = ConnectionManager();
        await connectionManager.disconnect(userInitiated: userInitiated);
      } catch (e) {
        debugPrint('⚠️ Could not notify ConnectionManager of disconnection: $e');
      }
      
      debugPrint('🔓 Unlinked from connected user');
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('❌ Error unlinking from connected user: $e');
      _errorMessage = 'unlink_failed';
      return false;
    }
  }
  
  // Get user-specific data
  Future<List<Map<String, dynamic>>> getUserData(String collectionName) async {
    if (_user == null) return [];
    
    try {
      debugPrint('🔍 Getting $collectionName data for user: ${_user!.uid}');
      final querySnapshot = await _firestore
          .collection(collectionName)
          .where('userId', isEqualTo: _user!.uid)
          .get();
      
      return querySnapshot.docs
          .map((doc) => {
                'id': doc.id,
                ...doc.data(),
              })
          .toList();
    } catch (e) {
      debugPrint('❌ Error getting user $collectionName data: $e');
      return [];
    }
  }
  
  // Get linked user details
  Future<Map<String, dynamic>?> getLinkedUserDetails() async {
    if (_linkedUserId == null) return null;
    
    try {
      final userDoc = await _usersCollection.doc(_linkedUserId).get();
      if (userDoc.exists) {
        final userData = userDoc.data();
        if (userData != null) {
          return {
            'id': _linkedUserId,
            'displayName': userData['displayName'],
            'email': userData['email'],
            'isBlindUser': userData['isBlindUser'],
            'linkedUserName': userData['linkedUserName'],
          };
        }
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error getting linked user details: $e');
      return null;
    }
  }
  
  // Add user-specific data
  Future<String?> addUserData(String collectionName, Map<String, dynamic> data) async {
    if (_user == null) return null;
    
    try {
      // Make sure to add userId field and timestamps
      data['userId'] = _user!.uid;
      data['createdAt'] = FieldValue.serverTimestamp();
      data['updatedAt'] = FieldValue.serverTimestamp();
      
      final docRef = await _firestore.collection(collectionName).add(data);
      debugPrint('✅ Added user data to $collectionName with ID: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      debugPrint('❌ Error adding user data to $collectionName: $e');
      return null;
    }
  }
  
  // Update user-specific data
  Future<bool> updateUserData(String collectionName, String documentId, Map<String, dynamic> data) async {
    if (_user == null) return false;
    
    try {
      // First verify this document belongs to the current user
      final docSnap = await _firestore.collection(collectionName).doc(documentId).get();
      
      if (!docSnap.exists) {
        debugPrint('⚠️ Document not found: $documentId');
        return false;
      }
      
      final docData = docSnap.data() as Map<String, dynamic>;
      if (docData['userId'] != _user!.uid) {
        debugPrint('⚠️ Document does not belong to current user');
        return false;
      }
      
      // Add updatedAt timestamp
      data['updatedAt'] = FieldValue.serverTimestamp();
      
      await _firestore.collection(collectionName).doc(documentId).update(data);
      debugPrint('✅ Updated document in $collectionName');
      return true;
    } catch (e) {
      debugPrint('❌ Error updating document in $collectionName: $e');
      return false;
    }
  }
  
  // Update user display name
  Future<bool> updateUserDisplayName(String displayName) async {
    try {
      if (_user != null) {
        // For authenticated users, update in Firestore
        await _updateUserData({
          'displayName': displayName,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
        
        // Try to update Auth profile if possible
        try {
          await _user!.updateDisplayName(displayName);
        } catch (e) {
          debugPrint('⚠️ Could not update Auth profile display name: $e');
          // Continue anyway since Firestore is our source of truth
        }
        
        debugPrint('✅ Updated user display name to: $displayName');
        notifyListeners();
        return true;
      } else if (_isBlindUser) {
        // For blind users without auth, store in SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_display_name', displayName);
        
        debugPrint('✅ Saved blind user display name to preferences: $displayName');
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ Error updating user display name: $e');
      return false;
    }
  }
  
  // Delete user-specific data
  Future<bool> deleteUserData(String collectionName, String documentId) async {
    if (_user == null) return false;
    
    try {
      // First verify this document belongs to the current user
      final docSnap = await _firestore.collection(collectionName).doc(documentId).get();
      
      if (!docSnap.exists) {
        debugPrint('⚠️ Document not found: $documentId');
        return false;
      }
      
      final docData = docSnap.data() as Map<String, dynamic>;
      if (docData['userId'] != _user!.uid) {
        debugPrint('⚠️ Document does not belong to current user');
        return false;
      }
      
      await _firestore.collection(collectionName).doc(documentId).delete();
      debugPrint('✅ Deleted document from $collectionName');
      return true;
    } catch (e) {
      debugPrint('❌ Error deleting document from $collectionName: $e');
      return false;
    }
  }
  
  // Get a stream of user-specific data for real-time updates
  Stream<QuerySnapshot>? streamUserData(String collectionName) {
    if (_user == null) return null;
    
    return _firestore
        .collection(collectionName)
        .where('userId', isEqualTo: _user!.uid)
        .snapshots();
  }
  
  // Check if forced sign-out is needed
  Future<void> _checkForcedSignOut() async {
    try {
      final currentUser = _authService.currentUser;
      
      if (currentUser != null) {
        debugPrint('👤 User found on startup: ${currentUser.email}');
        
        // Sign out if the last sign-in was too long ago
        // This can be customized based on your app's requirements
        final lastSignInTime = currentUser.metadata.lastSignInTime;
        if (lastSignInTime != null) {
          final hoursSinceLastLogin = DateTime.now().difference(lastSignInTime).inHours;
          debugPrint('⏰ Hours since last login: $hoursSinceLastLogin');
          
          // If it's been more than 720 hours (30 days), sign the user out for security
          if (hoursSinceLastLogin > 720) {
            debugPrint('🔒 Auto sign-out due to inactivity');
            await _authService.signOut();
            await _clearAuthStatus();
          }
        }
      } else {
        // If Firebase says no user, but we have a stored login, try to restore session
        final isLoggedIn = await _getStoredLoginStatus();
        if (isLoggedIn) {
          debugPrint('🔄 Attempting to restore user session from stored preferences');
        } else {
          debugPrint('👤 No user found on startup');
        }
      }
    } catch (e) {
      debugPrint('❌ Error checking forced sign-out: $e');
    }
  }

  // Save authentication status
  Future<void> _saveAuthStatus(String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(isLoggedInKey, true);
      await prefs.setString(userEmailKey, email);
      debugPrint('💾 Saved authentication status for: $email');
    } catch (e) {
      debugPrint('❌ Error saving authentication status: $e');
    }
  }
  
  // Clear authentication status
  Future<void> _clearAuthStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(isLoggedInKey, false);
      await prefs.remove(userEmailKey);
      await prefs.remove(linkedUserIdKey);
      await prefs.remove(helperNameKey);
      _helperName = null;
      debugPrint('🧹 Cleared authentication status');
    } catch (e) {
      debugPrint('❌ Error clearing authentication status: $e');
    }
  }
  
  // Get stored login status
  Future<bool> _getStoredLoginStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(isLoggedInKey) ?? false;
    } catch (e) {
      debugPrint('❌ Error getting stored login status: $e');
      return false;
    }
  }

  // Common auth handler
  Future<bool> _handleAuthOperation(Future<void> Function() authOperation) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      await authOperation();

      // Sync with current user in Firebase
      _user = FirebaseAuth.instance.currentUser;

      if (_user == null) {
        debugPrint('❌ User is still null after authentication operation');
        throw FirebaseAuthException(
          code: 'auth-failed',
          message: 'User is null after authentication.',
        );
      }
      
      // Save login status
      await _saveAuthStatus(_user!.email!);
      debugPrint('✅ Authentication operation successful. User: ${_user!.email}');
      
      // Ensure user data is in Firestore
      await _ensureUserInFirestore();
      
      return true;
    } on FirebaseAuthException catch (e) {
      // Special handling for our custom success-despite-error code
      if (e.code == 'success-despite-error' || e.code == 'user-already-signed-in') {
        debugPrint('✅ Auth succeeded despite error: ${e.message}');
        // Refresh the user
        _user = FirebaseAuth.instance.currentUser;
        if (_user != null) {
          // Save login status
          await _saveAuthStatus(_user!.email!);
          // Ensure user data is in Firestore
          await _ensureUserInFirestore();
          debugPrint('✅ User confirmed: ${_user!.email}');
          return true;
        }
      }
      
      _errorMessage = _authService.getErrorMessage(e);
      debugPrint('❌ FirebaseAuthException during auth operation: [${e.code}] - ${e.message}');
      
      // Add more detailed logging based on specific errors
      if (e.code == 'network-request-failed' || e.code == 'timeout') {
        debugPrint('⚠️ Network issue detected. Check internet connection.');
      } else if (e.code == 'unknown-error') {
        debugPrint('⚠️ Unknown error occurred during authentication.');
      }
      
      return false;
    } catch (e) {
      debugPrint('❌ Unexpected error during auth operation: $e');
      _errorMessage = 'sign_in_failed';
      
      // If we have a more specific error message from the exception, use it
      if (e.toString().contains('network')) {
        _errorMessage = 'network_request_failed';
      } else if (e.toString().contains('timeout')) {
        _errorMessage = 'network_timeout';
      }
      
      // Check if user is actually signed in despite the error
      if (FirebaseAuth.instance.currentUser != null) {
        debugPrint('✅ User is already signed in despite the error: ${FirebaseAuth.instance.currentUser!.email}');
        _user = FirebaseAuth.instance.currentUser;
        // Save login status
        await _saveAuthStatus(_user!.email!);
        // Ensure user data is in Firestore
        await _ensureUserInFirestore();
        return true;
      }
      
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Email and Password Login
  Future<bool> login(String email, String password) async {
    debugPrint('🔷 Attempting login with email: $email');
    final result = await _handleAuthOperation(() async {
      final userCredential = await _authService.signIn(
        email: email,
        password: password,
      );
      _user = userCredential.user;
      debugPrint('✅ Login successful for: ${_user?.email}');
      if (_user == null) {
        throw FirebaseAuthException(
          code: 'user-not-found',
          message: 'User is null after login.',
        );
      }
    });
    
    if (result) {
      await _loadUserType();
      await _loadLinkedUser();
    }
    
    return result;
  }

  // Register
  Future<bool> register(String email, String password, String name) async {
    debugPrint('🔷 Attempting registration with email: $email');
    final result = await _handleAuthOperation(() async {
      final userCredential = await _authService.signUp(
        email: email,
        password: password,
        displayName: name,
      );
      _user = userCredential.user;
      debugPrint('✅ Registration successful for: ${_user?.email}');
      if (_user == null) {
        throw FirebaseAuthException(
          code: 'registration-failed',
          message: 'User is null after registration.',
        );
      }

      // Optionally send email verification
      try {
        await _user!.sendEmailVerification();
        debugPrint('✅ Verification email sent');
      } catch (e) {
        debugPrint('⚠️ Failed to send verification email: $e');
      }
    });
    
    return result;
  }

  // Google Sign-In
  Future<bool> signInWithGoogle() async {
    debugPrint('🔷 Attempting Google sign-in');
    final result = await _handleAuthOperation(() async {
      final userCredential = await _authService.signInWithGoogle();
      _user = userCredential.user;
      debugPrint('✅ Google sign-in successful for: ${_user?.email}');
      if (_user == null) {
        throw FirebaseAuthException(
          code: 'google-sign-in-failed',
          message: 'User is null after Google Sign-In.',
        );
      }
    });
    
    if (result) {
      await _loadUserType();
      await _loadLinkedUser();
    }
    
    return result;
  }

  // Update user profile
  Future<bool> updateProfile({String? displayName, String? photoURL}) async {
    return _handleAuthOperation(() async {
      await _authService.updateProfile(
        displayName: displayName,
        photoURL: photoURL,
      );
      _user = _authService.currentUser;
      
      // Also update user data in Firestore
      if (displayName != null) {
        await _updateUserData({'displayName': displayName});
      }
    });
  }

  // Sign Out
  Future<bool> logout() async {
    debugPrint('🔷 Attempting logout');
    try {
      await _authService.signOut();
      _user = null;
      _linkedUserId = null;
      await _clearAuthStatus();
      debugPrint('✅ Logout successful');
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('❌ Error during logout: $e');
      return false;
    }
  }

  // Reset Password
  Future<bool> resetPassword(String email) async {
    debugPrint('🔷 Attempting password reset for: $email');
    return _handleAuthOperation(() async {
      await _authService.resetPassword(email: email);
      debugPrint('✅ Password reset email sent');
    });
  }

  // Check if user email is verified
  bool get isEmailVerified {
    return _user?.emailVerified ?? false;
  }

  // Get user details (for self or another user)
  Future<Map<String, dynamic>?> getUserDetails([String? userId]) async {
    try {
      final targetUserId = userId ?? _user?.uid;
      
      if (targetUserId == null) {
        debugPrint('❌ Cannot get user details: No user ID available');
        return null;
      }
      
      final userDoc = await _usersCollection.doc(targetUserId).get();
      
      if (userDoc.exists) {
        return userDoc.data();
      } else {
        debugPrint('❌ User document not found for ID: $targetUserId');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Error getting user details: $e');
      return null;
    }
  }
  
  // Refresh linked user status from Firestore
  Future<void> refreshLinkedUser() async {
    try {
      final userDetails = await getUserDetails();
      if (userDetails != null && userDetails.containsKey('linkedUserId')) {
        _linkedUserId = userDetails['linkedUserId'];
        debugPrint('✅ Refreshed linked user ID: $_linkedUserId');
        
        // Verify two-way linking for blind users
        if (_isBlindUser && _user != null && _linkedUserId != null) {
          final helperDoc = await _usersCollection.doc(_linkedUserId).get();
          if (helperDoc.exists) {
            final helperData = helperDoc.data();
            if (helperData == null || helperData['linkedUserId'] != _user!.uid) {
              // Helper doesn't have this blind user linked back - fix it
              debugPrint('⚠️ Two-way linking broken, attempting to fix from blind user side');
              await _usersCollection.doc(_linkedUserId).update({
                'linkedUserId': _user!.uid,
                'lastUpdated': FieldValue.serverTimestamp(),
              });
            }
          }
        }
        
        // Save to SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(linkedUserIdKey, _linkedUserId!);
        
        notifyListeners();
        return;
      }
      
      // If we couldn't find in Firestore, try SharedPreferences as fallback
      final prefs = await SharedPreferences.getInstance();
      _linkedUserId = prefs.getString(linkedUserIdKey);
      if (_linkedUserId != null) {
        debugPrint('✅ Found linked user ID in SharedPreferences: $_linkedUserId');
        
        // Force update Firestore with the linked user ID from SharedPreferences
        if (_user != null) {
          await _updateUserData({
            'linkedUserId': _linkedUserId,
            'lastUpdated': FieldValue.serverTimestamp(),
          });
          
          // For blind users, also update the helper's record
          if (_isBlindUser) {
            await _usersCollection.doc(_linkedUserId).update({
              'linkedUserId': _user!.uid,
              'lastUpdated': FieldValue.serverTimestamp(),
            }).catchError((e) {
              debugPrint('⚠️ Could not update helper record: $e');
            });
          }
        }
        
        notifyListeners();
      }
    } catch (e) {
      debugPrint('❌ Error refreshing linked user: $e');
    }
  }

  // Manually set the linked user ID (for internal use)
  Future<void> manuallySetLinkedUser(String linkedUserId) async {
    try {
      _linkedUserId = linkedUserId;
      debugPrint('✅ Manually set linked user ID: $_linkedUserId');
      
      // Save to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(linkedUserIdKey, _linkedUserId!);
      
      // Update Firestore if user is authenticated
      if (_user != null) {
        await _updateUserData({
          'linkedUserId': _linkedUserId,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      } else if (_helperName != null) {
        // For unauthenticated helpers
        final helperId = _helperName!.hashCode.toString();
        await _helperCollection.doc(helperId).update({
          'linkedUserId': _linkedUserId,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error manually setting linked user: $e');
    }
  }

  // Force bidirectional connection between current user and linked user
  Future<bool> forceBidirectionalConnection() async {
    debugPrint('🔄 Forcing bidirectional connection...');
    
    final String? currentId = currentUserId;
    if (currentId == null || _linkedUserId == null) {
      debugPrint('❌ Cannot force bidirectional connection: Current user ID or linked user ID is null');
      return false;
    }
    
    try {
      // Update current user's document to link to the helper
      await _firestore.collection('users').doc(currentId).update({
        'linkedUserId': _linkedUserId,
      });
      
      // Update helper's document to link back to the current user
      // First check if helper is in the helpers collection
      final helperDoc = await _firestore.collection('helpers').doc(_linkedUserId).get();
      
      if (helperDoc.exists) {
        await _firestore.collection('helpers').doc(_linkedUserId).update({
          'linkedUserId': currentId,
        });
        debugPrint('✅ Updated helper document in helpers collection');
      } else {
        // If not in helpers collection, try users collection
        await _firestore.collection('users').doc(_linkedUserId).update({
          'linkedUserId': currentId,
        });
        debugPrint('✅ Updated helper document in users collection');
      }
      
      // Save to SharedPreferences for local persistence
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(linkedUserIdKey, _linkedUserId!);
      
      // Create/update connection records in the connections collection
      await _firestore.collection('connections').doc(currentId).set({
        'connectedUserId': _linkedUserId,
        'chatRoomId': _getChatRoomId(currentId, _linkedUserId!),
        'timestamp': FieldValue.serverTimestamp(),
        'isPermanent': true,
        'lastSyncedAt': FieldValue.serverTimestamp(),
      });
      
      await _firestore.collection('connections').doc(_linkedUserId).set({
        'connectedUserId': currentId,
        'chatRoomId': _getChatRoomId(currentId, _linkedUserId!),
        'timestamp': FieldValue.serverTimestamp(),
        'isPermanent': true,
        'lastSyncedAt': FieldValue.serverTimestamp(),
      });
      
      debugPrint('✅ Created/updated connection records in Firestore');
      
      // Update local state - we already have _linkedUserId set
      notifyListeners();
      
      debugPrint('✅ Bidirectional connection forced successfully');
      return true;
    } catch (e) {
      debugPrint('❌ Error forcing bidirectional connection: $e');
      return false;
    }
  }
  
  // Helper method to generate consistent chat room ID
  String _getChatRoomId(String userId1, String userId2) {
    final List<String> userIds = [userId1, userId2];
    userIds.sort();
    return 'chat_${userIds.join('_')}';
  }

  // Update display name
  Future<bool> updateDisplayName(String displayName) async {
    return _handleAuthOperation(() async {
      await _authService.updateProfile(displayName: displayName);
      _user = _authService.currentUser;
      
      // Also update user data in Firestore
      await _updateUserData({'displayName': displayName});
      debugPrint('✅ Display name updated successfully to: $displayName');
    });
  }
  
  // Update email
  Future<bool> updateEmail(String newEmail, String password) async {
    return _handleAuthOperation(() async {
      // Reauthenticate user before changing email
      if (_user != null) {
        AuthCredential credential = EmailAuthProvider.credential(
          email: _user!.email!,
          password: password,
        );
        await _user!.reauthenticateWithCredential(credential);
        
        // Update email
        await _user!.updateEmail(newEmail);
        _user = _authService.currentUser;
        
        // Also update user data in Firestore
        await _updateUserData({'email': newEmail});
        debugPrint('✅ Email updated successfully to: $newEmail');
      } else {
        throw FirebaseAuthException(
          code: 'user-not-found',
          message: 'User is null when trying to update email.',
        );
      }
    });
  }
  
  // Update password
  Future<bool> updatePassword(String currentPassword, String newPassword) async {
    return _handleAuthOperation(() async {
      // Reauthenticate user before changing password
      if (_user != null) {
        AuthCredential credential = EmailAuthProvider.credential(
          email: _user!.email!,
          password: currentPassword,
        );
        await _user!.reauthenticateWithCredential(credential);
        
        // Update password
        await _user!.updatePassword(newPassword);
        debugPrint('✅ Password updated successfully');
      } else {
        throw FirebaseAuthException(
          code: 'user-not-found',
          message: 'User is null when trying to update password.',
        );
      }
    });
  }

  // Save FCM token to Firestore
  Future<void> _saveFCMToken() async {
    if (_user == null) return;
    try {
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null) {
        debugPrint('Saving FCM token: $fcmToken');
        
        // Get existing user document to check for existing tokens
        final userDoc = await _usersCollection.doc(_user!.uid).get();
        final userData = userDoc.data();
        List<String> existingTokens = [];
        
        if (userData != null && userData['fcmTokens'] is List) {
          existingTokens = List<String>.from(userData['fcmTokens']);
          // Remove any null or empty tokens
          existingTokens.removeWhere((token) => token.isEmpty);
        }
        
        // Add the new token if it's not already in the list
        if (!existingTokens.contains(fcmToken)) {
          existingTokens.add(fcmToken);
        }
        
        // Update the user document with both single token and token array
        await _usersCollection.doc(_user!.uid).update({
          'fcmToken': fcmToken, // Current token (for backward compatibility)
          'fcmTokens': existingTokens, // Array of tokens (more reliable)
          'lastFCMTokenUpdate': FieldValue.serverTimestamp(),
          'platform': defaultTargetPlatform.toString(),
          'appVersion': '1.0.0', // You can update this with your app version
        });
        
        // Also save to SharedPreferences for faster access
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('fcm_token', fcmToken);
        
        debugPrint('✅ FCM token saved to Firestore and SharedPreferences');
      } else {
        debugPrint('⚠️ FCM token is null, cannot save.');
      }
    } catch (e) {
      debugPrint('❌ Error saving FCM token: $e');
    }
  }
}
