import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

// Content-only widget for the Lab Summary tab — no Scaffold/AppBar
// of its own, since it lives inside ReportsScreen's TabBarView.
class LabSummaryTab extends StatefulWidget {
  const LabSummaryTab({super.key});

  @override
  State<LabSummaryTab> createState() => _LabSummaryTabState();
}

class _LabSummaryTabState extends State<LabSummaryTab> {
  // Theme colors — matched to Admin Dashboard's green palette
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _bg = Color(0xFFF4F7F6);

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
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: _primary))
                : RefreshIndicator(
                    onRefresh: _loadSummary,
                    color: _primary,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: _primary,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: [
                              const Text(
                                'TOTAL TESTS',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white70,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '$total',
                                style: const TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Revenue: Rs. $revenue',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'BY STATUS',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF6B7280),
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Column(
                            children: [
                              _StatusRow(
                                label: 'Completed',
                                count: completed,
                                percentage: _pct(completed, total),
                                color: const Color(0xFF0F9D58),
                                icon: Icons.check_circle_outline_rounded,
                              ),
                              const Divider(
                                  height: 20, color: Color(0xFFF0F0F0)),
                              _StatusRow(
                                label: 'Pending',
                                count: pending,
                                percentage: _pct(pending, total),
                                color: const Color(0xFFF4B400),
                                icon: Icons.hourglass_empty_rounded,
                              ),
                              const Divider(
                                  height: 20, color: Color(0xFFF0F0F0)),
                              _StatusRow(
                                label: 'In Progress',
                                count: inProgress,
                                percentage: _pct(inProgress, total),
                                color: const Color(0xFF1A73E8),
                                icon: Icons.science_outlined,
                              ),
                              const Divider(
                                  height: 20, color: Color(0xFFF0F0F0)),
                              _StatusRow(
                                label: 'Cancelled',
                                count: cancelled,
                                percentage: _pct(cancelled, total),
                                color: const Color(0xFFDB4437),
                                icon: Icons.cancel_outlined,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'BY TEST TYPE',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF6B7280),
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (byTestType.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border:
                                  Border.all(color: const Color(0xFFE5E7EB)),
                            ),
                            child: const Center(
                              child: Text(
                                'No lab tests this month',
                                style: TextStyle(
                                    fontSize: 13, color: Color(0xFF9CA3AF)),
                              ),
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border:
                                  Border.all(color: const Color(0xFFE5E7EB)),
                            ),
                            child: Column(
                              children: byTestType.map((entry) {
                                final isLast = entry == byTestType.last;
                                return Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 12),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            entry.key,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF1A1A2E),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: _primary.withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              '${entry.value}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: _primary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (!isLast)
                                      const Divider(
                                          height: 1, color: Color(0xFFF0F0F0)),
                                  ],
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
}

class _StatusRow extends StatelessWidget {
  final String label;
  final int count;
  final String percentage;
  final Color color;
  final IconData icon;

  const _StatusRow({
    required this.label,
    required this.count,
    required this.percentage,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A2E),
            ),
          ),
        ),
        Text(
          '$count',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1A2E),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          percentage,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}