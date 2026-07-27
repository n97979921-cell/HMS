import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'appointment_detail_screen.dart';

/// FIXES IS FILE MEIN:
/// 1. _cancelAppointment: Firestore rule — transaction mein SAB reads
///    writes se PEHLE hone chahiye. Purana code pehle update phir get
///    karta tha → runtime crash. Ab: dono reads pehle, phir writes.
/// 2. Cancel par slot DELETE hota hai (AVAILABLE mark nahi) —
///    schema decision: Firestore mein sirf HELD/BOOKED slots exist
///    karte hain, free slot ka koi document nahi hota.
/// 3. Card tap → AppointmentDetailScreen kholti hai.
class MyAppointmentsScreen extends StatefulWidget {
  const MyAppointmentsScreen({super.key});

  @override
  State<MyAppointmentsScreen> createState() => _MyAppointmentsScreenState();
}

class _MyAppointmentsScreenState extends State<MyAppointmentsScreen> {
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _primaryDark = Color(0xFF0D6B5A);

  final int _currentNavIndex = 1;
  String _selectedFilter = 'All';

  final List<String> _filters = [
    'All',
    'Requested',
    'Confirmed',
    'Completed',
    'Cancelled',
  ];

  bool _isLoading = true;
  List<Map<String, dynamic>> _appointments = [];

  @override
  void initState() {
    super.initState();
    _loadAppointments();
  }

