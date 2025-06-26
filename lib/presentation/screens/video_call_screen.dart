import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/video_call_service.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'incoming_call_screen.dart';
import 'package:zego_uikit/zego_uikit.dart';

class VideoCallScreen extends StatefulWidget {
  final String callID;
  final String targetUserID;
  final String targetUserName;
  final bool isOutgoing;

  const VideoCallScreen({
    super.key,
    required this.callID,
    required this.targetUserID,
    required this.targetUserName,
    this.isOutgoing = false,
  });

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen>
    with WidgetsBindingObserver {
  final FlutterTts _flutterTts = FlutterTts();
  final VideoCallService _callService = VideoCallService();
  bool _permissionsGranted = false;
  String _errorMessage = '';
  bool _isCallEnded = false;
  bool _isCallConnected = false;
  bool _showIncomingCallScreen = false;
  Timer? _callTimeoutTimer;
  Timer? _callDurationTimer;
  int _callDurationSeconds = 0;
  StreamSubscription? _callStatusSubscription;
  bool _isBlindUser = false;
  bool _isZegoUikitReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
    _initializeTTS();
    _initializeUserType();
    if (widget.isOutgoing) _announceCallStatus();
    _setupCallMonitoring();
    Vibration.vibrate(duration: 250);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.isOutgoing) _startCallTimeoutTimer();
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() {
            _isZegoUikitReady = true;
          });
        }
      });
    });
  }

  void _initializeUserType() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _isBlindUser = authProvider.isBlindUser;
    debugPrint('User is blind: $_isBlindUser');
  }

  void _setupCallMonitoring() {
    debugPrint('🔄 Setting up call monitoring for Call ID: ${widget.callID}');
    _callStatusSubscription = FirebaseFirestore.instance
        .collection('calls')
        .doc(widget.callID)
        .snapshots()
        .listen((snapshot) async {
      if (!snapshot.exists) {
        _handleCallEnded();
        return;
      }
      final data = snapshot.data();
      if (data == null) return;
      final String status = data['status'] as String? ?? '';
      final bool isActive = data['isActive'] as bool? ?? false;
      
      debugPrint('📞 Call status updated: $status, isActive: $isActive');
      
      if (!widget.isOutgoing &&
          status == 'ringing' &&
          !_isCallConnected &&
          !_showIncomingCallScreen) {
        setState(() => _showIncomingCallScreen = true);
      }
      
      // Handle both 'connected' and 'accepted' statuses
      if ((status == 'connected' || status == 'accepted') && !_isCallConnected) {
        debugPrint('📞 Call connected! Updating UI and starting timers.');
        
        // When the call is accepted, ensure we update to 'connected' status for both parties
        if (status == 'accepted' && widget.isOutgoing) {
          // If this is the outgoing call and we see 'accepted', update to 'connected'
          try {
            await FirebaseFirestore.instance
                .collection('calls')
                .doc(widget.callID)
                .update({
              'status': 'connected',
              'updatedAt': FieldValue.serverTimestamp(),
            });
            debugPrint('📞 Updated call status to connected');
          } catch (e) {
            debugPrint('❌ Error updating call status to connected: $e');
          }
        }
        
        setState(() {
          _isCallConnected = true;
          _showIncomingCallScreen = false;
        });
        
        _callTimeoutTimer?.cancel();
        _startCallDurationTimer();
        
        if (_isBlindUser) {
          _speak('Call connected.');
        } else {
          _speak('Call connected with ${widget.targetUserName}');
        }
      }
      
      if (!isActive || status == 'ended' || status == 'rejected') {
        _handleCallEnded();
      }
    });
  }

  void _startCallTimeoutTimer() {
    _callTimeoutTimer = Timer(const Duration(seconds: 45), () {
      if (!_isCallConnected && mounted) {
        if (_isBlindUser) {
          _speak('Call not answered. Returning to home screen.');
        } else {
          _speak('Call not answered. Ending call.');
        }
        _handleCallEnded();
      }
    });
  }

  void _startCallDurationTimer() {
    _callDurationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _callDurationSeconds++;
        });
      }
    });
  }

  Future<void> _checkPermissions() async {
    debugPrint('🎥 Checking camera and microphone permissions');
    final camera = await Permission.camera.request();
    final microphone = await Permission.microphone.request();
    
    debugPrint('📸 Camera permission: ${camera.isGranted}');
    debugPrint('🎤 Microphone permission: ${microphone.isGranted}');
    
    setState(() {
      _permissionsGranted = camera.isGranted && microphone.isGranted;
      if (!_permissionsGranted) {
        _errorMessage =
            'Camera and microphone permissions are required for video calls.';
        debugPrint('❌ Permission denied: $_errorMessage');
      } else {
        debugPrint('✅ All permissions granted');
      }
    });
  }

  Future<void> _initializeTTS() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  Future<void> _speak(String text) async {
    await _flutterTts.speak(text);
  }

  void _announceCallStatus() {
    Future.delayed(const Duration(milliseconds: 800), () {
      if (widget.isOutgoing) {
        if (_isBlindUser) {
          _speak("Calling ${widget.targetUserName}. Please wait for assistant to answer.");
        } else {
          _speak("Calling ${widget.targetUserName}. Please wait.");
        }
      } else {
        if (_isBlindUser) {
          _speak("Connected with ${widget.targetUserName}.");
        } else {
          _speak("Connected with ${widget.targetUserName}.");
        }
      }
    });
  }

  void _handleCallEnded() async {
    if (_isCallEnded) return;
    _isCallEnded = true;
    await _callService.endActiveCall(widget.callID);
    Future.delayed(const Duration(seconds: 3), () async {
      await FirebaseFirestore.instance
          .collection('calls')
          .doc(widget.callID)
          .delete();
    });
    _callTimeoutTimer?.cancel();
    _callDurationTimer?.cancel();
    _callStatusSubscription?.cancel();
    if (_isBlindUser) {
      _speak('Call ended. Returning to home screen.');
    } else {
      _speak('Call ended');
    }
    Vibration.vibrate(duration: 150);
    if (mounted) setState(() {});
  }

  String _formatCallDuration() {
    final minutes = (_callDurationSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_callDurationSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final currentUser = authProvider.user;

    if (_isCallEnded) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.call_end, color: Colors.red, size: 64),
              const SizedBox(height: 24),
              const Text('Call Ended',
                  style: TextStyle(color: Colors.white, fontSize: 24)),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _exitCallScreen,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: const Text('Return to Home',
                    style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      );
    }

    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Video Call Error')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("User not logged in. Please sign in to make calls."),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _exitCallScreen,
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_permissionsGranted) {
      return Scaffold(
        appBar: AppBar(title: const Text('Permission Required')),
        body: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.videocam_off, size: 80, color: Colors.red),
              const SizedBox(height: 20),
              Text(_errorMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () async {
                  await _checkPermissions();
                  if (!_permissionsGranted) {
                    await openAppSettings();
                  }
                },
                child: const Text('Grant Permissions'),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () {
                  _handleCallEnded();
                  _exitCallScreen();
                },
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    if (_showIncomingCallScreen && !_isCallConnected) {
      return IncomingCallScreen(
        callerName: widget.targetUserName,
        onAccept: () async {
          debugPrint('📱 Call accepted in VideoCallScreen, updating status to accepted');
          
          // First update to 'accepted'
          await FirebaseFirestore.instance
              .collection('calls')
              .doc(widget.callID)
              .update({
                'status': 'accepted',
                'updatedAt': FieldValue.serverTimestamp(),
              });
          
          // Wait a brief moment to ensure both sides see the update
          await Future.delayed(const Duration(milliseconds: 500));
          
          // Then update to 'connected' to ensure both sides enter the call
          await FirebaseFirestore.instance
              .collection('calls')
              .doc(widget.callID)
              .update({
                'status': 'connected',
                'updatedAt': FieldValue.serverTimestamp(),
              });
          
          debugPrint('📱 Call status updated to connected');
          
          setState(() {
            _showIncomingCallScreen = false;
            _isCallConnected = true;
          });
        },
        onReject: () async {
          await FirebaseFirestore.instance
              .collection('calls')
              .doc(widget.callID)
              .update({'status': 'rejected', 'isActive': false});
          _handleCallEnded();
        },
      );
    }

    final callConfig = ZegoUIKitPrebuiltCallConfig.oneOnOneVideoCall()
      ..turnOnCameraWhenJoining = true
      ..turnOnMicrophoneWhenJoining = true
      ..useSpeakerWhenJoining = true
      ..avatarBuilder = null // Ensure we always show video view even before connection
      ..audioVideoViewConfig = ZegoPrebuiltAudioVideoViewConfig(
        foregroundBuilder: (context, size, user, extraInfo) {
          return user != null && user.id == currentUser.uid
              ? Positioned(
                  right: 10,
                  bottom: 80,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _callDurationSeconds > 0
                          ? _formatCallDuration()
                          : 'Connecting...',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                )
              : const SizedBox();
        },
      )
      ..bottomMenuBarConfig = ZegoBottomMenuBarConfig(
        buttons: [
          ZegoMenuBarButtonName.toggleCameraButton,
          ZegoMenuBarButtonName.toggleMicrophoneButton,
          ZegoMenuBarButtonName.switchCameraButton,
          ZegoMenuBarButtonName.switchAudioOutputButton,
        ],
      );

    debugPrint('📞 Joining call with ID: ${widget.callID}, user: ${currentUser.uid}, display name: ${currentUser.displayName ?? "User"}');

    return WillPopScope(
      onWillPop: () async {
        _handleCallEnded();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            if (_isZegoUikitReady)
            ZegoUIKitPrebuiltCall(
              appID: 1293173730,
              appSign:
                  "",
              userID: currentUser.uid,
              userName: (currentUser.displayName != null &&
                      currentUser.displayName!.isNotEmpty)
                  ? currentUser.displayName!
                  : "User",
              callID: widget.callID,
              config: callConfig,
              onDispose: () {
                debugPrint('📞 ZegoUIKit: Call widget disposed');
                
                // Handle error code 0 assertion manually here
                try {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _handleCallEnded();
                  });
                } catch (e) {
                  debugPrint('Error in dispose handling: $e');
                }
              },
              plugins: const [], // Keep plugins empty to avoid additional assertions
              )
            else
              const Center(child: CircularProgressIndicator(color: Colors.white)),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.black.withOpacity(0.5),
                padding: const EdgeInsets.only(top: 40, bottom: 10),
                child: Column(
                  children: [
                    Text(
                      widget.isOutgoing && !_isCallConnected
                          ? 'Calling ${widget.targetUserName}...'
                          : 'In call with ${widget.targetUserName}',
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    if (_callDurationSeconds > 0)
                      Text(
                        _formatCallDuration(),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 50,
              left: 0,
              right: 0,
              child: Center(
                child: Semantics(
                  label: 'End call',
                  button: true,
                  child: GestureDetector(
                    onTap: () {
                      _handleCallEnded();
                      _exitCallScreen();
                    },
                    child: Container(
                      width: 70,
                      height: 70,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.call_end,
                          color: Colors.white, size: 34),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _flutterTts.stop();
    _callTimeoutTimer?.cancel();
    _callDurationTimer?.cancel();
    _callStatusSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _exitCallScreen() {
    if (!mounted) return;
    _callService.endActiveCall(widget.callID);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (authProvider.isBlindUser) {
        context.go('/home');
      } else {
        context.go('/helper-home');
      }
    });
  }
}
