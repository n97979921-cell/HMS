import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// LAB PAYMENTS (Receptionist)
///
/// Doctor ne jo lab tests REQUEST kiye (status: Pending), unko yahan
/// receptionist dekh sakta hai — patient reception aaye to price
/// bataye, phir:
///   - Pay kare → "Mark as Paid" → paymentStatus: Paid, status: Confirmed
///     + payments record bane (type: Lab, Cash, Paid) → LAB SIDE visible
///   - Mana kare → "Cancel" → status: Cancelled, koi payment nahi bani
///
/// LAZY 24HR AUTO-CANCEL: agar test 24 ghante se Pending hai aur
/// patient nahi aaya, khud Cancelled ho jata hai.
class LabPaymentsScreen extends StatefulWidget {
  const LabPaymentsScreen({super.key});

  @override
  State<LabPaymentsScreen> createState() => _LabPaymentsScreenState();
}

class _LabPaymentsScreenState extends State<LabPaymentsScreen> {
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _primaryDark = Color(0xFF0D6B5A);

  bool _isLoading = true;
  String? _processingId;
  int _autoExpired = 0;
  List<Map<String, dynamic>> _pending = [];

  @override
  void initState() {
    super.initState();
    _loadAndProcess();
  }

  Future<void> _loadAndProcess() async {
    setState(() {
      _isLoading = true;
      _autoExpired = 0;
    });
    try {
      final snap = await FirebaseFirestore.instance
          .collection('lab_tests')
          .where('status', isEqualTo: 'Pending')
          .get();

      final List<Map<String, dynamic>> result = [];
      final now = DateTime.now();

      for (final doc in snap.docs) {
        final data = doc.data();

        // ── LAZY 24HR AUTO-CANCEL ──
        final createdAt = data['createdAt'];
        DateTime? createdDt;
        if (createdAt is Timestamp) createdDt = createdAt.toDate();

        if (createdDt != null && now.difference(createdDt).inHours >= 24) {
          await _autoCancel(doc.id);
          _autoExpired++;
          continue;
        }

        // Patient + doctor naam
        String patientName = 'Patient';
        String doctorName = '';
        try {
          final p = await FirebaseFirestore.instance
              .collection('users')
              .doc(data['patientId'])
              .get();
          patientName = p.data()?['name'] ?? 'Patient';
          final d = await FirebaseFirestore.instance
              .collection('users')
              .doc(data['doctorId'])
              .get();
          doctorName = d.data()?['name'] ?? '';
        } catch (_) {}

        result.add({
          'testId': doc.id,
          'appointmentId': data['appointmentId'],
          'patientId': data['patientId'],
          'patientName': patientName,
          'doctorName': doctorName,
          'testType': data['testType'] ?? '',
          'charge': data['charge'] ?? 0,
          'createdAt': createdDt,
        });
      }

      result.sort((a, b) {
        final ad = a['createdAt'] as DateTime?;
        final bd = b['createdAt'] as DateTime?;
        if (ad == null || bd == null) return 0;
        return ad.compareTo(bd); // oldest first
      });

      setState(() {
        _pending = result;
        _isLoading = false;
      });

      if (_autoExpired > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('$_autoExpired lab test(s) auto-cancelled (24hr timeout)'),
          backgroundColor: const Color(0xFFB8860B),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Error loading lab tests: $e');
    }
  }

  Future<void> _autoCancel(String testId) async {
    try {
      await FirebaseFirestore.instance
          .collection('lab_tests')
          .doc(testId)
          .update({
        'status': 'Cancelled',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Silent — agli load par dobara try hoga
    }
  }

  // ── Mark as Paid: payment collect + test Confirmed (visible to lab) ──
  Future<void> _markPaid(Map<String, dynamic> test) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm payment received'),
        content: Text('Patient: ${test['patientName']}\n'
            'Test: ${test['testType']}\n\n'
            'Cash received: Rs. ${test['charge']}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: _primary),
            child: const Text('Cash received — Confirm',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _processingId = test['testId']);
    try {
      final testRef = FirebaseFirestore.instance
          .collection('lab_tests')
          .doc(test['testId']);
      final paymentRef =
          FirebaseFirestore.instance.collection('payments').doc();

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final testSnap = await transaction.get(testRef);
        if (!testSnap.exists) throw Exception('Test not found');
        if (testSnap.data()?['status'] != 'Pending') {
          throw Exception('This test is no longer pending.');
        }

        transaction.update(testRef, {
          'status': 'Confirmed',
          'paymentStatus': 'Paid',
          'updatedAt': FieldValue.serverTimestamp(),
        });

        transaction.set(paymentRef, {
          'paymentId': paymentRef.id,
          'appointmentId': test['appointmentId'],
          'patientId': test['patientId'],
          'type': 'Lab',
          'amount': test['charge'],
          'paymentMethod': 'Cash',
          'status': 'Paid',
          'referenceId': test['testId'],
          'transactionId': null,
          'screenshotBase64': null,
          'refundAmount': null,
          'refundPaid': false,
          'verifiedBy': null,
          'createdAt': FieldValue.serverTimestamp(),
          'paidAt': FieldValue.serverTimestamp(),
        });
      });

      _showSuccess('Payment confirmed — test sent to lab');
      _loadAndProcess();
    } catch (e) {
      _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _processingId = null);
    }
  }

  // ── Cancel: patient mana kar de (koi payment nahi bani abhi) ──
  Future<void> _cancelTest(Map<String, dynamic> test) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel this test?'),
        content: const Text(
            'Use this if the patient does not want to proceed with the '
            'test. No payment has been collected yet.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Cancel Test',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _processingId = test['testId']);
    try {
      await FirebaseFirestore.instance
          .collection('lab_tests')
          .doc(test['testId'])
          .update({
        'status': 'Cancelled',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _showSuccess('Test cancelled');
      _loadAndProcess();
    } catch (e) {
      _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _processingId = null);
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
                  : _pending.isEmpty
                      ? _buildEmpty()
                      : RefreshIndicator(
                          onRefresh: _loadAndProcess,
                          color: _primary,
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                            itemCount: _pending.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (ctx, i) => _card(_pending[i]),
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
          const Text('Lab Payments',
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
          Icon(Icons.science_outlined,
              size: 64, color: _primary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          const Text('No pending lab payments',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280))),
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> test) {
    final isProcessing = _processingId == test['testId'];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFD9ECF8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.science_outlined,
                    color: Color(0xFF1565C0), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(test['patientName'],
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A2F3A))),
                    Text('${test['testType']} · Dr. ${test['doctorName']}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54)),
                  ],
                ),
              ),
              Text('Rs. ${test['charge']}',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: _primary)),
            ],
          ),
          const SizedBox(height: 14),
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
                    onPressed: () => _cancelTest(test),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Color(0xFFD9534F)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancel',
                        style: TextStyle(
                            color: Color(0xFFD9534F),
                            fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () => _markPaid(test),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Mark as Paid',
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
