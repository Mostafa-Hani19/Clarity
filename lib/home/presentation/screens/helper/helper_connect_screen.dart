import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../../../../services/connection_manager.dart';
import '../../../../providers/auth_provider.dart';

class HelperConnectScreen extends StatefulWidget {
  const HelperConnectScreen({super.key});

  @override
  State<HelperConnectScreen> createState() => _HelperConnectScreenState();
}

class _HelperConnectScreenState extends State<HelperConnectScreen> {
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _isConnected = false;
  String? _connectedUserCode;

  @override
  void initState() {
    super.initState();
    _checkExistingConnection();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _checkExistingConnection() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final connectionManager =
          Provider.of<ConnectionManager>(context, listen: false);
      final savedCode = await connectionManager.getSavedBlindCode();

      if (savedCode != null) {
        setState(() {
          _isConnected = connectionManager.isConnected;
          _connectedUserCode = savedCode;
          _codeController.text = savedCode;
        });
      }
    } catch (e) {
      debugPrint('Error checking existing connection: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _connectWithCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a valid code';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final connectionManager =
          Provider.of<ConnectionManager>(context, listen: false);
      final success = await connectionManager.connectUsingBlindCode(code);

      if (success) {
        setState(() {
          _isConnected = true;
          _connectedUserCode = code;
          _errorMessage = null;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Successfully connected to blind user'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pushReplacementNamed('/helper_chat');
        }
      } else {
        setState(() {
          _errorMessage = 'Invalid code or user not found';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _disconnectFromUser() async {
    final bool confirm = await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirm Disconnection'),
            content: const Text(
              'Are you sure you want to disconnect from this blind user? You\'ll need their code again to reconnect.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('CANCEL'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text(
                  'DISCONNECT',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final connectionManager =
          Provider.of<ConnectionManager>(context, listen: false);
      await connectionManager.disconnect(userInitiated: true);

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      await authProvider.unlinkConnectedUser(userInitiated: true);

      setState(() {
        _isConnected = false;
        _connectedUserCode = null;
        _codeController.clear();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Disconnected from blind user'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: ${e.toString()}';
      });
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
        title: const Text('Connect to Blind User'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_isConnected) ...[
                              const Icon(
                                Icons.check_circle_outline,
                                color: Colors.green,
                                size: 80,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'You are connected to a blind user',
                                style: Theme.of(context).textTheme.titleLarge,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Code: ${_connectedUserCode ?? "Unknown"}',
                                style: Theme.of(context).textTheme.bodyLarge,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 24),
                              OutlinedButton(
                                onPressed: _disconnectFromUser,
                                style: OutlinedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                ),
                                child: const Text(
                                  'Disconnect',
                                  style: TextStyle(fontSize: 16),
                                ),
                              ),
                            ] else ...[
                              const Icon(
                                Icons.person_outline,
                                color: Colors.blue,
                                size: 80,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Connect to a Blind User',
                                style: Theme.of(context).textTheme.titleLarge,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 24),
                              const Text(
                                'Enter the code provided by the blind user:',
                                style: TextStyle(fontSize: 16),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _codeController,
                                decoration: InputDecoration(
                                  hintText: 'Enter blind user code',
                                  border: const OutlineInputBorder(),
                                  filled: true,
                                  errorText: _errorMessage,
                                ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(6),
                                ],
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontSize: 20, letterSpacing: 8),
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton(
                                onPressed: _connectWithCode,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                ),
                                child: const Text(
                                  'Connect',
                                  style: TextStyle(
                                      fontSize: 16, color: Colors.white),
                                ),
                              ),
                              const SizedBox(height: 24),
                              const Card(
                                child: Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: Column(
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.info_outline,
                                              color: Colors.blue),
                                          SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Permanent Connection System',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        'Once connected, you will remain permanently connected to the blind user until they explicitly disconnect you. This allows you to assist them at any time, even after app restarts or network issues.',
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            const Spacer(),
                          ],
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
