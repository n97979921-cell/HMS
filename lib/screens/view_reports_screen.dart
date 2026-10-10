import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../widgets/app_ui.dart';
import 'reports_screen.dart';

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
  // Theme colors — matched to Admin Dashboard's green palette
  static const Color _primary = Color(0xFF0E6E68);
  static const Color _bg = Color(0xFFF2F5F5);

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
        // Total patients = all patient accounts that exist (not
        // limited to this month — this is a running total).
        final allPatientsSnap = await FirebaseFirestore.instance
            .collection('users')
            .where('role', isEqualTo: 'patient')
            .get();

        // New vs Returning is based ONLY on patients who actually
        // had an appointment this month (apptSnap, already fetched
        // above for this same date range). For each of those
        // patients we look up when they originally signed up
        // (users.createdAt, which never changes):
        //   - signed up THIS month  → New
        //   - signed up a PAST month → Returning
        final Set<String> patientIdsWithApptsThisMonth = {};
        for (final doc in apptSnap.docs) {
          final pid = doc.data()['patientId'];
          if (pid != null) patientIdsWithApptsThisMonth.add(pid);
        }

        int newPatients = 0;
        int returningPatients = 0;

        for (final patientId in patientIdsWithApptsThisMonth) {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(patientId)
              .get();

          final createdAt = userDoc.data()?['createdAt'];
          if (createdAt is! Timestamp) continue;
          final signupDate = createdAt.toDate();

          if (signupDate.isAfter(range.start) &&
              signupDate.isBefore(range.end)) {
            newPatients++;
          } else {
            returningPatients++;
          }
        }

        result['totalPatients'] = allPatientsSnap.docs.length;
        result['newPatients'] = newPatients;
        result['returningPatients'] = returningPatients;
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
      backgroundColor: const Color(0xFF9A2E16),
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
          // Daily / Monthly toggle + date navigation (dark strip)
          ReportsHeaderStrip(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    children: [
                      _ToggleButton(
                        label: 'Daily',
                        isActive: _isDaily,
                        onTap: () => _switchTab(true),
                      ),
                      _ToggleButton(
                        label: 'Monthly',
                        isActive: !_isDaily,
                        onTap: () => _switchTab(false),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                ReportsDateNav(
                  label: _isDaily
                      ? DateFormat('MMM d, yyyy').format(_selectedDate)
                      : DateFormat('MMMM yyyy').format(_selectedDate),
                  onPrev: _canGoPrevious() ? () => _navigate(-1) : null,
                  onNext: _canGoNext() ? () => _navigate(1) : null,
                ),
              ],
            ),
          ),

          // Report content
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.teal))
                : RefreshIndicator(
                    onRefresh: _loadReport,
                    color: AppColors.teal,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                      children: [
                        // Quick snapshot tiles — same 4 headline numbers
                        Row(
                          children: [
                            _SnapshotChip(
                              label: 'Appointments',
                              value: '${_reportData['totalAppts'] ?? 0}',
                            ),
                            const SizedBox(width: 10),
                            _SnapshotChip(
                              label: 'Revenue collected',
                              value: 'Rs ${_reportData['totalRev'] ?? 0}',
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _SnapshotChip(
                              label:
                                  'Pending bills (${_reportData['pendingCount'] ?? 0})',
                              value: 'Rs ${_reportData['pendingAmount'] ?? 0}',
                            ),
                            const SizedBox(width: 10),
                            _SnapshotChip(
                              label: 'Bed occupancy',
                              value: '${_reportData['occupancyPct'] ?? 0}%',
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isActive ? AppColors.mint : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: isActive ? AppColors.header : Colors.white,
          ),
        ),
      ),
    );
  }
}

