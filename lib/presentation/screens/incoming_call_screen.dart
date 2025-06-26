import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';

class IncomingCallScreen extends StatefulWidget {
  final String callerName;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const IncomingCallScreen({
    super.key,
    required this.callerName,
    required this.onAccept,
    required this.onReject,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  final FlutterTts _tts = FlutterTts();
  bool _isAccepting = false;

  @override
  void initState() {
    super.initState();
    _announceIncomingCall();
    Vibration.vibrate(duration: 700);
    debugPrint('📱 IncomingCallScreen: Showing for caller ${widget.callerName}');
  }

  void _announceIncomingCall() async {
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.48);
    await _tts.speak("Incoming video call from ${widget.callerName}. "
        "Swipe right to accept, swipe left to reject.");
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  void _handleAccept() {
    if (_isAccepting) return;
    
    setState(() {
      _isAccepting = true;
    });
    
    debugPrint('📱 IncomingCallScreen: Call accepted for ${widget.callerName}');
    _tts.speak("Accepting call");
    
    // Add a short delay to ensure UI updates before calling onAccept
    Future.delayed(const Duration(milliseconds: 500), () {
      widget.onAccept();
    });
  }
  
  void _handleReject() {
    debugPrint('📱 IncomingCallScreen: Call rejected for ${widget.callerName}');
    _tts.speak("Rejecting call");
    widget.onReject();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          if (_isAccepting) return;
          
          if (details.primaryVelocity != null && details.primaryVelocity! > 0) {
            _handleAccept();
          } else if (details.primaryVelocity != null && details.primaryVelocity! < 0) {
            _handleReject();
          }
        },
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Semantics(
                label: 'Incoming call from ${widget.callerName}',
                child: Icon(Icons.call, color: Colors.green, size: 80),
              ),
              SizedBox(height: 24),
              Text(
                _isAccepting ? 'Connecting...' : 'Incoming video call from',
                style: TextStyle(color: Colors.white, fontSize: 24),
              ),
              SizedBox(height: 12),
              Text(
                widget.callerName,
                style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 32),
              _isAccepting 
                ? CircularProgressIndicator(color: Colors.green)
                : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Semantics(
                      label: 'Accept call',
                      button: true,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          shape: CircleBorder(),
                          padding: EdgeInsets.all(24),
                        ),
                        onPressed: _handleAccept,
                        child: Icon(Icons.call, color: Colors.white, size: 32),
                      ),
                    ),
                    SizedBox(width: 40),
                    Semantics(
                      label: 'Reject call',
                      button: true,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          shape: CircleBorder(),
                          padding: EdgeInsets.all(24),
                        ),
                        onPressed: _handleReject,
                        child: Icon(Icons.call_end, color: Colors.white, size: 32),
                      ),
                    ),
                  ],
                ),
              SizedBox(height: 24),
              if (!_isAccepting)
              Text(
                'Swipe right to accept, left to reject',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              )
            ],
          ),
        ),
      ),
    );
  }
}
