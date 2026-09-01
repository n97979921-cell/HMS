import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'assign_bed_screen.dart';
import '../services/notification_service.dart';

/// ADMISSIONS (Receptionist) — Pending | Occupied tabs
///
/// Ek hi screen, doctor_home_screen jaisa tab-toggle pattern:
///   PENDING  = admissionRecommended:true + Completed appointments
///              jinke liye abhi koi bed assign nahi
///   OCCUPIED = currently admitted patients (beds.availability=='Occupied')
///              + Release/discharge action
///
/// Release: round-to-nearest hour billing (min 1hr), "cash received?"
/// confirm, phir ATOMIC transaction (bed free + payment Paid — dono
/// ya koi nahi, "no release without payment").
class AdmissionsScreen extends StatefulWidget {
  const AdmissionsScreen({super.key});

  @override
  State<AdmissionsScreen> createState() => _AdmissionsScreenState();
}

class _AdmissionsScreenState extends State<AdmissionsScreen> {
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _primaryDark = Color(0xFF0D6B5A);

  String _selectedTab = 'Pending'; // Pending | Occupied
  bool _isLoading = true;
  String? _processingId;

  List<Map<String, dynamic>> _pending = [];
  List<Map<String, dynamic>> _occupied = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      await Future.wait([_loadPending(), _loadOccupied()]);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── PENDING: recommended + completed, no bed assigned yet ──
  Future<void> _loadPending() async {
    final apptSnap = await FirebaseFirestore.instance
        .collection('appointments')
        .where('admissionRecommended', isEqualTo: true)
        .where('status', isEqualTo: 'Completed')
        .get();

    final List<Map<String, dynamic>> result = [];

    for (final doc in apptSnap.docs) {
      final appt = doc.data();
      final apptId = doc.id;

      final occupiedBedSnap = await FirebaseFirestore.instance
          .collection('beds')
          .where('appointmentId', isEqualTo: apptId)
          .where('availability', isEqualTo: 'Occupied')
          .limit(1)
          .get();
      if (occupiedBedSnap.docs.isNotEmpty) continue; // already admitted

      final roomPaymentSnap = await FirebaseFirestore.instance
          .collection('payments')
          .where('appointmentId', isEqualTo: apptId)
          .where('type', isEqualTo: 'Room')
          .where('status', isEqualTo: 'Paid')
          .limit(1)
          .get();
      if (roomPaymentSnap.docs.isNotEmpty) continue; // already discharged

      String patientName = 'Patient';
      String doctorName = 'Doctor';
      try {
        final p = await FirebaseFirestore.instance
            .collection('users')
            .doc(appt['patientId'])
            .get();
        patientName = p.data()?['name'] ?? 'Patient';
        final d = await FirebaseFirestore.instance
            .collection('users')
            .doc(appt['doctorId'])
            .get();
        doctorName = d.data()?['name'] ?? 'Doctor';
      } catch (_) {}

      result.add({
        'appointmentId': apptId,
        'patientId': appt['patientId'],
        'patientName': patientName,
        'doctorName': doctorName,
      });
    }
    _pending = result;
  }

  // ── OCCUPIED: currently admitted ──
  Future<void> _loadOccupied() async {
    final bedsSnap = await FirebaseFirestore.instance
        .collection('beds')
        .where('availability', isEqualTo: 'Occupied')
        .get();

    final List<Map<String, dynamic>> result = [];

    for (final doc in bedsSnap.docs) {
      final bed = doc.data();
      final appointmentId = bed['appointmentId'];

      String patientName = 'Patient';
      String roomNumber = '';
      String roomType = '';

      if (appointmentId != null) {
        try {
          final apptDoc = await FirebaseFirestore.instance
              .collection('appointments')
              .doc(appointmentId)
              .get();
          final patientId = apptDoc.data()?['patientId'];
          if (patientId != null) {
            final p = await FirebaseFirestore.instance
                .collection('users')
                .doc(patientId)
                .get();
            patientName = p.data()?['name'] ?? 'Patient';
          }
        } catch (_) {}
      }

      try {
        final roomDoc = await FirebaseFirestore.instance
            .collection('rooms')
            .doc(bed['roomId'])
            .get();
        roomNumber = roomDoc.data()?['roomNumber'] ?? '';
        roomType = roomDoc.data()?['roomType'] ?? '';
      } catch (_) {}

      final assignedAt = bed['assignedAt'];
      DateTime? assignedDt;
      if (assignedAt is Timestamp) assignedDt = assignedAt.toDate();

      result.add({
        'bedId': doc.id,
        'appointmentId': appointmentId,
        'patientName': patientName,
        'roomNumber': roomNumber,
        'roomType': roomType,
        'pricePerHour': bed['pricePerHour'] ?? 0,
        'assignedAt': assignedDt,
      });
    }
    _occupied = result;
  }

  // Round-to-nearest hour billing, minimum 1 hour
  int _calculateHours(DateTime assignedAt) {
    final totalMinutes = DateTime.now().difference(assignedAt).inMinutes;
    int hours = (totalMinutes / 60).round();
    if (hours <= 0) hours = 1;
    return hours;
  }

  String _durationLabel(DateTime assignedAt) {
    final d = DateTime.now().difference(assignedAt);
    return '${d.inHours}h ${d.inMinutes % 60}m';
  }

