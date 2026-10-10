// lib/doctor_screens/add_prescription_screen.dart
import 'package:flutter/material.dart';
import '../widgets/app_ui.dart';
import 'doctor_repository.dart';
import 'prescription.dart';

class _RxColors {
  static const primary = Color(0xFF0E6E68);
  static const error = Color(0xFFB23A1E);
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
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                children: [
                  Text(
                    'Patient: ${widget.patientName}',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text),
                  ),
                  const SizedBox(height: 12),
                  for (int i = 0; i < _medicines.length; i++) ...[
                    _buildMedicineCard(i),
                    const SizedBox(height: 12),
                  ],
                  OutlinedButton.icon(
                    onPressed: _addMedicineRow,
                    icon: const Icon(Icons.add_rounded, color: AppColors.teal),
                    label: const Text('Add another medicine',
                        style: TextStyle(
                            color: AppColors.teal,
                            fontSize: 14,
                            fontWeight: FontWeight.w800)),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF9FB5B3)),
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
                20, 12, 20, 16 + MediaQuery.of(context).padding.bottom),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppColors.divider)),
            ),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _savePrescription,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.header,
                  disabledBackgroundColor: AppColors.header.withOpacity(0.5),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
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
                            fontSize: 15,
                            fontWeight: FontWeight.w800),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return AppHeader(
      title: 'Add Prescription',
      subtitle: widget.patientName,
    );
  }

  Widget _buildMedicineCard(int index) {
    final entry = _medicines[index];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppIconTile(
                icon: Icons.medication_outlined,
                color: AppColors.blue,
                background: AppColors.blueSoft,
                size: 28,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Medicine ${index + 1}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: AppColors.text)),
              ),
              if (_medicines.length > 1)
                AppDeleteButton(
                  onTap: () => _removeMedicineRow(index),
                  size: 32,
                  tooltip: 'Remove',
                ),
            ],
          ),
          const SizedBox(height: 12),
          _field(
            controller: entry.nameController,
            label: 'Medicine name',
            validator: (v) => v!.trim().isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _field(
                  controller: entry.dosageController,
                  label: 'Dosage (e.g. 500mg)',
                  validator: (v) => v!.trim().isEmpty ? 'Required' : null,
                ),
              ),
              const SizedBox(width: 8),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _field(
                  controller: entry.durationController,
                  label: 'Duration (e.g. 7 days)',
                  validator: (v) => v!.trim().isEmpty ? 'Required' : null,
                ),
              ),
              const SizedBox(width: 8),
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
      style: const TextStyle(fontSize: 13, color: AppColors.text),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 12, color: AppColors.faint),
        isDense: true,
        filled: true,
        fillColor: AppColors.bg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.teal, width: 1.5),
        ),
      ),
    );
  }
}
