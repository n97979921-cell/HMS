import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/notification_service.dart';
import '../widgets/app_ui.dart';

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
  static const Color _primary = Color(0xFF0B2E33);

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
          backgroundColor: const Color(0xFF8A6D00),
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
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Confirm payment received'),
        content: Text('Patient: ${test['patientName']}\n'
            'Test: ${test['testType']}\n\n'
            'Cash received: Rs. ${test['charge']}?'),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.muted),
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
      // ── NOTIFICATION: Lab Payment Done → Patient ──
      await NotificationService.send(
        userId: test['patientId'] ?? '',
        type: 'Lab',
        referenceId: test['testId'],
        message:
            'Your lab payment has been received. Test: ${test['testType']}.',
      );

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
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Cancel this test?'),
        content: const Text(
            'Use this if the patient does not want to proceed with the '
            'test. No payment has been collected yet.'),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.muted),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB23A1E), elevation: 0),
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
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.teal))
                : _pending.isEmpty
                    ? _buildEmpty()
                    : RefreshIndicator(
                        onRefresh: _loadAndProcess,
                        color: AppColors.teal,
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                          itemCount: _pending.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (ctx, i) => _card(_pending[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  // UI only: header total is calculated from the already-loaded list
  num _chargeOf(Map<String, dynamic> t) {
    final c = t['charge'];
    if (c is num) return c;
    return num.tryParse('$c') ?? 0;
  }

  Widget _buildHeader() {
    final num total = _pending.fold<num>(0, (sum, t) => sum + _chargeOf(t));
    final count = _pending.length;
    return AppHeader(
      title: 'Lab payments',
      subtitle: 'Collect cash and send test to lab',
      bottom: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('To collect',
                    style: TextStyle(
                        color: AppColors.headerMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(_isLoading ? '—' : 'Rs. $total',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.mint.withOpacity(0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count test${count == 1 ? '' : 's'} pending',
              style: const TextStyle(
                  color: AppColors.mint,
                  fontSize: 12,
                  fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return const SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: AppEmptyState(
        icon: Icons.science_outlined,
        title: 'No pending lab payments',
      ),
    );
  }

  Widget _card(Map<String, dynamic> test) {
    final isProcessing = _processingId == test['testId'];

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppIconTile(
                icon: Icons.science_outlined,
                color: AppColors.blue,
                background: AppColors.blueSoft,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(test['patientName'],
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.text)),
                    const SizedBox(height: 3),
                    Text('${test['testType']} · Dr. ${test['doctorName']}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
              Text('Rs. ${test['charge']}',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0B5E57))),
            ],
          ),
          const SizedBox(height: 14),
          if (isProcessing)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(color: AppColors.teal),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _cancelTest(test),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFFF0C9BE)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancel',
                        style: TextStyle(
                            color: Color(0xFF9A2E16),
                            fontSize: 14,
                            fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () => _markPaid(test),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.header,
                      elevation: 0,
                      minimumSize: const Size.fromHeight(44),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Mark as Paid',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
