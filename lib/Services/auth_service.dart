import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';

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
      // Firebase Auth mein create kar
      UserCredential cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Email verification bhej
      await cred.user!.sendEmailVerification();

      // Firestore mein user entry create kar
      await _firestore.collection('users').doc(cred.user!.uid).set({
        'uid': cred.user!.uid,
        'email': email,
        'name': name,
        'phone': phone,
        'cnic': cnic,
        'role': 'patient',
        'age': age,
        'gender': gender,
        'status': 'active',
        'patientType': 'REGISTERED',
        'createdAt': DateTime.now(),
      });

      _logger.i("Patient signup successful: $email");
      return true;
    } catch (e) {
      _logger.e("Patient signup error: $e");
      return false;
    }
  }

  // 2. LOGIN (SABB ROLES KE LIYE)
  Future<Map<String, dynamic>?> login({
    required String email,
    required String password,
  }) async {
    try {
      UserCredential cred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Firestore se user data le
      DocumentSnapshot userDoc =
          await _firestore.collection('users').doc(cred.user!.uid).get();

      if (!userDoc.exists) {
        throw "User not found in database";
      }

      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;

      // Check: user active hai?
      if (userData['status'] != 'active') {
        throw "User account is inactive";
      }

      await cred.user!.reload();

      // Check: email verified hai?
      String userRole = userData['role'] ?? '';
      if (userRole == 'patient' && !cred.user!.emailVerified) {
        throw "Please verify your email first";
      }

      return userData; // Return user data
    } catch (e) {
      _logger.e("Login error: $e");
      return null;
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

      if (!userDoc.exists) {
        _logger.e("User not found: $userId");
        return null;
      }

      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
      String role = userData['role'];

      _logger.i("User role verified: $role");
      return role;
    } catch (e) {
      _logger.e("Error verifying role: $e");
      return null;
    }
  }

  // 5. VERIFY EMAIL
  Future<bool> verifyEmail() async {
    try {
      User? firebaseUser = _auth.currentUser;

      if (firebaseUser == null) {
        _logger.e("No user logged in");
        return false;
      }

      if (firebaseUser.emailVerified) {
        _logger.i("Email already verified");
        return true;
      }

      await firebaseUser.sendEmailVerification();
      _logger.i("Verification email sent to ${firebaseUser.email}");
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
      _logger.i("Password reset email sent to $email");
      return true;
    } catch (e) {
      _logger.e("Forgot password error: $e");
      return false;
    }
  }

  // 7. DOCTOR SIGNUP (VIA INVITE)
  Future<bool> doctorSignupWithInvite({
    required String inviteCode,
    required String password,
  }) async {
    try {
      // 1. Invite validate kar
      DocumentSnapshot inviteDoc =
          await _firestore.collection('invites').doc(inviteCode).get();

      if (!inviteDoc.exists) {
        throw "Invalid invite code";
      }

      Map<String, dynamic> inviteData =
          inviteDoc.data() as Map<String, dynamic>;

      if (inviteData['used'] == true) {
        throw "This invite has already been used";
      }

      DateTime expiresAt = inviteData['expiresAt'].toDate();
      if (DateTime.now().isAfter(expiresAt)) {
        throw "This invite has expired";
      }

      // 2. Firebase Auth mein account create kar
      UserCredential cred = await _auth.createUserWithEmailAndPassword(
        email: inviteData['email'],
        password: password,
      );

      // 3. Firestore mein user entry
      await _firestore.collection('users').doc(cred.user!.uid).set({
        'uid': cred.user!.uid,
        'email': inviteData['email'],
        'name': inviteData['name'],
        'role': inviteData['role'],
        'status': 'active',
        'specialization': inviteData['specialization'] ?? '',
        'phone': inviteData['phone'] ?? '',
        'createdAt': DateTime.now(),
        'inviteCode': inviteCode,
      });

      // 4. Invite ko "used" mark kar
      await _firestore
          .collection('invites')
          .doc(inviteCode)
          .update({'used': true});

      return true;
    } catch (e) {
      _logger.e("Doctor signup error: $e");
      return false;
    }
  }

