import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'walk_in_screen.dart';
import 'receptionist_profile_screen.dart';
import '../widgets/app_ui.dart';

/// APPOINTMENTS TODAY — CHECK-IN + LAZY AUTO-CANCEL (Phase 4)
///
/// Receptionist ke liye aaj ki appointments (Confirmed / CheckedIn).
///
/// CHECK-IN (arrival ka single source of truth):
///   Patient reception par aaye → receptionist "Check-in" dabaye
///   → status: CheckedIn + checkedInAt set. Iske baad auto-cancel
///   is appointment ko kabhi nahi chhuega.
///
/// LAZY AUTO-CANCEL (list load hote waqt — Cloud Function nahi, free tier):
///   Har Confirmed (check-in NA hui) appointment par:
///   - NORMAL booking (slot-time se 10+ min pehle book hui thi):
///       agar ab slot-time se 10 min ya kam reh gaye / guzar gaya
///       → status: NoShow | slot: DELETE (kisi aur ko mile)
///       | payment: HalfRefunded (refundPaid:false → Pending Refunds)
///   - EDGE booking (slot-time se 10 min ke andar book hui thi):
///       agar appointment time guzar gaya
///       → status: NoShow | slot: rehne do (waqt guzar chuka, delete
///         ka faida nahi) | payment: HalfRefunded (refundPaid:false)
///
///  REAL-TIME (Rule 2): Data `slots` + `appointments` + `users` se
/// milkar banta hai, is liye poori screen StreamBuilder mein convert
/// NAHI ki. Iski jagah ek lightweight listener `appointments`
/// collection ko sunta hai (status filter: Confirmed/CheckedIn — yehi
/// do states is screen ke liye relevant hain). Naya booking ho, ya
/// koi check-in kare, list khud-ba-khud dobara load ho jaati hai.
class AppointmentsTodayScreen extends StatefulWidget {
  const AppointmentsTodayScreen({super.key});

  @override
  State<AppointmentsTodayScreen> createState() =>
      _AppointmentsTodayScreenState();
}

class _AppointmentsTodayScreenState extends State<AppointmentsTodayScreen> {
  bool _isLoading = true;
  int _autoProcessed = 0; // kitni expired process huin (info ke liye)
  List<Map<String, dynamic>> _appointments = [];

