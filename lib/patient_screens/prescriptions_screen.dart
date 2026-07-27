import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'prescription_detail_screen.dart';

/// SCHEMA COMPLIANCE:
/// - prescriptions where patientId == uid
/// - Sirf woh prescriptions dikhti hain jinki appointment Completed hai
///   (schema rule: "Available after appointment = Completed")
/// - Medicine count prescription_medicines collection se aata hai
class PrescriptionsScreen extends StatefulWidget {
  const PrescriptionsScreen({super.key});

  @override
  State<PrescriptionsScreen> createState() => _PrescriptionsScreenState();
}

class _PrescriptionsScreenState extends State<PrescriptionsScreen> {
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _primaryDark = Color(0xFF0D6B5A);

  bool _isLoading = true;
  List<Map<String, dynamic>> _prescriptions = [];

  @override
  void initState() {
    super.initState();
    _loadPrescriptions();
  }

  Future<void> _loadPrescriptions() async {
    setState(() => _isLoading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        setState(() => _isLoading = false);
        return;
      }

      final prescSnap = await FirebaseFirestore.instance
          .collection('prescriptions')
          .where('patientId', isEqualTo: uid)
          .get();

      final List<Map<String, dynamic>> result = [];

      for (final doc in prescSnap.docs) {
        final data = doc.data();

        // Schema rule: sirf Completed appointment ki prescription visible
        final apptDoc = await FirebaseFirestore.instance
            .collection('appointments')
            .doc(data['appointmentId'])
            .get();
        if (!apptDoc.exists) continue;
        if (apptDoc.data()?['status'] != 'Completed') continue;

        final doctorDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(data['doctorId'])
            .get();

        final profileDoc = await FirebaseFirestore.instance
            .collection('doctor_profiles')
            .doc(data['doctorId'])
            .get();

        final medsSnap = await FirebaseFirestore.instance
            .collection('prescription_medicines')
            .where('prescriptionId', isEqualTo: doc.id)
            .get();

        String dateLabel = '';
        final createdAt = data['createdAt'];
        if (createdAt is Timestamp) {
          dateLabel = DateFormat('d MMM yyyy').format(createdAt.toDate());
        }

        result.add({
          'prescriptionId': doc.id,
          'doctorName': doctorDoc.data()?['name'] ?? 'Doctor',
          'specialization': profileDoc.exists
              ? (profileDoc.data()?['specialization'] ?? '')
              : '',
          'dateLabel': dateLabel,
          'createdAt': createdAt,
          'medicineCount': medsSnap.docs.length,
        });
      }

      // Newest first
      result.sort((a, b) {
        final aTs = a['createdAt'];
        final bTs = b['createdAt'];
        if (aTs is! Timestamp || bTs is! Timestamp) return 0;
        return bTs.compareTo(aTs);
      });

      setState(() {
        _prescriptions = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Error loading prescriptions: $e');
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
                  : _prescriptions.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: _loadPrescriptions,
                          color: _primary,
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                            itemCount: _prescriptions.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (ctx, i) =>
                                _prescriptionCard(_prescriptions[i]),
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
                color: Colors.white.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.arrow_back, color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 14),
          const Text('Prescriptions',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.medication_outlined,
              size: 64, color: _primary.withOpacity(0.3)),
          const SizedBox(height: 16),
          const Text('No prescriptions yet',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280))),
          const SizedBox(height: 8),
          const Text('Prescriptions appear after a completed visit',
              style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
        ],
      ),
    );
  }

  Widget _prescriptionCard(Map<String, dynamic> presc) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PrescriptionDetailScreen(
              prescriptionId: presc['prescriptionId'],
              doctorName: presc['doctorName'],
              specialization: presc['specialization'],
              dateLabel: presc['dateLabel'],
            ),
          ),
        );
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
            Text(presc['doctorName'],
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A2F3A))),
            const SizedBox(height: 2),
            Text(presc['specialization'],
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 2),
            Text(presc['dateLabel'],
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.medication_outlined,
                        size: 14, color: _primary),
                    const SizedBox(width: 6),
                    Text(
                      '${presc['medicineCount']} medicine${presc['medicineCount'] == 1 ? '' : 's'}',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
                const Row(
                  children: [
                    Text('View detail',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _primary)),
                    SizedBox(width: 2),
                    Icon(Icons.chevron_right, size: 16, color: _primary),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
