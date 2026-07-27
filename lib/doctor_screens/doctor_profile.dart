// lib/doctor_screens/doctor_profile.dart
/// View-model for the doctor Profile screen.
/// Combines users + doctor_profiles + departments + doctor_settings.
class DoctorProfile {
  final String doctorId;
  final String name;
  final String email;
  final String phone;
  final String cnic;
  final String specialization;
  final String license;
  final String departmentName;
  final String? appointmentStartTime; // null = admin hasn't set timing yet
  final String? appointmentEndTime;

  DoctorProfile({
    required this.doctorId,
    required this.name,
    required this.email,
    required this.phone,
    required this.cnic,
    required this.specialization,
    required this.license,
    required this.departmentName,
    required this.appointmentStartTime,
    required this.appointmentEndTime,
  });
}