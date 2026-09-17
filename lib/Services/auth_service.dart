// lib/services/auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:logger/logger.dart';

/// FIXES:
/// 1. login() ab {'success': bool, 'user'/'error': ...} deta hai
/// 2. Invite signups TRANSACTION mein invite re-check + mark-used karte hain
/// 3. Transaction fail par orphan Firebase Auth account delete
/// 4. serverTimestamp() har jagah
/// 5. admin/doctor/labstaff/receptionist — sab invite se ban sakte hain
/// 6. Google Sign-In — LOGIN screen ka feature hai, signup nahi.
///    Account picker sab roles ki emails dikhata hai (ye OS/Google ka
///    apna native chooser hai, app control nahi karta), role-check
///    tabhi hota hai jab account select ho jaye:
///      - role != patient          -> "only for patients" error
///      - patient, record maujood  -> normal login
///      - patient, record nahi hai -> "email not registered" error
///        (Google se naya account is function se KABHI nahi banta)
/// 7. google_sign_in v6.2.2 API — GoogleSignIn() instance object,
///    .signIn() (null return hota hai agar user cancel kare),
///    .authentication ek Future hai (await lagta hai).
/// 8. NAYA — patientSignup() ab {'success': bool, 'error': String?}
///    return karta hai (login() jaisa hi pattern), pehle sirf bool
///    deta tha jis se asal Firebase error (email already in use,
///    weak password, Firestore permission-denied, waghera) screen
///    par kabhi nahi dikhta tha — sirf generic "Registration failed"
///    aata tha.
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Logger _logger = Logger();

  // Firebase Console > Authentication > Sign-in method > Google >
  // Web SDK configuration > Web client ID (yehi wala, jo aapne diya)
  static const String _webClientId =
      '904098371260-h7ds81cbguoji0ae7d1cfujj9unpuhaq.apps.googleusercontent.com';

  // v6.2.2 mein GoogleSignIn ek normal instance hai — koi separate
  // initialize() call ki zaroorat nahi (jo v7+ mein zaroori thi).
  // serverClientId isliye diya taake authentication.idToken mile
  // (Firebase credential banane ke liye zaroori hai).
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: _webClientId,
  );
  // Google Sign-In LOGIN screen ke liye hai — SIGNUP is method se kabhi nahi hota.

  // 1. PATIENT SIGNUP
  // NAYA: ab {'success': bool, 'error': String?} return karta hai
  // (login() jaisa hi pattern) — taake asal Firebase/Firestore error
  // screen par dikh sake, generic "Registration failed" ke peeche
  // chhupa na rahe.
  Future<Map<String, dynamic>> patientSignup({
    required String email,
    required String password,
    required String name,
    required String phone,
    required String cnic,
    required int age,
    required String gender,
  }) async {
    UserCredential? cred;
    try {
      cred = await _auth.createUserWithEmailAndPassword(
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
      return {'success': true};
    } on FirebaseAuthException catch (e) {
      _logger.e("Patient signup FirebaseAuth error: ${e.code}");
      String message;
      switch (e.code) {
        case 'email-already-in-use':
          message = 'This email is already registered. Try logging in.';
          break;
        case 'invalid-email':
          message = 'Invalid email format';
          break;
        case 'weak-password':
          message = 'Password is too weak (minimum 6 characters)';
          break;
        case 'network-request-failed':
          message = 'No internet connection. Please try again.';
          break;
        default:
          message = 'Registration failed: ${e.message ?? e.code}';
      }
      // Auth account ban chuka ho lekin baad mein fail ho to orphan
      // account clean up karo, taake wahi email dobara try ki ja sake.
      try {
        await cred?.user?.delete();
      } catch (_) {}
      return {'success': false, 'error': message};
    } catch (e) {
      _logger.e("Patient signup error: $e");
      try {
        await cred?.user?.delete();
      } catch (_) {}
      // Yahan aane wala error mostly Firestore security-rules /
      // permission-denied hota hai (Auth account ban chuka tha lekin
      // 'users' ya 'patient_profiles' collection mein likhne se
      // roka gaya) — is liye raw error message hi dikhate hain.
      return {'success': false, 'error': 'Registration failed: $e'};
    }
  }

  // 2. LOGIN (SAB ROLES)
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

  // 2b. GOOGLE SIGN-IN — LOGIN SCREEN ONLY, PATIENT ONLY
  // (koi bhi role account picker mein apni email dekh/select kar sakta hai —
  // ye Android/Google ka apna native chooser hai, app isay control nahi karta.
  // Behavior account select hone ke BAAD decide hota hai.)
  //
  //   - role != patient          -> error: only for patients
  //   - patient, record maujood  -> normal login
  //   - patient, record NAHI hai -> error: email not registered
  //     (Google se naya account YAHAN se kabhi nahi banta — signup hamesha
  //     email/password form se hota hai)
  //
  // Success (existing patient): {'success': true, 'user': userData}
  // Fail: {'success': false, 'error': 'reason'}
  Future<Map<String, dynamic>> signInWithGoogle() async {
    try {
      // Pehle purani cached Google session clear karo, taake
      // hamesha fresh account-picker screen dikhe (na ke silently
      // wahi purana account use ho jaye). Isi wajah se error ke baad
      // dobara button dabane par sab accounts ki list phir dikhti hai.
      await _googleSignIn.signOut();

      // v6.2.2: signIn() null return karta hai agar user ne dialog
      // cancel kar diya — koi exception throw nahi hoti.
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        return {'success': false, 'error': 'Google sign-in cancelled'};
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      if (googleAuth.idToken == null) {
        return {
          'success': false,
          'error': 'Google sign-in failed. Please try again.'
        };
      }

      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
        accessToken: googleAuth.accessToken,
      );

      final userCred = await _auth.signInWithCredential(credential);
      final firebaseUser = userCred.user!;

      final userDoc =
          await _firestore.collection('users').doc(firebaseUser.uid).get();

      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;

        if (userData['status'] != 'active') {
          await _auth.signOut();
          return {
            'success': false,
            'error': 'Your account is inactive. Contact the administrator.'
          };
        }
        // Security check: only patients can use Google Sign-In.
        // Doctor/Admin/Receptionist/LabStaff accounts are invite-based.
        if (userData['role'] != 'patient') {
          await _auth.signOut();
          return {
            'success': false,
            'error': 'This sign-in method is only available for patients.'
          };
        }

        return {'success': true, 'user': userData};
      }

      // Is Google uid ke against Firestore me koi record nahi hai.
      // Login screen se naya account kabhi nahi banega — signup
      // hamesha email/password form se hota hai.
      await _auth.signOut();
      return {
        'success': false,
        'error': 'This email is not registered. Please sign up first.'
      };
    } on FirebaseAuthException catch (e) {
      _logger.e("Google sign-in FirebaseAuth error: ${e.code}");
      if (e.code == 'account-exists-with-different-credential') {
        return {
          'success': false,
          'error':
              'This email is already registered with a password. Please log in using your email and password instead.'
        };
      }
      return {
        'success': false,
        'error': 'Google sign-in failed. Please try again.'
      };
    } catch (e) {
      _logger.e("Google sign-in error: $e");
      return {
        'success': false,
        'error': 'Google sign-in failed. Please try again.'
      };
    }
  }

  // 2c. COMPLETE PROFILE AFTER FIRST GOOGLE SIGN-IN (patient only)
  Future<bool> completeGooglePatientProfile({
    required String uid,
    required String email,
    required String name,
    required String phone,
    required String cnic,
    required int age,
    required String gender,
  }) async {
    try {
      await _firestore.collection('users').doc(uid).set({
        'uid': uid,
        'email': email,
        'name': name,
        'phone': phone,
        'cnic': cnic,
        'role': 'patient',
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _firestore.collection('patient_profiles').doc(uid).set({
        'patientId': uid,
        'age': age,
        'gender': gender,
        'bloodGroup': null,
        'allergies': null,
        'chronicConditions': null,
        'patientType': 'REGISTERED',
      });

      _logger.i("Google patient profile completed: $email");
      return true;
    } catch (e) {
      _logger.e("completeGooglePatientProfile error: $e");
      return false;
    }
  }

  // 3. LOGOUT
  Future<void> logout() async {
    try {
      await _auth.signOut();
      await _googleSignIn.signOut();
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