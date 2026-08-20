// lib/models/doctor_appointment_list_item.dart
import 'appointment_status.dart';

/// View-model for the doctor Home screen list.
/// Built by combining appointments + slots + users(patientName) —
/// none of these fields exist together on a single Firestore document.
class DoctorAppointmentListItem {
  final String appointmentId;
  final String patientId;
  final String patientName;
  final String slotTime;
  final AppointmentStatus status;
  final AppointmentType appointmentType;
  final bool admissionRecommended;
  final String? symptoms;
  final String? patientReportBase64;

  DoctorAppointmentListItem({
    required this.appointmentId,
    required this.patientId,
    required this.patientName,
    required this.slotTime,
    required this.status,
    required this.appointmentType,
    this.admissionRecommended = false,
    this.symptoms,
    this.patientReportBase64,
  });
}
