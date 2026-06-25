import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

// This widget renders the Overview report content (toggle + date nav +
// cards). It does NOT include its own Scaffold/AppBar — it's designed
// to be embedded inside the ReportsScreen's TabBarView, which provides
// the shared AppBar and tab bar for all four report sections.
class ReportsOverviewTab extends StatefulWidget {
  const ReportsOverviewTab({super.key});

  @override
  State<ReportsOverviewTab> createState() => _ReportsOverviewTabState();
}

class _ReportsOverviewTabState extends State<ReportsOverviewTab> {
  static const Color _primary = Color(0xFF0D6B6B);
  static const Color _bg = Color(0xFFF5F7FA);

  // true = Daily tab selected, false = Monthly tab selected
  bool _isDaily = true;

  // The currently selected date (for Daily) or month (for Monthly).
  DateTime _selectedDate = DateTime.now();

  bool _isLoading = true;
  Map<String, dynamic> _reportData = {};

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  // Returns the start/end boundaries we need to query Firestore with,
  // based on whether we're in Daily or Monthly mode.
  ({DateTime start, DateTime end}) _getDateRange() {
    if (_isDaily) {
      final start =
          DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      final end = start.add(const Duration(days: 1));
      return (start: start, end: end);
    } else {
      final start = DateTime(_selectedDate.year, _selectedDate.month, 1);
      final end = DateTime(_selectedDate.year, _selectedDate.month + 1, 1);
      return (start: start, end: end);
    }
  }

