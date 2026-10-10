import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/notification_service.dart';
import '../widgets/app_ui.dart';

/// REFUNDS SCREEN (Receptionist)
///
/// Jab bhi koi payment Refunded ya HalfRefunded ho lekin refundPaid:false,
/// matlab paisa abhi patient ko wapas dena baaki hai. "Pending" tab woh
/// sab dikhati hai. Receptionist paisa de kar (cash counter / EasyPaisa)
/// "Mark as Refunded" dabaye → refundPaid: true.
///
/// - Refunded     = full refund dena hai
/// - HalfRefunded = aadha refund dena hai (NoShow)
///
/// NAYA — "Processed" tab: refundPaid: true wale records (jo pehle
/// kahin dikhte hi nahi the, sirf Firestore mein hamesha ke liye reh
/// jate the). Yahan har record par individual "Delete" hai, aur jab
/// list khali na ho ek "Delete All" button bhi — dono bina confirmation
/// ke seedha permanent delete karte hain, taake purana processed data
/// halka rakha ja sake.
///
/// ✅ REAL-TIME (Rule 2): Data `payments` + `users` (patient naam) se
/// milkar banta hai, is liye poori screen StreamBuilder mein convert
/// NAHI ki. Iski jagah ek lightweight listener `payments` collection
/// ko sunta hai (status Refunded/HalfRefunded + refundPaid == false
/// filter ke saath — sirf Pending tab ke liye relevant). Naya
/// refund-to-process aate hi list turant update ho jaati hai.
class RefundsPendingScreen extends StatefulWidget {
  const RefundsPendingScreen({super.key});

  @override
  State<RefundsPendingScreen> createState() => _RefundsPendingScreenState();
}

class _RefundsPendingScreenState extends State<RefundsPendingScreen> {
  static const Color _primary = Color(0xFF0B2E33);

  // 'Pending' | 'Processed'
  String _selectedTab = 'Pending';

  bool _isLoading = true;
  List<Map<String, dynamic>> _refunds = [];

