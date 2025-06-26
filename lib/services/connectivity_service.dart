import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  
  // StreamController to broadcast connectivity changes.
  // Use .broadcast() if multiple listeners are expected.
  final StreamController<ConnectivityResult> _connectivityController =
      StreamController<ConnectivityResult>.broadcast();

  Stream<ConnectivityResult> get connectivityStream => _connectivityController.stream;

  ConnectivityResult _currentPrimaryStatus = ConnectivityResult.none;
  ConnectivityResult get currentPrimaryStatus => _currentPrimaryStatus;

  List<ConnectivityResult> _currentStatuses = [];
  List<ConnectivityResult> get currentStatuses => _currentStatuses;

  bool get isOnline => _currentPrimaryStatus != ConnectivityResult.none;

  ConnectivityService() {
    _connectivity.checkConnectivity().then((results) {
      _updateStatuses(results);
      debugPrint("Initial connectivity statuses: $results -> Primary: $_currentPrimaryStatus");
    });

    _connectivity.onConnectivityChanged.listen((List<ConnectivityResult> results) {
      _updateStatuses(results);
      debugPrint("Connectivity statuses changed: $results -> Primary: $_currentPrimaryStatus");
    });
    debugPrint("✅ ConnectivityService initialized and listening to changes.");
  }

  void _updateStatuses(List<ConnectivityResult> results) {
    _currentStatuses = results;
    if (results.isEmpty) {
      _currentPrimaryStatus = ConnectivityResult.none;
    } else {
      // Prioritize connections: Wi-Fi > Mobile > Ethernet > Bluetooth > Other > None
      if (results.contains(ConnectivityResult.wifi)) {
        _currentPrimaryStatus = ConnectivityResult.wifi;
      } else if (results.contains(ConnectivityResult.mobile)) {
        _currentPrimaryStatus = ConnectivityResult.mobile;
      } else if (results.contains(ConnectivityResult.ethernet)) {
        _currentPrimaryStatus = ConnectivityResult.ethernet;
      } else if (results.contains(ConnectivityResult.bluetooth)) {
        _currentPrimaryStatus = ConnectivityResult.bluetooth; // Typically not for internet, but for completeness
      } else if (results.contains(ConnectivityResult.vpn)) { // VPN implies an underlying connection
         // Try to find the first non-none, non-vpn connection
        _currentPrimaryStatus = results.firstWhere(
            (r) => r != ConnectivityResult.none && r != ConnectivityResult.vpn, 
            orElse: () => ConnectivityResult.vpn // If only VPN and none, consider VPN as primary
        );
         if (_currentPrimaryStatus == ConnectivityResult.vpn && !results.any((r) => r != ConnectivityResult.none && r != ConnectivityResult.vpn)){

            _currentPrimaryStatus = results.contains(ConnectivityResult.other) ? ConnectivityResult.other : ConnectivityResult.vpn;
         }
      } else if (results.contains(ConnectivityResult.other)) {
        _currentPrimaryStatus = ConnectivityResult.other;
      } else {
        _currentPrimaryStatus = ConnectivityResult.none; // Should be covered if results.contains(ConnectivityResult.none) is the only one
      }
    }
    _connectivityController.add(_currentPrimaryStatus);
  }

  Future<List<ConnectivityResult>> checkConnectivityList() async {
    final results = await _connectivity.checkConnectivity();
    _updateStatuses(results); // Update internal state and stream
    return results;
  }
  
  // For consumers that want a single primary status directly
  Future<ConnectivityResult> checkPrimaryConnectivity() async {
    await checkConnectivityList();
    return _currentPrimaryStatus;
  }

  void dispose() {
    _connectivityController.close();
    debugPrint("🔌 ConnectivityService disposed.");
  }
} 