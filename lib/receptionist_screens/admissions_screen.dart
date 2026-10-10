import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'assign_bed_screen.dart';
import '../services/notification_service.dart';
import '../widgets/app_ui.dart';

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
  static const Color _primary = Color(0xFF0B2E33);

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
        'bedNumber': bed['bedNumber'] ?? '',
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
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
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
            style: TextButton.styleFrom(foregroundColor: AppColors.muted),
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

  Future<void> _cancelRecommendation(Map<String, dynamic> p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Cancel recommendation'),
        content: Text(
            'Remove "${p['patientName']}" from pending admissions? No bed has been assigned yet.'),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.muted),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF9A2E16)),
            child: const Text('Yes, cancel',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _processingId = p['appointmentId']);
    try {
      await FirebaseFirestore.instance
          .collection('appointments')
          .doc(p['appointmentId'])
          .update({'admissionRecommended': false});

      if (!mounted) return;
      _showSuccess('Recommendation cancelled');
      _load();
    } catch (e) {
      _showError('Could not cancel: $e');
    } finally {
      if (mounted) setState(() => _processingId = null);
    }
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

  @override
  Widget build(BuildContext context) {
    final list = _selectedTab == 'Pending' ? _pending : _occupied;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.teal))
                : list.isEmpty
                    ? _buildEmpty()
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: AppColors.teal,
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
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
    );
  }

  Widget _buildHeader() {
    return AppHeader(
      title: 'Admissions',
      subtitle: 'Assign and release beds',
      bottom: _buildTabToggle(),
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 40,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.mint : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            count > 0 ? '$label ($count)' : label,
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
    final isPending = _selectedTab == 'Pending';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: AppEmptyState(
        icon: isPending ? Icons.bed_outlined : Icons.hotel_outlined,
        title: isPending ? 'No admissions pending' : 'No occupied beds',
      ),
    );
  }

  Widget _pendingCard(Map<String, dynamic> p) {
    final isProcessing = _processingId == p['appointmentId'];
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppIconTile(
                icon: Icons.bed_outlined,
                color: Color(0xFF9A2E16),
                background: Color(0xFFFBE6E0),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p['patientName'],
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.text)),
                    const SizedBox(height: 3),
                    Text('Recommended by Dr. ${p['doctorName']}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      isProcessing ? null : () => _cancelRecommendation(p),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(42),
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFFF0C9BE)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Cancel',
                      style: TextStyle(
                          color: Color(0xFF9A2E16),
                          fontSize: 13,
                          fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: isProcessing
                      ? null
                      : () async {
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
                    backgroundColor: AppColors.header,
                    disabledBackgroundColor: AppColors.header.withOpacity(0.5),
                    elevation: 0,
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: isProcessing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text('Assign Bed',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _occupiedCard(Map<String, dynamic> bed) {
    final isProcessing = _processingId == bed['bedId'];
    final assignedAt = bed['assignedAt'] as DateTime?;

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppIconTile(
                icon: Icons.bed_outlined,
                color: Color(0xFF5B3FA8),
                background: Color(0xFFEEE8FB),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(bed['patientName'],
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.text)),
                    const SizedBox(height: 3),
                    Text(
                        'Room ${bed['roomNumber']} · Bed ${bed['bedNumber']} · ${bed['roomType']}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
              if (assignedAt != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDDF3EE),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.schedule_rounded,
                          size: 13, color: Color(0xFF0B5E57)),
                      const SizedBox(width: 4),
                      Text(_durationLabel(assignedAt),
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0B5E57))),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isProcessing ? null : () => _releaseBed(bed),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.header,
                disabledBackgroundColor: AppColors.header.withOpacity(0.5),
                elevation: 0,
                minimumSize: const Size.fromHeight(44),
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
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}
