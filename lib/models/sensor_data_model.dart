class SensorData {
  final double temperature;
  final double humidity;
  final double distance;
  final bool motionDetected;
  final double gyroX;
  final double gyroY;
  final double gyroZ;
  final double accelX;
  final double accelY;
  final double accelZ;
  final DateTime timestamp;

  static const String defaultDeviceIp = '26.239.242.66';
  static const String defaultDeviceType = 'smart_glasses';

  SensorData({
    required this.temperature,
    required this.humidity,
    required this.distance,
    required this.motionDetected,
    required this.gyroX,
    required this.gyroY,
    required this.gyroZ,
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory SensorData.fromMap(Map<String, dynamic> map) {
    return SensorData(
      temperature:
          _parseDouble(map['temperature'] ?? map['Temperature']) ?? 0.0,
      humidity: _parseDouble(map['humidity'] ?? map['Humidity']) ?? 0.0,
      distance: _parseDouble(map['distance'] ?? map['Distance']) ?? 0.0,
      motionDetected: _parseMotion(map['motion_detected'] ?? map['Motion']),
      gyroX: _parseDouble(map['gyro_x'] ?? map['GyroX']) ?? 0.0,
      gyroY: _parseDouble(map['gyro_y'] ?? map['GyroY']) ?? 0.0,
      gyroZ: _parseDouble(map['gyro_z'] ?? map['GyroZ']) ?? 0.0,
      accelX: _parseDouble(map['accel_x'] ?? map['AccelX']) ?? 0.0,
      accelY: _parseDouble(map['accel_y'] ?? map['AccelY']) ?? 0.0,
      accelZ: _parseDouble(map['accel_z'] ?? map['AccelZ']) ?? 0.0,
      timestamp: _parseTimestamp(map['timestamp'] ?? map['created_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'temperature': temperature,
      'humidity': humidity,
      'distance': distance,
      'motion_detected': motionDetected,
      'gyro_x': gyroX,
      'gyro_y': gyroY,
      'gyro_z': gyroZ,
      'accel_x': accelX,
      'accel_y': accelY,
      'accel_z': accelZ,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'device_ip': defaultDeviceIp,
      'device_type': defaultDeviceType,
    };
  }

  Map<String, dynamic> toFirestore() {
    return {
      ...toMap(),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    };
  }

  // Parsing helpers
  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      try {
        return double.parse(value.replaceAll(RegExp(r'[^\d.-]'), ''));
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static bool _parseMotion(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is String) {
      return ['yes', 'true', 'detected', '1'].contains(value.toLowerCase());
    }
    if (value is num) return value != 0;
    return false;
  }

  static DateTime _parseTimestamp(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) {
      try {
        final parsed = int.tryParse(value);
        if (parsed != null) return DateTime.fromMillisecondsSinceEpoch(parsed);
        return DateTime.parse(value);
      } catch (_) {
        return DateTime.now();
      }
    }
    return DateTime.now();
  }

  @override
  String toString() {
    return 'SensorData(temp: $temperature, humidity: $humidity, distance: $distance, motion: $motionDetected, time: $timestamp)';
  }
}