  // Real-time listener — `appointments` collection ko sunta hai
  // (status Confirmed/CheckedIn filter ke saath, kyunke sirf yehi
  // states is screen ke liye relevant hain). Jab bhi kuch badle
  // (naya booking, naya check-in, ya koi appointment in states se
  // bahar nikle), _loadAndProcess() khud-ba-khud dobara chal jaata hai.
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
    // Pehla event hi initial load ka kaam kar deta hai, is liye alag
    // se _loadAndProcess() call karne ki zaroorat nahi.
    _appointmentsSub = FirebaseFirestore.instance
        .collection('appointments')
        .where('status', whereIn: ['Confirmed', 'CheckedIn'])
        .snapshots()
        .listen((_) {
          _loadAndProcess();
        }, onError: (_) {
          setState(() => _isLoading = false);
        });
  }

  String _todayStr() {
    final t = DateTime.now();
    return '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  DateTime? _slotDateTime(String? date, String? startTime) {
    try {
      final d = DateTime.parse(date!);
      final p = startTime!.split(':').map(int.parse).toList();
      return DateTime(d.year, d.month, d.day, p[0], p[1]);
    } catch (_) {
      return null;
    }
  }

  // ── Load: pehle expired process karo (lazy auto-cancel), phir list ──
  Future<void> _loadAndProcess() async {
    setState(() {
      _isLoading = true;
      _autoProcessed = 0;
    });
    try {
      final dateStr = _todayStr();

      // Aaj ke BOOKED slots se appointments nikaalo
      final slotsSnap = await FirebaseFirestore.instance
          .collection('slots')
          .where('date', isEqualTo: dateStr)
          .where('slotStatus', isEqualTo: 'BOOKED')
          .get();

      final List<Map<String, dynamic>> list = [];

      for (final slotDoc in slotsSnap.docs) {
        final slotData = slotDoc.data();
        final apptId = slotData['appointmentId'];
        if (apptId == null) continue;

        final apptDoc = await FirebaseFirestore.instance
            .collection('appointments')
            .doc(apptId)
            .get();
        if (!apptDoc.exists) continue;
        final appt = apptDoc.data()!;
        final status = appt['status'];

        // Sirf Confirmed / CheckedIn dikhani hain
        if (status != 'Confirmed' && status != 'CheckedIn') continue;

        // VIDEO_CALL ke liye receptionist check-in irrelevant hai —
        // schema: video call sirf doctor-triggered flow follow karta
        // hai (Requested → Confirmed → InProgress → Completed),
        // koi CheckedIn step nahi.
        if (appt['appointmentType'] == 'VIDEO_CALL') continue;

        final slotDt = _slotDateTime(slotData['date'], slotData['startTime']);

        // ── LAZY AUTO-CANCEL check (sirf Confirmed, check-in nahi hui) ──
        // VIDEO_CALL ka apna alag missed/no-show handling doctor side
        // aur video-call join screen pe hota hai — yahan skip.
        if (status == 'Confirmed' &&
            slotDt != null &&
            appt['appointmentType'] != 'VIDEO_CALL') {
          final createdAt = appt['createdAt'];
          DateTime? bookedAt;
          if (createdAt is Timestamp) bookedAt = createdAt.toDate();

          final now = DateTime.now();
          final isEdge =
              bookedAt != null && slotDt.difference(bookedAt).inMinutes <= 10;

          bool shouldNoShow = false;
          bool deleteSlot = false;

          if (isEdge) {
            // EDGE: appointment time guzar gaya, check-in nahi
            if (now.isAfter(slotDt)) {
              shouldNoShow = true;
              deleteSlot = false; // waqt guzar chuka — delete ka faida nahi
            }
          } else {
            // NORMAL: 10 min pehle tak check-in nahi
            if (now.isAfter(slotDt.subtract(const Duration(minutes: 10)))) {
              shouldNoShow = true;
              deleteSlot = true; // slot free — kisi aur ko mile
            }
          }

          if (shouldNoShow) {
            await _processNoShow(apptId, slotDoc.id, appt, deleteSlot);
            _autoProcessed++;
            continue; // list mein nahi dikhani — process ho gayi
          }
        }

        // Patient naam
        String patientName = 'Patient';
        try {
          final u = await FirebaseFirestore.instance
              .collection('users')
              .doc(appt['patientId'])
              .get();
          patientName = u.data()?['name'] ?? 'Patient';
        } catch (_) {}

        // Doctor naam
        String doctorName = '';
        try {
          final u = await FirebaseFirestore.instance
              .collection('users')
              .doc(appt['doctorId'])
              .get();
          doctorName = u.data()?['name'] ?? '';
        } catch (_) {}

        list.add({
          'appointmentId': apptId,
          'patientName': patientName,
          'doctorName': doctorName,
          'startTime': slotData['startTime'] ?? '',
          'status': status,
          'appointmentType': appt['appointmentType'] ?? '',
          'sortDt': slotDt,
        });
      }

      // Time ke hisaab se sort
      list.sort((a, b) {
        final ad = a['sortDt'] as DateTime?;
        final bd = b['sortDt'] as DateTime?;
        if (ad == null || bd == null) return 0;
        return ad.compareTo(bd);
      });

      if (!mounted) return;
      setState(() {
        _appointments = list;
        _isLoading = false;
      });

      if (_autoProcessed > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '$_autoProcessed no-show appointment(s) auto-processed (half refund pending)'),
          backgroundColor: const Color(0xFFB8860B),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('Error loading appointments: $e');
    }
  }

  // ── NoShow process: appointment NoShow + payment HalfRefunded
  //    (+ slot delete agar normal case) — transaction, reads pehle ──
  Future<void> _processNoShow(String apptId, String slotId,
      Map<String, dynamic> appt, bool deleteSlot) async {
    try {
      // Payment doc pehle query se dhoondo (transaction me query nahi hoti)
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
      final slotRef =
          FirebaseFirestore.instance.collection('slots').doc(slotId);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        // READS pehle
        final apptSnap = await transaction.get(apptRef);
        if (!apptSnap.exists) return;
        // Double-check: kahin abhi abhi check-in to nahi hui?
        if (apptSnap.data()!['status'] != 'Confirmed') return;
        final slotSnap = await transaction.get(slotRef);

        // WRITES
        transaction.update(apptRef, {
          'status': 'NoShow',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (deleteSlot && slotSnap.exists) {
          transaction.delete(slotRef);
        }
        if (payRef != null) {
          transaction.update(payRef, {
            'status': 'HalfRefunded',
            'refundAmount': payAmount / 2,
            'refundPaid': false,
          });
        }
      });
    } catch (e) {
      // Silent — agli load par dobara try hoga
    }
  }

  // ── CHECK-IN ──
  Future<void> _checkIn(Map<String, dynamic> appt) async {
    try {
      await FirebaseFirestore.instance
          .collection('appointments')
          .doc(appt['appointmentId'])
          .update({
        'status': 'CheckedIn',
        'checkedInAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _showSuccess('${appt['patientName']} checked in');
      _loadAndProcess();
    } catch (e) {
      _showError('Check-in failed: $e');
    }
  }

  void _confirmCancelWalkIn(Map<String, dynamic> appt) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Cancel this walk-in?',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.danger)),
        content: Text('${appt['patientName']} decided not to proceed before '
            'check-in. This will cancel the appointment and process a '
            'FULL refund.'),
        actions: [
          TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.muted),
              onPressed: () => Navigator.pop(context),
              child: const Text('Back')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _cancelWalkIn(appt);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger, elevation: 0),
            child: const Text('Cancel & Refund',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // Patient khud mana karta hai (check-in se PEHLE) — full refund,
  // kyunki yeh patient ki "no-show" galti nahi, khud cancel kiya.
  Future<void> _cancelWalkIn(Map<String, dynamic> appt) async {
    try {
      final apptId = appt['appointmentId'];
      final apptRef =
          FirebaseFirestore.instance.collection('appointments').doc(apptId);

      final apptDoc = await apptRef.get();
      final slotId = apptDoc.data()?['slotId'];

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

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final apptSnap = await transaction.get(apptRef);
        if (!apptSnap.exists) throw Exception('Appointment not found');
        if (apptSnap.data()!['status'] != 'Confirmed') {
          throw Exception('This appointment can no longer be cancelled.');
        }

        DocumentReference? slotRef;
        bool slotExists = false;
        if (slotId != null) {
          slotRef = FirebaseFirestore.instance.collection('slots').doc(slotId);
          final slotSnap = await transaction.get(slotRef);
          slotExists = slotSnap.exists;
        }

        transaction.update(apptRef, {
          'status': 'Cancelled',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (slotRef != null && slotExists) transaction.delete(slotRef);

        if (payRef != null) {
          transaction.update(payRef, {
            'status': 'Refunded',
            'refundAmount': payAmount,
            'refundPaid': false,
          });
        }
      });

      _showSuccess('Walk-in cancelled — full refund pending');
      _loadAndProcess();
    } catch (e) {
      _showError('Error: $e');
    }
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
      backgroundColor: AppColors.teal,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final waiting =
        _appointments.where((a) => a['status'] != 'CheckedIn').length;
    final checked =
        _appointments.where((a) => a['status'] == 'CheckedIn').length;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _buildHeader(waiting, checked),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.teal))
                : _appointments.isEmpty
                    ? _buildEmpty()
                    : RefreshIndicator(
                        onRefresh: _loadAndProcess,
                        color: AppColors.teal,
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
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
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHeader(int waiting, int checked) {
    Widget pill(String label, int n, Color color) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.headerMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                _isLoading ? '—' : '$n',
                style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return AppHeader(
      title: "Today's appointments",
      subtitle: 'In-person & walk-in',
      trailing: AppHeaderIconButton(
        icon: Icons.refresh_rounded,
        tooltip: 'Refresh',
        onTap: _loadAndProcess,
      ),
      bottom: Row(
        children: [
          pill('Waiting', waiting, AppColors.star),
          const SizedBox(width: 8),
          pill('Checked in', checked, AppColors.mint),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        AppEmptyState(
          icon: Icons.event_available_outlined,
          title: 'No appointments for today',
        ),
      ],
    );
  }

  Widget _appointmentCard(Map<String, dynamic> appt) {
    final isCheckedIn = appt['status'] == 'CheckedIn';
    final isWalkIn = appt['appointmentType'] == 'WALK_IN';
    final typeLabel = isWalkIn
        ? 'Walk-in'
        : appt['appointmentType'] == 'VIDEO_CALL'
            ? 'Video'
            : 'In-person';

    final checkInButton = ElevatedButton(
      onPressed: () => _checkIn(appt),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.header,
        elevation: 0,
        minimumSize: const Size.fromHeight(44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: const Text('Check-in',
          style: TextStyle(
              color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
    );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Time chip
              Container(
                width: 60,
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.tealSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(appt['startTime'],
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0B5E57))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(appt['patientName'],
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.text)),
                    const SizedBox(height: 3),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: '${appt['doctorName']} · '),
                          TextSpan(
                            text: typeLabel,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: isWalkIn
                                  ? const Color(0xFF8A5A00)
                                  : AppColors.teal,
                            ),
                          ),
                        ],
                      ),
                      style:
                          const TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              if (isCheckedIn)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDDF3EE),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_rounded,
                          color: Color(0xFF0B5E57), size: 14),
                      SizedBox(width: 4),
                      Text('Checked in',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0B5E57))),
                    ],
                  ),
                ),
            ],
          ),
          // Walk-in: Cancel (full refund) + Check-in — same as before
          if (isWalkIn && !isCheckedIn) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.divider),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _confirmCancelWalkIn(appt),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      side: const BorderSide(color: Color(0xFFF0C9BE)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancel',
                        style: TextStyle(
                            color: Color(0xFF9A2E16),
                            fontSize: 14,
                            fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: checkInButton),
              ],
            ),
          ] else if (!isCheckedIn) ...[
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: checkInButton),
          ],
        ],
      ),
    );
  }

  // Bottom nav — Home / Appointments / Walk-in / Profile.
  // Hum abhi "Appointments" tab par hain, is liye currentIndex: 1.
  // - Home: seedha dashboard tak wapis (popUntil root)
  // - Appointments: already yahan hain, kuch nahi hota
  // - Walk-in: WalkInScreen par switch (pushReplacement)
  // - Profile: ReceptionistProfileScreen push
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
        currentIndex: 1,
        selectedItemColor: AppColors.header,
        unselectedItemColor: AppColors.faint,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          if (index == 1) return; // already on Appointments
          if (index == 0) {
            Navigator.popUntil(context, (route) => route.isFirst);
          } else if (index == 2) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const WalkInScreen()),
            );
          } else if (index == 3) {
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const ReceptionistProfileScreen()),
            );
          }
        },
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home_rounded),
              label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.event_note_outlined),
              activeIcon: Icon(Icons.event_note_rounded),
              label: 'Appointments'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_add_alt_1_outlined),
              activeIcon: Icon(Icons.person_add_alt_1_rounded),
              label: 'Walk-in'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person_rounded),
              label: 'Profile'),
        ],
      ),
    );
  }
}
