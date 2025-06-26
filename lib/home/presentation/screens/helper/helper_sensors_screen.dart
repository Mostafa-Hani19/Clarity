import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';

class HelperSensorsScreen extends StatefulWidget {
  const HelperSensorsScreen({super.key});

  @override
  State<HelperSensorsScreen> createState() => _HelperSensorsScreenState();
}

class _HelperSensorsScreenState extends State<HelperSensorsScreen> {
  static const String dbUrl = 'https://clarity-app-1d42c-default-rtdb.europe-west1.firebasedatabase.app';
  late final DatabaseReference _database;
  // Store the broadcast stream as a class field
  late final Stream<DatabaseEvent> _onValueStream;

  DateTime? _lastUpdated;
  String _cmToFeet(dynamic value) {
    if (value is num) {
      double feet = value / 30.48;
      return '${feet.toStringAsFixed(2)} ft';
    }
    return 'No data';
  }

  @override
  void initState() {
    super.initState();
    // Make sure Firebase is initialized before using this screen
    _database = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: dbUrl,
    ).ref('smart_glasses');

    // Create a single broadcast stream
    _onValueStream = _database.onValue.asBroadcastStream();
    
    _onValueStream.listen((event) {
      setState(() {
        _lastUpdated = DateTime.now();
      });
      debugPrint('Firebase Data Received: ${event.snapshot.value}');
    }, onError: (error) {
      debugPrint('Firebase Error: $error');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Environmental Sensors'),
        backgroundColor: Colors.blue,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              debugPrint('Refreshing data...');
              try {
                var snapshot = await _database.get();
                debugPrint('Current data: ${snapshot.value}');
              } catch (e) {
                debugPrint('Error getting data: $e');
              }
            },
          ),
        ],
      ),
      body: StreamBuilder<DatabaseEvent>(
        stream: _onValueStream,
        builder: (context, snapshot) {
          debugPrint('SNAPSHOT Connection: ${snapshot.connectionState}');
          debugPrint('SNAPSHOT hasData: ${snapshot.hasData}');
          debugPrint('SNAPSHOT error: ${snapshot.error}');
          debugPrint('SNAPSHOT value: ${snapshot.data?.snapshot.value}');

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
                    style: TextStyle(fontSize: 16),
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
                  Icon(Icons.error_outline, color: Colors.red, size: 48),
                  SizedBox(height: 16),
                  Text(
                    'Firebase Connection Error:\n${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.red),
                  ),
                  SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {});
                    },
                    child: Text('Retry Connection'),
                  ),
                ],
              ),
            );
          }

          // Initialize empty data map
          Map<String, dynamic> data = {};

          // If we have data, use it
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
            // No data available
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.sensors_off, color: Colors.grey, size: 48),
                  SizedBox(height: 16),
                  Text(
                    'No sensor data available\nMake sure ESP32 is connected',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          // Always show all sections with available data or "No data" message
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSensorCard(
                  'Temperature',
                  _showSensorValue(data, 'temperature', '°C'),
                  Icons.thermostat,
                  Colors.orange,
                ),
                const SizedBox(height: 16),
                _buildSensorCard(
                  'Humidity',
                  _showSensorValue(data, 'humidity', '%'),
                  Icons.water_drop,
                  Colors.blue,
                ),
                const SizedBox(height: 16),
                _buildSensorCard(
                  'Distance',
                  data.containsKey('distance') && data['distance'] != null
                      ? _cmToFeet(data['distance'])
                      : 'No data',
                  Icons.straighten,
                  Colors.purple,
                ),
                const SizedBox(height: 16),
                _buildMotionCard(data['motion'] as bool? ?? false,
                    data.containsKey('motion')),
                const SizedBox(height: 16),
                _buildExpandableCard(
                  'Gyroscope',
                  Icons.rotate_right,
                  Colors.green,
                  Column(
                    children: [
                      _buildDataRow(
                          'X-axis', _safeNested(data, ['gyro', 'x'], '°/s')),
                      _buildDataRow(
                          'Y-axis', _safeNested(data, ['gyro', 'y'], '°/s')),
                      _buildDataRow(
                          'Z-axis', _safeNested(data, ['gyro', 'z'], '°/s')),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildExpandableCard(
                  'Accelerometer',
                  Icons.speed,
                  Colors.red,
                  Column(
                    children: [
                      _buildDataRow(
                          'X-axis', _safeNested(data, ['accel', 'x'], 'm/s²')),
                      _buildDataRow(
                          'Y-axis', _safeNested(data, ['accel', 'y'], 'm/s²')),
                      _buildDataRow(
                          'Z-axis', _safeNested(data, ['accel', 'z'], 'm/s²')),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (_lastUpdated != null)
                  Center(
                    child: Text(
                      'Last updated: ${_lastUpdated!.toLocal().toString().split('.')[0]}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
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
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
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
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: !motionExists
                ? [Colors.grey.shade400, Colors.grey.shade700]
                : isMotionDetected
                    ? [Colors.red.shade400, Colors.red.shade700]
                    : [Colors.green.shade400, Colors.green.shade700],
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                !motionExists
                    ? Icons.help_outline
                    : isMotionDetected
                        ? Icons.warning
                        : Icons.check_circle,
                color: Colors.white,
                size: 32,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Motion Detection',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
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

  Widget _buildExpandableCard(
      String title, IconData icon, Color color, Widget content) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: content,
          ),
        ],
      ),
    );
  }

  Widget _buildDataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
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
} 