  // Real-time listener — `payments` collection ko sunta hai (status
  // Refunded/HalfRefunded + refundPaid == false filter ke saath).
  // Sirf "Pending" tab ke liye relevant — "Processed" tab manually
  // load hota hai (_loadRefunds() dono tabs handle karta hai).
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
    // se _loadRefunds() call karne ki zaroorat nahi.
    _paymentsSub = FirebaseFirestore.instance
        .collection('payments')
        .where('status', whereIn: ['Refunded', 'HalfRefunded'])
        .where('refundPaid', isEqualTo: false)
        .snapshots()
        .listen((_) {
          // Sirf Pending tab par ho to hi is listener ki wajah se
          // reload karo — Processed tab ka apna refresh hota hai
          // (delete ke baad manually _loadRefunds() call hota hai).
          if (_selectedTab == 'Pending') _loadRefunds();
        }, onError: (_) {
          if (_selectedTab == 'Pending') setState(() => _isLoading = false);
        });
  }

  void _changeTab(String tab) {
    if (_selectedTab == tab) return;
    setState(() => _selectedTab = tab);
    _loadRefunds();
  }

  Future<void> _loadRefunds() async {
    setState(() => _isLoading = true);
    try {
      final bool wantPaid = _selectedTab == 'Processed';

      // Pending: Refunded/HalfRefunded + refundPaid == false
      // Processed: Refunded/HalfRefunded + refundPaid == true
      final snap = await FirebaseFirestore.instance
          .collection('payments')
          .where('status', whereIn: ['Refunded', 'HalfRefunded'])
          .where('refundPaid', isEqualTo: wantPaid)
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

      if (!mounted) return;
      setState(() {
        _refunds = result;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
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
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Confirm refund paid?'),
        content:
            Text('Have you given Rs. $refundAmt to ${refund['patientName']} '
                '(${refund['paymentMethod']})? This cannot be undone.'),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.muted),
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

  // ── Delete ek processed refund record — bina confirmation ke
  //    seedha permanent delete ──
  Future<void> _deleteRefund(String paymentId) async {
    try {
      await FirebaseFirestore.instance
          .collection('payments')
          .doc(paymentId)
          .delete();
      _showSuccess('Refund record deleted');
      _loadRefunds();
    } catch (e) {
      _showError('Error deleting: $e');
    }
  }

  // ── Delete All — SAARE processed (refundPaid: true) refund records
  //    ek batch write mein, bina confirmation ke ──
  Future<void> _deleteAllProcessed() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('payments')
          .where('status', whereIn: ['Refunded', 'HalfRefunded'])
          .where('refundPaid', isEqualTo: true)
          .get();

      if (snap.docs.isEmpty) return;

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      _showSuccess('${snap.docs.length} refund record(s) deleted');
      _loadRefunds();
    } catch (e) {
      _showError('Error deleting all: $e');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: const Color(0xFF9A2E16),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.teal,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _buildHeader(),
          if (_selectedTab == 'Processed' && !_isLoading && _refunds.isNotEmpty)
            _buildDeleteAllBar(),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.teal))
                : _refunds.isEmpty
                    ? _buildEmpty()
                    : RefreshIndicator(
                        onRefresh: _loadRefunds,
                        color: AppColors.teal,
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(
                              20, _selectedTab == 'Processed' ? 4 : 16, 20, 24),
                          itemCount: _refunds.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (ctx, i) => _refundCard(_refunds[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return AppHeader(
      title: 'Refunds',
      subtitle: 'Pay patients and mark done',
      bottom: _buildTabToggle(),
    );
  }

  Widget _buildTabToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _tabButton('Pending', 'Pending'),
          _tabButton('Processed', 'Processed'),
        ],
      ),
    );
  }

  Widget _tabButton(String label, String value) {
    final isSelected = _selectedTab == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => _changeTab(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 40,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.mint : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? AppColors.header : Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  // "Delete All" bar — sirf "Processed" tab par, jab list khali na ho.
  // Koi confirmation dialog nahi — seedha tap par saare processed
  // refund records permanent delete ho jaate hain.
  Widget _buildDeleteAllBar() {
    final n = _refunds.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$n processed record${n == 1 ? '' : 's'}',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.teal),
            ),
          ),
          GestureDetector(
            onTap: _deleteAllProcessed,
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.dangerSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete_sweep_outlined,
                      size: 16, color: AppColors.danger),
                  SizedBox(width: 6),
                  Text('Delete All',
                      style: TextStyle(
                          color: AppColors.danger,
                          fontSize: 12,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    final isProcessed = _selectedTab == 'Processed';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: AppEmptyState(
        icon: Icons.check_circle_outline,
        title: isProcessed ? 'No processed refunds' : 'No pending refunds',
        subtitle: isProcessed
            ? 'Refunds you\'ve paid out will show up here'
            : 'All refunds have been paid',
      ),
    );
  }

  Widget _subLine(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Text(text,
          style: const TextStyle(fontSize: 12, color: AppColors.muted)),
    );
  }

  Widget _refundCard(Map<String, dynamic> refund) {
    final isHalf = refund['status'] == 'HalfRefunded';
    final isProcessed = _selectedTab == 'Processed';
    final refundAmt = refund['refundAmount'] ??
        (isHalf ? (refund['amount'] / 2) : refund['amount']);

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(refund['patientName'],
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.text)),
                    _subLine('Dr. ${refund['doctorName']}'),
                    _subLine('${refund['type']} · ${refund['paymentMethod']}'),
                    if (refund['type'] == 'Lab')
                      _subLine('${refund['testType']}'),
                    if (refund['type'] == 'Consultation')
                      _subLine('${refund['apptTime']}'),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        const Icon(Icons.phone_outlined,
                            size: 13, color: AppColors.teal),
                        const SizedBox(width: 5),
                        Text(
                          refund['patientPhone'],
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.teal,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AppStatusChip(
                label: isHalf ? 'Half Refund' : 'Full Refund',
                colors: isHalf
                    ? const AppChipColors(Color(0xFF8A6D00), Color(0xFFF6F2E2))
                    : const AppChipColors(Color(0xFF9A2E16), Color(0xFFFBE6E0)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(isProcessed ? 'Amount refunded' : 'Amount to refund',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.muted)),
                Text('Rs. $refundAmt',
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0B5E57))),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (isProcessed)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _deleteRefund(refund['paymentId']),
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: Color(0xFF9A2E16)),
                label: const Text('Delete',
                    style: TextStyle(
                        color: Color(0xFF9A2E16),
                        fontSize: 14,
                        fontWeight: FontWeight.w800)),
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFFF0C9BE)),
                  minimumSize: const Size.fromHeight(44),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _markRefunded(refund),
                icon: const Icon(Icons.check_rounded,
                    size: 18, color: AppColors.mint),
                label: const Text('Mark as Refunded',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.header,
                  elevation: 0,
                  minimumSize: const Size.fromHeight(46),
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
