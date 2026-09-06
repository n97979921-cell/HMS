import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import '../services/notification_service.dart';

/// LAB TEST DETAIL (Lab Staff)
///
/// Confirmed  → "Start Test" button (status → In Progress)
/// In Progress → "Upload Report & Complete" (report base64, status →
///               Completed) YA "Cancel Test" (reason, refund)
/// Completed  → read-only (report dikhta hai), koi action nahi
///
/// CANCEL (Confirmed ya In Progress dono se): status → Cancelled +
/// jo Paid payment thi uska status → Refunded (refundPaid:false) →
/// turant Receptionist ki Pending Refunds list mein chala jata hai.
/// (Storage avoid — report base64 me, jaise payment screenshot.)
class LabTestDetailScreen extends StatefulWidget {
  final String testId;

  const LabTestDetailScreen({super.key, required this.testId});

  @override
  State<LabTestDetailScreen> createState() => _LabTestDetailScreenState();
}

class _LabTestDetailScreenState extends State<LabTestDetailScreen> {
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _primaryDark = Color(0xFF0D6B5A);

  final _picker = ImagePicker();
  final _reasonController = TextEditingController();

  bool _isLoading = true;
  bool _isProcessing = false;
  Map<String, dynamic>? _test;
  String _patientName = '';
  String _doctorName = '';
  String? _reportBase64;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('lab_tests')
          .doc(widget.testId)
          .get();
      if (!doc.exists) {
        setState(() => _isLoading = false);
        return;
      }
      _test = doc.data();

      final p = await FirebaseFirestore.instance
          .collection('users')
          .doc(_test!['patientId'])
          .get();
      _patientName = p.data()?['name'] ?? 'Patient';

