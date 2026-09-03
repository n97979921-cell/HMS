import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/notification_service.dart';

/// VERIFY PAYMENTS SCREEN (Receptionist) — Pending | Expired tabs
///
/// PENDING tab: payments jinki appointment abhi bhi Requested hai
/// (slot-time nahi guzra). 3 actions:
///   1. VERIFY & CONFIRM  → payment: Paid | appointment: Confirmed | slot: BOOKED
///   2. VERIFY BUT CANCEL → payment: Refunded (full) | appointment: Cancelled
///      (doctor unavailable) | slot: DELETE
///   3. REJECT            → payment: Rejected | appointment: Cancelled |
///      slot: DELETE (fake screenshot, koi refund nahi)
///
/// LAZY-CHECK (list load hote waqt): agar koi Pending payment ki
/// appointment ka slot-time GUZAR CHUKA hai (>= 24 hours se receptionist
/// ne kuch nahi kiya), to appointment KHUD auto-Cancel + slot DELETE ho
/// jati hai — LEKIN payment Pending hi rehti hai (touch nahi karte).
/// Aisi payments "Expired" tab mein chali jaati hain.
///
/// EXPIRED tab: payment abhi bhi Pending hai lekin appointment ab
/// Cancelled ho chuki (waqt guzarne ki wajah se, receptionist na verify
/// kar payi na reject). Sirf 2 actions (Confirm nahi — slot ja chuka):
///   - Refund  → payment: Refunded (full) — screenshot asli tha
///   - Reject  → payment: Rejected (koi refund) — screenshot fake tha
///
/// ✅ REAL-TIME (Rule 2): Data `payments` + `appointments` + `users` +
/// `slots` se milkar banta hai, is liye poori screen StreamBuilder mein
/// convert NAHI ki. Iski jagah ek lightweight listener `payments`
/// collection ko sunta hai (status == 'Pending' filter ke saath) —
/// jaise hi patient screenshot upload kare (nayi Pending payment ban
/// jaye), ya koi payment yahan se process ho (status badle), list
/// khud-ba-khud dobara load ho jaati hai.
class VerifyPaymentsScreen extends StatefulWidget {
  const VerifyPaymentsScreen({super.key});

  @override
  State<VerifyPaymentsScreen> createState() => _VerifyPaymentsScreenState();
}

class _VerifyPaymentsScreenState extends State<VerifyPaymentsScreen> {
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _primaryDark = Color(0xFF0D6B5A);

  String _selectedTab = 'Pending'; // Pending | Expired
  bool _isLoading = true;
  String? _processingId;
  int _autoExpired = 0;

  List<Map<String, dynamic>> _pending = [];
  List<Map<String, dynamic>> _expired = [];

  // Real-time listener — sirf `payments` collection ko sunta hai
  // (status == 'Pending' filter ke saath).
  StreamSubscription<QuerySnapshot>? _paymentsSub;

  @override
  void initState() {
    super.initState();
    _setupRealtimeListener();
  }

  @override
  void dispose() {
    _paymentsSub?.cancel();
    super.dispose();
  }

  void _setupRealtimeListener() {
    // Pehla event hi initial load ka kaam kar deta hai, is liye alag
    // se _loadAndProcess() call karne ki zaroorat nahi.
    _paymentsSub = FirebaseFirestore.instance
        .collection('payments')
        .where('status', isEqualTo: 'Pending')
        .snapshots()
        .listen((_) {
      _loadAndProcess();
    }, onError: (_) {
      setState(() => _isLoading = false);
    });
  }

