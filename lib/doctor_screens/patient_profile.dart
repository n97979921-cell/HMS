// lib/doctor_screens/patient_profile.dart

/// Read-only view-model for a patient, as seen by a doctor.
/// Combines `users` (basic info) + `patient_profiles` (medical info).
/// The doctor can only VIEW this — editing belongs to the patient/admin.
class PatientProfile {
  final String patientId;
  final String name;
  final String email;
  final String phone;
  final String cnic;
  final int? age;
  final String? gender;
  final String? bloodGroup;
  final String? allergies;
  final String? chronicConditions;
  final String patientType; // REGISTERED | WALK_IN

  PatientProfile({
    required this.patientId,
    required this.name,
    required this.email,
    required this.phone,
    required this.cnic,
    required this.age,
    required this.gender,
    required this.bloodGroup,
    required this.allergies,
    required this.chronicConditions,
    required this.patientType,
  });
}