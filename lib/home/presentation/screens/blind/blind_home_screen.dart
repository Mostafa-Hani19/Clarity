import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../../../../routes/app_router.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../services/video_call_service.dart';
import '../../../../services/connection_manager.dart';
import 'blind_chat_screen.dart';
import 'blind_emergency_screen.dart';
import 'blind_location_screen.dart';
import 'blind_reminder_screen.dart';
import 'blind_paper_scanner_screen.dart';
import 'blind_sensor_screen.dart';
import 'blind_currency_detector_screen.dart';
import '../../../../common/widgets/custom_gnav_bar.dart';
import '../helper/helper_connection_status.dart';
import '../../../../models/images.dart';
import 'blind_settings_screen.dart';
import '../../../../services/firestore_service.dart';

class BlindHomeScreen extends StatefulWidget {
  const BlindHomeScreen({super.key});

  @override
  State<BlindHomeScreen> createState() => _BlindHomeScreenState();
}

class _BlindHomeScreenState extends State<BlindHomeScreen> {
  int _selectedIndex = 0;
  final List<Widget> _pages = [const _HomePage(), const _SettingsPage()];
  String? _connectedUser;
  StreamSubscription<Map<String, dynamic>?>? _callSubscription;
  final VideoCallService _videoCallService = VideoCallService();

