// lib/doctor_screens/prescription.dart

/// A single medicine entry as entered by the doctor in the Add Prescription
/// form, before it is saved. Firestore assigns `prescriptionMedicineId` and
/// `prescriptionId` only once the write actually happens — see
/// DoctorRepository.addPrescription().
class PrescriptionMedicineInput {
  final String medicineName;
  final String dosage;
  final String frequency; // e.g. "Twice daily"
  final String duration; // e.g. "7 days"
  final String instructions; // e.g. "After meals"

  PrescriptionMedicineInput({
    required this.medicineName,
    required this.dosage,
    required this.frequency,
    required this.duration,
    required this.instructions,
  });
}