// lib/screens/doctor_performance_tab.dart (ya jo bhi iska actual filename hai)
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'doctor_performance_detail_sheet.dart';
import '../widgets/app_ui.dart';
import 'reports_screen.dart';

// Content-only widget for the Doctor Performance tab — no Scaffold/
// AppBar of its own, since it lives inside ReportsScreen's TabBarView.
class DoctorPerformanceTab extends StatefulWidget {
  const DoctorPerformanceTab({super.key});

  @override
  State<DoctorPerformanceTab> createState() => _DoctorPerformanceTabState();
}

class _DoctorPerformanceTabState extends State<DoctorPerformanceTab> {
  // Theme colors — matched to Admin Dashboard's green palette
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _bg = Color(0xFFF4F7F6);
  static const Color _headerTint = Color(0xFFDCEFE9);

  DateTime _selectedMonth = DateTime.now();
  bool _isLoading = true;
  List<Map<String, dynamic>> _doctorStats = [];

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  ({DateTime start, DateTime end}) _getMonthRange() {
    final start = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final end = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1);
    return (start: start, end: end);
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    try {
      final range = _getMonthRange();

      // ---- Fetch appointments for the month ----
      final apptSnap = await FirebaseFirestore.instance
          .collection('appointments')
          .where('createdAt', isGreaterThanOrEqualTo: range.start)
          .where('createdAt', isLessThan: range.end)
          .get();

      // Group appointment counts by doctorId
      final Map<String, int> apptCountByDoctor = {};
      for (final doc in apptSnap.docs) {
        final doctorId = doc.data()['doctorId'];
        if (doctorId != null) {
          apptCountByDoctor[doctorId] = (apptCountByDoctor[doctorId] ?? 0) + 1;
        }
      }

      // ---- Fetch feedback for the month, group ratings by doctorId ----
      final feedbackSnap = await FirebaseFirestore.instance
          .collection('feedback')
          .where('createdAt', isGreaterThanOrEqualTo: range.start)
          .where('createdAt', isLessThan: range.end)
          .get();

      final Map<String, List<int>> ratingsByDoctor = {};
      for (final doc in feedbackSnap.docs) {
        final data = doc.data();
        final doctorId = data['doctorId'];
        final rating = (data['rating'] ?? 0) as num;
        if (doctorId != null) {
          ratingsByDoctor.putIfAbsent(doctorId, () => []).add(rating.toInt());
        }
      }

      // ---- Build the list: only doctors who had at least one
      // appointment this month show up here ----
      final List<Map<String, dynamic>> results = [];

      for (final entry in apptCountByDoctor.entries) {
        final doctorId = entry.key;
        final apptCount = entry.value;

        final doctorDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(doctorId)
            .get();
        final doctorName = doctorDoc.exists
            ? (doctorDoc.data()?['name'] ?? 'Unknown')
            : 'Unknown';

        final ratings = ratingsByDoctor[doctorId] ?? [];
        final avgRating = ratings.isEmpty
            ? 0.0
            : ratings.reduce((a, b) => a + b) / ratings.length;

        results.add({
          'doctorId': doctorId,
          'doctorName': doctorName,
          'appointmentCount': apptCount,
          'avgRating': avgRating,
          'reviewCount': ratings.length,
        });
      }

      // Sort by appointment count, descending (busiest doctors first)
      results.sort((a, b) => (b['appointmentCount'] as int)
          .compareTo(a['appointmentCount'] as int));

      setState(() {
        _doctorStats = results;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Error loading doctor performance: $e');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: const Color(0xFFDB4437),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _navigate(int direction) {
    final newMonth =
        DateTime(_selectedMonth.year, _selectedMonth.month + direction, 1);
    final now = DateTime.now();
    if (newMonth.isAfter(DateTime(now.year, now.month, 1))) return;
    final monthsDiff =
        (now.year - newMonth.year) * 12 + (now.month - newMonth.month);
    if (monthsDiff > 12) return;

    setState(() => _selectedMonth = newMonth);
    _loadStats();
  }

  bool _canGoNext() {
    final next = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1);
    final now = DateTime.now();
    return !next.isAfter(DateTime(now.year, now.month, 1));
  }

  bool _canGoPrevious() {
    final prev = DateTime(_selectedMonth.year, _selectedMonth.month - 1, 1);
    final now = DateTime.now();
    final monthsDiff = (now.year - prev.year) * 12 + (now.month - prev.month);
    return monthsDiff <= 12;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _bg,
      child: Column(
        children: [
          // Month navigation (dark strip)
          ReportsHeaderStrip(
            child: Row(
              children: [
                const Text(
                  'Month by month',
                  style: TextStyle(
                    color: AppColors.headerMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                ReportsDateNav(
                  label: DateFormat('MMMM yyyy').format(_selectedMonth),
                  onPrev: _canGoPrevious() ? () => _navigate(-1) : null,
                  onNext: _canGoNext() ? () => _navigate(1) : null,
                ),
              ],
            ),
          ),

          // List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.teal))
                : _doctorStats.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(20),
                        children: const [
                          AppEmptyState(
                            icon: Icons.medical_services_outlined,
                            title: 'No appointment data this month',
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                        itemCount: _doctorStats.length + 1,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'DOCTOR',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.8,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    'APPOINTMENTS · RATING',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.8,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          final doc = _doctorStats[index - 1];
                          return _DoctorRow(
                            doctor: doc,
                            onTap: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (_) => DraggableScrollableSheet(
                                  initialChildSize: 0.55,
                                  minChildSize: 0.4,
                                  maxChildSize: 0.9,
                                  expand: false,
                                  builder: (context, scrollController) =>
                                      DoctorPerformanceDetailSheet(
                                    doctorId: doc['doctorId'],
                                    doctorName: doc['doctorName'],
                                    monthStart: _getMonthRange().start,
                                    monthEnd: _getMonthRange().end,
                                    monthLabel: DateFormat('MMMM yyyy')
                                        .format(_selectedMonth),
                                    scrollController: scrollController,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _DoctorRow extends StatelessWidget {
  final Map<String, dynamic> doctor;
  final VoidCallback onTap;

  const _DoctorRow({required this.doctor, required this.onTap});

  String _initials(String name) {
    final parts = name
        .replaceFirst('Dr. ', '')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toList();
    return parts.take(2).map((w) => w[0].toUpperCase()).join();
  }

  // NAYA (sirf dikhane ke liye): doctor ka department naam
  // (doctor_profiles → departments), wahi tareeqa jo detail sheet
  // pehle se use karti hai.
  Future<String> _loadDepartment(String? doctorId) async {
    if (doctorId == null) return '';
    try {
      final profile = await FirebaseFirestore.instance
          .collection('doctor_profiles')
          .doc(doctorId)
          .get();
      final deptId = profile.data()?['departmentId'];
      if (deptId == null) return '';
      final dept = await FirebaseFirestore.instance
          .collection('departments')
          .doc(deptId)
          .get();
      return dept.data()?['name'] ?? '';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final avgRating = (doctor['avgRating'] ?? 0.0) as double;
    final reviewCount = doctor['reviewCount'] ?? 0;
    final String name = doctor['doctorName'] ?? 'Unknown';
    final count = doctor['appointmentCount'];

    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFFEEE8FB),
            child: Text(
              _initials(name),
              style: const TextStyle(
                color: Color(0xFF5B3FA8),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                FutureBuilder<String>(
                  future: _loadDepartment(doctor['doctorId']),
                  builder: (context, snap) => Text(
                    snap.data ?? '',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$count',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              reviewCount == 0
                  ? const Text(
                      'No rating',
                      style: TextStyle(fontSize: 11, color: AppColors.faint),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 13, color: Color(0xFFE0A800)),
                        const SizedBox(width: 2),
                        Text(
                          avgRating.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF8A6D00),
                          ),
                        ),
                      ],
                    ),
            ],
          ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded,
              size: 20, color: AppColors.faint),
        ],
      ),
    );
  }
}
