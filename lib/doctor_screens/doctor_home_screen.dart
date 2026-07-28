import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../doctor_screens/appointment_detail_screen.dart';
import '../doctor_screens/doctor_repository.dart';
import '../doctor_screens/firebase_doctor_repository.dart';
import '../doctor_screens/doctor_appointment_list_item.dart';
import '../doctor_screens/appointment_status.dart';

/// DOCTOR HOME — aaj ke patients
///
/// SCHEMA RULES:
///  - Doctor ko sirf CHECKED-IN patients dikhte hain (arrival = receptionist
///    check-in). Confirmed = paisa aaya lekin patient aaya ya nahi, pata nahi.
///  - Doctor "Completed" mark karta hai (in-person, walk-in, video — teeno).
///  - Tabs: Waiting (CheckedIn) | Completed
///
/// PATTERN: seedha Firestore (koi repository/model class nahi) — baaki
/// project (patient/receptionist/admin) jaisa hi.
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

  DateTime _selectedDate = DateTime.now();
  String _selectedTab = 'CheckedIn'; // CheckedIn | Completed

  List<Map<String, dynamic>> _appointments = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  String _dateStr(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      // Doctor ka naam
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      _doctorName = userDoc.data()?['name'] ?? 'Doctor';

      // Us din ke BOOKED slots (receptionist pattern jaisa)
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

        // Tab filter: Waiting = CheckedIn (arrival hui) YA
        // VIDEO_CALL+Confirmed (video mein "aana" nahi hota, is liye
        // Confirmed hi "waiting" maana jata hai) | Completed = Completed
        final status = appt['status'];
        final type = appt['appointmentType'];
        final isWaiting = status == 'CheckedIn' ||
            (type == 'VIDEO_CALL' && status == 'Confirmed');

        if (_selectedTab == 'CheckedIn' && !isWaiting) continue;
        if (_selectedTab == 'Completed' && status != 'Completed') continue;

        // Patient naam
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
          'appointmentType': appt['appointmentType'] ?? 'IN_PERSON',
          'status': appt['status'],
          'symptoms': appt['symptoms'],
        });
      }

      // Time ke hisaab se sort
      result.sort((a, b) =>
          (a['startTime'] as String).compareTo(b['startTime'] as String));

      setState(() {
        _appointments = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Error loading appointments: $e');
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
          // Bell (abhi coming soon)
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
          // Profile (screen ban jaye to yahan lagayenge)
          GestureDetector(
            onTap: _comingSoon,
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
                ? 'Patients appear here after reception check-in'
                : 'Completed consultations will appear here',
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
                admissionRecommended: false,
              ),
              dateLabel: _formatDate(_selectedDate),
            ),
          ),
        );

        // Detail screen se wapas aaye to list refresh karo
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
            // Time chip
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
