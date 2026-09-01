import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/notification_service.dart';

/// REFUNDS PENDING SCREEN (Receptionist)
///
/// Jab bhi koi payment Refunded ya HalfRefunded ho lekin refundPaid:false,
/// matlab paisa abhi patient ko wapas dena baaki hai. Yeh screen woh sab
/// dikhati hai. Receptionist paisa de kar (cash counter / EasyPaisa)
/// "Mark as Refunded" dabaye → refundPaid: true.
///
/// - Refunded     = full refund dena hai
/// - HalfRefunded = aadha refund dena hai (NoShow)
class RefundsPendingScreen extends StatefulWidget {
  const RefundsPendingScreen({super.key});

  @override
  State<RefundsPendingScreen> createState() => _RefundsPendingScreenState();
}

class _RefundsPendingScreenState extends State<RefundsPendingScreen> {
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _primaryDark = Color(0xFF0D6B5A);

  bool _isLoading = true;
  List<Map<String, dynamic>> _refunds = [];

  @override
  void initState() {
    super.initState();
    _loadRefunds();
  }

  Future<void> _loadRefunds() async {
    setState(() => _isLoading = true);
    try {
      // Refunded ya HalfRefunded + refundPaid == false
      final snap = await FirebaseFirestore.instance
          .collection('payments')
          .where('status', whereIn: ['Refunded', 'HalfRefunded'])
          .where('refundPaid', isEqualTo: false)
          .get();

      final List<Map<String, dynamic>> result = [];
      for (final doc in snap.docs) {
        final data = doc.data();

        // Patient ka naam aur phone
        String patientName = 'Patient';
        String patientPhone = '';
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(data['patientId'])
              .get();
          patientName = userDoc.data()?['name'] ?? 'Patient';
          patientPhone = userDoc.data()?['phone'] ?? '';
        } catch (_) {}

// Doctor name aur slot time
        String doctorName = '';
        String apptTime = '';
        try {
          final apptDoc = await FirebaseFirestore.instance
              .collection('appointments')
              .doc(data['appointmentId'])
              .get();
          if (apptDoc.exists) {
            final doctorId = apptDoc.data()?['doctorId'];
            if (doctorId != null) {
              final doctorDoc = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(doctorId)
                  .get();
              doctorName = doctorDoc.data()?['name'] ?? '';
            }
            final slotId = apptDoc.data()?['slotId'];
            if (slotId != null) {
              final slotDoc = await FirebaseFirestore.instance
                  .collection('slots')
                  .doc(slotId)
                  .get();
              final date = slotDoc.data()?['date'] ?? '';
              final time = slotDoc.data()?['startTime'] ?? '';
              apptTime = '$date $time';
            }
          }
        } catch (_) {}

        // Lab test name fetch karo
        String testType = '';
        if (data['type'] == 'Lab' && data['referenceId'] != null) {
          try {
            final labDoc = await FirebaseFirestore.instance
                .collection('lab_tests')
                .doc(data['referenceId'])
                .get();
            testType = labDoc.data()?['testType'] ?? '';
          } catch (_) {}
        }

        result.add({
          'paymentId': doc.id,
          'patientId': data['patientId'],
          'patientName': patientName,
          'patientPhone': patientPhone,
          'doctorName': doctorName,
          'apptTime': apptTime,
          'amount': data['amount'] ?? 0,
          'refundAmount': data['refundAmount'],
          'status': data['status'],
          'paymentMethod': data['paymentMethod'] ?? 'Online',
          'type': data['type'] ?? 'Consultation',
          'testType': testType,
        });
      }

      setState(() {
        _refunds = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Error loading refunds: $e');
    }
  }

  // Refund de diya → refundPaid: true
  Future<void> _markRefunded(Map<String, dynamic> refund) async {
    final isHalf = refund['status'] == 'HalfRefunded';
    final refundAmt = refund['refundAmount'] ??
        (isHalf ? (refund['amount'] / 2) : refund['amount']);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm refund paid?'),
        content:
            Text('Have you given Rs. $refundAmt to ${refund['patientName']} '
                '(${refund['paymentMethod']})? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not yet'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: _primary),
            child: const Text('Yes, refund given',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      await FirebaseFirestore.instance
          .collection('payments')
          .doc(refund['paymentId'])
          .update({
        'refundPaid': true,
        'refundAmount': refundAmt,
        'refundedBy': uid,
        'refundedAt': FieldValue.serverTimestamp(),
      });
      // ── NOTIFICATION: Refund Processed → Patient ──
      await NotificationService.send(
        userId: refund['patientId'] ?? '',
        type: 'Payment',
        referenceId: refund['paymentId'],
        message: 'Your refund of Rs. $refundAmt has been processed.',
      );
      _showSuccess('Refund marked as paid');
      _loadRefunds();
    } catch (e) {
      _showError('Error: $e');
    }
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
                  : _refunds.isEmpty
                      ? _buildEmpty()
                      : RefreshIndicator(
                          onRefresh: _loadRefunds,
                          color: _primary,
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                            itemCount: _refunds.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (ctx, i) => _refundCard(_refunds[i]),
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
          const Text('Pending Refunds',
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
          const Text('No pending refunds',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280))),
          const SizedBox(height: 6),
          const Text('All refunds have been paid',
              style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
        ],
      ),
    );
  }

  Widget _refundCard(Map<String, dynamic> refund) {
    final isHalf = refund['status'] == 'HalfRefunded';
    final refundAmt = refund['refundAmount'] ??
        (isHalf ? (refund['amount'] / 2) : refund['amount']);

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
                    Text(refund['patientName'],
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A2F3A))),
                    const SizedBox(height: 2),
                    Text('Dr. ${refund['doctorName']}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54)),
                    const SizedBox(height: 2),
                    Text('${refund['type']} · ${refund['paymentMethod']}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54)),
                    if (refund['type'] == 'Lab') ...[
                      const SizedBox(height: 2),
                      Text(
                        '${refund['testType']}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54),
                      ),
                    ],
                    if (refund['type'] == 'Consultation') ...[
                      const SizedBox(height: 2),
                      Text(
                        '${refund['apptTime']}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54),
                      ),
                    ],
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.phone,
                            size: 12, color: Colors.black54),
                        const SizedBox(width: 4),
                        Text(
                          refund['patientPhone'],
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF0D6B6B),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isHalf
                      ? const Color(0xFFFCEFD8)
                      : const Color(0xFFFDE6E0),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isHalf ? 'Half Refund' : 'Full Refund',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isHalf
                        ? const Color(0xFFB8860B)
                        : const Color(0xFFD9534F),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F7F6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Amount to refund',
                    style: TextStyle(fontSize: 12, color: Colors.black54)),
                Text('Rs. $refundAmt',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _primaryDark)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _markRefunded(refund),
              icon: const Icon(Icons.check, size: 18, color: Colors.white),
              label: const Text('Mark as Refunded',
                  style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
