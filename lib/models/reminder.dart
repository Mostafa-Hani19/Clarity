import 'package:cloud_firestore/cloud_firestore.dart';

enum RecurrenceType { none, daily, weekly }

class Reminder {
  final String id;
  final String title;
  final DateTime dateTime;
  final RecurrenceType recurrenceType;
  final bool isCompleted;
  final String userId;
  final bool isSynced;

  Reminder({
    required this.id,
    required this.title,
    required this.dateTime,
    this.recurrenceType = RecurrenceType.none,
    this.isCompleted = false,
    required this.userId,
    this.isSynced = false,
  });

  factory Reminder.fromMap(Map<String, dynamic> map, String docId) {
    return Reminder(
      id: docId,
      title: map['title'] ?? '',
      dateTime: _parseDateTime(map['dateTime']),
      recurrenceType: _parseRecurrenceType(map['recurrenceType']),
      isCompleted: map['isCompleted'] ?? false,
      userId: map['userId'] ?? '',
      isSynced: map['isSynced'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'dateTime': Timestamp.fromDate(dateTime),
      'recurrenceType': recurrenceType.index,
      'isCompleted': isCompleted,
      'userId': userId,
      'isSynced': isSynced,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Reminder copyWith({
    String? id,
    String? title,
    DateTime? dateTime,
    RecurrenceType? recurrenceType,
    bool? isCompleted,
    String? userId,
    bool? isSynced,
  }) {
    return Reminder(
      id: id ?? this.id,
      title: title ?? this.title,
      dateTime: dateTime ?? this.dateTime,
      recurrenceType: recurrenceType ?? this.recurrenceType,
      isCompleted: isCompleted ?? this.isCompleted,
      userId: userId ?? this.userId,
      isSynced: isSynced ?? this.isSynced,
    );
  }

  // --- Helper methods for safe parsing ---
  static DateTime _parseDateTime(dynamic value) {
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

  static RecurrenceType _parseRecurrenceType(dynamic value) {
    if (value is int && value >= 0 && value < RecurrenceType.values.length) {
      return RecurrenceType.values[value];
    }
    if (value is String) {
      // optional: parse string values (e.g., "daily")
      return RecurrenceType.values.firstWhere(
        (e) => e.toString().split('.').last == value,
        orElse: () => RecurrenceType.none,
      );
    }
    return RecurrenceType.none;
  }

  // --- Optional: For easy printing/debugging ---
  @override
  String toString() {
    return 'Reminder(id: $id, title: $title, dateTime: $dateTime, recurrence: $recurrenceType, completed: $isCompleted, user: $userId)';
  }
}