  Future<void> _releaseBed(Map<String, dynamic> bed) async {
    final DateTime? assignedAt = bed['assignedAt'];
    if (assignedAt == null) {
      _showError('Missing assignment time — cannot calculate charge.');
      return;
    }

    final hours = _calculateHours(assignedAt);
    final amount = hours * (bed['pricePerHour'] as num);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Release bed'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Patient: ${bed['patientName']}'),
            Text(
                'Room ${bed['roomNumber']} · Bed ${bed['bedNumber']} (${bed['roomType']})'),
            const SizedBox(height: 8),
            Text('Duration: ${_durationLabel(assignedAt)}'),
            Text('Billed hours: $hours (rounded to nearest hour)'),
            const SizedBox(height: 8),
            Text('Total: Rs. $amount',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            const Text('Confirm cash received before releasing.',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: _primary),
            child: const Text('Cash received — Release',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _processingId = bed['bedId']);
    try {
      final bedRef =
          FirebaseFirestore.instance.collection('beds').doc(bed['bedId']);
      final paymentRef =
          FirebaseFirestore.instance.collection('payments').doc();
      final uid = FirebaseAuth.instance.currentUser?.uid;

      String? patientId;
      if (bed['appointmentId'] != null) {
        final apptDoc = await FirebaseFirestore.instance
            .collection('appointments')
            .doc(bed['appointmentId'])
            .get();
        patientId = apptDoc.data()?['patientId'];
      }

      // Release se PEHLE — current room_type_prices se fresh rate lo
      // (billing purani/locked price se hi hogi, yeh sirf bed ki
      // display-price ko naye rate pe REFRESH karta hai taake agla
      // patient sahi rate dekhe).
      num freshRate = bed['pricePerHour']; // fallback: purani price hi
      try {
        final priceDoc = await FirebaseFirestore.instance
            .collection('room_type_prices')
            .doc(bed['roomType'])
            .get();
        if (priceDoc.exists && priceDoc.data()?['pricePerHour'] != null) {
          freshRate = priceDoc.data()!['pricePerHour'];
        }
      } catch (_) {
        // fetch fail ho to purani price hi rakho, release na roko
      }

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final bedSnap = await transaction.get(bedRef);
        if (!bedSnap.exists) throw Exception('Bed not found');
        if (bedSnap.data()?['availability'] != 'Occupied') {
          throw Exception('This bed is no longer occupied.');
        }

        transaction.update(bedRef, {
          'availability': 'Available',
          'releasedAt': FieldValue.serverTimestamp(),
          'appointmentId': null,
          'pricePerHour': freshRate, // naye rate pe refresh
          'updatedAt': FieldValue.serverTimestamp(),
        });

        transaction.set(paymentRef, {
          'paymentId': paymentRef.id,
          'appointmentId': bed['appointmentId'],
          'patientId': patientId,
          'type': 'Room',
          'amount': amount,
          'paymentMethod': 'Cash',
          'status': 'Paid',
          'referenceId': bed['bedId'],
          'transactionId': null,
          'screenshotBase64': null,
          'refundAmount': null,
          'refundPaid': false,
          'verifiedBy': uid,
          'createdAt': FieldValue.serverTimestamp(),
          'paidAt': FieldValue.serverTimestamp(),
        });
      });
      // ── NOTIFICATION: Room Payment Confirmed → Patient ──
      await NotificationService.send(
        userId: patientId ?? '',
        type: 'Payment',
        referenceId: bed['bedId'],
        message: 'Your room payment of Rs. $amount has been received.',
      );

      if (!mounted) return;
      _showSuccess('Bed released — Rs. $amount collected');
      _load();
    } catch (e) {
      _showError('Could not release bed: $e');
    } finally {
      if (mounted) setState(() => _processingId = null);
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
    final list = _selectedTab == 'Pending' ? _pending : _occupied;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTabToggle(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: _primary))
                  : list.isEmpty
                      ? _buildEmpty()
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: _primary,
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                            itemCount: list.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (ctx, i) => _selectedTab == 'Pending'
                                ? _pendingCard(list[i])
                                : _occupiedCard(list[i]),
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
          const Text('Admissions',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildTabToggle() {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 14, 18, 8),
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
          _tabButton('Pending', _pending.length),
          _tabButton('Occupied', _occupied.length),
        ],
      ),
    );
  }

  Widget _tabButton(String label, int count) {
    final isSelected = _selectedTab == label;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = label),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? _primary : Colors.transparent,
            borderRadius: BorderRadius.circular(26),
          ),
          alignment: Alignment.center,
          child: Text(
            count > 0 ? '$label ($count)' : label,
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
    final isPending = _selectedTab == 'Pending';
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(isPending ? Icons.bed_outlined : Icons.hotel_outlined,
              size: 64, color: _primary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(isPending ? 'No admissions pending' : 'No occupied beds',
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280))),
        ],
      ),
    );
  }

  Widget _pendingCard(Map<String, dynamic> p) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFDE6E0),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.local_hospital_outlined,
                color: Color(0xFFD9534F), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p['patientName'],
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A2F3A))),
                const SizedBox(height: 2),
                Text('Recommended by Dr. ${p['doctorName']}',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final assigned = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => AssignBedScreen(
                    appointmentId: p['appointmentId'],
                    patientId: p['patientId'],
                    patientName: p['patientName'],
                  ),
                ),
              );
              if (assigned == true) _load();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Assign Bed',
                style: TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _occupiedCard(Map<String, dynamic> bed) {
    final isProcessing = _processingId == bed['bedId'];
    final assignedAt = bed['assignedAt'] as DateTime?;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(bed['patientName'],
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A2F3A))),
                    const SizedBox(height: 2),
                    Text(
                        'Room ${bed['roomNumber']} · Bed ${bed['bedNumber']} · ${bed['roomType']}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54)),
                  ],
                ),
              ),
              if (assignedAt != null)
                Text(_durationLabel(assignedAt),
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _primary)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isProcessing ? null : () => _releaseBed(bed),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: isProcessing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : const Text('Release Bed',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
