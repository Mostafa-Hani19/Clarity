import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../routes/app_router.dart';
import 'package:go_router/go_router.dart';

class ConnectWithBlindScreen extends StatefulWidget {
  const ConnectWithBlindScreen({super.key});

  @override
  State<ConnectWithBlindScreen> createState() => _ConnectWithBlindScreenState();
}

class _ConnectWithBlindScreenState extends State<ConnectWithBlindScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController(); // For helper name input
  bool _isLoading = false;
  String? _errorMessage;
  String? _connectedUser;

  @override
  void initState() {
    super.initState();
    _checkLinkedUser();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _checkLinkedUser() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    if (authProvider.isLinkedWithUser) {
      setState(() => _isLoading = true);
      
      final linkedUserDetails = await authProvider.getLinkedUserDetails();
      if (mounted) {
        setState(() {
          _connectedUser = linkedUserDetails?['displayName'] ?? linkedUserDetails?['email'];
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _connectWithBlindUser() async {
    if (!_formKey.currentState!.validate()) return;

    final code = _codeController.text.trim();
    final helperName = _nameController.text.trim();
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    // Set a display name for the helper (even without authentication)
    if (helperName.isNotEmpty) {
      await authProvider.setHelperName(helperName);
    }
    
    try {
      final success = await authProvider.linkWithBlindUser(code);

      if (mounted) {
        if (success) {
          // Ensure bidirectional connection is properly established
          await authProvider.forceBidirectionalConnection();
          
          // Connection successful, reload information
          await _checkLinkedUser();
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Successfully connected with blind user'),
              backgroundColor: Colors.green,
            ),
          );
          
          // Redirect to helper home screen
          context.go(AppRouter.helperHome);
        } else {
          setState(() {
            _isLoading = false;
            // Convert error codes to user-friendly messages
            String errorMsg = authProvider.errorMessage ?? 'Failed to connect with blind user';
            
            if (errorMsg.contains('blind_user_not_found')) {
              errorMsg = 'The ID you entered does not match any blind user. Please check and try again.';
            } else if (errorMsg.contains('not_a_blind_user')) {
              errorMsg = 'The ID you entered is not for a blind user. Please check with the user.';
            } else if (errorMsg.contains('not-found')) {
              errorMsg = 'Connection failed. The blind user ID may be invalid or no longer exists.';
            } else if (errorMsg.contains('permission-denied')) {
              errorMsg = 'Connection failed due to permission issues. Please try again.';
            } else if (errorMsg.contains('network')) {
              errorMsg = 'Connection failed due to network issues. Please check your internet connection.';
            }
            
            _errorMessage = errorMsg;
          });
          
          // Show a more visible error message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Connection failed: $_errorMessage'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Connection error: ${e.toString()}';
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection error: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _disconnectFromBlindUser() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect from Blind User'),
        content: const Text(
          'Are you sure you want to disconnect? You will no longer be able to assist them through the app.',
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
                
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? 'Successfully disconnected from blind user'
                          : 'Failed to disconnect. Please try again.',
                    ),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect With Blind User'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            context.go(AppRouter.welcome);
          },
        ),
      ),
      body: Container(
        color: Colors.green.shade50,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _isLoading
                ? const CircularProgressIndicator()
                : _connectedUser != null
                    ? _buildConnectedView()
                    : _buildConnectionForm(),
          ),
        ),
      ),
    );
  }

  Widget _buildConnectedView() {
    // Auto-navigate to home screen after a short delay
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _connectedUser != null) {
        context.go(AppRouter.helperHome);
      }
    });
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Colors.green.shade300,
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle,
              color: Colors.green,
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              'Connected',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You are connected with $_connectedUser',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'You can now assist them through the app. You\'ll receive notifications when they need assistance.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            
            // Go to Home button
            ElevatedButton.icon(
              onPressed: () {
                context.go(AppRouter.helperHome);
              },
              icon: const Icon(Icons.home),
              label: const Text('Go to Home'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Disconnect button
            ElevatedButton.icon(
              onPressed: _disconnectFromBlindUser,
              icon: const Icon(Icons.link_off),
              label: const Text('Disconnect'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Connect with a Blind User',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Enter the code provided by the blind user or scan their QR code',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 24),
        
        // Card with input field and connect button
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Input field for blind user code
                  TextFormField(
                    controller: _codeController,
                    decoration: InputDecoration(
                      hintText: 'Enter Blind User Code',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      prefixIcon: const Icon(Icons.person_outline),
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter the connection code';
                      }
                      return null;
                    },
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Helper name input is now handled as an internal step to simplify UI
                  if (_nameController.text.isEmpty) ...[
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        hintText: 'Your Name (for identification)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        prefixIcon: const Icon(Icons.person),
                        contentPadding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  // Connect button
                  ElevatedButton.icon(
                    onPressed: _connectWithBlindUser,
                    icon: const Icon(Icons.link),
                    label: const Text('Connect'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  
                  // Error message
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: Colors.red.shade700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        const Text(
          'OR',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        
        // Scan QR code button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              // TODO: Implement QR code scanning
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('QR code scanning coming soon')),
              );
            },
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan QR Code'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        
        const SizedBox(height: 32),
        
        // How it works section
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How it works:',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: 12),
            _InstructionStep(
              number: 1,
              text: 'The blind user will share their connection code with you',
            ),
            _InstructionStep(
              number: 2,
              text: 'Enter the code above or scan their QR code',
            ),
            _InstructionStep(
              number: 3,
              text: 'Once connected, you will be able to help them navigate',
            ),
            _InstructionStep(
              number: 4,
              text: 'You can see their location and can send them destinations',
            ),
          ],
        ),
      ],
    );
  }
}

// Helper widget for instruction steps
class _InstructionStep extends StatelessWidget {
  final int number;
  final String text;
  
  const _InstructionStep({
    required this.number,
    required this.text,
  });
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
} 