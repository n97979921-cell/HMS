import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'appointment_detail_screen.dart';
import 'appointment_status.dart';
import 'doctor_appointment_list_item.dart';
import 'firebase_doctor_repository.dart';
import 'doctor_profile_screen.dart';
import '../services/notification_service.dart';
import '../widgets/notification_bell_icon.dart';
import 'lab_reports_screen.dart';
import '../widgets/app_ui.dart';

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
///
///  REAL-TIME (Rule 2): Data kai collections (slots + appointments +
/// users) se milkar banta hai, is liye poori screen StreamBuilder mein
/// convert NAHI ki. Iski jagah ek lightweight listener sirf
/// `appointments` collection ko sunta hai (doctorId filter ke saath) —
/// yahin par status-changes (check-in, complete, video start) hote hain.
/// Jab bhi kuch badle, purana `_loadData()` khud-ba-khud dobara call ho
/// jata hai — poora load-logic bilkul waisa hi hai jaisa pehle tha.
class DoctorHomeScreen extends StatefulWidget {
  const DoctorHomeScreen({super.key});

  @override
  State<DoctorHomeScreen> createState() => _DoctorHomeScreenState();
}

class _DoctorHomeScreenState extends State<DoctorHomeScreen> {
  String _doctorName = '';
  bool _isLoading = true;
  int _autoProcessed = 0;

  DateTime _selectedDate = DateTime.now();
  String _selectedTab = 'CheckedIn'; // CheckedIn(=Waiting) | Completed

  List<Map<String, dynamic>> _appointments = [];

  // Real-time listener — sirf `appointments` collection ko sunta hai
  // (doctorId filter ke saath), taake naya check-in, video-start, ya
  // status-change hote hi _loadData() khud-ba-khud dobara chal jaye.
  StreamSubscription<QuerySnapshot>? _appointmentsSub;

  @override
  void initState() {
    super.initState();
    _setupRealtimeListener();
  }

  @override
  void dispose() {
    _appointmentsSub?.cancel();
    super.dispose();
  }

