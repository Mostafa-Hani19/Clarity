import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Collection references
  final CollectionReference<Map<String, dynamic>> _usersCollection =
      FirebaseFirestore.instance.collection('users');

  // Create or update user document
  Future<void> saveUserData(UserModel user) async {
    try {
      debugPrint('🔄 Saving user data for: ${user.email}');
      await _usersCollection.doc(user.id).set(
        user.toFirestore(),
        SetOptions(merge: true),
      );
      debugPrint('✅ User data saved successfully');
    } catch (e) {
      debugPrint('❌ Error saving user data: $e');
      rethrow;
    }
  }

  // Get user document by ID
  Future<UserModel?> getUserById(String userId) async {
    try {
      debugPrint('🔍 Getting user data for ID: $userId');
      final docSnapshot = await _usersCollection.doc(userId).get();
      final data = docSnapshot.data();
      if (data != null) {
        debugPrint('✅ User data found');
        return UserModel.fromFirestore(docSnapshot);
      } else {
        debugPrint('⚠️ No user document found for ID: $userId');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Error getting user data: $e');
      rethrow;
    }
  }

  // Stream user document by ID (for real-time updates)
  Stream<UserModel?> streamUserById(String userId) {
    return _usersCollection.doc(userId).snapshots().map((docSnapshot) {
      final data = docSnapshot.data();
      if (data != null) {
        return UserModel.fromFirestore(docSnapshot);
      }
      return null;
    });
  }

  // Get user document by email
  Future<UserModel?> getUserByEmail(String email) async {
    try {
      debugPrint('🔍 Getting user data for email: $email');
      final querySnapshot = await _usersCollection
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        debugPrint('✅ User data found');
        return UserModel.fromFirestore(querySnapshot.docs.first);
      } else {
        debugPrint('⚠️ No user document found for email: $email');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Error getting user data by email: $e');
      rethrow;
    }
  }

  // Update specific user fields
  Future<void> updateUserData(String userId, Map<String, dynamic> data) async {
    try {
      debugPrint('🔄 Updating user data for ID: $userId');
      data['lastUpdated'] = FieldValue.serverTimestamp();
      await _usersCollection.doc(userId).update(data);
      debugPrint('✅ User data updated successfully');
    } catch (e) {
      debugPrint('❌ Error updating user data: $e');
      rethrow;
    }
  }

  // Delete user document
  Future<void> deleteUser(String userId) async {
    try {
      debugPrint('🗑️ Deleting user data for ID: $userId');
      await _usersCollection.doc(userId).delete();
      debugPrint('✅ User data deleted successfully');
    } catch (e) {
      debugPrint('❌ Error deleting user data: $e');
      rethrow;
    }
  }

  // Get user-specific data from a sub-collection or other collection
  Future<List<Map<String, dynamic>>> getUserData(
      String userId, String collectionName) async {
    try {
      debugPrint('🔍 Getting $collectionName data for user: $userId');
      final querySnapshot = await _firestore
          .collection(collectionName)
          .where('userId', isEqualTo: userId)
          .get();

      return querySnapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .toList();
    } catch (e) {
      debugPrint('❌ Error getting user $collectionName data: $e');
      rethrow;
    }
  }

  // Add user-specific data
  Future<DocumentReference> addUserData(
    String userId,
    String collectionName,
    Map<String, dynamic> data,
  ) async {
    try {
      debugPrint('➕ Adding $collectionName data for user: $userId');
      data['userId'] = userId;
      data['createdAt'] = FieldValue.serverTimestamp();
      data['updatedAt'] = FieldValue.serverTimestamp();

      final docRef = await _firestore.collection(collectionName).add(data);
      debugPrint(
          '✅ $collectionName data added successfully with ID: ${docRef.id}');
      return docRef;
    } catch (e) {
      debugPrint('❌ Error adding user $collectionName data: $e');
      rethrow;
    }
  }

  // Update user-specific data
  Future<void> updateUserSpecificData(
    String documentId,
    String collectionName,
    Map<String, dynamic> data,
  ) async {
    try {
      debugPrint('🔄 Updating $collectionName document: $documentId');
      data['updatedAt'] = FieldValue.serverTimestamp();
      await _firestore.collection(collectionName).doc(documentId).update(data);
      debugPrint('✅ $collectionName document updated successfully');
    } catch (e) {
      debugPrint('❌ Error updating $collectionName document: $e');
      rethrow;
    }
  }

  // Delete user-specific data
  Future<void> deleteUserSpecificData(
      String documentId, String collectionName) async {
    try {
      debugPrint('🗑️ Deleting $collectionName document: $documentId');
      await _firestore.collection(collectionName).doc(documentId).delete();
      debugPrint('✅ $collectionName document deleted successfully');
    } catch (e) {
      debugPrint('❌ Error deleting $collectionName document: $e');
      rethrow;
    }
  }

  // Get a stream of user-specific data for real-time updates
  Stream<QuerySnapshot<Map<String, dynamic>>> streamUserData(
      String userId, String collectionName) {
    return _firestore
        .collection(collectionName)
        .where('userId', isEqualTo: userId)
        .snapshots();
  }
}
