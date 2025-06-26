import 'package:flutter/foundation.dart';

class SensorData {
  final double temperature;
  final double humidity;
  final double distance;
  final bool motion;
  final Gyroscope gyro;
  final Accelerometer accel;

  SensorData({
    required this.temperature,
    required this.humidity,
    required this.distance,
    required this.motion,
    required this.gyro,
    required this.accel,
  });

  factory SensorData.fromMap(Map<String, dynamic> map) {
    try {
      return SensorData(
        temperature: (map['temperature'] as num?)?.toDouble() ?? 0.0,
        humidity: (map['humidity'] as num?)?.toDouble() ?? 0.0,
        distance: (map['distance'] as num?)?.toDouble() ?? 0.0,
        motion: map['motion'] as bool? ?? false,
        gyro: map['gyro'] is Map ? Gyroscope.fromMap(_castToStringDynamicMap(map['gyro'])) : Gyroscope(x: 0, y: 0, z: 0),
        accel: map['accel'] is Map ? Accelerometer.fromMap(_castToStringDynamicMap(map['accel'])) : Accelerometer(x: 0, y: 0, z: 0),
      );
    } catch (e) {
      debugPrint('Error parsing SensorData: $e');
      // Return default values if parsing fails
      return SensorData(
        temperature: 0.0,
        humidity: 0.0,
        distance: 0.0,
        motion: false,
        gyro: Gyroscope(x: 0, y: 0, z: 0),
        accel: Accelerometer(x: 0, y: 0, z: 0),
      );
    }
  }

  // Helper method to safely cast maps
  static Map<String, dynamic> _castToStringDynamicMap(dynamic map) {
    if (map is Map<String, dynamic>) {
      return map;
    }
    if (map is Map) {
      final result = <String, dynamic>{};
      map.forEach((key, value) {
        if (key is String) {
          result[key] = value;
        }
      });
      return result;
    }
    return {};
  }

  Map<String, dynamic> toMap() {
    return {
      'temperature': temperature,
      'humidity': humidity,
      'distance': distance,
      'motion': motion,
      'gyro': gyro.toMap(),
      'accel': accel.toMap(),
    };
  }

  SensorData copyWith({
    double? temperature,
    double? humidity,
    double? distance,
    bool? motion,
    Gyroscope? gyro,
    Accelerometer? accel,
  }) {
    return SensorData(
      temperature: temperature ?? this.temperature,
      humidity: humidity ?? this.humidity,
      distance: distance ?? this.distance,
      motion: motion ?? this.motion,
      gyro: gyro ?? this.gyro,
      accel: accel ?? this.accel,
    );
  }
}

class Gyroscope {
  final double x;
  final double y;
  final double z;

  Gyroscope({
    required this.x,
    required this.y,
    required this.z,
  });

  factory Gyroscope.fromMap(Map<String, dynamic> map) {
    try {
      return Gyroscope(
        x: (map['x'] as num?)?.toDouble() ?? 0.0,
        y: (map['y'] as num?)?.toDouble() ?? 0.0,
        z: (map['z'] as num?)?.toDouble() ?? 0.0,
      );
    } catch (e) {
      debugPrint('Error parsing Gyroscope data: $e');
      return Gyroscope(x: 0.0, y: 0.0, z: 0.0);
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'x': x,
      'y': y,
      'z': z,
    };
  }

  Gyroscope copyWith({double? x, double? y, double? z}) {
    return Gyroscope(
      x: x ?? this.x,
      y: y ?? this.y,
      z: z ?? this.z,
    );
  }
}

class Accelerometer {
  final double x;
  final double y;
  final double z;

  Accelerometer({
    required this.x,
    required this.y,
    required this.z,
  });

  factory Accelerometer.fromMap(Map<String, dynamic> map) {
    try {
      return Accelerometer(
        x: (map['x'] as num?)?.toDouble() ?? 0.0,
        y: (map['y'] as num?)?.toDouble() ?? 0.0,
        z: (map['z'] as num?)?.toDouble() ?? 0.0,
      );
    } catch (e) {
      debugPrint('Error parsing Accelerometer data: $e');
      return Accelerometer(x: 0.0, y: 0.0, z: 0.0);
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'x': x,
      'y': y,
      'z': z,
    };
  }

  Accelerometer copyWith({double? x, double? y, double? z}) {
    return Accelerometer(
      x: x ?? this.x,
      y: y ?? this.y,
      z: z ?? this.z,
    );
  }
}
