import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'prescription_detail_screen.dart';
import '../widgets/app_ui.dart';

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

  // Deletes the prescription doc plus its medicines — same
  // "no confirmation, permanent batch delete" pattern used on
  // Refunds / Lab Staff Completed / Billing Paid bills.
  Future<void> _deletePrescription(String prescriptionId) async {
    try {
      final batch = FirebaseFirestore.instance.batch();

      final medsSnap = await FirebaseFirestore.instance
          .collection('prescription_medicines')
          .where('prescriptionId', isEqualTo: prescriptionId)
          .get();
      for (final med in medsSnap.docs) {
        batch.delete(med.reference);
      }

      batch.delete(FirebaseFirestore.instance
          .collection('prescriptions')
          .doc(prescriptionId));

      await batch.commit();

      setState(() {
        _prescriptions
            .removeWhere((p) => p['prescriptionId'] == prescriptionId);
      });
    } catch (e) {
      _showError('Error deleting prescription: $e');
    }
  }

  Future<void> _deleteAllPrescriptions() async {
    if (_prescriptions.isEmpty) return;
    try {
      final batch = FirebaseFirestore.instance.batch();

      for (final presc in _prescriptions) {
        final prescriptionId = presc['prescriptionId'] as String;

        final medsSnap = await FirebaseFirestore.instance
            .collection('prescription_medicines')
            .where('prescriptionId', isEqualTo: prescriptionId)
            .get();
        for (final med in medsSnap.docs) {
          batch.delete(med.reference);
        }

        batch.delete(FirebaseFirestore.instance
            .collection('prescriptions')
            .doc(prescriptionId));
      }

      await batch.commit();

      setState(() => _prescriptions.clear());
    } catch (e) {
      _showError('Error deleting prescriptions: $e');
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
                : _prescriptions.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadPrescriptions,
                        color: AppColors.teal,
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                          itemCount: _prescriptions.length + 1,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (ctx, i) {
                            if (i == 0) return _buildDeleteAllBar();
                            return _prescriptionCard(_prescriptions[i - 1]);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return const AppHeader(
      title: 'Prescriptions',
      subtitle: 'From completed visits',
    );
  }

  // "X prescriptions" count + Delete All (same action as before)
  Widget _buildDeleteAllBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          '${_prescriptions.length} prescription${_prescriptions.length == 1 ? '' : 's'}',
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.muted),
        ),
        GestureDetector(
          onTap: _deleteAllPrescriptions,
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
    );
  }

  Widget _buildEmptyState() {
    return const SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: AppEmptyState(
        icon: Icons.medication_outlined,
        title: 'No prescriptions yet',
        subtitle: 'Prescriptions appear after a completed visit',
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
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppIconTile(
                  icon: Icons.medication_outlined,
                  color: AppColors.blue,
                  background: AppColors.blueSoft,
                  size: 44,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(presc['doctorName'],
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.text)),
                      const SizedBox(height: 2),
                      Text(presc['specialization'],
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.muted)),
                      const SizedBox(height: 2),
                      Text(presc['dateLabel'],
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.faint)),
                    ],
                  ),
                ),
                AppDeleteButton(
                  onTap: () => _deletePrescription(presc['prescriptionId']),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.medication_outlined,
                      size: 15, color: AppColors.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${presc['medicineCount']} medicine${presc['medicineCount'] == 1 ? '' : 's'}',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.muted),
                    ),
                  ),
                  const Text('View detail',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.teal)),
                  const SizedBox(width: 2),
                  const Icon(Icons.chevron_right_rounded,
                      size: 18, color: AppColors.teal),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
