import 'package:clarity/home/presentation/screens/helper/helper_chat_screen.dart';
import 'package:clarity/home/presentation/screens/helper/helper_setting_screen.dart';
import 'package:clarity/services/connection_manager.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../../../../models/images.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../routes/app_router.dart';
import '../../../../services/video_call_service.dart';
import 'helper_location_screen.dart';
import 'helper_sensors_screen.dart';
import 'helper_reminder_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';
import 'package:easy_localization/easy_localization.dart';
import 'helper_person_upload_screen.dart';

class HelperHomeScreen extends StatefulWidget {
  const HelperHomeScreen({super.key});
  @override
  State<HelperHomeScreen> createState() => _HelperHomeScreenState();
}

class _HelperHomeScreenState extends State<HelperHomeScreen> {
  String? _connectedUser;
  bool _isLoading = false;
  StreamSubscription<DocumentSnapshot>? _connectionStatusSubscription;
  StreamSubscription<Map<String, dynamic>?>? _callSubscription;
  StreamSubscription<QuerySnapshot>? _emergencyAlertSubscription;
  final VideoCallService _videoCallService = VideoCallService();
  bool _isIncomingCallDialogShowing = false;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupConnectionStatusListener();
      _setupIncomingCallListener();
      _setupEmergencyAlertListener();
    });
  }

  @override
  void dispose() {
    _connectionStatusSubscription?.cancel();
    _callSubscription?.cancel();
    _emergencyAlertSubscription?.cancel();
    super.dispose();
  }

  void _setupIncomingCallListener() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.currentUserId;
    if (userId != null) {
      debugPrint('🔄 Setting up incoming call listener for helper with ID: $userId');
      
      // First check if there are any pending calls
      FirebaseFirestore.instance
          .collection('calls')
          .where('receiverId', isEqualTo: userId)
          .where('isActive', isEqualTo: true)
          .where('status', isEqualTo: 'ringing')
          .get()
          .then((snapshot) {
            if (snapshot.docs.isNotEmpty) {
              debugPrint('📞 Found pending calls during startup: ${snapshot.docs.length}');
              final callDoc = snapshot.docs.first;
              final callData = callDoc.data();
              final callId = callDoc.id;
              final callerId = callData['callerId'] as String? ?? '';
              final callerName = callData['callerName'] as String? ?? 'Blind User';
              
              if (callerId.isNotEmpty && mounted) {
                debugPrint('📞 Processing pending call from $callerName (ID: $callerId)');
                
                // Convert to the format expected by _showIncomingCallDialog
                final formattedCallData = {
                  'callId': callId,
                  'callerId': callerId,
                  'callerName': callerName,
                  ...callData,
                };
                
                _showIncomingCallDialog(formattedCallData);
              }
            } else {
              debugPrint('📞 No pending calls found during startup for helper: $userId');
            }
          });
      
      // Set up listener for new incoming calls
      _callSubscription =
          _videoCallService.getIncomingCallsStream(userId).listen((callData) {
        if (callData != null && mounted) {
          debugPrint('📞 Incoming call detected in stream listener!');
          _showIncomingCallDialog(callData);
        }
      }, onError: (error) {
        debugPrint('❌ Error in call listener: $error');
      });
      
      debugPrint('✅ Incoming call listener setup complete for helper: $userId');
    }
  }

  void _showIncomingCallDialog(Map<String, dynamic> callData) {
    final callId = callData['callId'];
    final callerId = callData['callerId'];
    final callerName = callData['callerName'] as String? ?? 'Blind User';

    debugPrint('🔔 Attempting to show incoming call dialog for: $callerName, Call ID: $callId');
    debugPrint('📞 Call data received: ${callData.toString()}');

    if (!mounted || _isIncomingCallDialogShowing) {
      debugPrint('⚠️ Already showing incoming call dialog or screen unmounted. Skipping.');
      return;
    }

    setState(() {
      _isIncomingCallDialogShowing = true;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Incoming Video Call'),
        content: Text(
            '$callerName is calling you for assistance. Would you like to answer?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _videoCallService.rejectCall(callId);
              setState(() {
                _isIncomingCallDialogShowing = false;
              });
            },
            child: const Text('Decline', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              
              _videoCallService.acceptCall(callId);
              debugPrint('📞 Helper accepted call with ID: $callId, navigating to video call screen');
              
              AppRouter.navigateToVideoCall(context,
                  callID: callId,
                  targetUserID: callerId,
                  targetUserName: callerName,
                  isOutgoing: false);
              setState(() {
                _isIncomingCallDialogShowing = false;
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Answer', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ).then((_) {
      if (mounted) {
        setState(() {
          _isIncomingCallDialogShowing = false;
        });
      }
    });
  }

  void _setupConnectionStatusListener() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.currentUserId;
    if (userId == null) return;

    final isAuthorizedUser = authProvider.user != null;
    final collectionPath = isAuthorizedUser ? 'users' : 'helpers';

    _connectionStatusSubscription = FirebaseFirestore.instance
        .collection(collectionPath)
        .doc(userId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        final data = snapshot.data();
        if (data != null) {
          final linkedUserId = data['linkedUserId'] as String?;
          final bool isConnected =
              linkedUserId != null && linkedUserId.isNotEmpty;
          if (linkedUserId != authProvider.linkedUserId) {
            if (linkedUserId != null) {
              authProvider.manuallySetLinkedUser(linkedUserId);
            }
          }
          if (isConnected) {
            _fetchConnectedUserName(linkedUserId);
          } else if (!isConnected) {
            setState(() => _connectedUser = null);
          }
        }
      }
    }, onError: (error) {
      debugPrint('Error in connection status listener: $error');
    });
  }

  Future<void> _fetchConnectedUserName(String blindUserId) async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(blindUserId)
          .get();

      if (userDoc.exists && userDoc.data() != null) {
        final userData = userDoc.data()!;
        final userName = userData['displayName'] ??
            userData['name'] ??
            userData['email'] ??
            'Blind User';

        if (mounted) {
          setState(() => _connectedUser = userName);
        }
      } else {
        if (mounted) {
          setState(() => _connectedUser = 'Blind User');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _connectedUser = 'Blind User');
      }
    }
  }

  Future<void> _disconnectFromUser() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final BuildContext currentContext = context;
    final ScaffoldMessengerState scaffoldContext =
        ScaffoldMessenger.of(currentContext);

    showDialog(
      context: currentContext,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Disconnect from Blind User'),
        content: const Text(
          'Are you sure you want to disconnect? You will no longer be connected with this blind user.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);

              setState(() => _isLoading = true);
              final success = await authProvider.unlinkConnectedUser();

              if (mounted) {
                setState(() {
                  _isLoading = false;
                  if (success) {
                    _connectedUser = null;
                  }
                });

                scaffoldContext.showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? 'Successfully disconnected'
                          : 'Failed to disconnect. Please try again.',
                    ),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
  }

  Future<void> _fixConnectionWithBlindUser() async {
    setState(() => _isLoading = true);
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      if (!authProvider.isLinkedWithUser) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No blind user is connected. Please connect first.'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
        return;
      }

      final success = await authProvider.forceBidirectionalConnection();
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connection has been fixed!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not fix connection. Try reconnecting.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _setupEmergencyAlertListener() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.currentUserId;
    if (userId == null) return;

    _emergencyAlertSubscription = FirebaseFirestore.instance
        .collection('emergencyAlerts')
        .where('linkedUserId', isEqualTo: userId)
        .where('status', isEqualTo: 'active')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .listen((snapshot) {
      debugPrint('Emergency alert listener triggered.');
      if (snapshot.docs.isNotEmpty && mounted) {
        final emergencyAlertData = snapshot.docs.first.data();
        final emergencyAlertId = snapshot.docs.first.id;
        final bool viewedByHelper = emergencyAlertData['viewedByHelper'] ?? false;
        debugPrint('Alert ID: $emergencyAlertId, Viewed: $viewedByHelper');

        if (!viewedByHelper) {
          debugPrint('Showing emergency alert dialog and notification.');
          _showEmergencyAlertDialog(context, emergencyAlertId);
          _showEmergencyNotification(emergencyAlertId);
        } else {
          debugPrint('Alert already viewed, not navigating.');
        }
      } else {
        debugPrint('No active emergency alerts found or screen unmounted.');
      }
    }, onError: (error) {
      debugPrint('Error in emergency alert listener: $error');
    });
  }

  void _showEmergencyAlertDialog(BuildContext context, String emergencyAlertId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('emergency_alert_exclamation'.tr(), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        content: Text('blind_user_sent_emergency_alert'.tr()),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              AppRouter.navigateToHelperEmergency(context, emergencyAlertId: emergencyAlertId);
            },
            child: Text('view_alert'.tr(), style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _showEmergencyNotification(String emergencyAlertId) async {
    if (await Vibration.hasVibrator() == true) {
      Vibration.vibrate(pattern: [0, 500, 200, 500]);
    }

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'emergency_channel',
      'emergency_alerts'.tr(),
      channelDescription: 'emergency_alerts_description'.tr(),
      importance: Importance.max,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
      fullScreenIntent: true,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'view_alert',
          'view_alert'.tr(),
          showsUserInterface: true,
        ),
      ],
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      0,
      'emergency_alert_exclamation'.tr(),
      'blind_user_needs_assistance'.tr(),
      platformChannelSpecifics,
      payload: emergencyAlertId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);

    return Scaffold(
      // Drawer يظهر الإعدادات الجاهزة
      drawer: Drawer(
        child: SafeArea(
          child: HelperSettingScreen(), 
        ),
      ),
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.green.shade900 : Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: isDarkMode
                        ? Colors.green.shade900.withOpacity(0.3)
                        : Colors.green.shade200.withOpacity(0.6),
                    blurRadius: 12,
                    spreadRadius: 1,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: isDarkMode
                  ? Image.asset(Appimages.whiteLogo, fit: BoxFit.contain)
                  : Image.asset(Appimages.logo1, fit: BoxFit.contain),
            ),
            const SizedBox(width: 14),
            Text(
              'app_name'.tr(),
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                fontFamily: 'Oxanium',
                color: isDarkMode ? Colors.white : Colors.black,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
      ),
      body: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 22),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_connectedUser != null) ...[
                          _buildConnectedUserCard(theme),
                          const SizedBox(height: 24),
                        ] else ...[
                          _buildConnectCard(theme),
                          const SizedBox(height: 24),
                        ],
                        Expanded(
                          child: Center(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                int crossAxisCount = 2;
                                if (constraints.maxWidth > 700) {
                                  crossAxisCount = 3;
                                }
                                if (constraints.maxWidth > 1100) {
                                  crossAxisCount = 4;
                                }
                                return _buildServiceCards(
                                    context, crossAxisCount);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildConnectCard(ThemeData theme) {
    final mainColor = Colors.green;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        constraints: const BoxConstraints(maxWidth: 480),
        child: Card(
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: [mainColor.withOpacity(0.15), Colors.white],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.connect_without_contact,
                      color: mainColor, size: 36),
                  const SizedBox(height: 10),
                  Text('Not Connected',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  Text(
                    'Connect with a blind user to provide assistance',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: Colors.grey[700]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          AppRouter.navigateToHelperConnect(context),
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Connect with Blind User'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: mainColor,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(44),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConnectedUserCard(ThemeData theme) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        constraints: const BoxConstraints(maxWidth: 480),
        child: Card(
          elevation: 6,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: [Colors.green.shade50, Colors.white],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.green.shade600,
                    radius: 23,
                    child: Icon(Icons.person, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Text(
                              'Connected',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green),
                            ),
                            SizedBox(width: 4),
                            Icon(Icons.check_circle,
                                color: Colors.green, size: 16),
                          ],
                        ),
                        Text(
                          _connectedUser ?? 'Blind User',
                          style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold, fontSize: 19),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _fixConnectionWithBlindUser,
                    icon: Icon(Icons.sync_problem,
                        color: Colors.orange.shade700, size: 22),
                    tooltip: 'Fix Connection',
                  ),
                  IconButton(
                    onPressed: _disconnectFromUser,
                    icon:
                        Icon(Icons.close, color: Colors.red.shade400, size: 22),
                    tooltip: 'Disconnect',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildServiceCards(BuildContext context, int crossAxisCount) {
    final authProvider = Provider.of<AuthProvider>(context);
    final connected = _connectedUser != null;
    return GridView(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
        childAspectRatio: 1.06,
      ),
      shrinkWrap: true,
      physics: const BouncingScrollPhysics(),
      children: [
        _buildServiceCard(
          title: 'sensors'.tr(),
          icon: Icons.sensors,
          color: Colors.green.shade600,
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (c) => const HelperSensorsScreen())),
          enabled: true,
        ),
        _buildServiceCard(
          title: 'video_call'.tr(),
          icon: Icons.videocam_rounded,
          color: Colors.purple.shade600,
          onTap: connected
              ? () async {
                  final connectionManager =
                      Provider.of<ConnectionManager>(context, listen: false);
                  if (connectionManager.isConnected &&
                      connectionManager.connectedUserId != null) {
                    await VideoCallService().initiateCall(
                      context,
                      authProvider.currentUserId!,
                      connectionManager.connectedUserId!,
                      _connectedUser!,
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Connection not available. Please reconnect with the blind user.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              : null,
          enabled: connected,
        ),
        _buildServiceCard(
          title: 'chat'.tr(),
          icon: Icons.chat_bubble_outline_rounded,
          color: Colors.blue.shade600,
          onTap: connected
              ? () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (c) => const HelperChatScreen()))
              : null,
          enabled: connected,
        ),
        _buildServiceCard(
          title: 'reminders'.tr(),
          icon: Icons.notifications_active_rounded,
          color: Colors.amber.shade700,
          onTap: connected
              ? () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (c) => const HelperReminderScreen()))
              : null,
          enabled: connected,
        ),
        _buildServiceCard(
          title: 'navigation'.tr(),
          icon: Icons.location_on_rounded,
          color: Colors.deepPurple.shade600,
          onTap: connected
              ? () {
                  final blindUserId = authProvider.linkedUserId;
                  if (blindUserId != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (c) => HelperLocationScreen(
                          blindUserId: blindUserId,
                          blindUserName: _connectedUser!,
                        ),
                      ),
                    );
                  }
                }
              : null,
          enabled: connected,
        ),
        // _buildServiceCard(
        //   title: 'person_upload'.tr(),
        //   icon: Icons.person_add_rounded,
        //   color: Colors.teal.shade600,
        //   onTap: () => Navigator.push(
        //       context,
        //       MaterialPageRoute(
        //           builder: (c) => const HelperPersonUploadScreen())),
        //   enabled: true,
        // ),
        _buildServiceCard(
          title: 'emergency'.tr(),
          icon: Icons.emergency_rounded,
          color: Colors.red.shade600,
          onTap: null,
          enabled: connected,
        ),
      ],
    );
  }

  Widget _buildServiceCard({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
    bool enabled = true,
  }) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled ? 1 : 0.33,
      child: Card(
        elevation: enabled ? 7 : 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(18),
          splashColor: color.withOpacity(0.14),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color.withOpacity(0.96),
                  color.withOpacity(0.75),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.08),
                  blurRadius: 14,
                  spreadRadius: 2,
                  offset: const Offset(2, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 48, color: Colors.white),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
