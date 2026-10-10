import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import '../services/notification_service.dart';
import '../widgets/app_ui.dart';

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
  final _picker = ImagePicker();
  final _reasonController = TextEditingController();

  bool _isLoading = true;
  bool _isProcessing = false;
  Map<String, dynamic>? _test;
  String _patientName = '';
  String _doctorName = '';
  String? _reportBase64;
  String? _reportType;
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
    await _pickImageReport();
  }

// ── Gallery image pick (purana image_picker wala logic) ──
  Future<void> _pickImageReport() async {
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
      setState(() {
        _reportBase64 = base64Encode(bytes);
        _reportType = 'image';
      });
    } catch (e) {
      _showError('Could not load image: $e');
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
        'reportType': _reportType,
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
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Cancel this test?'),
        content: const Text(
            'The patient already paid for this test. Cancelling will '
            'add a FULL refund to the receptionist\'s pending refunds list.'),
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
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text('Cancel Test',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text)),
                const SizedBox(height: 4),
                const Text('Please explain why this test cannot be completed.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
                const SizedBox(height: 14),
                TextField(
                  controller: _reasonController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'e.g. Sample damaged, equipment malfunction...',
                    hintStyle: const TextStyle(color: AppColors.faint),
                    filled: true,
                    fillColor: AppColors.bg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: AppColors.teal, width: 1.5),
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
                      backgroundColor: AppColors.danger,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Cancel Test',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800)),
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
      backgroundColor: AppColors.bg,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.teal))
          : _test == null
              ? const Center(child: Text('Test not found'))
              : Column(
                  children: [
                    _buildHeader(),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
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
    );
  }

  Widget _buildHeader() {
    return AppHeader(
      title: 'Test Detail',
      subtitle: '${_test!['testType'] ?? ''}',
    );
  }

  AppChipColors _statusColors() {
    switch (_status) {
      case 'Completed':
        return const AppChipColors(Color(0xFF0B5E57), Color(0xFFDDF3EE));
      case 'In Progress':
        return const AppChipColors(AppColors.blue, AppColors.blueSoft);
      case 'Cancelled':
        return const AppChipColors(Color(0xFF9A2E16), Color(0xFFFBE6E0));
      case 'Confirmed':
        return const AppChipColors(Color(0xFF5B3FA8), Color(0xFFEEE8FB));
      default:
        return const AppChipColors(Color(0xFF8A6D00), Color(0xFFF6F2E2));
    }
  }

  Widget _buildInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.tealSoft,
                child: Text(
                  _patientName.isNotEmpty ? _patientName[0].toUpperCase() : '?',
                  style: const TextStyle(
                      color: AppColors.teal,
                      fontSize: 18,
                      fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_patientName,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.text)),
                    const SizedBox(height: 2),
                    Text('Referred by Dr. $_doctorName',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
              AppStatusChip(label: _status, colors: _statusColors()),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                _infoRow('Test Type', _test!['testType'] ?? ''),
                const SizedBox(height: 8),
                _infoRow('Status', _status),
                if (_status == 'Cancelled' &&
                    _test!['cancelReason'] != null) ...[
                  const SizedBox(height: 8),
                  _infoRow('Cancel Reason', _test!['cancelReason']),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.faint)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text)),
        ),
      ],
    );
  }

  ButtonStyle _darkBtn() => ElevatedButton.styleFrom(
        backgroundColor: AppColors.header,
        disabledBackgroundColor: AppColors.header.withOpacity(0.5),
        elevation: 0,
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      );

  ButtonStyle _cancelBtn() => OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        side: const BorderSide(color: Color(0xFFF0C9BE)),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      );

  Widget _banner(IconData icon, String text, Color fg, Color bg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: fg, fontSize: 14, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _buildActionSection() {
    if (_status == 'Completed') {
      return _banner(
          Icons.check_circle_rounded,
          'Test completed — report submitted',
          const Color(0xFF0B5E57),
          const Color(0xFFDDF3EE));
    }

    if (_status == 'Cancelled') {
      return _banner(Icons.cancel_outlined, 'Test cancelled',
          const Color(0xFF9A2E16), const Color(0xFFFBE6E0));
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
                : const Icon(Icons.play_arrow_rounded, color: AppColors.mint),
            label: const Text('Start Test',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800)),
            style: _darkBtn(),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _isProcessing ? null : _showCancelSheet,
            icon: const Icon(Icons.cancel_outlined,
                color: Color(0xFF9A2E16), size: 18),
            label: const Text('Cancel Test',
                style: TextStyle(
                    color: Color(0xFF9A2E16),
                    fontSize: 14,
                    fontWeight: FontWeight.w800)),
            style: _cancelBtn(),
          ),
        ],
      );
    }

    // In Progress — report upload + complete, or cancel
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('UPLOAD REPORT',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: AppColors.muted)),
        const SizedBox(height: 10),
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
              : const Icon(Icons.check_circle_outline, color: AppColors.mint),
          label: const Text('Complete Test',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800)),
          style: _darkBtn(),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _isProcessing ? null : _showCancelSheet,
          icon: const Icon(Icons.cancel_outlined,
              color: Color(0xFF9A2E16), size: 18),
          label: const Text('Cancel Test',
              style: TextStyle(
                  color: Color(0xFF9A2E16),
                  fontSize: 14,
                  fontWeight: FontWeight.w800)),
          style: _cancelBtn(),
        ),
      ],
    );
  }

  Widget _buildReportPicker() {
    if (_reportBase64 != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(base64Decode(_reportBase64!),
                  height: 180, width: double.infinity, fit: BoxFit.cover),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _pickReport,
              child: Container(
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.tealSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.refresh_rounded,
                        size: 16, color: AppColors.teal),
                    SizedBox(width: 6),
                    Text('Change report',
                        style: TextStyle(
                            color: AppColors.teal,
                            fontSize: 13,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: _pickReport,
      child: Container(
        width: double.infinity,
        height: 130,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFB9CFCC), width: 1.5),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIconTile(
              icon: Icons.upload_file,
              color: AppColors.teal,
              background: AppColors.tealSoft,
            ),
            SizedBox(height: 8),
            Text('Tap to upload report',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text)),
          ],
        ),
      ),
    );
  }
}
