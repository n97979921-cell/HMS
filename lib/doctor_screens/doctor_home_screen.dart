import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'appointment_detail_screen.dart';
import 'appointment_status.dart';
import 'doctor_appointment_list_item.dart';
import 'firebase_doctor_repository.dart';
import 'doctor_profile_screen.dart';

/// DOCTOR HOME — aaj ke patients
///
/// SCHEMA RULES:
///  - IN_PERSON/WALK_IN: Waiting = CheckedIn (receptionist ne check-in kiya)
///  - VIDEO_CALL: Waiting = Confirmed (video mein "aana" nahi hota, is liye
///    Confirmed hi "waiting" maana jata hai — patient/doctor Join/Start
///    dabate hain seedha appointment-detail se)
///  - Doctor "Completed" mark karta hai (in-person, walk-in, video — teeno)
///
/// VIDEO CALL LAZY-CHECK (list load hote waqt, jaise receptionist ka
/// NoShow-check pattern — Cloud Function nahi, free tier):
///   Confirmed (Start nahi hua) + slot-time se 5+ min guzar gaye
///     → Cancelled + FULL refund (doctor ki galti — service mili hi nahi)
///   InProgress (Start hua) + patientJoinedAt null + slot-time se 5+ min
///     → NoShow + HALF refund (patient ki galti)
///   InProgress + patientJoinedAt set → chhuo mat, consultation chal rahi
class DoctorHomeScreen extends StatefulWidget {
  const DoctorHomeScreen({super.key});

  @override
  State<DoctorHomeScreen> createState() => _DoctorHomeScreenState();
}

class _DoctorHomeScreenState extends State<DoctorHomeScreen> {
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _primaryDark = Color(0xFF0D6B5A);

  String _doctorName = '';
  bool _isLoading = true;
  int _autoProcessed = 0;

  DateTime _selectedDate = DateTime.now();
  String _selectedTab = 'CheckedIn'; // CheckedIn(=Waiting) | Completed

