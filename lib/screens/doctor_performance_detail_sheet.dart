import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_ui.dart';

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
  static const Color _primary = Color(0xFF0B2E33);

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

  String _initials(String name) {
    final parts = name
        .replaceFirst('Dr. ', '')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toList();
    return parts.take(2).map((w) => w[0].toUpperCase()).join();
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
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                color: AppColors.border,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

          // Header with avatar + close button
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 16, 14),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: const Color(0xFFEEE8FB),
                  child: Text(
                    _initials(widget.doctorName),
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
                        widget.doctorName,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isLoading
                            ? widget.monthLabel
                            : '${widget.monthLabel} · $total appointment${total == 1 ? '' : 's'}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Material(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.pop(context),
                    child: const SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(Icons.close_rounded,
                          color: AppColors.muted, size: 20),
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
                : ListView(
                    controller: widget.scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    children: [
                      // Breakdown tiles
                      Row(
                        children: [
                          Expanded(
                            child: _BreakdownCard(
                              label: 'Completed',
                              count: completed,
                              percentage: _pct(completed, total),
                              colors: AppChipColors.green,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _BreakdownCard(
                              label: 'Cancelled',
                              count: cancelled,
                              percentage: _pct(cancelled, total),
                              colors: AppChipColors.red,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _BreakdownCard(
                              label: 'No-show',
                              count: noShow,
                              percentage: _pct(noShow, total),
                              colors: AppChipColors.yellow,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Department + rating rows
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: AppColors.bg,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          children: [
                            _infoLine(
                              'Department',
                              Text(
                                _detail['department'] ?? 'N/A',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.text,
                                ),
                              ),
                            ),
                            const Divider(height: 1, color: AppColors.divider),
                            _infoLine(
                              'Patient rating',
                              reviewCount == 0
                                  ? const Text(
                                      'No reviews',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppColors.faint,
                                      ),
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.star_rounded,
                                            size: 16, color: Color(0xFFE0A800)),
                                        const SizedBox(width: 3),
                                        Text(
                                          avgRating.toStringAsFixed(1),
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF8A6D00),
                                          ),
                                        ),
                                        Text(
                                          ' · $reviewCount review${reviewCount == 1 ? '' : 's'}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _infoLine(String label, Widget value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.muted,
              ),
            ),
          ),
          value,
        ],
      ),
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  final String label;
  final int count;
  final String percentage;
  final AppChipColors colors;

  const _BreakdownCard({
    required this.label,
    required this.count,
    required this.percentage,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: colors.fg,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: colors.fg,
            ),
          ),
          Text(
            percentage,
            style: TextStyle(
              fontSize: 11,
              color: colors.fg.withOpacity(0.75),
            ),
          ),
        ],
      ),
    );
  }
}