      final d = await FirebaseFirestore.instance
          .collection('users')
          .doc(_test!['doctorId'])
          .get();
      _doctorName = d.data()?['name'] ?? '';

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Error loading test: $e');
    }
  }

  String get _status => _test?['status'] ?? '';

  // ── Start Test: Confirmed → In Progress ──
  Future<void> _startTest() async {
    setState(() => _isProcessing = true);
    try {
      await FirebaseFirestore.instance
          .collection('lab_tests')
          .doc(widget.testId)
          .update({
        'status': 'In Progress',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _showSuccess('Test started');
      _load();
    } catch (e) {
      _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── Report upload (base64, gallery image) ──
  Future<void> _pickReport() async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 65,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.lengthInBytes > 700 * 1024) {
        _showError('Image too large. Please choose a smaller file.');
        return;
      }
      setState(() => _reportBase64 = base64Encode(bytes));
    } catch (e) {
      _showError('Could not load report: $e');
    }
  }

  // ── Complete: In Progress → Completed, report saved ──
  Future<void> _completeTest() async {
    if (_reportBase64 == null) {
      _showError('Please upload the report first');
      return;
    }
    setState(() => _isProcessing = true);
    try {
      await FirebaseFirestore.instance
          .collection('lab_tests')
          .doc(widget.testId)
          .update({
        'status': 'Completed',
        'reportBase64': _reportBase64,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // ── NOTIFICATION: Lab Report Ready ──
      // IN_PERSON: Doctor + Patient | WALK_IN: sirf Doctor (patient
      // ke paas app nahi)
      final apptDoc = await FirebaseFirestore.instance
          .collection('appointments')
          .doc(_test!['appointmentId'])
          .get();
      final apptType = apptDoc.data()?['appointmentType'] ?? 'IN_PERSON';

      await NotificationService.send(
        userId: _test!['doctorId'] ?? '',
        type: 'Lab',
        referenceId: widget.testId,
        message: 'Lab report ready for ${_patientName}: ${_test!['testType']}.',
      );

      if (apptType != 'WALK_IN') {
        await NotificationService.send(
          userId: _test!['patientId'] ?? '',
          type: 'Lab',
          referenceId: widget.testId,
          message: 'Your lab report is ready. Test: ${_test!['testType']}.',
        );
      }
      if (!mounted) return;
      _showSuccess('Report uploaded — test completed');
      Navigator.pop(context, true);
    } catch (e) {
      _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── Cancel (Confirmed ya In Progress se) — refund ke saath ──
  Future<void> _cancelTest() async {
    if (_reasonController.text.trim().isEmpty) {
      _showError('Please enter a reason for cancellation');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel this test?'),
        content: const Text(
            'The patient already paid for this test. Cancelling will '
            'add a FULL refund to the receptionist\'s pending refunds list.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Cancel & Refund',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isProcessing = true);
    try {
      // Jo Paid payment thi is test ke liye, dhoondo (query — transaction
      // ke bahar, kyunki Firestore transaction ke andar query nahi hoti)
      final paySnap = await FirebaseFirestore.instance
          .collection('payments')
          .where('referenceId', isEqualTo: widget.testId)
          .where('type', isEqualTo: 'Lab')
          .where('status', isEqualTo: 'Paid')
          .limit(1)
          .get();
      final payRef =
          paySnap.docs.isNotEmpty ? paySnap.docs.first.reference : null;
      final payAmount = paySnap.docs.isNotEmpty
          ? (paySnap.docs.first.data()['amount'] ?? 0)
          : 0;

      final testRef =
          FirebaseFirestore.instance.collection('lab_tests').doc(widget.testId);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final testSnap = await transaction.get(testRef);
        if (!testSnap.exists) throw Exception('Test not found');
        final currentStatus = testSnap.data()!['status'];
        if (currentStatus != 'Confirmed' && currentStatus != 'In Progress') {
          throw Exception('This test can no longer be cancelled.');
        }

        transaction.update(testRef, {
          'status': 'Cancelled',
          'cancelReason': _reasonController.text.trim(),
          'cancelledBy': 'Lab',
          'updatedAt': FieldValue.serverTimestamp(),
        });

        if (payRef != null) {
          transaction.update(payRef, {
            'status': 'Refunded',
            'refundAmount': payAmount,
            'refundPaid': false,
          });
        }
      });
      final apptDoc = await FirebaseFirestore.instance
          .collection('appointments')
          .doc(_test!['appointmentId'])
          .get();
      final apptType = apptDoc.data()?['appointmentType'] ?? 'IN_PERSON';

      await NotificationService.send(
        userId: _test!['doctorId'] ?? '',
        type: 'Lab',
        referenceId: widget.testId,
        message: 'Lab test cancelled for $_patientName: ${_test!['testType']}.',
      );

      if (apptType != 'WALK_IN') {
        await NotificationService.send(
          userId: _test!['patientId'] ?? '',
          type: 'Lab',
          referenceId: widget.testId,
          message:
              'Your lab test (${_test!['testType']}) was cancelled by lab. Reason: ${_reasonController.text.trim()}',
        );
      }
      if (!mounted) return;
      _showSuccess('Test cancelled — refund added to pending list');
      Navigator.pop(context, true);
    } catch (e) {
      _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
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

  void _showCancelSheet() {
    _reasonController.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Cancel Test',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('Please explain why this test cannot be completed.',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 14),
                TextField(
                  controller: _reasonController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'e.g. Sample damaged, equipment malfunction...',
                    filled: true,
                    fillColor: const Color(0xFFF4F7F6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _cancelTest();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Cancel Test',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: _primary))
            : _test == null
                ? const Center(child: Text('Test not found'))
                : Column(
                    children: [
                      _buildHeader(),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildInfoCard(),
                              const SizedBox(height: 20),
                              _buildActionSection(),
                            ],
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
      padding: const EdgeInsets.fromLTRB(12, 16, 20, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_primary, _primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          const Text('Test Detail',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_patientName,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A2F3A))),
          const SizedBox(height: 4),
          Text('Referred by Dr. $_doctorName',
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const Divider(height: 24),
          _infoRow('Test Type', _test!['testType'] ?? ''),
          const SizedBox(height: 10),
          _infoRow('Status', _status),
          if (_status == 'Cancelled' && _test!['cancelReason'] != null) ...[
            const SizedBox(height: 10),
            _infoRow('Cancel Reason', _test!['cancelReason']),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(label,
              style: const TextStyle(fontSize: 13, color: Colors.grey)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A2F3A))),
        ),
      ],
    );
  }

  Widget _buildActionSection() {
    if (_status == 'Completed') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: _primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(30),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, color: _primary, size: 18),
            SizedBox(width: 8),
            Text('Test completed — report submitted',
                style: TextStyle(color: _primary, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }

    if (_status == 'Cancelled') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFD9534F).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(30),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cancel_outlined, color: Color(0xFFD9534F), size: 18),
            SizedBox(width: 8),
            Text('Test cancelled',
                style: TextStyle(
                    color: Color(0xFFD9534F), fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }

    if (_status == 'Confirmed') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton.icon(
            onPressed: _isProcessing ? null : _startTest,
            icon: _isProcessing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.play_arrow, color: Colors.white),
            label:
                const Text('Start Test', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30)),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _isProcessing ? null : _showCancelSheet,
            icon: const Icon(Icons.cancel_outlined,
                color: Color(0xFFD9534F), size: 18),
            label: const Text('Cancel Test',
                style: TextStyle(color: Color(0xFFD9534F))),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFD9534F)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30)),
            ),
          ),
        ],
      );
    }

    // In Progress — report upload + complete, or cancel
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Upload Report',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A2F3A))),
        const SizedBox(height: 8),
        _buildReportPicker(),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _isProcessing ? null : _completeTest,
          icon: _isProcessing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.check_circle_outline, color: Colors.white),
          label: const Text('Complete Test',
              style: TextStyle(color: Colors.white)),
          style: ElevatedButton.styleFrom(
            backgroundColor: _primary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _isProcessing ? null : _showCancelSheet,
          icon: const Icon(Icons.cancel_outlined,
              color: Color(0xFFD9534F), size: 18),
          label: const Text('Cancel Test',
              style: TextStyle(color: Color(0xFFD9534F))),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Color(0xFFD9534F)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          ),
        ),
      ],
    );
  }

  Widget _buildReportPicker() {
    if (_reportBase64 != null) {
      return Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(base64Decode(_reportBase64!),
                height: 180, width: double.infinity, fit: BoxFit.cover),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _pickReport,
            icon: const Icon(Icons.refresh, size: 16, color: _primary),
            label:
                const Text('Change report', style: TextStyle(color: _primary)),
          ),
        ],
      );
    }
    return GestureDetector(
      onTap: _pickReport,
      child: Container(
        width: double.infinity,
        height: 120,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: _primary.withValues(alpha: 0.4), width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.upload_file,
                size: 30, color: _primary.withValues(alpha: 0.6)),
            const SizedBox(height: 8),
            const Text('Tap to upload report',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}
