import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Bottom sheet version of the doctor detail view. Used inside
// showModalBottomSheet + DraggableScrollableSheet from
// doctor_performance_screen.dart — not a full Scaffold screen.
class DoctorPerformanceDetailSheet extends StatefulWidget {
  final String doctorId;
  final String doctorName;
  final DateTime monthStart;
  final DateTime monthEnd;
  final String monthLabel;
  final ScrollController scrollController;

  const DoctorPerformanceDetailSheet({
    super.key,
    required this.doctorId,
    required this.doctorName,
    required this.monthStart,
    required this.monthEnd,
    required this.monthLabel,
    required this.scrollController,
  });

  @override
  State<DoctorPerformanceDetailSheet> createState() =>
      _DoctorPerformanceDetailSheetState();
}

class _DoctorPerformanceDetailSheetState
    extends State<DoctorPerformanceDetailSheet> {
  static const Color _primary = Color(0xFF0D6B6B);

  bool _isLoading = true;
  Map<String, dynamic> _detail = {};

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() => _isLoading = true);
    try {
      final profileDoc = await FirebaseFirestore.instance
          .collection('doctor_profiles')
          .doc(widget.doctorId)
          .get();

      String departmentName = 'N/A';
      if (profileDoc.exists) {
        final deptId = profileDoc.data()?['departmentId'];
        if (deptId != null) {
          final deptDoc = await FirebaseFirestore.instance
              .collection('departments')
              .doc(deptId)
              .get();
          if (deptDoc.exists) {
            departmentName = deptDoc.data()?['name'] ?? 'N/A';
          }
        }
      }

      final apptSnap = await FirebaseFirestore.instance
          .collection('appointments')
          .where('doctorId', isEqualTo: widget.doctorId)
          .where('createdAt', isGreaterThanOrEqualTo: widget.monthStart)
          .where('createdAt', isLessThan: widget.monthEnd)
          .get();

      int total = apptSnap.docs.length;
      int completed = 0, cancelled = 0, noShow = 0;

      for (final doc in apptSnap.docs) {
        switch (doc.data()['status']) {
          case 'Completed':
            completed++;
            break;
          case 'Cancelled':
            cancelled++;
            break;
          case 'NoShow':
            noShow++;
            break;
        }
      }

      final feedbackSnap = await FirebaseFirestore.instance
          .collection('feedback')
          .where('doctorId', isEqualTo: widget.doctorId)
          .where('createdAt', isGreaterThanOrEqualTo: widget.monthStart)
          .where('createdAt', isLessThan: widget.monthEnd)
          .get();

      final ratings = feedbackSnap.docs
          .map((d) => ((d.data()['rating'] ?? 0) as num).toInt())
          .toList();
      final avgRating = ratings.isEmpty
          ? 0.0
          : ratings.reduce((a, b) => a + b) / ratings.length;

      setState(() {
        _detail = {
          'department': departmentName,
          'total': total,
          'completed': completed,
          'cancelled': cancelled,
          'noShow': noShow,
          'avgRating': avgRating,
          'reviewCount': ratings.length,
        };
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  String _pct(int part, int total) {
    if (total == 0) return '0%';
    return '${((part / total) * 100).toStringAsFixed(0)}%';
  }

  @override
  Widget build(BuildContext context) {
    final total = _detail['total'] ?? 0;
    final completed = _detail['completed'] ?? 0;
    final cancelled = _detail['cancelled'] ?? 0;
    final noShow = _detail['noShow'] ?? 0;
    final avgRating = (_detail['avgRating'] ?? 0.0) as double;
    final reviewCount = _detail['reviewCount'] ?? 0;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF5F7FA),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD1D5DB),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

          // Header with close button
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.doctorName,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                      Text(
                        widget.monthLabel,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon:
                      const Icon(Icons.close_rounded, color: Color(0xFF6B7280)),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFE5E7EB)),

          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: _primary))
                : ListView(
                    controller: widget.scrollController,
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Department + Avg Rating card
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Department',
                                    style: TextStyle(
                                        fontSize: 11, color: Color(0xFF6B7280)),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _detail['department'] ?? 'N/A',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1A1A2E),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.star_rounded,
                                        size: 18, color: Color(0xFFF4B400)),
                                    const SizedBox(width: 4),
                                    Text(
                                      reviewCount == 0
                                          ? 'N/A'
                                          : avgRating.toStringAsFixed(1),
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF1A1A2E),
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  '$reviewCount review${reviewCount == 1 ? '' : 's'}',
                                  style: const TextStyle(
                                      fontSize: 11, color: Color(0xFF6B7280)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Total appointments hero
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _primary,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '$total',
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const Text(
                              'Total Appointments',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Breakdown
                      Row(
                        children: [
                          Expanded(
                            child: _BreakdownCard(
                              label: 'Completed',
                              count: completed,
                              percentage: _pct(completed, total),
                              color: const Color(0xFF0F9D58),
                              icon: Icons.check_circle_outline_rounded,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _BreakdownCard(
                              label: 'Cancelled',
                              count: cancelled,
                              percentage: _pct(cancelled, total),
                              color: const Color(0xFFDB4437),
                              icon: Icons.cancel_outlined,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _BreakdownCard(
                              label: 'No-Show',
                              count: noShow,
                              percentage: _pct(noShow, total),
                              color: const Color(0xFF6B7280),
                              icon: Icons.person_off_outlined,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(child: SizedBox()),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  final String label;
  final int count;
  final String percentage;
  final Color color;
  final IconData icon;

  const _BreakdownCard({
    required this.label,
    required this.count,
    required this.percentage,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$count',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  percentage,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