/// White card with a bold title.
class _ReportCard extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final List<Widget> children;

  const _ReportCard({
    required this.title,
    this.trailing,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _AppointmentsCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const _AppointmentsCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return _ReportCard(
      title: 'Appointments',
      children: [
        Row(
          children: [
            _StatBlock(label: 'Total', value: '${data['totalAppts'] ?? 0}'),
            _StatBlock(
              label: 'Completed',
              value: '${data['completed'] ?? 0}',
              color: const Color(0xFF0B5E57),
            ),
            _StatBlock(
              label: 'Pending',
              value: '${data['pending'] ?? 0}',
              color: const Color(0xFF8A6D00),
            ),
            _StatBlock(
              label: 'Cancelled',
              value: '${data['cancelled'] ?? 0}',
              color: const Color(0xFF9A2E16),
            ),
          ],
        ),
        if ((data['totalAppts'] ?? 0) > 0) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                _TypeChip(label: 'In-person', count: data['inPerson'] ?? 0),
                _TypeChip(label: 'Video call', count: data['videoCall'] ?? 0),
                _TypeChip(label: 'Walk-in', count: data['walkIn'] ?? 0),
              ],
            ),
          ),
        ],
      ],
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
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color ?? AppColors.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
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
    return Expanded(
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$label '),
            TextSpan(
              text: '$count',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
          ],
        ),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.muted,
        ),
      ),
    );
  }
}

class _RevenueCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const _RevenueCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final consultation = (data['consultationRev'] ?? 0) as num;
    final lab = (data['labRev'] ?? 0) as num;
    final room = (data['roomRev'] ?? 0) as num;
    final total = (data['totalRev'] ?? 0) as num;

    final consultationPct = total > 0 ? consultation / total : 0.0;
    final labPct = total > 0 ? lab / total : 0.0;
    final roomPct = total > 0 ? room / total : 0.0;

    const cConsult = Color(0xFF0E6E68);
    const cLab = Color(0xFF7FB8E8);
    const cRoom = Color(0xFFE0B04A);

    return _ReportCard(
      title: 'Revenue',
      trailing: Text(
        'Rs $total',
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: AppColors.teal,
        ),
      ),
      children: [
        if (total > 0) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  if (consultation > 0)
                    Expanded(
                      flex: (consultationPct * 1000).round().clamp(1, 1000),
                      child: Container(color: cConsult),
                    ),
                  if (lab > 0)
                    Expanded(
                      flex: (labPct * 1000).round().clamp(1, 1000),
                      child: Container(color: cLab),
                    ),
                  if (room > 0)
                    Expanded(
                      flex: (roomPct * 1000).round().clamp(1, 1000),
                      child: Container(color: cRoom),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _LegendDot(
                  color: cConsult,
                  label:
                      'Consultation ${(consultationPct * 100).toStringAsFixed(0)}%'),
              _LegendDot(
                  color: cLab,
                  label: 'Lab ${(labPct * 100).toStringAsFixed(0)}%'),
              _LegendDot(
                  color: cRoom,
                  label: 'Room ${(roomPct * 100).toStringAsFixed(0)}%'),
            ],
          ),
        ] else
          const Text(
            'No revenue collected in this period',
            style: TextStyle(fontSize: 12, color: AppColors.faint),
          ),
      ],
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
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.muted,
          ),
        ),
      ],
    );
  }
}

class _PatientStatsCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const _PatientStatsCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return _ReportCard(
      title: 'Patients',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Text(
          'Monthly only',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.muted,
          ),
        ),
      ),
      children: [
        Row(
          children: [
            _StatBlock(label: 'Total', value: '${data['totalPatients'] ?? 0}'),
            _StatBlock(
              label: 'New',
              value: '${data['newPatients'] ?? 0}',
              color: AppColors.teal,
            ),
            _StatBlock(
              label: 'Returning',
              value: '${data['returningPatients'] ?? 0}',
              color: AppColors.blue,
            ),
          ],
        ),
      ],
    );
  }
}

class _SnapshotChip extends StatelessWidget {
  final String value;
  final String label;

  const _SnapshotChip({
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
