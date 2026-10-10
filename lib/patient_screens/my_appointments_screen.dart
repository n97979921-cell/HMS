import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/app_ui.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'appointment_detail_screen.dart';
import '../services/notification_service.dart';
import 'feedback_screen.dart';
import 'patient_profile_screen.dart';

/// FIXES IS FILE MEIN:
/// 1. _cancelAppointment: Firestore rule — transaction mein SAB reads
///    writes se PEHLE hone chahiye. Purana code pehle update phir get
///    karta tha → runtime crash. Ab: dono reads pehle, phir writes.
/// 2. Cancel par slot DELETE hota hai (AVAILABLE mark nahi) —
///    schema decision: Firestore mein sirf HELD/BOOKED slots exist
///    karte hain, free slot ka koi document nahi hota.
/// 3. Card tap → AppointmentDetailScreen kholti hai.
/// 4. NAYA — VIDEO CALL LAZY-CHECK: Patient-side pe bhi wahi check
///    jo Doctor-side (doctor_home_screen.dart) mein hai, taake
///    Doctor ke apni list kholने par depend na rehna pade.
///    Priority: status=='Confirmed' (Doctor never started) → FULL
///    refund, patientJoinedAt irrelevant. status=='InProgress' +
///    patientJoinedAt==null → HALF refund.
/// 5. ✅ REAL-TIME (Rule 2): Data kai collections (appointments +
///    users + doctor_profiles + slots) se milkar banta hai, is liye
///    poori screen StreamBuilder mein convert NAHI ki. Iski jagah ek
///    lightweight listener sirf `appointments` collection ko sunta
///    hai (patientId filter ke saath) aur jab bhi kuch badle, purana
///    `_loadAppointments()` khud-ba-khud dobara call kar deta hai —
///    poora load-logic bilkul waisa hi hai jaisa pehle tha.
/// 6. NAYA — IN_PERSON ARRIVAL REMINDER: upcoming (Requested/Confirmed)
///    in-clinic appointment cards par ek chhota reminder banner —
///    patient ko yaad dilata hai ke 10 min pehle pohanchna hai.
/// 7. NAYA — DELETE: Cancelled appointments, aur Completed appointments
///    jin par feedback de diya ja chuka hai, un cards par ek "Delete"
///    option — permanent delete, koi confirmation dialog nahi (jaisa
///    request kiya gaya). Isse purana, ab bekaar data record se hat
///    jata hai.
/// 8. NAYA — NoShow appointments: inpar bhi individual "Delete" option
///    (Cancelled jaisa hi). Is ke ilawa, jab filter "NoShow" par ho
///    aur list khali na ho, ek "Delete All" button bhi dikhta hai jo
///    is patient ke SAARE NoShow records ek sath permanent delete
///    kar deta hai (batch write) — koi confirmation dialog nahi.
class MyAppointmentsScreen extends StatefulWidget {
  const MyAppointmentsScreen({super.key});

  @override
  State<MyAppointmentsScreen> createState() => _MyAppointmentsScreenState();
}

class _MyAppointmentsScreenState extends State<MyAppointmentsScreen> {
  final int _currentNavIndex = 1;
  String _selectedFilter = 'All';

  final List<String> _filters = [
    'All',
    'Requested',
    'Confirmed',
    'Completed',
    'Cancelled',
    'NoShow',
  ];

  bool _isLoading = true;
  int _autoProcessed = 0;
  List<Map<String, dynamic>> _appointments = [];

  // Real-time listener — sirf `appointments` collection ko sunta hai,
  // taake jab bhi kuch badle (naya appointment, status change, waghera)
  // to _loadAppointments() khud-ba-khud dobara chal jaye.
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

