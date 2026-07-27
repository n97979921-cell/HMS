// lib/doctor_screens/lab_test_detail.dart
import 'lab_test_status.dart';

/// View-model for the Report Detail screen.
/// Combines lab_tests + users(patientName, doctorName).
class LabTestDetail {
  final String testId;
  final String patientName;
  final String doctorName;
  final DateTime? reportDate;
  final String testType;
  final LabTestStatus status;
  final String? reportUrl;

  LabTestDetail({
    required this.testId,
    required this.patientName,
    required this.doctorName,
    required this.reportDate,
    required this.testType,
    required this.status,
    required this.reportUrl,
  });
}