import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _primaryDark = Color(0xFF0D6B5A);

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
      backgroundColor: const Color(0xFFF4F7F6),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: _primary))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildDoctorCard(),
                          const SizedBox(height: 20),
                          const Text('Medicines',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1A2F3A))),
                          const SizedBox(height: 10),
                          if (_medicines.isEmpty)
                            const Text('No medicines in this prescription.',
                                style: TextStyle(color: Colors.grey))
                          else
                            ..._medicines.map(_medicineCard),
                        ],
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
          const Text('Prescription detail',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
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
          Text(widget.doctorName,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A2F3A))),
          const SizedBox(height: 2),
          Text(widget.specialization,
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.calendar_today_outlined,
                  size: 13, color: Colors.grey),
              const SizedBox(width: 6),
              Text(widget.dateLabel,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(width: 14),
              const Icon(Icons.medication_outlined,
                  size: 13, color: Colors.grey),
              const SizedBox(width: 6),
              Text('${_medicines.length} medicines',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(med['medicineName'] ?? '',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A2F3A))),
              ),
              if (med['duration'] != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCEFE9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(med['duration'],
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _primary)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _detailRow(
              Icons.medication_liquid_outlined, 'Dosage', med['dosage'] ?? '—'),
          const SizedBox(height: 4),
          _detailRow(
              Icons.schedule_outlined, 'Frequency', med['frequency'] ?? '—'),
          if (med['instructions'] != null &&
              med['instructions'].toString().isNotEmpty) ...[
            const SizedBox(height: 4),
            _detailRow(Icons.info_outline, 'Instructions',
                med['instructions'].toString()),
          ],
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 6),
        Text('$label: ',
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Expanded(
          child: Text(value,
              style: const TextStyle(fontSize: 12, color: Colors.black87)),
        ),
      ],
    );
  }
}