  // ── Load: pehle 24hr-expired appointments process karo, phir list ──
  Future<void> _loadAndProcess() async {
    setState(() {
      _isLoading = true;
      _autoExpired = 0;
    });
    try {
      final snap = await FirebaseFirestore.instance
          .collection('payments')
          .where('status', isEqualTo: 'Pending')
          .get();

      final List<Map<String, dynamic>> pendingResult = [];
      final List<Map<String, dynamic>> expiredResult = [];

      for (final doc in snap.docs) {
        final data = doc.data();
        final apptId = data['appointmentId'];

        final apptDoc = await FirebaseFirestore.instance
            .collection('appointments')
            .doc(apptId)
            .get();
        if (!apptDoc.exists) continue;
        final appt = apptDoc.data()!;

        // Agar receptionist ne pehle hi Cancel kar diya (timeout se) —
        // seedha Expired list mein
        if (appt['status'] == 'Cancelled') {
          expiredResult.add(await _buildRow(doc.id, data, appt));
          continue;
        }

        // Sirf Requested payments pe LAZY 24hr CHECK
        if (appt['status'] == 'Requested') {
          final slotId = appt['slotId'];
          DateTime? slotDateTime;
          if (slotId != null) {
            final slotDoc = await FirebaseFirestore.instance
                .collection('slots')
                .doc(slotId)
                .get();
            if (slotDoc.exists) {
              slotDateTime = _parseSlotDateTime(
                  slotDoc.data()!['date'], slotDoc.data()!['startTime']);
            }
          }

          final now = DateTime.now();
          final createdAt = data['createdAt'];
          DateTime? bookedAt;
          if (createdAt is Timestamp) bookedAt = createdAt.toDate();

          final slotExpired = slotDateTime != null && now.isAfter(slotDateTime);
          final bookingTooOld =
              bookedAt != null && now.difference(bookedAt).inHours >= 24;

          if (slotExpired || bookingTooOld) {
            // AUTO-CANCEL appointment + slot, payment CHHUO MAT
            await _autoCancelExpired(apptId, slotId);
            _autoExpired++;
            expiredResult.add(await _buildRow(doc.id, data, {
              ...appt,
              'status': 'Cancelled', // local reflect
            }));
            continue;
          }

          pendingResult.add(await _buildRow(doc.id, data, appt));
        }
      }

      if (!mounted) return;
      setState(() {
        _pending = pendingResult;
        _expired = expiredResult;
        _isLoading = false;
      });

      if (_autoExpired > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '$_autoExpired appointment(s) auto-cancelled (slot expired) — review payment in Expired tab'),
          backgroundColor: const Color(0xFFB8860B),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('Error loading payments: $e');
    }
  }

