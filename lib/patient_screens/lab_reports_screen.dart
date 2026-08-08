import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

/// PATIENT — LAB REPORTS
///
/// SCHEMA COMPLIANCE:
/// - lab_tests where patientId == uid
/// - Report Storage avoid karne ke liye base64 me Firestore me
///   (reportBase64, na ke reportUrl) — jaise payment screenshot.
/// - Report "View" sirf tab jab status == Completed && reportBase64 != null
class LabReportsScreen extends StatefulWidget {
  const LabReportsScreen({super.key});

  @override
  State<LabReportsScreen> createState() => _LabReportsScreenState();
}

class _LabReportsScreenState extends State<LabReportsScreen> {
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _primaryDark = Color(0xFF0D6B5A);

  bool _isLoading = true;
  List<Map<String, dynamic>> _tests = [];

  @override
  void initState() {
    super.initState();
    _loadTests();
  }

  Future<void> _loadTests() async {
    setState(() => _isLoading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        setState(() => _isLoading = false);
        return;
      }

      final testsSnap = await FirebaseFirestore.instance
          .collection('lab_tests')
          .where('patientId', isEqualTo: uid)
          .get();

      final List<Map<String, dynamic>> result = [];

      for (final doc in testsSnap.docs) {
        final data = doc.data();

        final doctorDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(data['doctorId'])
            .get();

        String dateLabel = '';
        final createdAt = data['createdAt'];
        if (createdAt is Timestamp) {
          dateLabel = DateFormat('d MMM yyyy').format(createdAt.toDate());
        }

        result.add({
          'testId': doc.id,
          'testType': data['testType'] ?? '',
          'status': data['status'] ?? 'Pending',
          'reportBase64': data['reportBase64'],
          'charge': data['charge'] ?? 0,
          'paymentStatus': data['paymentStatus'],
          'doctorName': doctorDoc.data()?['name'] ?? 'Doctor',
          'dateLabel': dateLabel,
          'createdAt': createdAt,
        });
      }

      // Newest first
      result.sort((a, b) {
        final aTs = a['createdAt'];
        final bTs = b['createdAt'];
        if (aTs is! Timestamp || bTs is! Timestamp) return 0;
        return bTs.compareTo(aTs);
      });

      setState(() {
        _tests = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Error loading lab tests: $e');
    }
  }

  // Full-screen base64 report viewer (zoom/pan) — jaise payment screenshot
  void _viewReport(String base64Str) {
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

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: const Color(0xFFDB4437),
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
                  : _tests.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: _loadTests,
                          color: _primary,
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                            itemCount: _tests.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 14),
                            itemBuilder: (ctx, i) => _testCard(_tests[i]),
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
          const Text('Lab Reports',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.science_outlined,
              size: 64, color: _primary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          const Text('No lab tests yet',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280))),
        ],
      ),
    );
  }

  Widget _testCard(Map<String, dynamic> test) {
    final status = test['status'] as String;
    final statusColors = _statusColor(status);
    final String? reportBase64 = test['reportBase64'];
    final canView = status == 'Completed' &&
        reportBase64 != null &&
        reportBase64.isNotEmpty;
    final isPaid = test['paymentStatus'] == 'Paid';

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.science_outlined,
                    color: _primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(test['testType'],
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A2F3A))),
                    const SizedBox(height: 4),
                    Text('Requested by ${test['doctorName']}',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.black54)),
                    const SizedBox(height: 2),
                    Text(test['dateLabel'],
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColors['bg'],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(status,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: statusColors['text'])),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),
          if (canView) ...[
            GestureDetector(
              onTap: () => _viewReport(reportBase64),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      base64Decode(reportBase64),
                      height: 140,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        height: 140,
                        color: const Color(0xFFF0F0F0),
                        alignment: Alignment.center,
                        child: const Text('Could not load report',
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
                      child: const Icon(Icons.zoom_in,
                          color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isPaid
                    ? 'Rs. ${test['charge']} — Paid'
                    : 'Rs. ${test['charge']} — Pay at reception',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isPaid ? _primary : const Color(0xFFB8860B)),
              ),
              if (!canView)
                const Text('Report not ready',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }

  Map<String, Color> _statusColor(String status) {
    switch (status) {
      case 'Completed':
        return {'bg': const Color(0xFFDCEFE9), 'text': const Color(0xFF1F8A70)};
      case 'In Progress':
        return {'bg': const Color(0xFFD9ECF8), 'text': const Color(0xFF1565C0)};
      case 'Cancelled':
        return {'bg': const Color(0xFFFDE6E0), 'text': const Color(0xFFD9534F)};
      default: // Pending
        return {'bg': const Color(0xFFFCEFD8), 'text': const Color(0xFFB8860B)};
    }
  }
}