  Future<void> _loadReport() async {
    setState(() => _isLoading = true);

    try {
      final range = _getDateRange();

      // ---- APPOINTMENTS ----
      final apptSnap = await FirebaseFirestore.instance
          .collection('appointments')
          .where('createdAt', isGreaterThanOrEqualTo: range.start)
          .where('createdAt', isLessThan: range.end)
          .get();

      int totalAppts = apptSnap.docs.length;
      int completed = 0, pending = 0, cancelled = 0;
      int inPerson = 0, videoCall = 0, walkIn = 0;

      for (final doc in apptSnap.docs) {
        final data = doc.data();
        switch (data['status']) {
          case 'Completed':
            completed++;
            break;
          case 'Requested':
            pending++;
            break;
          case 'Cancelled':
          case 'NoShow':
            cancelled++;
            break;
          // 'Confirmed' appointments are upcoming/scheduled — not
          // counted here, per the decision to keep this simple.
        }
        switch (data['appointmentType']) {
          case 'IN_PERSON':
            inPerson++;
            break;
          case 'VIDEO_CALL':
            videoCall++;
            break;
          case 'WALK_IN':
            walkIn++;
            break;
        }
      }

      // ---- REVENUE (Paid payments) ----
      final paidSnap = await FirebaseFirestore.instance
          .collection('payments')
          .where('status', isEqualTo: 'Paid')
          .where('createdAt', isGreaterThanOrEqualTo: range.start)
          .where('createdAt', isLessThan: range.end)
          .get();

      num consultationRev = 0, labRev = 0, roomRev = 0;
      for (final doc in paidSnap.docs) {
        final data = doc.data();
        final amount = (data['amount'] ?? 0) as num;
        switch (data['type']) {
          case 'Consultation':
            consultationRev += amount;
            break;
          case 'Lab':
            labRev += amount;
            break;
          case 'Room':
            roomRev += amount;
            break;
        }
      }
      final totalRev = consultationRev + labRev + roomRev;

      // ---- PENDING BILLS ----
      final pendingSnap = await FirebaseFirestore.instance
          .collection('payments')
          .where('status', isEqualTo: 'Pending')
          .where('createdAt', isGreaterThanOrEqualTo: range.start)
          .where('createdAt', isLessThan: range.end)
          .get();

      num pendingAmount = 0;
      for (final doc in pendingSnap.docs) {
        pendingAmount += (doc.data()['amount'] ?? 0) as num;
      }

      // ---- BED OCCUPANCY (current snapshot — not time-bound,
      // shown for context alongside this period's stats) ----
      final bedsSnap =
          await FirebaseFirestore.instance.collection('beds').get();
      final totalBedsCount = bedsSnap.docs.length;
      final occupiedBedsCount = bedsSnap.docs
          .where((d) => d.data()['availability'] == 'Occupied')
          .length;
      final occupancyPct = totalBedsCount == 0
          ? 0
          : ((occupiedBedsCount / totalBedsCount) * 100).round();

      Map<String, dynamic> result = {
        'totalAppts': totalAppts,
        'completed': completed,
        'pending': pending,
        'cancelled': cancelled,
        'inPerson': inPerson,
        'videoCall': videoCall,
        'walkIn': walkIn,
        'consultationRev': consultationRev,
        'labRev': labRev,
        'roomRev': roomRev,
        'totalRev': totalRev,
        'pendingAmount': pendingAmount,
        'pendingCount': pendingSnap.docs.length,
        'occupancyPct': occupancyPct,
      };

      // ---- PATIENT STATS (Monthly only) ----
      if (!_isDaily) {
        final allPatientsSnap = await FirebaseFirestore.instance
            .collection('users')
            .where('role', isEqualTo: 'patient')
            .get();

        int newPatients = 0;
        for (final doc in allPatientsSnap.docs) {
          final createdAt = doc.data()['createdAt'];
          if (createdAt is Timestamp) {
            final date = createdAt.toDate();
            if (date.isAfter(range.start) && date.isBefore(range.end)) {
              newPatients++;
            }
          }
        }

        // Returning = patients with more than 1 appointment created
        // within this month's range.
        final apptsByPatient = <String, int>{};
        for (final doc in apptSnap.docs) {
          final pid = doc.data()['patientId'];
          if (pid != null) {
            apptsByPatient[pid] = (apptsByPatient[pid] ?? 0) + 1;
          }
        }
        final returning =
            apptsByPatient.values.where((count) => count > 1).length;

        result['totalPatients'] = allPatientsSnap.docs.length;
        result['newPatients'] = newPatients;
        result['returningPatients'] = returning;
      }

      setState(() {
        _reportData = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Error loading report: $e');
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

  void _switchTab(bool toDaily) {
    if (_isDaily == toDaily) return;
    setState(() {
      _isDaily = toDaily;
      _selectedDate = DateTime.now();
    });
    _loadReport();
  }

  // Moves the selected date/month forward or backward, respecting
  // the limits: can't go into the future, and can't go further back
  // than 30 days (daily) or 12 months (monthly).
  void _navigate(int direction) {
    DateTime newDate;
    if (_isDaily) {
      newDate = _selectedDate.add(Duration(days: direction));
      if (newDate.isAfter(DateTime.now())) return;
      final daysDiff = DateTime.now().difference(newDate).inDays;
      if (daysDiff > 30) return;
    } else {
      newDate =
          DateTime(_selectedDate.year, _selectedDate.month + direction, 1);
      final now = DateTime.now();
      if (newDate.isAfter(DateTime(now.year, now.month, 1))) return;
      final monthsDiff =
          (now.year - newDate.year) * 12 + (now.month - newDate.month);
      if (monthsDiff > 12) return;
    }
    setState(() => _selectedDate = newDate);
    _loadReport();
  }

  bool _canGoNext() {
    if (_isDaily) {
      final next = _selectedDate.add(const Duration(days: 1));
      return !next.isAfter(DateTime.now());
    } else {
      final next = DateTime(_selectedDate.year, _selectedDate.month + 1, 1);
      final now = DateTime.now();
      return !next.isAfter(DateTime(now.year, now.month, 1));
    }
  }

  bool _canGoPrevious() {
    if (_isDaily) {
      final prev = _selectedDate.subtract(const Duration(days: 1));
      return DateTime.now().difference(prev).inDays <= 30;
    } else {
      final prev = DateTime(_selectedDate.year, _selectedDate.month - 1, 1);
      final now = DateTime.now();
      final monthsDiff = (now.year - prev.year) * 12 + (now.month - prev.month);
      return monthsDiff <= 12;
    }
  }

  String get _dateLabel {
    if (_isDaily) {
      return DateFormat('MMMM d, yyyy').format(_selectedDate);
    } else {
      return DateFormat('MMMM yyyy').format(_selectedDate);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _bg,
      child: Column(
        children: [
          // Daily / Monthly toggle
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: _ToggleButton(
                    label: 'Daily',
                    isActive: _isDaily,
                    onTap: () => _switchTab(true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ToggleButton(
                    label: 'Monthly',
                    isActive: !_isDaily,
                    onTap: () => _switchTab(false),
                  ),
                ),
              ],
            ),
          ),

          // Date navigation
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
                  _dateLabel,
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

          // Quick snapshot strip — a fast horizontal glance at the
          // headline numbers before scrolling into the detailed cards.
          if (!_isLoading)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.only(bottom: 12),
              height: 92,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _SnapshotChip(
                    icon: Icons.calendar_today_rounded,
                    iconColor: const Color(0xFF1A73E8),
                    value: '${_reportData['totalAppts'] ?? 0}',
                    label: 'Appts',
                  ),
                  _SnapshotChip(
                    icon: Icons.payments_outlined,
                    iconColor: const Color(0xFF0F9D58),
                    value: 'Rs ${_reportData['totalRev'] ?? 0}',
                    label: 'Collected',
                  ),
                  _SnapshotChip(
                    icon: Icons.hourglass_empty_rounded,
                    iconColor: const Color(0xFFF4B400),
                    value: 'Rs ${_reportData['pendingAmount'] ?? 0}',
                    label: 'Bills Due',
                  ),
                  _SnapshotChip(
                    icon: Icons.bed_outlined,
                    iconColor: const Color(0xFF7C4DFF),
                    value: '${_reportData['occupancyPct'] ?? 0}%',
                    label: 'Occupied',
                  ),
                ],
              ),
            ),

          // Report content
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: _primary))
                : RefreshIndicator(
                    onRefresh: _loadReport,
                    color: _primary,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _AppointmentsCard(data: _reportData),
                        const SizedBox(height: 12),
                        _RevenueCard(data: _reportData),
                        if (!_isDaily) ...[
                          const SizedBox(height: 12),
                          _PatientStatsCard(data: _reportData),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ToggleButton({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  static const Color _primary = Color(0xFF0D6B6B);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? _primary : const Color(0xFFF5F7FA),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isActive ? Colors.white : const Color(0xFF6B7280),
          ),
        ),
      ),
    );
  }
}

