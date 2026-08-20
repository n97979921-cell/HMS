import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// OCCUPIED BEDS + RELEASE (Receptionist)
///
/// Saare Occupied beds dikhata hai. Release dabane par:
///   totalHours = round((now - assignedAt) / 60min), min 1 hour
///   amount = totalHours * pricePerHour
/// "Cash received?" confirm ke baad TRANSACTION (atomic):
///   beds: availability→Available, releasedAt→now, appointmentId→null
///   payments: naya record (type:Room, Cash, Paid, referenceId:bedId)
/// Payment fail ho to bed Occupied hi rehta hai — "no release without
/// payment" (schema Issue-3 pattern se match).
class OccupiedBedsScreen extends StatefulWidget {
  const OccupiedBedsScreen({super.key});

  @override
  State<OccupiedBedsScreen> createState() => _OccupiedBedsScreenState();
}

class _OccupiedBedsScreenState extends State<OccupiedBedsScreen> {
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _primaryDark = Color(0xFF0D6B5A);

  bool _isLoading = true;
  String? _processingBedId;
  List<Map<String, dynamic>> _occupied = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
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

      setState(() {
        _occupied = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Error loading occupied beds: $e');
    }
  }

  // Round-to-nearest hour billing, minimum 1 hour
  int _calculateHours(DateTime assignedAt) {
    final totalMinutes = DateTime.now().difference(assignedAt).inMinutes;
    int hours = (totalMinutes / 60).round();
    if (hours <= 0) hours = 1; // minimum 1 hour charge
    return hours;
  }

  String _durationLabel(DateTime assignedAt) {
    final d = DateTime.now().difference(assignedAt);
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return '${h}h ${m}m';
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
            Text('Room ${bed['roomNumber']} (${bed['roomType']})'),
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

    setState(() => _processingBedId = bed['bedId']);
    try {
      final bedRef =
          FirebaseFirestore.instance.collection('beds').doc(bed['bedId']);
      final paymentRef =
          FirebaseFirestore.instance.collection('payments').doc();
      final uid = FirebaseAuth.instance.currentUser?.uid;

      // Patient ID chahiye payment record ke liye
      String? patientId;
      if (bed['appointmentId'] != null) {
        final apptDoc = await FirebaseFirestore.instance
            .collection('appointments')
            .doc(bed['appointmentId'])
            .get();
        patientId = apptDoc.data()?['patientId'];
      }

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        // READ pehle — bed abhi bhi Occupied hai? (double-release se bachao)
        final bedSnap = await transaction.get(bedRef);
        if (!bedSnap.exists) throw Exception('Bed not found');
        if (bedSnap.data()?['availability'] != 'Occupied') {
          throw Exception('This bed is no longer occupied.');
        }

        // WRITES — atomic: bed free + payment record, dono ya koi nahi
        transaction.update(bedRef, {
          'availability': 'Available',
          'releasedAt': FieldValue.serverTimestamp(),
          'appointmentId': null,
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

      if (!mounted) return;
      _showSuccess('Bed released — Rs. $amount collected');
      _load();
    } catch (e) {
      _showError('Could not release bed: $e');
    } finally {
      if (mounted) setState(() => _processingBedId = null);
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
                  : _occupied.isEmpty
                      ? _buildEmpty()
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: _primary,
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                            itemCount: _occupied.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (ctx, i) => _card(_occupied[i]),
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
          const Text('Occupied Beds',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.hotel_outlined,
              size: 64, color: _primary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          const Text('No occupied beds',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280))),
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> bed) {
    final isProcessing = _processingBedId == bed['bedId'];
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
                    Text('Room ${bed['roomNumber']} · ${bed['roomType']}',
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
