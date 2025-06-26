import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String id;
  final String email;
  final String? displayName;
  final bool isBlindUser;
  final Map<String, dynamic>? preferences;
  final DateTime createdAt;
  final DateTime? lastUpdated;

  UserModel({
    required this.id,
    required this.email,
    this.displayName,
    required this.isBlindUser,
    this.preferences,
    required this.createdAt,
    this.lastUpdated,
  });

  // تحويل UserModel إلى Map لكتابة في Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      'displayName': displayName,
      'isBlindUser': isBlindUser,
      'preferences': preferences ?? {},
      'createdAt': Timestamp.fromDate(createdAt),
      'lastUpdated': Timestamp.fromDate(lastUpdated ?? createdAt),
    };
  }

  // إنشاء UserModel من Firestore Document
  factory UserModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return UserModel(
      id: doc.id,
      email: data['email'] ?? '',
      displayName: data['displayName'],
      isBlindUser: data['isBlindUser'] ?? false,
      preferences: (data['preferences'] as Map<String, dynamic>?),
      createdAt: _parseTimestamp(data['createdAt']),
      lastUpdated: data['lastUpdated'] != null
          ? _parseTimestamp(data['lastUpdated'])
          : null,
    );
  }

  // نسخة copyWith لتسهيل التعديل
  UserModel copyWith({
    String? id,
    String? email,
    String? displayName,
    bool? isBlindUser,
    Map<String, dynamic>? preferences,
    DateTime? createdAt,
    DateTime? lastUpdated,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      isBlindUser: isBlindUser ?? this.isBlindUser,
      preferences: preferences ?? this.preferences,
      createdAt: createdAt ?? this.createdAt,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'displayName': displayName,
      'isBlindUser': isBlindUser,
      'preferences': preferences ?? {},
      'createdAt': createdAt.toIso8601String(),
      'lastUpdated': lastUpdated?.toIso8601String(),
    };
  }

  // دالة خاصة لتحويل Timestamp/DateTime/null إلى DateTime
  static DateTime _parseTimestamp(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (e) {
        return DateTime.now();
      }
    }
    return DateTime.now();
  }
}
