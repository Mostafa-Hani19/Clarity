// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';
import '../../../../providers/auth_provider.dart';
import '../../../../services/connection_manager.dart';

class BlindConnectionScreen extends StatefulWidget {
  const BlindConnectionScreen({super.key});

  @override
  State<BlindConnectionScreen> createState() => _BlindConnectionScreenState();
}

class _BlindConnectionScreenState extends State<BlindConnectionScreen> {
  bool _isLoading = false;
  String? _blindUserCode;
  String? _helperName;
  bool _isConnected = false;
  
  @override
  void initState() {
    super.initState();
    _fetchBlindUserCode();
  }
  
  Future<void> _fetchBlindUserCode() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final connectionManager = Provider.of<ConnectionManager>(context, listen: false);
      
      // Get connection status
      _isConnected = connectionManager.isConnected;
      
      // Fetch blind user data from Firestore
      final userData = await _fetchUserData(authProvider.currentUserId!);
      if (userData != null) {
        setState(() {
          _blindUserCode = userData['userCode'] as String?;
        });
        
        // If we don't have a code yet, generate one and save it
        if (_blindUserCode == null) {
          await _generateAndSaveUserCode();
        }
      }
      
      // If connected, try to get helper name
      if (_isConnected && connectionManager.connectedUserId != null) {
        final helperData = await _fetchUserData(connectionManager.connectedUserId!);
        if (helperData != null) {
          setState(() {
            _helperName = helperData['displayName'] as String? ?? 'Helper';
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching blind user code: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<Map<String, dynamic>?> _fetchUserData(String userId) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      if (doc.exists) {
        return doc.data();
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching user data: $e');
      return null;
    }
  }
  
  Future<void> _generateAndSaveUserCode() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.currentUserId;
      if (userId == null) return;
      
      // Generate a 6-digit code
      final code = _generateRandomCode();
      
      // Save to Firestore
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'userCode': code,
        'isBlindUser': true,
      });
      
      setState(() {
        _blindUserCode = code;
      });
      
      debugPrint('Generated and saved new user code: $code');
    } catch (e) {
      debugPrint('Error generating user code: $e');
    }
  }
  
  String _generateRandomCode() {
    return (100000 + Random().nextInt(900000)).toString();
  }
  
  void _copyCodeToClipboard() {
    if (_blindUserCode == null) return;
    
    Clipboard.setData(ClipboardData(text: _blindUserCode!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Code copied to clipboard'),
        duration: Duration(seconds: 1),
      ),
    );
  }
  
  Future<void> _disconnectHelper() async {
    // Show a confirmation dialog first
    final bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Disconnection'),
        content: const Text(
          'Are you sure you want to disconnect? This will remove the helper\'s permanent access to assist you. You\'ll need to share your code again to reconnect.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('DISCONNECT', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ) ?? false;
    
    if (!confirm) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      final connectionManager = Provider.of<ConnectionManager>(context, listen: false);
      await connectionManager.disconnect(userInitiated: true);
      
      setState(() {
        _isConnected = false;
        _helperName = null;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Disconnected from helper'),
          backgroundColor: Colors.blue,
        ),
      );
    } catch (e) {
      debugPrint('Error disconnecting: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error disconnecting: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connection Status'),
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Status Card
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Icon(
                            _isConnected ? Icons.check_circle : Icons.person_outline,
                            color: _isConnected ? Colors.green : Colors.blue,
                            size: 60,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _isConnected 
                                ? 'Connected to Helper' 
                                : 'Not Connected',
                            style: Theme.of(context).textTheme.titleLarge!.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (_isConnected && _helperName != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                'Helper: $_helperName',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Connection Code Card
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Your Connection Code',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Share this code with your helper to connect',
                            style: TextStyle(color: Colors.grey, fontSize: 14),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _blindUserCode ?? 'Loading code...',
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 8,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _copyCodeToClipboard,
                            icon: const Icon(Icons.copy),
                            label: const Text('Copy Code'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 50),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  const Spacer(),
                  
                  // Connection hint text
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.blue),
                            SizedBox(width: 8),
                            Text(
                              'How Connection Works',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Once a helper connects using your code, they will remain permanently connected until you explicitly disconnect them. This maintains your connection even through app restarts and network issues.',
                        ),
                        if (_isConnected)
                          Padding(
                            padding: const EdgeInsets.only(top: 16.0),
                            child: OutlinedButton(
                              onPressed: _disconnectHelper,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                                minimumSize: const Size(double.infinity, 50),
                              ),
                              child: const Text('Disconnect Helper'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
} 