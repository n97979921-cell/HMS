import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';

/// FIXES:
/// 1. login() ab {'success': bool, 'user'/'error': ...} deta hai
///    (pehle null deta tha — user ko wajah nahi milti thi)
/// 2. Invite signups TRANSACTION mein invite re-check + mark-used karte
///    hain (double-use bug fix)
/// 3. Transaction fail par orphan Firebase Auth account delete
/// 4. serverTimestamp() har jagah
/// 5. admin/doctor/labstaff/receptionist — sab invite se ban sakte hain
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Logger _logger = Logger();

  // 1. PATIENT SIGNUP
  Future<bool> patientSignup({
    required String email,
    required String password,
    required String name,
    required String phone,
    required String cnic,
    required int age,
    required String gender,
  }) async {
    try {
      UserCredential cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      await cred.user!.sendEmailVerification();

      await _firestore.collection('users').doc(cred.user!.uid).set({
        'uid': cred.user!.uid,
        'email': email,
        'name': name,
        'phone': phone,
        'cnic': cnic,
        'role': 'patient',
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _firestore.collection('patient_profiles').doc(cred.user!.uid).set({
        'patientId': cred.user!.uid,
        'age': age,
        'gender': gender,
        'bloodGroup': null,
        'allergies': null,
        'chronicConditions': null,
        'patientType': 'REGISTERED',
      });

      _logger.i("Patient signup successful: $email");
      return true;
    } catch (e) {
      _logger.e("Patient signup error: $e");
      return false;
    }
  }

  // 2. LOGIN (SAB ROLES)
  // Success: {'success': true,  'user': userData}
  // Fail:    {'success': false, 'error': 'reason'}
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      UserCredential cred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      DocumentSnapshot userDoc =
          await _firestore.collection('users').doc(cred.user!.uid).get();

      if (!userDoc.exists) {
        await _auth.signOut();
        return {'success': false, 'error': 'User not found in database'};
      }

      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;

      if (userData['status'] != 'active') {
        await _auth.signOut();
        return {
          'success': false,
          'error': 'Your account is inactive. Contact the administrator.'
        };
      }

      await cred.user!.reload();

      String userRole = userData['role'] ?? '';
      if (userRole == 'patient' && !cred.user!.emailVerified) {
        await _auth.signOut();
        return {
          'success': false,
          'error': 'Please verify your email first. Check your inbox.'
        };
      }

      return {'success': true, 'user': userData};
    } on FirebaseAuthException catch (e) {
      _logger.e("Login FirebaseAuth error: ${e.code}");
      String message;
      switch (e.code) {
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          message = 'Incorrect email or password';
          break;
        case 'invalid-email':
          message = 'Invalid email format';
          break;
        case 'user-disabled':
          message = 'This account has been disabled';
          break;
        case 'too-many-requests':
          message = 'Too many attempts. Try again later.';
          break;
        default:
          message = 'Login failed. Please try again.';
      }
      return {'success': false, 'error': message};
    } catch (e) {
      _logger.e("Login error: $e");
      return {'success': false, 'error': 'Login failed. Please try again.'};
    }
  }

  // 3. LOGOUT
  Future<void> logout() async {
    try {
      await _auth.signOut();
      _logger.i("Logged out successfully");
    } catch (e) {
      _logger.e("Logout error: $e");
    }
  }

  // 4. VERIFY USER ROLE
  Future<String?> verifyRole(String userId) async {
    try {
      DocumentSnapshot userDoc =
          await _firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) return null;
      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
      return userData['role'];
    } catch (e) {
      _logger.e("Error verifying role: $e");
      return null;
    }
  }

  // 5. VERIFY EMAIL
  Future<bool> verifyEmail() async {
    try {
      User? firebaseUser = _auth.currentUser;
      if (firebaseUser == null) return false;
      if (firebaseUser.emailVerified) return true;
      await firebaseUser.sendEmailVerification();
      return true;
    } catch (e) {
      _logger.e("Error sending verification email: $e");
      return false;
    }
  }

  // 6. FORGOT PASSWORD
  Future<bool> forgotPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return true;
    } catch (e) {
      _logger.e("Forgot password error: $e");
      return false;
    }
  }

  // ─── INVITE SIGNUP — SHARED HELPER (transaction-safe) ───
  Future<bool> _signupWithInvite({
    required String inviteCode,
    required String password,
    required Map<String, dynamic> Function(
            String uid, Map<String, dynamic> inviteData)
        buildUserDoc,
    Map<String, dynamic> Function(String uid, Map<String, dynamic> inviteData)?
        buildProfileDoc,
    String? profileCollection,
  }) async {
    UserCredential? cred;
    try {
      final inviteRef = _firestore.collection('invites').doc(inviteCode);
      final inviteDoc = await inviteRef.get();

      if (!inviteDoc.exists) throw "Invalid invite code";
      final inviteData = inviteDoc.data()!;
      if (inviteData['used'] == true) throw "This invite has already been used";
      final DateTime expiresAt = inviteData['expiresAt'].toDate();
      if (DateTime.now().isAfter(expiresAt)) throw "This invite has expired";

      cred = await _auth.createUserWithEmailAndPassword(
        email: inviteData['email'],
        password: password,
      );
      final String uid = cred.user!.uid;

      await _firestore.runTransaction((transaction) async {
        final freshInvite = await transaction.get(inviteRef);
        if (!freshInvite.exists || freshInvite.data()!['used'] == true) {
          throw "This invite has already been used";
        }

        transaction.set(
          _firestore.collection('users').doc(uid),
          buildUserDoc(uid, inviteData),
        );

        if (profileCollection != null && buildProfileDoc != null) {
          transaction.set(
            _firestore.collection(profileCollection).doc(uid),
            buildProfileDoc(uid, inviteData),
          );
        }

        transaction.update(inviteRef, {
          'used': true,
          'usedAt': FieldValue.serverTimestamp(),
        });
      });

      _logger.i("Invite signup successful: ${inviteData['email']}");
      return true;
    } catch (e) {
      _logger.e("Invite signup error: $e");
      try {
        await cred?.user?.delete();
      } catch (deleteError) {
        _logger.e("Orphan cleanup failed: $deleteError");
      }
      return false;
    }
  }

  // 7. DOCTOR SIGNUP
  Future<bool> doctorSignupWithInvite({
    required String inviteCode,
    required String password,
  }) {
    return _signupWithInvite(
      inviteCode: inviteCode,
      password: password,
      buildUserDoc: (uid, invite) => {
        'uid': uid,
        'email': invite['email'],
        'name': invite['name'],
        'role': invite['role'],
        'status': 'active',
        'phone': invite['phone'] ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'inviteCode': inviteCode,
      },
      profileCollection: 'doctor_profiles',
      buildProfileDoc: (uid, invite) => {
        'doctorId': uid,
        'specialization': invite['specialization'] ?? '',
        'license': invite['license'] ?? '',
        'departmentId': invite['departmentId'] ?? '',
      },
    );
  }

  // 8. LAB STAFF SIGNUP
  Future<bool> labStaffSignupWithInvite({
    required String inviteCode,
    required String password,
  }) {
    return _signupWithInvite(
      inviteCode: inviteCode,
      password: password,
      buildUserDoc: (uid, invite) => {
        'uid': uid,
        'email': invite['email'],
        'name': invite['name'],
        'role': 'labstaff',
        'phone': invite['phone'] ?? '',
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'inviteCode': inviteCode,
      },
    );
  }

  // 9. RECEPTIONIST SIGNUP
  Future<bool> receptionistSignupWithInvite({
    required String inviteCode,
    required String password,
  }) {
    return _signupWithInvite(
      inviteCode: inviteCode,
      password: password,
      buildUserDoc: (uid, invite) => {
        'uid': uid,
        'email': invite['email'],
        'name': invite['name'],
        'role': 'receptionist',
        'phone': invite['phone'] ?? '',
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'inviteCode': inviteCode,
      },
    );
  }

  // 10. ADMIN SIGNUP
  Future<bool> adminSignupWithInvite({
    required String inviteCode,
    required String password,
  }) {
    return _signupWithInvite(
      inviteCode: inviteCode,
      password: password,
      buildUserDoc: (uid, invite) => {
        'uid': uid,
        'email': invite['email'],
        'name': invite['name'],
        'role': 'admin',
        'phone': invite['phone'] ?? '',
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'inviteCode': inviteCode,
      },
    );
  }

  // 11. GET CURRENT USER
  Future<Map<String, dynamic>?> getCurrentUser() async {
    try {
      User? firebaseUser = _auth.currentUser;
      if (firebaseUser == null) return null;
      DocumentSnapshot userDoc =
          await _firestore.collection('users').doc(firebaseUser.uid).get();
      return userDoc.data() as Map<String, dynamic>?;
    } catch (e) {
      _logger.e("getCurrentUser error: $e");
      return null;
    }
  }

  // 12. UPDATE USER PROFILE
  Future<bool> updateUserProfile({
    required String userId,
    required Map<String, dynamic> data,
  }) async {
    try {
      await _firestore.collection('users').doc(userId).update(data);
      return true;
    } catch (e) {
      _logger.e("updateUserProfile error: $e");
      return false;
    }
  }

  // 13. CHECK IF EMAIL EXISTS
  Future<bool> emailExists(String email) async {
    try {
      final result = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .get();
      return result.docs.isNotEmpty;
    } catch (e) {
      _logger.e("emailExists error: $e");
      return false;
    }
  }
}
