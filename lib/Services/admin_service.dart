import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
import '../Services/notification_service.dart';

/// FIXES IS FILE MEIN:
/// 1. addUserDirectly() DELETE kar diya — staff sirf INVITE se add
///    hota hai (invite_service + auth_service). Direct-create mein
///    admin ka session naye user se replace ho jata tha.
/// 2. Har jagah DateTime.now() ki jagah FieldValue.serverTimestamp()
class AdminService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Logger _logger = Logger();

  // NOTE: addUserDirectly() yahan se HATA diya gaya hai.
  // Staff add karne ka SIRF ek rasta hai: Admin invite generate
  // karta hai (InviteService.generateInvite) → user apne device
  // par invite se signup karta hai (AuthService).
  // Wajah: admin ke device par createUserWithEmailAndPassword
  // chalane se admin ka login session naye user se badal jata tha.

  // 1. GET ALL USERS
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

  // 2. EDIT USER
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
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': _auth.currentUser!.uid,
      });
      _logger.i("User updated: $userId | New role: $newRole");
      return true;
    } catch (e) {
      _logger.e("editUserInfo error: $e");
      return false;
    }
  }

// NAYA: doctor ki saari future Requested/Confirmed appointments
  // cancel karo + full refund set karo — jab doctor deactivate/delete
  // ho, taake patient wait na kare kabhi na aane wale doctor ka.
  Future<void> _cancelDoctorAppointments(String doctorId) async {
    try {
      final apptSnap = await _firestore
          .collection('appointments')
          .where('doctorId', isEqualTo: doctorId)
          .where('status', whereIn: ['Requested', 'Confirmed']).get();

      for (final apptDoc in apptSnap.docs) {
        final apptRef = apptDoc.reference;
        final apptData = apptDoc.data();
        final slotId = apptData['slotId'];

        // Payment dhoondo (agar Paid hai, refund karna hai)
        final paySnap = await _firestore
            .collection('payments')
            .where('appointmentId', isEqualTo: apptDoc.id)
            .where('status', isEqualTo: 'Paid')
            .limit(1)
            .get();

        await _firestore.runTransaction((transaction) async {
          // READS pehle
          final apptSnapshot = await transaction.get(apptRef);
          if (!apptSnapshot.exists) return;

          DocumentReference? slotRef;
          bool slotExists = false;
          if (slotId != null) {
            slotRef = _firestore.collection('slots').doc(slotId);
            final slotSnap = await transaction.get(slotRef);
            slotExists = slotSnap.exists;
          }

          // WRITES
          transaction.update(apptRef, {
            'status': 'Cancelled',
            'updatedAt': FieldValue.serverTimestamp(),
          });

          if (slotRef != null && slotExists) {
            transaction.delete(slotRef);
          }

          if (paySnap.docs.isNotEmpty) {
            final payRef = paySnap.docs.first.reference;
            final payAmount = paySnap.docs.first.data()['amount'] ?? 0;
            transaction.update(payRef, {
              'status': 'Refunded',
              'refundAmount': payAmount,
              'refundPaid': false,
            });
          }
        });
        // ── NOTIFICATION: Appointment Cancelled → Patient ──
        final patientId = apptData['patientId'];
        if (patientId != null) {
          await NotificationService.send(
            userId: patientId,
            type: 'Appointment',
            referenceId: apptDoc.id,
            message: 'Your appointment was cancelled because the doctor '
                'is no longer available. A full refund is being processed.',
          );
        }
      }
      _logger.w(
          "Cancelled ${apptSnap.docs.length} appointments for doctor: $doctorId");
    } catch (e) {
      _logger.e("_cancelDoctorAppointments error: $e");
    }
  }

  // 3. DEACTIVATE USER
  Future<bool> deactivateUser(String userId) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'status': 'inactive',
        'deactivatedAt': FieldValue.serverTimestamp(),
        'deactivatedBy': _auth.currentUser!.uid,
      });
      await _cancelDoctorAppointments(
          userId); // koi appointment na ho to kuch nahi karega
      _logger.w("User deactivated: $userId");
      return true;
    } catch (e) {
      _logger.e("deactivateUser error: $e");
      return false;
    }
  }

  // 4. REACTIVATE USER
  Future<bool> reactivateUser(String userId) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'status': 'active',
        'reactivatedAt': FieldValue.serverTimestamp(),
      });
      _logger.i("User reactivated: $userId");
      return true;
    } catch (e) {
      _logger.e("reactivateUser error: $e");
      return false;
    }
  }

  // 5. RESET PASSWORD
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

  // 6. DELETE USER (SOFT DELETE — schema rule)
  Future<bool> deleteUser(String userId) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'status': 'deleted',
        'deletedAt': FieldValue.serverTimestamp(),
        'deletedBy': _auth.currentUser!.uid,
      });
      await _cancelDoctorAppointments(userId);
      _logger.w("User deleted (soft): $userId");
      return true;
    } catch (e) {
      _logger.e("deleteUser error: $e");
      return false;
    }
  }

  // 7. SEARCH USERS
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

  // 8. FILTER BY ROLE
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
