import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../widgets/app_ui.dart';

/// PATIENT — LAB REPORTS
///
/// SCHEMA COMPLIANCE:
/// - lab_tests where patientId == uid
/// - Report Storage avoid karne ke liye base64 me Firestore me
///   (reportBase64, na ke reportUrl) — jaise payment screenshot.
/// - Report "View" sirf tab jab status == Completed && reportBase64 != null
///
///  UPDATED — Doctor-side jaisa "View" button pattern:
/// Status badge ki jagah "View" pill button dikhta hai jab report
/// ready ho (Completed + reportBase64 mojood). Baaki statuses ke
/// liye normal status badge.
///
///  NAYA — Filter tabs (doctor-side jaisa): All | Pending |
/// In Progress | Completed | Cancelled. Client-side filtering hai
/// (data ek hi baar load hota hai, tab badalne par sirf list filter
/// hoti hai — extra Firestore query nahi lagti).
///
///  NAYA — Delete / Delete All (sirf Completed aur Cancelled par):
/// lab_tests doctor, lab staff, admin aur payments sab ke liye shared
/// record hai, is liye patient ke "Delete" par document asal mein
/// delete nahi hota — us par 'patientHidden: true' lag jata hai aur
/// patient ki list se hat jata hai. Baaqi roles ka data safe rehta hai.
class LabReportsScreen extends StatefulWidget {
  const LabReportsScreen({super.key});

  @override
  State<LabReportsScreen> createState() => _LabReportsScreenState();
}

class _LabReportsScreenState extends State<LabReportsScreen> {
  static const Color _danger = Color(0xFF9A2E16);

  bool _isLoading = true;
  List<Map<String, dynamic>> _tests = [];

  // null = "All"
  String? _selectedFilter;

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

        // Patient ne jo tests "delete" (hide) kar diye, wo dobara
        // list mein nahi aate.
        if (data['patientHidden'] == true) continue;

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
          'reportType': data['reportType'],
          'charge': data['charge'] ?? 0,
          'paymentStatus': data['paymentStatus'],
          'doctorName': doctorDoc.data()?['name'] ?? 'Doctor',
          'dateLabel': dateLabel,
          'createdAt': createdAt,
          'cancelReason': data['cancelReason'],
          'cancelledBy': data['cancelledBy'],
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

  List<Map<String, dynamic>> get _filteredTests {
    if (_selectedFilter == null) return _tests;
    return _tests.where((t) => t['status'] == _selectedFilter).toList();
  }

  // Sirf Completed aur Cancelled tests delete ho sakte hain.
  static bool _isDeletable(Map<String, dynamic> t) =>
      t['status'] == 'Completed' || t['status'] == 'Cancelled';

  void _changeFilter(String? filter) {
    if (_selectedFilter == filter) return;
    setState(() => _selectedFilter = filter);
  }

  // ── Delete (single) — patient ki list se hata deta hai ──
  Future<void> _deleteTest(String testId) async {
    try {
      await FirebaseFirestore.instance
          .collection('lab_tests')
          .doc(testId)
          .update({'patientHidden': true});
      if (!mounted) return;
      setState(() => _tests.removeWhere((t) => t['testId'] == testId));
      _showSuccess('Lab test removed');
    } catch (e) {
      _showError('Error deleting: $e');
    }
  }

  // ── Delete All — jo Completed/Cancelled tests abhi (current filter
  //    ke andar) list mein dikh rahe hain, sab ek batch mein ──
  Future<void> _deleteAllDeletable() async {
    final deletable = _filteredTests.where(_isDeletable).toList();
    if (deletable.isEmpty) return;
    try {
      final batch = FirebaseFirestore.instance.batch();
      final ids = <String>{};
      for (final t in deletable) {
        final id = t['testId'] as String;
        ids.add(id);
        batch.update(FirebaseFirestore.instance.collection('lab_tests').doc(id),
            {'patientHidden': true});
      }
      await batch.commit();
      if (!mounted) return;
      setState(() => _tests.removeWhere((t) => ids.contains(t['testId'])));
      _showSuccess('${ids.length} lab test(s) removed');
    } catch (e) {
      _showError('Error deleting all: $e');
    }
  }