class _AppointmentsCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const _AppointmentsCard({required this.data});

  static const Color _primary = Color(0xFF0D6B6B);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_today_rounded,
                  size: 16, color: _primary),
              const SizedBox(width: 8),
              const Text(
                'APPOINTMENTS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6B7280),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _StatBlock(label: 'Total', value: '${data['totalAppts'] ?? 0}'),
              _StatBlock(
                label: 'Completed',
                value: '${data['completed'] ?? 0}',
                color: const Color(0xFF0F9D58),
              ),
              _StatBlock(
                label: 'Pending',
                value: '${data['pending'] ?? 0}',
                color: const Color(0xFFF4B400),
              ),
              _StatBlock(
                label: 'Cancelled',
                value: '${data['cancelled'] ?? 0}',
                color: const Color(0xFFDB4437),
              ),
            ],
          ),
          if ((data['totalAppts'] ?? 0) > 0) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _TypeChip(label: 'In-Person', count: data['inPerson'] ?? 0),
                _TypeChip(label: 'Video Call', count: data['videoCall'] ?? 0),
                _TypeChip(label: 'Walk-In', count: data['walkIn'] ?? 0),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _StatBlock({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color ?? const Color(0xFF1A1A2E),
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final int count;

  const _TypeChip({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF0D6B6B).withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$label: $count',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFF0D6B6B),
        ),
      ),
    );
  }
}

class _RevenueCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const _RevenueCard({required this.data});

  static const Color _primary = Color(0xFF0D6B6B);

  @override
  Widget build(BuildContext context) {
    final consultation = (data['consultationRev'] ?? 0) as num;
    final lab = (data['labRev'] ?? 0) as num;
    final room = (data['roomRev'] ?? 0) as num;
    final total = (data['totalRev'] ?? 0) as num;
    final pendingAmount = (data['pendingAmount'] ?? 0) as num;
    final pendingCount = data['pendingCount'] ?? 0;

    final consultationPct = total > 0 ? consultation / total : 0.0;
    final labPct = total > 0 ? lab / total : 0.0;
    final roomPct = total > 0 ? room / total : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.payments_outlined,
                      size: 16, color: Color(0xFF0F9D58)),
                  const SizedBox(width: 8),
                  const Text(
                    'REVENUE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF6B7280),
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              Text(
                'Rs. $total',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F9D58),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (total > 0) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 10,
                child: Row(
                  children: [
                    Expanded(
                      flex: (consultationPct * 1000).round().clamp(1, 1000),
                      child: Container(color: const Color(0xFF0D6B6B)),
                    ),
                    Expanded(
                      flex: (labPct * 1000).round().clamp(1, 1000),
                      child: Container(color: const Color(0xFF4DB6AC)),
                    ),
                    Expanded(
                      flex: (roomPct * 1000).round().clamp(1, 1000),
                      child: Container(color: const Color(0xFFB2DFDB)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _LegendDot(
                    color: const Color(0xFF0D6B6B),
                    label:
                        'Consultation ${(consultationPct * 100).toStringAsFixed(0)}%'),
                _LegendDot(
                    color: const Color(0xFF4DB6AC),
                    label: 'Lab ${(labPct * 100).toStringAsFixed(0)}%'),
                _LegendDot(
                    color: const Color(0xFFB2DFDB),
                    label: 'Room ${(roomPct * 100).toStringAsFixed(0)}%'),
              ],
            ),
            const SizedBox(height: 12),
          ] else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No revenue collected in this period',
                style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF4B400).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.hourglass_empty_rounded,
                        size: 14, color: Color(0xFFF4B400)),
                    const SizedBox(width: 6),
                    Text(
                      'Pending Bills ($pendingCount)',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFB8860B),
                      ),
                    ),
                  ],
                ),
                Text(
                  'Rs. $pendingAmount',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFB8860B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
        ),
      ],
    );
  }
}

class _PatientStatsCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const _PatientStatsCard({required this.data});

  static const Color _primary = Color(0xFF0D6B6B);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.people_outline_rounded,
                  size: 16, color: Color(0xFF7C4DFF)),
              const SizedBox(width: 8),
              const Text(
                'PATIENT STATS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6B7280),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _StatBlock(
                  label: 'Total Patients',
                  value: '${data['totalPatients'] ?? 0}'),
              _StatBlock(
                label: 'New This Month',
                value: '${data['newPatients'] ?? 0}',
                color: const Color(0xFF0F9D58),
              ),
              _StatBlock(
                label: 'Returning',
                value: '${data['returningPatients'] ?? 0}',
                color: const Color(0xFF1A73E8),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SnapshotChip extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _SnapshotChip({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A2E),
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }
}
