import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_tts/flutter_tts.dart';

class SensorScreen extends StatefulWidget {
  const SensorScreen({super.key});

  @override
  State<SensorScreen> createState() => _SensorScreenState();
}

class _SensorScreenState extends State<SensorScreen> {
  // EXPLICIT DATABASE URL
  static const String dbUrl =
      'https://clarity-app-1d42c-default-rtdb.europe-west1.firebasedatabase.app';
  late final DatabaseReference _database;
  late final Stream<DatabaseEvent> _onValueStream;
  StreamSubscription<DatabaseEvent>? _subscription;

  DateTime? _lastUpdated;
  bool _isRefreshing = false;
  final FlutterTts _tts = FlutterTts();
  bool _isMounted = true;  // Track mount state

  // Safe setState helper method
  void _safeSetState(VoidCallback fn) {
    if (mounted && _isMounted) {
      setState(fn);
    }
  }

  @override
  void initState() {
    super.initState();
    _isMounted = true;
    _database = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: dbUrl,
    ).ref('smart_glasses');
    _onValueStream = _database.onValue.asBroadcastStream();
    _subscription = _onValueStream.listen((event) {
      if (mounted) {
        _safeSetState(() {
          _lastUpdated = DateTime.now();
        });
        _announceAllSensors(event.snapshot.value);
      }
    }, onError: (error) {
      debugPrint('Firebase Error: $error');
    });
    _initTts();
  }

  @override
  void dispose() {
    _isMounted = false;
    _subscription?.cancel();
    _subscription = null;
    _tts.stop();
    super.dispose();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('en');
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
  }

  Future<void> _speak(String text) async {
    // Don't speak if the widget is no longer mounted
    if (!mounted || !_isMounted) return;
    
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      debugPrint('TTS Error: $e');
    }
  }

  void _announceAllSensors(dynamic raw) {
    if (!mounted || !_isMounted) return;  // Skip if not mounted
    
    if (raw is! Map) return;
    final data = Map<String, dynamic>.from(raw);
    final temp = data['temperature'] != null ? 'Temperature: ${data['temperature']} degrees Celsius.' : '';
    final hum = data['humidity'] != null ? 'Humidity: ${data['humidity']} percent.' : '';
    final dist = data['distance'] != null ? 'Distance: ${_cmToFeet(data['distance'])}.' : '';
    final motion = data['motion'] == true ? 'Motion detected.' : (data['motion'] == false ? 'No motion.' : '');
    final summary = [temp, hum, dist, motion].where((s) => s.isNotEmpty).join(' ');
    if (summary.isNotEmpty && mounted && _isMounted) _speak(summary);
  }

  String _cmToFeet(dynamic value) {
    if (value is num) {
      double feet = value / 30.48;
      return '${feet.toStringAsFixed(2)} feet';
    }
    return 'No data';
  }

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Environmental Sensors'),
        backgroundColor: Colors.blue.shade800,
        actions: [
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _isRefreshing
                ? null
                : () async {
                    _safeSetState(() => _isRefreshing = true);
                    try {
                      var snapshot = await _database.get();
                      debugPrint('Current data: ${snapshot.value}');
                      if (mounted && _isMounted) _announceAllSensors(snapshot.value);
                    } catch (e) {
                      debugPrint('Error getting data: $e');
                    }
                    _safeSetState(() => _isRefreshing = false);
                  },
          ),
        ],
      ),
      body: StreamBuilder<DatabaseEvent>(
        stream: _onValueStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Connecting to Firebase...\nFetching sensor data',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, color: Colors.red, size: 56),
                  SizedBox(height: 16),
                  Text(
                    'Firebase Connection Error:\n${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.red, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry Connection'),
                    onPressed: () {
                      _safeSetState(() {});
                    },
                  ),
                ],
              ),
            );
          }

          Map<String, dynamic> data = {};
          if (snapshot.hasData && snapshot.data?.snapshot.value != null) {
            try {
              final raw = snapshot.data!.snapshot.value;
              if (raw is Map) {
                data = Map<String, dynamic>.from(raw);
                debugPrint('Received Firebase data: $data');
              } else {
                debugPrint('Unexpected data format: $raw');
                return Center(child: Text('Data format error: $raw'));
              }
            } catch (e) {
              debugPrint('Error parsing Firebase data: $e');
              return Center(child: Text('Data parse error: $e'));
            }
          } else {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.sensors_off, color: Colors.grey, size: 56),
                  SizedBox(height: 16),
                  Text(
                    'No sensor data available\nMake sure ESP32 is connected',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.volume_up),
                  label: const Text('Read All'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () => _announceAllSensors(data),
                ),
                const SizedBox(height: 24),
                _buildTappableSensorCard(
                  'Temperature',
                  _showSensorValue(data, 'temperature', '°C'),
                  Icons.thermostat,
                  Colors.orange.shade700,
                  () => _speak('Temperature: ${_showSensorValue(data, 'temperature', 'degrees Celsius')}'),
                ),
                const SizedBox(height: 20),
                _buildTappableSensorCard(
                  'Humidity',
                  _showSensorValue(data, 'humidity', '%'),
                  Icons.water_drop,
                  Colors.blue.shade700,
                  () => _speak('Humidity: ${_showSensorValue(data, 'humidity', 'percent')}'),
                ),
                const SizedBox(height: 20),
                _buildTappableSensorCard(
                  'Distance',
                  data.containsKey('distance') && data['distance'] != null
                      ? _cmToFeet(data['distance'])
                      : 'No data',
                  Icons.straighten,
                  Colors.purple.shade700,
                  () => _speak('Distance: ${data.containsKey('distance') && data['distance'] != null ? _cmToFeet(data['distance']) : 'No data'}'),
                ),
                const SizedBox(height: 20),
                _buildTappableMotionCard(
                  data['motion'] as bool? ?? false,
                  data.containsKey('motion'),
                  () => _speak(data.containsKey('motion')
                      ? (data['motion'] == true ? 'Motion detected.' : 'No motion.')
                      : 'No motion data'),
                ),
                const SizedBox(height: 20),
                _buildExpandableCard(
                  'Gyroscope',
                  Icons.rotate_right,
                  Colors.green.shade700,
                  Column(
                    children: [
                      _buildDataRow('X-axis', _safeNested(data, ['gyro', 'x'], '°/s')),
                      _buildDataRow('Y-axis', _safeNested(data, ['gyro', 'y'], '°/s')),
                      _buildDataRow('Z-axis', _safeNested(data, ['gyro', 'z'], '°/s')),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _buildExpandableCard(
                  'Accelerometer',
                  Icons.speed,
                  Colors.red.shade700,
                  Column(
                    children: [
                      _buildDataRow('X-axis', _safeNested(data, ['accel', 'x'], 'm/s²')),
                      _buildDataRow('Y-axis', _safeNested(data, ['accel', 'y'], 'm/s²')),
                      _buildDataRow('Z-axis', _safeNested(data, ['accel', 'z'], 'm/s²')),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (_lastUpdated != null)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        'Last updated: ${_lastUpdated!.toLocal().toString().split('.')[0]}',
                        style: const TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _showSensorValue(Map data, String key, String unit) {
    if (data.containsKey(key) && data[key] != null) {
      final value = data[key];
      if (value is num) {
        return '${value.toStringAsFixed(1)} $unit';
      } else {
        return '$value $unit';
      }
    } else {
      return 'No data';
    }
  }

  Widget _buildSensorCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 40),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: color,
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

  Widget _buildMotionCard(bool isMotionDetected, bool motionExists) {
    String label = !motionExists
        ? 'No data'
        : isMotionDetected
            ? 'Motion Detected!'
            : 'No Motion';
    Color cardColor = !motionExists
        ? Colors.grey.shade600
        : isMotionDetected
            ? Colors.red.shade700
            : Colors.green.shade700;
    IconData icon = !motionExists
        ? Icons.help_outline
        : isMotionDetected
            ? Icons.warning_amber_rounded
            : Icons.check_circle;
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: cardColor.withOpacity(0.12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardColor.withOpacity(0.18),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                icon,
                color: cardColor,
                size: 40,
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Motion Detection',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: cardColor,
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

  Widget _buildExpandableCard(String title, IconData icon, Color color, Widget content) {
    return Card(
      elevation: 5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          childrenPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 20),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          children: [
            content,
          ],
        ),
      ),
    );
  }

  Widget _buildDataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _safeNested(Map data, List<String> path, String unit) {
    dynamic v = data;
    for (final key in path) {
      if (v is Map && v.containsKey(key) && v[key] != null) {
        v = v[key];
      } else {
        return 'No data';
      }
    }
    if (v is num) {
      return '${v.toStringAsFixed(2)} $unit';
    }
    return 'No data';
  }

  Widget _buildTappableSensorCard(String title, String value, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        if (mounted && _isMounted) onTap();
      },
      child: _buildSensorCard(title, value, icon, color),
    );
  }

  Widget _buildTappableMotionCard(bool isMotionDetected, bool motionExists, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        if (mounted && _isMounted) onTap();
      },
      child: _buildMotionCard(isMotionDetected, motionExists),
    );
  }
}