  void _setupRealtimeListener() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _isLoading = false);
      return;
    }

    // Pehla event hi initial load ka kaam kar deta hai, is liye alag
    // se _loadData() call karne ki zaroorat nahi.
    _appointmentsSub = FirebaseFirestore.instance
        .collection('appointments')
        .where('doctorId', isEqualTo: uid)
        .snapshots()
        .listen((_) {
      _loadData();
    }, onError: (_) {
      setState(() => _isLoading = false);
    });
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
          'symptoms': appt['symptoms'],
          'patientReportBase64': appt['patientReportBase64'],
        });
      }

      result.sort((a, b) =>
          (a['startTime'] as String).compareTo(b['startTime'] as String));

      if (!mounted) return;
      setState(() {
        _appointments = result;
        _isLoading = false;
      });

      if (_autoProcessed > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '$_autoProcessed video call(s) auto-processed (no-show/refund)'),
          backgroundColor: const Color(0xFF8A6D00),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (!mounted) return;
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

      // ── NOTIFICATION: Video Missed → Receptionist ──
      final receptionistSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'receptionist')
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();

      if (receptionistSnap.docs.isNotEmpty) {
        await NotificationService.send(
          userId: receptionistSnap.docs.first.id,
          type: 'VideoConsultation',
          referenceId: apptId,
          message: newStatus == 'Cancelled'
              ? 'A video consultation was missed by the doctor.'
              : 'A patient missed their video consultation.',
        );
      }
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
      backgroundColor: const Color(0xFF9A2E16),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.teal))
                : _appointments.isEmpty
                    ? _buildEmpty()
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        color: AppColors.teal,
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                          itemCount: _appointments.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (ctx, i) =>
                              _appointmentCard(_appointments[i]),
                        ),
                      ),
          ),
        ],
      ),

      // BOTTOM NAVIGATION — Home | Lab Reports | Profile
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // Dark header: logo, "Welcome,", name, tagline, bell + date navigator
  // + Waiting/Completed toggle (same actions as before)
  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.header,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            children: [
              Row(
                children: [
                  ClipOval(
                    child: Container(
                      width: 50,
                      height: 50,
                      color: Colors.white,
                      child: Image.asset(
                        'assets/Logo.png',
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(
                            Icons.local_hospital,
                            color: AppColors.header,
                            size: 24,
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Welcome,',
                          style: TextStyle(
                            color: AppColors.headerMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          _isLoading ? 'Loading...' : _doctorName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Text(
                          'Your patients today',
                          style: TextStyle(
                            color: AppColors.headerLabel,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Notification Bell with unread count
                  const NotificationBellIcon(
                    iconColor: Colors.white,
                    backgroundColor: Color(0x26FFFFFF),
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildDateNavigator(),
              const SizedBox(height: 12),
              _buildTabToggle(),
            ],
          ),
        ),
      ),
    );
  }

  // BOTTOM NAVIGATION BAR — same onTap as before, sirf look badla
  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: BottomNavigationBar(
        currentIndex: 0,
        onTap: (index) {
          if (index == 0) {
            // Already on Home
            return;
          } else if (index == 1) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => LabReportsScreen(
                  repository: FirebaseDoctorRepository(),
                  doctorId: FirebaseAuth.instance.currentUser?.uid ?? '',
                ),
              ),
            );
          } else if (index == 2) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DoctorProfileScreen(
                  repository: FirebaseDoctorRepository(),
                  doctorId: FirebaseAuth.instance.currentUser?.uid ?? '',
                ),
              ),
            );
          }
        },
        elevation: 0,
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.header,
        unselectedItemColor: AppColors.faint,
        selectedLabelStyle:
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
        unselectedLabelStyle:
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.science_outlined),
            activeIcon: Icon(Icons.science),
            label: 'Lab Reports',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget _navArrow(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  Widget _buildDateNavigator() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _navArrow(Icons.chevron_left_rounded, () => _changeDate(-1)),
          Expanded(
            child: Column(
              children: [
                Text(
                  _isToday(_selectedDate) ? 'Today' : 'Selected',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
                Text(
                  _formatDate(_selectedDate),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.headerMuted,
                  ),
                ),
              ],
            ),
          ),
          _navArrow(Icons.chevron_right_rounded, () => _changeDate(1)),
        ],
      ),
    );
  }

  Widget _buildTabToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 40,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.mint : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? AppColors.header : Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: AppEmptyState(
        icon: _selectedTab == 'CheckedIn'
            ? Icons.people_outline
            : Icons.check_circle_outline,
        title: _selectedTab == 'CheckedIn'
            ? 'No patients waiting'
            : 'No completed consultations',
        subtitle: _selectedTab == 'CheckedIn'
            ? 'Patients appear here after check-in (or when confirmed, for video calls)'
            : 'Completed consultations will appear here',
      ),
    );
  }

  Widget _appointmentCard(Map<String, dynamic> appt) {
    final type = appt['appointmentType'];
    final isVideo = type == 'VIDEO_CALL';
    final isWalkIn = type == 'WALK_IN';

    final Color badgeColor = isVideo
        ? AppColors.blue
        : isWalkIn
            ? const Color(0xFF8A6D00)
            : AppColors.teal;

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
                  appt['appointmentType'] ?? 'IN_PERSON',
                ),
                admissionRecommended: appt['admissionRecommended'] ?? false,
                symptoms: appt['symptoms'],
                patientReportBase64: appt['patientReportBase64'],
              ),
              dateLabel: _formatDate(_selectedDate),
            ),
          ),
        );

        if (result == true) _loadData();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.tealSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                appt['startTime'],
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0B5E57),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appt['patientName'],
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(typeIcon, size: 14, color: badgeColor),
                      const SizedBox(width: 5),
                      Text(
                        typeLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: badgeColor,
                        ),
                      ),
                      if (isVideo && appt['status'] == 'InProgress') ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.danger,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'LIVE',
                            style: TextStyle(
                              fontSize: 9,
                              letterSpacing: 0.5,
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.faint,
            ),
          ],
        ),
      ),
    );
  }
}
