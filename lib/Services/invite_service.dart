import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
import 'package:emailjs/emailjs.dart' as emailjs;

class InviteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Logger _logger = Logger();

  // 1. GENERATE INVITE
  Future<String?> generateInvite({
    required String doctorName,
    required String email,
    required String role,
    required String specialization,
    required String phone,
  }) async {
    try {
      String inviteCode = 'INVITE-${DateTime.now().millisecondsSinceEpoch}';

      await _firestore.collection('invites').doc(inviteCode).set({
        'code': inviteCode,
        'email': email,
        'name': doctorName,
        'role': role,
        'specialization': specialization,
        'phone': phone,
        'used': false,
        'createdAt': DateTime.now(),
        'expiresAt': DateTime.now().add(Duration(days: 7)),
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
  Future<bool> sendInviteEmail({
    required String email,
    required String inviteCode,
    required String name,
  }) async {
    try {
      String inviteLink =
          'https://hospitalmanagement-7605b.web.app?code=$inviteCode';

      _logger.i("Sending Email...");
      _logger.i("Email: $email");
      _logger.i("Name: $name");
      _logger.i("Invite Code: $inviteCode");
      _logger.i("Invite Link: $inviteLink");

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

  // 6. MARK AS USED
  Future<bool> markAsUsed(String inviteCode) async {
    try {
      await _firestore.collection('invites').doc(inviteCode).update({
        'used': true,
        'usedAt': DateTime.now(),
      });
      return true;
    } catch (e) {
      _logger.e("markAsUsed error: $e");
      return false;
    }
  }

  // 7. IS EXPIRED
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
