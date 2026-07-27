// lib/doctor_screens/doctor_repository.dart
import 'doctor_appointment_list_item.dart';
import 'lab_test_list_item.dart';
import 'lab_test_detail.dart';
import 'doctor_profile.dart';
import 'prescription.dart';
import 'patient_profile.dart';
import 'test_type_price.dart';

abstract class DoctorRepository {
  Future<List<DoctorAppointmentListItem>> getAppointmentsForDate({
    required String doctorId,
    required DateTime date,
    required List<String> statuses,
  });

  Future<String> getDoctorName(String doctorId);

  Future<List<LabTestListItem>> getLabTestsForDoctor({
    required String doctorId,
    String? statusFilter,
  });

  Future<LabTestDetail> getLabTestDetail(String testId);

  Future<DoctorProfile> getDoctorProfile(String doctorId);

  /// Only name and phone are editable by the doctor — see schema note:
  /// specialization/license/department/timing are admin-controlled.
  Future<void> updateDoctorProfile({
    required String doctorId,
    required String name,
    required String phone,
  });

  /// Updates the status of a single appointment (e.g. marking it
  /// 'Completed' once a consultation finishes).
  Future<void> updateAppointmentStatus({
    required String appointmentId,
    required String status,
  });

  /// Transitions a VIDEO_CALL appointment from Confirmed → InProgress and
  /// records `consultationStartedAt`, per the schema's video call rule:
  /// "Doctor [Start Consultation] press kare → status: Confirmed → InProgress".
  Future<void> startVideoConsultation({required String appointmentId});

  /// Saves a new prescription (with its medicines) for a completed
  /// appointment. Writes to both the `prescriptions` and
  /// `prescription_medicines` collections in a single atomic batch.
  Future<void> addPrescription({
    required String appointmentId,
    required String doctorId,
    required String patientId,
    required List<PrescriptionMedicineInput> medicines,
  });

  /// Doctor.viewPatientProfile() — read-only combined view of a patient's
  /// basic info (users) and medical info (patient_profiles).
  Future<PatientProfile> getPatientProfile(String patientId);

  /// Returns all admin-configured lab test types and their charges, used
  /// to populate the Request Lab Test dropdown.
  Future<List<TestTypePrice>> getTestTypePrices();

  /// Doctor.requestLabTest() — creates a new `lab_tests` document.
  /// Per schema: lab tests only apply to IN_PERSON/WALK_IN appointments,
  /// not VIDEO_CALL — enforced in the UI, not here.
  Future<void> requestLabTest({
    required String appointmentId,
    required String doctorId,
    required String patientId,
    required String testType,
    required num charge,
  });

  /// Doctor.recommendAdmission() — sets/clears
  /// `appointments.admissionRecommended`.
  Future<void> recommendAdmission({
    required String appointmentId,
    required bool recommended,
  });

  Future<void> logout();
}