// Lab Staff Signup (Via Invite)
  Future<bool> labStaffSignupWithInvite({
    required String inviteCode,
    required String password,
  }) async {
    try {
      DocumentSnapshot inviteDoc =
          await _firestore.collection('invites').doc(inviteCode).get();

      if (!inviteDoc.exists) {
        throw "Invalid invite code";
      }

      Map<String, dynamic> inviteData =
          inviteDoc.data() as Map<String, dynamic>;

      if (inviteData['used'] == true) {
        throw "This invite has already been used";
      }

      DateTime expiresAt = inviteData['expiresAt'].toDate();
      if (DateTime.now().isAfter(expiresAt)) {
        throw "This invite has expired";
      }

      UserCredential cred = await _auth.createUserWithEmailAndPassword(
        email: inviteData['email'],
        password: password,
      );

      await _firestore.collection('users').doc(cred.user!.uid).set({
        'uid': cred.user!.uid,
        'email': inviteData['email'],
        'name': inviteData['name'],
        'role': 'labstaff',
        'phone': inviteData['phone'] ?? '',
        'status': 'active',
        'createdAt': DateTime.now(),
        'inviteCode': inviteCode,
      });

      await _firestore
          .collection('invites')
          .doc(inviteCode)
          .update({'used': true});

      _logger.i("Lab Staff signup successful: ${inviteData['email']}");
      return true;
    } catch (e) {
      _logger.e("labStaffSignupWithInvite error: $e");
      return false;
    }
  }

  // Receptionist Signup (Via Invite)
  Future<bool> receptionistSignupWithInvite({
    required String inviteCode,
    required String password,
  }) async {
    try {
      DocumentSnapshot inviteDoc =
          await _firestore.collection('invites').doc(inviteCode).get();

      if (!inviteDoc.exists) {
        throw "Invalid invite code";
      }

      Map<String, dynamic> inviteData =
          inviteDoc.data() as Map<String, dynamic>;

      if (inviteData['used'] == true) {
        throw "This invite has already been used";
      }

      DateTime expiresAt = inviteData['expiresAt'].toDate();
      if (DateTime.now().isAfter(expiresAt)) {
        throw "This invite has expired";
      }

      UserCredential cred = await _auth.createUserWithEmailAndPassword(
        email: inviteData['email'],
        password: password,
      );

      await _firestore.collection('users').doc(cred.user!.uid).set({
        'uid': cred.user!.uid,
        'email': inviteData['email'],
        'name': inviteData['name'],
        'role': 'receptionist',
        'phone': inviteData['phone'] ?? '',
        'status': 'active',
        'createdAt': DateTime.now(),
        'inviteCode': inviteCode,
      });

      await _firestore
          .collection('invites')
          .doc(inviteCode)
          .update({'used': true});

      _logger.i("Receptionist signup successful: ${inviteData['email']}");
      return true;
    } catch (e) {
      _logger.e("receptionistSignupWithInvite error: $e");
      return false;
    }
  }

  // 8. GET CURRENT USER
  Future<Map<String, dynamic>?> getCurrentUser() async {
    try {
      User? firebaseUser = _auth.currentUser;

      if (firebaseUser == null) {
        _logger.w("getCurrentUser: No user is currently logged in");
        return null;
      }

      DocumentSnapshot userDoc =
          await _firestore.collection('users').doc(firebaseUser.uid).get();

      _logger.d("getCurrentUser: Fetched data for ${firebaseUser.uid}");
      return userDoc.data() as Map<String, dynamic>;
    } catch (e) {
      _logger.e("getCurrentUser error: $e");
      return null;
    }
  }

  // 9. UPDATE USER PROFILE
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

  // 10. CHECK IF EMAIL EXISTS
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

  // 11. RESET PASSWORD (ADMIN)
  Future<bool> resetUserPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return true;
    } catch (e) {
      _logger.e("resetUserPassword error: $e");
      return false;
    }
  }
}
