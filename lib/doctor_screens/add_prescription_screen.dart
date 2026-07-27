// lib/doctor_screens/add_prescription_screen.dart
import 'package:flutter/material.dart';
import 'doctor_repository.dart';
import 'prescription.dart';

class _RxColors {
  static const primary = Color(0xFF1F8A70);
  static const primaryDark = Color(0xFF166049);
  static const background = Color(0xFFF5F7F8);
  static const cardBackground = Colors.white;
  static const textMuted = Color(0xFF8A8A8A);
  static const error = Color(0xFFD64545);
}

class _MedicineFormEntry {
  final nameController = TextEditingController();
  final dosageController = TextEditingController();
  final frequencyController = TextEditingController();
  final durationController = TextEditingController();
  final instructionsController = TextEditingController();

  void dispose() {
    nameController.dispose();
    dosageController.dispose();
    frequencyController.dispose();
    durationController.dispose();
    instructionsController.dispose();
  }
}

class AddPrescriptionScreen extends StatefulWidget {
  final DoctorRepository repository;
  final String appointmentId;
  final String doctorId;
  final String patientId;
  final String patientName;

  const AddPrescriptionScreen({
    super.key,
    required this.repository,
    required this.appointmentId,
    required this.doctorId,
    required this.patientId,
    required this.patientName,
  });

  @override
  State<AddPrescriptionScreen> createState() => _AddPrescriptionScreenState();
}

class _AddPrescriptionScreenState extends State<AddPrescriptionScreen> {
  final _formKey = GlobalKey<FormState>();
  final List<_MedicineFormEntry> _medicines = [_MedicineFormEntry()];
  bool _isSaving = false;

  @override
  void dispose() {
    for (final m in _medicines) {
      m.dispose();
    }
    super.dispose();
  }

  void _addMedicineRow() {
    setState(() => _medicines.add(_MedicineFormEntry()));
  }

  void _removeMedicineRow(int index) {
    if (_medicines.length == 1) return; // keep at least one row
    setState(() {
      _medicines[index].dispose();
      _medicines.removeAt(index);
    });
  }

  Future<void> _savePrescription() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final medicines = _medicines
          .map((m) => PrescriptionMedicineInput(
                medicineName: m.nameController.text.trim(),
                dosage: m.dosageController.text.trim(),
                frequency: m.frequencyController.text.trim(),
                duration: m.durationController.text.trim(),
                instructions: m.instructionsController.text.trim(),
              ))
          .toList();

      await widget.repository.addPrescription(
        appointmentId: widget.appointmentId,
        doctorId: widget.doctorId,
        patientId: widget.patientId,
        medicines: medicines,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Prescription saved'),
            backgroundColor: _RxColors.primary,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save prescription: $e'),
            backgroundColor: _RxColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _RxColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Patient: ${widget.patientName}',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 16),
                    for (int i = 0; i < _medicines.length; i++) ...[
                      _buildMedicineCard(i),
                      const SizedBox(height: 12),
                    ],
                    OutlinedButton.icon(
                      onPressed: _addMedicineRow,
                      icon: const Icon(Icons.add, color: _RxColors.primary),
                      label: const Text('Add another medicine',
                          style: TextStyle(color: _RxColors.primary)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _RxColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _savePrescription,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _RxColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Text(
                                'Save Prescription',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600),
                              ),
                      ),
                    ),
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
      padding: const EdgeInsets.fromLTRB(12, 16, 20, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_RxColors.primary, _RxColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          const Text(
            'Add Prescription',
            style: TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildMedicineCard(int index) {
    final entry = _medicines[index];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _RxColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Medicine ${index + 1}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13)),
              if (_medicines.length > 1)
                IconButton(
                  onPressed: () => _removeMedicineRow(index),
                  icon: const Icon(Icons.close, size: 18, color: _RxColors.error),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _field(
            controller: entry.nameController,
            label: 'Medicine name',
            validator: (v) => v!.trim().isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _field(
                  controller: entry.dosageController,
                  label: 'Dosage (e.g. 500mg)',
                  validator: (v) => v!.trim().isEmpty ? 'Required' : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _field(
                  controller: entry.frequencyController,
                  label: 'Frequency (e.g. Twice daily)',
                  validator: (v) => v!.trim().isEmpty ? 'Required' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _field(
                  controller: entry.durationController,
                  label: 'Duration (e.g. 7 days)',
                  validator: (v) => v!.trim().isEmpty ? 'Required' : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _field(
                  controller: entry.instructionsController,
                  label: 'Instructions (optional)',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 12, color: _RxColors.textMuted),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _RxColors.primary, width: 1.5),
        ),
      ),
    );
  }
}