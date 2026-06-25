import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'doctor_performance_detail_sheet.dart';

// Content-only widget for the Doctor Performance tab — no Scaffold/
// AppBar of its own, since it lives inside ReportsScreen's TabBarView.
class DoctorPerformanceTab extends StatefulWidget {
  const DoctorPerformanceTab({super.key});

  @override
  State<DoctorPerformanceTab> createState() => _DoctorPerformanceTabState();
}

class _DoctorPerformanceTabState extends State<DoctorPerformanceTab> {
  static const Color _primary = Color(0xFF0D6B6B);
  static const Color _bg = Color(0xFFF5F7FA);

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
          // Month navigation
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: _canGoPrevious() ? () => _navigate(-1) : null,
                  icon: Icon(Icons.chevron_left_rounded,
                      color: _canGoPrevious()
                          ? _primary
                          : const Color(0xFFD1D5DB)),
                ),
                Text(
                  DateFormat('MMMM yyyy').format(_selectedMonth),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                IconButton(
                  onPressed: _canGoNext() ? () => _navigate(1) : null,
                  icon: Icon(Icons.chevron_right_rounded,
                      color: _canGoNext() ? _primary : const Color(0xFFD1D5DB)),
                ),
              ],
            ),
          ),

          // Table header
          if (!_isLoading && _doctorStats.isNotEmpty)
            Container(
              color: const Color(0xFFEFF6F6),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: const Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text('Doctor',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _primary)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text('Appts',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _primary)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text('Rating',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _primary)),
                  ),
                ],
              ),
            ),

          // List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: _primary))
                : _doctorStats.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.medical_services_outlined,
                                size: 64, color: _primary.withOpacity(0.3)),
                            const SizedBox(height: 16),
                            const Text(
                              'No appointment data this month',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: _doctorStats.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: Color(0xFFE5E7EB)),
                        itemBuilder: (context, index) {
                          final doc = _doctorStats[index];
                          return _DoctorRow(
                            doctor: doc,
                            onTap: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (_) => DraggableScrollableSheet(
                                  initialChildSize: 0.7,
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

  static const Color _primary = Color(0xFF0D6B6B);

  @override
  Widget build(BuildContext context) {
    final avgRating = (doctor['avgRating'] ?? 0.0) as double;
    final reviewCount = doctor['reviewCount'] ?? 0;

    return InkWell(
      onTap: onTap,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                doctor['doctorName'] ?? 'Unknown',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A2E),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                '${doctor['appointmentCount']}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _primary,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: reviewCount == 0
                  ? const Text(
                      'N/A',
                      textAlign: TextAlign.end,
                      style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 14, color: Color(0xFFF4B400)),
                        const SizedBox(width: 3),
                        Text(
                          avgRating.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1A2E),
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: Color(0xFF9CA3AF)),
          ],
        ),
      ),
    );
  }
}
