// lib/doctor_screens/dummy_doctor_repository.dart
// Kept only for offline UI testing — not used in production navigation.
import 'appointment_status.dart';
import 'doctor_appointment_list_item.dart';
import 'doctor_repository.dart';
import 'lab_test_status.dart';
import 'lab_test_list_item.dart';
import 'lab_test_detail.dart';
import 'doctor_profile.dart';
import 'prescription.dart';
import 'patient_profile.dart';
import 'test_type_price.dart';

class DummyDoctorRepository implements DoctorRepository {
  @override
  Future<String> getDoctorName(String doctorId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return 'Dr. Ahmed';
  }

  @override
  Future<List<DoctorAppointmentListItem>> getAppointmentsForDate({
    required String doctorId,
    required DateTime date,
    required List<String> statuses,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final all = [
      DoctorAppointmentListItem(
        appointmentId: 'apt1',
        patientId: 'p1',
        patientName: 'Ali Khan',
        slotTime: '10:00 AM',
        status: AppointmentStatus.confirmed,
        appointmentType: AppointmentType.videoCall,
      ),
    ];
    return all.where((a) => statuses.contains(a.status.name)).toList();
  }

  @override
  Future<List<LabTestListItem>> getLabTestsForDoctor({
    required String doctorId,
    String? statusFilter,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final all = [
      LabTestListItem(testId: 't1', patientName: 'Ali Khan', testType: 'CBC (Complete Blood Count)', status: LabTestStatus.pending),
    ];
    if (statusFilter == null) return all;
    return all.where((t) => t.status.name.toLowerCase() == statusFilter.toLowerCase()).toList();
  }

  @override
  Future<LabTestDetail> getLabTestDetail(String testId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return LabTestDetail(
      testId: testId,
      patientName: 'Ahmed Raza',
      doctorName: 'Dr. Ahmed',
      reportDate: DateTime(2026, 7, 20),
      testType: 'X-Ray Chest',
      status: LabTestStatus.completed,
      reportUrl: 'https://example.com/XRay_Chest.pdf',
    );
  }

  @override
  Future<DoctorProfile> getDoctorProfile(String doctorId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return DoctorProfile(
      doctorId: doctorId,
      name: 'Dr. Ahmed',
      email: 'ahmed@example.com',
      phone: '0300-1234567',
      cnic: '35202-1234567-1',
      specialization: 'Cardiologist',
      license: 'PMC-12345',
      departmentName: 'Cardiology',
      appointmentStartTime: '09:00',
      appointmentEndTime: '17:00',
    );
  }

  @override
  Future<void> updateDoctorProfile({
    required String doctorId,
    required String name,
    required String phone,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
  }

  @override
  Future<void> updateAppointmentStatus({
    required String appointmentId,
    required String status,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
  }

  @override
  Future<void> startVideoConsultation({required String appointmentId}) async {
    await Future.delayed(const Duration(milliseconds: 200));
  }

  @override
  Future<void> addPrescription({
    required String appointmentId,
    required String doctorId,
    required String patientId,
    required List<PrescriptionMedicineInput> medicines,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
  }

  @override
  Future<PatientProfile> getPatientProfile(String patientId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return PatientProfile(
      patientId: patientId,
      name: 'Ali Khan',
      email: 'ali.khan@example.com',
      phone: '0300-1234567',
      cnic: '35202-1234567-2',
      age: 34,
      gender: 'Male',
      bloodGroup: 'O+',
      allergies: 'Penicillin',
      chronicConditions: null,
      patientType: 'REGISTERED',
    );
  }

  @override
  Future<List<TestTypePrice>> getTestTypePrices() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return [
      TestTypePrice(testType: 'CBC (Complete Blood Count)', charge: 800),
      TestTypePrice(testType: 'X-Ray Chest', charge: 1500),
      TestTypePrice(testType: 'Blood Sugar', charge: 500),
    ];
  }

  @override
  Future<void> requestLabTest({
    required String appointmentId,
    required String doctorId,
    required String patientId,
    required String testType,
    required num charge,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
  }

  @override
  Future<void> recommendAdmission({
    required String appointmentId,
    required bool recommended,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
  }

  @override
  Future<void> logout() async {
    await Future.delayed(const Duration(milliseconds: 100));
  }
}