  DateTime? _parseSlotDateTime(dynamic date, dynamic startTime) {
    try {
      final d = DateTime.parse(date as String);
      final p = (startTime as String).split(':').map(int.parse).toList();
      return DateTime(d.year, d.month, d.day, p[0], p[1]);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _buildRow(String paymentId,
      Map<String, dynamic> data, Map<String, dynamic> appt) async {
    String patientName = 'Patient';
    String doctorName = '';
    String slotLabel = '';
    try {
      final p = await FirebaseFirestore.instance
          .collection('users')
          .doc(data['patientId'])
          .get();
      patientName = p.data()?['name'] ?? 'Patient';
      final d = await FirebaseFirestore.instance
          .collection('users')
          .doc(appt['doctorId'])
          .get();
      doctorName = d.data()?['name'] ?? '';

      // Slot date+time bhi fetch karo — receptionist ko dikhna zaroori hai
      final slotId = appt['slotId'];
      if (slotId != null) {
        final slotDoc = await FirebaseFirestore.instance
            .collection('slots')
            .doc(slotId)
            .get();
        if (slotDoc.exists) {
          final s = slotDoc.data()!;
          slotLabel = '${s['date']} · ${s['startTime']}';
        }
      }
    } catch (_) {}

    return {
      'paymentId': paymentId,
      'appointmentId': data['appointmentId'],
      'patientId': data['patientId'],
      'patientName': patientName,
      'doctorName': doctorName,
      'slotLabel': slotLabel,
      'amount': data['amount'] ?? 0,
      'screenshotBase64': data['screenshotBase64'],
      'transactionId': data['transactionId'],
    };
  }

  // Slot-time guzar gaya, payment abhi bhi Pending — appointment auto-Cancel
  // + slot DELETE. Payment ko yahan CHHUO MAT — receptionist Expired tab
  // se dekh kar Refund/Reject decide karegi.
  Future<void> _autoCancelExpired(String apptId, String? slotId) async {
    try {
      final apptRef =
          FirebaseFirestore.instance.collection('appointments').doc(apptId);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final apptSnap = await transaction.get(apptRef);
        if (!apptSnap.exists) return;
        if (apptSnap.data()!['status'] != 'Requested') return; // double-check

        DocumentReference? slotRef;
        bool slotExists = false;
        if (slotId != null) {
          slotRef = FirebaseFirestore.instance.collection('slots').doc(slotId);
          final slotSnap = await transaction.get(slotRef);
          slotExists = slotSnap.exists;
        }

        transaction.update(apptRef, {
          'status': 'Cancelled',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (slotRef != null && slotExists) transaction.delete(slotRef);
      });
    } catch (_) {
      // Silent — agli load par dobara try hoga
    }
  }

  // ── PENDING tab actions ──

  Future<void> _verifyConfirm(Map<String, dynamic> payment) async {
    setState(() => _processingId = payment['paymentId']);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final paymentRef = FirebaseFirestore.instance
          .collection('payments')
          .doc(payment['paymentId']);
      final apptRef = FirebaseFirestore.instance
          .collection('appointments')
          .doc(payment['appointmentId']);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final apptSnap = await transaction.get(apptRef);
        if (!apptSnap.exists) throw Exception('Appointment not found');
        final slotId = apptSnap.data()!['slotId'];

        final slotRef =
            FirebaseFirestore.instance.collection('slots').doc(slotId);
        final slotSnap = await transaction.get(slotRef);

        transaction.update(paymentRef, {
          'status': 'Paid',
          'verifiedBy': uid,
          'paidAt': FieldValue.serverTimestamp(),
        });
        transaction.update(apptRef, {
          'status': 'Confirmed',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (slotSnap.exists) {
          transaction.update(slotRef, {
            'slotStatus': 'BOOKED',
            'appointmentId': payment['appointmentId'],
            'heldByAppointmentId': null,
          });
        }
      });

      // ── NOTIFICATION: Appointment Confirmed → Patient ──
      // Sab appointment-types (IN_PERSON/WALK_IN/VIDEO_CALL) ke liye
      // Patient ko yeh notification jaati hai. Doctor ko VIDEO_CALL
      // ke liye bhi NAHI bhejni (schema-decision).
      await NotificationService.send(
        userId: payment['patientId'] ?? '',
        type: 'Appointment',
        referenceId: payment['appointmentId'],
        message: 'Your appointment has been confirmed.',
      );

      _showSuccess('Payment verified — appointment confirmed');
      _loadAndProcess();
    } catch (e) {
      _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _processingId = null);
    }
  }