  void _viewReport(String base64Str) {
    final bytes = base64Decode(base64Str);

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
                child: Image.memory(bytes),
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
      backgroundColor: _danger,
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
    final deletableCount = _filteredTests.where(_isDeletable).length;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _buildHeader(),
          // ── Delete All bar — sirf jab list mein Completed/Cancelled ho ──
          if (!_isLoading && deletableCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$deletableCount completed/cancelled test${deletableCount == 1 ? '' : 's'}',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.muted),
                    ),
                  ),
                  GestureDetector(
                    onTap: _deleteAllDeletable,
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
            ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.teal))
                : _filteredTests.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadTests,
                        color: AppColors.teal,
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                          itemCount: _filteredTests.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (ctx, i) => _testCard(_filteredTests[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return AppHeader(
      title: 'Lab Reports',
      subtitle: _isLoading ? null : '${_filteredTests.length} tests',
      bottom: _buildFilterTabs(),
    );
  }

  // Filters: All | Pending | In Progress | Completed | Cancelled
  Widget _buildFilterTabs() {
    final filters = <String, String?>{
      'All': null,
      'Pending': 'Pending',
      'In Progress': 'In Progress',
      'Completed': 'Completed',
      'Cancelled': 'Cancelled',
    };

    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: filters.entries.map((entry) {
          final isSelected = _selectedFilter == entry.value;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => _changeFilter(entry.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.mint
                      : Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(999),
                  border: isSelected
                      ? null
                      : Border.all(color: Colors.white.withOpacity(0.16)),
                ),
                alignment: Alignment.center,
                child: Text(
                  entry.key,
                  style: TextStyle(
                    color: isSelected ? AppColors.header : Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: AppEmptyState(
        icon: Icons.science_outlined,
        title: _selectedFilter == null
            ? 'No lab tests yet'
            : 'No ${_selectedFilter!.toLowerCase()} tests',
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
    final canDelete = _isDeletable(test);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppIconTile(
                icon: Icons.science_outlined,
                color: AppColors.blue,
                background: AppColors.blueSoft,
                size: 44,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(test['testType'],
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.text)),
                    const SizedBox(height: 3),
                    Text('Requested by Dr. ${test['doctorName']}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.muted)),
                    const SizedBox(height: 2),
                    Text(test['dateLabel'],
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.faint)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Report ready → "View" pill, warna status chip
              if (canView)
                GestureDetector(
                  onTap: () => _viewReport(reportBase64),
                  child: Container(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppColors.teal,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.remove_red_eye_outlined,
                            size: 15, color: Colors.white),
                        SizedBox(width: 5),
                        Text('View',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                )
              else
                AppStatusChip(
                  label: status,
                  colors:
                      AppChipColors(statusColors['text']!, statusColors['bg']!),
                ),
            ],
          ),
          if (status != 'Cancelled') ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      isPaid
                          ? 'Rs. ${test['charge']} — Paid'
                          : 'Rs. ${test['charge']} — Pay at reception',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: isPaid
                              ? const Color(0xFF0B5E57)
                              : const Color(0xFF8A6D00)),
                    ),
                  ),
                  if (!canView)
                    const Text('Report not ready',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.faint)),
                ],
              ),
            ),
          ],
          if (status == 'Cancelled' && test['cancelReason'] != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.dangerSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cancelled by ${test['cancelledBy'] ?? 'Lab'}',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF9A2E16))),
                  const SizedBox(height: 2),
                  Text('Reason: ${test['cancelReason']}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.muted)),
                ],
              ),
            ),
          ],
          // Delete — sirf Completed aur Cancelled cards par
          if (canDelete) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () => _deleteTest(test['testId']),
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
                      Icon(Icons.delete_outline_rounded,
                          size: 15, color: AppColors.danger),
                      SizedBox(width: 6),
                      Text('Delete',
                          style: TextStyle(
                              color: AppColors.danger,
                              fontSize: 12,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Map<String, Color> _statusColor(String status) {
    switch (status) {
      case 'Completed':
        return {'bg': const Color(0xFFDDF3EE), 'text': const Color(0xFF0B5E57)};
      case 'In Progress':
        return {'bg': AppColors.blueSoft, 'text': AppColors.blue};
      case 'Cancelled':
        return {'bg': const Color(0xFFFBE6E0), 'text': const Color(0xFF9A2E16)};
      default: // Pending
        return {'bg': const Color(0xFFF6F2E2), 'text': const Color(0xFF8A6D00)};
    }
  }
}
