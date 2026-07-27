import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
import 'package:emailjs/emailjs.dart' as emailjs;

class InviteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Logger _logger = Logger();

  // 1. GENERATE INVITE
  // FIX: pehle inviteCode timestamp se banta tha (INVITE-1784905218084)
  // — guessable tha. Ab Firestore ki apni random 20-character ID use
  // hoti hai (e.g. "Xk9fT2mQpL7aB3nRw8sD") — guess karna impossible.
  Future<String?> generateInvite({
    required String doctorName,
    required String email,
    required String role,
    required String specialization,
    required String phone,
    String departmentId = '',
    String license = '',
  }) async {
    try {
      // Firestore se free random unique ID lo — yehi inviteCode hai
      final inviteRef = _firestore.collection('invites').doc();
      final String inviteCode = inviteRef.id;

      await inviteRef.set({
        'inviteCode': inviteCode,
        'email': email,
        'name': doctorName,
        'role': role,
        'specialization': specialization,
        'phone': phone,
        'departmentId': departmentId,
        'license': license,
        'used': false,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': DateTime.now().add(const Duration(days: 7)),
        'createdBy': _auth.currentUser!.uid,
      });

      _logger
          .i("Invite generated: $inviteCode | Sent to: $email | Role: $role");
      return inviteCode;
    } catch (e) {
      _logger.e("generateInvite error: $e");
      return null;
    }
  }

  // 2. SEND INVITE EMAIL - EMAILJS
  //
  // ⚠️ TODO (security): yeh keys code mein hard-coded hain — koi bhi
  // APK decompile kar ke nikal sakta hai. Viva se pehle inhe ek alag
  // config file mein le jao jo .gitignore mein ho. Demo ke liye chalega.
  Future<bool> sendInviteEmail({
    required String email,
    required String inviteCode,
    required String name,
  }) async {
    try {
      String inviteLink =
          'https://hospitalmanagement-7605b.web.app?code=$inviteCode';

      _logger.i("Sending Email to: $email | Code: $inviteCode");

      await emailjs.send(
        'service_sc6wvhf',
        'template_iqvnejd',
        {
          'to_name': name.trim(),
          'to_email': email.trim(),
          'invite_code': inviteCode.trim(),
          'invite_link': inviteLink.trim(),
        },
        const emailjs.Options(
          publicKey: 't9GKgQhfS3KtJuTuA',
          privateKey: 'gSiQF2VczS6mP4Oo4I-7A',
        ),
      );

      _logger.i("✅ Email sent to: $email");
      return true;
    } catch (e) {
      _logger.e("❌ Email error: $e");
      return false;
    }
  }

  // 3. VALIDATE INVITE
  Future<Map<String, dynamic>?> validateInvite(String inviteCode) async {
    try {
      DocumentSnapshot doc =
          await _firestore.collection('invites').doc(inviteCode).get();

      if (!doc.exists) throw "Invalid invite code";

      Map<String, dynamic> inviteData = doc.data() as Map<String, dynamic>;

      if (inviteData['used'] == true) throw "Invite already used";

      DateTime expiresAt = inviteData['expiresAt'].toDate();
      if (DateTime.now().isAfter(expiresAt)) throw "Invite expired";

      _logger.i("Invite validated: $inviteCode");
      return inviteData;
    } catch (e) {
      _logger.e("validateInvite error: $e");
      return null;
    }
  }

  // 4. GET ALL INVITES
  Future<List<Map<String, dynamic>>> getInvites() async {
    try {
      QuerySnapshot snap = await _firestore.collection('invites').get();
      return snap.docs
          .map((doc) => doc.data() as Map<String, dynamic>)
          .toList();
    } catch (e) {
      _logger.e("getInvites error: $e");
      return [];
    }
  }

  // 5. REVOKE INVITE
  Future<bool> revokeInvite(String inviteCode) async {
    try {
      await _firestore
          .collection('invites')
          .doc(inviteCode)
          .update({'used': true});
      return true;
    } catch (e) {
      _logger.e("revokeInvite error: $e");
      return false;
    }
  }

  // NOTE: markAsUsed() yahan se HATA diya gaya hai.
  // Invite ko "used" mark karna ab AuthService ke signup
  // transaction ke ANDAR hota hai — taake do log same invite
  // ek saath use na kar sakein. (Dekho auth_service.dart)

  // 6. IS EXPIRED
  Future<bool> isExpired(String inviteCode) async {
    try {
      DocumentSnapshot doc =
          await _firestore.collection('invites').doc(inviteCode).get();
      if (!doc.exists) return true;
      Map<String, dynamic> inviteData = doc.data() as Map<String, dynamic>;
      DateTime expiresAt = inviteData['expiresAt'].toDate();
      return DateTime.now().isAfter(expiresAt);
    } catch (e) {
      _logger.e("isExpired error: $e");
      return true;
    }
  }
}
