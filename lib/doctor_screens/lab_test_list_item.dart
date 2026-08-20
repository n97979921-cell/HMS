// lib/doctor_screens/lab_test_list_item.dart
import 'lab_test_status.dart';

/// View-model for the Lab Reports list screen.
/// Combines lab_tests + users(patientName).
class LabTestListItem {
  final String testId;
  final String patientName;
  final String testType;
  final LabTestStatus status;
  final String? cancelReason;

  LabTestListItem({
    required this.testId,
    required this.patientName,
    required this.testType,
    required this.status,
    this.cancelReason,
  });
}
