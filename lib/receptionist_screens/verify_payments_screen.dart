import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// VERIFY PAYMENTS SCREEN (Receptionist)
///
/// Pending consultation payments dikhata hai. Receptionist screenshot
/// dekh kar 3 mein se ek action leta hai:
///
///  1. VERIFY & CONFIRM  → screenshot sahi, sab theek
///       payment: Paid | appointment: Confirmed | slot: BOOKED
///
///  2. VERIFY BUT CANCEL → screenshot sahi (paisa asli aaya), LEKIN
///     (doctor said no)     doctor ne is slot ke liye mana kiya
///       payment: Refunded (refundPaid:false) | appointment: Cancelled
///       | slot: DELETE  → Full refund banta hai (Refunds Pending mein)
///
///  3. REJECT           → screenshot fake/galat, paisa aaya hi nahi
///       payment: Rejected | appointment: Cancelled | slot: DELETE
///       Koi refund
class VerifyPaymentsScreen extends StatefulWidget {
  const VerifyPaymentsScreen({super.key});

  @override
  State<VerifyPaymentsScreen> createState() => _VerifyPaymentsScreenState();
}

class _VerifyPaymentsScreenState extends State<VerifyPaymentsScreen> {
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _primaryDark = Color(0xFF0D6B5A);

  bool _isLoading = true;
  String? _processingId; // jis payment pe kaam ho raha hai
  List<Map<String, dynamic>> _payments = [];

  @override
  void initState() {
    super.initState();
    _loadPending();
  }

  Future<void> _loadPending() async {
    setState(() => _isLoading = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('payments')
          .where('status', isEqualTo: 'Pending')
          .get();

      final List<Map<String, dynamic>> result = [];
      for (final doc in snap.docs) {
        final data = doc.data();

        // Patient naam + doctor naam + slot time
        String patientName = 'Patient';
        String doctorName = '';
        String slotLabel = '';
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(data['patientId'])
              .get();
          patientName = userDoc.data()?['name'] ?? 'Patient';

          final apptDoc = await FirebaseFirestore.instance
              .collection('appointments')
              .doc(data['appointmentId'])
              .get();
          if (apptDoc.exists) {
            final apptData = apptDoc.data()!;
            final docDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(apptData['doctorId'])
                .get();
            doctorName = docDoc.data()?['name'] ?? '';

            final slotId = apptData['slotId'];
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
          }
        } catch (_) {}

        result.add({
          'paymentId': doc.id,
          'appointmentId': data['appointmentId'],
          'patientName': patientName,
          'doctorName': doctorName,
          'slotLabel': slotLabel,
          'amount': data['amount'] ?? 0,
          'screenshotBase64': data['screenshotBase64'],
          'transactionId': data['transactionId'],
        });
      }

      setState(() {
        _payments = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Error loading payments: $e');
    }
  }

  // ── ACTION 1: Verify & Confirm ────────────────────────────
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
        // READS pehle
        final apptSnap = await transaction.get(apptRef);
        if (!apptSnap.exists) throw Exception('Appointment not found');
        final slotId = apptSnap.data()!['slotId'];
        final slotRef =
            FirebaseFirestore.instance.collection('slots').doc(slotId);
        final slotSnap = await transaction.get(slotRef);

        // WRITES baad
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

      _showSuccess('Payment verified — appointment confirmed');
      _loadPending();
    } catch (e) {
      _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _processingId = null);
    }
  }

  // ── ACTION 2: Verify but Cancel (doctor said no) + FULL refund ──
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

        // payment: Refunded (full), refundPaid false (Refunds Pending mein aayega)
        transaction.update(paymentRef, {
          'status': 'Refunded',
          'verifiedBy': uid,
          'paidAt': FieldValue.serverTimestamp(),
          'refundAmount': payment['amount'], // full
          'refundPaid': false,
        });
        transaction.update(apptRef, {
          'status': 'Cancelled',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (slotSnap.exists) transaction.delete(slotRef); // slot free
      });

      _showSuccess('Verified & cancelled — full refund pending');
      _loadPending();
    } catch (e) {
      _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _processingId = null);
    }
  }

  // ── ACTION 3: Reject (fake screenshot) — no refund ────────
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

        transaction.update(paymentRef, {
          'status': 'Rejected',
          'verifiedBy': uid,
        });
        transaction.update(apptRef, {
          'status': 'Cancelled',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (slotSnap.exists) transaction.delete(slotRef);
      });

      _showSuccess('Payment rejected — slot freed');
      _loadPending();
    } catch (e) {
      _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _processingId = null);
    }
  }

  // ── Confirmation dialogs ──────────────────────────────────
  void _confirmReject(Map<String, dynamic> payment) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reject payment?'),
        content: const Text(
            'Use this if the screenshot is invalid or fake. The appointment '
            'will be cancelled and the slot freed. No refund (no money '
            'received).'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
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
            'available for this slot. The appointment will be cancelled and '
            'a FULL refund of Rs. ${payment['amount']} will be added to '
            'pending refunds.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back'),
          ),
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

  // Screenshot full-screen zoom (pinch / scroll / drag)
  void _openScreenshotZoom(String base64Img) {
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
                child: Image.memory(base64Decode(base64Img)),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: _primary))
                  : _payments.isEmpty
                      ? _buildEmpty()
                      : RefreshIndicator(
                          onRefresh: _loadPending,
                          color: _primary,
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                            itemCount: _payments.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 14),
                            itemBuilder: (ctx, i) => _paymentCard(_payments[i]),
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

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline,
              size: 64, color: _primary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          const Text('No pending payments',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280))),
        ],
      ),
    );
  }

  Widget _paymentCard(Map<String, dynamic> payment) {
    final isProcessing = _processingId == payment['paymentId'];
    final base64Img = payment['screenshotBase64'];

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
                    Text(payment['patientName'],
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A2F3A))),
                    const SizedBox(height: 2),
                    Text(
                      '${payment['doctorName']} · ${payment['slotLabel']}',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              Text('Rs. ${payment['amount']}',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: _primary)),
            ],
          ),
          if (payment['transactionId'] != null) ...[
            const SizedBox(height: 4),
            Text('TID: ${payment['transactionId']}',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
          const SizedBox(height: 12),
          if (base64Img != null)
            Stack(
              children: [
                GestureDetector(
                  onTap: () => _openScreenshotZoom(base64Img),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      base64Decode(base64Img),
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        height: 180,
                        color: const Color(0xFFF0F0F0),
                        alignment: Alignment.center,
                        child: const Text('Could not load screenshot',
                            style: TextStyle(color: Colors.grey)),
                      ),
                    ),
                  ),
                ),
                // Zoom button (purane version jaisa)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: () => _openScreenshotZoom(base64Img),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.zoom_in,
                          color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),
          if (isProcessing)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(color: _primary),
              ),
            )
          else ...[
            // Action 1: Verify & Confirm (full width, primary)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _verifyConfirm(payment),
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
                // Action 3: Reject
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _confirmReject(payment),
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
                // Action 2: Verify but Cancel (doctor said no)
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _confirmVerifyButCancel(payment),
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
}