  Future<void> _verifyButCancel(Map<String, dynamic> payment) async {
    setState(() => _processingId = payment['paymentId']);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final paymentRef = FirebaseFirestore.instance
          .collection('payments')
          .doc(payment['paymentId']);
      final apptRef = FirebaseFirestore.instance
          .collection('appointments')
          .doc(payment['appointmentId']);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final apptSnap = await transaction.get(apptRef);
        if (!apptSnap.exists) throw Exception('Appointment not found');
        final slotId = apptSnap.data()!['slotId'];
        final slotRef =
            FirebaseFirestore.instance.collection('slots').doc(slotId);
        final slotSnap = await transaction.get(slotRef);

        transaction.update(paymentRef, {
          'status': 'Refunded',
          'verifiedBy': uid,
          'paidAt': FieldValue.serverTimestamp(),
          'refundAmount': payment['amount'],
          'refundPaid': false,
        });
        transaction.update(apptRef, {
          'status': 'Cancelled',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (slotSnap.exists) transaction.delete(slotRef);
      });

      // ── NOTIFICATION: Appointment Cancelled → Patient ──
      // (Refund-notification alag trigger hai — Step 9 mein, jab
      // receptionist actual paisa de kar "Mark as Refunded" kare)
      await NotificationService.send(
        userId: payment['patientId'] ?? '',
        type: 'Appointment',
        referenceId: payment['appointmentId'],
        message: 'Your appointment was cancelled by the hospital. A full '
            'refund is being processed.',
      );

      _showSuccess('Verified & cancelled — full refund pending');
      _loadAndProcess();
    } catch (e) {
      _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _processingId = null);
    }
  }

  Future<void> _reject(Map<String, dynamic> payment) async {
    setState(() => _processingId = payment['paymentId']);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final paymentRef = FirebaseFirestore.instance
          .collection('payments')
          .doc(payment['paymentId']);
      final apptRef = FirebaseFirestore.instance
          .collection('appointments')
          .doc(payment['appointmentId']);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final apptSnap = await transaction.get(apptRef);
        if (!apptSnap.exists) throw Exception('Appointment not found');
        final slotId = apptSnap.data()!['slotId'];
        final slotRef =
            FirebaseFirestore.instance.collection('slots').doc(slotId);
        final slotSnap = await transaction.get(slotRef);

        transaction
            .update(paymentRef, {'status': 'Rejected', 'verifiedBy': uid});
        transaction.update(apptRef, {
          'status': 'Cancelled',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (slotSnap.exists) transaction.delete(slotRef);
      });

      // ── NOTIFICATION: Appointment Cancelled → Patient ──
      await NotificationService.send(
        userId: payment['patientId'] ?? '',
        type: 'Appointment',
        referenceId: payment['appointmentId'],
        message: 'Your appointment was cancelled — the payment screenshot '
            'could not be verified.',
      );

      _showSuccess('Payment rejected — slot freed');
      _loadAndProcess();
    } catch (e) {
      _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _processingId = null);
    }
  }

  // ── EXPIRED tab actions (appointment already Cancelled — sirf payment) ──

  Future<void> _expiredRefund(Map<String, dynamic> payment) async {
    setState(() => _processingId = payment['paymentId']);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      await FirebaseFirestore.instance
          .collection('payments')
          .doc(payment['paymentId'])
          .update({
        'status': 'Refunded',
        'verifiedBy': uid,
        'refundAmount': payment['amount'],
        'refundPaid': false,
      });
      _showSuccess('Marked for refund — screenshot was valid');
      _loadAndProcess();
    } catch (e) {
      _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _processingId = null);
    }
  }

  Future<void> _expiredReject(Map<String, dynamic> payment) async {
    setState(() => _processingId = payment['paymentId']);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      await FirebaseFirestore.instance
          .collection('payments')
          .doc(payment['paymentId'])
          .update({'status': 'Rejected', 'verifiedBy': uid});
      _showSuccess('Rejected — no refund (invalid screenshot)');
      _loadAndProcess();
    } catch (e) {
      _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _processingId = null);
    }
  }

  // ── Dialogs ──

  void _confirmReject(Map<String, dynamic> payment) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reject payment?'),
        content: const Text(
            'Use this if the screenshot is invalid or fake. The appointment '
            'will be cancelled and the slot freed. No refund.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _reject(payment);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reject', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _confirmVerifyButCancel(Map<String, dynamic> payment) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Verify but cancel?'),
        content: Text(
            'Use this if the payment is genuine but the doctor is not '
            'available. The appointment will be cancelled and a FULL refund '
            'of Rs. ${payment['amount']} will be added to pending refunds.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _verifyButCancel(payment);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB8860B)),
            child: const Text('Cancel & Refund',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _confirmExpiredRefund(Map<String, dynamic> payment) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Refund this payment?'),
        content: Text(
            'The slot already expired and the appointment was auto-cancelled. '
            'Use this if the screenshot looks valid — a FULL refund of '
            'Rs. ${payment['amount']} will be added to pending refunds.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _expiredRefund(payment);
            },
            style: ElevatedButton.styleFrom(backgroundColor: _primary),
            child: const Text('Refund', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _confirmExpiredReject(Map<String, dynamic> payment) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reject this payment?'),
        content: const Text(
            'Use this if the screenshot is invalid or fake. No refund will '
            'be given.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _expiredReject(payment);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reject', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: const Color(0xFFDB4437),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: _primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _viewScreenshot(String base64Str) {
    showDialog(
      context: context,
      builder: (_) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 5.0,
                child: Image.memory(base64Decode(base64Str)),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _selectedTab == 'Pending' ? _pending : _expired;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTabToggle(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: _primary))
                  : list.isEmpty
                      ? _buildEmpty()
                      : RefreshIndicator(
                          onRefresh: _loadAndProcess,
                          color: _primary,
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                            itemCount: list.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 14),
                            itemBuilder: (ctx, i) => _selectedTab == 'Pending'
                                ? _pendingCard(list[i])
                                : _expiredCard(list[i]),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      color: _primaryDark,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.arrow_back, color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 14),
          const Text('Verify Payments',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildTabToggle() {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 14, 18, 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)
        ],
      ),
      child: Row(
        children: [
          _tabButton('Pending', _pending.length),
          _tabButton('Expired', _expired.length),
        ],
      ),
    );
  }

  Widget _tabButton(String label, int count) {
    final isSelected = _selectedTab == label;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = label),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? _primary : Colors.transparent,
            borderRadius: BorderRadius.circular(26),
          ),
          alignment: Alignment.center,
          child: Text(
            count > 0 ? '$label ($count)' : label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.grey,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    final isPending = _selectedTab == 'Pending';
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(isPending ? Icons.check_circle_outline : Icons.history_outlined,
              size: 64, color: _primary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(isPending ? 'No pending payments' : 'No expired payments',
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280))),
        ],
      ),
    );
  }

  Widget _screenshotPreview(String? base64Img) {
    if (base64Img == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => _viewScreenshot(base64Img),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              base64Decode(base64Img),
              height: 160,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 160,
                color: const Color(0xFFF0F0F0),
                alignment: Alignment.center,
                child: const Text('Could not load screenshot',
                    style: TextStyle(color: Colors.grey)),
              ),
            ),
          ),
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.zoom_in, color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pendingCard(Map<String, dynamic> p) {
    final isProcessing = _processingId == p['paymentId'];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p['patientName'],
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A2F3A))),
                    if (p['doctorName'] != '')
                      Text(
                        p['slotLabel'] != null && p['slotLabel'] != ''
                            ? 'Dr. ${p['doctorName']} · ${p['slotLabel']}'
                            : 'Dr. ${p['doctorName']}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54),
                      ),
                  ],
                ),
              ),
              Text('Rs. ${p['amount']}',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: _primary)),
            ],
          ),
          if (p['transactionId'] != null) ...[
            const SizedBox(height: 4),
            Text('TID: ${p['transactionId']}',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
          const SizedBox(height: 12),
          _screenshotPreview(p['screenshotBase64']),
          const SizedBox(height: 12),
          if (isProcessing)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(color: _primary),
              ),
            )
          else ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _verifyConfirm(p),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Verify & Confirm',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _confirmReject(p),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      side: const BorderSide(color: Color(0xFFD9534F)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Reject',
                        style: TextStyle(
                            color: Color(0xFFD9534F),
                            fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _confirmVerifyButCancel(p),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      side: const BorderSide(color: Color(0xFFB8860B)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Verify + Cancel',
                        style: TextStyle(
                            color: Color(0xFFB8860B),
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _expiredCard(Map<String, dynamic> p) {
    final isProcessing = _processingId == p['paymentId'];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFCEFD8)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFCEFD8),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text('SLOT EXPIRED — appointment auto-cancelled',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFB8860B))),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p['patientName'],
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A2F3A))),
                    if (p['doctorName'] != '')
                      Text('Dr. ${p['doctorName']}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54)),
                  ],
                ),
              ),
              Text('Rs. ${p['amount']}',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: _primary)),
            ],
          ),
          const SizedBox(height: 12),
          _screenshotPreview(p['screenshotBase64']),
          const SizedBox(height: 12),
          if (isProcessing)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(color: _primary),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _confirmExpiredReject(p),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Color(0xFFD9534F)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Reject (no refund)',
                        style: TextStyle(
                            color: Color(0xFFD9534F),
                            fontWeight: FontWeight.w600,
                            fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _confirmExpiredRefund(p),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Refund',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}