  List<Map<String, dynamic>> _appointments = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  String _dateStr(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DateTime? _slotDateTime(String? date, String? startTime) {
    try {
      final d = DateTime.parse(date!);
      final p = startTime!.split(':').map(int.parse).toList();
      return DateTime(d.year, d.month, d.day, p[0], p[1]);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _autoProcessed = 0;
    });
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      _doctorName = userDoc.data()?['name'] ?? 'Doctor';

      final slotsSnap = await FirebaseFirestore.instance
          .collection('slots')
          .where('doctorId', isEqualTo: uid)
          .where('date', isEqualTo: _dateStr(_selectedDate))
          .where('slotStatus', isEqualTo: 'BOOKED')
          .get();

      final List<Map<String, dynamic>> result = [];

      for (final slotDoc in slotsSnap.docs) {
        final slot = slotDoc.data();
        final apptId = slot['appointmentId'];
        if (apptId == null) continue;

        final apptDoc = await FirebaseFirestore.instance
            .collection('appointments')
            .doc(apptId)
            .get();
        if (!apptDoc.exists) continue;
        final appt = apptDoc.data()!;

        final status = appt['status'];
        final type = appt['appointmentType'];
        final isVideo = type == 'VIDEO_CALL';

        final slotDt = _slotDateTime(slot['date'], slot['startTime']);

        // ── VIDEO CALL LAZY-CHECK ──
        if (isVideo && slotDt != null) {
          final now = DateTime.now();
          final fiveMinPast =
              now.isAfter(slotDt.add(const Duration(minutes: 5)));

          if (status == 'Confirmed' && fiveMinPast) {
            // Doctor ne Start nahi kiya — service mili hi nahi, full refund
            await _autoProcessVideo(apptId, 'Cancelled', fullRefund: true);
            _autoProcessed++;
            continue;
          }
          if (status == 'InProgress' &&
              appt['patientJoinedAt'] == null &&
              fiveMinPast) {
            // Doctor ready tha, patient nahi aaya — half refund
            await _autoProcessVideo(apptId, 'NoShow', fullRefund: false);
            _autoProcessed++;
            continue;
          }
        }

        // Tab filter: Waiting = CheckedIn (in-person/walk-in) YA
        // VIDEO_CALL+Confirmed (video mein "aana" nahi hota)
        final isWaiting = status == 'CheckedIn' ||
            (isVideo && status == 'Confirmed') ||
            (isVideo && status == 'InProgress');

        if (_selectedTab == 'CheckedIn' && !isWaiting) continue;
        if (_selectedTab == 'Completed' && status != 'Completed') continue;

        String patientName = 'Patient';
        try {
          final p = await FirebaseFirestore.instance
              .collection('users')
              .doc(appt['patientId'])
              .get();
          patientName = p.data()?['name'] ?? 'Patient';
        } catch (_) {}

        result.add({
          'appointmentId': apptId,
          'patientId': appt['patientId'],
          'patientName': patientName,
          'startTime': slot['startTime'] ?? '',
          'appointmentType': type ?? 'IN_PERSON',
          'status': status,
          'admissionRecommended': appt['admissionRecommended'] ?? false,
        });
      }

      result.sort((a, b) =>
          (a['startTime'] as String).compareTo(b['startTime'] as String));

      setState(() {
        _appointments = result;
        _isLoading = false;
      });

      if (_autoProcessed > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '$_autoProcessed video call(s) auto-processed (no-show/refund)'),
          backgroundColor: const Color(0xFFB8860B),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Error loading appointments: $e');
    }
  }

  // Video call timeout — appointment status badlo + payment refund set karo.
  // Transaction: reads pehle, writes baad. Double-check status abhi bhi
  // wahi hai (kahin isi beech doctor/patient ne action na li ho).
  Future<void> _autoProcessVideo(String apptId, String newStatus,
      {required bool fullRefund}) async {
    try {
      final paySnap = await FirebaseFirestore.instance
          .collection('payments')
          .where('appointmentId', isEqualTo: apptId)
          .where('status', isEqualTo: 'Paid')
          .limit(1)
          .get();
      final payRef =
          paySnap.docs.isNotEmpty ? paySnap.docs.first.reference : null;
      final payAmount = paySnap.docs.isNotEmpty
          ? (paySnap.docs.first.data()['amount'] ?? 0)
          : 0;

      final apptRef =
          FirebaseFirestore.instance.collection('appointments').doc(apptId);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final apptSnap = await transaction.get(apptRef);
        if (!apptSnap.exists) return;
        final currentStatus = apptSnap.data()!['status'];
        // Double-check: sirf tab process karo jab abhi bhi wahi state ho
        if (newStatus == 'Cancelled' && currentStatus != 'Confirmed') return;
        if (newStatus == 'NoShow' && currentStatus != 'InProgress') return;

        transaction.update(apptRef, {
          'status': newStatus,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        if (payRef != null) {
          transaction.update(payRef, {
            'status': fullRefund ? 'Refunded' : 'HalfRefunded',
            'refundAmount': fullRefund ? payAmount : payAmount / 2,
            'refundPaid': false,
          });
        }
      });
    } catch (_) {
      // Silent — agli load par dobara try hoga
    }
  }

  void _changeDate(int days) {
    setState(() => _selectedDate = _selectedDate.add(Duration(days: days)));
    _loadData();
  }

  void _changeTab(String tab) {
    if (_selectedTab == tab) return;
    setState(() => _selectedTab = tab);
    _loadData();
  }

  bool _isToday(DateTime d) {
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
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

  void _comingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Coming soon'),
      backgroundColor: _primary,
      behavior: SnackBarBehavior.floating,
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
            _buildDateNavigator(),
            _buildTabToggle(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: _primary))
                  : _appointments.isEmpty
                      ? _buildEmpty()
                      : RefreshIndicator(
                          onRefresh: _loadData,
                          color: _primary,
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                            itemCount: _appointments.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (ctx, i) =>
                                _appointmentCard(_appointments[i]),
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
      margin: const EdgeInsets.fromLTRB(18, 16, 18, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_primary, _primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Welcome,',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  _isLoading ? 'Loading...' : _doctorName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                const Text('Your patients today',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Notifications coming soon'),
                backgroundColor: _primary,
                behavior: SnackBarBehavior.floating,
              ));
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.notifications_outlined,
                  color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DoctorProfileScreen(
                    repository: FirebaseDoctorRepository(),
                    doctorId: FirebaseAuth.instance.currentUser?.uid ?? '',
                  ),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_outline,
                  color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateNavigator() {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 16, 18, 0),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () => _changeDate(-1),
            icon: const Icon(Icons.chevron_left, color: _primary),
          ),
          Column(
            children: [
              Text(_isToday(_selectedDate) ? 'Today' : 'Selected',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF1A2F3A))),
              Text(_formatDate(_selectedDate),
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          IconButton(
            onPressed: () => _changeDate(1),
            icon: const Icon(Icons.chevron_right, color: _primary),
          ),
        ],
      ),
    );
  }

  Widget _buildTabToggle() {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 12, 18, 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)
        ],
      ),
      child: Row(
        children: [
          _tabButton('Waiting', 'CheckedIn'),
          _tabButton('Completed', 'Completed'),
        ],
      ),
    );
  }

  Widget _tabButton(String label, String value) {
    final isSelected = _selectedTab == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => _changeTab(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? _primary : Colors.transparent,
            borderRadius: BorderRadius.circular(26),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.grey,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _selectedTab == 'CheckedIn'
                ? Icons.people_outline
                : Icons.check_circle_outline,
            size: 64,
            color: _primary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            _selectedTab == 'CheckedIn'
                ? 'No patients waiting'
                : 'No completed consultations',
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 6),
          Text(
            _selectedTab == 'CheckedIn'
                ? 'Patients appear here after check-in (or when confirmed, for video calls)'
                : 'Completed consultations will appear here',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
          ),
        ],
      ),
    );
  }

  Widget _appointmentCard(Map<String, dynamic> appt) {
    final type = appt['appointmentType'];
    final isVideo = type == 'VIDEO_CALL';
    final isWalkIn = type == 'WALK_IN';

    final Color badgeColor = isVideo
        ? const Color(0xFF1565C0)
        : isWalkIn
            ? const Color(0xFFB8860B)
            : _primary;
    final String typeLabel = isVideo
        ? 'Video'
        : isWalkIn
            ? 'Walk-in'
            : 'In-person';
    final IconData typeIcon = isVideo
        ? Icons.videocam_outlined
        : isWalkIn
            ? Icons.storefront_outlined
            : Icons.local_hospital_outlined;

    return GestureDetector(
      onTap: () async {
        final repository = FirebaseDoctorRepository();
        final doctorId = FirebaseAuth.instance.currentUser?.uid ?? '';

        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AppointmentDetailScreen(
              repository: repository,
              doctorId: doctorId,
              appointment: DoctorAppointmentListItem(
                appointmentId: appt['appointmentId'],
                patientId: appt['patientId'],
                patientName: appt['patientName'],
                slotTime: appt['startTime'],
                status: AppointmentStatus.values.firstWhere(
                  (e) =>
                      e.name.toLowerCase() ==
                      (appt['status'] as String).toLowerCase(),
                  orElse: () => AppointmentStatus.checkedIn,
                ),
                appointmentType: AppointmentTypeX.fromString(
                    appt['appointmentType'] ?? 'IN_PERSON'),
                admissionRecommended: appt['admissionRecommended'] ?? false,
              ),
              dateLabel: _formatDate(_selectedDate),
            ),
          ),
        );

        if (result == true) _loadData();
      },
      child: Container(
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
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFDCEFE9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(appt['startTime'],
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: _primaryDark)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(appt['patientName'],
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A2F3A))),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(typeIcon, size: 13, color: badgeColor),
                      const SizedBox(width: 4),
                      Text(typeLabel,
                          style: TextStyle(fontSize: 12, color: badgeColor)),
                      if (isVideo && appt['status'] == 'InProgress') ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD9534F),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('LIVE',
                              style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
          ],
        ),
      ),
    );
  }
}
