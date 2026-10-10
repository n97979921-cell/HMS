import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_ui.dart';

/// SCHEMA COMPLIANCE:
/// - prescription_medicines where prescriptionId == given ID
/// - Fields: medicineName, dosage, frequency, duration, instructions
/// - Read-only (prescription unmodifiable after creation — schema rule)
class PrescriptionDetailScreen extends StatefulWidget {
  final String prescriptionId;
  final String doctorName;
  final String specialization;
  final String dateLabel;

  const PrescriptionDetailScreen({
    super.key,
    required this.prescriptionId,
    required this.doctorName,
    required this.specialization,
    required this.dateLabel,
  });

  @override
  State<PrescriptionDetailScreen> createState() =>
      _PrescriptionDetailScreenState();
}

class _PrescriptionDetailScreenState extends State<PrescriptionDetailScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _medicines = [];

  @override
  void initState() {
    super.initState();
    _loadMedicines();
  }

  Future<void> _loadMedicines() async {
    setState(() => _isLoading = true);
    try {
      final medsSnap = await FirebaseFirestore.instance
          .collection('prescription_medicines')
          .where('prescriptionId', isEqualTo: widget.prescriptionId)
          .get();

      setState(() {
        _medicines = medsSnap.docs.map((d) => d.data()).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
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
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDoctorCard(),
                        const SizedBox(height: 20),
                        const Text('MEDICINES',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                                color: AppColors.muted)),
                        const SizedBox(height: 10),
                        if (_medicines.isEmpty)
                          const AppEmptyState(
                            icon: Icons.medication_outlined,
                            title: 'No medicines in this prescription.',
                          )
                        else
                          ..._medicines.map(_medicineCard),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return AppHeader(
      title: 'Prescription detail',
      subtitle: widget.dateLabel,
    );
  }

  Widget _pill(IconData icon, String text, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 5),
          Text(text,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w800, color: fg)),
        ],
      ),
    );
  }

  Widget _buildDoctorCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.doctorName,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text)),
          const SizedBox(height: 2),
          Text(widget.specialization,
              style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _pill(Icons.calendar_today_outlined, widget.dateLabel,
                  AppColors.muted, AppColors.bg),
              _pill(Icons.medication_outlined, '${_medicines.length} medicines',
                  AppColors.blue, AppColors.blueSoft),
            ],
          ),
        ],
      ),
    );
  }

  Widget _medicineCard(Map<String, dynamic> med) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(med['medicineName'] ?? '',
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _box('Dosage', '${med['dosage'] ?? '—'}')),
              const SizedBox(width: 8),
              Expanded(child: _box('Frequency', '${med['frequency'] ?? '—'}')),
            ],
          ),
          if (med['duration'] != null &&
              med['duration'].toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            _detailRow('Duration', med['duration'].toString()),
          ],
          if (med['instructions'] != null &&
              med['instructions'].toString().isNotEmpty) ...[
            const SizedBox(height: 6),
            _detailRow('Instructions', med['instructions'].toString()),
          ],
        ],
      ),
    );
  }

  Widget _box(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.faint)),
          const SizedBox(height: 1),
          Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text)),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
        children: [
          TextSpan(
              text: '$label: ',
              style: const TextStyle(
                  fontWeight: FontWeight.w800, color: AppColors.text)),
          TextSpan(text: value),
        ],
      ),
    );
  }
}
