import 'package:cloud_firestore/cloud_firestore.dart';

/// NOTIFICATION SERVICE — reusable helper, har trigger-point se call hoga.
///
/// Schema:
///   notifications
///     userId, type, referenceId, message, isRead, createdAt
///
/// type ke options (schema se):
///   Appointment | Lab | Room | Payment | RoomRecommendation | VideoConsultation
///
/// ⚠️ NOTE (schema se): referenceId ko kabhi seedha use mat karo bina
/// 'type' check kiye — alag types ke liye referenceId alag cheezon
/// (appointmentId/testId/paymentId/bedId) ko point karta hai.
class NotificationService {
  static final _firestore = FirebaseFirestore.instance;

  /// Ek notification banata hai. Sab trigger-points isi ek function
  /// ko call karenge — taake duplicate-code na ho.
  static Future<void> send({
    required String userId,
    required String
        type, // Appointment|Lab|Room|Payment|RoomRecommendation|VideoConsultation
    required String referenceId,
    required String message,
  }) async {
    try {
      final ref = _firestore.collection('notifications').doc();
      await ref.set({
        'notificationId': ref.id,
        'userId': userId,
        'type': type,
        'referenceId': referenceId,
        'message': message,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Silent fail — notification na banne se main-action (booking,
      // payment, etc.) fail nahi honi chahiye. Yeh sirf "nice-to-have"
      // hai, core-flow ko block nahi karna.
    }
  }

  /// Ek saath do logon ko notify karna ho (jaise Doctor+Patient dono)
  static Future<void> sendToMultiple({
    required List<String> userIds,
    required String type,
    required String referenceId,
    required String message,
  }) async {
    for (final userId in userIds) {
      await send(
        userId: userId,
        type: type,
        referenceId: referenceId,
        message: message,
      );
    }
  }
}
