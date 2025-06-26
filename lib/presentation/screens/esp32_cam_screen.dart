import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

class ESP32CamScreen extends StatefulWidget {
  const ESP32CamScreen({Key? key}) : super(key: key);

  @override
  State<ESP32CamScreen> createState() => _ESP32CamScreenState();
}

class _ESP32CamScreenState extends State<ESP32CamScreen> {
  String _streamUrl = '';
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isFullScreen = false;
  bool _isFlashOn = false;
  String _currentIp = '';
  
  // WebView controller
  late WebViewController _webViewController;
  bool _isWebViewReady = false;
  
  // For timer-based image refresh (fallback)
  Timer? _refreshTimer;
  Uint8List? _imageBytes;
  bool _isLoadingImage = false;
  int _refreshRate = 500; // milliseconds
  bool _useTimerRefresh = false;
  
  final TextEditingController _ipController = TextEditingController();
  final List<String> _recentConnections = [];
  
  @override
  void initState() {
    super.initState();
    _loadRecentConnections();
    _initWebView();
  }
  
  void _initWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            setState(() {
              _isWebViewReady = true;
            });
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('WebView error: ${error.description}');
            // Fall back to timer refresh if web view fails
            if (_isConnected && !_useTimerRefresh) {
              setState(() {
                _useTimerRefresh = true;
              });
              _startImageRefresh();
            }
          },
        ),
      );
  }
  
  Future<void> _loadRecentConnections() async {
    final prefs = await SharedPreferences.getInstance();
    final recentIps = prefs.getStringList('esp32_recent_ips') ?? [];
    
    setState(() {
      _recentConnections.addAll(recentIps);
      
      // If there's a recent connection, pre-fill the field
      if (recentIps.isNotEmpty) {
        _ipController.text = recentIps.first;
      }
    });
  }
  
  Future<void> _saveRecentConnection(String ip) async {
    if (!_recentConnections.contains(ip)) {
      _recentConnections.insert(0, ip);
      
      // Limit to 5 recent connections
      if (_recentConnections.length > 5) {
        _recentConnections.removeLast();
      }
      
      // Save to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('esp32_recent_ips', _recentConnections);
    } else {
      // Move to top if already exists
      _recentConnections.remove(ip);
      _recentConnections.insert(0, ip);
      
      // Save the reordered list
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('esp32_recent_ips', _recentConnections);
    }
    
    setState(() {});
  }

  @override
  void dispose() {
    _ipController.dispose();
    _stopImageRefresh();
    super.dispose();
  }
  
  void _stopImageRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }
  
  void _startImageRefresh() {
    _stopImageRefresh();
    
    // Start a timer that periodically refreshes the image
    _refreshTimer = Timer.periodic(Duration(milliseconds: _refreshRate), (timer) {
      if (!mounted) {
        _stopImageRefresh();
        return;
      }
      
      _fetchLatestImage();
    });
    
    // Fetch first image immediately
    _fetchLatestImage();
  }
  
  Future<void> _fetchLatestImage() async {
    if (_isLoadingImage || !mounted) return;
    
    setState(() {
      _isLoadingImage = true;
    });
    
    try {
      final response = await http.get(
        Uri.parse('$_streamUrl?_=${DateTime.now().millisecondsSinceEpoch}'),
      ).timeout(const Duration(seconds: 3));
      
      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _imageBytes = response.bodyBytes;
            _isLoadingImage = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoadingImage = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingImage = false;
        });
      }
      debugPrint('Error fetching image: $e');
    }
  }

  Future<bool> _checkConnection(String ip) async {
    setState(() {
      _isConnecting = true;
    });
    
    debugPrint('Attempting to connect to ESP32-CAM at IP: $ip');

    // First, check if it's a valid IP format
    if (!_isValidIpAddress(ip)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid IP address format')),
      );
      setState(() {
        _isConnecting = false;
      });
      return false;
    }

    try {
      // Show detailed connection information
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trying to connect to ESP32-CAM...')),
      );

      // Try different possible endpoints for ESP32-CAM
      final endpoints = [
        'http://$ip',                // Root endpoint
        'http://$ip/status',         // Status endpoint
        'http://$ip/stream',         // Stream endpoint
        'http://$ip:81/stream',      // Alternative port
        'http://$ip/jpg',            // Single image endpoint
        'http://$ip/cam',            // Alternative camera endpoint
        'http://$ip/capture',        // Capture endpoint
      ];
      
      for (final endpoint in endpoints) {
        try {
          debugPrint('Trying endpoint: $endpoint');
          final response = await http.get(Uri.parse(endpoint))
            .timeout(const Duration(seconds: 3));
          
          debugPrint('Response from $endpoint: ${response.statusCode}');
          
          if (response.statusCode == 200) {
            setState(() {
              _isConnecting = false;
            });
            return true;
          }
        } catch (e) {
          debugPrint('Error connecting to $endpoint: $e');
          // Try next endpoint
          continue;
        }
      }
      
      // Try a direct MJPEG stream connection
      try {
        final streamUrl = 'http://$ip:81/stream';
        final result = await _tryMjpegConnection(streamUrl);
        if (result) {
          setState(() {
            _isConnecting = false;
          });
          return true;
        }
      } catch (e) {
        debugPrint('Error testing MJPEG stream: $e');
      }
      
      // Try alternative stream without port
      try {
        final streamUrl = 'http://$ip/stream';
        final result = await _tryMjpegConnection(streamUrl);
        if (result) {
          setState(() {
            _isConnecting = false;
          });
          return true;
        }
      } catch (e) {
        debugPrint('Error testing alternative MJPEG stream: $e');
      }
      
      setState(() {
        _isConnecting = false;
      });
      
      debugPrint('All connection attempts failed');
      return false;
    } catch (e) {
      debugPrint('Connection error: $e');
      setState(() {
        _isConnecting = false;
      });
      return false;
    }
  }
  
  bool _isValidIpAddress(String ip) {
    // Basic IP address validation
    RegExp ipRegex = RegExp(
      r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$',
    );
    
    if (!ipRegex.hasMatch(ip)) return false;
    
    // Check each octet
    List<String> octets = ip.split('.');
    for (String octet in octets) {
      int value = int.parse(octet);
      if (value < 0 || value > 255) return false;
    }
    
    return true;
  }
  
  void _showConnectionTroubleshootingDialog(String ip) {
    // Only show on first connection attempt
    if (_recentConnections.isNotEmpty) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ESP32-CAM Connection Tips'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'If you are having trouble connecting to your ESP32-CAM, check these common issues:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _buildTip('Make sure ESP32-CAM and phone are on the same WiFi network'),
              _buildTip('Verify the ESP32-CAM IP address is correct (check your router)'),
              _buildTip('Make sure ESP32-CAM is powered properly (needs stable 5V)'),
              _buildTip('Try accessing "http://$ip" directly in a browser'),
              _buildTip('Check your ESP32-CAM firmware supports streaming'),
              _buildTip('Restart the ESP32-CAM if it has been running for a long time'),
              const SizedBox(height: 16),
              const Text(
                'Common ESP32-CAM firmware configurations:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              _buildTip('Default streaming endpoint: /stream or :81/stream'),
              _buildTip('Some firmware use port 81 for streaming'),
              _buildTip('Some cameras use /jpg for static image capture'),
            ],
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Close'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildTip(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
  
  Future<bool> _tryMjpegConnection(String url) async {
    try {
      debugPrint('Testing direct MJPEG connection to $url');
      final request = http.Request('GET', Uri.parse(url));
      final response = await http.Client().send(request).timeout(const Duration(seconds: 5));
      
      // Check if the response headers indicate a MJPEG stream
      final contentType = response.headers['content-type'];
      debugPrint('Content-Type: $contentType');
      
      if (contentType != null && 
          (contentType.contains('multipart/x-mixed-replace') || 
           contentType.contains('image/jpeg') ||
           contentType.contains('image/jpg'))) {
        debugPrint('Valid MJPEG stream detected');
        return true;
      }
      
      // Even if not specifically MJPEG, if we got a 200 OK, consider it valid
      if (response.statusCode == 200) {
        debugPrint('Got 200 response, treating as valid endpoint');
        return true;
      }
      
      return false;
    } catch (e) {
      debugPrint('MJPEG connection test error: $e');
      return false;
    }
  }

  Future<bool> _sendCommand(String command) async {
    try {
      if (_currentIp.isEmpty) {
        return false;
      }

      // Try common ESP32-CAM command formats
      final commandUrls = [
        'http://$_currentIp/$command',
        'http://$_currentIp/control?var=$command',
        'http://$_currentIp/cmd?$command',
      ];
      
      for (final url in commandUrls) {
        try {
          final response = await http.get(
            Uri.parse(url),
          ).timeout(const Duration(seconds: 2));
          
          if (response.statusCode == 200) {
            debugPrint('Command sent successfully using URL: $url');
            return true;
          }
        } catch (e) {
          // Try next URL format
          continue;
        }
      }

      debugPrint('All command URL formats failed');
      return false;
    } catch (e) {
      debugPrint('Error sending command to ESP32-CAM: $e');
      return false;
    }
  }
  
  Future<void> _toggleLED() async {
    // Try different command formats for toggling LED
    final commands = [
      _isFlashOn ? 'led?val=0' : 'led?val=1',
      _isFlashOn ? 'flash=0' : 'flash=1',
      _isFlashOn ? 'lamp=0' : 'lamp=1',
      _isFlashOn ? 'led=0' : 'led=1'
    ];
    
    bool success = false;
    
    for (final command in commands) {
      success = await _sendCommand(command);
      if (success) break;
    }
    
    if (success) {
      setState(() {
        _isFlashOn = !_isFlashOn;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Flash ${_isFlashOn ? 'enabled' : 'disabled'}'),
          duration: const Duration(seconds: 1),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to toggle flash'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }
  
  Future<void> _flipCamera() async {
    // Try different command formats for flipping camera
    final commands = [
      'flip',
      'hmirror',
      'flip_camera',
      'mirror'
    ];
    
    bool success = false;
    
    for (final command in commands) {
      success = await _sendCommand(command);
      if (success) break;
    }
    
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Camera flipped'),
          duration: Duration(seconds: 1),
        ),
      );
      
      // Force stream refresh
      setState(() {
        _streamUrl = '$_streamUrl?refresh=${DateTime.now().millisecondsSinceEpoch}';
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to flip camera'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }
  
  Future<void> _restartCamera() async {
    // Try different command formats for restarting camera
    final commands = [
      'restart',
      'reboot',
      'reset',
      'restart_camera'
    ];
    
    bool success = false;
    
    for (final command in commands) {
      success = await _sendCommand(command);
      if (success) break;
    }
    
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Restarting camera...'),
        ),
      );
      
      // Wait for camera to restart
      await Future.delayed(const Duration(seconds: 5));
      
      // Try to reconnect using the previously established working stream URL
      setState(() {
        _isConnected = false;
      });
      
      // Re-connect to camera
      _connectToCamera();
    } else {
      // Even if the command failed, try refreshing the stream
      setState(() {
        _streamUrl = '$_streamUrl?refresh=${DateTime.now().millisecondsSinceEpoch}';
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to restart camera, refreshing stream instead'),
        ),
      );
    }
  }
  
  void _connectToCamera() async {
    if (_ipController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an IP address')),
      );
      return;
    }

    final ip = _ipController.text.trim();
    final isConnected = await _checkConnection(ip);

    if (isConnected) {
      // Try alternative stream formats
      final streamUrls = [
        'http://$ip/stream',
        'http://$ip:81/stream',
        'http://$ip/mjpeg/1',
        'http://$ip/video',
        'http://$ip/camera',
      ];
      
      bool streamFound = false;
      String workingStreamUrl = '';
      
      // Display connecting message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trying to connect to camera stream...'))
      );
      
      for (final streamUrl in streamUrls) {
        try {
          final response = await http.get(Uri.parse(streamUrl))
            .timeout(const Duration(seconds: 2));
          
          if (response.statusCode == 200) {
            workingStreamUrl = streamUrl;
            streamFound = true;
            break;
          }
        } catch (e) {
          // Try next stream URL
          continue;
        }
      }
      
      // Show connection dialog with information about common issues
      _showConnectionTroubleshootingDialog(ip);
      
      if (streamFound) {
        setState(() {
          _streamUrl = workingStreamUrl;
          _isConnected = true;
          _currentIp = ip;
          _useTimerRefresh = false; // Use WebView by default
        });
        
        // Load the stream URL into WebView
        _webViewController.loadRequest(Uri.parse(workingStreamUrl));
      } else {
        // Try multiple stream URLs before giving up
        final possibleStreamUrls = [
          'http://$ip/stream',       // Standard stream URL
          'http://$ip:81/stream',    // Alt port stream URL
          'http://$ip/mjpeg/1',      // ESP32-CAM MJPEG stream
          'http://$ip/video',        // Alt video stream
          'http://$ip/jpg',          // Static JPG capture - will need timer refresh
        ];
        
        String bestStreamUrl = 'http://$ip/stream'; // Default fallback
        bool isStaticImage = false;
        
        // Show status message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Testing multiple stream URLs...')),
        );
        
        // Try each URL and pick the first that seems to work
        for (final url in possibleStreamUrls) {
          try {
            final request = http.Request('GET', Uri.parse(url));
            final response = await http.Client().send(request).timeout(const Duration(seconds: 2));
            
            if (response.statusCode == 200) {
              bestStreamUrl = url;
              // Check if it's a static image URL
              isStaticImage = url.contains('/jpg') || url.contains('/capture');
              debugPrint('Selected stream URL: $bestStreamUrl (Static: $isStaticImage)');
              break;
            }
          } catch (e) {
            continue; // Try next URL
          }
        }
        
        setState(() {
          _streamUrl = bestStreamUrl;
          _isConnected = true;
          _currentIp = ip;
          _useTimerRefresh = isStaticImage; // Use timer refresh for static images
          
          // Use a faster refresh rate for still images
          if (isStaticImage) {
            _refreshRate = 200; // Faster refresh for static images
            _startImageRefresh();
          } else {
            // Load the stream URL into WebView for dynamic streams
            _webViewController.loadRequest(Uri.parse(bestStreamUrl));
          }
        });
      }
      
      // Save this connection to recent list
      await _saveRecentConnection(ip);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to connect to ESP32-CAM')),
      );
    }
  }
  
  void _toggleFullScreen() {
    setState(() {
      _isFullScreen = !_isFullScreen;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isFullScreen && _isConnected) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: _toggleFullScreen,
          child: Stack(
            children: [
              Center(
                child: _useTimerRefresh 
                  ? (_imageBytes != null
                      ? Image.memory(
                          _imageBytes!,
                          fit: BoxFit.contain,
                          height: double.infinity,
                          width: double.infinity,
                          gaplessPlayback: true,
                        )
                      : const CircularProgressIndicator())
                  : WebViewWidget(
                      controller: _webViewController,
                    ),
              ),
              Positioned(
                top: 40,
                left: 20,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: _toggleFullScreen,
                ),
              ),
              // Add controls in fullscreen mode
              Positioned(
                bottom: 40,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FloatingActionButton(
                      heroTag: 'flip-fullscreen',
                      mini: true,
                      onPressed: _flipCamera,
                      child: const Icon(Icons.flip_camera_android),
                    ),
                    const SizedBox(width: 20),
                    FloatingActionButton(
                      heroTag: 'flash-fullscreen',
                      mini: true,
                      onPressed: _toggleLED,
                      child: Icon(_isFlashOn ? Icons.flash_on : Icons.flash_off),
                    ),
                    const SizedBox(width: 20),
                    FloatingActionButton(
                      heroTag: 'refresh-fullscreen',
                      mini: true,
                      onPressed: _useTimerRefresh ? _fetchLatestImage : () {
                        _webViewController.reload();
                      },
                      child: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Main screen UI
    return Scaffold(
      appBar: AppBar(
        title: const Text('ESP32-CAM Stream'),
        actions: _isConnected ? [
          IconButton(
            icon: const Icon(Icons.fullscreen),
            onPressed: _toggleFullScreen,
          ),
        ] : null,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _ipController,
              decoration: InputDecoration(
                labelText: 'ESP32-CAM IP Address',
                hintText: 'e.g., 192.168.1.100',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => _ipController.clear(),
                ),
              ),
              keyboardType: TextInputType.text,
            ),
            
            if (_recentConnections.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: _recentConnections.map((ip) => InputChip(
                  label: Text(ip),
                  onPressed: () {
                    _ipController.text = ip;
                  },
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () {
                    setState(() {
                      _recentConnections.remove(ip);
                    });
                    SharedPreferences.getInstance().then((prefs) {
                      prefs.setStringList('esp32_recent_ips', _recentConnections);
                    });
                  },
                  backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                  labelStyle: TextStyle(
                    color: Theme.of(context).primaryColor,
                  ),
                )).toList(),
              ),
            ],
            
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isConnecting ? null : _connectToCamera,
                    child: _isConnecting 
                      ? const CircularProgressIndicator()
                      : const Text('Connect to Camera'),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _runNetworkDiagnostics,
                  icon: const Icon(Icons.network_check),
                  label: const Text('Diagnostics'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber.shade700,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isConnected
                ? _buildStreamView()
                : const Center(
                    child: Text(
                      'Enter ESP32-CAM IP address and connect to view the stream',
                      textAlign: TextAlign.center,
                    ),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStreamView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: _buildStreamContent(),
              ),
              Positioned(
                bottom: 16,
                right: 16,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FloatingActionButton(
                      heroTag: 'fullscreen',
                      mini: true,
                      onPressed: _toggleFullScreen,
                      child: const Icon(Icons.fullscreen),
                    ),
                    const SizedBox(height: 8),
                    FloatingActionButton(
                      heroTag: 'flip',
                      mini: true,
                      onPressed: _flipCamera,
                      child: const Icon(Icons.flip_camera_android),
                    ),
                    const SizedBox(height: 8),
                    FloatingActionButton(
                      heroTag: 'flash',
                      mini: true,
                      onPressed: _toggleLED,
                      child: Icon(_isFlashOn ? Icons.flash_on : Icons.flash_off),
                    ),
                  ],
                ),
              ),
              if (_isConnected && !_isWebViewReady && !_useTimerRefresh)
                const Center(
                  child: CircularProgressIndicator(),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.info_outline, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Stream URL: $_streamUrl',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          Text(
                            'Stream Mode: ${_useTimerRefresh ? 'Timer Refresh' : 'WebView Stream'}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    if (_useTimerRefresh)
                      Switch(
                        value: _useTimerRefresh,
                        onChanged: (value) {
                          setState(() {
                            _useTimerRefresh = value;
                            if (value) {
                              _startImageRefresh();
                            } else {
                              _stopImageRefresh();
                              _webViewController.loadRequest(Uri.parse(_streamUrl));
                            }
                          });
                        },
                        activeTrackColor: Colors.lightGreenAccent,
                        activeColor: Colors.green,
                      ),
                  ],
                ),
                if (_useTimerRefresh) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.timer, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Refresh Rate: ${_refreshRate}ms',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            Slider(
                              value: _refreshRate.toDouble(),
                              min: 100,
                              max: 2000,
                              divisions: 19,
                              onChanged: (value) {
                                setState(() {
                                  _refreshRate = value.toInt();
                                });
                                
                                // Restart timer with new refresh rate
                                if (_isConnected && _useTimerRefresh) {
                                  _startImageRefresh();
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        if (_useTimerRefresh) {
                          _fetchLatestImage();
                        } else {
                          _webViewController.reload();
                        }
                      },
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Refresh'),
                    ),
                    ElevatedButton.icon(
                      onPressed: _restartCamera,
                      icon: const Icon(Icons.restart_alt, size: 18),
                      label: const Text('Restart'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        _stopImageRefresh();
                        setState(() {
                          _isConnected = false;
                          _streamUrl = '';
                          _isFlashOn = false;
                          _imageBytes = null;
                          _isWebViewReady = false;
                        });
                      },
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Disconnect'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildStreamContent() {
    if (!_isConnected) {
      return const Center(
        child: Text('Not connected to camera'),
      );
    }
    
    // Use WebView for streaming
    if (!_useTimerRefresh) {
      return WebViewWidget(controller: _webViewController);
    }
    
    // Use timer-based image refresh
    return _buildStreamImage();
  }
  
  Widget _buildStreamImage() {
    if (_imageBytes != null) {
      return Image.memory(
        _imageBytes!,
        fit: BoxFit.contain,
        gaplessPlayback: true,
      );
    }
    
    if (_isLoadingImage) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading stream...'),
          ],
        ),
      );
    }
    
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.videocam_off,
            color: Colors.grey,
            size: 48,
          ),
          const SizedBox(height: 16),
          const Text(
            'Stream not loaded',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Waiting for camera stream to connect...',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _fetchLatestImage,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Future<void> _runNetworkDiagnostics() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Running network diagnostics...')),
    );
    
    // Check if we have a valid IP address to test
    String targetIp = _ipController.text.trim();
    if (targetIp.isEmpty && _recentConnections.isNotEmpty) {
      targetIp = _recentConnections.first;
    }
    
    // Data to display in the diagnostics dialog
    String wifiName = 'Checking...';
    String wifiIP = 'Checking...';
    String internetStatus = 'Checking...';
    String targetStatus = 'Checking...';
    String commonSubnet = 'Checking...';
    
    // Show dialog with initial "checking" status
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.network_check, color: Colors.blue),
                const SizedBox(width: 8),
                const Text('Network Diagnostics'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDiagnosticRow('WiFi Network:', wifiName),
                  _buildDiagnosticRow('Your Device IP:', wifiIP),
                  _buildDiagnosticRow('Internet Connection:', internetStatus),
                  if (targetIp.isNotEmpty)
                    _buildDiagnosticRow('ESP32-CAM Reachable:', targetStatus),
                  if (targetIp.isNotEmpty && wifiIP.isNotEmpty && wifiIP != 'Checking...')
                    _buildDiagnosticRow('Same Network Subnet:', commonSubnet),
                  const SizedBox(height: 16),
                  const Text(
                    'Network Configuration Tips:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  _buildTip('ESP32-CAM must be on the same WiFi network as your phone'),
                  _buildTip('Your phone and ESP32-CAM should have the same subnet (e.g., 192.168.1.x)'),
                  _buildTip('Make sure WiFi network allows device-to-device communication'),
                  _buildTip('Some public WiFi networks block device communication'),
                  const SizedBox(height: 16),
                  const Text(
                    'Common ESP32-CAM IP ranges:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text('• 192.168.1.x - Home networks'),
                  Text('• 192.168.0.x - Some routers'),
                  Text('• 10.0.0.x - Some networks'),
                  Text('• 172.16.x.x - Some networks'),
                ],
              ),
            ),
            actions: [
              TextButton(
                child: const Text('Close'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          );
        },
      ),
    );
    
    // Perform actual network diagnostics in the background
    try {
              // Get WiFi information
        bool isWifiConnected = false;
        try {
          final connectivity = await Connectivity().checkConnectivity();
          isWifiConnected = connectivity == ConnectivityResult.wifi || 
                          (connectivity.contains(ConnectivityResult.wifi));
        } catch (e) {
          debugPrint('Error checking connectivity: $e');
        }
      
      final info = NetworkInfo();
      final String? name = await info.getWifiName();
      final String? ip = await info.getWifiIP();
      
      // Test internet connectivity
      bool hasInternet = false;
      try {
        final response = await http.get(Uri.parse('https://www.google.com'))
          .timeout(const Duration(seconds: 5));
        hasInternet = response.statusCode == 200;
      } catch (e) {
        hasInternet = false;
      }
      
      // Test ESP32-CAM connectivity if we have an IP
      bool canReachTarget = false;
      if (targetIp.isNotEmpty) {
        try {
          final response = await http.get(Uri.parse('http://$targetIp'))
            .timeout(const Duration(seconds: 3));
          canReachTarget = response.statusCode == 200;
        } catch (e) {
          canReachTarget = false;
        }
      }
      
      // Check if on same subnet
      String subnetStatus = 'Unknown';
      if (ip != null && targetIp.isNotEmpty) {
        final deviceSubnet = _getSubnet(ip);
        final targetSubnet = _getSubnet(targetIp);
        
        if (deviceSubnet != null && targetSubnet != null) {
          subnetStatus = deviceSubnet == targetSubnet
              ? 'Yes ✓'
              : 'No ✗ ($deviceSubnet vs $targetSubnet)';
        }
      }
      
      // Update the dialog with results
      if (context.mounted) {
        Navigator.of(context).pop(); // Close the current dialog
        
        // Show updated dialog with results
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.network_check, color: Colors.blue),
                const SizedBox(width: 8),
                const Text('Network Diagnostics'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDiagnosticRow('WiFi Network:', name?.replaceAll('"', '') ?? 'Unknown'),
                  _buildDiagnosticRow('Your Device IP:', ip ?? 'Unknown'),
                  _buildDiagnosticRow(
                    'Internet Connection:', 
                    hasInternet 
                      ? 'Connected ✓' 
                      : 'Not connected ✗'
                  ),
                  if (targetIp.isNotEmpty)
                    _buildDiagnosticRow(
                      'ESP32-CAM Reachable:', 
                      canReachTarget 
                        ? 'Reachable ✓' 
                        : 'Not reachable ✗'
                    ),
                  if (targetIp.isNotEmpty && ip != null)
                    _buildDiagnosticRow('Same Network Subnet:', subnetStatus),
                  const SizedBox(height: 16),
                  const Text(
                    'Diagnosis:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _buildDiagnosis(
                    hasInternet, 
                    canReachTarget, 
                    subnetStatus.contains('Yes')
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Test Direct URLs:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ElevatedButton(
                        onPressed: () => _testDirectStreamUrl(targetIp),
                        child: const Text('Test Direct Stream'),
                      ),
                      ElevatedButton(
                        onPressed: () => _testDirectStreamUrl(targetIp, port: '81'),
                        child: const Text('Test Port 81'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                child: const Text('Close'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('Error running diagnostics: $e');
      if (context.mounted) {
        Navigator.of(context).pop(); // Close dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Diagnostics error: $e')),
        );
      }
    }
  }
  
  String? _getSubnet(String ip) {
    final parts = ip.split('.');
    if (parts.length == 4) {
      return '${parts[0]}.${parts[1]}.${parts[2]}';
    }
    return null;
  }
  
  Widget _buildDiagnosticRow(String label, String value) {
    Color valueColor = Colors.black;
    
    if (value.contains('✓')) {
      valueColor = Colors.green;
    } else if (value.contains('✗')) {
      valueColor = Colors.red;
    }
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(
            value, 
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDiagnosis(
    bool hasInternet,
    bool canReachTarget,
    bool sameSubnet
  ) {
    final bool isWifiConnected = true; // Assume wifi is connected at this point
    List<Widget> diagnostics = [];
    
    // Check WiFi connectivity - assume we're connected at this point
    
    // Check internet connectivity
    if (!hasInternet) {
      diagnostics.add(
        Text('• WiFi connected but no internet. Check if WiFi is working properly.',
          style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))
      );
    }
    
    // Check ESP32-CAM reachability
    if (!canReachTarget) {
      diagnostics.add(
        Text('• Cannot reach ESP32-CAM. Verify IP and that ESP32-CAM is powered on.',
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))
      );
    }
    
    // Check subnet match
    if (!sameSubnet) {
      diagnostics.add(
        Text('• Different network subnets. ESP32-CAM must be on same network as phone.',
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))
      );
    }
    
    // All good
    if (canReachTarget && sameSubnet) {
      diagnostics.add(
        Text('• Network configuration looks good. Try connecting to the camera.',
          style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))
      );
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: diagnostics.isNotEmpty
        ? diagnostics
        : [Text('No issues found', style: TextStyle(color: Colors.green))],
    );
  }

  Future<void> _testDirectStreamUrl(String ip, {String? port}) async {
    if (ip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an IP address first')),
      );
      return;
    }
    
    final baseUrl = port != null ? 'http://$ip:$port' : 'http://$ip';
    
    final urls = [
      '$baseUrl/stream',
      '$baseUrl/mjpeg/1',
      '$baseUrl/video',
      '$baseUrl/jpg',
      '$baseUrl/camera'
    ];
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Testing direct URLs for $baseUrl...')),
    );
    
    bool anySuccess = false;
    String workingUrl = '';
    
    for (final url in urls) {
      try {
        debugPrint('Testing direct URL: $url');
        
        final request = http.Request('GET', Uri.parse(url));
        final response = await http.Client().send(request)
          .timeout(const Duration(seconds: 3));
          
        if (response.statusCode == 200) {
          debugPrint('Success with URL: $url (${response.statusCode})');
          
          anySuccess = true;
          workingUrl = url;
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Success! $url is working'),
              backgroundColor: Colors.green,
              action: SnackBarAction(
                label: 'Use This URL',
                textColor: Colors.white,
                onPressed: () {
                  // Connect using this URL
                  setState(() {
                    _streamUrl = url;
                    _isConnected = true;
                    _currentIp = ip;
                    _useTimerRefresh = false;
                  });
                  
                  _webViewController.loadRequest(Uri.parse(url));
                  
                  // Save to recent connections
                  _saveRecentConnection(ip);
                  
                  // Close any open dialogs
                  Navigator.popUntil(context, (route) => route.isFirst);
                },
              ),
            ),
          );
          
          break;
        }
      } catch (e) {
        debugPrint('Error testing $url: $e');
        continue;
      }
    }
    
    if (!anySuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not connect to any stream URLs on $baseUrl'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
} 