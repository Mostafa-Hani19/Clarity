import 'package:firebase_database/firebase_database.dart';
import '../models/sensor_data.dart';

class SensorService {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final String _path = 'smart_glasses';

  Stream<SensorData> getSensorDataStream() {
    return _database.child(_path).onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>;
      return SensorData.fromMap(Map<String, dynamic>.from(data));
    });
  }
} 