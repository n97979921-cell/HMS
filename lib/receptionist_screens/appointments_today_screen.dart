import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
class AppointmentsTodayScreen extends StatefulWidget {
  const AppointmentsTodayScreen({super.key});

  @override
  State<AppointmentsTodayScreen> createState() =>
      _AppointmentsTodayScreenState();
}

class _AppointmentsTodayScreenState extends State<AppointmentsTodayScreen> {
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _primaryDark = Color(0xFF0D6B5A);

  bool _isLoading = true;
  int _autoProcessed = 0; // kitni expired process huin (info ke liye)
  List<Map<String, dynamic>> _appointments = [];

  @override
  void initState() {
    super.initState();
    _loadAndProcess();
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

        final slotDt = _slotDateTime(slotData['date'], slotData['startTime']);

        // ── LAZY AUTO-CANCEL check (sirf Confirmed, check-in nahi hui) ──
        if (status == 'Confirmed' && slotDt != null) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: _primary))
                  : _appointments.isEmpty
                      ? _buildEmpty()
                      : RefreshIndicator(
                          onRefresh: _loadAndProcess,
                          color: _primary,
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
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
      color: _primaryDark,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.arrow_back, color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text("Today's Appointments",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
          ),
          GestureDetector(
            onTap: _loadAndProcess,
            child: const Icon(Icons.refresh, color: Colors.white, size: 22),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_available_outlined,
              size: 64, color: _primary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          const Text('No appointments for today',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280))),
        ],
      ),
    );
  }

  Widget _appointmentCard(Map<String, dynamic> appt) {
    final isCheckedIn = appt['status'] == 'CheckedIn';
    final typeLabel = appt['appointmentType'] == 'WALK_IN'
        ? 'Walk-in'
        : appt['appointmentType'] == 'VIDEO_CALL'
            ? 'Video'
            : 'In-person';

    return Container(
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
                Text('${appt['doctorName']} · $typeLabel',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
          isCheckedIn
              ? Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCEFE9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle, color: _primary, size: 14),
                      SizedBox(width: 4),
                      Text('Checked in',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _primary)),
                    ],
                  ),
                )
              : ElevatedButton(
                  onPressed: () => _checkIn(appt),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Check-in',
                      style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
        ],
      ),
    );
  }
}