    // Is listener ka pehla event hi initial load ka kaam kar deta hai,
    // is liye alag se _loadAppointments() call karne ki zaroorat nahi.
    _appointmentsSub = FirebaseFirestore.instance
        .collection('appointments')
        .where('patientId', isEqualTo: uid)
        .snapshots()
        .listen((_) {
      _loadAppointments();
    }, onError: (_) {
      // Agar listener error de (jaise offline), purana data hi dikhta rahe.
      setState(() => _isLoading = false);
    });
  }

  Future<void> _loadAppointments() async {
    setState(() {
      _isLoading = true;
      _autoProcessed = 0;
    });
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

        // ── VIDEO CALL LAZY-CHECK (Patient-side) ──
        // Doctor-side (doctor_home_screen.dart) mein bhi yehi check
        // hai — jo bhi pehle list khole (Doctor ya Patient), wahi
        // trigger karega. Reliability ke liye dono jagah zaroori.
        if (data['appointmentType'] == 'VIDEO_CALL') {
          final slotId = data['slotId'];
          if (slotId != null) {
            final slotDoc = await FirebaseFirestore.instance
                .collection('slots')
                .doc(slotId)
                .get();
            if (slotDoc.exists) {
              final slotData = slotDoc.data()!;
              final slotDt =
                  _parseSlotDateTime(slotData['date'], slotData['startTime']);
              if (slotDt != null) {
                final now = DateTime.now();
                final fiveMinPast =
                    now.isAfter(slotDt.add(const Duration(minutes: 5)));
                final status = data['status'];

                if (fiveMinPast) {
                  if (status == 'Confirmed') {
                    // Priority 1: Doctor never started (regardless
                    // of patientJoinedAt) — full refund.
                    await _autoProcessVideo(doc.id, 'Cancelled',
                        fullRefund: true);
                    _autoProcessed++;
                    continue; // agli load pe naya status dikhega
                  } else if (status == 'InProgress' &&
                      data['patientJoinedAt'] == null) {
                    // Priority 2: Doctor started, patient never
                    // joined — half refund.
                    await _autoProcessVideo(doc.id, 'NoShow',
                        fullRefund: false);
                    _autoProcessed++;
                    continue;
                  }
                }
              }
            }
          }
        }

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

        bool hasFeedback = false;
        if (data['status'] == 'Completed') {
          final feedbackDoc = await FirebaseFirestore.instance
              .collection('feedback')
              .doc(doc.id)
              .get();
          hasFeedback = feedbackDoc.exists;
        }

        result.add({
          'appointmentId': doc.id,
          'doctorId': data['doctorId'],
          'doctorName': doctorDoc.data()?['name'] ?? 'Doctor',
          'specialization': profileDoc.exists
              ? (profileDoc.data()?['specialization'] ?? '')
              : '',
          'dateLabel': dateLabel,
          'sortDate': sortDate,
          'appointmentType': data['appointmentType'] ?? '',
          'status': data['status'] ?? '',
          'consultationFee': data['consultationFee'] ?? 0,
          'hasFeedback': hasFeedback,
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

  // Video call timeout — appointment status badlo + payment refund set
  // karo. Transaction: reads pehle, writes baad. Double-check status
  // abhi bhi wahi hai (kahin isi beech doctor/patient ne action na
  // li ho).
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
      backgroundColor: const Color(0xFF9A2E16),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.teal,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── Cancel: appointment Cancelled + slot DELETED, atomically ──
  Future<void> _cancelAppointment(Map<String, dynamic> appt) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Cancel appointment?'),
        content: const Text(
            'This will cancel your appointment and free up the slot.'),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.muted),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB23A1E), elevation: 0),
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
      // Real-time listener khud-ba-khud _loadAppointments() call kar
      // dega jab Firestore mein change reflect hoga — manual call ki
      // zaroorat nahi, lekin turant feel dene ke liye yahan bhi rakh
      // sakte hain, koi nuqsan nahi.
      _loadAppointments();
    } catch (e) {
      _showError('Error cancelling: $e');
    }
  }

  // ── Delete: sirf Cancelled, NoShow, ya (Completed + feedback diya ja
  //    chuka) appointments ke liye. Bina confirmation ke, seedha permanent
  //    delete — jaisa request kiya gaya. Appointment document Firestore
  //    se hamesha ke liye hat jata hai, is se data halka ho jata hai.
  Future<void> _deleteAppointment(Map<String, dynamic> appt) async {
    try {
      await FirebaseFirestore.instance
          .collection('appointments')
          .doc(appt['appointmentId'])
          .delete();
      _showSuccess('Appointment deleted');
      _loadAppointments();
    } catch (e) {
      _showError('Error deleting: $e');
    }
  }

  // ── Delete All — is patient ke SAARE NoShow appointments ek batch
  //    write mein, bina confirmation ke. Sirf "NoShow" filter tab par
  //    dikhta hai.
  Future<void> _deleteAllNoShow() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final snap = await FirebaseFirestore.instance
          .collection('appointments')
          .where('patientId', isEqualTo: uid)
          .where('status', isEqualTo: 'NoShow')
          .get();

      if (snap.docs.isEmpty) return;

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      _showSuccess('${snap.docs.length} no-show record(s) deleted');
      _loadAppointments();
    } catch (e) {
      _showError('Error deleting all: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _buildHeader(),
          if (_selectedFilter == 'NoShow' &&
              !_isLoading &&
              _filteredAppointments.isNotEmpty)
            _buildDeleteAllBar(),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.teal))
                : _filteredAppointments.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadAppointments,
                        color: AppColors.teal,
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(
                              20, _selectedFilter == 'NoShow' ? 4 : 16, 20, 24),
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
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  List<Map<String, dynamic>> get _filteredAppointments {
    if (_selectedFilter == 'All') return _appointments;
    return _appointments.where((a) => a['status'] == _selectedFilter).toList();
  }

  Widget _buildHeader() {
    return AppHeader(
      title: 'My Appointments',
      subtitle: _isLoading ? null : '${_appointments.length} appointments',
      bottom: _buildFilterTabs(),
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
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.mint
                    : Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(999),
                border: isSelected
                    ? null
                    : Border.all(color: Colors.white.withOpacity(0.16)),
              ),
              alignment: Alignment.center,
              child: Text(
                filter,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: isSelected ? AppColors.header : Colors.white,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // "Delete All" — sirf NoShow filter par, bina confirmation (pehle jaisa)
  Widget _buildDeleteAllBar() {
    final n = _filteredAppointments.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$n no-show record${n == 1 ? '' : 's'}',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.muted),
            ),
          ),
          GestureDetector(
            onTap: _deleteAllNoShow,
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.dangerSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete_sweep_outlined,
                      size: 16, color: AppColors.danger),
                  SizedBox(width: 6),
                  Text('Delete All',
                      style: TextStyle(
                          color: AppColors.danger,
                          fontSize: 12,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: AppEmptyState(
        icon: Icons.calendar_today_outlined,
        title: 'No appointments found',
      ),
    );
  }

  Widget _appointmentCard(Map<String, dynamic> appt) {
    final statusColors = _statusColor(appt['status']);
    final canCancel =
        appt['status'] == 'Requested' || appt['status'] == 'Confirmed';
    final isCompleted = appt['status'] == 'Completed';
    final isCancelled = appt['status'] == 'Cancelled';
    final isNoShow = appt['status'] == 'NoShow';
    final isCheckedIn = appt['status'] == 'CheckedIn';
    // Delete: Cancelled, NoShow, CheckedIn, ya Completed + feedback diya
    final canDelete = isCancelled ||
        isNoShow ||
        isCheckedIn ||
        (isCompleted && appt['hasFeedback'] == true);
    final canGiveFeedback = isCompleted && appt['hasFeedback'] != true;
    final showArrivalReminder =
        appt['appointmentType'] == 'IN_PERSON' && canCancel;
    final isVideo = appt['appointmentType'] == 'VIDEO_CALL';

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
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color:
                        isVideo ? AppColors.tealSoft : const Color(0xFFEEE8FB),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isVideo
                        ? Icons.videocam_outlined
                        : Icons.local_hospital_outlined,
                    size: 21,
                    color: isVideo ? AppColors.teal : const Color(0xFF5B3FA8),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(appt['doctorName'],
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.text)),
                      const SizedBox(height: 2),
                      Text(appt['specialization'],
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.muted)),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          const Icon(Icons.access_time_rounded,
                              size: 13, color: AppColors.text),
                          const SizedBox(width: 4),
                          Text(
                            appt['dateLabel'].isEmpty
                                ? 'Date unavailable'
                                : appt['dateLabel'],
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.text),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AppStatusChip(
                  label: appt['status'],
                  colors:
                      AppChipColors(statusColors['text']!, statusColors['bg']!),
                ),
              ],
            ),
            if (showArrivalReminder) ...[
              const SizedBox(height: 12),
              _buildArrivalReminder(),
            ],
            if (isCompleted && appt['hasFeedback'] == true) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.tealSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.star_rounded, size: 16, color: AppColors.teal),
                    SizedBox(width: 6),
                    Text('Feedback submitted',
                        style: TextStyle(
                            color: Color(0xFF0B5E57),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ],
            if (canCancel || canGiveFeedback || canDelete) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (canCancel)
                    Expanded(
                      child: _cardAction(
                        icon: Icons.close_rounded,
                        label: 'Cancel',
                        fg: const Color(0xFF9A2E16),
                        bg: Colors.white,
                        border: const Color(0xFFF0C9BE),
                        onTap: () => _cancelAppointment(appt),
                      ),
                    ),
                  if (canGiveFeedback)
                    Expanded(
                      child: _cardAction(
                        icon: Icons.star_outline_rounded,
                        iconColor: AppColors.mint,
                        label: 'Give Feedback',
                        fg: Colors.white,
                        bg: AppColors.header,
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FeedbackScreen(
                                appointmentId: appt['appointmentId'],
                                doctorId: appt['doctorId'] ?? '',
                                doctorName: appt['doctorName'],
                                specialization: appt['specialization'],
                              ),
                            ),
                          );
                          _loadAppointments(); // refresh to show "submitted"
                        },
                      ),
                    ),
                  if (canDelete)
                    Expanded(
                      child: _cardAction(
                        icon: Icons.delete_outline_rounded,
                        label: 'Delete',
                        fg: AppColors.danger,
                        bg: AppColors.dangerSoft,
                        onTap: () => _deleteAppointment(appt),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _cardAction({
    required IconData icon,
    required String label,
    required Color fg,
    required Color bg,
    Color? border,
    Color? iconColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: border != null ? Border.all(color: border) : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: iconColor ?? fg),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: fg, fontSize: 13, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }

  // Sirf upcoming IN_PERSON cards par — informational only.
  Widget _buildArrivalReminder() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F2E2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.access_time_rounded, color: Color(0xFF8A6D00), size: 15),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Please arrive 10 minutes early, or your appointment may be cancelled.',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF6B5500),
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Map<String, Color> _statusColor(String status) {
    switch (status) {
      case 'Confirmed':
        return {'bg': const Color(0xFFDDF3EE), 'text': const Color(0xFF0B5E57)};
      case 'Completed':
        return {'bg': AppColors.blueSoft, 'text': AppColors.blue};
      case 'Requested':
        return {'bg': const Color(0xFFF6F2E2), 'text': const Color(0xFF8A6D00)};
      case 'Cancelled':
        return {'bg': const Color(0xFFFBE6E0), 'text': const Color(0xFF9A2E16)};
      case 'InProgress':
        return {'bg': const Color(0xFFEEE8FB), 'text': const Color(0xFF5B3FA8)};
      case 'NoShow':
        return {'bg': const Color(0xFFEEF1F1), 'text': AppColors.muted};
      default:
        return {'bg': const Color(0xFFEEF1F1), 'text': AppColors.muted};
    }
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: BottomNavigationBar(
        elevation: 0,
        backgroundColor: Colors.white,
        selectedLabelStyle:
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
        unselectedLabelStyle:
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        currentIndex: _currentNavIndex,
        onTap: (index) {
          if (index == 0) {
            Navigator.pop(context); // Home pehle se stack mein hai
          } else if (index == 2) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PatientProfileScreen()),
            );
          }
          // index == 1 → already yahin hain, kuch mat karo
        },
        selectedItemColor: AppColors.header,
        unselectedItemColor: AppColors.faint,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home_rounded),
              label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.calendar_today_outlined),
              activeIcon: Icon(Icons.calendar_today_rounded),
              label: 'My appointments'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person_rounded),
              label: 'Profile'),
        ],
      ),
    );
  }
}
