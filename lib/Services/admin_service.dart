import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';

class AdminService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Logger _logger = Logger();

  // 1. ADD USER DIRECTLY
  Future<bool> addUserDirectly({
    required String email,
    required String password,
    required String name,
    required String role,
    required String phone,
  }) async {
    try {
      UserCredential cred =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      await _firestore.collection('users').doc(cred.user!.uid).set({
        'uid': cred.user!.uid,
        'email': email,
        'name': name,
        'role': role,
        'phone': phone,
        'status': 'active',
        'createdAt': DateTime.now(),
        'createdBy': _auth.currentUser!.uid,
      });

      _logger.i("User added directly: $email | Role: $role");
      return true;
    } catch (e) {
      _logger.e("addUserDirectly error: $e");
      return false;
    }
  }

  // 2. GET ALL USERS
  Future<List<Map<String, dynamic>>> getAllUsers() async {
    try {
      QuerySnapshot snap = await _firestore.collection('users').get();
      _logger.d("getAllUsers: ${snap.docs.length} users fetched");
      return snap.docs
          .map((doc) => doc.data() as Map<String, dynamic>)
          .toList();
    } catch (e) {
      _logger.e("getAllUsers error: $e");
      return [];
    }
  }

  // 3. EDIT USER
  Future<bool> editUserInfo({
    required String userId,
    required String newName,
    required String newPhone,
    required String newRole,
  }) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'name': newName,
        'phone': newPhone,
        'role': newRole,
        'updatedAt': DateTime.now(),
        'updatedBy': _auth.currentUser!.uid,
      });
      _logger.i("User updated: $userId | New role: $newRole");
      return true;
    } catch (e) {
      _logger.e("editUserInfo error: $e");
      return false;
    }
  }

  // 4. DEACTIVATE USER
  Future<bool> deactivateUser(String userId) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'status': 'inactive',
        'deactivatedAt': DateTime.now(),
        'deactivatedBy': _auth.currentUser!.uid,
      });
      _logger.w("User deactivated: $userId");
      return true;
    } catch (e) {
      _logger.e("deactivateUser error: $e");
      return false;
    }
  }

  // 5. REACTIVATE USER
  Future<bool> reactivateUser(String userId) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'status': 'active',
        'reactivatedAt': DateTime.now(),
      });
      _logger.i("User reactivated: $userId");
      return true;
    } catch (e) {
      _logger.e("reactivateUser error: $e");
      return false;
    }
  }

  // 6. RESET PASSWORD
  Future<bool> resetUserPassword(String email) async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _logger.i("Password reset sent to: $email");
      return true;
    } catch (e) {
      _logger.e("resetUserPassword error: $e");
      return false;
    }
  }

  // 7. DELETE USER
  Future<bool> deleteUser(String userId) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'status': 'deleted',
        'deletedAt': DateTime.now(),
        'deletedBy': _auth.currentUser!.uid,
      });
      _logger.w("User deleted: $userId");
      return true;
    } catch (e) {
      _logger.e("deleteUser error: $e");
      return false;
    }
  }

  // 8. SEARCH USERS
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    try {
      QuerySnapshot snap = await _firestore
          .collection('users')
          .where('email', isGreaterThanOrEqualTo: query)
          .where('email', isLessThan: '${query}z')
          .get();

      _logger.d("searchUsers: query='$query' | ${snap.docs.length} results");
      return snap.docs
          .map((doc) => doc.data() as Map<String, dynamic>)
          .toList();
    } catch (e) {
      _logger.e("searchUsers error: $e");
      return [];
    }
  }

  // 9. FILTER BY ROLE
  Future<List<Map<String, dynamic>>> getUsersByRole(String role) async {
    try {
      QuerySnapshot snap = await _firestore
          .collection('users')
          .where('role', isEqualTo: role)
          .get();

      _logger.d("getUsersByRole: role='$role' | ${snap.docs.length} found");
      return snap.docs
          .map((doc) => doc.data() as Map<String, dynamic>)
          .toList();
    } catch (e) {
      _logger.e("getUsersByRole error: $e");
      return [];
    }
  }
}