  void _onTabChange(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  void initState() {
    super.initState();
    _initializeConnection();
    _setupIncomingCallListener();
    _ensureCorrectHelperConnection();

    // Force locale update
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prefs = await SharedPreferences.getInstance();
      final languageCode = prefs.getString('language_code') ?? 'en';
      if (context.mounted && context.locale.languageCode != languageCode) {
        await context.setLocale(Locale(languageCode));
        if (context.mounted) {
          setState(() {});
        }
      }
    });
  }

  @override
  void dispose() {
    _callSubscription?.cancel();
    super.dispose();
  }

  // Set up listener for incoming video calls
  void _setupIncomingCallListener() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.currentUserId;

      if (userId != null) {
        // Listen for incoming calls
        _callSubscription =
            _videoCallService.getIncomingCallsStream(userId).listen((callData) {
          if (callData != null && mounted) {
            _showIncomingCallDialog(callData);
          }
        }, onError: (error) {
          debugPrint('Error in call listener: $error');
        });

        debugPrint('✅ Set up incoming call listener for $userId');
      }
    });
  }

  // Show dialog for incoming calls
  void _showIncomingCallDialog(Map<String, dynamic> callData) {
    final callId = callData['callId'];
    final callerId = callData['callerId'];
    final callerName = callData['callerName'] as String? ?? 'Helper';

    // Prevent showing multiple dialogs for the same call
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('incoming_video_call'.tr()),
        content: Text('$callerName ${'is_calling_you'.tr()}'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _videoCallService.rejectCall(callId);
            },
            child:
                Text('decline'.tr(), style: const TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);

              // First accept the call
              _videoCallService.acceptCall(callId);

              // Then navigate to the video call screen
              AppRouter.navigateToVideoCall(context,
                  callID: callId,
                  targetUserID: callerId,
                  targetUserName: callerName,
                  isOutgoing: false);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: Text('answer'.tr(),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _initializeConnection() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _checkConnectedUser();

      if (!mounted) return;
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (_connectedUser == null && authProvider.isLinkedWithUser) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
        await _checkConnectedUser();

        if (!mounted) return;
        if (_connectedUser == null && authProvider.isLinkedWithUser) {
          await _fixConnectionWithHelper();
        }
      }
    });
  }

  Future<void> _checkConnectedUser() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.refreshLinkedUser();

    if (!mounted) return;
    if (authProvider.isLinkedWithUser) {
      await _checkLinkedUserDetails(authProvider);
    } else {
      await _checkStoredConnection(authProvider);
    }
  }

  Future<void> _checkLinkedUserDetails(AuthProvider authProvider) async {
    try {
      final linkedUserDetails = await authProvider.getLinkedUserDetails();
      if (!mounted) return;
      setState(() {
        _connectedUser =
            linkedUserDetails?['displayName'] ?? linkedUserDetails?['email'];
      });
      debugPrint('Blind user is connected to helper: $_connectedUser');
    } catch (e) {
      debugPrint('Error getting linked user details: $e');
    }
  }

  Future<void> _checkStoredConnection(AuthProvider authProvider) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final linkedUserId = prefs.getString('linked_user_id');

      if (!mounted) return;
      if (linkedUserId != null && linkedUserId.isNotEmpty) {
        await authProvider.manuallySetLinkedUser(linkedUserId);
        final linkedUserDetails = await authProvider.getLinkedUserDetails();

        if (!mounted) return;
        if (linkedUserDetails != null) {
          setState(() {
            _connectedUser =
                linkedUserDetails['displayName'] ?? linkedUserDetails['email'];
          });
          debugPrint(
            'Connection restored from SharedPreferences: $_connectedUser',
          );
        }
      } else {
        debugPrint('Blind user is not connected to any helper');
      }
    } catch (e) {
      debugPrint('Error checking connection from SharedPreferences: $e');
    }
  }

  Future<void> _fixConnectionWithHelper() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (!mounted) return;

      if (!authProvider.isLinkedWithUser) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('no_helper_connected'.tr()),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final success = await authProvider.forceBidirectionalConnection();
      if (!mounted) return;

      if (success) {
        await _checkConnectedUser();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('connection_fixed'.tr()),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('could_not_fix_connection'.tr()),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error fixing connection: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${'failed_to_fix_connection'.tr()}: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ignore: unused_element
  Future<Map<String, dynamic>> _getCurrentLocation() async {
    return {
      'latitude': 0.0,
      'longitude': 0.0,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    // ignore: unused_local_variable
    final theme = Theme.of(context);

    // Get screen dimensions for responsive sizing
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 360;
    // ignore: unused_local_variable
    final isLandscape = screenSize.width > screenSize.height;
    // ignore: unused_local_variable
    final padding = isSmallScreen ? 12.0 : 20.0;
    // ignore: unused_local_variable
    final titleFontSize = isSmallScreen ? 26.0 : 32.0;

    return Scaffold(
      body: _selectedIndex == 0 ? const _HomePage() : _pages[_selectedIndex],
      bottomNavigationBar: CustomGNavBar(
        selectedIndex: _selectedIndex,
        onTabChange: _onTabChange,
      ),
    );
  }

  Future<bool> _verifyCorrectHelperConnection(
      AuthProvider authProvider, ConnectionManager connectionManager) async {
    debugPrint("🔍 Verifying correct helper connection...");

    try {
      // Get the linked helper ID from AuthProvider
      final String? linkedHelperId = authProvider.linkedUserId;
      debugPrint("🔍 AuthProvider linked helper ID: $linkedHelperId");
      debugPrint(
          "🔍 ConnectionManager connected user ID: ${connectionManager.connectedUserId}");

      // Check if the IDs match
      if (linkedHelperId != null &&
          connectionManager.connectedUserId != null &&
          linkedHelperId == connectionManager.connectedUserId) {
        debugPrint("✅ Helper connection verified: connected to correct helper");
        return true;
      }

      // If we reach here, there's a mismatch
      debugPrint(
          "❌ Helper connection mismatch: AuthProvider and ConnectionManager have different helpers");
      return false;
    } catch (e) {
      debugPrint("❌ Error verifying helper connection: $e");
      return false;
    }
  }

  void _ensureCorrectHelperConnection() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final connectionManager =
          Provider.of<ConnectionManager>(context, listen: false);

      // First attempt: verify and fix connection
      await _attemptFixConnection(authProvider, connectionManager);
      
      // Schedule additional check after a delay to ensure connection is stable
      Future.delayed(const Duration(seconds: 2), () async {
        if (!mounted) return;
        await _attemptFixConnection(authProvider, connectionManager);
        
        // If still not connected, try a more aggressive approach
        if (!connectionManager.isConnected && authProvider.isLinkedWithUser) {
          debugPrint("⚠️ Still not connected after two attempts. Trying aggressive fix...");
          await _forceConnectionFix(authProvider, connectionManager);
        }
      });
    });
  }
  
  Future<void> _attemptFixConnection(AuthProvider authProvider, ConnectionManager connectionManager) async {
    if (!mounted) return;
    
    // Verify that we're connected to the correct helper
    final bool isCorrectHelper = await _verifyCorrectHelperConnection(authProvider, connectionManager);
    if (!isCorrectHelper) {
      debugPrint("⚠️ Detected incorrect helper connection, attempting to fix...");
      await _fixHelperConnection(authProvider, connectionManager);
    } else {
      debugPrint("✅ Helper connection verified");
    }
  }

  Future<void> _forceConnectionFix(AuthProvider authProvider, ConnectionManager connectionManager) async {
    if (!mounted || !authProvider.isLinkedWithUser) return;
    
    try {
      final linkedHelperId = authProvider.linkedUserId!;
      
      // 1. Ensure both documents have correct linking
      await FirebaseFirestore.instance.collection('users').doc(authProvider.currentUserId!).update({
        'linkedUserId': linkedHelperId,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      
      await FirebaseFirestore.instance.collection('users').doc(linkedHelperId).update({
        'linkedUserId': authProvider.currentUserId,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      
      // 2. Create consistent chat room ID
      final List<String> userIds = [authProvider.currentUserId!, linkedHelperId];
      userIds.sort();
      final chatRoomId = 'chat_${userIds.join('_')}';
      
      // 3. Update connection records directly
      await FirebaseFirestore.instance.collection('connections').doc(authProvider.currentUserId).set({
        'connectedUserId': linkedHelperId,
        'chatRoomId': chatRoomId,
        'timestamp': FieldValue.serverTimestamp(),
        'isPermanent': true,
        'lastSyncedAt': FieldValue.serverTimestamp(),
      });
      
      await FirebaseFirestore.instance.collection('connections').doc(linkedHelperId).set({
        'connectedUserId': authProvider.currentUserId,
        'chatRoomId': chatRoomId,
        'timestamp': FieldValue.serverTimestamp(),
        'isPermanent': true,
        'lastSyncedAt': FieldValue.serverTimestamp(),
      });
      
      // 4. Force reconnection
      await connectionManager.disconnect(userInitiated: false);
      await connectionManager.connectToUser(linkedHelperId);
      await connectionManager.checkConnectionStatus();
      
      debugPrint("✅ Applied aggressive connection fix");
      
      // 5. Update local state
      await _checkConnectedUser();
    } catch (e) {
      debugPrint("❌ Error in aggressive connection fix: $e");
    }
  }

  Future<void> _repairConnection(ConnectionManager connectionManager) async {
    debugPrint("🔧 Attempting to repair connection...");

    try {
      // Force check connection status
      await connectionManager.checkConnectionStatus();
      debugPrint(
          "🔧 Connection status after repair attempt: isConnected=${connectionManager.isConnected}");

      if (connectionManager.isConnected &&
          connectionManager.connectedUserId != null) {
        // Try to force bidirectional connection
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        if (authProvider.isLinkedWithUser) {
          final success = await authProvider.forceBidirectionalConnection();
          debugPrint("🔧 Forced bidirectional connection result: $success");
        }

        // Update the local _connectedUser variable
        await _checkConnectedUser();
      }
    } catch (e) {
      debugPrint("❌ Error repairing connection: $e");
    }
  }

  Future<void> _fixHelperConnection(AuthProvider authProvider, ConnectionManager connectionManager) async {
    debugPrint("🔧 Fixing helper connection...");

    try {
      // First, refresh the linked user data from Firestore
      await authProvider.refreshLinkedUser();
      
      // Get the linked helper ID from AuthProvider
      final String? linkedHelperId = authProvider.linkedUserId;

      if (linkedHelperId != null) {
        // Force bidirectional connection first to ensure both sides are properly linked
        final bidirectionalSuccess = await authProvider.forceBidirectionalConnection();
        debugPrint("✅ Forced bidirectional connection result: $bidirectionalSuccess");
        
        // Force update the connection manager to use the correct helper
        await connectionManager.connectToUser(linkedHelperId);
        debugPrint("✅ Connected to helper via ConnectionManager: $linkedHelperId");
        
        // Force ConnectionManager to update its state
        await connectionManager.checkConnectionStatus();
        debugPrint("✅ Connection status after fix: isConnected=${connectionManager.isConnected}");
        
        // Update local state
        await _checkConnectedUser();

        // Notify user
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('connection_fixed'.tr()),
              backgroundColor: Colors.green,
            ),
          );
        }

        debugPrint("✅ Helper connection fixed");
      } else {
        // Try to recover from SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        final storedLinkedUserId = prefs.getString('linked_user_id');
        
        if (storedLinkedUserId != null && storedLinkedUserId.isNotEmpty) {
          debugPrint("🔍 Found linked helper ID in SharedPreferences: $storedLinkedUserId");
          
          // Set the linked user ID in AuthProvider
          await authProvider.manuallySetLinkedUser(storedLinkedUserId);
          
          // Now try to fix the connection again with the recovered ID
          await connectionManager.connectToUser(storedLinkedUserId);
          await authProvider.forceBidirectionalConnection();
          await connectionManager.checkConnectionStatus();
          
          // Update local state
          await _checkConnectedUser();
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('connection_restored_from_backup'.tr()),
                backgroundColor: Colors.green,
              ),
            );
          }
          
          debugPrint("✅ Helper connection restored from backup");
        } else {
          debugPrint("❌ Cannot fix helper connection: no linked helper in AuthProvider or SharedPreferences");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('cannot_fix_connection'.tr()),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint("❌ Error fixing helper connection: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${'error_fixing_connection'.tr()}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage();

  @override
  Widget build(BuildContext context) {
    return const SettingsContent();
  }
}

class SettingsContent extends StatelessWidget {
  const SettingsContent({super.key});

  @override
  Widget build(BuildContext context) {
    return const SettingsScreen(hideBottomNavBar: true);
  }
}

class _HomePage extends StatefulWidget {
  const _HomePage();

  @override
  State<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<_HomePage> {
  String? _connectedUser;
  final FirestoreService _firestoreService = FirestoreService();
  StreamSubscription<Map<String, dynamic>?>? _callSubscription;
  final VideoCallService _videoCallService = VideoCallService();

  @override
  void initState() {
    super.initState();
    _initializeConnection();
    _setupIncomingCallListener();
    // No need to call _ensureCorrectHelperConnection() here, it's handled in BlindHomeScreen

    // Force locale update
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prefs = await SharedPreferences.getInstance();
      final languageCode = prefs.getString('language_code') ?? 'en';
      if (context.mounted && context.locale.languageCode != languageCode) {
        await context.setLocale(Locale(languageCode));
        if (context.mounted) {
          setState(() {});
        }
      }
    });
  }

  @override
  void dispose() {
    _callSubscription?.cancel();
    super.dispose();
  }

  // Set up listener for incoming video calls
  void _setupIncomingCallListener() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.currentUserId;

      if (userId != null) {
        // Listen for incoming calls
        _callSubscription =
            _videoCallService.getIncomingCallsStream(userId).listen((callData) {
          if (callData != null && mounted) {
            _showIncomingCallDialog(callData);
          }
        }, onError: (error) {
          debugPrint('Error in call listener: $error');
        });

        debugPrint('✅ Set up incoming call listener for $userId');
      }
    });
  }

  // Show dialog for incoming calls
  void _showIncomingCallDialog(Map<String, dynamic> callData) {
    final callId = callData['callId'];
    final callerId = callData['callerId'];
    final callerName = callData['callerName'] as String? ?? 'Helper';

    // Prevent showing multiple dialogs for the same call
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('incoming_video_call'.tr()),
        content: Text('$callerName ${'is_calling_you'.tr()}'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _videoCallService.rejectCall(callId);
            },
            child:
                Text('decline'.tr(), style: const TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);

              // First accept the call
              _videoCallService.acceptCall(callId);

              // Then navigate to the video call screen
              AppRouter.navigateToVideoCall(context,
                  callID: callId,
                  targetUserID: callerId,
                  targetUserName: callerName,
                  isOutgoing: false);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: Text('answer'.tr(),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _initializeConnection() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _checkConnectedUser();

      if (!mounted) return;
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (_connectedUser == null && authProvider.isLinkedWithUser) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
        await _checkConnectedUser();

        if (!mounted) return;
        if (_connectedUser == null && authProvider.isLinkedWithUser) {
          await _fixConnectionWithHelper();
        }
      }
    });
  }

  Future<void> _checkConnectedUser() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.refreshLinkedUser();

    if (!mounted) return;
    if (authProvider.isLinkedWithUser) {
      await _checkLinkedUserDetails(authProvider);
    } else {
      await _checkStoredConnection(authProvider);
    }
  }

  Future<void> _checkLinkedUserDetails(AuthProvider authProvider) async {
    try {
      final linkedUserDetails = await authProvider.getLinkedUserDetails();
      if (!mounted) return;
      setState(() {
        _connectedUser =
            linkedUserDetails?['displayName'] ?? linkedUserDetails?['email'];
      });
      debugPrint('Blind user is connected to helper: $_connectedUser');
    } catch (e) {
      debugPrint('Error getting linked user details: $e');
    }
  }

  Future<void> _checkStoredConnection(AuthProvider authProvider) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final linkedUserId = prefs.getString('linked_user_id');

      if (!mounted) return;
      if (linkedUserId != null && linkedUserId.isNotEmpty) {
        await authProvider.manuallySetLinkedUser(linkedUserId);
        final linkedUserDetails = await authProvider.getLinkedUserDetails();

        if (!mounted) return;
        if (linkedUserDetails != null) {
          setState(() {
            _connectedUser =
                linkedUserDetails['displayName'] ?? linkedUserDetails['email'];
          });
          debugPrint(
            'Connection restored from SharedPreferences: $_connectedUser',
          );
        }
      } else {
        debugPrint('Blind user is not connected to any helper');
      }
    } catch (e) {
      debugPrint('Error checking connection from SharedPreferences: $e');
    }
  }

  // ignore: unused_element
  Future<void> _disconnectFromUser() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('disconnect_from_helper'.tr()),
        content: Text('disconnect_confirmation'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('cancel'.tr()),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final success = await authProvider.unlinkConnectedUser();
              if (!mounted) return;

              setState(() {
                if (success) _connectedUser = null;
              });

              // ignore: use_build_context_synchronously
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    success
                        ? 'successfully_disconnected'.tr()
                        : 'failed_to_disconnect'.tr(),
                  ),
                  backgroundColor: success ? Colors.green : Colors.red,
                ),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('disconnect'.tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _fixConnectionWithHelper() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (!mounted) return;

      if (!authProvider.isLinkedWithUser) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('no_helper_connected'.tr()),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final success = await authProvider.forceBidirectionalConnection();
      if (!mounted) return;

      if (success) {
        await _checkConnectedUser();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('connection_fixed'.tr()),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('could_not_fix_connection'.tr()),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error fixing connection: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${'failed_to_fix_connection'.tr()}: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _sendDataToFirebase(String serviceName) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.currentUserId;

      if (!mounted) return;
      if (userId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('must_be_logged_in'.tr()),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final data = {
        'service': serviceName,
        'timestamp': FieldValue.serverTimestamp(),
        'userLocation': await _getCurrentLocation(),
        'connectedHelper': _connectedUser,
      };

      await _firestoreService.addUserData(userId, 'service_usage', data);
      debugPrint('✅ Data sent to Firebase for service: $serviceName');
    } catch (e) {
      debugPrint('❌ Error sending data to Firebase: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${'failed_to_send_data'.tr()}: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<Map<String, dynamic>> _getCurrentLocation() async {
    return {
      'latitude': 0.0,
      'longitude': 0.0,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);

    // Get screen dimensions for responsive sizing
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 360;
    final isLandscape = screenSize.width > screenSize.height;
    final padding = isSmallScreen ? 12.0 : 20.0;
    final titleFontSize = isSmallScreen ? 26.0 : 32.0;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: isDarkMode ? Colors.white : Colors.black,
        elevation: 0,
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: isSmallScreen ? 32 : 40,
              width: isSmallScreen ? 32 : 40,
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.blue.shade800 : Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: isDarkMode
                        ? Colors.blue.shade800.withOpacity(0.6)
                        : Colors.blue.shade300.withOpacity(0.5),
                    spreadRadius: 1,
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Image.asset(
                isDarkMode ? Appimages.whiteLogo : Appimages.logo1,
                width: isSmallScreen ? 42 : 50,
                height: isSmallScreen ? 42 : 50,
                fit: BoxFit.contain,
              ),
            ),
            SizedBox(width: isSmallScreen ? 8 : 12),
            Semantics(
              child: Text(
                'app_name'.tr(),
                style: TextStyle(
                  fontSize: titleFontSize,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Oxanium',
                  color: isDarkMode ? Colors.white : Colors.black,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: padding,
                vertical: isLandscape ? padding : padding * 2),
            child: isLandscape
                ? _buildLandscapeLayout(
                    theme, isDarkMode, screenSize, isSmallScreen, padding)
                : _buildPortraitLayout(
                    theme, isDarkMode, screenSize, isSmallScreen, padding),
          ),
        ),
      ),
    );
  }

  Widget _buildPortraitLayout(ThemeData theme, bool isDarkMode, Size screenSize,
      bool isSmallScreen, double padding) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 20),
        _buildConnectedUserCard(theme),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: screenSize.width > 600 ? 600 : screenSize.width,
              ),
              child: _buildServiceCards(
                  isDarkMode, theme, isSmallScreen, screenSize),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLandscapeLayout(ThemeData theme, bool isDarkMode,
      Size screenSize, bool isSmallScreen, double padding) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Connection status on the left
        SizedBox(
          width: screenSize.width * 0.3,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildConnectedUserCard(theme),
            ],
          ),
        ),

        // Services grid on the right
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: screenSize.width > 800 ? 700 : screenSize.width * 0.7,
                maxHeight: screenSize.height,
              ),
              child: _buildServiceCards(
                  isDarkMode, theme, isSmallScreen, screenSize),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConnectedUserCard(ThemeData theme) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        constraints: const BoxConstraints(maxWidth: 500),
        child: const HelperConnectionStatus(),
      ),
    );
  }

  Widget _buildServiceCards(
      bool isDarkMode, ThemeData theme, bool isSmallScreen, Size screenSize) {
    final gridPadding = isSmallScreen ? 8.0 : 10.0;
    final gridSpacing = isSmallScreen ? 10.0 : 20.0;
    // ignore: unused_local_variable
    final isLandscape = screenSize.width > screenSize.height;
    final crossAxisCount = isSmallScreen
        ? 2
        : screenSize.width > 600
            ? 3
            : 2;

    return GridView.count(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.all(gridPadding),
      crossAxisCount: crossAxisCount,
      crossAxisSpacing: gridSpacing,
      mainAxisSpacing: gridSpacing,
      children: [
        _buildServiceCard(
          title: 'sensors'.tr(),
          icon: Icons.sensors,
          color: Colors.green.shade600,
          isDarkMode: isDarkMode,
          theme: theme,
          isSmallScreen: isSmallScreen,
          onTap: () {
            _sendDataToFirebase('sensors');
            if (mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SensorScreen(),
                ),
              );
            }
          },
        ),
        _buildServiceCard(
          title: 'navigation'.tr(),
          icon: Icons.navigation_rounded,
          color: Colors.blue.shade600,
          isDarkMode: isDarkMode,
          theme: theme,
          isSmallScreen: isSmallScreen,
          onTap: () {
            _sendDataToFirebase('navigation');
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const LocationSenderScreen(),
              ),
            );
          },
        ),
          _buildServiceCard(
          title: 'reminders'.tr(),
          icon: Icons.alarm_rounded,
          color: Colors.amber.shade700,
          isDarkMode: isDarkMode,
          theme: theme,
          isSmallScreen: isSmallScreen,
          onTap: () {
            _sendDataToFirebase('reminders');
            if (mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const BlindReminderScreen(),
                ),
              );
            }
          },
        ),
      
        _buildServiceCard(
          title: 'video_call'.tr(),
          icon: Icons.videocam,
          color: Colors.indigo.shade600,
          isDarkMode: isDarkMode,
          theme: theme,
          isSmallScreen: isSmallScreen,
          onTap: () async {
            // First check if connected to a helper
            final connectionManager =
                Provider.of<ConnectionManager>(context, listen: false);
            if (!connectionManager.isConnected) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('connect_to_helper_first'.tr()),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }

            _sendDataToFirebase('video_call');

            try {
              // Get user details
              final authProvider =
                  Provider.of<AuthProvider>(context, listen: false);
              final userId = authProvider.currentUserId;

              if (userId != null && connectionManager.connectedUserId != null) {
                // Debug connection information
                debugPrint(
                    "📋 Connection status: connected=${connectionManager.isConnected}");
                debugPrint(
                    "📋 Connected user ID: ${connectionManager.connectedUserId}");
                debugPrint("📋 Chat room ID: ${connectionManager.chatRoomId}");
                debugPrint("📋 Current user ID: $userId");

                // Verify that we're connected to the correct helper
                final bool isCorrectHelper =
                    await _verifyCorrectHelperConnection(
                        authProvider, connectionManager);
                if (!isCorrectHelper) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('wrong_helper_connection'.tr()),
                      backgroundColor: Colors.red,
                      action: SnackBarAction(
                        label: 'fix'.tr(),
                        onPressed: () async {
                          await _fixHelperConnection(
                              authProvider, connectionManager);
                        },
                      ),
                    ),
                  );
                  return;
                }

                // Check if the helper exists in the helpers collection or users collection
                bool helperFound = false;
                String helperName = _connectedUser ?? 'helper'.tr();
                DocumentSnapshot? helperDoc;

                // First try the helpers collection
                helperDoc = await FirebaseFirestore.instance
                    .collection('helpers')
                    .doc(connectionManager.connectedUserId)
                    .get();
                debugPrint(
                    "📋 Checked helpers collection: exists=${helperDoc.exists}");

                if (helperDoc.exists) {
                  helperFound = true;
                  final data = helperDoc.data() as Map<String, dynamic>?;
                  if (data != null && data['displayName'] != null) {
                    helperName = data['displayName'] as String;
                    debugPrint(
                        "📞 Using helper name from helpers collection: $helperName");
                  }
                  debugPrint("📋 Helper document data: ${data.toString()}");
                } else {
                  // If not found in helpers collection, try users collection
                  helperDoc = await FirebaseFirestore.instance
                      .collection('users')
                      .doc(connectionManager.connectedUserId)
                      .get();
                  debugPrint(
                      "📋 Checked users collection: exists=${helperDoc.exists}");

                  if (helperDoc.exists) {
                    helperFound = true;
                    final data = helperDoc.data() as Map<String, dynamic>?;
                    if (data != null && data['displayName'] != null) {
                      helperName = data['displayName'] as String;
                      debugPrint(
                          "📞 Using helper name from users collection: $helperName");
                    }
                    debugPrint("📋 Helper document data: ${data.toString()}");
                  }
                }

                if (!helperFound) {
                  debugPrint(
                      "❌ Helper account not found in any collection: ${connectionManager.connectedUserId}");

                  // Try to repair the connection
                  await _repairConnection(connectionManager);

                  // Check if repair was successful
                  if (!connectionManager.isConnected) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('helper_not_found'.tr()),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                }

                // Create video call service
                final videoCallService = VideoCallService();

                // Start video call
                await videoCallService.initiateCall(
                  context,
                  userId,
                  connectionManager.connectedUserId!,
                  helperName,
                );

                debugPrint(
                    "✅ Video call initiated successfully from blind home screen");

                // Provide feedback to the user
                if (mounted) {
                
                }
              }
            } catch (e) {
              debugPrint('❌ Error starting video call: $e');
              if (mounted) {
            
              }
            }
          },
        ),
        _buildServiceCard(
          title: 'chat'.tr(),
          icon: Icons.chat_bubble_outline_rounded,
          color: Colors.blue.shade600,
          isDarkMode: isDarkMode,
          theme: theme,
          isSmallScreen: isSmallScreen,
          onTap: () {
            _sendDataToFirebase('chat');
            if (mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const BlindChatScreen(),
                ),
              );
            }
          },
        ),
        _buildServiceCard(
          title: 'emergency'.tr(),
          icon: Icons.call_rounded,
          color: Colors.red.shade600,
          isDarkMode: isDarkMode,
          theme: theme,
          isSmallScreen: isSmallScreen,
          onTap: () {
            _sendDataToFirebase('emergency');
            if (mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const EmergencyScreen(),
                ),
              );
            }
          },
        ),
        _buildServiceCard(
          title: 'paper_scanner'.tr(),
          icon: Icons.document_scanner_rounded,
          color: Colors.purple.shade600,
          isDarkMode: isDarkMode,
          theme: theme,
          isSmallScreen: isSmallScreen,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const BlindPaperScannerScreen(),
              ),
            );
          },
        ),
        _buildServiceCard(
          title: 'currency_detector'.tr(),
          icon: Icons.currency_exchange,
          color: Colors.teal.shade600,
          isDarkMode: isDarkMode,
          theme: theme,
          isSmallScreen: isSmallScreen,
          onTap: () {
            if (mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const BlindCurrencyDetectorScreen(),
                ),
              );
            }
          },
        ),
      ],
    );
  }

  Widget _buildServiceCard({
    required String title,
    required IconData icon,
    required Color color,
    required bool isDarkMode,
    required ThemeData theme,
    required bool isSmallScreen,
    required VoidCallback onTap,
  }) {
    final iconSize = isSmallScreen ? 42.0 : 60.0;
    final fontSize = isSmallScreen ? 18.0 : 22.0;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color, color.withOpacity(0.8)],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(height: isSmallScreen ? 8 : 16),
              Icon(icon, size: iconSize, color: Colors.white),
              SizedBox(height: isSmallScreen ? 8 : 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _verifyCorrectHelperConnection(
      AuthProvider authProvider, ConnectionManager connectionManager) async {
    debugPrint("🔍 Verifying correct helper connection...");

    try {
      // Get the linked helper ID from AuthProvider
      final String? linkedHelperId = authProvider.linkedUserId;
      debugPrint("🔍 AuthProvider linked helper ID: $linkedHelperId");
      debugPrint(
          "🔍 ConnectionManager connected user ID: ${connectionManager.connectedUserId}");

      // Check if the IDs match
      if (linkedHelperId != null &&
          connectionManager.connectedUserId != null &&
          linkedHelperId == connectionManager.connectedUserId) {
        debugPrint("✅ Helper connection verified: connected to correct helper");
        return true;
      }

      // If we reach here, there's a mismatch
      debugPrint(
          "❌ Helper connection mismatch: AuthProvider and ConnectionManager have different helpers");
      return false;
    } catch (e) {
      debugPrint("❌ Error verifying helper connection: $e");
      return false;
    }
  }

  Future<void> _repairConnection(ConnectionManager connectionManager) async {
    debugPrint("🔧 Attempting to repair connection...");

    try {
      // Force check connection status
      await connectionManager.checkConnectionStatus();
      debugPrint(
          "🔧 Connection status after repair attempt: isConnected=${connectionManager.isConnected}");

      if (connectionManager.isConnected &&
          connectionManager.connectedUserId != null) {
        // Try to force bidirectional connection
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        if (authProvider.isLinkedWithUser) {
          final success = await authProvider.forceBidirectionalConnection();
          debugPrint("🔧 Forced bidirectional connection result: $success");
        }

        // Update the local _connectedUser variable
        await _checkConnectedUser();
      }
    } catch (e) {
      debugPrint("❌ Error repairing connection: $e");
    }
  }

  Future<void> _fixHelperConnection(AuthProvider authProvider, ConnectionManager connectionManager) async {
    debugPrint("🔧 Fixing helper connection...");

    try {
      // First, refresh the linked user data from Firestore
      await authProvider.refreshLinkedUser();
      
      // Get the linked helper ID from AuthProvider
      final String? linkedHelperId = authProvider.linkedUserId;

      if (linkedHelperId != null) {
        // Force bidirectional connection first to ensure both sides are properly linked
        final bidirectionalSuccess = await authProvider.forceBidirectionalConnection();
        debugPrint("✅ Forced bidirectional connection result: $bidirectionalSuccess");
        
        // Force update the connection manager to use the correct helper
        await connectionManager.connectToUser(linkedHelperId);
        debugPrint("✅ Connected to helper via ConnectionManager: $linkedHelperId");
        
        // Force ConnectionManager to update its state
        await connectionManager.checkConnectionStatus();
        debugPrint("✅ Connection status after fix: isConnected=${connectionManager.isConnected}");
        
        // Update local state
        await _checkConnectedUser();

        // Notify user
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('connection_fixed'.tr()),
              backgroundColor: Colors.green,
            ),
          );
        }

        debugPrint("✅ Helper connection fixed");
      } else {
        // Try to recover from SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        final storedLinkedUserId = prefs.getString('linked_user_id');
        
        if (storedLinkedUserId != null && storedLinkedUserId.isNotEmpty) {
          debugPrint("🔍 Found linked helper ID in SharedPreferences: $storedLinkedUserId");
          
          // Set the linked user ID in AuthProvider
          await authProvider.manuallySetLinkedUser(storedLinkedUserId);
          
          // Now try to fix the connection again with the recovered ID
          await connectionManager.connectToUser(storedLinkedUserId);
          await authProvider.forceBidirectionalConnection();
          await connectionManager.checkConnectionStatus();
          
          // Update local state
          await _checkConnectedUser();
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('connection_restored_from_backup'.tr()),
                backgroundColor: Colors.green,
              ),
            );
          }
          
          debugPrint("✅ Helper connection restored from backup");
        } else {
          debugPrint("❌ Cannot fix helper connection: no linked helper in AuthProvider or SharedPreferences");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('cannot_fix_connection'.tr()),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint("❌ Error fixing helper connection: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${'error_fixing_connection'.tr()}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
