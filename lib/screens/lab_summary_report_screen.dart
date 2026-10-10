import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../widgets/app_ui.dart';
import 'reports_screen.dart';

// Content-only widget for the Lab Summary tab — no Scaffold/AppBar
// of its own, since it lives inside ReportsScreen's TabBarView.
class LabSummaryTab extends StatefulWidget {
  const LabSummaryTab({super.key});

  @override
  State<LabSummaryTab> createState() => _LabSummaryTabState();
}

class _LabSummaryTabState extends State<LabSummaryTab> {
  // Theme colors — matched to Admin Dashboard's green palette
  static const Color _primary = Color(0xFF0E6E68);
  static const Color _bg = Color(0xFFF2F5F5);

  DateTime _selectedMonth = DateTime.now();
  bool _isLoading = true;
  Map<String, dynamic> _data = {};

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  ({DateTime start, DateTime end}) _getMonthRange() {
    final start = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final end = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1);
    return (start: start, end: end);
  }

  Future<void> _loadSummary() async {
    setState(() => _isLoading = true);
    try {
      final range = _getMonthRange();

      final testsSnap = await FirebaseFirestore.instance
          .collection('lab_tests')
          .where('createdAt', isGreaterThanOrEqualTo: range.start)
          .where('createdAt', isLessThan: range.end)
          .get();

      int total = testsSnap.docs.length;
      int completed = 0, pending = 0, inProgress = 0, cancelled = 0;
      num revenue = 0;
      final Map<String, int> byTestType = {};

      for (final doc in testsSnap.docs) {
        final data = doc.data();

        switch (data['status']) {
          case 'Completed':
            completed++;
            if (data['paymentStatus'] == 'Paid') {
              revenue += (data['charge'] ?? 0) as num;
            }
            break;
          case 'Pending':
            pending++;
            break;
          case 'In Progress':
            inProgress++;
            break;
          case 'Cancelled':
            cancelled++;
            break;
        }

        final testType = data['testType'] ?? 'Other';
        byTestType[testType] = (byTestType[testType] ?? 0) + 1;
      }

      final sortedTypes = byTestType.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      setState(() {
        _data = {
          'total': total,
          'completed': completed,
          'pending': pending,
          'inProgress': inProgress,
          'cancelled': cancelled,
          'revenue': revenue,
          'byTestType': sortedTypes,
        };
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Error loading lab summary: $e');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: const Color(0xFF9A2E16),
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
    _loadSummary();
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

  String _pct(int part, int total) {
    if (total == 0) return '0%';
    return '${((part / total) * 100).round()}%';
  }

  @override
  Widget build(BuildContext context) {
    final total = _data['total'] ?? 0;
    final completed = _data['completed'] ?? 0;
    final pending = _data['pending'] ?? 0;
    final inProgress = _data['inProgress'] ?? 0;
    final cancelled = _data['cancelled'] ?? 0;
    final revenue = _data['revenue'] ?? 0;
    final byTestType = ((_data['byTestType'] ?? []) as List)
        .map((e) => e as MapEntry<String, int>)
        .toList();

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
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.teal))
                : RefreshIndicator(
                    onRefresh: _loadSummary,
                    color: AppColors.teal,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                      children: [
                        // Total tests | Lab revenue
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: IntrinsicHeight(
                            child: Row(
                              children: [
                                Expanded(
                                  child: _metric('Total tests', '$total'),
                                ),
                                Container(
                                  width: 1,
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 12),
                                  color: AppColors.divider,
                                ),
                                Expanded(
                                  child: _metric('Lab revenue', 'Rs $revenue'),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        _sectionLabel('BY STATUS'),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Column(
                            children: [
                              _StatusRow(
                                label: 'Completed',
                                count: completed,
                                percentage: _pct(completed, total),
                                color: const Color(0xFF0B5E57),
                              ),
                              const Divider(
                                  height: 1, color: AppColors.divider),
                              _StatusRow(
                                label: 'Pending',
                                count: pending,
                                percentage: _pct(pending, total),
                                color: const Color(0xFFC9A400),
                              ),
                              const Divider(
                                  height: 1, color: AppColors.divider),
                              _StatusRow(
                                label: 'In progress',
                                count: inProgress,
                                percentage: _pct(inProgress, total),
                                color: const Color(0xFF1D4F91),
                              ),
                              const Divider(
                                  height: 1, color: AppColors.divider),
                              _StatusRow(
                                label: 'Cancelled',
                                count: cancelled,
                                percentage: _pct(cancelled, total),
                                color: const Color(0xFF9A2E16),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        _sectionLabel('BY TEST TYPE'),
                        const SizedBox(height: 10),
                        if (byTestType.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(22),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Center(
                              child: Text(
                                'No lab tests this month',
                                style: TextStyle(
                                    fontSize: 13, color: AppColors.faint),
                              ),
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(
                              children: byTestType.map((entry) {
                                final isLast = entry == byTestType.last;
                                return Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 13),
                                  decoration: BoxDecoration(
                                    border: isLast
                                        ? null
                                        : const Border(
                                            bottom: BorderSide(
                                                color: AppColors.divider)),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          entry.key,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.text,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: AppColors.tealSoft,
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          '${entry.value}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.teal,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppColors.text,
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
        color: AppColors.muted,
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final int count;
  final String percentage;
  final Color color;

  const _StatusRow({
    required this.label,
    required this.count,
    required this.percentage,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
          ),
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 36,
            child: Text(
              percentage,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