  Future<void> _loadAppointments() async {
    setState(() => _isLoading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        setState(() => _isLoading = false);
        return;
      }

      final apptSnap = await FirebaseFirestore.instance
          .collection('appointments')
          .where('patientId', isEqualTo: uid)
          .get();

      final List<Map<String, dynamic>> result = [];

      for (final doc in apptSnap.docs) {
        final data = doc.data();

        final doctorDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(data['doctorId'])
            .get();

        final profileDoc = await FirebaseFirestore.instance
            .collection('doctor_profiles')
            .doc(data['doctorId'])
            .get();

        String dateLabel = '';
        DateTime? sortDate;
        final slotId = data['slotId'];
        if (slotId != null) {
          final slotDoc = await FirebaseFirestore.instance
              .collection('slots')
              .doc(slotId)
              .get();
          if (slotDoc.exists) {
            final slotData = slotDoc.data()!;
            final parsed =
                _parseSlotDateTime(slotData['date'], slotData['startTime']);
            if (parsed != null) {
              sortDate = parsed;
              dateLabel = _formatDate(parsed);
            }
          }
        }

        result.add({
          'appointmentId': doc.id,
          'doctorName': doctorDoc.data()?['name'] ?? 'Doctor',
          'specialization': profileDoc.exists
              ? (profileDoc.data()?['specialization'] ?? '')
              : '',
          'dateLabel': dateLabel,
          'sortDate': sortDate,
          'appointmentType': data['appointmentType'] ?? '',
          'status': data['status'] ?? '',
          'consultationFee': data['consultationFee'] ?? 0,
        });
      }

      result.sort((a, b) {
        final aDate = a['sortDate'] as DateTime?;
        final bDate = b['sortDate'] as DateTime?;
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });

      setState(() {
        _appointments = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Error loading appointments: $e');
    }
  }

  DateTime? _parseSlotDateTime(dynamic dateStr, dynamic startTime) {
    try {
      final date = DateTime.parse(dateStr as String);
      final timeParts = (startTime as String).split(':');
      return DateTime(date.year, date.month, date.day, int.parse(timeParts[0]),
          int.parse(timeParts[1]));
    } catch (e) {
      return null;
    }
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final apptDay = DateTime(dt.year, dt.month, dt.day);
    final timeLabel = DateFormat('h:mm a').format(dt);

    if (apptDay == today) return 'Today, $timeLabel';
    if (apptDay == today.add(const Duration(days: 1))) {
      return 'Tomorrow, $timeLabel';
    }
    return '${DateFormat('d MMM').format(dt)}, $timeLabel';
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

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: _primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── Cancel: appointment Cancelled + slot DELETED, atomically ──
  Future<void> _cancelAppointment(Map<String, dynamic> appt) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel appointment?'),
        content: const Text(
            'This will cancel your appointment and free up the slot.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Yes, cancel',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final apptRef = FirebaseFirestore.instance
          .collection('appointments')
          .doc(appt['appointmentId']);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        // ── STEP 1: SAB READS PEHLE (Firestore transaction rule) ──
        final apptSnap = await transaction.get(apptRef);
        if (!apptSnap.exists) throw Exception('Appointment not found');

        final apptData = apptSnap.data()!;
        final status = apptData['status'];
        if (status != 'Requested' && status != 'Confirmed') {
          throw Exception('This appointment can no longer be cancelled');
        }

        final slotId = apptData['slotId'];
        DocumentReference? slotRef;
        bool slotExists = false;
        if (slotId != null) {
          slotRef = FirebaseFirestore.instance.collection('slots').doc(slotId);
          final slotSnap = await transaction.get(slotRef);
          slotExists = slotSnap.exists;
        }

        // ── STEP 2: AB WRITES ──
        transaction.update(apptRef, {
          'status': 'Cancelled',
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Schema decision: free slot ka document exist nahi karta —
        // is liye DELETE, "AVAILABLE" mark nahi.
        if (slotRef != null && slotExists) {
          transaction.delete(slotRef);
        }
      });

      _showSuccess('Appointment cancelled');
      _loadAppointments();
    } catch (e) {
      _showError('Error cancelling: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: _buildFilterTabs(),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: _primary))
                  : _filteredAppointments.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: _loadAppointments,
                          color: _primary,
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(18, 0, 18, 80),
                            itemCount: _filteredAppointments.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (ctx, i) =>
                                _appointmentCard(_filteredAppointments[i]),
                          ),
                        ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  List<Map<String, dynamic>> get _filteredAppointments {
    if (_selectedFilter == 'All') return _appointments;
    return _appointments.where((a) => a['status'] == _selectedFilter).toList();
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
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.arrow_back, color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'My Appointments',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTabs() {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final filter = _filters[i];
          final isSelected = filter == _selectedFilter;
          return GestureDetector(
            onTap: () => setState(() => _selectedFilter = filter),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? _primary : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2))
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                filter,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : const Color(0xFF1A2F3A),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.calendar_today_outlined,
              size: 64, color: _primary.withOpacity(0.3)),
          const SizedBox(height: 16),
          const Text(
            'No appointments found',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }

  Widget _appointmentCard(Map<String, dynamic> appt) {
    final statusColors = _statusColor(appt['status']);
    final canCancel =
        appt['status'] == 'Requested' || appt['status'] == 'Confirmed';

    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                AppointmentDetailScreen(appointmentId: appt['appointmentId']),
          ),
        );
        _loadAppointments(); // refresh after returning
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: _primary.withOpacity(0.15),
                  child: const Icon(Icons.person, color: _primary, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(appt['doctorName'],
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A2F3A))),
                      const SizedBox(height: 2),
                      Text(appt['specialization'],
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.access_time,
                              size: 13, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            appt['dateLabel'].isEmpty
                                ? 'Date unavailable'
                                : appt['dateLabel'],
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColors['bg'],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    appt['status'],
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: statusColors['text'],
                    ),
                  ),
                ),
              ],
            ),
            if (canCancel) ...[
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _cancelAppointment(appt),
                  icon: const Icon(Icons.close, size: 16, color: Colors.red),
                  label: const Text('Cancel',
                      style: TextStyle(color: Colors.red, fontSize: 12)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Map<String, Color> _statusColor(String status) {
    switch (status) {
      case 'Confirmed':
        return {'bg': const Color(0xFFDCEFE9), 'text': const Color(0xFF1F8A70)};
      case 'Completed':
        return {'bg': const Color(0xFFD9ECF8), 'text': const Color(0xFF1565C0)};
      case 'Requested':
        return {'bg': const Color(0xFFFCEFD8), 'text': const Color(0xFFB8860B)};
      case 'Cancelled':
        return {'bg': const Color(0xFFFDE6E0), 'text': const Color(0xFFD9534F)};
      case 'InProgress':
        return {'bg': const Color(0xFFEAE3F7), 'text': const Color(0xFF7E57C2)};
      case 'NoShow':
        return {'bg': Colors.grey.withOpacity(0.15), 'text': Colors.grey};
      default:
        return {'bg': Colors.grey.withOpacity(0.15), 'text': Colors.grey};
    }
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _currentNavIndex,
      onTap: (index) {
        if (index != 1) Navigator.pop(context);
      },
      backgroundColor: Colors.white,
      selectedItemColor: _primary,
      unselectedItemColor: Colors.grey,
      type: BottomNavigationBarType.fixed,
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
        BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today_outlined),
            label: 'My appointments'),
        BottomNavigationBarItem(
            icon: Icon(Icons.person_outline), label: 'Profile'),
      ],
    );
  }
}
