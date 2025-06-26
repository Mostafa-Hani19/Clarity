// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:math';
import '../../../../providers/auth_provider.dart';
import '../../../../services/connection_manager.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class BlindUserProfileScreen extends StatefulWidget {
  const BlindUserProfileScreen({super.key});

  @override
  State<BlindUserProfileScreen> createState() => _BlindUserProfileScreenState();
}

class _BlindUserProfileScreenState extends State<BlindUserProfileScreen> {
  bool _isCopied = false;
  StreamSubscription<DocumentSnapshot>? _connectionStatusSubscription;
  bool _isConnected = false;
  bool _isLoading = false;
  String? _connectedHelperName;
  String? _blindUserCode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupConnectionStatusListener();
      _fetchBlindUserCode();
    });
  }

  @override
  void dispose() {
    _connectionStatusSubscription?.cancel();
    super.dispose();
  }

  void _setupConnectionStatusListener() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.currentUserId;
    if (userId == null) return;

    setState(() {
      _isConnected = authProvider.isLinkedWithUser;
    });

    _connectionStatusSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      final data = snapshot.data();
      if (snapshot.exists && data != null) {
        final linkedUserId = data['linkedUserId'] as String?;
        setState(() {
          _isConnected = linkedUserId != null && linkedUserId.isNotEmpty;
          _connectedHelperName = null; // Reset helper name
        });
        if (linkedUserId != null && _isConnected) {
          _fetchHelperName(linkedUserId);
        }
      }
    });
  }

  Future<void> _fetchBlindUserCode() async {
    setState(() => _isLoading = true);
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.currentUserId;
      if (userId == null) return;
      final doc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      if (!mounted) return;
      final data = doc.data();
      if (data != null) {
        _blindUserCode = data['userCode'] as String?;
        if (_blindUserCode == null) {
          await _generateAndSaveUserCode(userId);
        }
      }
    } catch (e) {
      debugPrint('Error fetching blind user code: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _generateAndSaveUserCode(String userId) async {
    try {
      final code = _generateRandomCode();
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'userCode': code,
        'isBlindUser': true,
      });
      if (!mounted) return;
      setState(() {
        _blindUserCode = code;
      });
      debugPrint('Generated and saved new user code: $code');
    } catch (e) {
      debugPrint('Error generating user code: $e');
    }
  }

  String _generateRandomCode() => (100000 + Random().nextInt(900000)).toString();

  Future<void> _disconnectHelper() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Disconnection'),
        content: const Text(
          'Are you sure you want to disconnect? This will remove the helper\'s permanent access. You\'ll need to share your code again to reconnect.'
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('CANCEL')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('DISCONNECT', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final connectionManager = Provider.of<ConnectionManager>(context, listen: false);
      await connectionManager.disconnect(userInitiated: true);
      setState(() => _isConnected = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Disconnected from helper'), backgroundColor: Colors.blue));
    } catch (e) {
      debugPrint('Error disconnecting: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error disconnecting: $e'), backgroundColor: Colors.red));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchHelperName(String helperId) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(helperId).get();
      if (!mounted) return;
      final data = doc.data();
      String helperName = data?['displayName'] ?? data?['name'] ?? data?['email'] ?? 'Unknown helper';
      setState(() => _connectedHelperName = helperName);
    } catch (e) {
      debugPrint('Error fetching helper name: $e');
      if (mounted) setState(() => _connectedHelperName = 'Unknown helper');
    }
  }

  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    setState(() => _isCopied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _isCopied = false);
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 1)));
  }

  Future<void> _shareUserId(String userId) async {
    await Share.share('Connect with me on Clarity! My User ID is: $userId', subject: 'Connect with me on Clarity');
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final authProvider = Provider.of<AuthProvider>(context);
    final userId = authProvider.currentUserId;
    final userName = authProvider.user?.displayName ?? 'User';
    final userEmail = authProvider.user?.email ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.all(size.width * 0.05),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(height: size.height * 0.02),
                      const CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.blue,
                        child: Icon(Icons.person, size: 50, color: Colors.white),
                      ),
                      SizedBox(height: size.height * 0.02),
                      Text(userName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      if (userEmail.isNotEmpty)
                        Text(userEmail, style: TextStyle(fontSize: 16, color: Colors.grey.shade700)),
                      SizedBox(height: size.height * 0.04),
                      _sectionTitle('Your User ID'),
                      const Text('Share this ID with sighted helpers so they can connect with you', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey)),
                      SizedBox(height: size.height * 0.02),
                      _idCard(userId, _copyToClipboard, _shareUserId),
                      SizedBox(height: size.height * 0.04),
                      _connectionCodeCard(_blindUserCode, _copyToClipboard),
                      SizedBox(height: size.height * 0.04),
                      _connectionStatusCard(_isConnected, _connectedHelperName, _disconnectHelper),
                      SizedBox(height: size.height * 0.04),
                      _howConnectionWorksCard(),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  // Widgets refactored for reusability & cleaner code

  Widget _sectionTitle(String title) =>
      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold));

  Widget _idCard(String? userId, Function(String) onCopy, Function(String) onShare) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.shade200),
        ),
        child: Column(
          children: [
            SelectableText(userId ?? 'Not available', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.2), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: userId != null ? () => onCopy(userId) : null,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                  icon: Icon(_isCopied ? Icons.check : Icons.copy),
                  label: Text(_isCopied ? 'Copied' : 'Copy ID'),
                ),
                const SizedBox(width: 20),
                ElevatedButton.icon(
                  onPressed: userId != null ? () => onShare(userId) : null,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                  icon: const Icon(Icons.share),
                  label: const Text('Share ID'),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _connectionCodeCard(String? code, Function(String) onCopy) => Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('Your Connection Code'),
              const SizedBox(height: 8),
              const Text('Share this code with your helper to connect', style: TextStyle(color: Colors.grey, fontSize: 14)),
              const SizedBox(height: 16),
              Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
                child: Text(code ?? 'Loading code...', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 8)),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: code != null ? () => onCopy(code) : null,
                icon: const Icon(Icons.copy),
                label: const Text('Copy Code'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50)),
              ),
            ],
          ),
        ),
      );

  Widget _connectionStatusCard(bool isConnected, String? helperName, VoidCallback onDisconnect) => Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('Connection Status'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(isConnected ? Icons.check_circle : Icons.info, color: isConnected ? Colors.green : Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isConnected ? 'Connected with a helper' : 'Not connected with any helper',
                      style: TextStyle(fontSize: 16, color: isConnected ? Colors.green : Colors.orange),
                    ),
                  ),
                ],
              ),
              if (isConnected && helperName != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text('Connected with: $helperName', style: const TextStyle(fontSize: 14)),
                ),
              if (isConnected)
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: OutlinedButton(
                    onPressed: onDisconnect,
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red), minimumSize: const Size(double.infinity, 50)),
                    child: const Text('Disconnect Helper'),
                  ),
                ),
            ],
          ),
        ),
      );

  Widget _howConnectionWorksCard() => Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('How Connection Works'),
              const SizedBox(height: 8),
              const Text(
                'Once a helper connects using your code, they will remain permanently connected until you explicitly disconnect them. This maintains your connection even through app restarts and network issues.',
              ),
              const SizedBox(height: 16),
              _buildHowToItem('1', 'Share your 6-digit Connection Code'),
              _buildHowToItem('2', 'Send it to a sighted helper'),
              _buildHowToItem('3', 'Helper enters your code in their app'),
              _buildHowToItem('4', 'You\'ll receive assistance immediately'),
            ],
          ),
        ),
      );

  Widget _buildHowToItem(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
            child: Center(child: Text(number, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 16))),
        ],
      ),
    );
  }
}
